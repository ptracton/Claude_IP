// sram_array.sv — Tiles sram_macro instances into a DEPTH x MW array.
//
// Organisation (all sizes are powers of two except MW):
//   banks    NUM_BANKS groups of BANK_D = DEPTH / NUM_BANKS words; each bank has
//            its own sleep pins (the power domains of BANK_PG).
//   rows     inside a bank, BANK_D / MAC_D tiles of MAC_D words (one row when
//            the chosen macro is deeper than the bank; its top address bits
//            are then tied to 0).
//   columns  COLS = ceil(MW / MAC_W) macros side by side; the last column is
//            zero-padded when MAC_W does not divide MW.
// MAC_W / MAC_D come from sram_pkg::macro_width / macro_depth for TECH.
//
// Write lanes: lane_we_i has NLANES bits, each covering MW / NLANES stored
// bits. Every column byte takes the enable of the lane its first bit falls
// in; sram_pkg::macro_width keeps mask-less macros inside one lane.
//
// Read: rdata_o is valid in the cycle after a read and comes from the tile
// read in the previous cycle.
//
// DUAL_PORT: a second, independent port (b_*) on every tile, using the
// technology's two-port macros (sram_macro_dp, sram_pkg::macro_*_dp). Port B
// has its own read multiplexer. Sleep pins are shared by both ports.

