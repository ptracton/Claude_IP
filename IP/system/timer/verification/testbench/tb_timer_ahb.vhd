-- tb_timer_ahb.vhd — AHB-Lite testbench for timer IP (VHDL-2008).
--
-- Instantiates timer_ahb and drives the AHB-Lite bus to run a basic
-- directed test sequence covering:
--   1. Reset state verification
--   2. Register read/write (CTRL, LOAD)
--   3. COUNT read-only check
--   4. Timer repeat mode interrupt
--
-- Bus transactions are inlined in the stimulus process to avoid VHDL
-- signal-mode procedure-parameter constraints.
--
-- AHB-Lite two-phase transaction:
--   Address phase: HSEL=1, HTRANS=NONSEQ, HADDR, HWRITE set at posedge
--   Data phase   : at next posedge HTRANS→IDLE, HWDATA set (for writes)
--   HRDATA       : valid one posedge after the data phase for reads

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.timer_test_pkg.all;

entity tb_timer_ahb is
end entity tb_timer_ahb;

architecture sim of tb_timer_ahb is

  component timer_ahb is
    generic (
      DATA_W  : positive := 32;
      ADDR_W  : positive := 4;
      RST_POL : natural  := 0
    );
    port (
      HCLK        : in  std_ulogic;
      HRESETn     : in  std_ulogic;
      HSEL        : in  std_ulogic;
      HADDR       : in  std_ulogic_vector(11 downto 0);
      HTRANS      : in  std_ulogic_vector(1 downto 0);
      HWRITE      : in  std_ulogic;
      HWDATA      : in  std_ulogic_vector(31 downto 0);
      HWSTRB      : in  std_ulogic_vector(3 downto 0);
      HRDATA      : out std_ulogic_vector(31 downto 0);
      HREADY      : out std_ulogic;
      HRESP       : out std_ulogic;
      irq         : out std_ulogic;
      trigger_out : out std_ulogic
    );
  end component timer_ahb;

  constant CLK_PERIOD : time := 10 ns;

  -- AHB HTRANS encoding
  constant HTRANS_IDLE  : std_ulogic_vector(1 downto 0) := "00";
  constant HTRANS_NONSEQ : std_ulogic_vector(1 downto 0) := "10";

  signal clk     : std_ulogic := '0';
  signal rst_n   : std_ulogic := '0';

  signal HSEL    : std_ulogic := '0';
  signal HADDR   : std_ulogic_vector(11 downto 0) := (others => '0');
  signal HTRANS  : std_ulogic_vector(1 downto 0) := "00";
  signal HWRITE  : std_ulogic := '0';
  signal HWDATA  : std_ulogic_vector(31 downto 0) := (others => '0');
  signal HWSTRB  : std_ulogic_vector(3 downto 0) := (others => '1');
  signal HRDATA  : std_ulogic_vector(31 downto 0);
  signal HREADY  : std_ulogic;
  signal HRESP   : std_ulogic;
  signal irq         : std_ulogic;
  signal trigger_out : std_ulogic;

  signal sim_done : boolean := false;

