// claude_axi4l_if.sv — AXI4-Lite bus-to-regfile bridge (shared Claude IP component).
//
// Translates AXI4-Lite transactions into the flat register-file access bus.
// This module is protocol-generic and contains no IP-specific logic.
// It is shared across all Claude IP blocks that expose an AXI4-Lite slave port.
//
// AXI4-Lite channels used:
//   AW (write address), W (write data), B (write response)
//   AR (read address),  R  (read data)
//
// Implementation notes:
//   - Single outstanding transaction per channel (no pipelining).
//   - AWREADY / WREADY / ARREADY are always asserted so masters can present
//     address and data in the same cycle.
//   - Write: capture AW and W simultaneously; generate wr_en and BVALID next
//     cycle; hold BVALID until master asserts BREADY.
//   - Read: capture AR; assert rd_en; present RVALID / RDATA the cycle after
//     rd_en (matched to regfile registered read latency).
//   - BRESP and RRESP are always OKAY (2'b00).
//
// Ports (bus side):
//   ACLK, ARESETn — AXI clock and active-low reset
//   AW channel    — AWVALID, AWREADY, AWADDR[11:0]
//   W  channel    — WVALID, WREADY, WDATA[31:0], WSTRB[3:0]
//   B  channel    — BVALID, BREADY, BRESP[1:0]
//   AR channel    — ARVALID, ARREADY, ARADDR[11:0]
//   R  channel    — RVALID, RREADY, RDATA[31:0], RRESP[1:0]
//
// Ports (regfile side):
//   wr_en, wr_addr, wr_data, wr_strb — write channel
//   rd_en, rd_addr, rd_data          — read channel

