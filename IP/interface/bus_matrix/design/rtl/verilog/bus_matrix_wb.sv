// bus_matrix_wb.sv — Wishbone B4 bus matrix top-level.
//
// Crossbar interconnect connecting NUM_MASTERS Wishbone masters to NUM_SLAVES
// Wishbone slaves. All configuration is set via elaboration-time parameters;
// there are no runtime registers or admin bus ports.

module bus_matrix_wb #(
  parameter int NUM_MASTERS = 2,                             // 1-16 active masters
  parameter int NUM_SLAVES  = 2,                             // 1-32 active slaves
  parameter int DATA_W      = 32,                            // data bus width
  parameter int ADDR_W      = 32,                            // address width
  parameter int ARB_MODE    = 0,                             // 0=fixed-priority, 1=round-robin
  parameter logic [NUM_MASTERS*4-1:0]  M_PRIORITY = '0,     // master i priority [i*4+:4]
  parameter logic [NUM_SLAVES*32-1:0]  S_BASE     = '0,     // slave j base addr [j*32+:32]
  parameter logic [NUM_SLAVES*32-1:0]  S_MASK     = '0      // slave j addr mask [j*32+:32]
) (
  input  logic              clk,   // system clock
  input  logic              rst_n, // synchronous active-low reset

  // -----------------------------------------------------------------------
  // Master input ports (NUM_MASTERS active) — Wishbone B4 slave-facing
  // Flat-packed: master i signals at bit slice [i*W+:W]
  // -----------------------------------------------------------------------
  input  logic [NUM_MASTERS-1:0]          M_CYC,   // master i CYC
  input  logic [NUM_MASTERS-1:0]          M_STB,   // master i STB
  input  logic [NUM_MASTERS-1:0]          M_WE,    // master i WE
  input  logic [NUM_MASTERS*ADDR_W-1:0]   M_ADR,   // master i ADR [i*ADDR_W+:ADDR_W]
  input  logic [NUM_MASTERS*DATA_W-1:0]   M_DAT_I, // master i write data
  input  logic [NUM_MASTERS*4-1:0]        M_SEL,   // master i byte select [i*4+:4]
  output logic [NUM_MASTERS*DATA_W-1:0]   M_DAT_O, // master i read data
  output logic [NUM_MASTERS-1:0]          M_ACK,   // master i acknowledge
  output logic [NUM_MASTERS-1:0]          M_ERR,   // master i error

  // -----------------------------------------------------------------------
  // Slave output ports (NUM_SLAVES active) — Wishbone B4 master-facing
  // Flat-packed: slave j signals at bit slice [j*W+:W]
  // -----------------------------------------------------------------------
  output logic [NUM_SLAVES-1:0]           S_CYC,   // slave j CYC
  output logic [NUM_SLAVES-1:0]           S_STB,   // slave j STB
  output logic [NUM_SLAVES-1:0]           S_WE,    // slave j WE
  output logic [NUM_SLAVES*ADDR_W-1:0]    S_ADR,   // slave j ADR [j*ADDR_W+:ADDR_W]
  output logic [NUM_SLAVES*DATA_W-1:0]    S_DAT_O, // slave j write data
  output logic [NUM_SLAVES*4-1:0]         S_SEL,   // slave j byte select [j*4+:4]
  input  logic [NUM_SLAVES*DATA_W-1:0]    S_DAT_I, // slave j read data
  input  logic [NUM_SLAVES-1:0]           S_ACK,   // slave j acknowledge
  input  logic [NUM_SLAVES-1:0]           S_ERR    // slave j error
);

  // -------------------------------------------------------------------------
  // Internal protocol wires
  // -------------------------------------------------------------------------
  logic [NUM_MASTERS-1:0]         mst_req;
  logic [NUM_MASTERS*ADDR_W-1:0]  mst_addr;
  logic [NUM_MASTERS*DATA_W-1:0]  mst_wdata;
  logic [NUM_MASTERS-1:0]         mst_we;
  logic [NUM_MASTERS*4-1:0]       mst_be;
  logic [NUM_MASTERS-1:0]         mst_gnt;
  logic [NUM_MASTERS*DATA_W-1:0]  mst_rdata;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [NUM_MASTERS-1:0]         mst_rvalid;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [NUM_MASTERS-1:0]         mst_err;

  logic [NUM_SLAVES-1:0]          slv_req;
  logic [NUM_SLAVES*ADDR_W-1:0]   slv_addr;
  logic [NUM_SLAVES*DATA_W-1:0]   slv_wdata;
  logic [NUM_SLAVES-1:0]          slv_we;
  logic [NUM_SLAVES*4-1:0]        slv_be;
  logic [NUM_SLAVES-1:0]          slv_gnt;
  logic [NUM_SLAVES*DATA_W-1:0]   slv_rdata;
  logic [NUM_SLAVES-1:0]          slv_rvalid;

  // -------------------------------------------------------------------------
  // Wishbone master-side adapter (per master)
  // Transaction: CYC+STB asserted → mst_req; ACK → mst_gnt
  // -------------------------------------------------------------------------
  logic [NUM_MASTERS-1:0] wb_stb_prev_q;
  logic [NUM_MASTERS-1:0] wb_pending_q;

  genvar gi;
  generate
    for (gi = 0; gi < NUM_MASTERS; gi = gi + 1) begin : gen_mst_wb
      always_ff @(posedge clk) begin : p_mst_wb
        if (!rst_n) begin
          wb_stb_prev_q[gi] <= 1'b0;
          wb_pending_q[gi]  <= 1'b0;
        end else begin
          wb_stb_prev_q[gi] <= M_CYC[gi] & M_STB[gi] & ~wb_stb_prev_q[gi];
          if (M_CYC[gi] && M_STB[gi] && !wb_stb_prev_q[gi])
            wb_pending_q[gi] <= 1'b1;
          else if (mst_gnt[gi])
            wb_pending_q[gi] <= 1'b0;
        end
      end

      assign mst_req[gi]                   = wb_pending_q[gi];
      assign mst_addr[gi*ADDR_W+:ADDR_W]  = M_ADR[gi*ADDR_W+:ADDR_W];
      assign mst_wdata[gi*DATA_W+:DATA_W] = M_DAT_I[gi*DATA_W+:DATA_W];
      assign mst_we[gi]                   = M_WE[gi];
      assign mst_be[gi*4+:4]              = M_SEL[gi*4+:4];

      assign M_ACK[gi]                     = mst_gnt[gi];
      assign M_ERR[gi]                     = mst_err[gi];
      assign M_DAT_O[gi*DATA_W+:DATA_W]   = mst_rdata[gi*DATA_W+:DATA_W];
    end
  endgenerate

  // -------------------------------------------------------------------------
  // Wishbone slave-side adapter (per slave)
  // -------------------------------------------------------------------------
  generate
    for (gi = 0; gi < NUM_SLAVES; gi = gi + 1) begin : gen_slv_wb
      assign S_CYC[gi]                     = slv_req[gi];
      assign S_STB[gi]                     = slv_req[gi];
      assign S_WE[gi]                      = slv_we[gi];
      assign S_ADR[gi*ADDR_W+:ADDR_W]     = slv_addr[gi*ADDR_W+:ADDR_W];
      assign S_DAT_O[gi*DATA_W+:DATA_W]   = slv_wdata[gi*DATA_W+:DATA_W];
      assign S_SEL[gi*4+:4]               = slv_be[gi*4+:4];

      assign slv_gnt[gi]                   = S_ACK[gi];
      assign slv_rdata[gi*DATA_W+:DATA_W]  = S_DAT_I[gi*DATA_W+:DATA_W];
      assign slv_rvalid[gi]                = S_ACK[gi] & ~slv_we[gi];

      /* verilator lint_off UNUSED */
      logic unused_slv_err;
      assign unused_slv_err = S_ERR[gi];
      /* verilator lint_on UNUSED */
    end
  endgenerate

  // -------------------------------------------------------------------------
  // Bus matrix core
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
    .clk        (clk),
    .rst_n      (rst_n),
    .mst_req    (mst_req),
    .mst_addr   (mst_addr),
    .mst_wdata  (mst_wdata),
    .mst_we     (mst_we),
    .mst_be     (mst_be),
    .mst_gnt    (mst_gnt),
    .mst_rdata  (mst_rdata),
    .mst_rvalid (mst_rvalid),
    .mst_err    (mst_err),
    .slv_req    (slv_req),
    .slv_addr   (slv_addr),
    .slv_wdata  (slv_wdata),
    .slv_we     (slv_we),
    .slv_be     (slv_be),
    .slv_gnt    (slv_gnt),
    .slv_rdata  (slv_rdata),
    .slv_rvalid (slv_rvalid)
  );

endmodule : bus_matrix_wb