module sram_array #(
  parameter int unsigned TECH      = sram_pkg::TECH_GENERIC, // technology
  parameter int unsigned MW        = 32,    // stored word width (data + ECC)
  parameter int unsigned DEPTH     = 1024,  // words
  parameter int unsigned NUM_BANKS = 1,     // banks (power domains)
  parameter int unsigned NLANES    = 4,     // write lanes
  parameter bit          DUAL_PORT = 0,     // second port (b_*)
  parameter string       INIT_FILE = ""     // preload (GENERIC/FPGA, NUM_BANKS = 1)
) (
  input  logic                       clk,        // clock
  input  logic                       cs_i,       // access this cycle
  input  logic                       we_i,       // 1 = write, 0 = read
  input  logic [$clog2(DEPTH)-1:0]   idx_i,      // word index
  input  logic [MW-1:0]              wdata_i,    // stored word to write
  input  logic [NLANES-1:0]          lane_we_i,  // lanes to write
  input  logic [NUM_BANKS-1:0]       ls_i,       // light sleep, per bank
  input  logic [NUM_BANKS-1:0]       ds_i,       // deep sleep, per bank
  input  logic [NUM_BANKS-1:0]       sd_i,       // shutdown, per bank
  output logic [MW-1:0]              rdata_o,    // stored word (cycle after a read)

  // Port B (DUAL_PORT; tie inputs to 0 otherwise)
  input  logic                       b_cs_i,     // access this cycle
  input  logic                       b_we_i,     // 1 = write
  input  logic [$clog2(DEPTH)-1:0]   b_idx_i,    // word index
  input  logic [MW-1:0]              b_wdata_i,  // stored word to write
  input  logic [NLANES-1:0]          b_lane_we_i,// lanes to write
  output logic [MW-1:0]              b_rdata_o   // stored word (cycle after a read)
);

  localparam int unsigned IdxW   = $clog2(DEPTH);
  localparam int unsigned LaneW  = MW / NLANES;
  localparam int unsigned MacW   = DUAL_PORT ? sram_pkg::macro_width_dp(TECH, MW, NLANES)
                                             : sram_pkg::macro_width(TECH, MW, NLANES);
  localparam int unsigned BankD  = DEPTH / NUM_BANKS;
  localparam int unsigned MacD   = DUAL_PORT ? sram_pkg::macro_depth_dp(TECH, MacW, BankD)
                                             : sram_pkg::macro_depth(TECH, MacW, BankD);
  localparam int unsigned MacAw  = $clog2(MacD);
  localparam int unsigned Cols   = (MW + MacW - 1) / MacW;
  localparam int unsigned PadW   = Cols * MacW;
  localparam int unsigned Rows   = (BankD > MacD) ? BankD / MacD : 1;
  localparam int unsigned Tiles  = NUM_BANKS * Rows;
  // Index bits below the tile number: the macro address (or the whole bank
  // offset when the macro is deeper than the bank).
  localparam int unsigned TileSh = (MacD <= BankD) ? MacAw : $clog2(BankD);
  localparam int unsigned TileW  = (Tiles > 1) ? $clog2(Tiles) : 1;

  // Lane of stored bit p (padding bits take the last lane).
  function automatic int unsigned lane_of(int unsigned p);
    int unsigned q;
    q = (p < MW) ? p : MW - 1;
    return q / LaneW;
  endfunction

  logic [TileW-1:0]  tile,      b_tile;       // tile addressed this cycle
  logic [TileW-1:0]  rd_tile_q, b_rd_tile_q;  // tile read last cycle
  logic [MacAw-1:0]  maddr,     b_maddr;      // macro word address
  logic [PadW-1:0]   wdata_pad, b_wdata_pad;  // write data, zero-padded
  logic [PadW-1:0]   tile_rdata   [Tiles];
  logic [PadW-1:0]   b_tile_rdata [Tiles];

  if (Tiles > 1) begin : g_tile_sel
    assign tile   = TileW'(idx_i >> TileSh);
    assign b_tile = TileW'(b_idx_i >> TileSh);
  end else begin : g_one_tile
    assign tile   = '0;
    assign b_tile = '0;
  end

  if (TileSh > 0) begin : g_maddr
    assign maddr   = MacAw'(idx_i[TileSh-1:0]);
    assign b_maddr = MacAw'(b_idx_i[TileSh-1:0]);
  end else begin : g_maddr_zero
    assign maddr   = '0;
    assign b_maddr = '0;
  end

  assign wdata_pad   = PadW'(wdata_i);
  assign b_wdata_pad = PadW'(b_wdata_i);

  // Remember which tile each port read, for the read multiplexers.
  always_ff @(posedge clk) begin : p_rd_tile
    if (cs_i && !we_i) begin
      rd_tile_q <= tile;
    end
    if (b_cs_i && !b_we_i) begin
      b_rd_tile_q <= b_tile;
    end
  end

  assign rdata_o   = MW'(tile_rdata[rd_tile_q]);
  assign b_rdata_o = DUAL_PORT ? MW'(b_tile_rdata[b_rd_tile_q]) : '0;

  for (genvar t = 0; t < Tiles; t++) begin : g_tile
    localparam int unsigned Bank = t / Rows;

    logic tile_cs, b_tile_cs;
    assign tile_cs   = cs_i && (tile == TileW'(t));
    assign b_tile_cs = b_cs_i && (b_tile == TileW'(t));

    for (genvar c = 0; c < Cols; c++) begin : g_col
      logic [MacW/8-1:0] col_wbe, b_col_wbe;

      for (genvar k = 0; k < MacW / 8; k++) begin : g_byte
        assign col_wbe[k]   = lane_we_i[lane_of(c * MacW + 8 * k)];
        assign b_col_wbe[k] = b_lane_we_i[lane_of(c * MacW + 8 * k)];
      end

      if (DUAL_PORT) begin : g_dp
        sram_macro_dp #(
          .TECH     (TECH),
          .MAC_W    (MacW),
          .MAC_D    (MacD),
          .INIT_FILE(INIT_FILE)
        ) u_macro (
          .clk      (clk),
          .a_cs_i   (tile_cs),
          .a_we_i   (we_i),
          .a_addr_i (maddr),
          .a_wdata_i(wdata_pad[c * MacW +: MacW]),
          .a_wbe_i  (col_wbe),
          .a_rdata_o(tile_rdata[t][c * MacW +: MacW]),
          .b_cs_i   (b_tile_cs),
          .b_we_i   (b_we_i),
          .b_addr_i (b_maddr),
          .b_wdata_i(b_wdata_pad[c * MacW +: MacW]),
          .b_wbe_i  (b_col_wbe),
          .b_rdata_o(b_tile_rdata[t][c * MacW +: MacW]),
          .ls_i     (ls_i[Bank]),
          .ds_i     (ds_i[Bank]),
          .sd_i     (sd_i[Bank])
        );
      end else begin : g_sp
        assign b_tile_rdata[t][c * MacW +: MacW] = '0;

        sram_macro #(
          .TECH     (TECH),
          .MAC_W    (MacW),
          .MAC_D    (MacD),
          .INIT_FILE(INIT_FILE)
        ) u_macro (
          .clk    (clk),
          .cs_i   (tile_cs),
          .we_i   (we_i),
          .addr_i (maddr),
          .wdata_i(wdata_pad[c * MacW +: MacW]),
          .wbe_i  (col_wbe),
          .ls_i   (ls_i[Bank]),
          .ds_i   (ds_i[Bank]),
          .sd_i   (sd_i[Bank]),
          .rdata_o(tile_rdata[t][c * MacW +: MacW])
        );
      end
    end
  end

endmodule : sram_array
