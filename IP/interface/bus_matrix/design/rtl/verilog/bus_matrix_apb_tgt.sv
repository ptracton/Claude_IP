// bus_matrix_apb_tgt.sv — APB4 target adapter for one bus matrix master port.
//
// Acts as an APB4 slave towards the external master. The ACCESS phase
// (PSEL & PENABLE) is the core request; the master holds it, with address,
// control and write data stable, until PREADY. PREADY and PSLVERR are the
// core's done and err, so the ACCESS phase lasts as long as the routed
// transaction (including any wait for arbitration).
//
// Purely combinational: APB4 already holds every request field for the
// whole transfer.

module bus_matrix_apb_tgt #(
  parameter int unsigned DATA_W = 32, // data bus width
  parameter int unsigned ADDR_W = 32  // address width
) (
  // APB4 slave interface (towards the external master)
  input  logic                  PSEL,    // slave select
  input  logic                  PENABLE, // ACCESS phase
  input  logic [ADDR_W-1:0]     PADDR,   // byte address
  input  logic                  PWRITE,  // 1 = write
  input  logic [DATA_W-1:0]     PWDATA,  // write data
  input  logic [DATA_W/8-1:0]   PSTRB,   // byte strobes
  output logic [DATA_W-1:0]     PRDATA,  // read data
  output logic                  PREADY,  // transfer done
  output logic                  PSLVERR, // 1 = error

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

  assign core_req   = PSEL & PENABLE;
  assign core_addr  = PADDR;
  assign core_wdata = PWDATA;
  assign core_we    = PWRITE;
  assign core_be    = PSTRB;

  assign PREADY  = core_done;
  assign PSLVERR = core_done & core_err;
  assign PRDATA  = core_rdata;

endmodule : bus_matrix_apb_tgt
