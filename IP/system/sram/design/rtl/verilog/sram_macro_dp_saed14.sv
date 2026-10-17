// sram_macro_dp_saed14.sv — SAED14 two-port SRAM wrapper (DUAL_PORT).
//
// A W x D two-port memory built from SAED14 (SAED14nm_EDK_SRAM)
// SRAM2RW<d>x<w> primitives: two independent read/write ports on one
// clock (see the pin mapping).
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
// Example: W = 32, D = 1024 with 4 byte lanes -> 512x8 primitives, 2 rows
// x 4 columns.
//
// Pin mapping (every primitive):
//   CE1 = CE2 = a_clk. The SRAM2RW is not a true two-clock macro: CE1 clocks
//   both ports' writes and CE2 both ports' reads (liberty and model agree), so
//   it only works with one clock and sram_core rejects COMMON_CLK = 0 for
//   TECH_SAED14. b_clk only clocks port B's row register (the same clock).
//   CSB1/CSB2 = not row select of port A/B (ACTIVE LOW for
//   the two-port primitives - databook: "Chip Select signal is low for
//   read/write" - unlike the single-port SRAM1RW); WEB1/WEB2 = not write;
//   OEB1 = OEB2 = 0. Each port has its own row decode and row register.
//   Read data is registered: valid in the cycle after a read.
//   No byte mask: each column lies inside one write lane (checked below), and
//   that lane's enable gates the column's WEB. With COMMON_CLK the core keeps
//   the ports off the same word in one cycle when either writes; with separate
//   clocks, such a collision is undefined. SRAM2RW16x16 is not
//   used (5-bit O in the vendor files).
//   ls_i / ds_i / sd_i are unused: no sleep pins on this family (UPF).

