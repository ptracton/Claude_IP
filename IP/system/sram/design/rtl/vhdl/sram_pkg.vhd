-- sram_pkg.vhd — Constants and elaboration-time helper functions for the sram IP.
--
-- VHDL-2008 twin of sram_pkg.sv: technology codes, power-mode encodings,
-- SECDED sizing, per-technology primitive selection and power-mode timing, plus
-- the width helpers VHDL needs (clog2 and the derived widths that the SV
-- modules declare as localparams).
-- One-bit options are natural generics (0 / 1) so the entities bind cleanly
-- to SystemVerilog parameters in mixed-language simulation.

library ieee;
use ieee.std_logic_1164.all;

package sram_pkg is

  -- Technology (TECH generic)
  constant TECH_GENERIC_C : natural := 0; -- behavioral array (sim, formal, Yosys)
  constant TECH_XILINX_C  : natural := 1; -- xpm_memory_spram
  constant TECH_ALTERA_C  : natural := 2; -- altsyncram
  constant TECH_SAED90_C  : natural := 3; -- SRAM<w>x<d>_1rw
  constant TECH_SAED32_C  : natural := 4; -- SRAMLP1RW<d>x<w> (LS/DS/SD pins)
  constant TECH_SAED14_C  : natural := 5; -- SRAM1RW<d>x<w>
  constant TECH_SKY130_C  : natural := 6; -- OpenRAM sky130_sram_*_1rw1r_*

  -- Power modes (pwr_mode_req_i / pwr_mode_ack_o encoding)
  constant PWR_RUN_C : std_ulogic_vector(1 downto 0) := "00"; -- full operation
  constant PWR_LS_C  : std_ulogic_vector(1 downto 0) := "01"; -- light sleep
  constant PWR_DS_C  : std_ulogic_vector(1 downto 0) := "10"; -- deep sleep
  constant PWR_SD_C  : std_ulogic_vector(1 downto 0) := "11"; -- shutdown

  -- ceil(log2(n)), 0 for n <= 1.
  function clog2(n : natural) return natural;

  -- SECDED (extended Hamming): r Hamming bits with 2**r >= k + r + 1, plus
  -- one overall parity bit; ecc_data_pos(j) = Hamming position of data bit j.
  function ecc_hamming_bits(k : natural) return natural;
  function ecc_check_bits(k : natural) return natural;
  function ecc_data_pos(j : natural) return natural;

  -- Derived widths (SV localparams).
  -- Stored word layout (see sram_pkg.sv): width / cw ECC codewords of cw data
  -- bits; lanes = codewords with ECC, bytes with byte enables, else one.
  function ecc_cw(width : natural; width_b : natural; dual_port : natural) return natural;
  function stored_width(width : natural; cw : natural; ecc_en : natural) return natural;
  function stored_lanes(width : natural; cw : natural; byte_en : natural;
                        ecc_en : natural) return natural;
  function num_domains(bank_pg : natural; num_banks : natural) return natural;

  -- Primitive selection of the tiled technology wrappers (see sram_pkg.sv).
  function prim_width(tech : natural; w : natural; nlanes : natural) return natural;
  function pick_depth(d : natural; d0, d1, d2, d3, d4 : natural) return natural;
  function prim_depth(tech : natural; prim_w : natural; d : natural) return natural;
  function tile_rows(d : natural; prim_d : natural) return natural;
  function lane_of(p : natural; w : natural; nlanes : natural) return natural;

  -- Two-port primitive selection (DUAL_PORT; see sram_pkg.sv).
  function prim_width_dp(tech : natural; w : natural; nlanes : natural) return natural;
  function prim_depth_dp(tech : natural; prim_w : natural; d : natural) return natural;

  -- Power-mode timing in clock cycles (mode: 1 = LS, 2 = DS, 3 = SD).
  function pwr_enter_cycles(tech : natural) return natural;
  function pwr_wake_cycles(tech : natural; mode : natural) return natural;

end package sram_pkg;

