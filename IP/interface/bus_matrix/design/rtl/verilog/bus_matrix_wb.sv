// bus_matrix_wb.sv — Wishbone B4 bus matrix top-level.
//
// Crossbar interconnect connecting NUM_MASTERS Wishbone B4 (classic) masters to
// NUM_SLAVES Wishbone B4 (classic) slaves. All configuration (address map, arbitration
// mode, priorities) is set via elaboration-time parameters; there are no
// runtime registers. The defaults (bus_matrix_pkg) are the synthesized
// configuration.
//
// Structure: one bus_matrix_wb_tgt per master port, one
// bus_matrix_wb_ini per slave port, and the protocol-agnostic
// bus_matrix_core between them. Ports are flat-packed: master i / slave j
// occupy slice [i*W+:W] / [j*W+:W].

module bus_matrix_wb #(
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

  // Master ports (the matrix is the Wishbone B4 slave)
  input  logic [NUM_MASTERS-1:0]            M_CYC,          // master i CYC
  input  logic [NUM_MASTERS-1:0]            M_STB,          // master i STB
  input  logic [NUM_MASTERS-1:0]            M_WE,           // master i WE
  input  logic [NUM_MASTERS*ADDR_W-1:0]     M_ADR,          // master i ADR
  input  logic [NUM_MASTERS*DATA_W-1:0]     M_DAT_I,        // master i DAT_I
  input  logic [NUM_MASTERS*DATA_W/8-1:0]   M_SEL,          // master i SEL
  output logic [NUM_MASTERS*DATA_W-1:0]     M_DAT_O,        // master i DAT_O
  output logic [NUM_MASTERS-1:0]            M_ACK,          // master i ACK
  output logic [NUM_MASTERS-1:0]            M_ERR,          // master i ERR

  // Slave ports (the matrix is the Wishbone B4 master)
  output logic [NUM_SLAVES-1:0]             S_CYC,          // slave j CYC
  output logic [NUM_SLAVES-1:0]             S_STB,          // slave j STB
  output logic [NUM_SLAVES-1:0]             S_WE,           // slave j WE
  output logic [NUM_SLAVES*ADDR_W-1:0]      S_ADR,          // slave j ADR
  output logic [NUM_SLAVES*DATA_W-1:0]      S_DAT_O,        // slave j DAT_O
  output logic [NUM_SLAVES*DATA_W/8-1:0]    S_SEL,          // slave j SEL
  input  logic [NUM_SLAVES*DATA_W-1:0]      S_DAT_I,        // slave j DAT_I
  input  logic [NUM_SLAVES-1:0]             S_ACK,          // slave j ACK
  input  logic [NUM_SLAVES-1:0]             S_ERR           // slave j ERR
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
    bus_matrix_wb_tgt #(
      .DATA_W (DATA_W),
      .ADDR_W (ADDR_W)
    ) u_tgt (
      .CYC        (M_CYC[gi]),
      .STB        (M_STB[gi]),
      .WE         (M_WE[gi]),
      .ADR        (M_ADR[gi*ADDR_W+:ADDR_W]),
      .DAT_W      (M_DAT_I[gi*DATA_W+:DATA_W]),
      .SEL        (M_SEL[gi*STRB_W+:STRB_W]),
      .DAT_R      (M_DAT_O[gi*DATA_W+:DATA_W]),
      .ACK        (M_ACK[gi]),
      .ERR        (M_ERR[gi]),
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
    bus_matrix_wb_ini #(
      .DATA_W (DATA_W),
      .ADDR_W (ADDR_W)
    ) u_ini (
      .core_req   (slv_req[gj]),
      .core_addr  (slv_addr[gj*ADDR_W+:ADDR_W]),
      .core_wdata (slv_wdata[gj*DATA_W+:DATA_W]),
      .core_we    (slv_we[gj]),
      .core_be    (slv_be[gj*STRB_W+:STRB_W]),
      .core_done  (slv_done[gj]),
      .core_rdata (slv_rdata[gj*DATA_W+:DATA_W]),
      .core_err   (slv_err[gj]),
      .CYC        (S_CYC[gj]),
      .STB        (S_STB[gj]),
      .WE         (S_WE[gj]),
      .ADR        (S_ADR[gj*ADDR_W+:ADDR_W]),
      .DAT_W      (S_DAT_O[gj*DATA_W+:DATA_W]),
      .SEL        (S_SEL[gj*STRB_W+:STRB_W]),
      .DAT_R      (S_DAT_I[gj*DATA_W+:DATA_W]),
      .ACK        (S_ACK[gj]),
      .ERR        (S_ERR[gj])
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

endmodule : bus_matrix_wb
