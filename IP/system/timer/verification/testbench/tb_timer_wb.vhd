-- tb_timer_wb.vhd — Wishbone B4 testbench for timer IP (VHDL-2008).
--
-- Instantiates timer_wb and drives the Wishbone B4 bus to run a basic
-- directed test sequence covering:
--   1. Reset state verification
--   2. Register read/write (CTRL, LOAD)
--   3. COUNT read-only check
--   4. Timer repeat mode interrupt
--
-- Note: Wishbone uses synchronous active-high RST_I (RST_POL=0 means
-- the DUT's internal reset is active-low; RST_I is inverted inside the IF).
-- Bus transactions are inlined in the stimulus process to avoid VHDL
-- signal-mode procedure-parameter constraints.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ip_test_pkg.all;
use std.env.all;

entity tb_timer_wb is
end entity tb_timer_wb;

architecture sim of tb_timer_wb is

  component timer_wb is
    generic (
      DATA_W  : positive := 32;
      ADDR_W  : positive := 4;
      RST_POL : natural  := 0
    );
    port (
      CLK_I   : in  std_ulogic;
      RST_I   : in  std_ulogic;
      CYC_I   : in  std_ulogic;
      STB_I   : in  std_ulogic;
      WE_I    : in  std_ulogic;
      ADR_I   : in  std_ulogic_vector(11 downto 0);
      DAT_I   : in  std_ulogic_vector(31 downto 0);
      SEL_I   : in  std_ulogic_vector(3 downto 0);
      DAT_O   : out std_ulogic_vector(31 downto 0);
      ACK_O   : out std_ulogic;
      ERR_O   : out std_ulogic;
      irq         : out std_ulogic;
      trigger_out : out std_ulogic
    );
  end component timer_wb;

  constant CLK_PERIOD : time := 10 ns;

  signal clk   : std_ulogic := '0';
  signal RST_I : std_ulogic := '1'; -- active-high reset

  signal CYC_I : std_ulogic := '0';
  signal STB_I : std_ulogic := '0';
  signal WE_I  : std_ulogic := '0';
  signal ADR_I : std_ulogic_vector(11 downto 0) := (others => '0');
  signal DAT_I : std_ulogic_vector(31 downto 0) := (others => '0');
  signal SEL_I : std_ulogic_vector(3 downto 0) := (others => '1');
  signal DAT_O : std_ulogic_vector(31 downto 0);
  signal ACK_O : std_ulogic;
  signal ERR_O : std_ulogic;
  signal irq         : std_ulogic;
  signal trigger_out : std_ulogic;

  signal sim_done : boolean := false;

begin

  clk <= not clk after CLK_PERIOD / 2;

  u_dut : timer_wb
    generic map (DATA_W => 32, ADDR_W => 4, RST_POL => 0)
    port map (
      CLK_I       => clk,
      RST_I       => RST_I,
      CYC_I       => CYC_I,
      STB_I       => STB_I,
      WE_I        => WE_I,
      ADR_I       => ADR_I,
      DAT_I       => DAT_I,
      SEL_I       => SEL_I,
      DAT_O       => DAT_O,
      ACK_O       => ACK_O,
      ERR_O       => ERR_O,
      irq         => irq,
      trigger_out => trigger_out
    );

  p_timeout : process is
  begin
    wait for 1 ms;
    if not sim_done then
      report "FAIL tb_timer_wb: simulation timeout" severity failure;
    end if;
    wait;
  end process p_timeout;

  -- -------------------------------------------------------------------------
  -- Stimulus — bus transactions inlined
  -- Wishbone B4 single-cycle transaction (AWREADY=1 always):
  --   Write: assert CYC+STB+WE+ADR+DAT+SEL; wait for ACK (1 cycle later);
  --          deassert CYC+STB+WE; idle 1 cycle.
  --   Read:  assert CYC+STB+ADR+SEL; wait for ACK; capture DAT_O;
  --          deassert CYC+STB; idle 1 cycle.
  -- -------------------------------------------------------------------------
  p_stim : process is
    variable rdata_v     : std_ulogic_vector(31 downto 0);
    variable saved_count : std_ulogic_vector(31 downto 0);
    variable timeout     : integer;
  begin
    RST_I <= '1';
    CYC_I <= '0';
    STB_I <= '0';
    WE_I  <= '0';
    ADR_I <= (others => '0');
    DAT_I <= (others => '0');
    SEL_I <= (others => '1');
    for i in 0 to 7 loop
      wait until rising_edge(clk);
    end loop;
    RST_I <= '0';
    wait until rising_edge(clk);

    -- ---- Test: reset values ----
    test_start("test_reset");

    -- Read CTRL (0x000)
    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '0'; ADR_I <= x"000"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    rdata_v := DAT_O;
    CYC_I <= '0'; STB_I <= '0';
    wait until rising_edge(clk);
    check_eq(rdata_v, x"00000000", "CTRL reset");

    -- Read STATUS (0x004)
    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '0'; ADR_I <= x"004"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    rdata_v := DAT_O;
    CYC_I <= '0'; STB_I <= '0';
    wait until rising_edge(clk);
    check_eq(rdata_v, x"00000000", "STATUS reset");

    -- Read LOAD (0x008)
    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '0'; ADR_I <= x"008"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    rdata_v := DAT_O;
    CYC_I <= '0'; STB_I <= '0';
    wait until rising_edge(clk);
    check_eq(rdata_v, x"00000000", "LOAD reset");

    -- Read COUNT (0x00C)
    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '0'; ADR_I <= x"00C"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    rdata_v := DAT_O;
    CYC_I <= '0'; STB_I <= '0';
    wait until rising_edge(clk);
    check_eq(rdata_v, x"00000000", "COUNT reset");

    test_done("test_reset");

    -- ---- Test: write/read CTRL ----
    test_start("test_rw");

    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '1';
    ADR_I <= x"000"; DAT_I <= x"00000005"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    CYC_I <= '0'; STB_I <= '0'; WE_I <= '0';
    wait until rising_edge(clk);

    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '0'; ADR_I <= x"000"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    rdata_v := DAT_O;
    CYC_I <= '0'; STB_I <= '0';
    wait until rising_edge(clk);
    check_eq(rdata_v, x"00000005", "CTRL write/read");

    -- Clear CTRL
    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '1';
    ADR_I <= x"000"; DAT_I <= x"00000000"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    CYC_I <= '0'; STB_I <= '0'; WE_I <= '0';
    wait until rising_edge(clk);

    -- ---- Test: write/read LOAD ----
    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '1';
    ADR_I <= x"008"; DAT_I <= x"DEADBEEF"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    CYC_I <= '0'; STB_I <= '0'; WE_I <= '0';
    wait until rising_edge(clk);

    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '0'; ADR_I <= x"008"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    rdata_v := DAT_O;
    CYC_I <= '0'; STB_I <= '0';
    wait until rising_edge(clk);
    check_eq(rdata_v, x"DEADBEEF", "LOAD write/read");

    -- Restore LOAD
    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '1';
    ADR_I <= x"008"; DAT_I <= x"00000000"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    CYC_I <= '0'; STB_I <= '0'; WE_I <= '0';
    wait until rising_edge(clk);

    -- ---- Test: COUNT read-only ----
    -- Read COUNT before write attempt (save baseline)
    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '0'; ADR_I <= x"00C"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    saved_count := DAT_O;
    CYC_I <= '0'; STB_I <= '0';
    wait until rising_edge(clk);

    -- Attempt write to COUNT (should be no-op)
    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '1';
    ADR_I <= x"00C"; DAT_I <= x"FFFFFFFF"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    CYC_I <= '0'; STB_I <= '0'; WE_I <= '0';
    wait until rising_edge(clk);

    -- Read COUNT again: must equal saved value (write was ignored)
    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '0'; ADR_I <= x"00C"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    rdata_v := DAT_O;
    CYC_I <= '0'; STB_I <= '0';
    wait until rising_edge(clk);
    check_eq(rdata_v, saved_count, "COUNT read-only");

    test_done("test_rw");

    -- ---- Test: timer repeat mode interrupt ----
    test_start("test_timer_ops");

    -- Write LOAD=8
    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '1';
    ADR_I <= x"008"; DAT_I <= x"00000008"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    CYC_I <= '0'; STB_I <= '0'; WE_I <= '0';
    wait until rising_edge(clk);

    -- Write CTRL: EN=1, INTR_EN=1
    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '1';
    ADR_I <= x"000"; DAT_I <= x"00000005"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    CYC_I <= '0'; STB_I <= '0'; WE_I <= '0';
    wait until rising_edge(clk);

    -- Wait for irq
    timeout := 0;
    while irq = '0' and timeout < 200 loop
      wait until rising_edge(clk);
      timeout := timeout + 1;
    end loop;
    if timeout >= 200 then
      report "FAIL tb_timer_wb: timeout waiting for irq" severity failure;
    end if;

    -- Read STATUS: check INTR and ACTIVE
    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '0'; ADR_I <= x"004"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    rdata_v := DAT_O;
    CYC_I <= '0'; STB_I <= '0';
    wait until rising_edge(clk);
    check_eq(rdata_v and x"00000001", x"00000001", "STATUS.INTR set");
    check_eq(rdata_v and x"00000002", x"00000002", "STATUS.ACTIVE set");

    -- Disable timer FIRST so repeat mode cannot re-assert INTR before W1C clear.
    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '1';
    ADR_I <= x"000"; DAT_I <= x"00000000"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    CYC_I <= '0'; STB_I <= '0'; WE_I <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- W1C clear STATUS.INTR
    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '1';
    ADR_I <= x"004"; DAT_I <= x"00000001"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    CYC_I <= '0'; STB_I <= '0'; WE_I <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- Read STATUS: INTR should be 0
    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '0'; ADR_I <= x"004"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    rdata_v := DAT_O;
    CYC_I <= '0'; STB_I <= '0';
    wait until rising_edge(clk);
    check_eq(rdata_v and x"00000001", x"00000000", "STATUS.INTR cleared");

    -- Disable timer
    wait until rising_edge(clk);
    CYC_I <= '1'; STB_I <= '1'; WE_I <= '1';
    ADR_I <= x"000"; DAT_I <= x"00000000"; SEL_I <= x"F";
    while ACK_O = '0' loop wait until rising_edge(clk); end loop;
    CYC_I <= '0'; STB_I <= '0'; WE_I <= '0';
    wait until rising_edge(clk);

    test_done("test_timer_ops");

    sim_done <= true;
    report "PASS tb_timer_wb: all tests passed" severity note;
    stop;
  end process p_stim;

end architecture sim;
