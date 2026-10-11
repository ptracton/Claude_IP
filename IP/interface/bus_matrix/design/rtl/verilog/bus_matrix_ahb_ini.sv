// bus_matrix_ahb_ini.sv — AHB-Lite initiator adapter for one bus matrix slave port.
//
// Acts as an AHB-Lite master towards the external slave and runs exactly one
// single transfer for each core request.
//
//   Address phase: presented (HSEL, HTRANS=NONSEQ) while idle and req is
//     high; held until the slave's HREADY is high.
//   Data phase:    HTRANS=IDLE, HWDATA/HWSTRB driven from the core; done
//     pulses in the cycle the slave raises HREADY, with HRDATA and HRESP.
//
// The core keeps req high until done and drops it on the following cycle,
// so a new address phase is never started for a finished request.

module bus_matrix_ahb_ini #(
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

  // AHB-Lite master interface (towards the external slave)
  output logic                  HSEL,   // slave select
  output logic [ADDR_W-1:0]     HADDR,  // byte address
  output logic [1:0]            HTRANS, // transfer type
  output logic                  HWRITE, // 1 = write
  output logic [DATA_W-1:0]     HWDATA, // write data (data phase)
  output logic [DATA_W/8-1:0]   HWSTRB, // byte strobes (data phase)
  input  logic [DATA_W-1:0]     HRDATA, // read data
  input  logic                  HREADY, // transfer done
  input  logic                  HRESP   // 1 = ERROR
);

  localparam logic [1:0] HTRANS_IDLE   = 2'b00;
  localparam logic [1:0] HTRANS_NONSEQ = 2'b10;

  logic dphase_q; // data phase in progress
  logic aphase;   // address phase presented this cycle

  assign aphase = core_req & ~dphase_q;

  always_ff @(posedge clk) begin : p_dphase
    if (!rst_n) begin
      dphase_q <= 1'b0;
    end else if (HREADY) begin
      dphase_q <= aphase;
    end
  end

  assign HSEL   = aphase;
  assign HTRANS = aphase ? HTRANS_NONSEQ : HTRANS_IDLE;
  assign HADDR  = core_addr;
  assign HWRITE = core_we;
  assign HWDATA = core_wdata;
  assign HWSTRB = core_we ? core_be : '0;

  assign core_done  = dphase_q & HREADY;
  assign core_rdata = HRDATA;
  assign core_err   = HRESP;

endmodule : bus_matrix_ahb_ini
