-- mst_if_stim.vhd — Protocol-neutral initiator and tests for the master-adapter VHDL benches.
--
-- VHDL-2008, simulation only. The VHDL counterpart of mst_if_tests.sv, used by every
-- tb_claude_<proto>_mst_if.vhd so the VHDL adapters can be simulated on GHDL with no SV.
-- It drives the DUT's mem_* port as an initiator (rules 1, 2, 6-9 of
-- .agents/IP_SPEC_mem_bus_initiator.md), checks the DUT's target behaviour (rules 3-5),
-- keeps a reference memory, and runs the same tests as the SV benches:
--   latency / throughput, basic words, every size on every lane, sparse write strobes,
--   all mem_prot values, the error region, reset during a transfer, and constrained-random
--   traffic; first with a zero-wait memory, then with random delays and back-pressure.
--
-- It owns rst_n and the memory / throttle knobs (max_gnt, max_rsp, throttle). When the
-- tests end it raises done with n_fail = test failures + mem_* rule violations + accounting
-- errors; the testbench adds its bus-monitor errors and prints the PASS / FAIL line.
--
-- SPARSE_WR_OK = 0: non-aligned write patterns must be answered with mem_err and no bus
-- access (AHB-Lite with HAS_HWSTRB = 0, rule 8).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mst_if_stim is
  generic (
    DATA_W       : positive := 32;
    ADDR_W       : positive := 32;
    SPARSE_WR_OK : natural  := 1;
    LAT_EXP      : natural  := 3;    -- zero-wait latency (rising edges, handshake to rvalid)
    PERIOD_EXP   : natural  := 4;    -- zero-wait period between back-to-back handshakes
    N_RANDOM     : natural  := 500;
    CLK_PERIOD   : time     := 10 ns;
    SEED         : natural  := 3
  );
  port (
    clk        : in  std_ulogic;
    rst_n      : out std_ulogic;
    mem_req    : out std_ulogic;
    mem_gnt    : in  std_ulogic;
    mem_we     : out std_ulogic;
    mem_addr   : out std_ulogic_vector(ADDR_W - 1 downto 0);
    mem_be     : out std_ulogic_vector(DATA_W / 8 - 1 downto 0);
    mem_wdata  : out std_ulogic_vector(DATA_W - 1 downto 0);
    mem_prot   : out std_ulogic_vector(2 downto 0);
    mem_rvalid : in  std_ulogic;
    mem_rdata  : in  std_ulogic_vector(DATA_W - 1 downto 0);
    mem_err    : in  std_ulogic;
    max_gnt    : out natural;        -- to the memory model
    max_rsp    : out natural;
    throttle   : out natural;        -- to the testbench's bus throttle
    done       : out std_ulogic;
    n_fail     : out natural
  );
end entity mst_if_stim;

