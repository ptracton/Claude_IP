// bus_matrix_apb.sv — APB4 bus matrix top-level.
//
// Crossbar interconnect connecting NUM_MASTERS APB4 masters to
// NUM_SLAVES APB4 slaves. All configuration (address map, arbitration
// mode, priorities) is set via elaboration-time parameters; there are no
// runtime registers. The defaults (bus_matrix_pkg) are the synthesized
// configuration.
//
// Structure: one bus_matrix_apb_tgt per master port, one
// bus_matrix_apb_ini per slave port, and the protocol-agnostic
// bus_matrix_core between them. Ports are flat-packed: master i / slave j
// occupy slice [i*W+:W] / [j*W+:W].

module bus_matrix_apb #(
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

  // Master ports (the matrix is the APB4 slave)
  input  logic [NUM_MASTERS-1:0]            M_PSEL,         // master i PSEL
  input  logic [NUM_MASTERS-1:0]            M_PENABLE,      // master i PENABLE
  input  logic [NUM_MASTERS*ADDR_W-1:0]     M_PADDR,        // master i PADDR
  input  logic [NUM_MASTERS-1:0]            M_PWRITE,       // master i PWRITE
  input  logic [NUM_MASTERS*DATA_W-1:0]     M_PWDATA,       // master i PWDATA
  input  logic [NUM_MASTERS*DATA_W/8-1:0]   M_PSTRB,        // master i PSTRB
  output logic [NUM_MASTERS*DATA_W-1:0]     M_PRDATA,       // master i PRDATA
  output logic [NUM_MASTERS-1:0]            M_PREADY,       // master i PREADY
  output logic [NUM_MASTERS-1:0]            M_PSLVERR,      // master i PSLVERR

  // Slave ports (the matrix is the APB4 master)
  output logic [NUM_SLAVES-1:0]             S_PSEL,         // slave j PSEL
  output logic [NUM_SLAVES-1:0]             S_PENABLE,      // slave j PENABLE
  output logic [NUM_SLAVES*ADDR_W-1:0]      S_PADDR,        // slave j PADDR
  output logic [NUM_SLAVES-1:0]             S_PWRITE,       // slave j PWRITE
  output logic [NUM_SLAVES*DATA_W-1:0]      S_PWDATA,       // slave j PWDATA
  output logic [NUM_SLAVES*DATA_W/8-1:0]    S_PSTRB,        // slave j PSTRB
  input  logic [NUM_SLAVES*DATA_W-1:0]      S_PRDATA,       // slave j PRDATA
  input  logic [NUM_SLAVES-1:0]             S_PREADY,       // slave j PREADY
  input  logic [NUM_SLAVES-1:0]             S_PSLVERR       // slave j PSLVERR
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
  genvar gi, gj;
  generate
    for (gi = 0; gi < NUM_MASTERS; gi++) begin : gen_mst
      bus_matrix_apb_tgt #(
        .DATA_W (DATA_W),
        .ADDR_W (ADDR_W)
      ) u_tgt (
        .PSEL       (M_PSEL[gi]),
        .PENABLE    (M_PENABLE[gi]),
        .PADDR      (M_PADDR[gi*ADDR_W+:ADDR_W]),
        .PWRITE     (M_PWRITE[gi]),
        .PWDATA     (M_PWDATA[gi*DATA_W+:DATA_W]),
        .PSTRB      (M_PSTRB[gi*STRB_W+:STRB_W]),
        .PRDATA     (M_PRDATA[gi*DATA_W+:DATA_W]),
        .PREADY     (M_PREADY[gi]),
        .PSLVERR    (M_PSLVERR[gi]),
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
  endgenerate

  // -------------------------------------------------------------------------
  // Slave ports
  // -------------------------------------------------------------------------
  generate
    for (gj = 0; gj < NUM_SLAVES; gj++) begin : gen_slv
      bus_matrix_apb_ini #(
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
        .PSEL       (S_PSEL[gj]),
        .PENABLE    (S_PENABLE[gj]),
        .PADDR      (S_PADDR[gj*ADDR_W+:ADDR_W]),
        .PWRITE     (S_PWRITE[gj]),
        .PWDATA     (S_PWDATA[gj*DATA_W+:DATA_W]),
        .PSTRB      (S_PSTRB[gj*STRB_W+:STRB_W]),
        .PRDATA     (S_PRDATA[gj*DATA_W+:DATA_W]),
        .PREADY     (S_PREADY[gj]),
        .PSLVERR    (S_PSLVERR[gj])
      );
    end
  endgenerate

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

endmodule : bus_matrix_apb
