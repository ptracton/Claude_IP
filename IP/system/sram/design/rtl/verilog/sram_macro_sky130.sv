// sram_macro_sky130.sv — SkyWater SKY130 OpenRAM SRAM wrapper (TECH_SKY130).
//
// A W x D single-port memory built from the OpenRAM 1rw1r macros in
// libs.ref/sky130_sram_macros:
//   32 x 256   sky130_sram_1kbyte_1rw1r_32x256_8   (wmask0, one bit per byte)
//   32 x 512   sky130_sram_2kbyte_1rw1r_32x512_8   (wmask0, one bit per byte)
//    8 x 1024  sky130_sram_1kbyte_1rw1r_8x1024_8   (wmask0, one bit)
// One primitive size PRIM_W x PRIM_D is picked by sram_pkg::prim_width /
// prim_depth (the sizes in the g_<w>x<d> branches below), and generate loops
// tile it:
//   rows     ROWS = D / PRIM_D primitives stacked in depth. The address bits
//            above the primitive address select the row (its chip select),
//            and a row register remembers the row read, for the read mux.
//            When D < PRIM_D there is one row and the primitive's top address
//            bits are tied to 0.
//   columns  COLS = ceil(W / PRIM_W) primitives side by side. The last column
//            is zero-padded when PRIM_W does not divide W.
// Example: W = 32, D = 2048 -> 32x512 primitives, 4 rows x 1 column, the
// row selected by addr_i[10:9].
//
// Pin mapping (every primitive; port 0 = read/write, port 1 unused):
//   clk0 = clk, csb0 = not row select, web0 = not we_i (both active low),
//   wmask0 = the lane enable of each byte (native byte mask), addr0, din0,
//   dout0. clk1 = clk, csb1 = 1 (deselected), addr1 = 0, dout1 open.
//   vccd1/vssd1 exist only with USE_POWER_PINS (not used in RTL).
//   The model latches inputs on the rising edge and drives dout0 a few ns
//   after the falling edge; it goes X shortly after the next rising edge, so
//   read data is valid exactly in the cycle after the read. The clock period
//   must exceed ~8 ns in simulation. VERBOSE = 0 silences the model.
//   ls_i / ds_i / sd_i are unused: no sleep pins (UPF).

