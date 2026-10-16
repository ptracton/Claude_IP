// sram_pkg.sv — Constants and elaboration-time helper functions for the sram IP.
//
// Technology codes, power-mode encodings, SECDED sizing, the per-technology
// macro selection used to tile the array, and power-mode timing. Everything
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
  // Macro selection. The array is tiled into banks (DEPTH / NUM_BANKS words)
  // and, inside a bank, rows of MAC_D words by columns of MAC_W bits.
  //   macro_width(tech, mw, nlanes)   column width for an mw-bit stored word
  //                                   split into nlanes write lanes
  //   macro_depth(tech, mac_w, bank_d) words per macro (largest available
  //                                   <= bank_d, else the smallest)
  // Macros without a byte mask (SAED) need columns no wider than a lane.
  // -------------------------------------------------------------------------
  function automatic int unsigned round_up8(int unsigned w);
    return ((w + 7) / 8) * 8;
  endfunction

  function automatic int unsigned macro_width(int unsigned tech, int unsigned mw,
                                              int unsigned nlanes);
    int unsigned w;
    case (tech)
      TECH_SAED90, TECH_SAED32, TECH_SAED14: w = ((nlanes > 1) || (mw % 32 != 0)) ? 8 : 32;
      TECH_SKY130:                           w = (mw % 32 == 0) ? 32 : 8;
      default:                               w = round_up8(mw);  // one column per bank
    endcase
    return w;
  endfunction

  // Largest entry of the 5-entry depth list <= bank_d, else the smallest.
  function automatic int unsigned pick_depth(int unsigned bank_d, int unsigned d0,
                                             int unsigned d1, int unsigned d2,
                                             int unsigned d3, int unsigned d4);
    int unsigned best;
    best = d0;  // list is ascending; d0 is the smallest
    if (d1 <= bank_d) best = d1;
    if (d2 <= bank_d) best = d2;
    if (d3 <= bank_d) best = d3;
    if (d4 <= bank_d) best = d4;
    if (d0 > bank_d)  best = d0;
    return best;
  endfunction

  function automatic int unsigned macro_depth(int unsigned tech, int unsigned mac_w,
                                              int unsigned bank_d);
    int unsigned d;
    case (tech)
      // SRAM8x{64..1024}_1rw, SRAM32x{64,256,512}_1rw
      TECH_SAED90: d = (mac_w == 8) ? pick_depth(bank_d, 64, 128, 256, 512, 1024)
                                    : pick_depth(bank_d, 64, 64, 64, 256, 512);
      // SRAMLP1RW{64..1024}x8, SRAMLP1RW{64,256,512}x32
      TECH_SAED32: d = (mac_w == 8) ? pick_depth(bank_d, 64, 128, 256, 512, 1024)
                                    : pick_depth(bank_d, 64, 64, 64, 256, 512);
      // SRAM1RW{16..512}x8 and x32 (16 and 32 folded into the list below)
      TECH_SAED14: d = (bank_d < 64) ? ((bank_d < 32) ? 16 : 32)
                                     : pick_depth(bank_d, 64, 128, 256, 512, 512);
      // sky130_sram_{1,2}kbyte_1rw1r_32x{256,512}_8, sky130_sram_1kbyte_1rw1r_8x1024_8
      TECH_SKY130: d = (mac_w == 32) ? pick_depth(bank_d, 256, 256, 256, 256, 512) : 1024;
      default:     d = bank_d;  // inferred / generic: one tile per bank
    endcase
    return d;
  endfunction

  // -------------------------------------------------------------------------
  // Two-port macro selection (DUAL_PORT). Same rules as above, with each
  // technology's two-port catalogue:
  //   SAED90  SRAM<w>x<d>        w 8/32/39 (39 only 32 deep), d 16..128
  //   SAED32  SRAMLP2RW<d>x<w>   w 8/32, d 16..128
  //   SAED14  SRAM2RW<d>x<w>     w 8/32, d 16..512
  //   SKY130  the 1rw1r macros (port 1 is read-only)
  // -------------------------------------------------------------------------
  function automatic int unsigned macro_width_dp(int unsigned tech, int unsigned mw,
                                                 int unsigned nlanes);
    int unsigned w;
    case (tech)
      TECH_SAED90: w = (nlanes > 1) ? 8 : (mw == 39) ? 39 : (mw % 32 == 0) ? 32 : 8;
      TECH_SAED32, TECH_SAED14: w = ((nlanes > 1) || (mw % 32 != 0)) ? 8 : 32;
      TECH_SKY130: w = (mw % 32 == 0) ? 32 : 8;
      default:     w = round_up8(mw);
    endcase
    return w;
  endfunction

  function automatic int unsigned macro_depth_dp(int unsigned tech, int unsigned mac_w,
                                                 int unsigned bank_d);
    int unsigned d;
    case (tech)
      TECH_SAED90: d = (mac_w == 39) ? 32 : pick_depth(bank_d, 16, 32, 64, 128, 128);
      TECH_SAED32: d = pick_depth(bank_d, 16, 32, 64, 128, 128);
      TECH_SAED14: d = (bank_d >= 512) ? 512 : pick_depth(bank_d, 16, 32, 64, 128, 256);
      TECH_SKY130: d = (mac_w == 32) ? pick_depth(bank_d, 256, 256, 256, 256, 512) : 1024;
      default:     d = bank_d;
    endcase
    return d;
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