module sram_macro_dp_saed14 #(
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
  input  logic                 b_we_i,      // port B 1 = write
  input  logic [$clog2(D)-1:0] b_addr_i,    // port B word address
  input  logic [W-1:0]         b_wdata_i,   // port B write data
  input  logic [NLANES-1:0]    b_lane_we_i, // port B lanes to write
  output logic [W-1:0]         b_rdata_o,   // port B read data
  // No sleep pins on this primitive family: power is controlled through UPF.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic                 ls_i,        // light sleep (unused)
  input  logic                 ds_i,        // deep sleep (unused)
  input  logic                 sd_i         // shutdown (unused)
  /* verilator lint_on UNUSEDSIGNAL */
);

  localparam int unsigned Tech   = sram_pkg::TECH_SAED14;
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
      $fatal(1, "sram_macro_dp_saed14: D must be a power of two >= 2");
    if (W % NLANES != 0)
      $fatal(1, "sram_macro_dp_saed14: NLANES must divide W");
    if (NLANES > 1 && (W / NLANES) % PrimW != 0)
      $fatal(1, "sram_macro_dp_saed14: a %0d-bit column crosses a write lane", PrimW);
  end
  // synopsys translate_on

  logic [RowW-1:0]   a_row;               // port A: row addressed this cycle
  logic [RowW-1:0]   a_rd_row_q;          // port A: row read last cycle
  logic [PrimAw-1:0] a_paddr;             // port A: primitive word address
  logic [PadW-1:0]   a_wdata_pad;         // port A: write data, zero-padded
  logic [Cols-1:0]   a_col_web;           // port A: write enable per column, active low
  logic [PadW-1:0]   a_row_rdata [Rows];  // port A: read data of each row
  logic [RowW-1:0]   b_row;               // port B: row addressed this cycle
  logic [RowW-1:0]   b_rd_row_q;          // port B: row read last cycle
  logic [PrimAw-1:0] b_paddr;             // port B: primitive word address
  logic [PadW-1:0]   b_wdata_pad;         // port B: write data, zero-padded
  logic [Cols-1:0]   b_col_web;           // port B: write enable per column, active low
  logic [PadW-1:0]   b_row_rdata [Rows];  // port B: read data of each row

  // Low address bits go to every primitive (zero-extended when D < PRIM_D).
  assign a_paddr     = PrimAw'(a_addr_i);
  assign b_paddr     = PrimAw'(b_addr_i);
  assign a_wdata_pad = PadW'(a_wdata_i);
  assign b_wdata_pad = PadW'(b_wdata_i);

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
      if (b_cs_i && !b_we_i) begin
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

  // Each column takes the write enable of the lane it lies in.
  for (genvar c = 0; c < Cols; c++) begin : g_col_we
    assign a_col_web[c] = ~(a_we_i & a_lane_we_i[sram_pkg::lane_of(c * PrimW, W, NLANES)]);
    assign b_col_web[c] = ~(b_we_i & b_lane_we_i[sram_pkg::lane_of(c * PrimW, W, NLANES)]);
  end

  for (genvar r = 0; r < Rows; r++) begin : g_row
    logic a_csb;  // this row's port A chip select, active low
    logic b_csb;  // this row's port B chip select, active low
    assign a_csb = ~(a_cs_i && (a_row == RowW'(r)));
    assign b_csb = ~(b_cs_i && (b_row == RowW'(r)));

    for (genvar c = 0; c < Cols; c++) begin : g_col
      // One branch per supported size (sram_pkg::prim_depth_dp only picks these).
      if (PrimW == 8 && PrimD == 16) begin : g_8x16
        SRAM2RW16x8 u_prim (
          .A1  (a_paddr),
          .A2  (b_paddr),
          .CE1 (a_clk),
          .CE2 (a_clk),
          .WEB1(a_col_web[c]),
          .WEB2(b_col_web[c]),
          .OEB1(1'b0),
          .OEB2(1'b0),
          .CSB1(a_csb),
          .CSB2(b_csb),
          .I1  (a_wdata_pad[c * PrimW +: PrimW]),
          .I2  (b_wdata_pad[c * PrimW +: PrimW]),
          .O1  (a_row_rdata[r][c * PrimW +: PrimW]),
          .O2  (b_row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 8 && PrimD == 32) begin : g_8x32
        SRAM2RW32x8 u_prim (
          .A1  (a_paddr),
          .A2  (b_paddr),
          .CE1 (a_clk),
          .CE2 (a_clk),
          .WEB1(a_col_web[c]),
          .WEB2(b_col_web[c]),
          .OEB1(1'b0),
          .OEB2(1'b0),
          .CSB1(a_csb),
          .CSB2(b_csb),
          .I1  (a_wdata_pad[c * PrimW +: PrimW]),
          .I2  (b_wdata_pad[c * PrimW +: PrimW]),
          .O1  (a_row_rdata[r][c * PrimW +: PrimW]),
          .O2  (b_row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 8 && PrimD == 64) begin : g_8x64
        SRAM2RW64x8 u_prim (
          .A1  (a_paddr),
          .A2  (b_paddr),
          .CE1 (a_clk),
          .CE2 (a_clk),
          .WEB1(a_col_web[c]),
          .WEB2(b_col_web[c]),
          .OEB1(1'b0),
          .OEB2(1'b0),
          .CSB1(a_csb),
          .CSB2(b_csb),
          .I1  (a_wdata_pad[c * PrimW +: PrimW]),
          .I2  (b_wdata_pad[c * PrimW +: PrimW]),
          .O1  (a_row_rdata[r][c * PrimW +: PrimW]),
          .O2  (b_row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 8 && PrimD == 128) begin : g_8x128
        SRAM2RW128x8 u_prim (
          .A1  (a_paddr),
          .A2  (b_paddr),
          .CE1 (a_clk),
          .CE2 (a_clk),
          .WEB1(a_col_web[c]),
          .WEB2(b_col_web[c]),
          .OEB1(1'b0),
          .OEB2(1'b0),
          .CSB1(a_csb),
          .CSB2(b_csb),
          .I1  (a_wdata_pad[c * PrimW +: PrimW]),
          .I2  (b_wdata_pad[c * PrimW +: PrimW]),
          .O1  (a_row_rdata[r][c * PrimW +: PrimW]),
          .O2  (b_row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 8 && PrimD == 256) begin : g_8x256
        SRAM2RW256x8 u_prim (
          .A1  (a_paddr),
          .A2  (b_paddr),
          .CE1 (a_clk),
          .CE2 (a_clk),
          .WEB1(a_col_web[c]),
          .WEB2(b_col_web[c]),
          .OEB1(1'b0),
          .OEB2(1'b0),
          .CSB1(a_csb),
          .CSB2(b_csb),
          .I1  (a_wdata_pad[c * PrimW +: PrimW]),
          .I2  (b_wdata_pad[c * PrimW +: PrimW]),
          .O1  (a_row_rdata[r][c * PrimW +: PrimW]),
          .O2  (b_row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 8 && PrimD == 512) begin : g_8x512
        SRAM2RW512x8 u_prim (
          .A1  (a_paddr),
          .A2  (b_paddr),
          .CE1 (a_clk),
          .CE2 (a_clk),
          .WEB1(a_col_web[c]),
          .WEB2(b_col_web[c]),
          .OEB1(1'b0),
          .OEB2(1'b0),
          .CSB1(a_csb),
          .CSB2(b_csb),
          .I1  (a_wdata_pad[c * PrimW +: PrimW]),
          .I2  (b_wdata_pad[c * PrimW +: PrimW]),
          .O1  (a_row_rdata[r][c * PrimW +: PrimW]),
          .O2  (b_row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 32 && PrimD == 16) begin : g_32x16
        SRAM2RW16x32 u_prim (
          .A1  (a_paddr),
          .A2  (b_paddr),
          .CE1 (a_clk),
          .CE2 (a_clk),
          .WEB1(a_col_web[c]),
          .WEB2(b_col_web[c]),
          .OEB1(1'b0),
          .OEB2(1'b0),
          .CSB1(a_csb),
          .CSB2(b_csb),
          .I1  (a_wdata_pad[c * PrimW +: PrimW]),
          .I2  (b_wdata_pad[c * PrimW +: PrimW]),
          .O1  (a_row_rdata[r][c * PrimW +: PrimW]),
          .O2  (b_row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 32 && PrimD == 32) begin : g_32x32
        SRAM2RW32x32 u_prim (
          .A1  (a_paddr),
          .A2  (b_paddr),
          .CE1 (a_clk),
          .CE2 (a_clk),
          .WEB1(a_col_web[c]),
          .WEB2(b_col_web[c]),
          .OEB1(1'b0),
          .OEB2(1'b0),
          .CSB1(a_csb),
          .CSB2(b_csb),
          .I1  (a_wdata_pad[c * PrimW +: PrimW]),
          .I2  (b_wdata_pad[c * PrimW +: PrimW]),
          .O1  (a_row_rdata[r][c * PrimW +: PrimW]),
          .O2  (b_row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 32 && PrimD == 64) begin : g_32x64
        SRAM2RW64x32 u_prim (
          .A1  (a_paddr),
          .A2  (b_paddr),
          .CE1 (a_clk),
          .CE2 (a_clk),
          .WEB1(a_col_web[c]),
          .WEB2(b_col_web[c]),
          .OEB1(1'b0),
          .OEB2(1'b0),
          .CSB1(a_csb),
          .CSB2(b_csb),
          .I1  (a_wdata_pad[c * PrimW +: PrimW]),
          .I2  (b_wdata_pad[c * PrimW +: PrimW]),
          .O1  (a_row_rdata[r][c * PrimW +: PrimW]),
          .O2  (b_row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 32 && PrimD == 128) begin : g_32x128
        SRAM2RW128x32 u_prim (
          .A1  (a_paddr),
          .A2  (b_paddr),
          .CE1 (a_clk),
          .CE2 (a_clk),
          .WEB1(a_col_web[c]),
          .WEB2(b_col_web[c]),
          .OEB1(1'b0),
          .OEB2(1'b0),
          .CSB1(a_csb),
          .CSB2(b_csb),
          .I1  (a_wdata_pad[c * PrimW +: PrimW]),
          .I2  (b_wdata_pad[c * PrimW +: PrimW]),
          .O1  (a_row_rdata[r][c * PrimW +: PrimW]),
          .O2  (b_row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 32 && PrimD == 256) begin : g_32x256
        SRAM2RW256x32 u_prim (
          .A1  (a_paddr),
          .A2  (b_paddr),
          .CE1 (a_clk),
          .CE2 (a_clk),
          .WEB1(a_col_web[c]),
          .WEB2(b_col_web[c]),
          .OEB1(1'b0),
          .OEB2(1'b0),
          .CSB1(a_csb),
          .CSB2(b_csb),
          .I1  (a_wdata_pad[c * PrimW +: PrimW]),
          .I2  (b_wdata_pad[c * PrimW +: PrimW]),
          .O1  (a_row_rdata[r][c * PrimW +: PrimW]),
          .O2  (b_row_rdata[r][c * PrimW +: PrimW])
        );
      end else if (PrimW == 32 && PrimD == 512) begin : g_32x512
        SRAM2RW512x32 u_prim (
          .A1  (a_paddr),
          .A2  (b_paddr),
          .CE1 (a_clk),
          .CE2 (a_clk),
          .WEB1(a_col_web[c]),
          .WEB2(b_col_web[c]),
          .OEB1(1'b0),
          .OEB2(1'b0),
          .CSB1(a_csb),
          .CSB2(b_csb),
          .I1  (a_wdata_pad[c * PrimW +: PrimW]),
          .I2  (b_wdata_pad[c * PrimW +: PrimW]),
          .O1  (a_row_rdata[r][c * PrimW +: PrimW]),
          .O2  (b_row_rdata[r][c * PrimW +: PrimW])
        );
      end else begin : g_unsupported
        // Elaboration-time error: no primitive of this size in the curated list.
        initial $fatal(1, "sram_macro_dp_saed14: no %0dx%0d primitive", PrimW, PrimD);
        assign a_row_rdata[r][c * PrimW +: PrimW] = '0;
        assign b_row_rdata[r][c * PrimW +: PrimW] = '0;
      end
    end
  end

endmodule : sram_macro_dp_saed14
