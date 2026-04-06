// bus_matrix_axi.sv — AXI4-Lite bus matrix top-level.
//
// Crossbar interconnect connecting NUM_MASTERS AXI4-Lite masters to NUM_SLAVES
// AXI4-Lite slaves. All configuration is set via elaboration-time parameters;
// there are no runtime registers or admin bus ports.
//
// One outstanding transaction per master port supported.
// Write: AW+W presented together → mst_req, wait for mst_gnt → BVALID.
// Read:  AR → mst_req, wait for mst_rvalid → RVALID+RDATA.

module bus_matrix_axi #(
  parameter int NUM_MASTERS = 2,                             // 1-16 active masters
  parameter int NUM_SLAVES  = 2,                             // 1-32 active slaves
  parameter int DATA_W      = 32,                            // data bus width (32 for AXI4-Lite)
  parameter int ADDR_W      = 32,                            // address width
  parameter int ARB_MODE    = 0,                             // 0=fixed-priority, 1=round-robin
  parameter logic [NUM_MASTERS*4-1:0]  M_PRIORITY = '0,     // master i priority [i*4+:4]
  parameter logic [NUM_SLAVES*32-1:0]  S_BASE     = '0,     // slave j base addr [j*32+:32]
  parameter logic [NUM_SLAVES*32-1:0]  S_MASK     = '0      // slave j addr mask [j*32+:32]
) (
  input  logic              clk,   // system clock
  input  logic              rst_n, // synchronous active-low reset

  // -----------------------------------------------------------------------
  // Master input ports (NUM_MASTERS active) — AXI4-Lite slave-facing
  // Flat-packed: master i signals at bit slice [i*W+:W]
  // -----------------------------------------------------------------------
  // Write address channel
  input  logic [NUM_MASTERS-1:0]          M_AWVALID,
  output logic [NUM_MASTERS-1:0]          M_AWREADY,
  input  logic [NUM_MASTERS*ADDR_W-1:0]   M_AWADDR,
  // Write data channel
  input  logic [NUM_MASTERS-1:0]          M_WVALID,
  output logic [NUM_MASTERS-1:0]          M_WREADY,
  input  logic [NUM_MASTERS*DATA_W-1:0]   M_WDATA,
  input  logic [NUM_MASTERS*4-1:0]        M_WSTRB,
  // Write response channel
  output logic [NUM_MASTERS-1:0]          M_BVALID,
  input  logic [NUM_MASTERS-1:0]          M_BREADY,
  output logic [NUM_MASTERS*2-1:0]        M_BRESP,
  // Read address channel
  input  logic [NUM_MASTERS-1:0]          M_ARVALID,
  output logic [NUM_MASTERS-1:0]          M_ARREADY,
  input  logic [NUM_MASTERS*ADDR_W-1:0]   M_ARADDR,
  // Read data channel
  output logic [NUM_MASTERS-1:0]          M_RVALID,
  input  logic [NUM_MASTERS-1:0]          M_RREADY,
  output logic [NUM_MASTERS*DATA_W-1:0]   M_RDATA,
  output logic [NUM_MASTERS*2-1:0]        M_RRESP,

  // -----------------------------------------------------------------------
  // Slave output ports (NUM_SLAVES active) — AXI4-Lite master-facing
  // Flat-packed: slave j signals at bit slice [j*W+:W]
  // -----------------------------------------------------------------------
  // Write address channel
  output logic [NUM_SLAVES-1:0]           S_AWVALID,
  input  logic [NUM_SLAVES-1:0]           S_AWREADY,
  output logic [NUM_SLAVES*ADDR_W-1:0]    S_AWADDR,
  // Write data channel
  output logic [NUM_SLAVES-1:0]           S_WVALID,
  input  logic [NUM_SLAVES-1:0]           S_WREADY,
  output logic [NUM_SLAVES*DATA_W-1:0]    S_WDATA,
  output logic [NUM_SLAVES*4-1:0]         S_WSTRB,
  // Write response channel
  input  logic [NUM_SLAVES-1:0]           S_BVALID,
  output logic [NUM_SLAVES-1:0]           S_BREADY,
  input  logic [NUM_SLAVES*2-1:0]         S_BRESP,
  // Read address channel
  output logic [NUM_SLAVES-1:0]           S_ARVALID,
  input  logic [NUM_SLAVES-1:0]           S_ARREADY,
  output logic [NUM_SLAVES*ADDR_W-1:0]    S_ARADDR,
  // Read data channel
  input  logic [NUM_SLAVES-1:0]           S_RVALID,
  output logic [NUM_SLAVES-1:0]           S_RREADY,
  input  logic [NUM_SLAVES*DATA_W-1:0]    S_RDATA,
  input  logic [NUM_SLAVES*2-1:0]         S_RRESP
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
  logic [NUM_MASTERS-1:0]         mst_rvalid;
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
  // AXI4-Lite master-side adapter registers (one per master)
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] {
    AXI_MST_IDLE  = 2'b00,
    AXI_MST_WRITE = 2'b01,
    AXI_MST_READ  = 2'b10
  } axi_mst_state_t;

  axi_mst_state_t axi_mst_state_q [0:NUM_MASTERS-1];
  logic [ADDR_W-1:0] axi_mst_addr_q  [0:NUM_MASTERS-1];
  logic [DATA_W-1:0] axi_mst_wdata_q [0:NUM_MASTERS-1];
  logic [3:0]        axi_mst_strb_q  [0:NUM_MASTERS-1];
  logic              axi_bvalid_q    [0:NUM_MASTERS-1];
  logic              axi_rvalid_q    [0:NUM_MASTERS-1];
  logic [DATA_W-1:0] axi_rdata_q     [0:NUM_MASTERS-1];

  genvar gi;
  generate
    for (gi = 0; gi < NUM_MASTERS; gi = gi + 1) begin : gen_mst_axi
      always_ff @(posedge clk) begin : p_mst_axi
        if (!rst_n) begin
          axi_mst_state_q[gi] <= AXI_MST_IDLE;
          axi_mst_addr_q[gi]  <= {ADDR_W{1'b0}};
          axi_mst_wdata_q[gi] <= {DATA_W{1'b0}};
          axi_mst_strb_q[gi]  <= 4'h0;
          axi_bvalid_q[gi]    <= 1'b0;
          axi_rvalid_q[gi]    <= 1'b0;
          axi_rdata_q[gi]     <= {DATA_W{1'b0}};
        end else begin
          case (axi_mst_state_q[gi])
            AXI_MST_IDLE: begin
              axi_bvalid_q[gi] <= 1'b0;
              axi_rvalid_q[gi] <= 1'b0;
              if (M_AWVALID[gi] && M_WVALID[gi]) begin
                axi_mst_state_q[gi] <= AXI_MST_WRITE;
                axi_mst_addr_q[gi]  <= M_AWADDR[gi*ADDR_W+:ADDR_W];
                axi_mst_wdata_q[gi] <= M_WDATA[gi*DATA_W+:DATA_W];
                axi_mst_strb_q[gi]  <= M_WSTRB[gi*4+:4];
              end else if (M_ARVALID[gi]) begin
                axi_mst_state_q[gi] <= AXI_MST_READ;
                axi_mst_addr_q[gi]  <= M_ARADDR[gi*ADDR_W+:ADDR_W];
              end
            end

            AXI_MST_WRITE: begin
              if (mst_gnt[gi]) begin
                axi_bvalid_q[gi]    <= 1'b1;
                axi_mst_state_q[gi] <= AXI_MST_IDLE;
              end
              if (axi_bvalid_q[gi] && M_BREADY[gi])
                axi_bvalid_q[gi] <= 1'b0;
            end

            AXI_MST_READ: begin
              if (mst_rvalid[gi]) begin
                axi_rvalid_q[gi]    <= 1'b1;
                axi_rdata_q[gi]     <= mst_rdata[gi*DATA_W+:DATA_W];
                axi_mst_state_q[gi] <= AXI_MST_IDLE;
              end
              if (axi_rvalid_q[gi] && M_RREADY[gi])
                axi_rvalid_q[gi] <= 1'b0;
            end

            default: axi_mst_state_q[gi] <= AXI_MST_IDLE;
          endcase
        end
      end

      assign mst_req[gi]                   = (axi_mst_state_q[gi] != AXI_MST_IDLE);
      assign mst_addr[gi*ADDR_W+:ADDR_W]  = axi_mst_addr_q[gi];
      assign mst_wdata[gi*DATA_W+:DATA_W] = axi_mst_wdata_q[gi];
      assign mst_we[gi]                   = (axi_mst_state_q[gi] == AXI_MST_WRITE);
      assign mst_be[gi*4+:4]              = axi_mst_strb_q[gi];

      assign M_AWREADY[gi]                = (axi_mst_state_q[gi] == AXI_MST_IDLE);
      assign M_WREADY[gi]                 = (axi_mst_state_q[gi] == AXI_MST_IDLE);
      assign M_ARREADY[gi]                = (axi_mst_state_q[gi] == AXI_MST_IDLE) && !M_AWVALID[gi];
      assign M_BVALID[gi]                 = axi_bvalid_q[gi];
      assign M_BRESP[gi*2+:2]             = 2'b00; // OKAY
      assign M_RVALID[gi]                 = axi_rvalid_q[gi];
      assign M_RDATA[gi*DATA_W+:DATA_W]   = axi_rdata_q[gi];
      assign M_RRESP[gi*2+:2]             = mst_err[gi] ? 2'b10 : 2'b00;
    end
  endgenerate

  // -------------------------------------------------------------------------
  // AXI4-Lite slave-side adapter (per slave)
  // -------------------------------------------------------------------------
  generate
    for (gi = 0; gi < NUM_SLAVES; gi = gi + 1) begin : gen_slv_axi
      assign S_AWVALID[gi]                 = slv_req[gi] & slv_we[gi];
      assign S_AWADDR[gi*ADDR_W+:ADDR_W]  = slv_addr[gi*ADDR_W+:ADDR_W];
      assign S_WVALID[gi]                  = slv_req[gi] & slv_we[gi];
      assign S_WDATA[gi*DATA_W+:DATA_W]   = slv_wdata[gi*DATA_W+:DATA_W];
      assign S_WSTRB[gi*4+:4]             = slv_be[gi*4+:4];
      assign S_BREADY[gi]                  = 1'b1;

      assign S_ARVALID[gi]                 = slv_req[gi] & ~slv_we[gi];
      assign S_ARADDR[gi*ADDR_W+:ADDR_W]  = slv_addr[gi*ADDR_W+:ADDR_W];
      assign S_RREADY[gi]                  = 1'b1;

      // slv_gnt: transaction-completion signal per protocol spec
      assign slv_gnt[gi]                   = slv_we[gi] ? S_BVALID[gi] : S_RVALID[gi];
      assign slv_rdata[gi*DATA_W+:DATA_W]  = S_RDATA[gi*DATA_W+:DATA_W];
      assign slv_rvalid[gi]                = S_RVALID[gi];

      /* verilator lint_off UNUSED */
      logic unused_slv_resp;
      assign unused_slv_resp = (^S_BRESP[gi*2+:2]) ^ (^S_RRESP[gi*2+:2]) ^
                                S_AWREADY[gi] ^ S_WREADY[gi] ^ S_ARREADY[gi];
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

endmodule : bus_matrix_axi
