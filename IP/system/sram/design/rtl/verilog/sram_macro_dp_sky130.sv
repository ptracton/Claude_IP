// sram_macro_dp_sky130.sv — SKY130 OpenRAM SRAM wrapper (TECH_SKY130, DUAL_PORT).
//
// A W x D memory built from the same 1rw1r macros as sram_macro_sky130,
// with both macro ports used:
//   port 0 = port A, read/write: csb0 = not A row select, web0 = not a_we_i,
//            wmask0 = lane enable of each byte, addr0, din0, dout0
//   port 1 = port B, READ ONLY:  csb1 = not B row select, addr1, dout1
// One primitive size PRIM_W x PRIM_D is picked by sram_pkg::prim_width_dp /
// prim_depth_dp (the sizes in the g_<w>x<d> branches below), and generate loops
// tile it:
//   rows     ROWS = D / PRIM_D primitives stacked in depth. The address bits
//            above the primitive address select the row (its chip select),
//            and a row register remembers the row read, for the read mux.
//            When D < PRIM_D there is one row and the primitive's top address
//            bits are tied to 0.
//   columns  COLS = ceil(W / PRIM_W) primitives side by side. The last column
//            is zero-padded when PRIM_W does not divide W.
// Example: W = 32, D = 2048 -> 32x512 primitives, 4 rows x 1 column.
//
// The core turns every port-B write into a bus error for this technology
// (sram_port READ_ONLY), so b_we_i / b_wdata_i / b_lane_we_i are never needed.
// Each port has its own row decode and row register on its own clock (clk0 =
// a_clk, clk1 = b_clk). Read data is valid in the cycle after a read; the
// simulation clock period must exceed ~8 ns on each port.
// VERBOSE = 0. ls_i / ds_i / sd_i are unused: no sleep pins (UPF).