module sram_macro_sky130 #(
  parameter int unsigned W      = 32,   // word width
  parameter int unsigned D      = 1024, // words (power of two)
  parameter int unsigned NLANES = 4     // write lanes of W / NLANES bits
) (
  input  logic                 clk,       // clock
  input  logic                 cs_i,      // chip select
  input  logic                 we_i,      // 1 = write, 0 = read
  input  logic [$clog2(D)-1:0] addr_i,    // word address
  input  logic [W-1:0]         wdata_i,   // write data
  input  logic [NLANES-1:0]    lane_we_i, // lanes to write
  // No sleep pins on this primitive family: power is controlled through UPF.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic                 ls_i,      // light sleep (unused)
  input  logic                 ds_i,      // deep sleep (unused)
  input  logic                 sd_i,      // shutdown (unused)
  /* verilator lint_on UNUSEDSIGNAL */
  output logic [W-1:0]         rdata_o    // read data (cycle after a read)
);

  localparam int unsigned Tech   = sram_pkg::TECH_SKY130;
  localparam int unsigned PrimW  = sram_pkg::prim_width(Tech, W, NLANES);
  localparam int unsigned PrimD  = sram_pkg::prim_depth(Tech, PrimW, D);
  localparam int unsigned PrimAw = $clog2(PrimD);
  localparam int unsigned Rows   = sram_pkg::tile_rows(D, PrimD);
  localparam int unsigned Cols   = (W + PrimW - 1) / PrimW;
  localparam int unsigned PadW   = Cols * PrimW;
  localparam int unsigned RowW   = (Rows > 1) ? $clog2(Rows) : 1;

  // synopsys translate_off
  initial begin : p_param_check
    if ((D & (D - 1)) != 0 || D < 2)
      $fatal(1, "sram_macro_sky130: D must be a power of two >= 2");
    if (W % NLANES != 0)
      $fatal(1, "sram_macro_sky130: NLANES must divide W");
    if (NLANES > 1 && (W / NLANES) % 8 != 0)
      $fatal(1, "sram_macro_sky130: a byte crosses a write lane");
  end
  // synopsys translate_on

  logic [RowW-1:0]   row;               // row addressed this cycle
  logic [RowW-1:0]   rd_row_q;          // row read last cycle
  logic [PrimAw-1:0] paddr;             // primitive word address
  logic [PadW-1:0]   wdata_pad;         // write data, zero-padded
  logic [PadW-1:0]   row_rdata [Rows];  // read data of each row
  logic              web;               // write enable, active low

  // Low address bits go to every primitive (zero-extended when D < PRIM_D).
  assign paddr     = PrimAw'(addr_i);
  assign wdata_pad = PadW'(wdata_i);
  assign web       = ~we_i;

  // Row select from the address bits above the primitive address; the row
  // read is remembered for the read multiplexer.
  if (Rows > 1) begin : g_rows
    assign row = RowW'(addr_i >> PrimAw);

    always_ff @(posedge clk) begin : p_rd_row
      if (cs_i && !we_i) begin
        rd_row_q <= row;
      end
    end
  end else begin : g_one_row
    assign row      = '0;
    assign rd_row_q = '0;
  end

  assign rdata_o = W'(row_rdata[rd_row_q]);

  for (genvar r = 0; r < Rows; r++) begin : g_row
    logic csb;  // this row's chip select, active low
    assign csb = ~(cs_i && (row == RowW'(r)));

    for (genvar c = 0; c < Cols; c++) begin : g_col
      logic [PrimW/8-1:0] wmask;  // byte write mask (lane enables)

      for (genvar k = 0; k < PrimW / 8; k++) begin : g_byte
        assign wmask[k] = lane_we_i[sram_pkg::lane_of(c * PrimW + 8 * k, W, NLANES)];
      end

      // One branch per supported size (sram_pkg::prim_depth only picks these).
      if (PrimW == 32 && PrimD == 256) begin : g_32x256
        sky130_sram_1kbyte_1rw1r_32x256_8 #(
          .VERBOSE(0)
        ) u_prim (
          .clk0  (clk),
          .csb0  (csb),
          .web0  (web),
          .wmask0(wmask),
          .addr0 (paddr),
          .din0  (wdata_pad[c * PrimW +: PrimW]),
          .dout0 (row_rdata[r][c * PrimW +: PrimW]),
          .clk1  (clk),
          .csb1  (1'b1),
          .addr1 ('0),
          .dout1 ()
        );
      end else if (PrimW == 32 && PrimD == 512) begin : g_32x512
        sky130_sram_2kbyte_1rw1r_32x512_8 #(
          .VERBOSE(0)
        ) u_prim (
          .clk0  (clk),
          .csb0  (csb),
          .web0  (web),
          .wmask0(wmask),
          .addr0 (paddr),
          .din0  (wdata_pad[c * PrimW +: PrimW]),
          .dout0 (row_rdata[r][c * PrimW +: PrimW]),
          .clk1  (clk),
          .csb1  (1'b1),
          .addr1 ('0),
          .dout1 ()
        );
      end else if (PrimW == 8 && PrimD == 1024) begin : g_8x1024
        sky130_sram_1kbyte_1rw1r_8x1024_8 #(
          .VERBOSE(0)
        ) u_prim (
          .clk0  (clk),
          .csb0  (csb),
          .web0  (web),
          .wmask0(wmask),
          .addr0 (paddr),
          .din0  (wdata_pad[c * PrimW +: PrimW]),
          .dout0 (row_rdata[r][c * PrimW +: PrimW]),
          .clk1  (clk),
          .csb1  (1'b1),
          .addr1 ('0),
          .dout1 ()
        );
      end else begin : g_unsupported
        // Elaboration-time error: no primitive of this size in the curated list.
        initial $fatal(1, "sram_macro_sky130: no %0dx%0d primitive", PrimW, PrimD);
        assign row_rdata[r][c * PrimW +: PrimW] = '0;
      end
    end
  end

endmodule : sram_macro_sky130
