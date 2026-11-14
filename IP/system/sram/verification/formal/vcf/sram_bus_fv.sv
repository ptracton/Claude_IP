// sram_bus_fv.sv — Bus-port checkers of the top-level formal jobs
// (sram_apb / sram_ahb / sram_axi4l / sram_wb), bound by sram_<proto>_fv_bind.
//
// Each wraps the shared claude_<proto>_fv (IP/common) with MASTER_IS_ENV = 1:
// the solver plays a legal bus master, and the SRAM top-level (adapter and
// core together) must obey every slave rule, answering within MAX_WAIT
// cycles. The response bound relies on the core checker's environment rule
// (side band quiet while the core port is busy, sram_core_fv).
// AHB also needs what the shared checker has no pins for: a single-slave bus
// (HREADY = HREADYOUT), and legal, aligned HSIZE (as the adapter's own
// harness in IP/common/verification/mem_if/formal assumes).
// Ports only (bind-friendly for SV and VHDL top-levels).

module sram_apb_bus_fv #(
  parameter int unsigned ADDR_W   = 8,
  parameter int unsigned WIDTH    = 32,
  parameter int unsigned MAX_WAIT = 64
) (
  input  logic                PCLK,
  input  logic                PRESETn,
  input  logic                PSEL,
  input  logic                PENABLE,
  input  logic [ADDR_W-1:0]   PADDR,
  input  logic                PWRITE,
  input  logic [WIDTH-1:0]    PWDATA,
  input  logic [WIDTH/8-1:0]  PSTRB,
  input  logic [WIDTH-1:0]    PRDATA,
  input  logic                PREADY,
  input  logic                PSLVERR
);
  logic                obs_wr_vld, obs_wr_busy, obs_rd_req, obs_rd_vld;
  logic [ADDR_W-3:0]   obs_wr_addr, obs_rd_addr;
  logic [WIDTH-1:0]    obs_wr_data, obs_rd_data;
  logic [WIDTH/8-1:0]  obs_wr_strb;

  claude_apb_fv #(
    .DATA_W(WIDTH), .ADDR_W(ADDR_W-2), .PADDR_W(ADDR_W), .MASTER_IS_ENV(1), .MAX_WAIT(MAX_WAIT)
  ) u_bus (
    .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PENABLE(PENABLE), .PADDR(PADDR),
    .PWRITE(PWRITE), .PWDATA(PWDATA), .PSTRB(PSTRB), .PRDATA(PRDATA), .PREADY(PREADY),
    .PSLVERR(PSLVERR),
    .obs_wr_vld(obs_wr_vld), .obs_wr_addr(obs_wr_addr), .obs_wr_data(obs_wr_data),
    .obs_wr_strb(obs_wr_strb), .obs_wr_busy(obs_wr_busy), .obs_rd_req(obs_rd_req),
    .obs_rd_vld(obs_rd_vld), .obs_rd_addr(obs_rd_addr), .obs_rd_data(obs_rd_data)
  );
endmodule : sram_apb_bus_fv

