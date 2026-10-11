// bus_matrix_wb_ini.sv — Wishbone B4 (classic) initiator adapter for one bus matrix slave port.
//
// Acts as a Wishbone master towards the external slave. CYC and STB follow
// the core request, which is held until the slave answers with ACK or ERR
// and dropped on the following cycle, so each grant is exactly one classic
// single read or write.
//
// Purely combinational.

module bus_matrix_wb_ini #(
  parameter int unsigned DATA_W = 32, // data bus width
  parameter int unsigned ADDR_W = 32  // address width
) (
  // Core handshake
  input  logic                  core_req,   // run one transaction
  input  logic [ADDR_W-1:0]     core_addr,  // byte address
  input  logic [DATA_W-1:0]     core_wdata, // write data
  input  logic                  core_we,    // 1 = write
  input  logic [DATA_W/8-1:0]   core_be,    // byte enables
  output logic                  core_done,  // one-cycle completion
  output logic [DATA_W-1:0]     core_rdata, // read data (valid with done)
  output logic                  core_err,   // error (valid with done)

  // Wishbone master interface (towards the external slave)
  output logic                  CYC,   // bus cycle
  output logic                  STB,   // strobe
  output logic                  WE,    // 1 = write
  output logic [ADDR_W-1:0]     ADR,   // byte address
  output logic [DATA_W-1:0]     DAT_W, // write data (matrix -> slave)
  output logic [DATA_W/8-1:0]   SEL,   // byte selects
  input  logic [DATA_W-1:0]     DAT_R, // read data (slave -> matrix)
  input  logic                  ACK,   // normal termination
  input  logic                  ERR    // error termination
);

  assign CYC   = core_req;
  assign STB   = core_req;
  assign WE    = core_we;
  assign ADR   = core_addr;
  assign DAT_W = core_wdata;
  assign SEL   = core_be;

  assign core_done  = core_req & (ACK | ERR);
  assign core_err   = ERR;
  assign core_rdata = DAT_R;

endmodule : bus_matrix_wb_ini
