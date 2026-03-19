-- tb_timer_apb.vhd — APB4 testbench for timer IP (VHDL-2008).
--
-- Instantiates timer_apb and drives the APB4 bus to run a basic directed
-- test sequence covering:
--   1. Reset state verification (all registers = 0)
--   2. Register read/write (CTRL, LOAD)
--   3. STATUS.INTR W1C behavior
--   4. Timer functional test (repeat mode, interrupt)
--
-- Bus transactions are inlined in the stimulus process to avoid VHDL
-- signal-mode procedure-parameter constraints.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ip_test_pkg.all;
use std.env.all;

entity tb_timer_apb is
end entity tb_timer_apb;

architecture sim of tb_timer_apb is

  -- -------------------------------------------------------------------------
  -- Component declaration
  -- -------------------------------------------------------------------------
  component timer_apb is
    generic (
      DATA_W  : positive := 32;
      ADDR_W  : positive := 4;
      RST_POL : natural  := 0
    );
    port (
      PCLK        : in  std_ulogic;
      PRESETn     : in  std_ulogic;
      PSEL        : in  std_ulogic;
      PENABLE     : in  std_ulogic;
      PADDR       : in  std_ulogic_vector(11 downto 0);
      PWRITE      : in  std_ulogic;
      PWDATA      : in  std_ulogic_vector(31 downto 0);
      PSTRB       : in  std_ulogic_vector(3 downto 0);
      PRDATA      : out std_ulogic_vector(31 downto 0);
      PREADY      : out std_ulogic;
      PSLVERR     : out std_ulogic;
      irq         : out std_ulogic;
      trigger_out : out std_ulogic
    );
  end component timer_apb;

  constant CLK_PERIOD : time := 10 ns;

  signal clk         : std_ulogic := '0';
  signal rst_n       : std_ulogic := '0';

  signal PSEL        : std_ulogic := '0';
  signal PENABLE     : std_ulogic := '0';
  signal PADDR       : std_ulogic_vector(11 downto 0) := (others => '0');
  signal PWRITE      : std_ulogic := '0';
  signal PWDATA      : std_ulogic_vector(31 downto 0) := (others => '0');
  signal PSTRB       : std_ulogic_vector(3 downto 0) := (others => '1');
  signal PRDATA      : std_ulogic_vector(31 downto 0);
  signal PREADY      : std_ulogic;
  signal PSLVERR     : std_ulogic;
  signal irq         : std_ulogic;
  signal trigger_out : std_ulogic;

  signal sim_done : boolean := false;

