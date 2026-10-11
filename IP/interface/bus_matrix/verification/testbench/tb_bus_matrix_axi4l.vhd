-- tb_bus_matrix_axi4l.vhd — AXI4-Lite bus_matrix directed testbench (VHDL-2008).
--
-- DUT: bus_matrix_axi4l with its default generics (bus_matrix_pkg).
--   Masters: u_m0, u_m1 — bus_matrix_tb_axi4l_master (one transfer per command)
--   Slaves:  gen_slv(j) — shared claude_axi4l_if bridge + bus_matrix_tb_mem
-- The test sequence mirrors the SV testbench (verification/tests/test_*.sv):
-- test_reset, test_route, test_strobe, test_decode_err, test_contention, test_arb.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

use work.ip_test_pkg.all;
use work.bus_matrix_pkg.all;

entity tb_bus_matrix_axi4l is
end entity tb_bus_matrix_axi4l;

architecture sim of tb_bus_matrix_axi4l is

  constant CLK_PERIOD : time     := 10 ns;
  constant N_MST      : positive := BM_NUM_MASTERS;
  constant N_SLV      : positive := BM_NUM_SLAVES;
  constant MEM_AW     : positive := 10;  -- 1024 words = 4 KB per slave

  subtype word_t is std_ulogic_vector(31 downto 0);
  type word_arr_t is array (natural range <>) of word_t;
  type strb_arr_t is array (natural range <>) of std_ulogic_vector(3 downto 0);

  constant ZERO : word_t := (others => '0');
  -- Addresses that match no slave in the default map
  constant UNMAPPED : word_arr_t(0 to 3) := (
    x"10000000",  -- gap between Boot ROM and SRAM
    x"00010000",  -- just past the 64 KB Boot ROM
    x"20020000",  -- just past the 128 KB SRAM
    x"F0000000"   -- top of the address space
  );

  signal clk   : std_ulogic := '0';
  signal rst_n : std_ulogic := '0';
  signal rst   : std_ulogic;

  -- DUT ports (flat-packed)
  signal M_AWVALID  : std_ulogic_vector(N_MST - 1 downto 0);
  signal M_AWREADY  : std_ulogic_vector(N_MST - 1 downto 0);
  signal M_AWADDR   : std_ulogic_vector(N_MST * 32 - 1 downto 0);
  signal M_WVALID   : std_ulogic_vector(N_MST - 1 downto 0);
  signal M_WREADY   : std_ulogic_vector(N_MST - 1 downto 0);
  signal M_WDATA    : std_ulogic_vector(N_MST * 32 - 1 downto 0);
  signal M_WSTRB    : std_ulogic_vector(N_MST * 4 - 1 downto 0);
  signal M_BVALID   : std_ulogic_vector(N_MST - 1 downto 0);
  signal M_BREADY   : std_ulogic_vector(N_MST - 1 downto 0);
  signal M_BRESP    : std_ulogic_vector(N_MST * 2 - 1 downto 0);
  signal M_ARVALID  : std_ulogic_vector(N_MST - 1 downto 0);
  signal M_ARREADY  : std_ulogic_vector(N_MST - 1 downto 0);
  signal M_ARADDR   : std_ulogic_vector(N_MST * 32 - 1 downto 0);
  signal M_RVALID   : std_ulogic_vector(N_MST - 1 downto 0);
  signal M_RREADY   : std_ulogic_vector(N_MST - 1 downto 0);
  signal M_RDATA    : std_ulogic_vector(N_MST * 32 - 1 downto 0);
  signal M_RRESP    : std_ulogic_vector(N_MST * 2 - 1 downto 0);
  signal S_AWVALID  : std_ulogic_vector(N_SLV - 1 downto 0);
  signal S_AWREADY  : std_ulogic_vector(N_SLV - 1 downto 0);
  signal S_AWADDR   : std_ulogic_vector(N_SLV * 32 - 1 downto 0);
  signal S_WVALID   : std_ulogic_vector(N_SLV - 1 downto 0);
  signal S_WREADY   : std_ulogic_vector(N_SLV - 1 downto 0);
  signal S_WDATA    : std_ulogic_vector(N_SLV * 32 - 1 downto 0);
  signal S_WSTRB    : std_ulogic_vector(N_SLV * 4 - 1 downto 0);
  signal S_BVALID   : std_ulogic_vector(N_SLV - 1 downto 0);
  signal S_BREADY   : std_ulogic_vector(N_SLV - 1 downto 0);
  signal S_BRESP    : std_ulogic_vector(N_SLV * 2 - 1 downto 0);
  signal S_ARVALID  : std_ulogic_vector(N_SLV - 1 downto 0);
  signal S_ARREADY  : std_ulogic_vector(N_SLV - 1 downto 0);
  signal S_ARADDR   : std_ulogic_vector(N_SLV * 32 - 1 downto 0);
  signal S_RVALID   : std_ulogic_vector(N_SLV - 1 downto 0);
  signal S_RREADY   : std_ulogic_vector(N_SLV - 1 downto 0);
  signal S_RDATA    : std_ulogic_vector(N_SLV * 32 - 1 downto 0);
  signal S_RRESP    : std_ulogic_vector(N_SLV * 2 - 1 downto 0);

  -- Master command interfaces
  signal cmd_req   : std_ulogic_vector(0 to N_MST - 1) := (others => '0');
  signal cmd_ack   : std_ulogic_vector(0 to N_MST - 1);
  signal cmd_we    : std_ulogic_vector(0 to N_MST - 1) := (others => '0');
  signal cmd_addr  : word_arr_t(0 to N_MST - 1) := (others => ZERO);
  signal cmd_wdata : word_arr_t(0 to N_MST - 1) := (others => ZERO);
  signal cmd_strb  : strb_arr_t(0 to N_MST - 1) := (others => x"F");
  signal rsp_rdata : word_arr_t(0 to N_MST - 1);
  signal rsp_err   : std_ulogic_vector(0 to N_MST - 1);

  -- Slave 1 write log (arbitration test)
  signal log_clear   : std_ulogic := '0';
  signal s1_wr_count : natural;
  signal s1_wr_log0  : std_ulogic_vector(MEM_AW - 1 downto 0);
  signal s1_wr_log1  : std_ulogic_vector(MEM_AW - 1 downto 0);

  signal sim_done : boolean := false;

  -- Byte address of offset off inside slave j's region
  function slv_addr (j : natural; off : std_ulogic_vector(11 downto 0)) return word_t is
  begin
    return BM_S_BASE_USED(j * 32 + 31 downto j * 32) or (x"00000" & off);
  end function slv_addr;

  function word (k : natural) return word_t is
  begin
    return std_ulogic_vector(to_unsigned(k, 32));
  end function word;

  function tag (j : natural) return word_t is  -- j << 8
  begin
    return std_ulogic_vector(to_unsigned(j * 256, 32));
  end function tag;

  function off (base : std_ulogic_vector(11 downto 0); k : natural) return std_ulogic_vector is
  begin
    return std_ulogic_vector(unsigned(base) + to_unsigned(4 * k, 12));
  end function off;

  function flag (b : std_ulogic) return word_t is
  begin
    return (31 downto 1 => '0') & b;
  end function flag;

