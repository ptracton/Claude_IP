// bus_matrix_apb_ini.sv — APB4 initiator adapter for one bus matrix slave port.
//
// Acts as an APB4 master towards the external slave and runs exactly one
// transfer for each core request:
//   SETUP  (PSEL=1, PENABLE=0) for one cycle, presented while idle and req is high,
//   ACCESS (PSEL=1, PENABLE=1) until PREADY; done pulses in that cycle.
// PSTRB is zero on reads, as APB4 requires.

module bus_matrix_apb_ini #(
  parameter int unsigned DATA_W = 32, // data bus width
  parameter int unsigned ADDR_W = 32  // address width
) (
  input  logic                  clk,   // system clock
  input  logic                  rst_n, // synchronous active-low reset

  // Core handshake
  input  logic                  core_req,   // run one transaction
  input  logic [ADDR_W-1:0]     core_addr,  // byte address
  input  logic [DATA_W-1:0]     core_wdata, // write data
  input  logic                  core_we,    // 1 = write
  input  logic [DATA_W/8-1:0]   core_be,    // byte enables
  output logic                  core_done,  // one-cycle completion
  output logic [DATA_W-1:0]     core_rdata, // read data (valid with done)
  output logic                  core_err,   // error (valid with done)

  // APB4 master interface (towards the external slave)
  output logic                  PSEL,    // slave select
  output logic                  PENABLE, // ACCESS phase
  output logic [ADDR_W-1:0]     PADDR,   // byte address
  output logic                  PWRITE,  // 1 = write
  output logic [DATA_W-1:0]     PWDATA,  // write data
  output logic [DATA_W/8-1:0]   PSTRB,   // byte strobes
  input  logic [DATA_W-1:0]     PRDATA,  // read data
  input  logic                  PREADY,  // transfer done
  input  logic                  PSLVERR  // 1 = error
);

  logic access_q; // ACCESS phase in progress

  always_ff @(posedge clk) begin : p_access
    if (!rst_n) begin
      access_q <= 1'b0;
    end else if (access_q) begin
      access_q <= ~PREADY;
    end else begin
      access_q <= core_req;
    end
  end

  assign PSEL    = core_req | access_q;
  assign PENABLE = access_q;
  assign PADDR   = core_addr;
  assign PWRITE  = core_we;
  assign PWDATA  = core_wdata;
  assign PSTRB   = core_we ? core_be : '0;

  assign core_done  = access_q & PREADY;
  assign core_rdata = PRDATA;
  assign core_err   = PSLVERR;

endmodule : bus_matrix_apb_ini
