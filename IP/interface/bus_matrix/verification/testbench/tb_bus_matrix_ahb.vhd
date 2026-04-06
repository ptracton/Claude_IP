-- tb_bus_matrix_ahb.vhd -- AHB bus_matrix VHDL-2008 testbench.
--
-- Tests fabric write + readback via master 0 to slave 0.
-- Address map configured via DUT generics (no admin port).
-- S0: base=0x10000000, mask=0xF0000000
-- S1: base=0x20000000, mask=0xF0000000
--
-- Prints "PASS tb_bus_matrix_ahb" on success.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_bus_matrix_ahb is
end entity tb_bus_matrix_ahb;

architecture sim of tb_bus_matrix_ahb is

  constant CLK_PERIOD : time := 10 ns;
  constant AHB_IDLE   : std_ulogic_vector(1 downto 0) := "00";
  constant AHB_NONSEQ : std_ulogic_vector(1 downto 0) := "10";

  constant NM : positive := 2;
  constant NS : positive := 2;
  constant DW : positive := 32;
  constant AW : positive := 32;

  signal clk   : std_ulogic := '0';
  signal rst_n : std_ulogic := '0';

  -- Master 0 fabric port
  signal m0_HSEL   : std_ulogic                     := '0';
  signal m0_HADDR  : std_ulogic_vector(31 downto 0) := (others => '0');
  signal m0_HTRANS : std_ulogic_vector(1 downto 0)  := AHB_IDLE;
  signal m0_HWRITE : std_ulogic                     := '0';
  signal m0_HWDATA : std_ulogic_vector(31 downto 0) := (others => '0');
  signal m0_HWSTRB : std_ulogic_vector(3 downto 0)  := x"F";
  signal m0_HREADY : std_ulogic;
  signal m0_HRDATA : std_ulogic_vector(31 downto 0);
  signal m0_HRESP  : std_ulogic;

  -- Master 1 (tied off)
  signal m1_HSEL   : std_ulogic                     := '0';
  signal m1_HADDR  : std_ulogic_vector(31 downto 0) := (others => '0');
  signal m1_HTRANS : std_ulogic_vector(1 downto 0)  := AHB_IDLE;
  signal m1_HWRITE : std_ulogic                     := '0';
  signal m1_HWDATA : std_ulogic_vector(31 downto 0) := (others => '0');
  signal m1_HWSTRB : std_ulogic_vector(3 downto 0)  := x"F";

  -- Flat-packed DUT master ports
  signal M_HSEL   : std_ulogic_vector(NM-1 downto 0)      := (others => '0');
  signal M_HADDR  : std_ulogic_vector(NM*AW-1 downto 0)   := (others => '0');
  signal M_HTRANS : std_ulogic_vector(NM*2-1 downto 0)    := (others => '0');
  signal M_HWRITE : std_ulogic_vector(NM-1 downto 0)      := (others => '0');
  signal M_HWDATA : std_ulogic_vector(NM*DW-1 downto 0)   := (others => '0');
  signal M_HWSTRB : std_ulogic_vector(NM*4-1 downto 0)    := (others => '0');
  signal M_HREADY : std_ulogic_vector(NM-1 downto 0);
  signal M_HRDATA : std_ulogic_vector(NM*DW-1 downto 0);
  signal M_HRESP  : std_ulogic_vector(NM-1 downto 0);

  -- Flat-packed DUT slave ports
  signal S_HSEL   : std_ulogic_vector(NS-1 downto 0);
  signal S_HADDR  : std_ulogic_vector(NS*AW-1 downto 0);
  signal S_HTRANS : std_ulogic_vector(NS*2-1 downto 0);
  signal S_HWRITE : std_ulogic_vector(NS-1 downto 0);
  signal S_HWDATA : std_ulogic_vector(NS*DW-1 downto 0);
  signal S_HWSTRB : std_ulogic_vector(NS*4-1 downto 0);
  signal S_HREADY : std_ulogic_vector(NS-1 downto 0)      := (others => '1');
  signal S_HRDATA : std_ulogic_vector(NS*DW-1 downto 0)   := (others => '0');
  signal S_HRESP  : std_ulogic_vector(NS-1 downto 0)      := (others => '0');

  -- Slave 0 extracted signals
  signal s0_HSEL   : std_ulogic;
  signal s0_HADDR  : std_ulogic_vector(31 downto 0);
  signal s0_HTRANS : std_ulogic_vector(1 downto 0);
  signal s0_HWRITE : std_ulogic;
  signal s0_HWDATA : std_ulogic_vector(31 downto 0);
  signal s0_HWSTRB : std_ulogic_vector(3 downto 0);
  signal s0_HRDATA : std_ulogic_vector(31 downto 0);

  -- Slave 0 memory (64 words)
  type mem_t is array (0 to 63) of std_ulogic_vector(31 downto 0);
  signal s0_mem : mem_t := (others => (others => '0'));

  signal test_failed : boolean := false;

  -- Build S_BASE: S0=0x10000000, S1=0x20000000
  function make_s_base return std_ulogic_vector is
    variable v : std_ulogic_vector(32*32-1 downto 0) := (others => '0');
  begin
    v(31 downto 0)  := x"10000000";
    v(63 downto 32) := x"20000000";
    return v;
  end function;

  function make_s_mask return std_ulogic_vector is
    variable v : std_ulogic_vector(32*32-1 downto 0) := (others => '0');
  begin
    v(31 downto 0)  := x"F0000000";
    v(63 downto 32) := x"F0000000";
    return v;
  end function;

  -- DUT component
  component bus_matrix_ahb is
    generic (
      NUM_MASTERS : positive;
      NUM_SLAVES  : positive;
      DATA_W      : positive;
      ADDR_W      : positive;
      ARB_MODE    : natural;
      M_PRIORITY  : std_ulogic_vector(16*4-1 downto 0);
      S_BASE      : std_ulogic_vector(32*32-1 downto 0);
      S_MASK      : std_ulogic_vector(32*32-1 downto 0)
    );
    port (
      clk       : in  std_ulogic;
      rst_n     : in  std_ulogic;
      M_HSEL    : in  std_ulogic_vector(NUM_MASTERS-1 downto 0);
      M_HADDR   : in  std_ulogic_vector(NUM_MASTERS*ADDR_W-1 downto 0);
      M_HTRANS  : in  std_ulogic_vector(NUM_MASTERS*2-1 downto 0);
      M_HWRITE  : in  std_ulogic_vector(NUM_MASTERS-1 downto 0);
      M_HWDATA  : in  std_ulogic_vector(NUM_MASTERS*DATA_W-1 downto 0);
      M_HWSTRB  : in  std_ulogic_vector(NUM_MASTERS*4-1 downto 0);
      M_HREADY  : out std_ulogic_vector(NUM_MASTERS-1 downto 0);
      M_HRDATA  : out std_ulogic_vector(NUM_MASTERS*DATA_W-1 downto 0);
      M_HRESP   : out std_ulogic_vector(NUM_MASTERS-1 downto 0);
      S_HSEL    : out std_ulogic_vector(NUM_SLAVES-1 downto 0);
      S_HADDR   : out std_ulogic_vector(NUM_SLAVES*ADDR_W-1 downto 0);
      S_HTRANS  : out std_ulogic_vector(NUM_SLAVES*2-1 downto 0);
      S_HWRITE  : out std_ulogic_vector(NUM_SLAVES-1 downto 0);
      S_HWDATA  : out std_ulogic_vector(NUM_SLAVES*DATA_W-1 downto 0);
      S_HWSTRB  : out std_ulogic_vector(NUM_SLAVES*4-1 downto 0);
      S_HREADY  : in  std_ulogic_vector(NUM_SLAVES-1 downto 0);
      S_HRDATA  : in  std_ulogic_vector(NUM_SLAVES*DATA_W-1 downto 0);
      S_HRESP   : in  std_ulogic_vector(NUM_SLAVES-1 downto 0)
    );
  end component bus_matrix_ahb;

  procedure check_eq (
    actual   : in std_ulogic_vector(31 downto 0);
    expected : in std_ulogic_vector(31 downto 0);
    msg      : in string;
    signal failed_sig : out boolean
  ) is
    variable l : line;
  begin
    if actual /= expected then
      write(l, string'("FAIL: ") & msg &
            " expected=0x" & to_hstring(expected) &
            " got=0x" & to_hstring(actual));
      writeline(output, l);
      failed_sig <= true;
    else
      write(l, string'("  OK: ") & msg & " = 0x" & to_hstring(actual));
      writeline(output, l);
    end if;
  end procedure check_eq;

begin

  clk <= not clk after CLK_PERIOD / 2;

  -- Flat-pack masters
  M_HSEL   <= m1_HSEL & m0_HSEL;
  M_HADDR  <= m1_HADDR & m0_HADDR;
  M_HTRANS <= m1_HTRANS & m0_HTRANS;
  M_HWRITE <= m1_HWRITE & m0_HWRITE;
  M_HWDATA <= m1_HWDATA & m0_HWDATA;
  M_HWSTRB <= m1_HWSTRB & m0_HWSTRB;

  m0_HREADY <= M_HREADY(0);
  m0_HRDATA <= M_HRDATA(31 downto 0);
  m0_HRESP  <= M_HRESP(0);

  -- Extract slave 0
  s0_HSEL   <= S_HSEL(0);
  s0_HADDR  <= S_HADDR(31 downto 0);
  s0_HTRANS <= S_HTRANS(1 downto 0);
  s0_HWRITE <= S_HWRITE(0);
  s0_HWDATA <= S_HWDATA(31 downto 0);
  s0_HWSTRB <= S_HWSTRB(3 downto 0);

  -- Slave 0 drives back
  S_HREADY(0)           <= '1';
  S_HRDATA(31 downto 0) <= s0_HRDATA;
  S_HRESP(0)            <= '0';
  -- Slave 1 always ready, no data
  S_HREADY(1)            <= '1';
  S_HRDATA(63 downto 32) <= (others => '0');
  S_HRESP(1)             <= '0';

  -- DUT
  u_dut : bus_matrix_ahb
    generic map (
      NUM_MASTERS => NM,
      NUM_SLAVES  => NS,
      DATA_W      => DW,
      ADDR_W      => AW,
      ARB_MODE    => 0,
      M_PRIORITY  => (others => '0'),
      S_BASE      => make_s_base,
      S_MASK      => make_s_mask
    )
    port map (
      clk      => clk,
      rst_n    => rst_n,
      M_HSEL   => M_HSEL,
      M_HADDR  => M_HADDR,
      M_HTRANS => M_HTRANS,
      M_HWRITE => M_HWRITE,
      M_HWDATA => M_HWDATA,
      M_HWSTRB => M_HWSTRB,
      M_HREADY => M_HREADY,
      M_HRDATA => M_HRDATA,
      M_HRESP  => M_HRESP,
      S_HSEL   => S_HSEL,
      S_HADDR  => S_HADDR,
      S_HTRANS => S_HTRANS,
      S_HWRITE => S_HWRITE,
      S_HWDATA => S_HWDATA,
      S_HWSTRB => S_HWSTRB,
      S_HREADY => S_HREADY,
      S_HRDATA => S_HRDATA,
      S_HRESP  => S_HRESP
    );

  -- Slave 0 BFM: combinational read, registered write
  p_slave0_read : process (s0_HADDR, s0_mem) is
    variable addr_idx : integer;
  begin
    addr_idx := to_integer(unsigned(s0_HADDR(7 downto 2)));
    if addr_idx > 63 then addr_idx := 0; end if;
    s0_HRDATA <= s0_mem(addr_idx);
  end process p_slave0_read;

  p_slave0_write : process (clk) is
    variable addr_idx : integer;
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        s0_mem <= (others => (others => '0'));
      elsif s0_HSEL = '1' and s0_HTRANS = AHB_NONSEQ and s0_HWRITE = '1' then
        addr_idx := to_integer(unsigned(s0_HADDR(7 downto 2)));
        if addr_idx <= 63 then
          if s0_HWSTRB(0) = '1' then s0_mem(addr_idx)(7 downto 0)   <= s0_HWDATA(7 downto 0); end if;
          if s0_HWSTRB(1) = '1' then s0_mem(addr_idx)(15 downto 8)  <= s0_HWDATA(15 downto 8); end if;
          if s0_HWSTRB(2) = '1' then s0_mem(addr_idx)(23 downto 16) <= s0_HWDATA(23 downto 16); end if;
          if s0_HWSTRB(3) = '1' then s0_mem(addr_idx)(31 downto 24) <= s0_HWDATA(31 downto 24); end if;
        end if;
      end if;
    end if;
  end process p_slave0_write;

  -- Stimulus
  p_stimulus : process is
    variable rdata : std_ulogic_vector(31 downto 0);
    variable l     : line;
  begin
    m0_HSEL <= '0'; m0_HADDR <= (others=>'0'); m0_HTRANS <= AHB_IDLE;
    m0_HWRITE <= '0'; m0_HWDATA <= (others=>'0'); m0_HWSTRB <= x"F";
    m1_HSEL <= '0'; m1_HADDR <= (others=>'0'); m1_HTRANS <= AHB_IDLE;
    m1_HWRITE <= '0'; m1_HWDATA <= (others=>'0'); m1_HWSTRB <= x"F";

    -- Reset
    rst_n <= '0';
    for i in 1 to 6 loop wait until rising_edge(clk); end loop;
    rst_n <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- TEST 1: Fabric write via master 0 to slave 0 at 0x10000100
    write(l, string'("--- Test 1: Fabric write via M0 to S0 ---"));
    writeline(output, l);

    wait until rising_edge(clk);
    m0_HSEL   <= '1';
    m0_HADDR  <= x"10000100";
    m0_HTRANS <= AHB_NONSEQ;
    m0_HWRITE <= '1';
    m0_HWSTRB <= x"F";

    wait until rising_edge(clk);
    m0_HWDATA <= x"A5A5A5A5";
    m0_HSEL   <= '0';
    m0_HTRANS <= AHB_IDLE;

    wait until rising_edge(clk);
    if m0_HREADY /= '1' then
      for i in 1 to 20 loop
        wait until rising_edge(clk);
        exit when m0_HREADY = '1';
      end loop;
    end if;

    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- TEST 2: Fabric readback
    write(l, string'("--- Test 2: Fabric readback via M0 from S0 ---"));
    writeline(output, l);

    wait until rising_edge(clk);
    m0_HSEL   <= '1';
    m0_HADDR  <= x"10000100";
    m0_HTRANS <= AHB_NONSEQ;
    m0_HWRITE <= '0';
    m0_HWSTRB <= x"F";

    wait until rising_edge(clk);
    m0_HSEL   <= '0';
    m0_HTRANS <= AHB_IDLE;

    wait until rising_edge(clk);
    for i in 1 to 20 loop
      exit when m0_HREADY = '1';
      wait until rising_edge(clk);
    end loop;

    rdata := m0_HRDATA;
    check_eq(rdata, x"A5A5A5A5", "Fabric R/W 0x10000100", test_failed);

    -- Final result
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    if test_failed then
      write(l, string'("FAIL tb_bus_matrix_ahb"));
      writeline(output, l);
      finish(1);
    else
      write(l, string'(""));
      writeline(output, l);
      write(l, string'("PASS tb_bus_matrix_ahb"));
      writeline(output, l);
      finish(0);
    end if;

    wait;
  end process p_stimulus;

  p_watchdog : process is
    variable l : line;
  begin
    wait for 500 us;
    write(l, string'("FATAL_ERROR: simulation timeout in tb_bus_matrix_ahb"));
    writeline(output, l);
    finish(1);
    wait;
  end process p_watchdog;

end architecture sim;