module sram_ahb_bus_fv #(
  parameter int unsigned ADDR_W   = 8,
  parameter int unsigned WIDTH    = 32,
  parameter int unsigned MAX_WAIT = 64
) (
  input  logic                HCLK,
  input  logic                HRESETn,
  input  logic                HSEL,
  input  logic [ADDR_W-1:0]   HADDR,
  input  logic [1:0]          HTRANS,
  input  logic                HWRITE,
  input  logic [2:0]          HSIZE,
  input  logic [WIDTH-1:0]    HWDATA,
  input  logic [WIDTH/8-1:0]  HWSTRB,
  input  logic                HREADY,
  input  logic [WIDTH-1:0]    HRDATA,
  input  logic                HREADYOUT,
  input  logic                HRESP
);
  localparam int unsigned MaxSize = $clog2(WIDTH / 8);

  default clocking cb @(posedge HCLK); endclocking
  default disable iff (!HRESETn);

  logic aphase;
  assign aphase = HSEL && HTRANS[1];

  am_single_slave: assume property (HREADY == HREADYOUT);
  am_size_legal:   assume property (aphase |-> HSIZE <= 3'(MaxSize));
  am_addr_aligned: assume property (aphase |->
                     ((HADDR & ((ADDR_W'(1) << HSIZE) - ADDR_W'(1))) == '0));

  logic                obs_wr_vld, obs_wr_busy, obs_rd_req, obs_rd_vld;
  logic [ADDR_W-3:0]   obs_wr_addr, obs_rd_addr;
  logic [WIDTH-1:0]    obs_wr_data, obs_rd_data;
  logic [WIDTH/8-1:0]  obs_wr_strb;

  claude_ahb_fv #(
    .DATA_W(WIDTH), .ADDR_W(ADDR_W-2), .HADDR_W(ADDR_W), .MASTER_IS_ENV(1),
    .SINGLE_ONLY(0), .MAX_WAIT(MAX_WAIT)
  ) u_bus (
    .HCLK(HCLK), .HRESETn(HRESETn), .HSEL(HSEL), .HADDR(HADDR), .HTRANS(HTRANS),
    .HWRITE(HWRITE), .HWDATA(HWDATA), .HWSTRB(HWSTRB), .HRDATA(HRDATA),
    .HREADY(HREADYOUT), .HRESP(HRESP),
    .obs_wr_vld(obs_wr_vld), .obs_wr_addr(obs_wr_addr), .obs_wr_data(obs_wr_data),
    .obs_wr_strb(obs_wr_strb), .obs_wr_busy(obs_wr_busy), .obs_rd_req(obs_rd_req),
    .obs_rd_vld(obs_rd_vld), .obs_rd_addr(obs_rd_addr), .obs_rd_data(obs_rd_data)
  );
endmodule : sram_ahb_bus_fv

module sram_axi4l_bus_fv #(
  parameter int unsigned ADDR_W   = 8,
  parameter int unsigned WIDTH    = 32,
  parameter int unsigned MAX_WAIT = 64
) (
  input  logic                ACLK,
  input  logic                ARESETn,
  input  logic                AWVALID,
  input  logic                AWREADY,
  input  logic [ADDR_W-1:0]   AWADDR,
  input  logic                WVALID,
  input  logic                WREADY,
  input  logic [WIDTH-1:0]    WDATA,
  input  logic [WIDTH/8-1:0]  WSTRB,
  input  logic                BVALID,
  input  logic                BREADY,
  input  logic [1:0]          BRESP,
  input  logic                ARVALID,
  input  logic                ARREADY,
  input  logic [ADDR_W-1:0]   ARADDR,
  input  logic                RVALID,
  input  logic                RREADY,
  input  logic [WIDTH-1:0]    RDATA,
  input  logic [1:0]          RRESP
);
  logic                obs_wr_vld, obs_wr_busy, obs_rd_req, obs_rd_vld;
  logic [ADDR_W-3:0]   obs_wr_addr, obs_rd_addr;
  logic [WIDTH-1:0]    obs_wr_data, obs_rd_data;
  logic [WIDTH/8-1:0]  obs_wr_strb;

  claude_axi4l_fv #(
    .DATA_W(WIDTH), .ADDR_W(ADDR_W-2), .AXADDR_W(ADDR_W), .MASTER_IS_ENV(1), .MAX_WAIT(MAX_WAIT)
  ) u_bus (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AWVALID(AWVALID), .AWREADY(AWREADY), .AWADDR(AWADDR),
    .WVALID(WVALID), .WREADY(WREADY), .WDATA(WDATA), .WSTRB(WSTRB),
    .BVALID(BVALID), .BREADY(BREADY), .BRESP(BRESP),
    .ARVALID(ARVALID), .ARREADY(ARREADY), .ARADDR(ARADDR),
    .RVALID(RVALID), .RREADY(RREADY), .RDATA(RDATA), .RRESP(RRESP),
    .obs_wr_vld(obs_wr_vld), .obs_wr_addr(obs_wr_addr), .obs_wr_data(obs_wr_data),
    .obs_wr_strb(obs_wr_strb), .obs_wr_busy(obs_wr_busy), .obs_rd_req(obs_rd_req),
    .obs_rd_vld(obs_rd_vld), .obs_rd_addr(obs_rd_addr), .obs_rd_data(obs_rd_data)
  );
endmodule : sram_axi4l_bus_fv

module sram_wb_bus_fv #(
  parameter int unsigned ADDR_W   = 8,
  parameter int unsigned WIDTH    = 32,
  parameter int unsigned MAX_WAIT = 64
) (
  input  logic                CLK_I,
  input  logic                RST_I,
  input  logic                CYC_I,
  input  logic                STB_I,
  input  logic                WE_I,
  input  logic [ADDR_W-1:0]   ADR_I,
  input  logic [WIDTH-1:0]    DAT_I,
  input  logic [WIDTH/8-1:0]  SEL_I,
  input  logic [WIDTH-1:0]    DAT_O,
  input  logic                ACK_O,
  input  logic                ERR_O
);
  logic                obs_wr_vld, obs_wr_busy, obs_rd_req, obs_rd_vld;
  logic [ADDR_W-3:0]   obs_wr_addr, obs_rd_addr;
  logic [WIDTH-1:0]    obs_wr_data, obs_rd_data;
  logic [WIDTH/8-1:0]  obs_wr_strb;

  claude_wb_fv #(
    .DATA_W(WIDTH), .ADDR_W(ADDR_W-2), .ADR_W(ADDR_W), .MASTER_IS_ENV(1), .MAX_WAIT(MAX_WAIT)
  ) u_bus (
    .CLK_I(CLK_I), .RST_I(RST_I), .CYC_I(CYC_I), .STB_I(STB_I), .WE_I(WE_I),
    .ADR_I(ADR_I), .DAT_I(DAT_I), .SEL_I(SEL_I), .DAT_O(DAT_O), .ACK_O(ACK_O),
    .ERR_O(ERR_O),
    .obs_wr_vld(obs_wr_vld), .obs_wr_addr(obs_wr_addr), .obs_wr_data(obs_wr_data),
    .obs_wr_strb(obs_wr_strb), .obs_wr_busy(obs_wr_busy), .obs_rd_req(obs_rd_req),
    .obs_rd_vld(obs_rd_vld), .obs_rd_addr(obs_rd_addr), .obs_rd_data(obs_rd_data)
  );
endmodule : sram_wb_bus_fv
