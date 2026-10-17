// sram_macro_saed14.sv — SAED14 SRAM wrapper (TECH_SAED14).
//
// A W x D single-port memory built from SAED14 (SAED14nm_EDK_SRAM)
// SRAM1RW<d>x<w> primitives.
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
// Example: W = 32, D = 1024 with 4 byte lanes -> 512x8 primitives, 2 rows x
// 4 columns, the row selected by addr_i[9].
//
// Pin mapping (every primitive):
//   CE = clk, CSB = row select (ACTIVE HIGH: SAED14nm Memories databook,
//   "CSB - Primary Chip Select, Active High"), WEB = not write (active low),
//   OEB = 0. The primitive drives O to 0 after any cycle that is not a read,
//   so the row register only changes on a read.
//   Quirk: SRAM1RW32x8 has a 32-bit I bus (model and liberty); its data is
//   zero-extended.
//   Read data is registered on CE: valid in the cycle after a read.
//   No byte mask: each column lies inside one write lane (checked below), and
//   that lane's enable gates the column's WEB.
//   ls_i / ds_i / sd_i are unused: no sleep pins on this family (UPF).

module sram_macro_saed14 #(
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

  localparam int unsigned Tech   = sram_pkg::TECH_SAED14;
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
      $fatal(1, "sram_macro_saed14: D must be a power of two >= 2");
    if (W % NLANES != 0)
      $fatal(1, "sram_macro_saed14: NLANES must divide W");
    if (NLANES > 1 && (W / NLANES) % PrimW != 0)
      $fatal(1, "sram_macro_saed14: a %0d-bit column crosses a write lane", PrimW);
  end
  // synopsys translate_on

  logic [RowW-1:0]   row;               // row addressed this cycle
  logic [RowW-1:0]   rd_row_q;          // row read last cycle
  logic [PrimAw-1:0] paddr;             // primitive word address
  logic [PadW-1:0]   wdata_pad;         // write data, zero-padded
  logic [Cols-1:0]   col_web;           // write enable per column, active low
  logic [PadW-1:0]   row_rdata [Rows];  // read data of each row

  // Low address bits go to every primitive (zero-extended when D < PRIM_D).
  assign paddr     = PrimAw'(addr_i);
  assign wdata_pad = PadW'(wdata_i);

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

  // Each column takes the write enable of the lane it lies in.
  for (genvar c = 0; c < Cols; c++) begin : g_col_we
    assign col_web[c] = ~(we_i & lane_we_i[sram_pkg::lane_of(c * PrimW, W, NLANES)]);
  end

  for (genvar r = 0; r < Rows; r++) begin : g_row
    logic csb;  // this row's chip select (macro polarity: active high)
    assign csb = cs_i && (row == RowW'(r));

    for (genvar c = 0; c < Cols; c++) begin : g_col
      // One branch per supported size (sram_pkg::prim_depth only picks these).
      if (PrimW == 8 && PrimD == 16) begin : g_8x16
        SRAM1RW16x8 u_prim (
          .A  (paddr),
          .CE (clk),
          .WEB(col_web[c]),
          .OEB(1'b0),
          .CSB(csb),
          .I  (wdata_pad[c * PrimW +: PrimW]),
          .O  (row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 8 && PrimD == 32) begin : g_8x32
        SRAM1RW32x8 u_prim (
          .A  (paddr),
          .CE (clk),
          .WEB(col_web[c]),
          .OEB(1'b0),
          .CSB(csb),
          // SRAM1RW32x8 has a 32-bit I bus (liberty too); only 8 bits are used.
          .I  (32'(wdata_pad[c * PrimW +: PrimW])),
          .O  (row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 8 && PrimD == 64) begin : g_8x64
        SRAM1RW64x8 u_prim (
          .A  (paddr),
          .CE (clk),
          .WEB(col_web[c]),
          .OEB(1'b0),
          .CSB(csb),
          .I  (wdata_pad[c * PrimW +: PrimW]),
          .O  (row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 8 && PrimD == 128) begin : g_8x128
        SRAM1RW128x8 u_prim (
          .A  (paddr),
          .CE (clk),
          .WEB(col_web[c]),
          .OEB(1'b0),
          .CSB(csb),
          .I  (wdata_pad[c * PrimW +: PrimW]),
          .O  (row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 8 && PrimD == 256) begin : g_8x256
        SRAM1RW256x8 u_prim (
          .A  (paddr),
          .CE (clk),
          .WEB(col_web[c]),
          .OEB(1'b0),
          .CSB(csb),
          .I  (wdata_pad[c * PrimW +: PrimW]),
          .O  (row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 8 && PrimD == 512) begin : g_8x512
        SRAM1RW512x8 u_prim (
          .A  (paddr),
          .CE (clk),
          .WEB(col_web[c]),
          .OEB(1'b0),
          .CSB(csb),
          .I  (wdata_pad[c * PrimW +: PrimW]),
          .O  (row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 32 && PrimD == 16) begin : g_32x16
        SRAM1RW16x32 u_prim (
          .A  (paddr),
          .CE (clk),
          .WEB(col_web[c]),
          .OEB(1'b0),
          .CSB(csb),
          .I  (wdata_pad[c * PrimW +: PrimW]),
          .O  (row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 32 && PrimD == 32) begin : g_32x32
        SRAM1RW32x32 u_prim (
          .A  (paddr),
          .CE (clk),
          .WEB(col_web[c]),
          .OEB(1'b0),
          .CSB(csb),
          .I  (wdata_pad[c * PrimW +: PrimW]),
          .O  (row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 32 && PrimD == 64) begin : g_32x64
        SRAM1RW64x32 u_prim (
          .A  (paddr),
          .CE (clk),
          .WEB(col_web[c]),
          .OEB(1'b0),
          .CSB(csb),
          .I  (wdata_pad[c * PrimW +: PrimW]),
          .O  (row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 32 && PrimD == 128) begin : g_32x128
        SRAM1RW128x32 u_prim (
          .A  (paddr),
          .CE (clk),
          .WEB(col_web[c]),
          .OEB(1'b0),
          .CSB(csb),
          .I  (wdata_pad[c * PrimW +: PrimW]),
          .O  (row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 32 && PrimD == 256) begin : g_32x256
        SRAM1RW256x32 u_prim (
          .A  (paddr),
          .CE (clk),
          .WEB(col_web[c]),
          .OEB(1'b0),
          .CSB(csb),
          .I  (wdata_pad[c * PrimW +: PrimW]),
          .O  (row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 32 && PrimD == 512) begin : g_32x512
        SRAM1RW512x32 u_prim (
          .A  (paddr),
          .CE (clk),
          .WEB(col_web[c]),
          .OEB(1'b0),
          .CSB(csb),
          .I  (wdata_pad[c * PrimW +: PrimW]),
          .O  (row_rdata[r][c * PrimW +: PrimW])
        );
      end else begin : g_unsupported
        // Elaboration-time error: no primitive of this size in the curated list.
        initial $fatal(1, "sram_macro_saed14: no %0dx%0d primitive", PrimW, PrimD);
        assign row_rdata[r][c * PrimW +: PrimW] = '0;
      end
    end
  end

endmodule : sram_macro_saed14
