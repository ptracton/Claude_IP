// claude_ahb_mst_if.sv — Claude memory bus to AHB-Lite master adapter (shared component).
//
// Takes requests on the Claude memory bus (mem_*, the adapter is the target)
// and issues them as single AHB-Lite master transfers. It is the initiator-side
// counterpart of claude_ahb_mem_if. The bus rules are in .agents/IP_SPEC_mem_bus.md
// (rules 1-5) and .agents/IP_SPEC_mem_bus_initiator.md (rules 6-9, mem_prot, timing).
//
// Protocol notes:
//   - One transfer at a time: HTRANS = NONSEQ for the address phase, then IDLE;
//     HBURST = SINGLE, HMASTLOCK = 0. With one transfer outstanding there is never
//     a following transfer to cancel after an ERROR response.
//   - mem_gnt_o is high whenever the adapter is idle; a request is captured in its
//     handshake cycle (cycle 0). Cycle 1: address phase, held until HREADY. Next:
//     data phase until HREADY, with HRDATA and HRESP captured then. The cycle after:
//     mem_rvalid_o. Zero-wait slave: mem_rvalid_o in cycle 3, one transfer per 4
//     cycles.
//   - HSIZE / HADDR from the byte enables: a naturally aligned power-of-two pattern
//     (every read, rule 7) gives HADDR = mem_addr_i and HSIZE = log2(bytes); any
//     other write pattern gives a full-width transfer at the word-aligned address
//     with HWSTRB selecting the bytes.
//   - HWSTRB (AHB5 write strobes): mem_be_i on writes and 0 on reads when
//     HAS_HWSTRB = 1. With HAS_HWSTRB = 0 the port is driven all ones (a master
//     without strobes, as the slave adapter expects) and a write pattern that is not
//     naturally aligned is answered with mem_err_o in the next cycle, without a bus
//     access (rule 8).
//   - HPROT[3:0] = {0 (not cacheable), 0 (not bufferable), mem_prot_i[0]
//     (privileged), ~mem_prot_i[2] (data)}. HNONSEC = mem_prot_i[1] when
//     HAS_HNONSEC = 1, else 0.
//   - HRESP ERROR (two-cycle response) -> mem_err_o.
//   - Every AHB output and every mem_* output comes from a flop. During reset the
//     bus is idle (HTRANS = IDLE) and mem_gnt_o is 0.
//   - No DFT ports: no clock, reset or memory logic of its own (spec).
//
// Parameters:
//   DATA_W      : data width, a power of two, 8..1024 (default 32)
//   ADDR_W      : byte address width, 1..64 (default 32)
//   HAS_HWSTRB  : 1 = drive HWSTRB, any write pattern (default 1)
//   HAS_HNONSEC : 1 = drive HNONSEC from mem_prot_i[1] (default 0)