module claude_axi4l_if #(
  parameter int unsigned DATA_W = 32, // data bus width
  parameter int unsigned ADDR_W = 4   // regfile word-address width
) (
  // AXI4-Lite global signals
  input  logic                  ACLK,          // AXI clock
  input  logic                  ARESETn,        // AXI active-low reset

  // Write address channel
  input  logic                  AWVALID,        // master write address valid
  output logic                  AWREADY,        // slave ready for write address
  // AWADDR/ARADDR[11:0] per AXI4-Lite spec; only [ADDR_W+1:2] used (4 regs = 16 B).
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [11:0]           AWADDR,         // write byte address

  // Write data channel
  input  logic                  WVALID,         // master write data valid
  output logic                  WREADY,         // slave ready for write data
  input  logic [DATA_W-1:0]     WDATA,          // write data
  input  logic [DATA_W/8-1:0]   WSTRB,          // byte write enables

  // Write response channel
  output logic                  BVALID,         // slave write response valid
  input  logic                  BREADY,         // master ready for response
  output logic [1:0]            BRESP,          // write response (OKAY)

  // Read address channel
  input  logic                  ARVALID,        // master read address valid
  output logic                  ARREADY,        // slave ready for read address
  input  logic [11:0]           ARADDR,         // read byte address
  /* verilator lint_on UNUSEDSIGNAL */

  // Read data channel
  output logic                  RVALID,         // slave read data valid
  input  logic                  RREADY,         // master ready for read data
  output logic [DATA_W-1:0]     RDATA,          // read data
  output logic [1:0]            RRESP,          // read response (OKAY)

  // Register-file write channel
  output logic                  wr_en,          // write enable
  output logic [ADDR_W-1:0]     wr_addr,        // word address
  output logic [DATA_W-1:0]     wr_data,        // write data
  output logic [DATA_W/8-1:0]   wr_strb,        // byte write enables

  // Register-file read channel
  output logic                  rd_en,          // read enable
  output logic [ADDR_W-1:0]     rd_addr,        // word address
  input  logic [DATA_W-1:0]     rd_data         // read data (registered in regfile)
);

  // -------------------------------------------------------------------------
  // Internal state
  // -------------------------------------------------------------------------

  // Write path: capture AW and W simultaneously when both are valid
  logic                aw_captured_q; // write address captured
  logic [ADDR_W-1:0]   aw_addr_q;     // captured write word address
  logic                w_captured_q;  // write data captured
  logic [DATA_W-1:0]   w_data_q;      // captured write data
  logic [DATA_W/8-1:0] w_strb_q;      // captured write strobes

  logic                bvalid_q;      // BVALID register

  // Read path: two-stage pipeline to match regfile registered-read latency
  //   Stage 1 (ar_captured_q): AR captured → rd_en asserted this cycle
  //   Stage 2 (ar_rd_pending_q): rd_data valid next cycle → latch into rdata_q
  logic                ar_captured_q;   // read address captured (rd_en pulse)
  logic [ADDR_W-1:0]   ar_addr_q;       // captured read word address
  logic                ar_rd_pending_q; // one-cycle delay; rd_data valid on this cycle
  logic                rvalid_q;        // RVALID register
  logic [DATA_W-1:0]   rdata_q;         // captured read data

  // -------------------------------------------------------------------------
  // Write address / data capture and wr_en generation
  // -------------------------------------------------------------------------
  always_ff @(posedge ACLK) begin : p_write
    if (!ARESETn) begin
      aw_captured_q <= 1'b0;
      aw_addr_q     <= {ADDR_W{1'b0}};
      w_captured_q  <= 1'b0;
      w_data_q      <= {DATA_W{1'b0}};
      w_strb_q      <= {(DATA_W/8){1'b0}};
      bvalid_q      <= 1'b0;
    end else begin
      // Capture write address when presented (AWVALID, no outstanding aw)
      if (AWVALID && AWREADY) begin
        aw_captured_q <= 1'b1;
        aw_addr_q     <= AWADDR[ADDR_W+1:2];
      end else if (aw_captured_q && w_captured_q) begin
        aw_captured_q <= 1'b0; // consumed
      end

      // Capture write data when presented
      if (WVALID && WREADY) begin
        w_captured_q <= 1'b1;
        w_data_q     <= WDATA;
        w_strb_q     <= WSTRB;
      end else if (aw_captured_q && w_captured_q) begin
        w_captured_q <= 1'b0; // consumed
      end

      // Issue BVALID one cycle after both AW and W are captured
      if (aw_captured_q && w_captured_q) begin
        bvalid_q <= 1'b1;
      end else if (BREADY) begin
        bvalid_q <= 1'b0;
      end
    end
  end

  // wr_en is a single-cycle pulse when both halves are ready
  assign wr_en   = aw_captured_q & w_captured_q;
  assign wr_addr = aw_addr_q;
  assign wr_data = w_data_q;
  assign wr_strb = w_strb_q;

  // AW and W channels always ready (back-pressure not supported)
  assign AWREADY = 1'b1;
  assign WREADY  = 1'b1;

  assign BVALID = bvalid_q;
  assign BRESP  = 2'b00; // OKAY

  // -------------------------------------------------------------------------
  // Read address capture and rd_en / RVALID generation
  // -------------------------------------------------------------------------
  always_ff @(posedge ACLK) begin : p_read
    if (!ARESETn) begin
      ar_captured_q   <= 1'b0;
      ar_addr_q       <= {ADDR_W{1'b0}};
      ar_rd_pending_q <= 1'b0;
      rvalid_q        <= 1'b0;
      rdata_q         <= {DATA_W{1'b0}};
    end else begin
      // Stage 1: capture AR address; assert rd_en (combinational below)
      if (ARVALID && ARREADY) begin
        ar_captured_q <= 1'b1;
        ar_addr_q     <= ARADDR[ADDR_W+1:2];
      end else begin
        ar_captured_q <= 1'b0;
      end

      // Stage 2: rd_en was high last cycle; regfile has now registered rd_data
      ar_rd_pending_q <= ar_captured_q;
      if (ar_rd_pending_q) begin
        rdata_q  <= rd_data; // rd_data is valid this cycle (one cycle after rd_en)
        rvalid_q <= 1'b1;
      end else if (RREADY && rvalid_q) begin
        rvalid_q <= 1'b0;
      end
    end
  end

  assign rd_en   = ar_captured_q;
  assign rd_addr = ar_addr_q;

  assign ARREADY = 1'b1; // always ready for read address
  assign RVALID  = rvalid_q;
  assign RDATA   = rdata_q;
  assign RRESP   = 2'b00; // OKAY

endmodule : claude_axi4l_if
