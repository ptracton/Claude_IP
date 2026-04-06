-- tb_bus_matrix_axi.vhd -- AXI4-Lite bus_matrix VHDL-2008 testbench.
--
-- Tests fabric write + readback via master 0 to slave 0.
-- Address map configured via DUT generics (no admin port).
-- S0: base=0x10000000, mask=0xF0000000
-- S1: base=0x20000000, mask=0xF0000000
--
-- Prints "PASS tb_bus_matrix_axi" on success.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_bus_matrix_axi is
end entity tb_bus_matrix_axi;

architecture sim of tb_bus_matrix_axi is

  constant CLK_PERIOD : time := 10 ns;

  constant NM : positive := 2;
  constant NS : positive := 2;
  constant DW : positive := 32;
  constant AW : positive := 32;

  signal clk   : std_ulogic := '0';
  signal rst_n : std_ulogic := '0';

  -- Master 0 fabric port
  signal m0_AWVALID : std_ulogic                     := '0';
  signal m0_AWREADY : std_ulogic;
  signal m0_AWADDR  : std_ulogic_vector(31 downto 0) := (others => '0');
  signal m0_WVALID  : std_ulogic                     := '0';
  signal m0_WREADY  : std_ulogic;
  signal m0_WDATA   : std_ulogic_vector(31 downto 0) := (others => '0');
  signal m0_WSTRB   : std_ulogic_vector(3 downto 0)  := (others => '0');
  signal m0_BVALID  : std_ulogic;
  signal m0_BREADY  : std_ulogic                     := '1';
  signal m0_BRESP   : std_ulogic_vector(1 downto 0);
  signal m0_ARVALID : std_ulogic                     := '0';
  signal m0_ARREADY : std_ulogic;
  signal m0_ARADDR  : std_ulogic_vector(31 downto 0) := (others => '0');
  signal m0_RVALID  : std_ulogic;
  signal m0_RREADY  : std_ulogic                     := '1';
  signal m0_RDATA   : std_ulogic_vector(31 downto 0);
  signal m0_RRESP   : std_ulogic_vector(1 downto 0);

  -- Flat-packed master busses
  signal M_AWVALID : std_ulogic_vector(NM-1 downto 0)    := (others => '0');
  signal M_AWREADY : std_ulogic_vector(NM-1 downto 0);
  signal M_AWADDR  : std_ulogic_vector(NM*AW-1 downto 0) := (others => '0');
  signal M_WVALID  : std_ulogic_vector(NM-1 downto 0)    := (others => '0');
  signal M_WREADY  : std_ulogic_vector(NM-1 downto 0);
  signal M_WDATA   : std_ulogic_vector(NM*DW-1 downto 0) := (others => '0');
  signal M_WSTRB   : std_ulogic_vector(NM*4-1 downto 0)  := (others => '0');
  signal M_BVALID  : std_ulogic_vector(NM-1 downto 0);
  signal M_BREADY  : std_ulogic_vector(NM-1 downto 0)    := (others => '0');
  signal M_BRESP   : std_ulogic_vector(NM*2-1 downto 0);
  signal M_ARVALID : std_ulogic_vector(NM-1 downto 0)    := (others => '0');
  signal M_ARREADY : std_ulogic_vector(NM-1 downto 0);
  signal M_ARADDR  : std_ulogic_vector(NM*AW-1 downto 0) := (others => '0');
  signal M_RVALID  : std_ulogic_vector(NM-1 downto 0);
  signal M_RREADY  : std_ulogic_vector(NM-1 downto 0)    := (others => '0');
  signal M_RDATA   : std_ulogic_vector(NM*DW-1 downto 0);
  signal M_RRESP   : std_ulogic_vector(NM*2-1 downto 0);

  -- Flat-packed slave busses
  signal S_AWVALID : std_ulogic_vector(NS-1 downto 0);
  signal S_AWREADY : std_ulogic_vector(NS-1 downto 0)    := (others => '1');
  signal S_AWADDR  : std_ulogic_vector(NS*AW-1 downto 0);
  signal S_WVALID  : std_ulogic_vector(NS-1 downto 0);
  signal S_WREADY  : std_ulogic_vector(NS-1 downto 0)    := (others => '1');
  signal S_WDATA   : std_ulogic_vector(NS*DW-1 downto 0);
  signal S_WSTRB   : std_ulogic_vector(NS*4-1 downto 0);
  signal S_BVALID  : std_ulogic_vector(NS-1 downto 0)    := (others => '0');
  signal S_BREADY  : std_ulogic_vector(NS-1 downto 0);
  signal S_BRESP   : std_ulogic_vector(NS*2-1 downto 0)  := (others => '0');
  signal S_ARVALID : std_ulogic_vector(NS-1 downto 0);
  signal S_ARREADY : std_ulogic_vector(NS-1 downto 0)    := (others => '1');
  signal S_ARADDR  : std_ulogic_vector(NS*AW-1 downto 0);
  signal S_RVALID  : std_ulogic_vector(NS-1 downto 0)    := (others => '0');
  signal S_RREADY  : std_ulogic_vector(NS-1 downto 0);
  signal S_RDATA   : std_ulogic_vector(NS*DW-1 downto 0) := (others => '0');
  signal S_RRESP   : std_ulogic_vector(NS*2-1 downto 0)  := (others => '0');

  -- Slave 0 extracted signals
  signal s0_AWVALID : std_ulogic;
  signal s0_AWADDR  : std_ulogic_vector(31 downto 0);
  signal s0_WVALID  : std_ulogic;
  signal s0_WDATA   : std_ulogic_vector(31 downto 0);
  signal s0_WSTRB   : std_ulogic_vector(3 downto 0);
  signal s0_BREADY  : std_ulogic;
  signal s0_ARVALID : std_ulogic;
  signal s0_ARADDR  : std_ulogic_vector(31 downto 0);
  signal s0_RREADY  : std_ulogic;

  -- Slave 0 driven outputs
  signal s0_AWREADY : std_ulogic := '1';
  signal s0_WREADY  : std_ulogic := '1';
  signal s0_BVALID  : std_ulogic := '0';
  signal s0_BRESP   : std_ulogic_vector(1 downto 0) := "00";
  signal s0_ARREADY : std_ulogic := '1';
  signal s0_RVALID  : std_ulogic := '0';
  signal s0_RDATA   : std_ulogic_vector(31 downto 0) := (others => '0');
  signal s0_RRESP   : std_ulogic_vector(1 downto 0) := "00";

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

  component bus_matrix_axi is
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
      M_AWVALID : in  std_ulogic_vector(NUM_MASTERS-1 downto 0);
      M_AWREADY : out std_ulogic_vector(NUM_MASTERS-1 downto 0);
      M_AWADDR  : in  std_ulogic_vector(NUM_MASTERS*ADDR_W-1 downto 0);
      M_WVALID  : in  std_ulogic_vector(NUM_MASTERS-1 downto 0);
      M_WREADY  : out std_ulogic_vector(NUM_MASTERS-1 downto 0);
      M_WDATA   : in  std_ulogic_vector(NUM_MASTERS*DATA_W-1 downto 0);
      M_WSTRB   : in  std_ulogic_vector(NUM_MASTERS*4-1 downto 0);
      M_BVALID  : out std_ulogic_vector(NUM_MASTERS-1 downto 0);
      M_BREADY  : in  std_ulogic_vector(NUM_MASTERS-1 downto 0);
      M_BRESP   : out std_ulogic_vector(NUM_MASTERS*2-1 downto 0);
      M_ARVALID : in  std_ulogic_vector(NUM_MASTERS-1 downto 0);
      M_ARREADY : out std_ulogic_vector(NUM_MASTERS-1 downto 0);
      M_ARADDR  : in  std_ulogic_vector(NUM_MASTERS*ADDR_W-1 downto 0);
      M_RVALID  : out std_ulogic_vector(NUM_MASTERS-1 downto 0);
      M_RREADY  : in  std_ulogic_vector(NUM_MASTERS-1 downto 0);
      M_RDATA   : out std_ulogic_vector(NUM_MASTERS*DATA_W-1 downto 0);
      M_RRESP   : out std_ulogic_vector(NUM_MASTERS*2-1 downto 0);
      S_AWVALID : out std_ulogic_vector(NUM_SLAVES-1 downto 0);
      S_AWREADY : in  std_ulogic_vector(NUM_SLAVES-1 downto 0);
      S_AWADDR  : out std_ulogic_vector(NUM_SLAVES*ADDR_W-1 downto 0);
      S_WVALID  : out std_ulogic_vector(NUM_SLAVES-1 downto 0);
      S_WREADY  : in  std_ulogic_vector(NUM_SLAVES-1 downto 0);
      S_WDATA   : out std_ulogic_vector(NUM_SLAVES*DATA_W-1 downto 0);
      S_WSTRB   : out std_ulogic_vector(NUM_SLAVES*4-1 downto 0);
      S_BVALID  : in  std_ulogic_vector(NUM_SLAVES-1 downto 0);
      S_BREADY  : out std_ulogic_vector(NUM_SLAVES-1 downto 0);
      S_BRESP   : in  std_ulogic_vector(NUM_SLAVES*2-1 downto 0);
      S_ARVALID : out std_ulogic_vector(NUM_SLAVES-1 downto 0);
      S_ARREADY : in  std_ulogic_vector(NUM_SLAVES-1 downto 0);
      S_ARADDR  : out std_ulogic_vector(NUM_SLAVES*ADDR_W-1 downto 0);
      S_RVALID  : in  std_ulogic_vector(NUM_SLAVES-1 downto 0);
      S_RREADY  : out std_ulogic_vector(NUM_SLAVES-1 downto 0);
      S_RDATA   : in  std_ulogic_vector(NUM_SLAVES*DATA_W-1 downto 0);
      S_RRESP   : in  std_ulogic_vector(NUM_SLAVES*2-1 downto 0)
    );
  end component bus_matrix_axi;

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
  M_AWVALID(0)          <= m0_AWVALID;
  M_AWVALID(1)          <= '0';
  M_AWADDR(31 downto 0) <= m0_AWADDR;
  M_AWADDR(63 downto 32) <= (others => '0');
  M_WVALID(0)           <= m0_WVALID;
  M_WVALID(1)           <= '0';
  M_WDATA(31 downto 0)  <= m0_WDATA;
  M_WDATA(63 downto 32) <= (others => '0');
  M_WSTRB(3 downto 0)   <= m0_WSTRB;
  M_WSTRB(7 downto 4)   <= (others => '0');
  M_BREADY(0)           <= m0_BREADY;
  M_BREADY(1)           <= '0';
  M_ARVALID(0)          <= m0_ARVALID;
  M_ARVALID(1)          <= '0';
  M_ARADDR(31 downto 0) <= m0_ARADDR;
  M_ARADDR(63 downto 32) <= (others => '0');
  M_RREADY(0)           <= m0_RREADY;
  M_RREADY(1)           <= '0';

  m0_AWREADY <= M_AWREADY(0);
  m0_WREADY  <= M_WREADY(0);
  m0_BVALID  <= M_BVALID(0);
  m0_BRESP   <= M_BRESP(1 downto 0);
  m0_ARREADY <= M_ARREADY(0);
  m0_RVALID  <= M_RVALID(0);
  m0_RDATA   <= M_RDATA(31 downto 0);
  m0_RRESP   <= M_RRESP(1 downto 0);

  -- Extract slave 0
  s0_AWVALID <= S_AWVALID(0);
  s0_AWADDR  <= S_AWADDR(31 downto 0);
  s0_WVALID  <= S_WVALID(0);
  s0_WDATA   <= S_WDATA(31 downto 0);
  s0_WSTRB   <= S_WSTRB(3 downto 0);
  s0_BREADY  <= S_BREADY(0);
  s0_ARVALID <= S_ARVALID(0);
  s0_ARADDR  <= S_ARADDR(31 downto 0);
  s0_RREADY  <= S_RREADY(0);

  -- Slave 0 drives back
  S_AWREADY(0)          <= s0_AWREADY;
  S_AWREADY(1)          <= '1';
  S_WREADY(0)           <= s0_WREADY;
  S_WREADY(1)           <= '1';
  S_BVALID(0)           <= s0_BVALID;
  S_BVALID(1)           <= '0';
  S_BRESP(1 downto 0)   <= s0_BRESP;
  S_BRESP(3 downto 2)   <= (others => '0');
  S_ARREADY(0)          <= s0_ARREADY;
  S_ARREADY(1)          <= '1';
  S_RVALID(0)           <= s0_RVALID;
  S_RVALID(1)           <= '0';
  S_RDATA(31 downto 0)  <= s0_RDATA;
  S_RDATA(63 downto 32) <= (others => '0');
  S_RRESP(1 downto 0)   <= s0_RRESP;
  S_RRESP(3 downto 2)   <= (others => '0');

  -- DUT
  u_dut : bus_matrix_axi
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
      clk       => clk,
      rst_n     => rst_n,
      M_AWVALID => M_AWVALID,
      M_AWREADY => M_AWREADY,
      M_AWADDR  => M_AWADDR,
      M_WVALID  => M_WVALID,
      M_WREADY  => M_WREADY,
      M_WDATA   => M_WDATA,
      M_WSTRB   => M_WSTRB,
      M_BVALID  => M_BVALID,
      M_BREADY  => M_BREADY,
      M_BRESP   => M_BRESP,
      M_ARVALID => M_ARVALID,
      M_ARREADY => M_ARREADY,
      M_ARADDR  => M_ARADDR,
      M_RVALID  => M_RVALID,
      M_RREADY  => M_RREADY,
      M_RDATA   => M_RDATA,
      M_RRESP   => M_RRESP,
      S_AWVALID => S_AWVALID,
      S_AWREADY => S_AWREADY,
      S_AWADDR  => S_AWADDR,
      S_WVALID  => S_WVALID,
      S_WREADY  => S_WREADY,
      S_WDATA   => S_WDATA,
      S_WSTRB   => S_WSTRB,
      S_BVALID  => S_BVALID,
      S_BREADY  => S_BREADY,
      S_BRESP   => S_BRESP,
      S_ARVALID => S_ARVALID,
      S_ARREADY => S_ARREADY,
      S_ARADDR  => S_ARADDR,
      S_RVALID  => S_RVALID,
      S_RREADY  => S_RREADY,
      S_RDATA   => S_RDATA,
      S_RRESP   => S_RRESP
    );

  -- Slave 0 BFM
  p_slave0 : process (clk) is
    variable addr_idx : integer;
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        s0_BVALID <= '0';
        s0_RVALID <= '0';
        s0_RDATA  <= (others => '0');
        s0_mem    <= (others => (others => '0'));
      else
        s0_BVALID <= '0';
        s0_RVALID <= '0';

        if s0_AWVALID = '1' and s0_WVALID = '1' then
          addr_idx := to_integer(unsigned(s0_AWADDR(5 downto 2)));
          if addr_idx > 15 then addr_idx := 0; end if;
          if s0_WSTRB(0) = '1' then s0_mem(addr_idx)(7 downto 0)   <= s0_WDATA(7 downto 0); end if;
          if s0_WSTRB(1) = '1' then s0_mem(addr_idx)(15 downto 8)  <= s0_WDATA(15 downto 8); end if;
          if s0_WSTRB(2) = '1' then s0_mem(addr_idx)(23 downto 16) <= s0_WDATA(23 downto 16); end if;
          if s0_WSTRB(3) = '1' then s0_mem(addr_idx)(31 downto 24) <= s0_WDATA(31 downto 24); end if;
          s0_BVALID <= '1';
        end if;

        if s0_BVALID = '1' and s0_BREADY = '1' then
          s0_BVALID <= '0';
        end if;

        if s0_ARVALID = '1' then
          addr_idx := to_integer(unsigned(s0_ARADDR(5 downto 2)));
          if addr_idx > 15 then addr_idx := 0; end if;
          s0_RDATA  <= s0_mem(addr_idx);
          s0_RVALID <= '1';
        end if;

        if s0_RVALID = '1' and s0_RREADY = '1' then
          s0_RVALID <= '0';
        end if;
      end if;
    end if;
  end process p_slave0;

  -- Stimulus
  p_stimulus : process is
    variable rd_val : std_ulogic_vector(31 downto 0);
    variable l      : line;
  begin
    m0_AWVALID <= '0'; m0_AWADDR <= (others => '0');
    m0_WVALID  <= '0'; m0_WDATA  <= (others => '0'); m0_WSTRB <= x"F";
    m0_BREADY  <= '1';
    m0_ARVALID <= '0'; m0_ARADDR <= (others => '0');
    m0_RREADY  <= '1';

    rst_n <= '0';
    for i in 1 to 4 loop wait until rising_edge(clk); end loop;
    rst_n <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- TEST 1: Fabric write via master 0 to slave 0 at 0x10000100
    write(l, string'("--- Test 1: Fabric write via M0 to S0 ---"));
    writeline(output, l);

    wait until rising_edge(clk);
    m0_AWVALID <= '1';
    m0_AWADDR  <= x"10000100";
    m0_WVALID  <= '1';
    m0_WDATA   <= x"A5A5A5A5";
    m0_WSTRB   <= x"F";
    m0_BREADY  <= '1';

    loop
      wait until rising_edge(clk);
      if m0_AWREADY = '1' and m0_WREADY = '1' then
        m0_AWVALID <= '0';
        m0_WVALID  <= '0';
        exit;
      end if;
    end loop;

    for i in 1 to 30 loop
      exit when m0_BVALID = '1';
      wait until rising_edge(clk);
    end loop;
    wait until rising_edge(clk);

    -- TEST 2: Fabric readback
    write(l, string'("--- Test 2: Fabric readback via M0 from S0 ---"));
    writeline(output, l);

    wait until rising_edge(clk);
    m0_ARVALID <= '1';
    m0_ARADDR  <= x"10000100";
    m0_RREADY  <= '1';

    loop
      wait until rising_edge(clk);
      if m0_ARREADY = '1' then
        m0_ARVALID <= '0';
        exit;
      end if;
    end loop;

    for i in 1 to 30 loop
      exit when m0_RVALID = '1';
      wait until rising_edge(clk);
    end loop;

    rd_val := m0_RDATA;
    check_eq(rd_val, x"A5A5A5A5", "Fabric R/W 0x10000100", test_failed);
    wait until rising_edge(clk);

    -- Final result
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    if test_failed then
      write(l, string'("FAIL tb_bus_matrix_axi"));
      writeline(output, l);
      finish(1);
    else
      write(l, string'(""));
      writeline(output, l);
      write(l, string'("PASS tb_bus_matrix_axi"));
      writeline(output, l);
      finish(0);
    end if;

    wait;
  end process p_stimulus;

  p_watchdog : process is
    variable l : line;
  begin
    wait for 500 us;
    write(l, string'("FATAL_ERROR: simulation timeout in tb_bus_matrix_axi"));
    writeline(output, l);
    finish(1);
    wait;
  end process p_watchdog;

end architecture sim;