module claude_ahb_mst_if #(
  parameter int unsigned DATA_W      = 32, // data bus width (power of two, 8..1024)
  parameter int unsigned ADDR_W      = 32, // byte address width (1..64)
  parameter int unsigned HAS_HWSTRB  = 1,  // 1 = AHB5 write strobes (0 or 1)
  parameter int unsigned HAS_HNONSEC = 0   // 1 = AHB5 HNONSEC (0 or 1)
) (
  // AHB-Lite bus signals (master side)
  input  logic                  HCLK,          // AHB clock
  input  logic                  HRESETn,       // AHB active-low synchronous reset
  output logic [ADDR_W-1:0]     HADDR,         // byte address
  output logic [1:0]            HTRANS,        // IDLE (00) or NONSEQ (10)
  output logic                  HWRITE,        // 1 = write
  output logic [2:0]            HSIZE,         // transfer size, 2**HSIZE bytes
  output logic [2:0]            HBURST,        // SINGLE
  output logic [3:0]            HPROT,         // protection
  output logic                  HMASTLOCK,     // 0
  output logic                  HNONSEC,       // AHB5 non-secure (HAS_HNONSEC)
  output logic [DATA_W-1:0]     HWDATA,        // write data (data phase)
  output logic [DATA_W/8-1:0]   HWSTRB,        // write strobes (data phase)
  input  logic [DATA_W-1:0]     HRDATA,        // read data
  input  logic                  HREADY,        // transfer complete / bus ready
  input  logic                  HRESP,         // 0 = OKAY, 1 = ERROR

  // Memory bus (target side)
  input  logic                  mem_req_i,     // request valid
  output logic                  mem_gnt_o,     // request accepted (adapter idle)
  input  logic                  mem_we_i,      // 1 = write
  input  logic [ADDR_W-1:0]     mem_addr_i,    // byte address (rule 6)
  input  logic [DATA_W/8-1:0]   mem_be_i,      // byte enables (rules 7-9)
  input  logic [DATA_W-1:0]     mem_wdata_i,   // write data
  input  logic [2:0]            mem_prot_i,    // protection (AxPROT encoding)
  output logic                  mem_rvalid_o,  // response valid (one cycle)
  output logic [DATA_W-1:0]     mem_rdata_o,   // read data (valid with mem_rvalid_o)
  output logic                  mem_err_o      // response is an error
);

  // -------------------------------------------------------------------------
  // Parameter checks (IP_SPEC_sideband.md rule 6)
  // -------------------------------------------------------------------------
  localparam bit DataWOk = (DATA_W >= 8) && (DATA_W <= 1024) && ((DATA_W & (DATA_W - 1)) == 0);
  localparam bit AddrWOk = (ADDR_W >= 1) && (ADDR_W <= 64) && (HAS_HWSTRB <= 1) && (HAS_HNONSEC <= 1);
  generate
    if (!DataWOk) begin : g_chk_data_w
`ifdef ALTERA_RESERVED_QIS
      claude_param_out_of_range u_data_w ();   // Quartus has no elaboration $error
`else
      $error("claude_ahb_mst_if: DATA_W = %0d out of range (power of two, 8..1024)", DATA_W);
`endif
    end
  endgenerate
  generate
    if (!AddrWOk) begin : g_chk_addr_w
`ifdef ALTERA_RESERVED_QIS
      claude_param_out_of_range u_addr_w ();   // Quartus has no elaboration $error
`else
      $error("claude_ahb_mst_if: ADDR_W = %0d out of range [1, 64], or HAS_HWSTRB / HAS_HNONSEC not 0 or 1", ADDR_W);
`endif
    end
  endgenerate
