// claude_mem_model.sv — Behavioral memory that is a target on the Claude memory bus (mem_*).
//
// Testbench only (not synthesizable). Specified in .agents/IP_SPEC_mem_bus_initiator.md
// (verification plan, "claude_mem_model"); the bus rules are in .agents/IP_SPEC_mem_bus.md.
// Used by the master-adapter loopback and system tests, and by any bench that needs a
// simple SRAM behind a mem_* port. Runs on Icarus 12, xsim, VCS and Xcelium.
//
// Behaviour:
//   - Storage: SIZE bytes from byte address BASE (SIZE a multiple of DATA_W/8). Word index
//     = (addr - BASE) / (DATA_W/8). Contents start at INIT (default 0).
//   - Writes merge byte lanes by mem_be. Reads return the whole word.
//   - Errors: an access outside [BASE, BASE + SIZE) answers mem_err = 1 when OOR_ERR = 1
//     (default); otherwise the address wraps inside the storage. In addition, any access in
//     [err_lo, err_hi] (run-time variables, empty by default) answers mem_err = 1. A failed
//     write is dropped; failed read data is 0.
//   - Timing (run-time variables, settable from the bench at any time):
//       min_gnt_delay / max_gnt_delay  cycles a request waits for mem_gnt: a random value in
//                                      [min, max] per request (0 / 0 = grant in the request
//                                      cycle)
//       min_rsp_delay / max_rsp_delay  extra cycles after the cycle following the grant:
//                                      random in [min, max] (0 / 0 = response in the next
//                                      cycle)
//   - mem_rdata / mem_err are X outside the response cycle, so an initiator that samples
//     them at the wrong time sees X.
//   - Checks on the initiator (counted in proto_errors and printed):
//       rule 1  request held, payload stable until granted
//       rule 2  no request while one is outstanding, nor in the response cycle
//       rule 9  mem_be not all zeros
//     and, when CHECK_INIT_RULES = 1 (for initiators that follow the initiator spec, not for
//     the slave adapters, which pass bus addresses through), rules 6 and 7 (address = lowest
//     enabled lane; reads naturally aligned).
//   - Backdoor: peek(addr) / poke(addr, data, be) functions, fill(value), and counters n_req,
//     n_wr, n_rd, n_err, n_gnt_stall, n_rsp_stall.

