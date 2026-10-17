// sram_pkg.sv — Constants and elaboration-time helper functions for the sram IP.
//
// Technology codes, power-mode encodings, SECDED sizing, the per-technology
// primitive selection used to tile each wrapper, and power-mode timing. Everything
// here is evaluated at elaboration (functions of parameters only).

package sram_pkg;

  // -------------------------------------------------------------------------
  // Technology (TECH parameter)
  // -------------------------------------------------------------------------
  parameter int unsigned TECH_GENERIC = 0;  // behavioral array (sim, formal, Yosys)
  parameter int unsigned TECH_XILINX  = 1;  // xpm_memory_spram
  parameter int unsigned TECH_ALTERA  = 2;  // altsyncram
  parameter int unsigned TECH_SAED90  = 3;  // SRAM<w>x<d>_1rw
  parameter int unsigned TECH_SAED32  = 4;  // SRAMLP1RW<d>x<w> (low-power, LS/DS/SD pins)
  parameter int unsigned TECH_SAED14  = 5;  // SRAM1RW<d>x<w>
  parameter int unsigned TECH_SKY130  = 6;  // OpenRAM sky130_sram_*_1rw1r_*

  // -------------------------------------------------------------------------
  // Power modes (pwr_mode_req_i / pwr_mode_ack_o encoding)
  // -------------------------------------------------------------------------
  parameter logic [1:0] PWR_RUN = 2'd0;  // full operation
  parameter logic [1:0] PWR_LS  = 2'd1;  // light sleep: retained, auto-wake on access
  parameter logic [1:0] PWR_DS  = 2'd2;  // deep sleep: retained, access is a bus error
  parameter logic [1:0] PWR_SD  = 2'd3;  // shutdown: contents lost, access is a bus error

  // -------------------------------------------------------------------------
  // SECDED (extended Hamming) sizing: r Hamming check bits with
  // 2**r >= k + r + 1, plus one overall parity bit.
  // -------------------------------------------------------------------------
  function automatic int unsigned ecc_hamming_bits(int unsigned k);
    int unsigned r;
    r = 1;
    while ((2 ** r) < (k + r + 1)) r++;
    return r;
  endfunction

  function automatic int unsigned ecc_check_bits(int unsigned k);
    return ecc_hamming_bits(k) + 1;
  endfunction

  // Hamming position (1-based) of data bit j: positions that are not powers
  // of two, in increasing order.
  // (Bounded loop so synthesis tools can unroll it: 1024 positions cover
  // any WIDTH up to 1013 bits.)
  function automatic int unsigned ecc_data_pos(int unsigned j);
    int unsigned seen;
    int unsigned result;
    seen   = 0;
    result = 0;
    for (int unsigned pos = 1; pos < 1024; pos++) begin
      if ((pos & (pos - 1)) != 0) begin
        if (seen == j && result == 0) result = pos;
        seen++;
      end
    end
    return result;
  endfunction

  // -------------------------------------------------------------------------
  // Stored word layout. A bus word of `width` bits is stored as width / cw
  // ECC codewords of cw data bits each (cw = width for a single port; for a
  // dual port, the narrower port's width, so each narrow word is one
  // codeword). Write lanes: one per codeword with ECC, one per byte with
  // byte enables, else one.
  // -------------------------------------------------------------------------
  function automatic int unsigned ecc_cw(int unsigned width, int unsigned width_b,
                                         bit dual_port);
    return (dual_port && width_b < width) ? width_b : width;
  endfunction

  function automatic int unsigned stored_width(int unsigned width, int unsigned cw,
                                               bit ecc_en);
    return ecc_en ? (width / cw) * (cw + ecc_check_bits(cw)) : width;
  endfunction

  function automatic int unsigned stored_lanes(int unsigned width, int unsigned cw,
                                               bit byte_en, bit ecc_en);
    return ecc_en ? width / cw : (byte_en ? width / 8 : 1);
  endfunction

  // -------------------------------------------------------------------------
  // Primitive selection. Each technology wrapper (sram_macro_<tech>) builds a
  // W x D memory from ROWS x COLS vendor primitives of PRIM_W x PRIM_D:
  //   prim_width(tech, w, nlanes)    primitive width for a w-bit word split
  //                                  into nlanes write lanes
  //   prim_depth(tech, prim_w, d)    primitive words (deepest available <= d,
  //                                  else the smallest)
  //   tile_rows(d, prim_d)           rows of primitives stacked in depth
  //   lane_of(p, w, nlanes)          write lane of bit p of a w-bit word
  // Primitives without a byte mask (SAED) need columns no wider than a lane.
  // GENERIC / XILINX / ALTERA wrappers are not tiled (one inferred memory of
  // W x D); for them the functions return w and d.
  // -------------------------------------------------------------------------
  function automatic int unsigned prim_width(int unsigned tech, int unsigned w,
                                             int unsigned nlanes);
    int unsigned pw;
    case (tech)
      TECH_SAED90, TECH_SAED32, TECH_SAED14: pw = ((nlanes > 1) || (w % 32 != 0)) ? 8 : 32;
      TECH_SKY130:                           pw = (w % 32 == 0) ? 32 : 8;
      default:                               pw = w;  // not tiled
    endcase
    return pw;
  endfunction

  // Largest entry of the 5-entry depth list <= d, else the smallest.
  function automatic int unsigned pick_depth(int unsigned d, int unsigned d0,
                                             int unsigned d1, int unsigned d2,
                                             int unsigned d3, int unsigned d4);
    int unsigned best;
    best = d0;  // list is ascending; d0 is the smallest
    if (d1 <= d) best = d1;
    if (d2 <= d) best = d2;
    if (d3 <= d) best = d3;
    if (d4 <= d) best = d4;
    if (d0 > d)  best = d0;
    return best;
  endfunction

  function automatic int unsigned prim_depth(int unsigned tech, int unsigned prim_w,
                                             int unsigned d);
    int unsigned pd;
    case (tech)
      // SRAM8x{64..1024}_1rw, SRAM32x{64,256,512}_1rw
      TECH_SAED90: pd = (prim_w == 8) ? pick_depth(d, 64, 128, 256, 512, 1024)
                                      : pick_depth(d, 64, 64, 64, 256, 512);
      // SRAMLP1RW{64..1024}x8, SRAMLP1RW{64,256,512}x32
      TECH_SAED32: pd = (prim_w == 8) ? pick_depth(d, 64, 128, 256, 512, 1024)
                                      : pick_depth(d, 64, 64, 64, 256, 512);
      // SRAM1RW{16..512}x8 and x32 (16 and 32 folded into the list below)
      TECH_SAED14: pd = (d < 64) ? ((d < 32) ? 16 : 32)
                                 : pick_depth(d, 64, 128, 256, 512, 512);
      // sky130_sram_{1,2}kbyte_1rw1r_32x{256,512}_8, sky130_sram_1kbyte_1rw1r_8x1024_8
      TECH_SKY130: pd = (prim_w == 32) ? pick_depth(d, 256, 256, 256, 256, 512) : 1024;
      default:     pd = d;  // not tiled
    endcase
    return pd;
  endfunction

  function automatic int unsigned tile_rows(int unsigned d, int unsigned prim_d);
    return (d > prim_d) ? d / prim_d : 1;
  endfunction

  // Lane of bit p of a w-bit word (bits past the word, i.e. column padding,
  // take the last lane).
  function automatic int unsigned lane_of(int unsigned p, int unsigned w,
                                          int unsigned nlanes);
    int unsigned q;
    q = (p < w) ? p : w - 1;
    return q / (w / nlanes);
  endfunction

  // -------------------------------------------------------------------------
  // Two-port primitive selection (DUAL_PORT). Same rules as above, with each
  // technology's two-port catalogue:
  //   SAED90  SRAM<w>x<d>        w 8/32/39 (39 only 32 deep), d 16..128
  //   SAED32  SRAMLP2RW<d>x<w>   w 8/32, d 16..128
  //   SAED14  SRAM2RW<d>x<w>     w 8/32, d 16..512
  //   SKY130  the 1rw1r macros (port 1 is read-only)
  // -------------------------------------------------------------------------
  function automatic int unsigned prim_width_dp(int unsigned tech, int unsigned w,
                                                int unsigned nlanes);
    int unsigned pw;
    case (tech)
      TECH_SAED90: pw = (nlanes > 1) ? 8 : (w == 39) ? 39 : (w % 32 == 0) ? 32 : 8;
      TECH_SAED32, TECH_SAED14: pw = ((nlanes > 1) || (w % 32 != 0)) ? 8 : 32;
      TECH_SKY130: pw = (w % 32 == 0) ? 32 : 8;
      default:     pw = w;  // not tiled
    endcase
    return pw;
  endfunction

  function automatic int unsigned prim_depth_dp(int unsigned tech, int unsigned prim_w,
                                                int unsigned d);
    int unsigned pd;
    case (tech)
      TECH_SAED90: pd = (prim_w == 39) ? 32 : pick_depth(d, 16, 32, 64, 128, 128);
      TECH_SAED32: pd = pick_depth(d, 16, 32, 64, 128, 128);
      TECH_SAED14: pd = (d >= 512) ? 512 : pick_depth(d, 16, 32, 64, 128, 256);
      TECH_SKY130: pd = (prim_w == 32) ? pick_depth(d, 256, 256, 256, 256, 512) : 1024;
      default:     pd = d;  // not tiled
    endcase
    return pd;
  endfunction

  // -------------------------------------------------------------------------
  // Power-mode timing in clock cycles (entry: pins asserted -> mode reached;
  // wake: pins released -> first access). Conservative defaults; the SAED32
  // low-power values are to be checked against its liberty/databook timing
  // (tLSI/tLSW, tDSI/tDSW) at synthesis.
  // -------------------------------------------------------------------------
  function automatic int unsigned pwr_enter_cycles(int unsigned tech);
    return (tech == TECH_SAED32) ? 4 : 2;
  endfunction

  function automatic int unsigned pwr_wake_cycles(int unsigned tech, logic [1:0] mode);
    int unsigned c;
    case (mode)
      PWR_LS:  c = 2;
      PWR_DS:  c = (tech == TECH_SAED32) ? 8 : 4;
      PWR_SD:  c = (tech == TECH_SAED32) ? 16 : 8;
      default: c = 1;
    endcase
    return c;
  endfunction

endpackage : sram_pkg