module sram_macro_dp_sky130 #(
  parameter int unsigned W      = 32,   // word width
  parameter int unsigned D      = 1024, // words (power of two)
  parameter int unsigned NLANES = 4     // write lanes of W / NLANES bits
) (
  input  logic                 a_clk,       // port A clock
  input  logic                 a_cs_i,      // port A chip select
  input  logic                 a_we_i,      // port A 1 = write
  input  logic [$clog2(D)-1:0] a_addr_i,    // port A word address
  input  logic [W-1:0]         a_wdata_i,   // port A write data
  input  logic [NLANES-1:0]    a_lane_we_i, // port A lanes to write
  output logic [W-1:0]         a_rdata_o,   // port A read data
  input  logic                 b_clk,       // port B clock
  input  logic                 b_cs_i,      // port B chip select
  // Port B is read-only on this macro (see header).
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic                 b_we_i,      // port B 1 = write (unused)
  input  logic [$clog2(D)-1:0] b_addr_i,    // port B word address
  input  logic [W-1:0]         b_wdata_i,   // port B write data (unused)
  input  logic [NLANES-1:0]    b_lane_we_i, // port B lanes (unused)
  /* verilator lint_on UNUSEDSIGNAL */
  output logic [W-1:0]         b_rdata_o,   // port B read data
  // No sleep pins on this primitive family: power is controlled through UPF.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic                 ls_i,        // light sleep (unused)
  input  logic                 ds_i,        // deep sleep (unused)
  input  logic                 sd_i         // shutdown (unused)
  /* verilator lint_on UNUSEDSIGNAL */
);

  localparam int unsigned Tech   = sram_pkg::TECH_SKY130;
  localparam int unsigned PrimW  = sram_pkg::prim_width_dp(Tech, W, NLANES);
  localparam int unsigned PrimD  = sram_pkg::prim_depth_dp(Tech, PrimW, D);
  localparam int unsigned PrimAw = $clog2(PrimD);
  localparam int unsigned Rows   = sram_pkg::tile_rows(D, PrimD);
  localparam int unsigned Cols   = (W + PrimW - 1) / PrimW;
  localparam int unsigned PadW   = Cols * PrimW;
  localparam int unsigned RowW   = (Rows > 1) ? $clog2(Rows) : 1;

  // synopsys translate_off
  initial begin : p_param_check
    if ((D & (D - 1)) != 0 || D < 2)
      $fatal(1, "sram_macro_dp_sky130: D must be a power of two >= 2");
    if (W % NLANES != 0)
      $fatal(1, "sram_macro_dp_sky130: NLANES must divide W");
    if (NLANES > 1 && (W / NLANES) % 8 != 0)
      $fatal(1, "sram_macro_dp_sky130: a byte crosses a write lane");
  end
  // synopsys translate_on

  logic [RowW-1:0]   a_row;               // port A: row addressed this cycle
  logic [RowW-1:0]   a_rd_row_q;          // port A: row read last cycle
  logic [PrimAw-1:0] a_paddr;             // port A: primitive word address
  logic [PadW-1:0]   a_wdata_pad;         // port A: write data, zero-padded
  logic [PadW-1:0]   a_row_rdata [Rows];  // port A: read data of each row
  logic [RowW-1:0]   b_row;               // port B: row addressed this cycle
  logic [RowW-1:0]   b_rd_row_q;          // port B: row read last cycle
  logic [PrimAw-1:0] b_paddr;             // port B: primitive word address
  logic [PadW-1:0]   b_row_rdata [Rows];  // port B: read data of each row
  logic              a_web;               // write enable, active low

  // Low address bits go to every primitive (zero-extended when D < PRIM_D).
  assign a_paddr     = PrimAw'(a_addr_i);
  assign b_paddr     = PrimAw'(b_addr_i);
  assign a_wdata_pad = PadW'(a_wdata_i);
  assign a_web       = ~a_we_i;

  // Row select from the address bits above the primitive address; each port
  // remembers the row it read, for its read multiplexer.
  if (Rows > 1) begin : g_rows
    assign a_row = RowW'(a_addr_i >> PrimAw);
    assign b_row = RowW'(b_addr_i >> PrimAw);

    always_ff @(posedge a_clk) begin : p_a_rd_row
      if (a_cs_i && !a_we_i) begin
        a_rd_row_q <= a_row;
      end
    end

    always_ff @(posedge b_clk) begin : p_b_rd_row
      if (b_cs_i) begin
        b_rd_row_q <= b_row;
      end
    end
  end else begin : g_one_row
    assign a_row      = '0;
    assign a_rd_row_q = '0;
    assign b_row      = '0;
    assign b_rd_row_q = '0;
  end

  assign a_rdata_o = W'(a_row_rdata[a_rd_row_q]);
  assign b_rdata_o = W'(b_row_rdata[b_rd_row_q]);

  for (genvar r = 0; r < Rows; r++) begin : g_row
    logic a_csb;  // this row's port A chip select, active low
    logic b_csb;  // this row's port B chip select, active low
    assign a_csb = ~(a_cs_i && (a_row == RowW'(r)));
    assign b_csb = ~(b_cs_i && (b_row == RowW'(r)));

    for (genvar c = 0; c < Cols; c++) begin : g_col
      logic [PrimW/8-1:0] a_wmask;  // byte write mask (lane enables)

      for (genvar k = 0; k < PrimW / 8; k++) begin : g_byte
        assign a_wmask[k] = a_lane_we_i[sram_pkg::lane_of(c * PrimW + 8 * k, W, NLANES)];
      end

      // One branch per supported size (sram_pkg::prim_depth_dp only picks these).
      if (PrimW == 32 && PrimD == 256) begin : g_32x256
        sky130_sram_1kbyte_1rw1r_32x256_8 #(
          .VERBOSE(0)
        ) u_prim (
          .clk0  (a_clk),
          .csb0  (a_csb),
          .web0  (a_web),
          .wmask0(a_wmask),
          .addr0 (a_paddr),
          .din0  (a_wdata_pad[c * PrimW +: PrimW]),
          .dout0 (a_row_rdata[r][c * PrimW +: PrimW]),
          .clk1  (b_clk),
          .csb1  (b_csb),
          .addr1 (b_paddr),
          .dout1 (b_row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 32 && PrimD == 512) begin : g_32x512
        sky130_sram_2kbyte_1rw1r_32x512_8 #(
          .VERBOSE(0)
        ) u_prim (
          .clk0  (a_clk),
          .csb0  (a_csb),
          .web0  (a_web),
          .wmask0(a_wmask),
          .addr0 (a_paddr),
          .din0  (a_wdata_pad[c * PrimW +: PrimW]),
          .dout0 (a_row_rdata[r][c * PrimW +: PrimW]),
          .clk1  (b_clk),
          .csb1  (b_csb),
          .addr1 (b_paddr),
          .dout1 (b_row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 8 && PrimD == 1024) begin : g_8x1024
        sky130_sram_1kbyte_1rw1r_8x1024_8 #(
          .VERBOSE(0)
        ) u_prim (
          .clk0  (a_clk),
          .csb0  (a_csb),
          .web0  (a_web),
          .wmask0(a_wmask),
          .addr0 (a_paddr),
          .din0  (a_wdata_pad[c * PrimW +: PrimW]),
          .dout0 (a_row_rdata[r][c * PrimW +: PrimW]),
          .clk1  (b_clk),
          .csb1  (b_csb),
          .addr1 (b_paddr),
          .dout1 (b_row_rdata[r][c * PrimW +: PrimW])
        );
      end else begin : g_unsupported
        // Elaboration-time error: no primitive of this size in the curated list.
        initial $fatal(1, "sram_macro_dp_sky130: no %0dx%0d primitive", PrimW, PrimD);
        assign a_row_rdata[r][c * PrimW +: PrimW] = '0;
        assign b_row_rdata[r][c * PrimW +: PrimW] = '0;
      end
    end
  end

endmodule : sram_macro_dp_sky130
