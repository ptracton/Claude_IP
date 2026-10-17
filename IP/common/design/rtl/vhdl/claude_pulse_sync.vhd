-- claude_pulse_sync.vhd — Single-cycle pulse crossing between clock domains.
--
-- VHDL-2008 twin of claude_pulse_sync.sv; behaviour is identical.
-- Each src_pulse_i (one src_clk cycle wide) flips a toggle flop in the
-- source domain; the toggle is synchronized into dst_clk (claude_sync) and
-- every change becomes a one-cycle dst_pulse_o. Pulses closer together
-- than about three destination cycles plus one source cycle may merge, so
-- use it for events, not counts that must be exact.
-- Each domain has its own synchronous active-low reset; reset both
-- together.

library ieee;
use ieee.std_logic_1164.all;

entity claude_pulse_sync is
  generic (
    STAGES : positive := 2   -- synchronizer flops (>= 2)
  );
  port (
    src_clk     : in  std_ulogic;  -- source clock
    src_rst_n   : in  std_ulogic;  -- source synchronous active-low reset
    src_pulse_i : in  std_ulogic;  -- event (one src_clk cycle)
    dst_clk     : in  std_ulogic;  -- destination clock
    dst_rst_n   : in  std_ulogic;  -- destination synchronous active-low reset
    dst_pulse_o : out std_ulogic   -- event (one dst_clk cycle)
  );
end entity claude_pulse_sync;

architecture rtl of claude_pulse_sync is

  signal src_tgl_q : std_ulogic := '0';  -- flips on every source pulse
  signal src_tgl_v : std_ulogic_vector(0 downto 0);  -- src_tgl_q as a vector
  signal dst_tgl   : std_ulogic_vector(0 downto 0);  -- synchronized toggle
  signal dst_tgl_q : std_ulogic := '0';  -- synchronized toggle, one cycle later

begin

  -- Source toggle.
  p_src : process (src_clk) is
  begin
    if rising_edge(src_clk) then
      if src_rst_n = '0' then
        src_tgl_q <= '0';
      elsif src_pulse_i = '1' then
        src_tgl_q <= not src_tgl_q;
      end if;
    end if;
  end process p_src;

  src_tgl_v(0) <= src_tgl_q;

  u_sync : entity work.claude_sync(rtl)
    generic map (
      WIDTH  => 1,
      STAGES => STAGES
    )
    port map (
      clk   => dst_clk,
      rst_n => dst_rst_n,
      d_i   => src_tgl_v,
      q_o   => dst_tgl
    );

  -- Destination edge detect.
  p_dst : process (dst_clk) is
  begin
    if rising_edge(dst_clk) then
      if dst_rst_n = '0' then
        dst_tgl_q <= '0';
      else
        dst_tgl_q <= dst_tgl(0);
      end if;
    end if;
  end process p_dst;

  dst_pulse_o <= dst_tgl(0) xor dst_tgl_q;

end architecture rtl;