begin

  clk <= not clk after CLK_PERIOD / 2;

  u_dut : timer_ahb
    generic map (DATA_W => 32, ADDR_W => 4, RST_POL => 0)
    port map (
      HCLK        => clk,
      HRESETn     => rst_n,
      HSEL        => HSEL,
      HADDR       => HADDR,
      HTRANS      => HTRANS,
      HWRITE      => HWRITE,
      HWDATA      => HWDATA,
      HWSTRB      => HWSTRB,
      HRDATA      => HRDATA,
      HREADY      => HREADY,
      HRESP       => HRESP,
      irq         => irq,
      trigger_out => trigger_out
    );

  p_timeout : process is
  begin
    wait for 1 ms;
    if not sim_done then
      report "FAIL tb_timer_ahb: simulation timeout" severity failure;
    end if;
    wait;
  end process p_timeout;

  -- -------------------------------------------------------------------------
  -- Stimulus — bus transactions inlined
  -- AHB-Lite write:
  --   Cycle 1 (addr phase): HSEL=1, HTRANS=NONSEQ, HADDR, HWRITE=1
  --   Cycle 2 (data phase): HTRANS=IDLE, HSEL=0, HWDATA, HWSTRB
  --   Cycle 3: idle / deassert
  -- AHB-Lite read:
  --   Cycle 1 (addr phase): HSEL=1, HTRANS=NONSEQ, HADDR, HWRITE=0
  --   Cycle 2 (data phase): HTRANS=IDLE, HSEL=0
  --   Cycle 3: capture HRDATA
  -- -------------------------------------------------------------------------
  p_stim : process is
    variable rdata_v : std_ulogic_vector(31 downto 0);
    variable timeout : integer;
  begin
    rst_n  <= '0';
    HSEL   <= '0';
    HADDR  <= (others => '0');
    HTRANS <= HTRANS_IDLE;
    HWRITE <= '0';
    HWDATA <= (others => '0');
    HWSTRB <= (others => '1');
    for i in 0 to 7 loop
      wait until rising_edge(clk);
    end loop;
    rst_n <= '1';
    wait until rising_edge(clk);

    -- ---- Test: reset values ----
    test_start("test_reset");

    -- Read CTRL
    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"000"; HWRITE <= '0';
    wait until rising_edge(clk); HTRANS <= HTRANS_IDLE; HSEL <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk); rdata_v := HRDATA;
    check_eq(rdata_v, x"00000000", "CTRL reset");

    -- Read STATUS
    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"004"; HWRITE <= '0';
    wait until rising_edge(clk); HTRANS <= HTRANS_IDLE; HSEL <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk); rdata_v := HRDATA;
    check_eq(rdata_v, x"00000000", "STATUS reset");

    -- Read LOAD
    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"008"; HWRITE <= '0';
    wait until rising_edge(clk); HTRANS <= HTRANS_IDLE; HSEL <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk); rdata_v := HRDATA;
    check_eq(rdata_v, x"00000000", "LOAD reset");

    -- Read COUNT
    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"00C"; HWRITE <= '0';
    wait until rising_edge(clk); HTRANS <= HTRANS_IDLE; HSEL <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk); rdata_v := HRDATA;
    check_eq(rdata_v, x"00000000", "COUNT reset");

    test_done("test_reset");

    -- ---- Test: write/read CTRL ----
    test_start("test_rw");

    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"000"; HWRITE <= '1';
    wait until rising_edge(clk);
    HTRANS <= HTRANS_IDLE; HSEL <= '0'; HWDATA <= x"00000005"; HWSTRB <= x"F";
    wait until rising_edge(clk); HWRITE <= '0';

    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"000"; HWRITE <= '0';
    wait until rising_edge(clk); HTRANS <= HTRANS_IDLE; HSEL <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk); rdata_v := HRDATA;
    check_eq(rdata_v, x"00000005", "CTRL write/read");

    -- Clear CTRL
    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"000"; HWRITE <= '1';
    wait until rising_edge(clk);
    HTRANS <= HTRANS_IDLE; HSEL <= '0'; HWDATA <= x"00000000"; HWSTRB <= x"F";
    wait until rising_edge(clk); HWRITE <= '0';

    -- ---- Test: write/read LOAD ----
    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"008"; HWRITE <= '1';
    wait until rising_edge(clk);
    HTRANS <= HTRANS_IDLE; HSEL <= '0'; HWDATA <= x"DEADBEEF"; HWSTRB <= x"F";
    wait until rising_edge(clk); HWRITE <= '0';

    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"008"; HWRITE <= '0';
    wait until rising_edge(clk); HTRANS <= HTRANS_IDLE; HSEL <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk); rdata_v := HRDATA;
    check_eq(rdata_v, x"DEADBEEF", "LOAD write/read");

    -- Restore LOAD
    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"008"; HWRITE <= '1';
    wait until rising_edge(clk);
    HTRANS <= HTRANS_IDLE; HSEL <= '0'; HWDATA <= x"00000000"; HWSTRB <= x"F";
    wait until rising_edge(clk); HWRITE <= '0';

    -- ---- Test: COUNT read-only ----
    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"00C"; HWRITE <= '1';
    wait until rising_edge(clk);
    HTRANS <= HTRANS_IDLE; HSEL <= '0'; HWDATA <= x"FFFFFFFF"; HWSTRB <= x"F";
    wait until rising_edge(clk); HWRITE <= '0';

    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"00C"; HWRITE <= '0';
    wait until rising_edge(clk); HTRANS <= HTRANS_IDLE; HSEL <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk); rdata_v := HRDATA;
    check_eq(rdata_v, x"00000000", "COUNT read-only");

    test_done("test_rw");

    -- ---- Test: timer repeat mode interrupt ----
    test_start("test_timer_ops");

    -- Write LOAD=8
    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"008"; HWRITE <= '1';
    wait until rising_edge(clk);
    HTRANS <= HTRANS_IDLE; HSEL <= '0'; HWDATA <= x"00000008"; HWSTRB <= x"F";
    wait until rising_edge(clk); HWRITE <= '0';

    -- Write CTRL: EN=1, INTR_EN=1
    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"000"; HWRITE <= '1';
    wait until rising_edge(clk);
    HTRANS <= HTRANS_IDLE; HSEL <= '0'; HWDATA <= x"00000005"; HWSTRB <= x"F";
    wait until rising_edge(clk); HWRITE <= '0';

    -- Wait for irq
    timeout := 0;
    while irq = '0' and timeout < 200 loop
      wait until rising_edge(clk);
      timeout := timeout + 1;
    end loop;
    if timeout >= 200 then
      report "FAIL tb_timer_ahb: timeout waiting for irq" severity failure;
    end if;

    -- Read STATUS: check INTR and ACTIVE
    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"004"; HWRITE <= '0';
    wait until rising_edge(clk); HTRANS <= HTRANS_IDLE; HSEL <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk); rdata_v := HRDATA;
    check_eq(rdata_v and x"00000001", x"00000001", "STATUS.INTR set");
    check_eq(rdata_v and x"00000002", x"00000002", "STATUS.ACTIVE set");

    -- Disable timer FIRST so repeat mode cannot re-assert INTR before W1C clear.
    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"000"; HWRITE <= '1';
    wait until rising_edge(clk);
    HTRANS <= HTRANS_IDLE; HSEL <= '0'; HWDATA <= x"00000000"; HWSTRB <= x"F";
    wait until rising_edge(clk); HWRITE <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- W1C clear STATUS.INTR
    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"004"; HWRITE <= '1';
    wait until rising_edge(clk);
    HTRANS <= HTRANS_IDLE; HSEL <= '0'; HWDATA <= x"00000001"; HWSTRB <= x"F";
    wait until rising_edge(clk); HWRITE <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- Read STATUS: INTR should be 0
    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"004"; HWRITE <= '0';
    wait until rising_edge(clk); HTRANS <= HTRANS_IDLE; HSEL <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk); rdata_v := HRDATA;
    check_eq(rdata_v and x"00000001", x"00000000", "STATUS.INTR cleared");

    -- Disable timer
    wait until rising_edge(clk);
    HSEL <= '1'; HTRANS <= HTRANS_NONSEQ; HADDR <= x"000"; HWRITE <= '1';
    wait until rising_edge(clk);
    HTRANS <= HTRANS_IDLE; HSEL <= '0'; HWDATA <= x"00000000"; HWSTRB <= x"F";
    wait until rising_edge(clk); HWRITE <= '0';

    test_done("test_timer_ops");

    sim_done <= true;
    report "PASS tb_timer_ahb: all tests passed" severity note;
    wait;
  end process p_stim;

end architecture sim;
