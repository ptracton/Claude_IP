// bus_matrix_axi4l.sv — AXI4-Lite bus matrix top-level.
//
// Crossbar interconnect connecting NUM_MASTERS AXI4-Lite masters to
// NUM_SLAVES AXI4-Lite slaves. All configuration (address map, arbitration
// mode, priorities) is set via elaboration-time parameters; there are no
// runtime registers. The defaults (bus_matrix_pkg) are the synthesized
// configuration.
//
// Structure: one bus_matrix_axi4l_tgt per master port, one
// bus_matrix_axi4l_ini per slave port, and the protocol-agnostic
// bus_matrix_core between them. Ports are flat-packed: master i / slave j
// occupy slice [i*W+:W] / [j*W+:W].

module bus_matrix_axi4l #(
  // Defaults from bus_matrix_pkg (package-qualified rather than imported in
  // the header, which Yosys cannot parse).
  parameter int unsigned NUM_MASTERS = bus_matrix_pkg::BM_NUM_MASTERS,             // 1-16 active masters
  parameter int unsigned NUM_SLAVES  = bus_matrix_pkg::BM_NUM_SLAVES,              // 1-32 active slaves
  parameter int unsigned DATA_W      = 32,                                         // data bus width
  parameter int unsigned ADDR_W      = 32,                                         // address width (must be 32)
  parameter int unsigned ARB_MODE    = bus_matrix_pkg::BM_ARB_MODE,                // 0=fixed-priority, 1=round-robin
  parameter logic [NUM_MASTERS*4-1:0]  M_PRIORITY = bus_matrix_pkg::BM_M_PRIORITY, // master i priority [i*4+:4]
  parameter logic [NUM_SLAVES*32-1:0]  S_BASE     = bus_matrix_pkg::BM_S_BASE,     // slave j base [j*32+:32]
  parameter logic [NUM_SLAVES*32-1:0]  S_MASK     = bus_matrix_pkg::BM_S_MASK      // slave j mask [j*32+:32]
) (
  input  logic                              clk,      // system clock
  input  logic                              rst_n,    // synchronous active-low reset

  // Master ports (the matrix is the AXI4-Lite slave)
  input  logic [NUM_MASTERS-1:0]            M_AWVALID,      // master i AWVALID
  output logic [NUM_MASTERS-1:0]            M_AWREADY,      // master i AWREADY
  input  logic [NUM_MASTERS*ADDR_W-1:0]     M_AWADDR,       // master i AWADDR
  input  logic [NUM_MASTERS-1:0]            M_WVALID,       // master i WVALID
  output logic [NUM_MASTERS-1:0]            M_WREADY,       // master i WREADY
  input  logic [NUM_MASTERS*DATA_W-1:0]     M_WDATA,        // master i WDATA
  input  logic [NUM_MASTERS*DATA_W/8-1:0]   M_WSTRB,        // master i WSTRB
  output logic [NUM_MASTERS-1:0]            M_BVALID,       // master i BVALID
  input  logic [NUM_MASTERS-1:0]            M_BREADY,       // master i BREADY
  output logic [NUM_MASTERS*2-1:0]          M_BRESP,        // master i BRESP
  input  logic [NUM_MASTERS-1:0]            M_ARVALID,      // master i ARVALID
  output logic [NUM_MASTERS-1:0]            M_ARREADY,      // master i ARREADY
  input  logic [NUM_MASTERS*ADDR_W-1:0]     M_ARADDR,       // master i ARADDR
  output logic [NUM_MASTERS-1:0]            M_RVALID,       // master i RVALID
  input  logic [NUM_MASTERS-1:0]            M_RREADY,       // master i RREADY
  output logic [NUM_MASTERS*DATA_W-1:0]     M_RDATA,        // master i RDATA
  output logic [NUM_MASTERS*2-1:0]          M_RRESP,        // master i RRESP

  // Slave ports (the matrix is the AXI4-Lite master)
  output logic [NUM_SLAVES-1:0]             S_AWVALID,      // slave j AWVALID
  input  logic [NUM_SLAVES-1:0]             S_AWREADY,      // slave j AWREADY
  output logic [NUM_SLAVES*ADDR_W-1:0]      S_AWADDR,       // slave j AWADDR
  output logic [NUM_SLAVES-1:0]             S_WVALID,       // slave j WVALID
  input  logic [NUM_SLAVES-1:0]             S_WREADY,       // slave j WREADY
  output logic [NUM_SLAVES*DATA_W-1:0]      S_WDATA,        // slave j WDATA
  output logic [NUM_SLAVES*DATA_W/8-1:0]    S_WSTRB,        // slave j WSTRB
  input  logic [NUM_SLAVES-1:0]             S_BVALID,       // slave j BVALID
  output logic [NUM_SLAVES-1:0]             S_BREADY,       // slave j BREADY
  input  logic [NUM_SLAVES*2-1:0]           S_BRESP,        // slave j BRESP
  output logic [NUM_SLAVES-1:0]             S_ARVALID,      // slave j ARVALID
  input  logic [NUM_SLAVES-1:0]             S_ARREADY,      // slave j ARREADY
  output logic [NUM_SLAVES*ADDR_W-1:0]      S_ARADDR,       // slave j ARADDR
  input  logic [NUM_SLAVES-1:0]             S_RVALID,       // slave j RVALID
  output logic [NUM_SLAVES-1:0]             S_RREADY,       // slave j RREADY
  input  logic [NUM_SLAVES*DATA_W-1:0]      S_RDATA,        // slave j RDATA
  input  logic [NUM_SLAVES*2-1:0]           S_RRESP         // slave j RRESP
);

  localparam int unsigned STRB_W = DATA_W / 8;

  // Core handshake wires
  logic [NUM_MASTERS-1:0]         mst_req;
  logic [NUM_MASTERS*ADDR_W-1:0]  mst_addr;
  logic [NUM_MASTERS*DATA_W-1:0]  mst_wdata;
  logic [NUM_MASTERS-1:0]         mst_we;
  logic [NUM_MASTERS*STRB_W-1:0]  mst_be;
  logic [NUM_MASTERS-1:0]         mst_done;
  logic [NUM_MASTERS*DATA_W-1:0]  mst_rdata;
  logic [NUM_MASTERS-1:0]         mst_err;

  logic [NUM_SLAVES-1:0]          slv_req;
  logic [NUM_SLAVES*ADDR_W-1:0]   slv_addr;
  logic [NUM_SLAVES*DATA_W-1:0]   slv_wdata;
  logic [NUM_SLAVES-1:0]          slv_we;
  logic [NUM_SLAVES*STRB_W-1:0]   slv_be;
  logic [NUM_SLAVES-1:0]          slv_done;
  logic [NUM_SLAVES*DATA_W-1:0]   slv_rdata;
  logic [NUM_SLAVES-1:0]          slv_err;

  // -------------------------------------------------------------------------
  // Master ports
  // -------------------------------------------------------------------------
  for (genvar gi = 0; gi < NUM_MASTERS; gi++) begin : gen_mst
    bus_matrix_axi4l_tgt #(
      .DATA_W (DATA_W),
      .ADDR_W (ADDR_W)
    ) u_tgt (
      .clk        (clk),
      .rst_n      (rst_n),
      .AWVALID    (M_AWVALID[gi]),
      .AWREADY    (M_AWREADY[gi]),
      .AWADDR     (M_AWADDR[gi*ADDR_W+:ADDR_W]),
      .WVALID     (M_WVALID[gi]),
      .WREADY     (M_WREADY[gi]),
      .WDATA      (M_WDATA[gi*DATA_W+:DATA_W]),
      .WSTRB      (M_WSTRB[gi*STRB_W+:STRB_W]),
      .BVALID     (M_BVALID[gi]),
      .BREADY     (M_BREADY[gi]),
      .BRESP      (M_BRESP[gi*2+:2]),
      .ARVALID    (M_ARVALID[gi]),
      .ARREADY    (M_ARREADY[gi]),
      .ARADDR     (M_ARADDR[gi*ADDR_W+:ADDR_W]),
      .RVALID     (M_RVALID[gi]),
      .RREADY     (M_RREADY[gi]),
      .RDATA      (M_RDATA[gi*DATA_W+:DATA_W]),
      .RRESP      (M_RRESP[gi*2+:2]),
      .core_req   (mst_req[gi]),
      .core_addr  (mst_addr[gi*ADDR_W+:ADDR_W]),
      .core_wdata (mst_wdata[gi*DATA_W+:DATA_W]),
      .core_we    (mst_we[gi]),
      .core_be    (mst_be[gi*STRB_W+:STRB_W]),
      .core_done  (mst_done[gi]),
      .core_rdata (mst_rdata[gi*DATA_W+:DATA_W]),
      .core_err   (mst_err[gi])
    );
  end

  // -------------------------------------------------------------------------
  // Slave ports
  // -------------------------------------------------------------------------
  for (genvar gj = 0; gj < NUM_SLAVES; gj++) begin : gen_slv
    bus_matrix_axi4l_ini #(
      .DATA_W (DATA_W),
      .ADDR_W (ADDR_W)
    ) u_ini (
      .clk        (clk),
      .rst_n      (rst_n),
      .core_req   (slv_req[gj]),
      .core_addr  (slv_addr[gj*ADDR_W+:ADDR_W]),
      .core_wdata (slv_wdata[gj*DATA_W+:DATA_W]),
      .core_we    (slv_we[gj]),
      .core_be    (slv_be[gj*STRB_W+:STRB_W]),
      .core_done  (slv_done[gj]),
      .core_rdata (slv_rdata[gj*DATA_W+:DATA_W]),
      .core_err   (slv_err[gj]),
      .AWVALID    (S_AWVALID[gj]),
      .AWREADY    (S_AWREADY[gj]),
      .AWADDR     (S_AWADDR[gj*ADDR_W+:ADDR_W]),
      .WVALID     (S_WVALID[gj]),
      .WREADY     (S_WREADY[gj]),
      .WDATA      (S_WDATA[gj*DATA_W+:DATA_W]),
      .WSTRB      (S_WSTRB[gj*STRB_W+:STRB_W]),
      .BVALID     (S_BVALID[gj]),
      .BREADY     (S_BREADY[gj]),
      .BRESP      (S_BRESP[gj*2+:2]),
      .ARVALID    (S_ARVALID[gj]),
      .ARREADY    (S_ARREADY[gj]),
      .ARADDR     (S_ARADDR[gj*ADDR_W+:ADDR_W]),
      .RVALID     (S_RVALID[gj]),
      .RREADY     (S_RREADY[gj]),
      .RDATA      (S_RDATA[gj*DATA_W+:DATA_W]),
      .RRESP      (S_RRESP[gj*2+:2])
    );
  end

  // -------------------------------------------------------------------------
  // Crossbar core
  // -------------------------------------------------------------------------
  bus_matrix_core #(
    .NUM_MASTERS (NUM_MASTERS),
    .NUM_SLAVES  (NUM_SLAVES),
    .DATA_W      (DATA_W),
    .ADDR_W      (ADDR_W),
    .ARB_MODE    (ARB_MODE),
    .M_PRIORITY  (M_PRIORITY),
    .S_BASE      (S_BASE),
    .S_MASK      (S_MASK)
  ) u_core (
    .clk       (clk),
    .rst_n     (rst_n),
    .mst_req   (mst_req),
    .mst_addr  (mst_addr),
    .mst_wdata (mst_wdata),
    .mst_we    (mst_we),
    .mst_be    (mst_be),
    .mst_done  (mst_done),
    .mst_rdata (mst_rdata),
    .mst_err   (mst_err),
    .slv_req   (slv_req),
    .slv_addr  (slv_addr),
    .slv_wdata (slv_wdata),
    .slv_we    (slv_we),
    .slv_be    (slv_be),
    .slv_done  (slv_done),
    .slv_rdata (slv_rdata),
    .slv_err   (slv_err)
  );

endmodule : bus_matrix_axi4l