`timescale 1ns / 1ps

module claude_mem_model #(
  parameter int unsigned        DATA_W           = 32,
  parameter int unsigned        ADDR_W           = 32,
  parameter logic [63:0]        BASE             = 64'h0,
  parameter int unsigned        SIZE             = 4096,   // bytes
  parameter bit                 OOR_ERR          = 1'b1,   // out-of-range access is an error
  parameter bit                 CHECK_INIT_RULES = 1'b0,   // also check initiator rules 6, 7
  parameter logic [DATA_W-1:0]  INIT             = '0,
  parameter int unsigned        SEED             = 1
) (
  input  logic                  clk,
  input  logic                  rst_n,        // active-low, synchronous
  input  logic                  mem_req,
  output logic                  mem_gnt,
  input  logic                  mem_we,
  input  logic [ADDR_W-1:0]     mem_addr,
  input  logic [DATA_W/8-1:0]   mem_be,
  input  logic [DATA_W-1:0]     mem_wdata,
  output logic                  mem_rvalid,
  output logic [DATA_W-1:0]     mem_rdata,
  output logic                  mem_err
);

  localparam int unsigned StrbW = DATA_W / 8;
  localparam int unsigned OffW  = (StrbW > 1) ? $clog2(StrbW) : 0;
  localparam int unsigned Words = SIZE / StrbW;

  logic [DATA_W-1:0] mem [Words];

  // Run-time knobs
  int unsigned       min_gnt_delay = 0;
  int unsigned       max_gnt_delay = 0;
  int unsigned       min_rsp_delay = 0;
  int unsigned       max_rsp_delay = 0;
  logic [ADDR_W-1:0] err_lo = '1;      // empty range by default (lo > hi)
  logic [ADDR_W-1:0] err_hi = '0;

  // Counters
  int unsigned n_req        = 0;
  int unsigned n_wr         = 0;
  int unsigned n_rd         = 0;
  int unsigned n_err        = 0;
  int unsigned n_gnt_stall  = 0;
  int unsigned n_rsp_stall  = 0;
  int unsigned proto_errors = 0;

  // Own xorshift32 generator: seeded by SEED, identical on every simulator
  // ($urandom seeding differs between Icarus, xsim, VCS and Xcelium).
  logic [31:0] rng_q = (SEED == 0) ? 32'h1 : 32'(SEED);
  logic        outstanding;
  int unsigned rsp_wait;
  logic [DATA_W-1:0] rsp_data;
  logic        rsp_err;

  logic              prev_wait;
  logic              prev_we;
  logic [ADDR_W-1:0] prev_addr;
  logic [StrbW-1:0]  prev_be;
  logic [DATA_W-1:0] prev_wdata;

  initial begin
    for (int i = 0; i < Words; i++) mem[i] = INIT;
  end

  function automatic logic [31:0] rng_next();
    logic [31:0] x;
    x = rng_q;
    x = x ^ (x << 13);
    x = x ^ (x >> 17);
    x = x ^ (x << 5);
    rng_q = x;
    return x;
  endfunction

  function automatic int unsigned pick(int unsigned lo, int unsigned hi);
    if (hi <= lo) return lo;
    return lo + (rng_next() % (hi - lo + 1));
  endfunction

  function automatic logic in_range(logic [ADDR_W-1:0] a);
    logic [63:0] a64;
    a64 = 64'(a);
    return (a64 >= BASE) && (a64 < BASE + 64'(SIZE));
  endfunction

  function automatic int unsigned index(logic [ADDR_W-1:0] a);
    logic [63:0] off;
    off = (64'(a) - BASE);
    return int'((off >> OffW) % Words);
  endfunction

  // --- backdoor --------------------------------------------------------------
  function automatic logic [DATA_W-1:0] peek(logic [ADDR_W-1:0] a);
    return mem[index(a)];
  endfunction

  task automatic poke(logic [ADDR_W-1:0] a, logic [DATA_W-1:0] d, logic [StrbW-1:0] be);
    for (int b = 0; b < StrbW; b++) if (be[b]) mem[index(a)][8*b +: 8] = d[8*b +: 8];
  endtask

  task automatic fill(logic [DATA_W-1:0] d);
    for (int i = 0; i < Words; i++) mem[i] = d;
  endtask

  // --- initiator rule checks ---------------------------------------------------
  function automatic logic lanes_ok(logic we, logic [ADDR_W-1:0] a, logic [StrbW-1:0] be);
    int unsigned lo, n;
    logic        contiguous, seen_gap;
    lo = StrbW; n = 0; contiguous = 1'b1; seen_gap = 1'b0;
    for (int b = 0; b < StrbW; b++) begin
      if (be[b]) begin
        if (lo == StrbW) lo = b;
        if (seen_gap) contiguous = 1'b0;
        n++;
      end else if (lo != StrbW) begin
        seen_gap = 1'b1;
      end
    end
    if (n == 0) return 1'b1;                               // reported by rule 9
    if (int'(64'(a) % StrbW) != lo) return 1'b0;           // rule 6
    if (!we) begin                                         // rule 7: aligned power of two
      if (!contiguous) return 1'b0;
      if ((n & (n - 1)) != 0) return 1'b0;
      if ((lo % n) != 0) return 1'b0;
    end
    return 1'b1;
  endfunction

  // --- grant -------------------------------------------------------------------
  // cur_wait is chosen while no request is waiting, so a delay of 0 grants in the
  // request cycle; waited counts the cycles the current request has waited.
  int unsigned cur_wait;
  int unsigned waited;

  assign mem_gnt = mem_req & ~outstanding & ~mem_rvalid & (waited >= cur_wait);

  always @(posedge clk) begin : p_gnt
    if (!rst_n) begin
      cur_wait <= 0;
      waited   <= 0;
    end else if (!mem_req || mem_gnt) begin
      cur_wait <= pick(min_gnt_delay, max_gnt_delay);
      waited   <= 0;
    end else begin
      waited <= waited + 1;
    end
  end

  // --- main ----------------------------------------------------------------------
  always @(posedge clk) begin : p_main
    int unsigned d;
    if (!rst_n) begin
      outstanding <= 1'b0;
      rsp_wait    <= 0;
      mem_rvalid  <= 1'b0;
      prev_wait   <= 1'b0;
    end else begin
      // rule 1
      if (prev_wait && !(mem_req && mem_we == prev_we && mem_addr == prev_addr &&
                         mem_be == prev_be && (!mem_we || mem_wdata == prev_wdata))) begin
        $display("ERROR [claude_mem_model] request dropped or changed before grant (%0t)", $time);
        proto_errors++;
      end
      // rule 2
      if (mem_req && (outstanding || mem_rvalid)) begin
        $display("ERROR [claude_mem_model] request while one is outstanding (%0t)", $time);
        proto_errors++;
      end
      // rule 9, and 6 / 7 when enabled
      if (mem_req && mem_be == '0) begin
        $display("ERROR [claude_mem_model] mem_be all zeros (%0t)", $time);
        proto_errors++;
      end
      if (CHECK_INIT_RULES && mem_req && !lanes_ok(mem_we, mem_addr, mem_be)) begin
        $display("ERROR [claude_mem_model] address / byte enables break rule 6 or 7: %s 0x%0h be %b (%0t)",
                 mem_we ? "WR" : "RD", mem_addr, mem_be, $time);
        proto_errors++;
      end
      if (mem_req && !mem_gnt) n_gnt_stall++;
      if (outstanding) n_rsp_stall++;
      prev_wait  <= mem_req & ~mem_gnt;
      prev_we    <= mem_we;
      prev_addr  <= mem_addr;
      prev_be    <= mem_be;
      prev_wdata <= mem_wdata;

      mem_rvalid <= 1'b0;
      if (mem_req && mem_gnt) begin
        n_req++;
        rsp_err  <= 1'b0;
        rsp_data <= '0;
        if ((OOR_ERR && !in_range(mem_addr)) || (mem_addr >= err_lo && mem_addr <= err_hi)) begin
          n_err++;
          rsp_err <= 1'b1;
        end else if (mem_we) begin
          n_wr++;
          for (int b = 0; b < StrbW; b++)
            if (mem_be[b]) mem[index(mem_addr)][8*b +: 8] <= mem_wdata[8*b +: 8];
        end else begin
          n_rd++;
          rsp_data <= mem[index(mem_addr)];
        end
        d = pick(min_rsp_delay, max_rsp_delay);
        if (d == 0) begin
          mem_rvalid <= 1'b1;
        end else begin
          rsp_wait    <= d - 1;
          outstanding <= 1'b1;
        end
      end else if (outstanding) begin
        if (rsp_wait == 0) begin
          mem_rvalid  <= 1'b1;
          outstanding <= 1'b0;
        end else begin
          rsp_wait <= rsp_wait - 1;
        end
      end
    end
  end

  assign mem_rdata = mem_rvalid ? rsp_data : {DATA_W{1'bx}};
  assign mem_err   = mem_rvalid ? rsp_err  : 1'bx;

endmodule : claude_mem_model
