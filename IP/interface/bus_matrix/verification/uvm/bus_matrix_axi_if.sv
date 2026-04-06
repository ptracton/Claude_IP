// bus_matrix_axi_if.sv — SystemVerilog interface for AXI4-Lite master port.
//
// Used by the UVM driver and monitor to access DUT signals.

`ifndef BUS_MATRIX_AXI_IF_SV
`define BUS_MATRIX_AXI_IF_SV

interface bus_matrix_axi_if #(
  parameter int DATA_W = 32,
  parameter int ADDR_W = 32
) (
  input logic clk,
  input logic rst_n
);
  // Write address channel
  logic              AWVALID;
  logic              AWREADY;
  logic [ADDR_W-1:0] AWADDR;
  // Write data channel
  logic              WVALID;
  logic              WREADY;
  logic [DATA_W-1:0] WDATA;
  logic [DATA_W/8-1:0] WSTRB;
  // Write response channel
  logic              BVALID;
  logic              BREADY;
  logic [1:0]        BRESP;
  // Read address channel
  logic              ARVALID;
  logic              ARREADY;
  logic [ADDR_W-1:0] ARADDR;
  // Read data channel
  logic              RVALID;
  logic              RREADY;
  logic [DATA_W-1:0] RDATA;
  logic [1:0]        RRESP;

  // Clocking block for driver (master drives on posedge, samples setup before)
  clocking driver_cb @(posedge clk);
    default input #1step output #1;
    output AWVALID, AWADDR;
    input  AWREADY;
    output WVALID, WDATA, WSTRB;
    input  WREADY;
    input  BVALID; input BRESP;
    output BREADY;
    output ARVALID, ARADDR;
    input  ARREADY;
    input  RVALID, RDATA, RRESP;
    output RREADY;
  endclocking

  // Clocking block for monitor (sample only)
  clocking monitor_cb @(posedge clk);
    default input #1step;
    input AWVALID, AWREADY, AWADDR;
    input WVALID,  WREADY,  WDATA, WSTRB;
    input BVALID,  BREADY,  BRESP;
    input ARVALID, ARREADY, ARADDR;
    input RVALID,  RREADY,  RDATA, RRESP;
  endclocking

endinterface : bus_matrix_axi_if

`endif // BUS_MATRIX_AXI_IF_SV
