// bus_matrix_ahb.sv — AHB-Lite bus matrix top-level.
//
// Crossbar interconnect connecting NUM_MASTERS AHB masters to NUM_SLAVES
// AHB slaves. All configuration (address map, arbitration mode, priorities)
// is set via elaboration-time parameters; there are no runtime registers or
// admin bus ports.
//
// Inline AHB-Lite adapter converts master/slave AHB protocol to/from the
// internal flat-packed request/grant protocol used by bus_matrix_core.

module bus_matrix_ahb #(
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
  // Master input ports (NUM_MASTERS active)
  // Flat-packed: master i signals at bit slice [i*W+:W]
  // -----------------------------------------------------------------------
  input  logic [NUM_MASTERS-1:0]          M_HSEL,   // master i HSEL
  input  logic [NUM_MASTERS*ADDR_W-1:0]   M_HADDR,  // master i HADDR
  input  logic [NUM_MASTERS*2-1:0]        M_HTRANS, // master i HTRANS [i*2+:2]
  input  logic [NUM_MASTERS-1:0]          M_HWRITE, // master i HWRITE
  input  logic [NUM_MASTERS*DATA_W-1:0]   M_HWDATA, // master i HWDATA
  input  logic [NUM_MASTERS*4-1:0]        M_HWSTRB, // master i HWSTRB [i*4+:4]
  output logic [NUM_MASTERS-1:0]          M_HREADY, // master i HREADY
  output logic [NUM_MASTERS*DATA_W-1:0]   M_HRDATA, // master i HRDATA
  output logic [NUM_MASTERS-1:0]          M_HRESP,  // master i HRESP

  // -----------------------------------------------------------------------
  // Slave output ports (NUM_SLAVES active)
  // Flat-packed: slave j signals at bit slice [j*W+:W]
  // -----------------------------------------------------------------------
  output logic [NUM_SLAVES-1:0]           S_HSEL,   // slave j HSEL
  output logic [NUM_SLAVES*ADDR_W-1:0]    S_HADDR,  // slave j HADDR
  output logic [NUM_SLAVES*2-1:0]         S_HTRANS, // slave j HTRANS [j*2+:2]
  output logic [NUM_SLAVES-1:0]           S_HWRITE, // slave j HWRITE
  output logic [NUM_SLAVES*DATA_W-1:0]    S_HWDATA, // slave j HWDATA
  output logic [NUM_SLAVES*4-1:0]         S_HWSTRB, // slave j HWSTRB [j*4+:4]
  input  logic [NUM_SLAVES-1:0]           S_HREADY, // slave j HREADY
  input  logic [NUM_SLAVES*DATA_W-1:0]    S_HRDATA, // slave j HRDATA
  input  logic [NUM_SLAVES-1:0]           S_HRESP   // slave j HRESP
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
  // AHB master-side adapter registers
  // -------------------------------------------------------------------------
  logic [ADDR_W-1:0] ahb_addr_q  [0:NUM_MASTERS-1];
  logic              ahb_write_q [0:NUM_MASTERS-1];
  logic [3:0]        ahb_strb_q  [0:NUM_MASTERS-1];
  logic              ahb_active_q[0:NUM_MASTERS-1];

  localparam logic [1:0] AHB_NONSEQ = 2'b10;
  localparam logic [1:0] AHB_IDLE   = 2'b00;

  genvar gi;
  generate
    for (gi = 0; gi < NUM_MASTERS; gi = gi + 1) begin : gen_mst_adapt
      always_ff @(posedge clk) begin : p_mst_capture
        if (!rst_n) begin
          ahb_addr_q[gi]   <= {ADDR_W{1'b0}};
          ahb_write_q[gi]  <= 1'b0;
          ahb_strb_q[gi]   <= 4'h0;
          ahb_active_q[gi] <= 1'b0;
        end else begin
          if (M_HSEL[gi] && (M_HTRANS[gi*2+:2] == AHB_NONSEQ) && !ahb_active_q[gi]) begin
            ahb_addr_q[gi]   <= M_HADDR[gi*ADDR_W+:ADDR_W];
            ahb_write_q[gi]  <= M_HWRITE[gi];
            ahb_strb_q[gi]   <= M_HWSTRB[gi*4+:4];
            ahb_active_q[gi] <= 1'b1;
          end else if (mst_gnt[gi]) begin
            ahb_active_q[gi] <= 1'b0;
          end
        end
      end

      assign mst_req[gi]                   = ahb_active_q[gi];
      assign mst_addr[gi*ADDR_W+:ADDR_W]  = ahb_addr_q[gi];
      assign mst_wdata[gi*DATA_W+:DATA_W] = M_HWDATA[gi*DATA_W+:DATA_W];
      assign mst_we[gi]                   = ahb_write_q[gi];
      assign mst_be[gi*4+:4]              = ahb_strb_q[gi];

      assign M_HREADY[gi]                 = mst_gnt[gi] | ~mst_req[gi];
      assign M_HRDATA[gi*DATA_W+:DATA_W]  = mst_rdata[gi*DATA_W+:DATA_W];
      assign M_HRESP[gi]                  = mst_err[gi];
    end
  endgenerate

  // -------------------------------------------------------------------------
  // AHB slave-side adapter
  // -------------------------------------------------------------------------
  generate
    for (gi = 0; gi < NUM_SLAVES; gi = gi + 1) begin : gen_slv_adapt
      assign S_HSEL[gi]                   = slv_req[gi];
      assign S_HTRANS[gi*2+:2]            = slv_req[gi] ? AHB_NONSEQ : AHB_IDLE;
      assign S_HADDR[gi*ADDR_W+:ADDR_W]   = slv_addr[gi*ADDR_W+:ADDR_W];
      assign S_HWRITE[gi]                  = slv_we[gi];
      assign S_HWSTRB[gi*4+:4]            = slv_be[gi*4+:4];
      assign S_HWDATA[gi*DATA_W+:DATA_W]  = slv_wdata[gi*DATA_W+:DATA_W];

      assign slv_gnt[gi]                   = S_HREADY[gi];
      assign slv_rdata[gi*DATA_W+:DATA_W]  = S_HRDATA[gi*DATA_W+:DATA_W];
      assign slv_rvalid[gi]                = S_HREADY[gi] & ~slv_we[gi];

      /* verilator lint_off UNUSED */
      logic unused_slv_hresp;
      assign unused_slv_hresp = S_HRESP[gi];
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

endmodule : bus_matrix_ahb
