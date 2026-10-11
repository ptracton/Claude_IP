// bus_matrix_axi4l_tgt.sv — AXI4-Lite target adapter for one bus matrix master port.
//
// Acts as an AXI4-Lite slave towards the external master. One write and one
// read may be outstanding at the same time; each is turned into one request
// on the core's internal handshake (writes first when both are waiting).
//
//   Write: AW and W are accepted independently, in either order. Once both
//     have been taken the write is issued; its response is held on B until
//     BREADY. AWREADY/WREADY stay low from acceptance until the B handshake.
//   Read:  AR is accepted, the read is issued, and RDATA/RRESP are held on R
//     until RREADY. ARREADY stays low until the R handshake.
//   Errors (decode or slave) are returned as SLVERR.

module bus_matrix_axi4l_tgt #(
  parameter int unsigned DATA_W = 32, // data bus width
  parameter int unsigned ADDR_W = 32  // address width
) (
  input  logic                  clk,   // system clock
  input  logic                  rst_n, // synchronous active-low reset

  // AXI4-Lite slave interface (towards the external master)
  input  logic                  AWVALID, // write address valid
  output logic                  AWREADY, // write address ready
  input  logic [ADDR_W-1:0]     AWADDR,  // write byte address
  input  logic                  WVALID,  // write data valid
  output logic                  WREADY,  // write data ready
  input  logic [DATA_W-1:0]     WDATA,   // write data
  input  logic [DATA_W/8-1:0]   WSTRB,   // write byte strobes
  output logic                  BVALID,  // write response valid
  input  logic                  BREADY,  // write response ready
  output logic [1:0]            BRESP,   // write response
  input  logic                  ARVALID, // read address valid
  output logic                  ARREADY, // read address ready
  input  logic [ADDR_W-1:0]     ARADDR,  // read byte address
  output logic                  RVALID,  // read data valid
  input  logic                  RREADY,  // read data ready
  output logic [DATA_W-1:0]     RDATA,   // read data
  output logic [1:0]            RRESP,   // read response

  // Core handshake
  output logic                  core_req,   // request held until done
  output logic [ADDR_W-1:0]     core_addr,  // byte address
  output logic [DATA_W-1:0]     core_wdata, // write data
  output logic                  core_we,    // 1 = write
  output logic [DATA_W/8-1:0]   core_be,    // byte enables
  input  logic                  core_done,  // one-cycle completion
  input  logic [DATA_W-1:0]     core_rdata, // read data (valid with done)
  input  logic                  core_err    // error (valid with done)
);

  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;

  typedef enum logic [1:0] {
    CurNone  = 2'b00,  // no request on the core port
    CurWrite = 2'b01,  // the write is being routed
    CurRead  = 2'b10   // the read is being routed
  } cur_e;

  // Write path
  logic                aw_got_q;  // AW accepted
  logic                w_got_q;   // W accepted
  logic [ADDR_W-1:0]   awaddr_q;
  logic [DATA_W-1:0]   wdata_q;
  logic [DATA_W/8-1:0] wstrb_q;
  logic                bvalid_q;
  logic [1:0]          bresp_q;

  // Read path
  logic                ar_got_q;  // AR accepted
  logic [ADDR_W-1:0]   araddr_q;
  logic                rvalid_q;
  logic [DATA_W-1:0]   rdata_q;
  logic [1:0]          rresp_q;

  cur_e                cur_q;

  logic aw_hs, w_hs, ar_hs, wr_pending, rd_pending;

  assign AWREADY = ~aw_got_q & ~bvalid_q;
  assign WREADY  = ~w_got_q  & ~bvalid_q;
  assign ARREADY = ~ar_got_q & ~rvalid_q;

  assign aw_hs = AWVALID & AWREADY;
  assign w_hs  = WVALID  & WREADY;
  assign ar_hs = ARVALID & ARREADY;

  // A fully received write / read that has not been routed yet
  assign wr_pending = aw_got_q & w_got_q & ~bvalid_q & (cur_q != CurWrite);
  assign rd_pending = ar_got_q & ~rvalid_q & (cur_q != CurRead);

  // Accepted-flag next state: set by the handshake, cleared when the routed
  // transaction completes (a new handshake cannot coincide with completion,
  // since READY is low while the flag is set).
  logic wr_done, rd_done;
  logic aw_got_d, w_got_d, ar_got_d;

  assign wr_done  = (cur_q == CurWrite) & core_done;
  assign rd_done  = (cur_q == CurRead)  & core_done;
  assign aw_got_d = (aw_got_q | aw_hs) & ~wr_done;
  assign w_got_d  = (w_got_q  | w_hs)  & ~wr_done;
  assign ar_got_d = (ar_got_q | ar_hs) & ~rd_done;

  always_ff @(posedge clk) begin : p_got
    if (!rst_n) begin
      aw_got_q <= 1'b0;
      w_got_q  <= 1'b0;
      ar_got_q <= 1'b0;
    end else begin
      aw_got_q <= aw_got_d;
      w_got_q  <= w_got_d;
      ar_got_q <= ar_got_d;
    end
  end

  always_ff @(posedge clk) begin : p_write
    if (!rst_n) begin
      awaddr_q <= '0;
      wdata_q  <= '0;
      wstrb_q  <= '0;
      bvalid_q <= 1'b0;
      bresp_q  <= RESP_OKAY;
    end else begin
      if (aw_hs) begin
        awaddr_q <= AWADDR;
      end
      if (w_hs) begin
        wdata_q <= WDATA;
        wstrb_q <= WSTRB;
      end
      if (wr_done) begin
        bvalid_q <= 1'b1;
        bresp_q  <= core_err ? RESP_SLVERR : RESP_OKAY;
      end else if (bvalid_q && BREADY) begin
        bvalid_q <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk) begin : p_read
    if (!rst_n) begin
      araddr_q <= '0;
      rvalid_q <= 1'b0;
      rdata_q  <= '0;
      rresp_q  <= RESP_OKAY;
    end else begin
      if (ar_hs) begin
        araddr_q <= ARADDR;
      end
      if (rd_done) begin
        rvalid_q <= 1'b1;
        rdata_q  <= core_rdata;
        rresp_q  <= core_err ? RESP_SLVERR : RESP_OKAY;
      end else if (rvalid_q && RREADY) begin
        rvalid_q <= 1'b0;
      end
    end
  end

  // Core port ownership: hold the routed direction until done.
  always_ff @(posedge clk) begin : p_cur
    if (!rst_n) begin
      cur_q <= CurNone;
    end else if (cur_q != CurNone) begin
      if (core_done) begin
        cur_q <= CurNone;
      end
    end else if (wr_pending) begin
      cur_q <= CurWrite;
    end else if (rd_pending) begin
      cur_q <= CurRead;
    end
  end

  assign core_req   = (cur_q != CurNone);
  assign core_we    = (cur_q == CurWrite);
  assign core_addr  = (cur_q == CurWrite) ? awaddr_q : araddr_q;
  assign core_wdata = wdata_q;
  assign core_be    = wstrb_q;

  assign BVALID = bvalid_q;
  assign BRESP  = bresp_q;
  assign RVALID = rvalid_q;
  assign RDATA  = rdata_q;
  assign RRESP  = rresp_q;

endmodule : bus_matrix_axi4l_tgt
