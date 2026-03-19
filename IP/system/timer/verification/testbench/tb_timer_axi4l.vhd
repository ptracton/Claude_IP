-- tb_timer_axi4l.vhd — AXI4-Lite testbench for timer IP (VHDL-2008).
--
-- Instantiates timer_axi4l and drives the AXI4-Lite channels to run a basic
-- directed test sequence covering:
--   1. Reset state verification
--   2. Register read/write (CTRL, LOAD)
--   3. COUNT read-only check
--   4. Timer repeat mode interrupt
--
-- Bus transactions are inline in the stimulus process (no signal-mode
-- procedure parameters) to avoid VHDL signal-actual constraints.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.timer_test_pkg.all;

entity tb_timer_axi4l is
end entity tb_timer_axi4l;

architecture sim of tb_timer_axi4l is

  component timer_axi4l is
    generic (
      DATA_W  : positive := 32;
      ADDR_W  : positive := 4;
      RST_POL : natural  := 0
    );
    port (
      ACLK    : in  std_ulogic;
      ARESETn : in  std_ulogic;
      AWVALID : in  std_ulogic;
      AWREADY : out std_ulogic;
      AWADDR  : in  std_ulogic_vector(11 downto 0);
      WVALID  : in  std_ulogic;
      WREADY  : out std_ulogic;
      WDATA   : in  std_ulogic_vector(31 downto 0);
      WSTRB   : in  std_ulogic_vector(3 downto 0);
      BVALID  : out std_ulogic;
      BREADY  : in  std_ulogic;
      BRESP   : out std_ulogic_vector(1 downto 0);
      ARVALID : in  std_ulogic;
      ARREADY : out std_ulogic;
      ARADDR  : in  std_ulogic_vector(11 downto 0);
      RVALID  : out std_ulogic;
      RREADY  : in  std_ulogic;
      RDATA   : out std_ulogic_vector(31 downto 0);
      RRESP   : out std_ulogic_vector(1 downto 0);
      irq         : out std_ulogic;
      trigger_out : out std_ulogic
    );
  end component timer_axi4l;

  constant CLK_PERIOD : time := 10 ns;

  signal clk     : std_ulogic := '0';
  signal rst_n   : std_ulogic := '0';

  signal AWVALID : std_ulogic := '0';
  signal AWREADY : std_ulogic;
  signal AWADDR  : std_ulogic_vector(11 downto 0) := (others => '0');
  signal WVALID  : std_ulogic := '0';
  signal WREADY  : std_ulogic;
  signal WDATA   : std_ulogic_vector(31 downto 0) := (others => '0');
  signal WSTRB   : std_ulogic_vector(3 downto 0) := (others => '1');
  signal BVALID  : std_ulogic;
  signal BREADY  : std_ulogic := '1';
  signal BRESP   : std_ulogic_vector(1 downto 0);
  signal ARVALID : std_ulogic := '0';
  signal ARREADY : std_ulogic;
  signal ARADDR  : std_ulogic_vector(11 downto 0) := (others => '0');
  signal RVALID  : std_ulogic;
  signal RREADY  : std_ulogic := '1';
  signal RDATA   : std_ulogic_vector(31 downto 0);
  signal RRESP   : std_ulogic_vector(1 downto 0);
  signal irq         : std_ulogic;
  signal trigger_out : std_ulogic;

  signal sim_done : boolean := false;

