-- sram_clr.vhd — Clear engine for the sram IP: writes zero to whole domains.
--
-- VHDL-2008 twin of sram_clr.sv (see it for the full description).
-- Requests (start_i + mask_i, auto_i after shutdown, or every domain at
-- reset with CLEAR_ON_RESET) collect in a pending mask; a pass starts when
-- the bus port is idle and writes one word per cycle in every selected
-- domain, skipping the others a domain at a time and waking light-sleeping
-- ones. done_o / dom_done_o pulse at the end of a pass.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sram_pkg.all;

entity sram_clr is
  generic (
    DEPTH          : positive := 1024; -- words
    NPD            : positive := 1;    -- power domains (equal-size slices)
    CLEAR_ON_RESET : natural  := 0     -- clear everything after reset (0 / 1)
  );
  port (
    clk         : in  std_ulogic;                                  -- clock
    rst_n       : in  std_ulogic;                                  -- synchronous active-low reset
    start_i     : in  std_ulogic;                                  -- software clear request (pulse)
    mask_i      : in  std_ulogic_vector(NPD - 1 downto 0);         -- domains for start_i
    auto_i      : in  std_ulogic_vector(NPD - 1 downto 0);         -- domains needing a clear
    port_idle_i : in  std_ulogic;                                  -- bus port has nothing in flight
    ok_i        : in  std_ulogic_vector(NPD - 1 downto 0);         -- domain accepts engine writes
    wakeable_i  : in  std_ulogic_vector(NPD - 1 downto 0);         -- domain may be woken
    wake_o      : out std_ulogic_vector(NPD - 1 downto 0);         -- wake this domain
    pending_o   : out std_ulogic;                                  -- work pending or running
    busy_o      : out std_ulogic;                                  -- a pass is running
    done_o      : out std_ulogic;                                  -- pass finished (pulse)
    dom_done_o  : out std_ulogic_vector(NPD - 1 downto 0);         -- domains cleared (pulse)
    cs_o        : out std_ulogic;                                  -- array write this cycle
    idx_o       : out std_ulogic_vector(clog2(DEPTH) - 1 downto 0) -- word index written
  );
end entity sram_clr;

architecture rtl of sram_clr is

  constant IDX_W_C  : positive := clog2(DEPTH);
  constant DOM_D_C  : positive := DEPTH / NPD;    -- words per domain
  constant DOM_SH_C : natural  := clog2(DOM_D_C); -- index bits inside a domain

  function reset_mask return std_ulogic_vector is
  begin
    if CLEAR_ON_RESET /= 0 then
      return (NPD - 1 downto 0 => '1');
    end if;
    return (NPD - 1 downto 0 => '0');
  end function reset_mask;

  signal active_q   : std_ulogic;
  signal pend_q     : std_ulogic_vector(NPD - 1 downto 0);
  signal pend_d     : std_ulogic_vector(NPD - 1 downto 0);
  signal cur_q      : std_ulogic_vector(NPD - 1 downto 0); -- domains of the running pass
  signal idx_q      : unsigned(IDX_W_C downto 0);          -- extra bit: pass ends on overflow
  signal idx_d      : unsigned(IDX_W_C downto 0);
  signal dom        : natural range 0 to NPD - 1; -- domain of idx_q
  signal step       : std_ulogic;                 -- advance one word
  signal skip       : std_ulogic;                 -- advance to the next domain
  signal last       : std_ulogic;                 -- this cycle finishes the pass
  signal start_pass : std_ulogic;

begin

  gen_dom : if NPD > 1 generate
    dom <= to_integer(shift_right(idx_q(IDX_W_C - 1 downto 0), DOM_SH_C));
  else generate
    dom <= 0;
  end generate gen_dom;

  -- Work in the current domain: write, wait for a wake-up, or skip it.
  p_step : process (all) is
  begin
    step   <= '0';
    skip   <= '0';
    wake_o <= (others => '0');
    cs_o   <= '0';
    if active_q = '1' then
      if cur_q(dom) = '0' then
        skip <= '1';
      elsif ok_i(dom) = '1' then
        cs_o <= '1';
        step <= '1';
      elsif wakeable_i(dom) = '1' then
        wake_o(dom) <= '1';
      else
        skip <= '1';
      end if;
    end if;
  end process p_step;

  p_next_idx : process (all) is
  begin
    idx_d <= idx_q;
    if step = '1' then
      idx_d <= idx_q + 1;
    elsif skip = '1' then
      idx_d <= to_unsigned((dom + 1) * DOM_D_C, IDX_W_C + 1);
    end if;
  end process p_next_idx;

  last       <= active_q and idx_d(IDX_W_C);
  start_pass <= '1' when active_q = '0' and unsigned(pend_q) /= 0 and port_idle_i = '1' else '0';

  -- New requests join the pending mask, except domains this pass covers.
  p_pending : process (all) is
    variable p : std_ulogic_vector(NPD - 1 downto 0);
  begin
    p := pend_q or auto_i;
    if start_i = '1' then
      p := p or mask_i;
    end if;
    if active_q = '1' then
      p := p and not cur_q;
    end if;
    if start_pass = '1' then
      p := (others => '0');
    end if;
    pend_d <= p;
  end process p_pending;

  -- Pass control, pending mask and word index.
  p_regs : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        active_q <= '0';
        pend_q   <= reset_mask;
        cur_q    <= (others => '0');
        idx_q    <= (others => '0');
      else
        pend_q <= pend_d;
        if start_pass = '1' then
          active_q <= '1';
          cur_q    <= pend_q;
          idx_q    <= (others => '0');
        elsif last = '1' then
          active_q <= '0';
          cur_q    <= (others => '0');
          idx_q    <= (others => '0');
        else
          idx_q <= idx_d;
        end if;
      end if;
    end if;
  end process p_regs;

  idx_o      <= std_ulogic_vector(idx_q(IDX_W_C - 1 downto 0));
  busy_o     <= active_q;
  pending_o  <= '1' when active_q = '1' or unsigned(pend_q) /= 0 else '0';
  done_o     <= last;
  dom_done_o <= cur_q when last = '1' else (others => '0');

end architecture rtl;
