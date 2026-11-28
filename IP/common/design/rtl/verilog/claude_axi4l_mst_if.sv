// claude_axi4l_mst_if.sv — Claude memory bus to AXI4-Lite master adapter (shared component).
//
// Takes requests on the Claude memory bus (mem_*, the adapter is the target)
// and issues them as AXI4-Lite master transactions. It is the initiator-side
// counterpart of claude_axi4l_mem_if. The bus rules are in .agents/IP_SPEC_mem_bus.md
// (rules 1-5) and .agents/IP_SPEC_mem_bus_initiator.md (rules 6-9, mem_prot, timing).
//
// Protocol notes:
//   - One transaction at a time. mem_gnt_o is high whenever the adapter is idle; a
//     request is captured in its handshake cycle (cycle 0).
//   - Write: AWVALID and WVALID rise together in cycle 1 and each is held until its
//     own handshake (AW and W may be accepted in either order, or together). BREADY
//     is high from cycle 1 until the B handshake.
//   - Read: ARVALID rises in cycle 1 and is held until ARREADY; RREADY is high from
//     cycle 1 until the R handshake.
//   - The cycle after the B or R handshake: mem_rvalid_o, with mem_rdata_o = RDATA
//     and mem_err_o = BRESP[1] / RRESP[1] (SLVERR and DECERR are both errors; the two
//     codes are not distinguished on mem_*). Zero-wait slave: mem_rvalid_o in cycle 3,
//     one transaction per 4 cycles.
//   - AWADDR / ARADDR = mem_addr_i (byte address), WSTRB = mem_be_i (any pattern,
//     rule 8), AWPROT / ARPROT = mem_prot_i.
//   - VALID never depends on READY, and every AXI output and every mem_* output comes
//     from a flop. During reset every VALID and READY is low and mem_gnt_o is 0.
//   - No DFT ports: no clock, reset or memory logic of its own (spec).
//
// Parameters:
//   DATA_W : data width, 32 or 64 (AXI4-Lite), default 32
//   ADDR_W : byte address width, 1..64, default 32

