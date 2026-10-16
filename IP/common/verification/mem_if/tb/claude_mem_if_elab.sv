// claude_mem_if_elab.sv — Elaboration check of the claude_<proto>_mem_if adapters.
//
// Instantiates all four adapters at data widths 8, 16 and 64 (the
// testbenches cover 32), so a width-dependent bug in either language
// (e.g. the AHB byte-lane logic at DATA_W = 8) fails compilation or the
// short lane-mask self-check below. Simulation only.

`timescale 1ns / 1ps

module claude_mem_if_elab;

  logic clk = 1'b0;
  logic rst_n;
  always #5 clk = ~clk;

  for (genvar w = 0; w < 3; w++) begin : g_width
    localparam int unsigned DataW = (w == 0) ? 8 : (w == 1) ? 16 : 64;
    localparam int unsigned StrbW = DataW / 8;
    localparam int unsigned AddrW = 16;

    // Shared stimulus; every adapter sees an idle bus except the AHB one.
    logic [AddrW-1:0] addr;
    logic [DataW-1:0] wdata;
    logic [StrbW-1:0] strb;
    logic [2:0]       hsize;
    logic             hsel;
    logic [1:0]       htrans;
    logic             hreadyout;
    logic             ahb_clr_n;   // per-lane reset of the AHB adapter

    logic             ahb_req, apb_req, axi_req, wb_req;
    logic [StrbW-1:0] ahb_be;

    claude_ahb_mem_if #(
      .DATA_W(DataW),
      .ADDR_W(AddrW)
    ) u_ahb (
      .HCLK        (clk),
      .HRESETn     (rst_n & ahb_clr_n),
      .HSEL        (hsel),
      .HADDR       (addr),
      .HTRANS      (htrans),
      .HWRITE      (1'b1),
      .HSIZE       (hsize),
      .HWDATA      (wdata),
      .HWSTRB      ({StrbW{1'b1}}),
      .HREADY      (hreadyout),
      .HRDATA      (),
      .HREADYOUT   (hreadyout),
      .HRESP       (),
      .mem_req_o   (ahb_req),
      .mem_gnt_i   (1'b0),
      .mem_we_o    (),
      .mem_addr_o  (),
      .mem_be_o    (ahb_be),
      .mem_wdata_o (),
      .mem_rvalid_i(1'b0),
      .mem_rdata_i ({DataW{1'b0}}),
      .mem_err_i   (1'b0)
    );

    claude_apb_mem_if #(
      .DATA_W(DataW),
      .ADDR_W(AddrW)
    ) u_apb (
      .PCLK        (clk),
      .PRESETn     (rst_n),
      .PSEL        (1'b0),
      .PENABLE     (1'b0),
      .PADDR       (addr),
      .PWRITE      (1'b0),
      .PWDATA      (wdata),
      .PSTRB       (strb),
      .PRDATA      (),
      .PREADY      (),
      .PSLVERR     (),
      .mem_req_o   (apb_req),
      .mem_gnt_i   (1'b0),
      .mem_we_o    (),
      .mem_addr_o  (),
      .mem_be_o    (),
      .mem_wdata_o (),
      .mem_rvalid_i(1'b0),
      .mem_rdata_i ({DataW{1'b0}}),
      .mem_err_i   (1'b0)
    );

    claude_axi4l_mem_if #(
      .DATA_W(DataW),
      .ADDR_W(AddrW)
    ) u_axi4l (
      .ACLK        (clk),
      .ARESETn     (rst_n),
      .AWVALID     (1'b0),
      .AWREADY     (),
      .AWADDR      (addr),
      .WVALID      (1'b0),
      .WREADY      (),
      .WDATA       (wdata),
      .WSTRB       (strb),
      .BVALID      (),
      .BREADY      (1'b1),
      .BRESP       (),
      .ARVALID     (1'b0),
      .ARREADY     (),
      .ARADDR      (addr),
      .RVALID      (),
      .RREADY      (1'b1),
      .RDATA       (),
      .RRESP       (),
      .mem_req_o   (axi_req),
      .mem_gnt_i   (1'b0),
      .mem_we_o    (),
      .mem_addr_o  (),
      .mem_be_o    (),
      .mem_wdata_o (),
      .mem_rvalid_i(1'b0),
      .mem_rdata_i ({DataW{1'b0}}),
      .mem_err_i   (1'b0)
    );

    claude_wb_mem_if #(
      .DATA_W(DataW),
      .ADDR_W(AddrW)
    ) u_wb (
      .CLK_I       (clk),
      .RST_I       (~rst_n),
      .CYC_I       (1'b0),
      .STB_I       (1'b0),
      .WE_I        (1'b0),
      .ADR_I       (addr),
      .DAT_I       (wdata),
      .SEL_I       (strb),
      .DAT_O       (),
      .ACK_O       (),
      .ERR_O       (),
      .mem_req_o   (wb_req),
      .mem_gnt_i   (1'b0),
      .mem_we_o    (),
      .mem_addr_o  (),
      .mem_be_o    (),
      .mem_wdata_o (),
      .mem_rvalid_i(1'b0),
      .mem_rdata_i ({DataW{1'b0}}),
      .mem_err_i   (1'b0)
    );

    // Lane-mask self-check: one single-byte AHB write per lane; the memory
    // never grants, so each request sits in the data phase where mem_be_o
    // can be checked, then reset clears the adapter for the next lane.
    initial begin : p_lanes
      logic [StrbW-1:0] exp;
      hsel   = 1'b0;
      htrans = 2'b00;
      hsize  = 3'd0;
      addr   = '0;
      wdata  = '0;
      strb   = '0;
      ahb_clr_n = 1'b1;
      @(posedge rst_n);
      for (int lane = 0; lane < StrbW; lane++) begin
        @(negedge clk);
        hsel   = 1'b1;
        htrans = 2'b10;
        addr   = AddrW'(lane);
        @(negedge clk);
        hsel   = 1'b0;
        htrans = 2'b00;
        exp    = StrbW'(1) << lane;
        if (!ahb_req || ahb_be !== exp) begin
          $display("FAIL claude_mem_if_elab: DATA_W=%0d lane %0d be=0b%b exp 0b%b",
                   DataW, lane, ahb_be, exp);
          $finish(1);
        end
        ahb_clr_n = 1'b0;
        @(negedge clk);
        ahb_clr_n = 1'b1;
      end
    end
  end

  initial begin : p_main
    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    repeat (40) @(posedge clk);
    $display("PASS claude_mem_if_elab: DATA_W 8/16/64 elaborate, AHB lanes correct");
    $finish;
  end

endmodule : claude_mem_if_elab
