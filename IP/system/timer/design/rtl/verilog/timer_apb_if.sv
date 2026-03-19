// timer_apb_if.sv — APB4 bus interface for Timer IP.
//
// Translates APB4 transactions into the flat register-file access bus.
//
// APB4 protocol:
//   SETUP phase : PSEL asserted, PENABLE deasserted.
//   ACCESS phase: PSEL and PENABLE both asserted.
//   Transfer completes when PENABLE is asserted and PREADY is sampled high.
//
// This implementation asserts PREADY in the same cycle as PENABLE (zero
// wait-states).  Write and read enables are generated only during ACCESS phase.
//
// Ports (bus side):
//   PCLK, PRESETn — APB clock and active-low reset
//   PSEL          — slave select
//   PENABLE       — enable (second phase)
//   PADDR[11:0]   — byte address
//   PWRITE        — 1=write, 0=read
//   PWDATA[31:0]  — write data
//   PSTRB[3:0]    — byte write enables
//   PRDATA[31:0]  — read data
//   PREADY        — ready (always 1)
//   PSLVERR       — slave error (always 0)
//
// Ports (regfile side):
//   wr_en, wr_addr, wr_data, wr_strb — write channel
//   rd_en, rd_addr, rd_data          — read channel

module timer_apb_if #(
  parameter int unsigned DATA_W = 32, // data bus width
  parameter int unsigned ADDR_W = 4   // regfile word-address width
) (
  // APB4 bus signals
  // PCLK/PRESETn are APB4-required ports; this module is purely combinational
  // and therefore has no registered state. The regfile above instantiates
  // the clocked path. Waive the Verilator UNUSEDSIGNAL warning accordingly.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic                  PCLK,          // APB clock (routed to regfile/core above)
  input  logic                  PRESETn,        // APB reset  (routed to regfile/core above)
  /* verilator lint_on UNUSEDSIGNAL */

  input  logic                  PSEL,           // slave select
  input  logic                  PENABLE,        // enable (ACCESS phase)
  // PADDR[11:0] declared per APB4 spec; only [ADDR_W+1:2] (4 registers × 4B = 16 B)
  // are used. Upper and byte-offset bits are reserved for future expansion.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [11:0]           PADDR,          // byte address
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic                  PWRITE,         // 1=write
  input  logic [DATA_W-1:0]     PWDATA,         // write data
  input  logic [DATA_W/8-1:0]   PSTRB,          // byte write enables
  output logic [DATA_W-1:0]     PRDATA,         // read data
  output logic                  PREADY,         // always ready
  output logic                  PSLVERR,        // always OKAY

  // Register-file write channel
  output logic                  wr_en,          // write enable (ACCESS phase write)
  output logic [ADDR_W-1:0]     wr_addr,        // word address
  output logic [DATA_W-1:0]     wr_data,        // write data
  output logic [DATA_W/8-1:0]   wr_strb,        // byte write enables

  // Register-file read channel
  output logic                  rd_en,          // read enable (SETUP phase read)
  output logic [ADDR_W-1:0]     rd_addr,        // word address
  input  logic [DATA_W-1:0]     rd_data         // read data (registered in regfile)
);

  // -------------------------------------------------------------------------
  // APB transfers complete in the ACCESS phase (PSEL & PENABLE).
  // Issue wr_en / rd_en only at that point so the regfile sees a single pulse.
  //
  // For reads: rd_en is asserted during SETUP phase so that rd_data is ready
  // one cycle later (in the ACCESS phase) when PRDATA must be valid.
  // -------------------------------------------------------------------------

  // Write path: full access phase, write direction
  assign wr_en   = PSEL & PENABLE & PWRITE;
  assign wr_addr = PADDR[ADDR_W+1:2];
  assign wr_data = PWDATA;
  assign wr_strb = PSTRB;

  // Read path: issue rd_en in SETUP phase (PSEL & ~PENABLE) so regfile
  // registered read data is stable during ACCESS phase.
  assign rd_en   = PSEL & ~PENABLE & ~PWRITE;
  assign rd_addr = PADDR[ADDR_W+1:2];
  assign PRDATA  = rd_data;

  // -------------------------------------------------------------------------
  // APB handshake: zero wait-states, no error
  // -------------------------------------------------------------------------
  assign PREADY  = 1'b1;
  assign PSLVERR = 1'b0;

endmodule : timer_apb_if