module claude_axi4l_mst_if #(
  parameter int unsigned DATA_W = 32, // data bus width (32 or 64)
  parameter int unsigned ADDR_W = 32  // byte address width (1..64)
) (
  // AXI4-Lite global signals
  input  logic                  ACLK,          // AXI clock
  input  logic                  ARESETn,       // AXI active-low synchronous reset

  // Write address channel
  output logic                  AWVALID,       // write address valid
  input  logic                  AWREADY,       // write address accepted
  output logic [ADDR_W-1:0]     AWADDR,        // write byte address
  output logic [2:0]            AWPROT,        // write protection

  // Write data channel
  output logic                  WVALID,        // write data valid
  input  logic                  WREADY,        // write data accepted
  output logic [DATA_W-1:0]     WDATA,         // write data
  output logic [DATA_W/8-1:0]   WSTRB,         // write byte strobes

  // Write response channel
  input  logic                  BVALID,        // write response valid
  output logic                  BREADY,        // write response accepted
  input  logic [1:0]            BRESP,         // write response

  // Read address channel
  output logic                  ARVALID,       // read address valid
  input  logic                  ARREADY,       // read address accepted
  output logic [ADDR_W-1:0]     ARADDR,        // read byte address
  output logic [2:0]            ARPROT,        // read protection

  // Read data channel
  input  logic                  RVALID,        // read data valid
  output logic                  RREADY,        // read data accepted
  input  logic [DATA_W-1:0]     RDATA,         // read data
  input  logic [1:0]            RRESP,         // read response

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
  localparam bit DataWOk = (DATA_W == 32) || (DATA_W == 64);
  localparam bit AddrWOk = (ADDR_W >= 1) && (ADDR_W <= 64);
  generate
    if (!DataWOk) begin : g_chk_data_w
`ifdef ALTERA_RESERVED_QIS
      claude_param_out_of_range u_data_w ();   // Quartus has no elaboration $error
`else
      $error("claude_axi4l_mst_if: DATA_W = %0d out of range (32 or 64)", DATA_W);
`endif
    end
  endgenerate
  generate
    if (!AddrWOk) begin : g_chk_addr_w
`ifdef ALTERA_RESERVED_QIS
      claude_param_out_of_range u_addr_w ();   // Quartus has no elaboration $error
`else
      $error("claude_axi4l_mst_if: ADDR_W = %0d out of range [1, 64]", ADDR_W);
`endif
    end
  endgenerate
`ifdef __ICARUS__
  // Icarus 12 ignores elaboration-time $error in generate blocks: check at time 0.
  initial begin : p_chk_icarus
    if (!DataWOk || !AddrWOk)
      $fatal(1, "claude_axi4l_mst_if: DATA_W = %0d / ADDR_W = %0d out of range", DATA_W, ADDR_W);
  end
`endif

  typedef enum logic [1:0] {
    ST_IDLE  = 2'd0,
    ST_WRITE = 2'd1,
    ST_READ  = 2'd2
  } state_t;

  state_t state_q;
  logic   gnt_q;       // registered mem_gnt_o: high in IDLE, low in reset
  logic   accept;      // request handshake this cycle
  logic   b_done;      // write response handshake this cycle
  logic   r_done;      // read response handshake this cycle

  assign accept = mem_req_i & gnt_q;
  assign b_done = (state_q == ST_WRITE) & BVALID & BREADY;
  assign r_done = (state_q == ST_READ)  & RVALID & RREADY;

  // State machine and the VALID / READY signals.
  always_ff @(posedge ACLK) begin : p_fsm
    if (!ARESETn) begin
      state_q <= ST_IDLE;
      gnt_q   <= 1'b0;
      AWVALID <= 1'b0;
      WVALID  <= 1'b0;
      BREADY  <= 1'b0;
      ARVALID <= 1'b0;
      RREADY  <= 1'b0;
    end else begin
      case (state_q)
        ST_IDLE: begin
          gnt_q <= 1'b1;
          if (accept) begin
            gnt_q <= 1'b0;
            if (mem_we_i) begin
              state_q <= ST_WRITE;
              AWVALID <= 1'b1;
              WVALID  <= 1'b1;
              BREADY  <= 1'b1;
            end else begin
              state_q <= ST_READ;
              ARVALID <= 1'b1;
              RREADY  <= 1'b1;
            end
          end
        end
        ST_WRITE: begin
          if (AWVALID && AWREADY) AWVALID <= 1'b0;
          if (WVALID && WREADY)   WVALID  <= 1'b0;
          if (b_done) begin
            state_q <= ST_IDLE;
            gnt_q   <= 1'b1;
            BREADY  <= 1'b0;
          end
        end
        ST_READ: begin
          if (ARVALID && ARREADY) ARVALID <= 1'b0;
          if (r_done) begin
            state_q <= ST_IDLE;
            gnt_q   <= 1'b1;
            RREADY  <= 1'b0;
          end
        end
        default: begin
          state_q <= ST_IDLE;
          gnt_q   <= 1'b0;
          AWVALID <= 1'b0;
          WVALID  <= 1'b0;
          BREADY  <= 1'b0;
          ARVALID <= 1'b0;
          RREADY  <= 1'b0;
        end
      endcase
    end
  end

  // Address, protection, data and strobes: captured at the handshake and held until
  // the transaction completes (AXI: payload stable while VALID is high).
  always_ff @(posedge ACLK) begin : p_payload
    if (!ARESETn) begin
      AWADDR <= '0;
      AWPROT <= '0;
      WDATA  <= '0;
      WSTRB  <= '0;
      ARADDR <= '0;
      ARPROT <= '0;
    end else if (accept) begin
      if (mem_we_i) begin
        AWADDR <= mem_addr_i;
        AWPROT <= mem_prot_i;
        WDATA  <= mem_wdata_i;
        WSTRB  <= mem_be_i;
      end else begin
        ARADDR <= mem_addr_i;
        ARPROT <= mem_prot_i;
      end
    end
  end

  // Response: one-cycle mem_rvalid_o after the B or R handshake.
  always_ff @(posedge ACLK) begin : p_rsp
    if (!ARESETn) begin
      mem_rvalid_o <= 1'b0;
      mem_rdata_o  <= '0;
      mem_err_o    <= 1'b0;
    end else begin
      mem_rvalid_o <= b_done | r_done;
      if (r_done) begin
        mem_rdata_o <= RDATA;
        mem_err_o   <= RRESP[1];
      end else if (b_done) begin
        mem_rdata_o <= '0;
        mem_err_o   <= BRESP[1];
      end
    end
  end

  assign mem_gnt_o = gnt_q;

  // BRESP[0] / RRESP[0] only tell SLVERR from DECERR, which mem_* does not carry.
  logic unused_resp;
  assign unused_resp = BRESP[0] ^ RRESP[0];

endmodule : claude_axi4l_mst_if
