// sram_bus_if.sv — UVM signal bundle of one sram bus port (Step 6).
//
// One interface carries the pins of all four protocols, so the UVM agent has
// a single virtual-interface type; tb_sram_uvm.sv wires only the protocol it
// was built for and the others stay idle. Data and strobes are MAX_W = 64
// bits wide; a narrower port uses the low bits.
//
// UVM exception (.agents/uvm.md): SV interfaces are allowed in
// verification/tasks/uvm/ only. Signal names follow the bus specifications
// (upper case), not the lower_snake_case rule, so the wiring in the top-level
// reads like the protocol.

`timescale 1ns / 1ps

interface sram_bus_if (
  input logic clk,
  input logic rst_n
);

  localparam int unsigned MAX_W = 64;
  localparam int unsigned MAX_S = MAX_W / 8;

  // APB4
  logic             PSEL;
  logic             PENABLE;
  logic [31:0]      PADDR;
  logic             PWRITE;
  logic [MAX_W-1:0] PWDATA;
  logic [MAX_S-1:0] PSTRB;
  logic [MAX_W-1:0] PRDATA;
  logic             PREADY;
  logic             PSLVERR;

  // AHB-Lite (HREADY is the slave's HREADYOUT: the port is the only slave)
  logic             HSEL;
  logic [31:0]      HADDR;
  logic [1:0]       HTRANS;
  logic             HWRITE;
  logic [2:0]       HSIZE;
  logic [MAX_W-1:0] HWDATA;
  logic [MAX_S-1:0] HWSTRB;
  logic [MAX_W-1:0] HRDATA;
  logic             HREADY;
  logic             HRESP;

  // AXI4-Lite
  logic             AWVALID;
  logic             AWREADY;
  logic [31:0]      AWADDR;
  logic             WVALID;
  logic             WREADY;
  logic [MAX_W-1:0] WDATA;
  logic [MAX_S-1:0] WSTRB;
  logic             BVALID;
  logic             BREADY;
  logic [1:0]       BRESP;
  logic             ARVALID;
  logic             ARREADY;
  logic [31:0]      ARADDR;
  logic             RVALID;
  logic             RREADY;
  logic [MAX_W-1:0] RDATA;
  logic [1:0]       RRESP;

  // Wishbone B4 classic
  logic             CYC;
  logic             STB;
  logic             WE;
  logic [31:0]      ADR;
  logic [MAX_W-1:0] DAT_W;     // master -> slave (DAT_I of the slave)
  logic [MAX_S-1:0] SEL;
  logic [MAX_W-1:0] DAT_R;     // slave -> master (DAT_O of the slave)
  logic             ACK;
  logic             ERR;

  // Every master output idle (the driver also does this at time 0).
  function automatic void idle_all();
    PSEL    = 1'b0;
    PENABLE = 1'b0;
    PADDR   = '0;
    PWRITE  = 1'b0;
    PWDATA  = '0;
    PSTRB   = '0;
    HSEL    = 1'b0;
    HADDR   = '0;
    HTRANS  = 2'b00;
    HWRITE  = 1'b0;
    HSIZE   = 3'd0;
    HWDATA  = '0;
    HWSTRB  = '0;
    AWVALID = 1'b0;
    AWADDR  = '0;
    WVALID  = 1'b0;
    WDATA   = '0;
    WSTRB   = '0;
    BREADY  = 1'b0;
    ARVALID = 1'b0;
    ARADDR  = '0;
    RREADY  = 1'b0;
    CYC     = 1'b0;
    STB     = 1'b0;
    WE      = 1'b0;
    ADR     = '0;
    DAT_W   = '0;
    SEL     = '0;
  endfunction

endinterface : sram_bus_if
