// bus_matrix_tb_axi4l_slave.sv — behavioral AXI4-Lite slave for bus_matrix testbenches.
//
// A 4 KB (2**MEM_AW words) memory behind an AXI4-Lite slave port that
// exercises what the shared claude_axi4l_if bridge never does:
//   - Random wait states on every channel, at most MAX_WAIT cycles each:
//     AWREADY, WREADY and ARREADY are held low for a random number of cycles
//     after VALID rises, and BVALID / RVALID come a random number of cycles
//     after the request is complete.
//   - AW and W are accepted independently (either may complete first); a
//     write is performed once both have been taken.
//   - Slave errors: any access to the 256-byte page ERR_PAGE of the 4 KB
//     window (offsets ERR_PAGE*0x100 .. +0xFF) returns SLVERR, and such a
//     write leaves the memory unchanged. The default page (0xE) keeps the
//     top word of the window (the last word of every region) error-free.
// One write and one read may be in progress at the same time. The address is
// taken modulo 4 KB (addr[11:2]), as with bus_matrix_tb_mem.
//
// Testbench-only (uses $urandom); not synthesizable.

`timescale 1ns / 1ps

module bus_matrix_tb_axi4l_slave #(
  parameter int unsigned MEM_AW     = 10,      // memory word-address width (4 KB)
  parameter int unsigned MAX_WAIT   = 3,       // maximum wait states per channel
  parameter logic [3:0]  ERR_PAGE   = 4'hE     // offsets 0xE00-0xEFF return SLVERR
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        AWVALID,
  output logic        AWREADY,
  input  logic [31:0] AWADDR,
  input  logic        WVALID,
  output logic        WREADY,
  input  logic [31:0] WDATA,
  input  logic [3:0]  WSTRB,
  output logic        BVALID,
  input  logic        BREADY,
  output logic [1:0]  BRESP,
  input  logic        ARVALID,
  output logic        ARREADY,
  input  logic [31:0] ARADDR,
  output logic        RVALID,
  input  logic        RREADY,
  output logic [31:0] RDATA,
  output logic [1:0]  RRESP
);

  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;

  logic [31:0] mem [2**MEM_AW];

  function automatic int unsigned rnd_wait();
    return $urandom_range(MAX_WAIT, 0);
  endfunction

  function automatic logic is_err(logic [31:0] a);
    return a[11:8] == ERR_PAGE;
  endfunction

  // -------------------------------------------------------------------------
  // Write path
  // -------------------------------------------------------------------------
  logic        aw_got, w_got;
  logic [31:0] awaddr_q, wdata_q;
  logic [3:0]  wstrb_q;
  int unsigned aw_wait, w_wait, b_wait;
  logic        b_pend; // both halves taken, response not yet given

  assign AWREADY = !aw_got && (aw_wait == 0);
  assign WREADY  = !w_got  && (w_wait  == 0);

  // Plain always (not always_ff): mem is also cleared by the initial block.
  always @(posedge clk) begin
    if (!rst_n) begin
      aw_got  <= 1'b0;
      w_got   <= 1'b0;
      b_pend  <= 1'b0;
      BVALID  <= 1'b0;
      BRESP   <= RESP_OKAY;
      aw_wait <= rnd_wait();
      w_wait  <= rnd_wait();
      b_wait  <= 0;
    end else begin
      // AW: count down the wait while VALID is presented, then accept
      if (!aw_got && AWVALID) begin
        if (aw_wait != 0) aw_wait <= aw_wait - 1;
        else begin
          aw_got   <= 1'b1;
          awaddr_q <= AWADDR;
        end
      end
      // W: same, independently of AW
      if (!w_got && WVALID) begin
        if (w_wait != 0) w_wait <= w_wait - 1;
        else begin
          w_got   <= 1'b1;
          wdata_q <= WDATA;
          wstrb_q <= WSTRB;
        end
      end
      // Both taken: perform the write, then respond after a random delay
      if (aw_got && w_got && !b_pend && !BVALID) begin
        b_pend <= 1'b1;
        b_wait <= rnd_wait();
        if (!is_err(awaddr_q))
          for (int b = 0; b < 4; b++)
            if (wstrb_q[b]) mem[awaddr_q[MEM_AW+1:2]][b*8+:8] <= wdata_q[b*8+:8];
      end
      if (b_pend && !BVALID) begin
        if (b_wait != 0) b_wait <= b_wait - 1;
        else begin
          BVALID <= 1'b1;
          BRESP  <= is_err(awaddr_q) ? RESP_SLVERR : RESP_OKAY;
        end
      end
      if (BVALID && BREADY) begin
        BVALID  <= 1'b0;
        b_pend  <= 1'b0;
        aw_got  <= 1'b0;
        w_got   <= 1'b0;
        aw_wait <= rnd_wait();
        w_wait  <= rnd_wait();
      end
    end
  end

  // -------------------------------------------------------------------------
  // Read path
  // -------------------------------------------------------------------------
  logic        ar_got;
  logic [31:0] araddr_q;
  int unsigned ar_wait, r_wait;

  assign ARREADY = !ar_got && (ar_wait == 0);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      ar_got  <= 1'b0;
      RVALID  <= 1'b0;
      RDATA   <= '0;
      RRESP   <= RESP_OKAY;
      ar_wait <= rnd_wait();
      r_wait  <= 0;
    end else begin
      if (!ar_got && ARVALID) begin
        if (ar_wait != 0) ar_wait <= ar_wait - 1;
        else begin
          ar_got   <= 1'b1;
          araddr_q <= ARADDR;
          r_wait   <= rnd_wait();
        end
      end
      if (ar_got && !RVALID) begin
        if (r_wait != 0) r_wait <= r_wait - 1;
        else begin
          RVALID <= 1'b1;
          RRESP  <= is_err(araddr_q) ? RESP_SLVERR : RESP_OKAY;
          RDATA  <= is_err(araddr_q) ? 32'hDEAD_BEEF : mem[araddr_q[MEM_AW+1:2]];
        end
      end
      if (RVALID && RREADY) begin
        RVALID  <= 1'b0;
        ar_got  <= 1'b0;
        ar_wait <= rnd_wait();
      end
    end
  end

  initial foreach (mem[i]) mem[i] = '0;

endmodule : bus_matrix_tb_axi4l_slave
