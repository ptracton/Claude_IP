// timer_ahb_if.sv — AHB-Lite bus interface for Timer IP.
//
// Translates AHB-Lite transactions into the flat register-file access bus
// (wr_en / wr_addr / wr_data / wr_strb / rd_en / rd_addr / rd_data).
//
// Protocol notes:
//   - Two-phase pipeline: address phase then data phase.
//   - HREADY is always asserted (zero wait-states).
//   - HRESP is always OKAY (no error response).
//   - Only HTRANS == NONSEQ (2'b10) initiates a transfer.
//   - HSEL qualifies all transactions.
//
// Ports (bus side):
//   HCLK, HRESETn — AHB clock and active-low reset
//   HSEL          — slave select
//   HADDR[11:0]   — byte address (bits [3:2] used as word address)
//   HTRANS[1:0]   — transfer type (NONSEQ=2'b10 only)
//   HWRITE        — 1=write, 0=read
//   HWDATA[31:0]  — write data (valid in data phase)
//   HWSTRB[3:0]   — byte write enables (valid in data phase)
//   HRDATA[31:0]  — read data output
//   HREADY        — ready output (always 1 — zero wait states)
//   HRESP         — response (always 0 — OKAY)
//
// Ports (regfile side):
//   wr_en, wr_addr, wr_data, wr_strb — write channel
//   rd_en, rd_addr, rd_data          — read channel

module timer_ahb_if #(
  parameter int unsigned DATA_W = 32, // data bus width
  parameter int unsigned ADDR_W = 4   // regfile word-address width
) (
  // AHB-Lite bus signals
  input  logic                  HCLK,          // AHB clock
  input  logic                  HRESETn,        // AHB active-low reset

  input  logic                  HSEL,           // slave select
  // HADDR[11:0] per AHB-Lite spec; only [ADDR_W+1:2] used (4 registers = 16 B).
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [11:0]           HADDR,          // byte address
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic [1:0]            HTRANS,         // transfer type
  input  logic                  HWRITE,         // 1=write
  input  logic [DATA_W-1:0]     HWDATA,         // write data (data phase)
  input  logic [DATA_W/8-1:0]   HWSTRB,         // byte strobes (data phase)
  output logic [DATA_W-1:0]     HRDATA,         // read data
  output logic                  HREADY,         // always ready
  output logic                  HRESP,          // always OKAY

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

  // AHB HTRANS encoding
  localparam logic [1:0] AHB_TRANS_NONSEQ = 2'b10;

  // -------------------------------------------------------------------------
  // Address-phase pipeline registers
  // Capture address-phase signals; drive data-phase outputs one cycle later.
  // -------------------------------------------------------------------------
  logic                dphase_valid_q; // data phase active
  logic                dphase_write_q; // 1=write, 0=read
  logic [ADDR_W-1:0]   dphase_addr_q;  // word address latched in address phase

  // -------------------------------------------------------------------------
  // Address phase: latch when a valid NONSEQ transfer is selected
  // -------------------------------------------------------------------------
  always_ff @(posedge HCLK) begin : p_addr_phase
    if (!HRESETn) begin
      dphase_valid_q <= 1'b0;
      dphase_write_q <= 1'b0;
      dphase_addr_q  <= {ADDR_W{1'b0}};
    end else begin
      if (HSEL && (HTRANS == AHB_TRANS_NONSEQ) && HREADY) begin
        dphase_valid_q <= 1'b1;
        dphase_write_q <= HWRITE;
        dphase_addr_q  <= HADDR[ADDR_W+1:2]; // byte -> word address
      end else begin
        dphase_valid_q <= 1'b0;
      end
    end
  end

  // -------------------------------------------------------------------------
  // Write channel: drive regfile write signals during data phase
  // -------------------------------------------------------------------------
  assign wr_en   = dphase_valid_q & dphase_write_q;
  assign wr_addr = dphase_addr_q;
  assign wr_data = HWDATA;
  assign wr_strb = HWSTRB;

  // -------------------------------------------------------------------------
  // Read channel: assert rd_en and capture address during address phase
  // (registered read data in regfile is valid the cycle after rd_en)
  // -------------------------------------------------------------------------
  assign rd_en   = dphase_valid_q & ~dphase_write_q;
  assign rd_addr = dphase_addr_q;
  assign HRDATA  = rd_data;

  // -------------------------------------------------------------------------
  // AHB handshake: zero wait-states, always OKAY
  // -------------------------------------------------------------------------
  assign HREADY = 1'b1;
  assign HRESP  = 1'b0; // OKAY

endmodule : timer_ahb_if