architecture sim of mst_if_stim is

  constant STRB_W    : positive := DATA_W / 8;

  function clog2(n : positive) return natural is
  begin
    for i in 0 to 30 loop
      if 2 ** i >= n then
        return i;
      end if;
    end loop;
    return 31;
  end function;

  constant OFF_W     : natural  := clog2(STRB_W);
  constant MAX_SIZE  : natural  := clog2(STRB_W);
  constant REF_WORDS : positive := 1024;
  constant IDX_W     : natural  := 10;

  -- Naturally aligned power-of-two block of byte lanes?
  function is_aligned(be : std_ulogic_vector) return boolean is
    variable lo  : natural := be'length;
    variable n   : natural := 0;
    variable gap : boolean := false;
    variable ok  : boolean := true;
  begin
    for b in 0 to be'length - 1 loop
      if be(be'low + b) = '1' then
        if lo = be'length then
          lo := b;
        end if;
        if gap then
          ok := false;
        end if;
        n := n + 1;
      elsif lo /= be'length then
        gap := true;
      end if;
    end loop;
    if n = 0 then
      return false;
    end if;
    return ok and 2 ** clog2(n) = n and (lo mod n) = 0;
  end function;

  signal rst_n_i    : std_ulogic := '0';
  signal pending    : boolean := false;
  signal n_accepted : natural := 0;
  signal n_resp     : natural := 0;
  signal n_aborted  : natural := 0;
  signal n_viol     : natural := 0;
  signal last_hs_t  : time := 0 ns;
  signal prev_hs_t  : time := 0 ns;

begin

  rst_n <= rst_n_i;

  -- Target-rule checks on the DUT's mem_* port and accounting.
  p_rules : process (clk) is
    variable acc, rsp, abt, vio : natural := 0;
  begin
    if rising_edge(clk) then
      if rst_n_i = '0' then
        if pending then
          abt := abt + 1;
        end if;
        pending <= false;
        if mem_gnt = '1' then
          report "ERROR [mst_if] mem_gnt high during reset" severity error;
          vio := vio + 1;
        end if;
      else
        if mem_rvalid = '1' then
          rsp := rsp + 1;
          if not pending then
            report "ERROR [mst_if] mem_rvalid without an outstanding request" severity error;
            vio := vio + 1;
          end if;
        end if;
        if mem_req = '1' and mem_gnt = '1' then
          acc := acc + 1;
          if pending and mem_rvalid = '0' then
            report "ERROR [mst_if] request accepted while one is outstanding" severity error;
            vio := vio + 1;
          end if;
          prev_hs_t <= last_hs_t;
          last_hs_t <= now;
          pending   <= true;
        elsif mem_rvalid = '1' then
          pending <= false;
        end if;
      end if;
      n_accepted <= acc;
      n_resp     <= rsp;
      n_aborted  <= abt;
      n_viol     <= vio;
    end if;
  end process p_rules;

  p_stim : process is
    type ref_t is array (0 to REF_WORDS - 1) of std_ulogic_vector(DATA_W - 1 downto 0);
    variable ref_mem  : ref_t := (others => (others => '0'));
    variable x        : unsigned(31 downto 0) := to_unsigned(SEED + 1, 32);
    variable fails    : natural := 0;
    variable max_idle : natural := 0;
    variable lat      : natural;
    variable rd       : std_ulogic_vector(DATA_W - 1 downto 0);
    variable err      : std_ulogic;

    impure function rnd(lo, hi : natural) return natural is
    begin
      x := x xor shift_left(x, 13);
      x := x xor shift_right(x, 17);
      x := x xor shift_left(x, 5);
      if hi <= lo then
        return lo;
      end if;
      return lo + to_integer(x mod to_unsigned(hi - lo + 1, 32));
    end function;

    impure function rand_data return std_ulogic_vector is
      variable d : std_ulogic_vector(DATA_W - 1 downto 0);
    begin
      for b in 0 to STRB_W - 1 loop
        d(8 * b + 7 downto 8 * b) := std_ulogic_vector(to_unsigned(rnd(0, 255), 8));
      end loop;
      return d;
    end function;

    function ref_index(a : std_ulogic_vector) return natural is
    begin
      return to_integer(unsigned(a(OFF_W + IDX_W - 1 downto OFF_W)));
    end function;

    function word_addr(i : natural) return std_ulogic_vector is
      variable a : std_ulogic_vector(ADDR_W - 1 downto 0) := (others => '0');
    begin
      a(OFF_W + IDX_W - 1 downto OFF_W) := std_ulogic_vector(to_unsigned(i mod REF_WORDS, IDX_W));
      return a;
    end function;

    function plus(a : std_ulogic_vector; off : natural) return std_ulogic_vector is
    begin
      return std_ulogic_vector(unsigned(a) + off);
    end function;

    function err_addr(a : std_ulogic_vector) return std_ulogic_vector is
      variable r : std_ulogic_vector(a'range) := a;
    begin
      r(ADDR_W - 1) := '1';
      return r;
    end function;

    function lanes(size, off : natural) return std_ulogic_vector is
      variable be : std_ulogic_vector(STRB_W - 1 downto 0) := (others => '0');
    begin
      for b in 0 to 2 ** size - 1 loop
        be(off + b) := '1';
      end loop;
      return be;
    end function;

    function bus_legal(we : std_ulogic; be : std_ulogic_vector) return boolean is
    begin
      return SPARSE_WR_OK /= 0 or we = '0' or is_aligned(be);
    end function;

    procedure fail(msg : string) is
    begin
      report "FAIL [mst_if] " & msg severity error;
      fails := fails + 1;
    end procedure;

    procedure bus_idle is
    begin
      mem_req   <= '0';
      mem_we    <= '0';
      mem_addr  <= (others => '0');
      mem_be    <= (others => '0');
      mem_wdata <= (others => '0');
      mem_prot  <= "000";
    end procedure;

    -- One transfer; lat = rising edges from the handshake edge to the rvalid edge.
    procedure xfer(we : std_ulogic; addr, be, wdata : std_ulogic_vector;
                   prot : std_ulogic_vector(2 downto 0)) is
      variable guard : natural;
    begin
      for i in 1 to rnd(0, max_idle) loop
        wait until falling_edge(clk);
      end loop;
      wait until falling_edge(clk);
      mem_req  <= '1';
      mem_we   <= we;
      mem_addr <= addr;
      mem_be   <= be;
      if we = '1' then
        mem_wdata <= wdata;
      else
        mem_wdata <= (others => 'X');
      end if;
      mem_prot <= prot;
      guard := 0;
      loop
        wait until rising_edge(clk);
        guard := guard + 1;
        exit when mem_gnt = '1' or guard = 1000;
      end loop;
      if mem_gnt /= '1' then
        fail("no grant within 1000 cycles");
      end if;
      wait until falling_edge(clk);
      bus_idle;
      lat := 0;
      loop
        wait until rising_edge(clk);
        lat := lat + 1;
        exit when mem_rvalid = '1' or lat = 1000;
      end loop;
      if mem_rvalid /= '1' then
        fail("no response within 1000 cycles");
      end if;
      rd  := mem_rdata;
      err := mem_err;
    end procedure;

    procedure do_write(addr, be, data : std_ulogic_vector; prot : std_ulogic_vector(2 downto 0);
                       expect_err : boolean) is
      variable e : boolean := expect_err or not bus_legal('1', be);
    begin
      xfer('1', addr, be, data, prot);
      if (err = '1') /= e then
        fail("write 0x" & to_hstring(addr) & " be " & to_string(be) & ": err " & to_string(err));
      end if;
      if not e then
        for b in 0 to STRB_W - 1 loop
          if be(b) = '1' then
            ref_mem(ref_index(addr))(8 * b + 7 downto 8 * b) := data(8 * b + 7 downto 8 * b);
          end if;
        end loop;
      end if;
    end procedure;

    procedure do_read(addr, be : std_ulogic_vector; prot : std_ulogic_vector(2 downto 0);
                      expect_err : boolean) is
      variable zero : std_ulogic_vector(DATA_W - 1 downto 0) := (others => '0');
    begin
      xfer('0', addr, be, zero, prot);
      if (err = '1') /= expect_err then
        fail("read 0x" & to_hstring(addr) & ": err " & to_string(err));
      end if;
      if not expect_err then
        for b in 0 to STRB_W - 1 loop
          if be(b) = '1' and rd(8 * b + 7 downto 8 * b) /= ref_mem(ref_index(addr))(8 * b + 7 downto 8 * b) then
            fail("read 0x" & to_hstring(addr) & " lane " & integer'image(b) & ": 0x" &
                 to_hstring(rd(8 * b + 7 downto 8 * b)) & ", expected 0x" &
                 to_hstring(ref_mem(ref_index(addr))(8 * b + 7 downto 8 * b)));
          end if;
        end loop;
      end if;
    end procedure;

    constant ALL1 : std_ulogic_vector(STRB_W - 1 downto 0) := (others => '1');
    constant P0   : std_ulogic_vector(2 downto 0) := "000";

    procedure test_basic_rw is
    begin
      do_write(word_addr(0), ALL1, rand_data, P0, false);
      do_write(word_addr(REF_WORDS / 2), ALL1, rand_data, P0, false);
      do_write(word_addr(REF_WORDS - 1), ALL1, rand_data, P0, false);
      do_read(word_addr(0), ALL1, P0, false);
      do_read(word_addr(REF_WORDS / 2), ALL1, P0, false);
      do_read(word_addr(REF_WORDS - 1), ALL1, P0, false);
    end procedure;

    procedure test_sizes_lanes is
      variable off : natural;
    begin
      for size in 0 to MAX_SIZE loop
        off := 0;
        while off < STRB_W loop
          do_write(plus(word_addr(16 + size), off), lanes(size, off), rand_data, P0, false);
          do_read(plus(word_addr(16 + size), off), lanes(size, off), P0, false);
          off := off + 2 ** size;
        end loop;
        do_read(word_addr(16 + size), ALL1, P0, false);
      end loop;
    end procedure;

    procedure test_sparse_strobes is
      variable be  : std_ulogic_vector(STRB_W - 1 downto 0);
      variable low : natural;
    begin
      if STRB_W >= 2 then
        do_write(word_addr(40), ALL1, std_ulogic_vector(to_unsigned(0, DATA_W)), P0, false);
        for p in 1 to 2 ** STRB_W - 1 loop
          be := std_ulogic_vector(to_unsigned(p, STRB_W));
          low := 0;
          for b in STRB_W - 1 downto 0 loop
            if be(b) = '1' then
              low := b;
            end if;
          end loop;
          do_write(plus(word_addr(40), low), be, rand_data, P0, false);
          do_read(word_addr(40), ALL1, P0, false);
        end loop;
      end if;
    end procedure;

    procedure test_prot is
    begin
      for p in 0 to 7 loop
        do_write(word_addr(60), ALL1, rand_data, std_ulogic_vector(to_unsigned(p, 3)), false);
        do_read(word_addr(60), ALL1, std_ulogic_vector(to_unsigned(p, 3)), false);
      end loop;
    end procedure;

    procedure test_error is
    begin
      do_write(word_addr(70), ALL1, rand_data, P0, false);
      do_write(err_addr(word_addr(70)), ALL1, rand_data, P0, true);
      do_read(err_addr(word_addr(70)), ALL1, P0, true);
      do_read(word_addr(70), ALL1, P0, false);
    end procedure;

    procedure test_latency is
      variable wd : std_ulogic_vector(DATA_W - 1 downto 0);
    begin
      wd := rand_data;
      xfer('1', word_addr(80), ALL1, wd, P0);
      ref_mem(ref_index(word_addr(80))) := wd;
      if lat /= LAT_EXP then
        fail("write latency " & integer'image(lat) & " cycles, expected " & integer'image(LAT_EXP));
      end if;
      xfer('0', word_addr(80), ALL1, wd, P0);
      if lat /= LAT_EXP then
        fail("read latency " & integer'image(lat) & " cycles, expected " & integer'image(LAT_EXP));
      end if;
      xfer('0', word_addr(80), ALL1, wd, P0);
      xfer('0', word_addr(80), ALL1, wd, P0);
      if last_hs_t - prev_hs_t /= PERIOD_EXP * CLK_PERIOD then
        fail("back-to-back handshakes " & time'image(last_hs_t - prev_hs_t) & " apart, expected " &
             integer'image(PERIOD_EXP) & " cycles");
      end if;
      do_read(word_addr(80), ALL1, P0, false);
    end procedure;

    procedure test_random(n : natural) is
      variable a    : std_ulogic_vector(ADDR_W - 1 downto 0);
      variable be   : std_ulogic_vector(STRB_W - 1 downto 0);
      variable size : natural;
      variable off  : natural;
      variable is_e : boolean;
      variable prot : std_ulogic_vector(2 downto 0);
    begin
      for i in 1 to n loop
        is_e := rnd(0, 19) = 0;
        prot := std_ulogic_vector(to_unsigned(rnd(0, 7), 3));
        if rnd(0, 1) = 1 then                       -- write
          if STRB_W > 1 and rnd(0, 3) = 0 then      -- sparse pattern
            be := std_ulogic_vector(to_unsigned(rnd(1, 2 ** STRB_W - 1), STRB_W));
            off := 0;
            for b in STRB_W - 1 downto 0 loop
              if be(b) = '1' then
                off := b;
              end if;
            end loop;
          else
            size := rnd(0, MAX_SIZE);
            off  := rnd(0, STRB_W / 2 ** size - 1) * 2 ** size;
            be   := lanes(size, off);
          end if;
          a := plus(word_addr(rnd(0, REF_WORDS - 1)), off);
          if is_e then
            a := err_addr(a);
          end if;
          do_write(a, be, rand_data, prot, is_e);
        else                                        -- read
          size := rnd(0, MAX_SIZE);
          off  := rnd(0, STRB_W / 2 ** size - 1) * 2 ** size;
          a    := plus(word_addr(rnd(0, REF_WORDS - 1)), off);
          if is_e then
            a := err_addr(a);
          end if;
          do_read(a, lanes(size, off), prot, is_e);
        end if;
      end loop;
    end procedure;

    procedure test_reset_mid_transfer is
    begin
      wait until falling_edge(clk);
      mem_req   <= '1';
      mem_we    <= '1';
      mem_addr  <= word_addr(90);
      mem_be    <= ALL1;
      mem_wdata <= rand_data;
      mem_prot  <= P0;
      loop
        wait until rising_edge(clk);
        exit when mem_gnt = '1';
      end loop;
      wait until falling_edge(clk);
      bus_idle;
      wait until falling_edge(clk);
      rst_n_i <= '0';
      for i in 1 to 3 loop
        wait until falling_edge(clk);
      end loop;
      rst_n_i <= '1';
      for i in 1 to 2 loop
        wait until falling_edge(clk);
      end loop;
      do_write(word_addr(90), ALL1, rand_data, P0, false);
      do_read(word_addr(90), ALL1, P0, false);
    end procedure;

    procedure run_all(title : string) is
    begin
      report "[mst_if] --- " & title & " ---" severity note;
      test_basic_rw;
      test_sizes_lanes;
      test_sparse_strobes;
      test_prot;
      test_error;
      test_random(N_RANDOM);
    end procedure;

  begin
    bus_idle;
    max_gnt  <= 0;
    max_rsp  <= 0;
    throttle <= 0;
    done     <= '0';
    n_fail   <= 0;
    rst_n_i  <= '0';
    for i in 1 to 5 loop
      wait until falling_edge(clk);
    end loop;
    rst_n_i <= '1';
    for i in 1 to 2 loop
      wait until falling_edge(clk);
    end loop;

    -- Zero-wait memory, no idle cycles, no back-pressure.
    max_idle := 0;
    test_latency;
    run_all("zero wait");
    test_reset_mid_transfer;

    -- Random memory delays, idle cycles and bus back-pressure.
    max_gnt  <= 3;
    max_rsp  <= 4;
    throttle <= 3;
    max_idle := 3;
    run_all("random delays and back-pressure");

    for i in 1 to 5 loop
      wait until falling_edge(clk);
    end loop;
    if n_accepted /= n_resp + n_aborted then
      fail(integer'image(n_accepted) & " requests accepted, " & integer'image(n_resp) &
           " responses, " & integer'image(n_aborted) & " aborted by reset");
    end if;
    report "[mst_if] requests " & integer'image(n_accepted) & ", responses " &
           integer'image(n_resp) & ", mem_* violations " & integer'image(n_viol) severity note;
    n_fail <= fails + n_viol;
    done   <= '1';
    wait;
  end process p_stim;

end architecture sim;
