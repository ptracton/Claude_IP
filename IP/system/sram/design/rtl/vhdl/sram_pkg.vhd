-- sram_pkg.vhd — Constants and elaboration-time helper functions for the sram IP.
--
-- VHDL-2008 twin of sram_pkg.sv: technology codes, power-mode encodings,
-- SECDED sizing, per-technology macro selection and power-mode timing, plus
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
  function mem_width(width : natural; ecc_en : natural) return natural;
  function num_lanes(width : natural; byte_en : natural; ecc_en : natural) return natural;
  function num_domains(bank_pg : natural; num_banks : natural) return natural;

  -- Macro selection (see sram_pkg.sv).
  function round_up8(w : natural) return natural;
  function macro_width(tech : natural; mw : natural; nlanes : natural) return natural;
  function pick_depth(bank_d : natural; d0, d1, d2, d3, d4 : natural) return natural;
  function macro_depth(tech : natural; mac_w : natural; bank_d : natural) return natural;

  -- Two-port macro selection (DUAL_PORT; see sram_pkg.sv).
  function macro_width_dp(tech : natural; mw : natural; nlanes : natural) return natural;
  function macro_depth_dp(tech : natural; mac_w : natural; bank_d : natural) return natural;

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

  function mem_width(width : natural; ecc_en : natural) return natural is
  begin
    if ecc_en /= 0 then
      return width + ecc_check_bits(width);
    end if;
    return width;
  end function mem_width;

  function num_lanes(width : natural; byte_en : natural; ecc_en : natural) return natural is
  begin
    if byte_en /= 0 and ecc_en = 0 then
      return width / 8;
    end if;
    return 1;
  end function num_lanes;

  function num_domains(bank_pg : natural; num_banks : natural) return natural is
  begin
    if bank_pg /= 0 then
      return num_banks;
    end if;
    return 1;
  end function num_domains;

  function round_up8(w : natural) return natural is
  begin
    return ((w + 7) / 8) * 8;
  end function round_up8;

  function macro_width(tech : natural; mw : natural; nlanes : natural) return natural is
  begin
    if tech = TECH_SAED90_C or tech = TECH_SAED32_C or tech = TECH_SAED14_C then
      if nlanes > 1 or (mw mod 32) /= 0 then
        return 8;
      end if;
      return 32;
    elsif tech = TECH_SKY130_C then
      if (mw mod 32) = 0 then
        return 32;
      end if;
      return 8;
    end if;
    return round_up8(mw); -- one column per bank
  end function macro_width;

  -- Largest entry of the ascending 5-entry list <= bank_d, else the smallest.
  function pick_depth(bank_d : natural; d0, d1, d2, d3, d4 : natural) return natural is
    variable best : natural;
  begin
    best := d0;
    for i in 1 to 4 loop
      case i is
        when 1 =>
          if d1 <= bank_d then
            best := d1;
          end if;
        when 2 =>
          if d2 <= bank_d then
            best := d2;
          end if;
        when 3 =>
          if d3 <= bank_d then
            best := d3;
          end if;
        when others =>
          if d4 <= bank_d then
            best := d4;
          end if;
      end case;
    end loop;
    return best;
  end function pick_depth;

  function macro_depth(tech : natural; mac_w : natural; bank_d : natural) return natural is
  begin
    if tech = TECH_SAED90_C or tech = TECH_SAED32_C then
      -- SAED90 SRAM8x{64..1024}_1rw / SRAM32x{64,256,512}_1rw,
      -- SAED32 SRAMLP1RW{64..1024}x8 / SRAMLP1RW{64,256,512}x32
      if mac_w = 8 then
        return pick_depth(bank_d, 64, 128, 256, 512, 1024);
      end if;
      return pick_depth(bank_d, 64, 64, 64, 256, 512);
    elsif tech = TECH_SAED14_C then
      -- SRAM1RW{16..512}x8 and x32
      if bank_d < 32 then
        return 16;
      elsif bank_d < 64 then
        return 32;
      end if;
      return pick_depth(bank_d, 64, 128, 256, 512, 512);
    elsif tech = TECH_SKY130_C then
      if mac_w = 32 then
        return pick_depth(bank_d, 256, 256, 256, 256, 512);
      end if;
      return 1024;
    end if;
    return bank_d; -- inferred / generic: one tile per bank
  end function macro_depth;

  function macro_width_dp(tech : natural; mw : natural; nlanes : natural) return natural is
  begin
    if tech = TECH_SAED90_C then
      if nlanes > 1 then
        return 8;
      elsif mw = 39 then
        return 39;
      elsif (mw mod 32) = 0 then
        return 32;
      end if;
      return 8;
    elsif tech = TECH_SAED32_C or tech = TECH_SAED14_C then
      if nlanes > 1 or (mw mod 32) /= 0 then
        return 8;
      end if;
      return 32;
    elsif tech = TECH_SKY130_C then
      if (mw mod 32) = 0 then
        return 32;
      end if;
      return 8;
    end if;
    return round_up8(mw);
  end function macro_width_dp;

  function macro_depth_dp(tech : natural; mac_w : natural; bank_d : natural) return natural is
  begin
    if tech = TECH_SAED90_C then
      if mac_w = 39 then
        return 32;
      end if;
      return pick_depth(bank_d, 16, 32, 64, 128, 128);
    elsif tech = TECH_SAED32_C then
      return pick_depth(bank_d, 16, 32, 64, 128, 128);
    elsif tech = TECH_SAED14_C then
      if bank_d >= 512 then
        return 512;
      end if;
      return pick_depth(bank_d, 16, 32, 64, 128, 256);
    elsif tech = TECH_SKY130_C then
      if mac_w = 32 then
        return pick_depth(bank_d, 256, 256, 256, 256, 512);
      end if;
      return 1024;
    end if;
    return bank_d;
  end function macro_depth_dp;

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