begin

  clk <= not clk after CLK_PERIOD / 2;

  u_dut : timer_apb
    generic map (DATA_W => 32, ADDR_W => 4, RST_POL => 0)
    port map (
      PCLK        => clk,
      PRESETn     => rst_n,
      PSEL        => PSEL,
      PENABLE     => PENABLE,
      PADDR       => PADDR,
      PWRITE      => PWRITE,
      PWDATA      => PWDATA,
      PSTRB       => PSTRB,
      PRDATA      => PRDATA,
      PREADY      => PREADY,
      PSLVERR     => PSLVERR,
      irq         => irq,
      trigger_out => trigger_out
    );

  p_timeout : process is
  begin
    wait for 1 ms;
    if not sim_done then
      report "FAIL tb_timer_apb: simulation timeout" severity failure;
    end if;
    wait;
  end process p_timeout;

  -- -------------------------------------------------------------------------
  -- Stimulus — bus transactions inlined
  -- APB write: SETUP (PSEL=1,PENABLE=0) then ACCESS (PSEL=1,PENABLE=1)
  -- APB read:  SETUP fires rd_en; ACCESS provides PRDATA
  -- -------------------------------------------------------------------------
  p_stim : process is
    variable rdata_v     : std_ulogic_vector(31 downto 0);
    variable saved_count : std_ulogic_vector(31 downto 0);
    variable timeout     : integer;
  begin
    rst_n   <= '0';
    PSEL    <= '0';
    PENABLE <= '0';
    PADDR   <= (others => '0');
    PWRITE  <= '0';
    PWDATA  <= (others => '0');
    PSTRB   <= (others => '1');
    for i in 0 to 7 loop
      wait until rising_edge(clk);
    end loop;
    rst_n <= '1';
    wait until rising_edge(clk);

    -- ------------------------------------------------------------------
    -- Helper: APB write inline macro
    --   SETUP: PSEL=1, PENABLE=0
    --   ACCESS: PSEL=1, PENABLE=1
    --   Deassert after ACCESS
    -- ------------------------------------------------------------------

    -- ---- Test: reset values ----
    test_start("test_reset");

    -- Read CTRL
    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"000"; PWRITE <= '0';
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); rdata_v := PRDATA;
    PSEL <= '0'; PENABLE <= '0';
    check_eq(rdata_v, x"00000000", "CTRL reset");

    -- Read STATUS
    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"004"; PWRITE <= '0';
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); rdata_v := PRDATA;
    PSEL <= '0'; PENABLE <= '0';
    check_eq(rdata_v, x"00000000", "STATUS reset");

    -- Read LOAD
    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"008"; PWRITE <= '0';
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); rdata_v := PRDATA;
    PSEL <= '0'; PENABLE <= '0';
    check_eq(rdata_v, x"00000000", "LOAD reset");

    -- Read COUNT
    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"00C"; PWRITE <= '0';
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); rdata_v := PRDATA;
    PSEL <= '0'; PENABLE <= '0';
    check_eq(rdata_v, x"00000000", "COUNT reset");

    test_done("test_reset");

    -- ---- Test: write/read CTRL ----
    test_start("test_rw");

    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"000"; PWRITE <= '1';
    PWDATA <= x"00000005"; PSTRB <= x"F";
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); PSEL <= '0'; PENABLE <= '0'; PWRITE <= '0';

    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"000"; PWRITE <= '0';
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); rdata_v := PRDATA;
    PSEL <= '0'; PENABLE <= '0';
    check_eq(rdata_v, x"00000005", "CTRL write/read");

    -- Clear CTRL
    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"000"; PWRITE <= '1';
    PWDATA <= x"00000000"; PSTRB <= x"F";
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); PSEL <= '0'; PENABLE <= '0'; PWRITE <= '0';

    -- ---- Test: write/read LOAD ----
    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"008"; PWRITE <= '1';
    PWDATA <= x"DEADBEEF"; PSTRB <= x"F";
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); PSEL <= '0'; PENABLE <= '0'; PWRITE <= '0';

    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"008"; PWRITE <= '0';
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); rdata_v := PRDATA;
    PSEL <= '0'; PENABLE <= '0';
    check_eq(rdata_v, x"DEADBEEF", "LOAD write/read");

    -- Restore LOAD
    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"008"; PWRITE <= '1';
    PWDATA <= x"00000000"; PSTRB <= x"F";
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); PSEL <= '0'; PENABLE <= '0'; PWRITE <= '0';

    -- ---- Test: COUNT read-only ----
    -- Read COUNT before write attempt (save baseline)
    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"00C"; PWRITE <= '0';
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); saved_count := PRDATA;
    PSEL <= '0'; PENABLE <= '0';

    -- Attempt write to COUNT (should be no-op)
    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"00C"; PWRITE <= '1';
    PWDATA <= x"FFFFFFFF"; PSTRB <= x"F";
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); PSEL <= '0'; PENABLE <= '0'; PWRITE <= '0';

    -- Read COUNT again: must equal saved value (write was ignored)
    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"00C"; PWRITE <= '0';
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); rdata_v := PRDATA;
    PSEL <= '0'; PENABLE <= '0';
    check_eq(rdata_v, saved_count, "COUNT read-only");

    test_done("test_rw");

    -- ---- Test: timer repeat mode interrupt ----
    test_start("test_timer_ops");
    -- Write LOAD=8
    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"008"; PWRITE <= '1';
    PWDATA <= x"00000008"; PSTRB <= x"F";
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); PSEL <= '0'; PENABLE <= '0'; PWRITE <= '0';

    -- Write CTRL: EN=1, INTR_EN=1 = 0x05
    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"000"; PWRITE <= '1';
    PWDATA <= x"00000005"; PSTRB <= x"F";
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); PSEL <= '0'; PENABLE <= '0'; PWRITE <= '0';

    -- Wait for irq
    timeout := 0;
    while irq = '0' and timeout < 200 loop
      wait until rising_edge(clk);
      timeout := timeout + 1;
    end loop;
    if timeout >= 200 then
      report "FAIL tb_timer_apb: timeout waiting for irq" severity failure;
    end if;

    -- Read STATUS: check INTR and ACTIVE
    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"004"; PWRITE <= '0';
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); rdata_v := PRDATA;
    PSEL <= '0'; PENABLE <= '0';
    check_eq(rdata_v and x"00000001", x"00000001", "STATUS.INTR set");
    check_eq(rdata_v and x"00000002", x"00000002", "STATUS.ACTIVE set");

    -- W1C clear STATUS.INTR
    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"004"; PWRITE <= '1';
    PWDATA <= x"00000001"; PSTRB <= x"F";
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); PSEL <= '0'; PENABLE <= '0'; PWRITE <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- Read STATUS: INTR should be 0
    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"004"; PWRITE <= '0';
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); rdata_v := PRDATA;
    PSEL <= '0'; PENABLE <= '0';
    check_eq(rdata_v and x"00000001", x"00000000", "STATUS.INTR cleared");

    -- Disable timer
    wait until rising_edge(clk);
    PSEL <= '1'; PENABLE <= '0'; PADDR <= x"000"; PWRITE <= '1';
    PWDATA <= x"00000000"; PSTRB <= x"F";
    wait until rising_edge(clk); PENABLE <= '1';
    wait until rising_edge(clk); PSEL <= '0'; PENABLE <= '0'; PWRITE <= '0';

    test_done("test_timer_ops");

    sim_done <= true;
    report "PASS tb_timer_apb: all tests passed" severity note;
    stop;
  end process p_stim;

end architecture sim;
