// bus_matrix_wb_tgt.sv — Wishbone B4 (classic) target adapter for one bus matrix master port.
//
// Acts as a Wishbone slave towards the external master. CYC & STB is the core
// request; the master holds it, with address, data and selects stable, until
// ACK or ERR. ACK/ERR are the core's done split by err. A master that keeps
// STB high after a termination starts a new transfer (classic back-to-back).
//
// Not supported: aborting a transfer by dropping CYC/STB before ACK/ERR.
//
// Purely combinational.

module bus_matrix_wb_tgt #(
  parameter int unsigned DATA_W = 32, // data bus width
  parameter int unsigned ADDR_W = 32  // address width
) (
  // Wishbone slave interface (towards the external master)
  input  logic                  CYC,   // bus cycle
  input  logic                  STB,   // strobe
  input  logic                  WE,    // 1 = write
  input  logic [ADDR_W-1:0]     ADR,   // byte address
  input  logic [DATA_W-1:0]     DAT_W, // write data (master -> matrix)
  input  logic [DATA_W/8-1:0]   SEL,   // byte selects
  output logic [DATA_W-1:0]     DAT_R, // read data (matrix -> master)
  output logic                  ACK,   // normal termination
  output logic                  ERR,   // error termination

  // Core handshake
  output logic                  core_req,   // request held until done
  output logic [ADDR_W-1:0]     core_addr,  // byte address
  output logic [DATA_W-1:0]     core_wdata, // write data
  output logic                  core_we,    // 1 = write
  output logic [DATA_W/8-1:0]   core_be,    // byte enables
  input  logic                  core_done,  // one-cycle completion
  input  logic [DATA_W-1:0]     core_rdata, // read data (valid with done)
  input  logic                  core_err    // error (valid with done)
);

  assign core_req   = CYC & STB;
  assign core_addr  = ADR;
  assign core_wdata = DAT_W;
  assign core_we    = WE;
  assign core_be    = SEL;

  assign ACK   = core_done & ~core_err;
  assign ERR   = core_done & core_err;
  assign DAT_R = core_rdata;

endmodule : bus_matrix_wb_tgt