package body sram_pkg is

  function clog2(n : natural) return natural is
    variable r : natural := 0;
  begin
    while (2 ** r) < n loop
      r := r + 1;
    end loop;
    return r;
  end function clog2;

  function ecc_hamming_bits(k : natural) return natural is
    variable r : natural := 1;
  begin
    while (2 ** r) < (k + r + 1) loop
      r := r + 1;
    end loop;
    return r;
  end function ecc_hamming_bits;

  function ecc_check_bits(k : natural) return natural is
  begin
    return ecc_hamming_bits(k) + 1;
  end function ecc_check_bits;

  -- Positions that are not powers of two, in increasing order (bounded loop
  -- so synthesis can unroll it; covers widths up to 1013 bits).
  function ecc_data_pos(j : natural) return natural is
    variable seen   : natural := 0;
    variable result : natural := 0;
    variable is_pow : boolean;
    variable p      : natural;
  begin
    for pos in 1 to 1023 loop
      is_pow := false;
      p      := 1;
      while p <= pos loop
        if p = pos then
          is_pow := true;
        end if;
        p := p * 2;
      end loop;
      if not is_pow then
        if seen = j and result = 0 then
          result := pos;
        end if;
        seen := seen + 1;
      end if;
    end loop;
    return result;
  end function ecc_data_pos;

  function ecc_cw(width : natural; width_b : natural; dual_port : natural) return natural is
  begin
    if dual_port /= 0 and width_b < width then
      return width_b;
    end if;
    return width;
  end function ecc_cw;

  function stored_width(width : natural; cw : natural; ecc_en : natural) return natural is
  begin
    if ecc_en /= 0 then
      return (width / cw) * (cw + ecc_check_bits(cw));
    end if;
    return width;
  end function stored_width;

  function stored_lanes(width : natural; cw : natural; byte_en : natural;
                        ecc_en : natural) return natural is
  begin
    if ecc_en /= 0 then
      return width / cw;
    elsif byte_en /= 0 then
      return width / 8;
    end if;
    return 1;
  end function stored_lanes;

  function num_domains(bank_pg : natural; num_banks : natural) return natural is
  begin
    if bank_pg /= 0 then
      return num_banks;
    end if;
    return 1;
  end function num_domains;

  function prim_width(tech : natural; w : natural; nlanes : natural) return natural is
  begin
    if tech = TECH_SAED90_C or tech = TECH_SAED32_C or tech = TECH_SAED14_C then
      if nlanes > 1 or (w mod 32) /= 0 then
        return 8;
      end if;
      return 32;
    elsif tech = TECH_SKY130_C then
      if (w mod 32) = 0 then
        return 32;
      end if;
      return 8;
    end if;
    return w; -- not tiled
  end function prim_width;

  -- Largest entry of the ascending 5-entry list <= d, else the smallest.
  function pick_depth(d : natural; d0, d1, d2, d3, d4 : natural) return natural is
    variable best : natural;
  begin
    best := d0;
    for i in 1 to 4 loop
      case i is
        when 1 =>
          if d1 <= d then
            best := d1;
          end if;
        when 2 =>
          if d2 <= d then
            best := d2;
          end if;
        when 3 =>
          if d3 <= d then
            best := d3;
          end if;
        when others =>
          if d4 <= d then
            best := d4;
          end if;
      end case;
    end loop;
    return best;
  end function pick_depth;

  function prim_depth(tech : natural; prim_w : natural; d : natural) return natural is
  begin
    if tech = TECH_SAED90_C or tech = TECH_SAED32_C then
      -- SAED90 SRAM8x{64..1024}_1rw / SRAM32x{64,256,512}_1rw,
      -- SAED32 SRAMLP1RW{64..1024}x8 / SRAMLP1RW{64,256,512}x32
      if prim_w = 8 then
        return pick_depth(d, 64, 128, 256, 512, 1024);
      end if;
      return pick_depth(d, 64, 64, 64, 256, 512);
    elsif tech = TECH_SAED14_C then
      -- SRAM1RW{16..512}x8 and x32
      if d < 32 then
        return 16;
      elsif d < 64 then
        return 32;
      end if;
      return pick_depth(d, 64, 128, 256, 512, 512);
    elsif tech = TECH_SKY130_C then
      if prim_w = 32 then
        return pick_depth(d, 256, 256, 256, 256, 512);
      end if;
      return 1024;
    end if;
    return d; -- not tiled
  end function prim_depth;

  function tile_rows(d : natural; prim_d : natural) return natural is
  begin
    if d > prim_d then
      return d / prim_d;
    end if;
    return 1;
  end function tile_rows;

  -- Lane of bit p of a w-bit word (column padding bits take the last lane).
  function lane_of(p : natural; w : natural; nlanes : natural) return natural is
  begin
    if p < w then
      return p / (w / nlanes);
    end if;
    return (w - 1) / (w / nlanes);
  end function lane_of;

  function prim_width_dp(tech : natural; w : natural; nlanes : natural) return natural is
  begin
    if tech = TECH_SAED90_C then
      if nlanes > 1 then
        return 8;
      elsif w = 39 then
        return 39;
      elsif (w mod 32) = 0 then
        return 32;
      end if;
      return 8;
    elsif tech = TECH_SAED32_C or tech = TECH_SAED14_C then
      if nlanes > 1 or (w mod 32) /= 0 then
        return 8;
      end if;
      return 32;
    elsif tech = TECH_SKY130_C then
      if (w mod 32) = 0 then
        return 32;
      end if;
      return 8;
    end if;
    return w; -- not tiled
  end function prim_width_dp;

  function prim_depth_dp(tech : natural; prim_w : natural; d : natural) return natural is
  begin
    if tech = TECH_SAED90_C then
      if prim_w = 39 then
        return 32;
      end if;
      return pick_depth(d, 16, 32, 64, 128, 128);
    elsif tech = TECH_SAED32_C then
      return pick_depth(d, 16, 32, 64, 128, 128);
    elsif tech = TECH_SAED14_C then
      if d >= 512 then
        return 512;
      end if;
      return pick_depth(d, 16, 32, 64, 128, 256);
    elsif tech = TECH_SKY130_C then
      if prim_w = 32 then
        return pick_depth(d, 256, 256, 256, 256, 512);
      end if;
      return 1024;
    end if;
    return d; -- not tiled
  end function prim_depth_dp;

  function pwr_enter_cycles(tech : natural) return natural is
  begin
    if tech = TECH_SAED32_C then
      return 4;
    end if;
    return 2;
  end function pwr_enter_cycles;

  function pwr_wake_cycles(tech : natural; mode : natural) return natural is
  begin
    case mode is
      when 1 =>
        return 2;
      when 2 =>
        if tech = TECH_SAED32_C then
          return 8;
        end if;
        return 4;
      when 3 =>
        if tech = TECH_SAED32_C then
          return 16;
        end if;
        return 8;
      when others =>
        return 1;
    end case;
  end function pwr_wake_cycles;

end package body sram_pkg;
