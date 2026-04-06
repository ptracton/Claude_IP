-- tb_bus_matrix_wb.vhd -- Wishbone bus_matrix VHDL-2008 testbench.
--
-- Tests fabric write + readback via master 0 to slave 0.
-- Address map configured via DUT generics (no admin port).
-- S0: base=0x10000000, mask=0xF0000000
-- S1: base=0x20000000, mask=0xF0000000
--
-- Prints "PASS tb_bus_matrix_wb" on success.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_bus_matrix_wb is
end entity tb_bus_matrix_wb;

architecture sim of tb_bus_matrix_wb is

  constant CLK_PERIOD : time := 10 ns;

  constant NM : positive := 2;
  constant NS : positive := 2;
  constant DW : positive := 32;
  constant AW : positive := 32;

  signal clk   : std_ulogic := '0';
  signal rst_n : std_ulogic := '0';

  -- Master 0 fabric port
  signal m0_CYC   : std_ulogic                     := '0';
  signal m0_STB   : std_ulogic                     := '0';
  signal m0_WE    : std_ulogic                     := '0';
  signal m0_ADR   : std_ulogic_vector(31 downto 0) := (others => '0');
  signal m0_DAT_O : std_ulogic_vector(31 downto 0) := (others => '0');
  signal m0_SEL   : std_ulogic_vector(3 downto 0)  := (others => '0');
  signal m0_DAT_I : std_ulogic_vector(31 downto 0);
  signal m0_ACK   : std_ulogic;
  signal m0_ERR   : std_ulogic;

  -- Flat-packed master busses
  signal M_CYC   : std_ulogic_vector(NM-1 downto 0)      := (others => '0');
  signal M_STB   : std_ulogic_vector(NM-1 downto 0)      := (others => '0');
  signal M_WE    : std_ulogic_vector(NM-1 downto 0)      := (others => '0');
  signal M_ADR   : std_ulogic_vector(NM*AW-1 downto 0)   := (others => '0');
  signal M_DAT_I : std_ulogic_vector(NM*DW-1 downto 0)   := (others => '0');
  signal M_SEL   : std_ulogic_vector(NM*4-1 downto 0)    := (others => '0');
  signal M_DAT_O : std_ulogic_vector(NM*DW-1 downto 0);
  signal M_ACK   : std_ulogic_vector(NM-1 downto 0);
  signal M_ERR   : std_ulogic_vector(NM-1 downto 0);

  -- Flat-packed slave busses
  signal S_CYC   : std_ulogic_vector(NS-1 downto 0);
  signal S_STB   : std_ulogic_vector(NS-1 downto 0);
  signal S_WE    : std_ulogic_vector(NS-1 downto 0);
  signal S_ADR   : std_ulogic_vector(NS*AW-1 downto 0);
  signal S_DAT_O : std_ulogic_vector(NS*DW-1 downto 0);
  signal S_SEL   : std_ulogic_vector(NS*4-1 downto 0);
  signal S_DAT_I : std_ulogic_vector(NS*DW-1 downto 0)   := (others => '0');
  signal S_ACK   : std_ulogic_vector(NS-1 downto 0)      := (others => '0');
  signal S_ERR   : std_ulogic_vector(NS-1 downto 0)      := (others => '0');

  -- Slave 0 extracted signals
  signal s0_CYC   : std_ulogic;
  signal s0_STB   : std_ulogic;
  signal s0_WE    : std_ulogic;
  signal s0_ADR   : std_ulogic_vector(31 downto 0);
  signal s0_DAT_O : std_ulogic_vector(31 downto 0);
  signal s0_SEL   : std_ulogic_vector(3 downto 0);

  signal s0_DAT_I : std_ulogic_vector(31 downto 0) := (others => '0');
  signal s0_ACK   : std_ulogic := '0';
  signal s0_ERR   : std_ulogic := '0';

  -- Slave 0 memory (16 words)
  type mem_t is array (0 to 15) of std_ulogic_vector(31 downto 0);
  signal s0_mem : mem_t := (others => (others => '0'));

  signal test_failed : boolean := false;

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

  component bus_matrix_wb is
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
      clk     : in  std_ulogic;
      rst_n   : in  std_ulogic;
      M_CYC   : in  std_ulogic_vector(NUM_MASTERS-1 downto 0);
      M_STB   : in  std_ulogic_vector(NUM_MASTERS-1 downto 0);
      M_WE    : in  std_ulogic_vector(NUM_MASTERS-1 downto 0);
      M_ADR   : in  std_ulogic_vector(NUM_MASTERS*ADDR_W-1 downto 0);
      M_DAT_I : in  std_ulogic_vector(NUM_MASTERS*DATA_W-1 downto 0);
      M_SEL   : in  std_ulogic_vector(NUM_MASTERS*4-1 downto 0);
      M_DAT_O : out std_ulogic_vector(NUM_MASTERS*DATA_W-1 downto 0);
      M_ACK   : out std_ulogic_vector(NUM_MASTERS-1 downto 0);
      M_ERR   : out std_ulogic_vector(NUM_MASTERS-1 downto 0);
      S_CYC   : out std_ulogic_vector(NUM_SLAVES-1 downto 0);
      S_STB   : out std_ulogic_vector(NUM_SLAVES-1 downto 0);
      S_WE    : out std_ulogic_vector(NUM_SLAVES-1 downto 0);
      S_ADR   : out std_ulogic_vector(NUM_SLAVES*ADDR_W-1 downto 0);
      S_DAT_O : out std_ulogic_vector(NUM_SLAVES*DATA_W-1 downto 0);
      S_SEL   : out std_ulogic_vector(NUM_SLAVES*4-1 downto 0);
      S_DAT_I : in  std_ulogic_vector(NUM_SLAVES*DATA_W-1 downto 0);
      S_ACK   : in  std_ulogic_vector(NUM_SLAVES-1 downto 0);
      S_ERR   : in  std_ulogic_vector(NUM_SLAVES-1 downto 0)
    );
  end component bus_matrix_wb;

  procedure check_eq (
    actual   : in std_ulogic_vector(31 downto 0);
    expected : in std_ulogic_vector(31 downto 0);
    msg      : in string;
    signal failed_sig : out boolean
  ) is
    variable l : line;
  begin
    if actual /= expected then
      write(l, string'("FAIL: "));
      write(l, msg);
      write(l, string'(" expected=0x"));
      write(l, to_hstring(expected));
      write(l, string'(" got=0x"));
      write(l, to_hstring(actual));
      writeline(output, l);
      failed_sig <= true;
    else
      write(l, string'("  OK: "));
      write(l, msg);
      write(l, string'(" = 0x"));
      write(l, to_hstring(actual));
      writeline(output, l);
    end if;
  end procedure check_eq;

begin

  clk <= not clk after CLK_PERIOD / 2;

  -- Flat-pack master 0 (slot 0)
  M_CYC(0)             <= m0_CYC;
  M_CYC(1)             <= '0';
  M_STB(0)             <= m0_STB;
  M_STB(1)             <= '0';
  M_WE(0)              <= m0_WE;
  M_WE(1)              <= '0';
  M_ADR(31 downto 0)   <= m0_ADR;
  M_ADR(63 downto 32)  <= (others => '0');
  M_DAT_I(31 downto 0) <= m0_DAT_O;
  M_DAT_I(63 downto 32) <= (others => '0');
  M_SEL(3 downto 0)    <= m0_SEL;
  M_SEL(7 downto 4)    <= (others => '0');

  m0_DAT_I <= M_DAT_O(31 downto 0);
  m0_ACK   <= M_ACK(0);
  m0_ERR   <= M_ERR(0);

  -- Extract slave 0
  s0_CYC   <= S_CYC(0);
  s0_STB   <= S_STB(0);
  s0_WE    <= S_WE(0);
  s0_ADR   <= S_ADR(31 downto 0);
  s0_DAT_O <= S_DAT_O(31 downto 0);
  s0_SEL   <= S_SEL(3 downto 0);

  S_DAT_I(31 downto 0)  <= s0_DAT_I;
  S_DAT_I(63 downto 32) <= (others => '0');
  S_ACK(0)               <= s0_ACK;
  S_ACK(1)               <= '0';
  S_ERR(0)               <= s0_ERR;
  S_ERR(1)               <= '0';

  -- DUT
  u_dut : bus_matrix_wb
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
      clk     => clk,
      rst_n   => rst_n,
      M_CYC   => M_CYC,
      M_STB   => M_STB,
      M_WE    => M_WE,
      M_ADR   => M_ADR,
      M_DAT_I => M_DAT_I,
      M_SEL   => M_SEL,
      M_DAT_O => M_DAT_O,
      M_ACK   => M_ACK,
      M_ERR   => M_ERR,
      S_CYC   => S_CYC,
      S_STB   => S_STB,
      S_WE    => S_WE,
      S_ADR   => S_ADR,
      S_DAT_O => S_DAT_O,
      S_SEL   => S_SEL,
      S_DAT_I => S_DAT_I,
      S_ACK   => S_ACK,
      S_ERR   => S_ERR
    );

  -- Slave 0 BFM
  p_slave0 : process (clk) is
    variable addr_idx : integer;
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        s0_ACK   <= '0';
        s0_DAT_I <= (others => '0');
        s0_mem   <= (others => (others => '0'));
      else
        s0_ACK <= '0';

        if s0_CYC = '1' and s0_STB = '1' and s0_ACK = '0' then
          addr_idx := to_integer(unsigned(s0_ADR(5 downto 2)));
          if addr_idx > 15 then addr_idx := 0; end if;

          if s0_WE = '1' then
            if s0_SEL(0) = '1' then s0_mem(addr_idx)(7 downto 0)   <= s0_DAT_O(7 downto 0); end if;
            if s0_SEL(1) = '1' then s0_mem(addr_idx)(15 downto 8)  <= s0_DAT_O(15 downto 8); end if;
            if s0_SEL(2) = '1' then s0_mem(addr_idx)(23 downto 16) <= s0_DAT_O(23 downto 16); end if;
            if s0_SEL(3) = '1' then s0_mem(addr_idx)(31 downto 24) <= s0_DAT_O(31 downto 24); end if;
          else
            s0_DAT_I <= s0_mem(addr_idx);
          end if;
          s0_ACK <= '1';
        end if;
      end if;
    end if;
  end process p_slave0;

  s0_ERR <= '0';

  -- Stimulus
  p_stimulus : process is
    variable rdata : std_ulogic_vector(31 downto 0);
    variable l     : line;
  begin
    m0_CYC   <= '0';
    m0_STB   <= '0';
    m0_WE    <= '0';
    m0_ADR   <= (others => '0');
    m0_DAT_O <= (others => '0');
    m0_SEL   <= x"F";

    rst_n <= '0';
    for i in 1 to 4 loop wait until rising_edge(clk); end loop;
    rst_n <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- TEST 1: Fabric write via master 0 to slave 0 at 0x10000100
    write(l, string'("--- Test 1: Fabric write via M0 to S0 ---"));
    writeline(output, l);

    wait until rising_edge(clk);
    m0_CYC   <= '1';
    m0_STB   <= '1';
    m0_WE    <= '1';
    m0_ADR   <= x"10000100";
    m0_DAT_O <= x"A5A5A5A5";
    m0_SEL   <= x"F";

    for i in 1 to 30 loop
      wait until rising_edge(clk);
      exit when m0_ACK = '1';
    end loop;

    m0_CYC <= '0';
    m0_STB <= '0';
    m0_WE  <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- TEST 2: Fabric readback
    write(l, string'("--- Test 2: Fabric readback via M0 from S0 ---"));
    writeline(output, l);

    wait until rising_edge(clk);
    m0_CYC <= '1';
    m0_STB <= '1';
    m0_WE  <= '0';
    m0_ADR <= x"10000100";
    m0_SEL <= x"F";

    for i in 1 to 30 loop
      wait until rising_edge(clk);
      exit when m0_ACK = '1';
    end loop;

    rdata := m0_DAT_I;
    m0_CYC <= '0';
    m0_STB <= '0';

    check_eq(rdata, x"A5A5A5A5", "Fabric R/W 0x10000100", test_failed);

    -- Final result
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    if test_failed then
      write(l, string'("FAIL tb_bus_matrix_wb"));
      writeline(output, l);
      finish(1);
    else
      write(l, string'(""));
      writeline(output, l);
      write(l, string'("PASS tb_bus_matrix_wb"));
      writeline(output, l);
      finish(0);
    end if;

    wait;
  end process p_stimulus;

  p_watchdog : process is
    variable l : line;
  begin
    wait for 500 us;
    write(l, string'("FATAL_ERROR: simulation timeout in tb_bus_matrix_wb"));
    writeline(output, l);
    finish(1);
    wait;
  end process p_watchdog;

end architecture sim;
