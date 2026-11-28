// claude_apb_mst_if.sv — Claude memory bus to APB4 master adapter (shared component).
//
// Takes requests on the Claude memory bus (mem_*, the adapter is the target)
// and issues them as APB4 master transfers. It is the initiator-side
// counterpart of claude_apb_mem_if; one claude_<proto>_mem_if followed by a
// claude_<proto>_mst_if is a protocol bridge. The bus rules are in
// .agents/IP_SPEC_mem_bus.md (rules 1-5) and .agents/IP_SPEC_mem_bus_initiator.md
// (rules 6-9, mem_prot, timing).
//
// Protocol notes:
//   - One transfer at a time. mem_gnt_o is high whenever the adapter is idle;
//     a request is captured in its handshake cycle (cycle 0).
//   - Cycle 1: SETUP (PSEL = 1, PENABLE = 0). Cycle 2 onwards: ACCESS
//     (PENABLE = 1) until PREADY. The cycle after PREADY: mem_rvalid_o, with
//     mem_rdata_o = PRDATA and mem_err_o = PSLVERR captured at PREADY.
//     Zero-wait slave: mem_rvalid_o in cycle 3, one transfer per 4 cycles.
//   - Every APB output and every mem_* output comes from a flop.
//   - PSTRB = mem_be_i on writes and 0 on reads (APB4 rule). PADDR is the byte
//     address mem_addr_i unchanged. PPROT = mem_prot_i (AxPROT encoding).
//   - During reset the bus is idle (PSEL = PENABLE = 0) and mem_gnt_o is 0.
//   - Address decoding (several slaves) belongs to the bus demux or the
//     bus_matrix: there is one PSEL.
//   - No DFT ports: no clock, reset or memory logic of its own (spec).
//
// Parameters:
//   DATA_W : data width, a multiple of 8, 8..32 for APB4 (default 32)
//   ADDR_W : byte address width, 1..32 (default 32)

module claude_apb_mst_if #(
  parameter int unsigned DATA_W = 32, // data bus width (multiple of 8, 8..32)
  parameter int unsigned ADDR_W = 32  // byte address width (1..32)
) (
  // APB4 bus signals (master side)
  input  logic                  PCLK,          // APB clock
  input  logic                  PRESETn,       // APB active-low synchronous reset
  output logic                  PSEL,          // slave select
  output logic                  PENABLE,       // ACCESS phase
  output logic [ADDR_W-1:0]     PADDR,         // byte address
  output logic                  PWRITE,        // 1 = write
  output logic [DATA_W-1:0]     PWDATA,        // write data
  output logic [DATA_W/8-1:0]   PSTRB,         // write strobes (0 on reads)
  output logic [2:0]            PPROT,         // protection (AxPROT encoding)
  input  logic [DATA_W-1:0]     PRDATA,        // read data
  input  logic                  PREADY,        // transfer complete
  input  logic                  PSLVERR,       // transfer failed

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
  generate
    if (DATA_W < 8 || DATA_W > 32 || (DATA_W % 8) != 0) begin : g_chk_data_w
`ifdef ALTERA_RESERVED_QIS
      claude_param_out_of_range u_data_w ();   // Quartus has no elaboration $error
`else
      $error("claude_apb_mst_if: DATA_W = %0d out of range (8, 16, 24 or 32)", DATA_W);
`endif
    end
  endgenerate
  generate
    if (ADDR_W < 1 || ADDR_W > 32) begin : g_chk_addr_w
`ifdef ALTERA_RESERVED_QIS
      claude_param_out_of_range u_addr_w ();   // Quartus has no elaboration $error
`else
      $error("claude_apb_mst_if: ADDR_W = %0d out of range [1, 32]", ADDR_W);
`endif
    end
  endgenerate
`ifdef __ICARUS__
  // Icarus 12 ignores elaboration-time $error in generate blocks: check at time 0.
  initial begin : p_chk_icarus
    if (DATA_W < 8 || DATA_W > 32 || (DATA_W % 8) != 0 || ADDR_W < 1 || ADDR_W > 32) begin
      $fatal(1, "claude_apb_mst_if: DATA_W = %0d / ADDR_W = %0d out of range", DATA_W, ADDR_W);
    end
  end
`endif

  localparam int unsigned StrbW = DATA_W / 8;

  // Transfer state: IDLE, SETUP, ACCESS.
  typedef enum logic [1:0] {
    ST_IDLE   = 2'd0,
    ST_SETUP  = 2'd1,
    ST_ACCESS = 2'd2
  } state_t;

  state_t state_q;
  logic   gnt_q;      // registered mem_gnt_o: high in IDLE, low in reset
  logic   accept;     // request handshake this cycle
  logic   done;       // ACCESS completes this cycle

  assign accept = mem_req_i & gnt_q;
  assign done   = (state_q == ST_ACCESS) & PREADY;

  // State machine and the APB control signals.
  always_ff @(posedge PCLK) begin : p_fsm
    if (!PRESETn) begin
      state_q <= ST_IDLE;
      gnt_q   <= 1'b0;
      PSEL    <= 1'b0;
      PENABLE <= 1'b0;
    end else begin
      case (state_q)
        ST_IDLE: begin
          gnt_q <= 1'b1;
          if (accept) begin
            state_q <= ST_SETUP;
            gnt_q   <= 1'b0;
            PSEL    <= 1'b1;
          end
        end
        ST_SETUP: begin
          state_q <= ST_ACCESS;
          PENABLE <= 1'b1;
        end
        ST_ACCESS: begin
          if (PREADY) begin
            state_q <= ST_IDLE;
            gnt_q   <= 1'b1;
            PSEL    <= 1'b0;
            PENABLE <= 1'b0;
          end
        end
        default: begin
          state_q <= ST_IDLE;
          gnt_q   <= 1'b0;
          PSEL    <= 1'b0;
          PENABLE <= 1'b0;
        end
      endcase
    end
  end

  // Address, control and write data: captured at the handshake, held for the
  // whole transfer (APB4 SETUP-to-ACCESS stability).
  always_ff @(posedge PCLK) begin : p_payload
    if (!PRESETn) begin
      PADDR  <= '0;
      PWRITE <= 1'b0;
      PWDATA <= '0;
      PSTRB  <= '0;
      PPROT  <= '0;
    end else if (accept) begin
      PADDR  <= mem_addr_i;
      PWRITE <= mem_we_i;
      PWDATA <= mem_wdata_i;
      PSTRB  <= mem_we_i ? mem_be_i : {StrbW{1'b0}};
      PPROT  <= mem_prot_i;
    end
  end

  // Response: one-cycle mem_rvalid_o after PREADY, data and error captured.
  always_ff @(posedge PCLK) begin : p_rsp
    if (!PRESETn) begin
      mem_rvalid_o <= 1'b0;
      mem_rdata_o  <= '0;
      mem_err_o    <= 1'b0;
    end else begin
      mem_rvalid_o <= done;
      if (done) begin
        mem_rdata_o <= PRDATA;
        mem_err_o   <= PSLVERR;
      end
    end
  end

  assign mem_gnt_o = gnt_q;

endmodule : claude_apb_mst_if
