// claude_mem_tb_target.sv — Simulation memory model for the Claude memory bus.
//
// Plays the target side of the mem_* bus (IP/common/design/rtl/mem_bus.md)
// for the claude_<proto>_mem_if testbenches. Simulation only.
//
// Behaviour:
//   - WORDS words of storage, indexed by the word address bits above the
//     byte offset (higher bits alias). Contents start at zero.
//   - Addresses with bit ADDR_W-1 set are an error region: the request is
//     answered with mem_err = 1, a write is dropped and read data is 0.
//   - Latency knobs (set from the testbench at any time):
//       max_gnt_delay  0: grant in the request cycle; N: each cycle a waiting
//                      request is granted with probability 1/(N+1)
//       max_rsp_delay  0: respond in the cycle after the grant; N: 0..N extra
//                      cycles, uniformly random
//   - rdata / err are driven to X outside the response cycle, so an adapter
//     that uses them at the wrong time shows up as X on the bus.
//   - Protocol checks on the initiator (adapter): request payload held until
//     granted, no request while one is outstanding. Violations are counted in
//     proto_errors and printed.
//   - Counters for the testbench: n_req (granted requests), n_wr, n_rd,
//     n_err, n_gnt_stall (cycles a request waited for its grant),
//     n_rsp_stall (cycles a granted request waited beyond the minimum);
//     last_we / last_addr / last_be / last_wdata of the last request.

`timescale 1ns / 1ps

module claude_mem_tb_target #(
  parameter int unsigned DATA_W = 32,
  parameter int unsigned ADDR_W = 32,
  parameter int unsigned WORDS  = 1024,
  parameter int unsigned SEED   = 1
) (
  input  logic                  clk,
  input  logic                  rst,          // active-high
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
  localparam int unsigned IdxW  = $clog2(WORDS);

  logic [DATA_W-1:0] mem [WORDS];

  int unsigned max_gnt_delay = 0;
  int unsigned max_rsp_delay = 0;

  int unsigned n_req        = 0;
  int unsigned n_wr         = 0;
  int unsigned n_rd         = 0;
  int unsigned n_err        = 0;
  int unsigned proto_errors = 0;
  int unsigned n_gnt_stall  = 0;
  int unsigned n_rsp_stall  = 0;

  logic                last_we;
  logic [ADDR_W-1:0]   last_addr;
  logic [StrbW-1:0]    last_be;
  logic [DATA_W-1:0]   last_wdata;

  logic                gnt_allow;     // this cycle's grant decision
  logic                outstanding;   // granted, not yet answered
  int unsigned         rsp_wait;      // cycles left before the response
  logic [DATA_W-1:0]   rsp_data;
  logic                rsp_err;

  logic                prev_wait;     // last cycle: request not granted
  logic                prev_we;
  logic [ADDR_W-1:0]   prev_addr;
  logic [StrbW-1:0]    prev_be;
  logic [DATA_W-1:0]   prev_wdata;

  initial begin
    void'($urandom(SEED));
    for (int i = 0; i < WORDS; i++) mem[i] = '0;
  end

  function automatic int unsigned word_index(logic [ADDR_W-1:0] addr);
    return int'(addr[OffW +: IdxW]);
  endfunction

  assign mem_gnt = mem_req & gnt_allow;

  // Simulation model: plain always blocks, because the counters and the
  // storage are also written by declaration initializers / initial blocks,
  // which always_ff forbids.

  // Grant decision for the next cycle (random when max_gnt_delay > 0).
  always @(posedge clk) begin
    if (rst || max_gnt_delay == 0) begin
      gnt_allow <= 1'b1;
    end else begin
      gnt_allow <= ($urandom_range(max_gnt_delay, 0) == 0);
    end
  end

  always @(posedge clk) begin
    int unsigned delay;
    if (rst) begin
      outstanding <= 1'b0;
      rsp_wait    <= 0;
      mem_rvalid  <= 1'b0;
      prev_wait   <= 1'b0;
    end else begin
      // ---- protocol checks on the adapter ---------------------------------
      if (prev_wait && !(mem_req && mem_we == prev_we && mem_addr == prev_addr &&
                         mem_be == prev_be && (!mem_we || mem_wdata == prev_wdata))) begin
        $display("ERROR [claude_mem_tb_target] request dropped or changed before grant (%0t)",
                 $time);
        proto_errors++;
      end
      if (mem_req && (outstanding || mem_rvalid)) begin
        $display("ERROR [claude_mem_tb_target] request while one is outstanding (%0t)", $time);
        proto_errors++;
      end
      if (mem_req && !mem_gnt) n_gnt_stall++;
      if (outstanding) n_rsp_stall++;
      prev_wait  <= mem_req & ~mem_gnt;
      prev_we    <= mem_we;
      prev_addr  <= mem_addr;
      prev_be    <= mem_be;
      prev_wdata <= mem_wdata;

      // ---- accept a request -----------------------------------------------
      mem_rvalid <= 1'b0;
      if (mem_req && mem_gnt) begin
        n_req++;
        last_we    <= mem_we;
        last_addr  <= mem_addr;
        last_be    <= mem_be;
        last_wdata <= mem_wdata;
        rsp_err    <= mem_addr[ADDR_W-1];
        if (mem_addr[ADDR_W-1]) begin
          n_err++;
          rsp_data <= '0;
        end else if (mem_we) begin
          n_wr++;
          for (int b = 0; b < StrbW; b++) begin
            if (mem_be[b]) mem[word_index(mem_addr)][8*b +: 8] <= mem_wdata[8*b +: 8];
          end
          rsp_data <= '0;
        end else begin
          n_rd++;
          rsp_data <= mem[word_index(mem_addr)];
        end
        // Response in the next cycle plus 0..max_rsp_delay extra cycles.
        delay = (max_rsp_delay == 0) ? 0 : $urandom_range(max_rsp_delay, 0);
        if (delay == 0) begin
          mem_rvalid <= 1'b1;
        end else begin
          rsp_wait    <= delay - 1;
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

  assign mem_rdata = mem_rvalid ? rsp_data : 'x;
  assign mem_err   = mem_rvalid ? rsp_err  : 1'bx;

endmodule : claude_mem_tb_target