begin

  clk <= not clk after CLK_PERIOD / 2;

  u_dut : timer_axi4l
    generic map (DATA_W => 32, ADDR_W => 4, RST_POL => 0)
    port map (
      ACLK        => clk,
      ARESETn     => rst_n,
      AWVALID     => AWVALID,
      AWREADY     => AWREADY,
      AWADDR      => AWADDR,
      WVALID      => WVALID,
      WREADY      => WREADY,
      WDATA       => WDATA,
      WSTRB       => WSTRB,
      BVALID      => BVALID,
      BREADY      => BREADY,
      BRESP       => BRESP,
      ARVALID     => ARVALID,
      ARREADY     => ARREADY,
      ARADDR      => ARADDR,
      RVALID      => RVALID,
      RREADY      => RREADY,
      RDATA       => RDATA,
      RRESP       => RRESP,
      irq         => irq,
      trigger_out => trigger_out
    );

  p_timeout : process is
  begin
    wait for 1 ms;
    if not sim_done then
      report "FAIL tb_timer_axi4l: simulation timeout" severity failure;
    end if;
    wait;
  end process p_timeout;

  -- -------------------------------------------------------------------------
  -- Stimulus: all bus transactions inlined to avoid signal-mode issues
  -- -------------------------------------------------------------------------
  p_stim : process is
    variable rdata_v : std_ulogic_vector(31 downto 0);
    variable timeout : integer;
  begin
    -- Initialise
    rst_n   <= '0';
    AWVALID <= '0';
    AWADDR  <= (others => '0');
    WVALID  <= '0';
    WDATA   <= (others => '0');
    WSTRB   <= (others => '1');
    BREADY  <= '1';
    ARVALID <= '0';
    ARADDR  <= (others => '0');
    RREADY  <= '1';
    for i in 0 to 7 loop
      wait until rising_edge(clk);
    end loop;
    rst_n <= '1';
    wait until rising_edge(clk);

    -- ------------------------------------------------------------------
    -- Macro: AXI4-Lite write to addr with data and strobe
    -- AWREADY=WREADY=1 always so AW and W accepted immediately.
    -- ------------------------------------------------------------------

    -- ---- Test: reset values ----
    test_start("test_reset");

    -- Read CTRL (0x000)
    wait until rising_edge(clk);
    ARVALID <= '1'; ARADDR <= x"000"; RREADY <= '1';
    wait until rising_edge(clk); ARVALID <= '0';
    while RVALID = '0' loop wait until rising_edge(clk); end loop;
    rdata_v := RDATA;
    wait until rising_edge(clk); RREADY <= '0';
    check_eq(rdata_v, x"00000000", "CTRL reset");

    -- Read STATUS (0x004)
    wait until rising_edge(clk);
    ARVALID <= '1'; ARADDR <= x"004"; RREADY <= '1';
    wait until rising_edge(clk); ARVALID <= '0';
    while RVALID = '0' loop wait until rising_edge(clk); end loop;
    rdata_v := RDATA;
    wait until rising_edge(clk); RREADY <= '0';
    check_eq(rdata_v, x"00000000", "STATUS reset");

    -- Read LOAD (0x008)
    wait until rising_edge(clk);
    ARVALID <= '1'; ARADDR <= x"008"; RREADY <= '1';
    wait until rising_edge(clk); ARVALID <= '0';
    while RVALID = '0' loop wait until rising_edge(clk); end loop;
    rdata_v := RDATA;
    wait until rising_edge(clk); RREADY <= '0';
    check_eq(rdata_v, x"00000000", "LOAD reset");

    -- Read COUNT (0x00C)
    wait until rising_edge(clk);
    ARVALID <= '1'; ARADDR <= x"00C"; RREADY <= '1';
    wait until rising_edge(clk); ARVALID <= '0';
    while RVALID = '0' loop wait until rising_edge(clk); end loop;
    rdata_v := RDATA;
    wait until rising_edge(clk); RREADY <= '0';
    check_eq(rdata_v, x"00000000", "COUNT reset");

    test_done("test_reset");

    -- ---- Test: write/read CTRL ----
    test_start("test_rw");

    wait until rising_edge(clk);
    AWVALID <= '1'; AWADDR <= x"000";
    WVALID  <= '1'; WDATA  <= x"00000005"; WSTRB <= x"F"; BREADY <= '1';
    wait until rising_edge(clk); AWVALID <= '0'; WVALID <= '0';
    while BVALID = '0' loop wait until rising_edge(clk); end loop;
    wait until rising_edge(clk); BREADY <= '0';

    wait until rising_edge(clk);
    ARVALID <= '1'; ARADDR <= x"000"; RREADY <= '1';
    wait until rising_edge(clk); ARVALID <= '0';
    while RVALID = '0' loop wait until rising_edge(clk); end loop;
    rdata_v := RDATA;
    wait until rising_edge(clk); RREADY <= '0';
    check_eq(rdata_v, x"00000005", "CTRL write/read");

    -- Clear CTRL
    wait until rising_edge(clk);
    AWVALID <= '1'; AWADDR <= x"000";
    WVALID  <= '1'; WDATA  <= x"00000000"; WSTRB <= x"F"; BREADY <= '1';
    wait until rising_edge(clk); AWVALID <= '0'; WVALID <= '0';
    while BVALID = '0' loop wait until rising_edge(clk); end loop;
    wait until rising_edge(clk); BREADY <= '0';

    -- ---- Test: write/read LOAD ----
    wait until rising_edge(clk);
    AWVALID <= '1'; AWADDR <= x"008";
    WVALID  <= '1'; WDATA  <= x"DEADBEEF"; WSTRB <= x"F"; BREADY <= '1';
    wait until rising_edge(clk); AWVALID <= '0'; WVALID <= '0';
    while BVALID = '0' loop wait until rising_edge(clk); end loop;
    wait until rising_edge(clk); BREADY <= '0';

    wait until rising_edge(clk);
    ARVALID <= '1'; ARADDR <= x"008"; RREADY <= '1';
    wait until rising_edge(clk); ARVALID <= '0';
    while RVALID = '0' loop wait until rising_edge(clk); end loop;
    rdata_v := RDATA;
    wait until rising_edge(clk); RREADY <= '0';
    check_eq(rdata_v, x"DEADBEEF", "LOAD write/read");

    -- Restore LOAD
    wait until rising_edge(clk);
    AWVALID <= '1'; AWADDR <= x"008";
    WVALID  <= '1'; WDATA  <= x"00000000"; WSTRB <= x"F"; BREADY <= '1';
    wait until rising_edge(clk); AWVALID <= '0'; WVALID <= '0';
    while BVALID = '0' loop wait until rising_edge(clk); end loop;
    wait until rising_edge(clk); BREADY <= '0';

    -- ---- Test: COUNT read-only ----
    wait until rising_edge(clk);
    AWVALID <= '1'; AWADDR <= x"00C";
    WVALID  <= '1'; WDATA  <= x"FFFFFFFF"; WSTRB <= x"F"; BREADY <= '1';
    wait until rising_edge(clk); AWVALID <= '0'; WVALID <= '0';
    while BVALID = '0' loop wait until rising_edge(clk); end loop;
    wait until rising_edge(clk); BREADY <= '0';

    wait until rising_edge(clk);
    ARVALID <= '1'; ARADDR <= x"00C"; RREADY <= '1';
    wait until rising_edge(clk); ARVALID <= '0';
    while RVALID = '0' loop wait until rising_edge(clk); end loop;
    rdata_v := RDATA;
    wait until rising_edge(clk); RREADY <= '0';
    check_eq(rdata_v, x"00000000", "COUNT read-only");

    test_done("test_rw");

    -- ---- Test: timer repeat mode interrupt ----
    test_start("test_timer_ops");

    -- Write LOAD=8
    wait until rising_edge(clk);
    AWVALID <= '1'; AWADDR <= x"008";
    WVALID  <= '1'; WDATA  <= x"00000008"; WSTRB <= x"F"; BREADY <= '1';
    wait until rising_edge(clk); AWVALID <= '0'; WVALID <= '0';
    while BVALID = '0' loop wait until rising_edge(clk); end loop;
    wait until rising_edge(clk); BREADY <= '0';

    -- Write CTRL: EN=1, INTR_EN=1
    wait until rising_edge(clk);
    AWVALID <= '1'; AWADDR <= x"000";
    WVALID  <= '1'; WDATA  <= x"00000005"; WSTRB <= x"F"; BREADY <= '1';
    wait until rising_edge(clk); AWVALID <= '0'; WVALID <= '0';
    while BVALID = '0' loop wait until rising_edge(clk); end loop;
    wait until rising_edge(clk); BREADY <= '0';

    -- Wait for irq
    timeout := 0;
    while irq = '0' and timeout < 200 loop
      wait until rising_edge(clk);
      timeout := timeout + 1;
    end loop;
    if timeout >= 200 then
      report "FAIL tb_timer_axi4l: timeout waiting for irq" severity failure;
    end if;

    -- Check STATUS.INTR and ACTIVE
    wait until rising_edge(clk);
    ARVALID <= '1'; ARADDR <= x"004"; RREADY <= '1';
    wait until rising_edge(clk); ARVALID <= '0';
    while RVALID = '0' loop wait until rising_edge(clk); end loop;
    rdata_v := RDATA;
    wait until rising_edge(clk); RREADY <= '0';
    check_eq(rdata_v and x"00000001", x"00000001", "STATUS.INTR set");
    check_eq(rdata_v and x"00000002", x"00000002", "STATUS.ACTIVE set");

    -- Disable timer FIRST so it cannot re-assert INTR before we clear it.
    wait until rising_edge(clk);
    AWVALID <= '1'; AWADDR <= x"000";
    WVALID  <= '1'; WDATA  <= x"00000000"; WSTRB <= x"F"; BREADY <= '1';
    wait until rising_edge(clk); AWVALID <= '0'; WVALID <= '0';
    while BVALID = '0' loop wait until rising_edge(clk); end loop;
    wait until rising_edge(clk); BREADY <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- W1C clear STATUS.INTR
    wait until rising_edge(clk);
    AWVALID <= '1'; AWADDR <= x"004";
    WVALID  <= '1'; WDATA  <= x"00000001"; WSTRB <= x"F"; BREADY <= '1';
    wait until rising_edge(clk); AWVALID <= '0'; WVALID <= '0';
    while BVALID = '0' loop wait until rising_edge(clk); end loop;
    wait until rising_edge(clk); BREADY <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- Verify STATUS.INTR cleared
    wait until rising_edge(clk);
    ARVALID <= '1'; ARADDR <= x"004"; RREADY <= '1';
    wait until rising_edge(clk); ARVALID <= '0';
    while RVALID = '0' loop wait until rising_edge(clk); end loop;
    rdata_v := RDATA;
    wait until rising_edge(clk); RREADY <= '0';
    check_eq(rdata_v and x"00000001", x"00000000", "STATUS.INTR cleared");

    -- Disable timer
    wait until rising_edge(clk);
    AWVALID <= '1'; AWADDR <= x"000";
    WVALID  <= '1'; WDATA  <= x"00000000"; WSTRB <= x"F"; BREADY <= '1';
    wait until rising_edge(clk); AWVALID <= '0'; WVALID <= '0';
    while BVALID = '0' loop wait until rising_edge(clk); end loop;
    wait until rising_edge(clk); BREADY <= '0';

    test_done("test_timer_ops");

    sim_done <= true;
    report "PASS tb_timer_axi4l: all tests passed" severity note;
    wait;
  end process p_stim;

end architecture sim;