begin

  clk <= not clk after CLK_PERIOD / 2;
  rst <= not rst_n;

  u_dut : entity work.bus_matrix_axi4l(rtl)
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

  gen_mst : for gi in 0 to N_MST - 1 generate
    u_m : entity work.bus_matrix_tb_axi4l_master(sim)
      port map (
        clk       => clk,
        cmd_req   => cmd_req(gi),
        cmd_we    => cmd_we(gi),
        cmd_addr  => cmd_addr(gi),
        cmd_wdata => cmd_wdata(gi),
        cmd_strb  => cmd_strb(gi),
        cmd_ack   => cmd_ack(gi),
        rsp_rdata => rsp_rdata(gi),
        rsp_err   => rsp_err(gi),
        AWVALID   => M_AWVALID(gi),
        AWREADY   => M_AWREADY(gi),
        AWADDR    => M_AWADDR(gi * 32 + 31 downto gi * 32),
        WVALID    => M_WVALID(gi),
        WREADY    => M_WREADY(gi),
        WDATA     => M_WDATA(gi * 32 + 31 downto gi * 32),
        WSTRB     => M_WSTRB(gi * 4 + 3 downto gi * 4),
        BVALID    => M_BVALID(gi),
        BREADY    => M_BREADY(gi),
        BRESP     => M_BRESP(gi * 2 + 1 downto gi * 2),
        ARVALID   => M_ARVALID(gi),
        ARREADY   => M_ARREADY(gi),
        ARADDR    => M_ARADDR(gi * 32 + 31 downto gi * 32),
        RVALID    => M_RVALID(gi),
        RREADY    => M_RREADY(gi),
        RDATA     => M_RDATA(gi * 32 + 31 downto gi * 32),
        RRESP     => M_RRESP(gi * 2 + 1 downto gi * 2)
      );
  end generate gen_mst;

  gen_slv : for gj in 0 to N_SLV - 1 generate
    signal wr_en     : std_ulogic;
    signal wr_addr   : std_ulogic_vector(MEM_AW - 1 downto 0);
    signal wr_data   : std_ulogic_vector(31 downto 0);
    signal wr_strb   : std_ulogic_vector(3 downto 0);
    signal rd_en     : std_ulogic;
    signal rd_addr   : std_ulogic_vector(MEM_AW - 1 downto 0);
    signal rd_data   : std_ulogic_vector(31 downto 0);
    signal wr_count  : natural;
    signal wr_log0   : std_ulogic_vector(MEM_AW - 1 downto 0);
    signal wr_log1   : std_ulogic_vector(MEM_AW - 1 downto 0);
  begin
    u_if : entity work.claude_axi4l_if(rtl)
      generic map (
        DATA_W => 32,
        ADDR_W => MEM_AW
      )
      port map (
        ACLK    => clk,
        ARESETn => rst_n,
        AWVALID => S_AWVALID(gj),
        AWREADY => S_AWREADY(gj),
        AWADDR  => S_AWADDR(gj * 32 + 11 downto gj * 32),
        WVALID  => S_WVALID(gj),
        WREADY  => S_WREADY(gj),
        WDATA   => S_WDATA(gj * 32 + 31 downto gj * 32),
        WSTRB   => S_WSTRB(gj * 4 + 3 downto gj * 4),
        BVALID  => S_BVALID(gj),
        BREADY  => S_BREADY(gj),
        BRESP   => S_BRESP(gj * 2 + 1 downto gj * 2),
        ARVALID => S_ARVALID(gj),
        ARREADY => S_ARREADY(gj),
        ARADDR  => S_ARADDR(gj * 32 + 11 downto gj * 32),
        RVALID  => S_RVALID(gj),
        RREADY  => S_RREADY(gj),
        RDATA   => S_RDATA(gj * 32 + 31 downto gj * 32),
        RRESP   => S_RRESP(gj * 2 + 1 downto gj * 2),
        wr_en   => wr_en,
        wr_addr => wr_addr,
        wr_data => wr_data,
        wr_strb => wr_strb,
        rd_en   => rd_en,
        rd_addr => rd_addr,
        rd_data => rd_data
      );

    u_mem : entity work.bus_matrix_tb_mem(sim)
      generic map (
        ADDR_W => MEM_AW
      )
      port map (
        clk       => clk,
        wr_en     => wr_en,
        wr_addr   => wr_addr,
        wr_data   => wr_data,
        wr_strb   => wr_strb,
        rd_en     => rd_en,
        rd_addr   => rd_addr,
        rd_data   => rd_data,
        log_clear => log_clear,
        wr_count  => wr_count,
        wr_log0   => wr_log0,
        wr_log1   => wr_log1
      );

    g_s1 : if gj = 1 generate
      s1_wr_count <= wr_count;
      s1_wr_log0  <= wr_log0;
      s1_wr_log1  <= wr_log1;
    end generate g_s1;
  end generate gen_slv;

  p_timeout : process is
  begin
    wait for 2 ms;
    if not sim_done then
      report "FAIL tb_bus_matrix_axi4l: simulation timeout" severity failure;
    end if;
    wait;
  end process p_timeout;

  p_stim : process is
    variable rdata    : word_t;
    variable rdata1   : word_t;
    variable err      : std_ulogic;
    variable err1     : std_ulogic;
    variable first_w  : std_ulogic_vector(11 downto 0);
    variable second_w : std_ulogic_vector(11 downto 0);

    -- Start a transfer on master m (returns at once)
    procedure issue (m : natural; we : std_ulogic; addr : word_t; wdata : word_t;
                     strb : std_ulogic_vector(3 downto 0)) is
    begin
      cmd_we(m)    <= we;
      cmd_addr(m)  <= addr;
      cmd_wdata(m) <= wdata;
      cmd_strb(m)  <= strb;
      cmd_req(m)   <= not cmd_req(m);
      wait for 0 ns;
    end procedure issue;

    -- Wait for master m's transfer to finish
    procedure complete (m : natural; rd : out word_t; e : out std_ulogic) is
    begin
      if cmd_ack(m) /= cmd_req(m) then
        wait until cmd_ack(m) = cmd_req(m);
      end if;
      rd := rsp_rdata(m);
      e  := rsp_err(m);
    end procedure complete;

    procedure xfer (m : natural; we : std_ulogic; addr : word_t; wdata : word_t;
                    strb : std_ulogic_vector(3 downto 0); rd : out word_t; e : out std_ulogic) is
    begin
      issue(m, we, addr, wdata, strb);
      complete(m, rd, e);
    end procedure xfer;
  begin
    rst_n <= '0';
    for i in 0 to 7 loop
      wait until rising_edge(clk);
    end loop;
    rst_n <= '1';
    wait until rising_edge(clk);

    -- -----------------------------------------------------------------------
    -- test_reset: every slave reachable from both masters after reset
    -- -----------------------------------------------------------------------
    test_start("test_reset");
    for j in 0 to N_SLV - 1 loop
      xfer(0, '0', slv_addr(j, x"000"), ZERO, x"F", rdata, err);
      check_eq(rdata, ZERO, "M0 read S" & integer'image(j) & " after reset");
      check_eq(flag(err), ZERO, "M0 S" & integer'image(j) & " response OKAY");
      xfer(1, '0', slv_addr(j, x"004"), ZERO, x"F", rdata, err);
      check_eq(rdata, ZERO, "M1 read S" & integer'image(j) & " after reset");
      check_eq(flag(err), ZERO, "M1 S" & integer'image(j) & " response OKAY");
    end loop;
    test_done("test_reset");

    -- -----------------------------------------------------------------------
    -- test_route: every master reaches every slave; no aliasing
    -- -----------------------------------------------------------------------
    test_start("test_route");
    for j in 0 to N_SLV - 1 loop
      xfer(0, '1', slv_addr(j, x"010"), x"A0000010" or tag(j), x"F", rdata, err);
      xfer(1, '1', slv_addr(j, x"020"), x"50000020" or tag(j), x"F", rdata, err);
    end loop;
    for j in 0 to N_SLV - 1 loop
      xfer(1, '0', slv_addr(j, x"010"), ZERO, x"F", rdata, err);
      check_eq(rdata, x"A0000010" or tag(j), "M0 write -> S" & integer'image(j) & " -> M1 read");
      xfer(0, '0', slv_addr(j, x"020"), ZERO, x"F", rdata, err);
      check_eq(rdata, x"50000020" or tag(j), "M1 write -> S" & integer'image(j) & " -> M0 read");
    end loop;
    for j in 0 to N_SLV - 1 loop
      xfer(0, '1', slv_addr(j, x"FFC"), x"C0DE0000" or word(j), x"F", rdata, err);
    end loop;
    for j in 0 to N_SLV - 1 loop
      xfer(1, '0', slv_addr(j, x"FFC"), ZERO, x"F", rdata, err);
      check_eq(rdata, x"C0DE0000" or word(j), "S" & integer'image(j) & " offset 0xFFC");
    end loop;
    test_done("test_route");

    -- -----------------------------------------------------------------------
    -- test_strobe: byte lanes routed independently
    -- -----------------------------------------------------------------------
    test_start("test_strobe");
    xfer(0, '1', slv_addr(1, x"100"), ZERO, x"F", rdata, err);
    xfer(0, '1', slv_addr(1, x"100"), x"111111AA", "0001", rdata, err);
    xfer(1, '1', slv_addr(1, x"100"), x"2222BB22", "0010", rdata, err);
    xfer(0, '1', slv_addr(1, x"100"), x"33CC3333", "0100", rdata, err);
    xfer(1, '1', slv_addr(1, x"100"), x"DD444444", "1000", rdata, err);
    xfer(0, '0', slv_addr(1, x"100"), ZERO, x"F", rdata, err);
    check_eq(rdata, x"DDCCBBAA", "one lane per write, both masters");
    xfer(1, '1', slv_addr(1, x"100"), ZERO, "0000", rdata, err);
    xfer(1, '0', slv_addr(1, x"100"), ZERO, x"F", rdata, err);
    check_eq(rdata, x"DDCCBBAA", "all-zero strobe writes nothing");
    test_done("test_strobe");

    -- -----------------------------------------------------------------------
    -- test_decode_err: unmapped addresses get an error from the matrix
    -- -----------------------------------------------------------------------
    test_start("test_decode_err");
    for k in 0 to 3 loop
      xfer(0, '1', UNMAPPED(k), x"BAD00000" or word(k), x"F", rdata, err);
      check_eq(flag(err), x"00000001", "M0 write 0x" & to_hstring(UNMAPPED(k)) & " -> error");
      xfer(1, '0', UNMAPPED(k), ZERO, x"F", rdata, err);
      check_eq(flag(err), x"00000001", "M1 read  0x" & to_hstring(UNMAPPED(k)) & " -> error");
    end loop;
    xfer(0, '0', UNMAPPED(0), ZERO, x"F", rdata, err);
    xfer(0, '0', UNMAPPED(3), ZERO, x"F", rdata, err);
    check_eq(flag(err), x"00000001", "second consecutive error");
    xfer(0, '1', slv_addr(2, x"040"), x"600D600D", x"F", rdata, err);
    check_eq(flag(err), ZERO, "good write after errors");
    xfer(0, '0', slv_addr(2, x"040"), ZERO, x"F", rdata, err);
    check_eq(rdata, x"600D600D", "good read after errors");
    check_eq(flag(err), ZERO, "good read response OKAY");
    for j in 0 to N_SLV - 1 loop
      xfer(1, '0', slv_addr(j, x"000"), ZERO, x"F", rdata, err);
      check_eq(rdata, ZERO, "S" & integer'image(j) & " untouched by errors");
    end loop;
    test_done("test_decode_err");

    -- -----------------------------------------------------------------------
    -- test_contention: both masters at once, same slave then different slaves
    -- -----------------------------------------------------------------------
    test_start("test_contention");
    for k in 0 to 7 loop
      issue(0, '1', slv_addr(1, off(x"200", k)), x"0A000000" or word(k), x"F");
      issue(1, '1', slv_addr(1, off(x"300", k)), x"0B000000" or word(k), x"F");
      complete(0, rdata, err);
      complete(1, rdata1, err1);
    end loop;
    for k in 0 to 7 loop
      issue(0, '0', slv_addr(1, off(x"300", k)), ZERO, x"F");
      issue(1, '0', slv_addr(1, off(x"200", k)), ZERO, x"F");
      complete(0, rdata, err);
      complete(1, rdata1, err1);
      check_eq(rdata,  x"0B000000" or word(k), "M0 reads M1 word " & integer'image(k));
      check_eq(rdata1, x"0A000000" or word(k), "M1 reads M0 word " & integer'image(k));
    end loop;
    for k in 0 to 3 loop
      issue(0, '1', slv_addr(2, off(x"400", k)), x"0C000000" or word(k), x"F");
      issue(1, '1', slv_addr(3, off(x"400", k)), x"0D000000" or word(k), x"F");
      complete(0, rdata, err);
      complete(1, rdata1, err1);
    end loop;
    for k in 0 to 3 loop
      xfer(1, '0', slv_addr(2, off(x"400", k)), ZERO, x"F", rdata, err);
      check_eq(rdata, x"0C000000" or word(k), "S2 word " & integer'image(k));
      xfer(0, '0', slv_addr(3, off(x"400", k)), ZERO, x"F", rdata, err);
      check_eq(rdata, x"0D000000" or word(k), "S3 word " & integer'image(k));
    end loop;
    test_done("test_contention");

    -- -----------------------------------------------------------------------
    -- test_arb: round robin, the master not served last on S1 wins a tie
    -- -----------------------------------------------------------------------
    test_start("test_arb");
    for run in 0 to 3 loop
      if run < 2 then
        xfer(0, '1', slv_addr(1, x"700"), x"00000700", x"F", rdata, err);
        first_w  := x"180";  -- M1 (0x600 >> 2)
        second_w := x"140";  -- M0 (0x500 >> 2)
      else
        xfer(1, '1', slv_addr(1, x"700"), x"00000700", x"F", rdata, err);
        first_w  := x"140";
        second_w := x"180";
      end if;
      wait until rising_edge(clk);
      log_clear <= '1';
      wait for 1 ns;
      log_clear <= '0';
      if run mod 2 = 0 then
        issue(0, '1', slv_addr(1, x"500"), x"00000500", x"F");
        issue(1, '1', slv_addr(1, x"600"), x"00000600", x"F");
      else
        issue(1, '1', slv_addr(1, x"600"), x"00000600", x"F");
        issue(0, '1', slv_addr(1, x"500"), x"00000500", x"F");
      end if;
      complete(0, rdata, err);
      complete(1, rdata1, err1);
      wait until rising_edge(clk);
      wait for 1 ns;
      check_eq(std_ulogic_vector(to_unsigned(s1_wr_count, 32)), x"00000002",
               "run " & integer'image(run) & ": two writes");
      check_eq(std_ulogic_vector(resize(unsigned(s1_wr_log0), 32)),
               std_ulogic_vector(resize(unsigned(first_w), 32)),
               "run " & integer'image(run) & ": winner first");
      check_eq(std_ulogic_vector(resize(unsigned(s1_wr_log1), 32)),
               std_ulogic_vector(resize(unsigned(second_w), 32)),
               "run " & integer'image(run) & ": other second");
    end loop;
    test_done("test_arb");

    sim_done <= true;
    report "PASS tb_bus_matrix_axi4l: all tests passed" severity note;
    stop;
    wait;
  end process p_stim;

end architecture sim;
