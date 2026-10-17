-- sram_cdc.vhd — Clock-domain crossing between the sram core (clk_a) and a
-- bus port B on its own clock (clk_b), for DUAL_PORT with COMMON_CLK = 0.
--
-- VHDL-2008 twin of sram_cdc.sv (see it for the full description). Port B
-- may only access a power domain while it holds that domain's permission,
-- a four-phase handshake per domain: allow(d) (A -> B) only follows want(d)
-- when it equals hold(d) (B -> A: permission seen, or an access in flight);
-- quiet(d) = not allow(d) and not hold(d) lets the core sleep the domain or
-- start an engine. Also crossed: domain error (A -> B), wake requests, RMW
-- busy and the ECC / IRQ pulses (B -> A). Every signal is registered in its
-- source domain before claude_sync / claude_pulse_sync (IP/common).

library ieee;
use ieee.std_logic_1164.all;

entity sram_cdc is
  generic (
    NPD : positive := 1  -- power domains
  );
  port (
    clk_a        : in  std_ulogic;                          -- core clock (port A)
    rst_a_n      : in  std_ulogic;                          -- clk_a synchronous reset
    clk_b        : in  std_ulogic;                          -- port B clock
    rst_b_n      : in  std_ulogic;                          -- clk_b synchronous reset

    -- clk_a side
    a_want_i     : in  std_ulogic_vector(NPD - 1 downto 0); -- B should be allowed in
    a_err_i      : in  std_ulogic_vector(NPD - 1 downto 0); -- domain access is an error
    a_quiet_o    : out std_ulogic_vector(NPD - 1 downto 0); -- B is out of the domain
    a_wake_o     : out std_ulogic_vector(NPD - 1 downto 0); -- a B request waits for it
    a_busy_o     : out std_ulogic;                          -- B read-modify-write busy
    a_corr_o     : out std_ulogic;                          -- B ECC corrected (pulse)
    a_uncorr_o   : out std_ulogic;                          -- B ECC uncorrectable (pulse)
    a_irq_o      : out std_ulogic;                          -- B error IRQ (pulse)

    -- clk_b side
    b_allow_o    : out std_ulogic_vector(NPD - 1 downto 0); -- synchronized allow
    b_err_o      : out std_ulogic_vector(NPD - 1 downto 0); -- synchronized err
    b_dom_busy_i : in  std_ulogic_vector(NPD - 1 downto 0); -- B access in flight
    b_wake_i     : in  std_ulogic_vector(NPD - 1 downto 0); -- B request waits
    b_busy_i     : in  std_ulogic;                          -- B read-modify-write busy
    b_corr_i     : in  std_ulogic;                          -- ECC corrected (pulse)
    b_uncorr_i   : in  std_ulogic;                          -- ECC uncorrectable (pulse)
    b_irq_i      : in  std_ulogic                           -- error IRQ (pulse)
  );
end entity sram_cdc;

architecture rtl of sram_cdc is

  signal a_allow_q : std_ulogic_vector(NPD - 1 downto 0);  -- registered at the source
  signal a_err_q   : std_ulogic_vector(NPD - 1 downto 0);
  signal a_hold    : std_ulogic_vector(NPD - 1 downto 0);  -- synchronized acknowledge
  signal to_b_d    : std_ulogic_vector(2 * NPD - 1 downto 0);
  signal to_b_q    : std_ulogic_vector(2 * NPD - 1 downto 0);
  signal b_allow   : std_ulogic_vector(NPD - 1 downto 0);

  signal b_hold_q  : std_ulogic_vector(NPD - 1 downto 0);  -- registered at the source
  signal b_wake_q  : std_ulogic_vector(NPD - 1 downto 0);
  signal b_busy_q  : std_ulogic;
  signal to_a_d    : std_ulogic_vector(2 * NPD downto 0);
  signal to_a_q    : std_ulogic_vector(2 * NPD downto 0);

begin

  ----------------------
  -- clk_a -> clk_b   --
  ----------------------
  -- allow follows want only when the handshake is settled (allow = hold).
  p_a_src : process (clk_a) is
  begin
    if rising_edge(clk_a) then
      if rst_a_n = '0' then
        a_allow_q <= (others => '0');
        a_err_q   <= (others => '0');
      else
        for d in 0 to NPD - 1 loop
          if a_allow_q(d) = a_hold(d) then
            a_allow_q(d) <= a_want_i(d);
          end if;
        end loop;
        a_err_q <= a_err_i;
      end if;
    end if;
  end process p_a_src;

  a_quiet_o <= not a_allow_q and not a_hold;
  to_b_d    <= a_err_q & a_allow_q;

  u_sync_to_b : entity work.claude_sync(rtl)
    generic map (
      WIDTH => 2 * NPD
    )
    port map (
      clk   => clk_b,
      rst_n => rst_b_n,
      d_i   => to_b_d,
      q_o   => to_b_q
    );

  b_allow   <= to_b_q(NPD - 1 downto 0);
  b_allow_o <= b_allow;
  b_err_o   <= to_b_q(2 * NPD - 1 downto NPD);

  ----------------------
  -- clk_b -> clk_a   --
  ----------------------
  -- hold: B saw the permission, or an access it started is still in flight.
  p_b_src : process (clk_b) is
  begin
    if rising_edge(clk_b) then
      if rst_b_n = '0' then
        b_hold_q <= (others => '0');
        b_wake_q <= (others => '0');
        b_busy_q <= '0';
      else
        b_hold_q <= b_allow or b_dom_busy_i;
        b_wake_q <= b_wake_i;
        b_busy_q <= b_busy_i;
      end if;
    end if;
  end process p_b_src;

  to_a_d <= b_busy_q & b_wake_q & b_hold_q;

  u_sync_to_a : entity work.claude_sync(rtl)
    generic map (
      WIDTH => 2 * NPD + 1
    )
    port map (
      clk   => clk_a,
      rst_n => rst_a_n,
      d_i   => to_a_d,
      q_o   => to_a_q
    );

  a_hold   <= to_a_q(NPD - 1 downto 0);
  a_wake_o <= to_a_q(2 * NPD - 1 downto NPD);
  a_busy_o <= to_a_q(2 * NPD);

  u_corr : entity work.claude_pulse_sync(rtl)
    port map (
      src_clk     => clk_b,
      src_rst_n   => rst_b_n,
      src_pulse_i => b_corr_i,
      dst_clk     => clk_a,
      dst_rst_n   => rst_a_n,
      dst_pulse_o => a_corr_o
    );

  u_uncorr : entity work.claude_pulse_sync(rtl)
    port map (
      src_clk     => clk_b,
      src_rst_n   => rst_b_n,
      src_pulse_i => b_uncorr_i,
      dst_clk     => clk_a,
      dst_rst_n   => rst_a_n,
      dst_pulse_o => a_uncorr_o
    );

  u_irq : entity work.claude_pulse_sync(rtl)
    port map (
      src_clk     => clk_b,
      src_rst_n   => rst_b_n,
      src_pulse_i => b_irq_i,
      dst_clk     => clk_a,
      dst_rst_n   => rst_a_n,
      dst_pulse_o => a_irq_o
    );

end architecture rtl;