`ifdef __ICARUS__
  // Icarus 12 ignores elaboration-time $error in generate blocks: check at time 0.
  initial begin : p_chk_icarus
    if (!DataWOk || !AddrWOk)
      $fatal(1, "claude_ahb_mst_if: DATA_W = %0d / ADDR_W = %0d out of range", DATA_W, ADDR_W);
  end
`endif

  localparam int unsigned StrbW   = DATA_W / 8;
  localparam logic [2:0]  FullSz  = 3'($clog2(StrbW));
  // Byte-offset bits of an address (a sized constant: Quartus has no ADDR_W'(...) cast).
  localparam logic [ADDR_W-1:0] OffMask = StrbW - 1;
  localparam logic [1:0]  TrIdle  = 2'b00;
  localparam logic [1:0]  TrNseq  = 2'b10;

  // -------------------------------------------------------------------------
  // Byte-enable analysis: naturally aligned power-of-two block? and its size.
  // -------------------------------------------------------------------------
  function automatic logic be_aligned(logic [StrbW-1:0] be);
    int unsigned lo, n;
    logic        gap, ok;
    lo = StrbW; n = 0; gap = 1'b0; ok = 1'b1;
    for (int b = 0; b < StrbW; b++) begin
      if (be[b]) begin
        if (lo == StrbW) lo = b;
        if (gap) ok = 1'b0;
        n++;
      end else if (lo != StrbW) begin
        gap = 1'b1;
      end
    end
    if (n == 0 || (n & (n - 1)) != 0 || (lo % n) != 0) ok = 1'b0;
    be_aligned = ok;   // assignment form: Yosys does not take `return`
  endfunction

  function automatic logic [2:0] be_size(logic [StrbW-1:0] be);
    int unsigned n;
    n = 0;
    for (int b = 0; b < StrbW; b++) if (be[b]) n++;
    // log2 of a power-of-two byte count (fixed loop: $clog2 of a run-time value is
    // not synthesizable everywhere)
    be_size = 3'b000;
    for (int i = 1; i < 8; i++) if (n == (1 << i)) be_size = 3'(i);
  endfunction

  typedef enum logic [1:0] {
    ST_IDLE = 2'd0,
    ST_ADDR = 2'd1,
    ST_DATA = 2'd2
  } state_t;

  state_t state_q;
  logic   gnt_q;       // registered mem_gnt_o: high in IDLE, low in reset
  logic   accept;      // request handshake this cycle
  logic   aligned;     // the request's byte enables are an aligned block
  logic   illegal;     // rule 8: write pattern the bus cannot carry
  logic   done;        // data phase completes this cycle

  assign accept  = mem_req_i & gnt_q;
  assign aligned = be_aligned(mem_be_i);
  assign illegal = (HAS_HWSTRB == 0) && mem_we_i && !aligned;
  assign done    = (state_q == ST_DATA) & HREADY;

  // State machine and HTRANS.
  always_ff @(posedge HCLK) begin : p_fsm
    if (!HRESETn) begin
      state_q <= ST_IDLE;
      gnt_q   <= 1'b0;
      HTRANS  <= TrIdle;
    end else begin
      case (state_q)
        ST_IDLE: begin
          gnt_q <= 1'b1;
          if (accept && !illegal) begin
            state_q <= ST_ADDR;
            gnt_q   <= 1'b0;
            HTRANS  <= TrNseq;
          end
        end
        ST_ADDR: begin
          if (HREADY) begin        // address phase accepted
            state_q <= ST_DATA;
            HTRANS  <= TrIdle;
          end
        end
        ST_DATA: begin
          if (HREADY) begin        // data phase complete
            state_q <= ST_IDLE;
            gnt_q   <= 1'b1;
          end
        end
        default: begin
          state_q <= ST_IDLE;
          gnt_q   <= 1'b0;
          HTRANS  <= TrIdle;
        end
      endcase
    end
  end

  // Address phase and data phase payload: captured at the handshake, held for the
  // whole transfer.
  always_ff @(posedge HCLK) begin : p_payload
    if (!HRESETn) begin
      HADDR   <= '0;
      HWRITE  <= 1'b0;
      HSIZE   <= 3'b000;
      HPROT   <= 4'b0011;
      HNONSEC <= 1'b0;
      HWDATA  <= '0;
      HWSTRB  <= '0;
    end else if (accept && !illegal) begin
      HWRITE  <= mem_we_i;
      HPROT   <= {2'b00, mem_prot_i[0], ~mem_prot_i[2]};
      HNONSEC <= (HAS_HNONSEC != 0) ? mem_prot_i[1] : 1'b0;
      HWDATA  <= mem_wdata_i;
      if (aligned) begin
        HADDR <= mem_addr_i;
        HSIZE <= be_size(mem_be_i);
      end else begin
        // Sparse write (HAS_HWSTRB = 1 only): full width at the aligned address.
        HADDR <= mem_addr_i & ~OffMask;
        HSIZE <= FullSz;
      end
      if (HAS_HWSTRB == 0) HWSTRB <= {StrbW{1'b1}};
      else if (mem_we_i)   HWSTRB <= mem_be_i;
      else                 HWSTRB <= {StrbW{1'b0}};
    end
  end

  // Response: one-cycle mem_rvalid_o after the data phase, or in the cycle after
  // the handshake for an illegal write pattern (rule 8, no bus access).
  always_ff @(posedge HCLK) begin : p_rsp
    if (!HRESETn) begin
      mem_rvalid_o <= 1'b0;
      mem_rdata_o  <= '0;
      mem_err_o    <= 1'b0;
    end else begin
      mem_rvalid_o <= done | (accept & illegal);
      if (done) begin
        mem_rdata_o <= HRDATA;
        mem_err_o   <= HRESP;
      end else if (accept && illegal) begin
        mem_rdata_o <= '0;
        mem_err_o   <= 1'b1;
      end
    end
  end

  assign HBURST    = 3'b000;   // SINGLE
  assign HMASTLOCK = 1'b0;
  assign mem_gnt_o = gnt_q;

endmodule : claude_ahb_mst_if
