-- tb_claude_ahb_mst_if.vhd — Pure-VHDL loopback testbench for claude_ahb_mst_if (GHDL).
--
--   mst_if_stim ─ mem_* ─► claude_ahb_mst_if (DUT) ─ AHB-Lite ─► claude_ahb_mem_if
--                                                  ─ mem_* ─► claude_mem_model
--
-- VHDL twin of tb_claude_ahb_mst_if.sv. The monitor checks: HTRANS only IDLE / NONSEQ and
-- no new transfer during a data phase, HBURST SINGLE, HMASTLOCK 0, legal HSIZE / alignment,
-- the address phase held while HREADY is low, HWDATA / HWSTRB held through data-phase wait
-- states, HTRANS IDLE in reset; end to end: HADDR / HSIZE, HWRITE, HPROT, HNONSEC, HWSTRB and
-- HWDATA. The bus-wide HREADY is held low at random outside the DUT's own data phase, so the
-- address-phase hold rule is exercised. The signed-off slave adapter adds one wait state per
-- beat: latency 4, period 5.
--
-- Generics: DATA_W (8, 16 or 32), ADDR_W (32), HAS_HWSTRB, HAS_HNONSEC (0 / 1).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_claude_ahb_mst_if is
  generic (
    DATA_W      : positive := 32;
    ADDR_W      : positive := 32;
    HAS_HWSTRB  : natural  := 1;
    HAS_HNONSEC : natural  := 1
  );
end entity tb_claude_ahb_mst_if;

architecture sim of tb_claude_ahb_mst_if is

  constant STRB_W     : positive := DATA_W / 8;
  constant CLK_PERIOD : time     := 10 ns;

  function clog2(n : positive) return natural is
  begin
    for i in 0 to 30 loop
      if 2 ** i >= n then
        return i;
      end if;
    end loop;
    return 31;
  end function;

  function is_aligned(be : std_ulogic_vector) return boolean is
    variable lo  : natural := be'length;
    variable n   : natural := 0;
    variable gap : boolean := false;
    variable ok  : boolean := true;
  begin
    for b in 0 to be'length - 1 loop
      if be(be'low + b) = '1' then
        if lo = be'length then lo := b; end if;
        if gap then ok := false; end if;
        n := n + 1;
      elsif lo /= be'length then
        gap := true;
      end if;
    end loop;
    if n = 0 then return false; end if;
    return ok and 2 ** clog2(n) = n and (lo mod n) = 0;
  end function;

  function popcount(v : std_ulogic_vector) return natural is
    variable n : natural := 0;
  begin
    for i in v'range loop
      if v(i) = '1' then n := n + 1; end if;
    end loop;
    return n;
  end function;

  constant TR_IDLE : std_ulogic_vector(1 downto 0) := "00";
  constant TR_NSEQ : std_ulogic_vector(1 downto 0) := "10";

  signal clk   : std_ulogic := '0';
  signal rst_n : std_ulogic;

  signal mem_req, mem_gnt, mem_we, mem_rvalid, mem_err : std_ulogic;
  signal mem_addr  : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal mem_be    : std_ulogic_vector(STRB_W - 1 downto 0);
  signal mem_wdata : std_ulogic_vector(DATA_W - 1 downto 0);
  signal mem_rdata : std_ulogic_vector(DATA_W - 1 downto 0);
  signal mem_prot  : std_ulogic_vector(2 downto 0);

  signal HADDR   : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal HTRANS  : std_ulogic_vector(1 downto 0);
  signal HWRITE, HMASTLOCK, HNONSEC, HREADYOUT, HREADY, HRESP : std_ulogic;
  signal HSIZE, HBURST : std_ulogic_vector(2 downto 0);
  signal HPROT   : std_ulogic_vector(3 downto 0);
  signal HWDATA  : std_ulogic_vector(DATA_W - 1 downto 0);
  signal HRDATA  : std_ulogic_vector(DATA_W - 1 downto 0);
  signal HWSTRB  : std_ulogic_vector(STRB_W - 1 downto 0);

  signal t_req, t_gnt, t_we, t_rvalid, t_err : std_ulogic;
  signal t_addr  : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal t_be    : std_ulogic_vector(STRB_W - 1 downto 0);
  signal t_wdata : std_ulogic_vector(DATA_W - 1 downto 0);
  signal t_rdata : std_ulogic_vector(DATA_W - 1 downto 0);

  signal max_gnt, max_rsp, throttle, n_fail, tgt_errors : natural;
  signal done       : std_ulogic;
  signal bus_errors : natural := 0;
  signal bus_xfers  : natural := 0;
  signal dp_active  : std_ulogic := '0';   -- a data phase is in progress (monitor)
  signal hr_allow   : std_ulogic := '1';

begin

  clk <= not clk after CLK_PERIOD / 2;

  u_stim : entity work.mst_if_stim
    generic map (DATA_W => DATA_W, ADDR_W => ADDR_W, SPARSE_WR_OK => HAS_HWSTRB,
                 LAT_EXP => 4, PERIOD_EXP => 5, CLK_PERIOD => CLK_PERIOD, SEED => 11)
    port map (clk => clk, rst_n => rst_n, mem_req => mem_req, mem_gnt => mem_gnt,
              mem_we => mem_we, mem_addr => mem_addr, mem_be => mem_be, mem_wdata => mem_wdata,
              mem_prot => mem_prot, mem_rvalid => mem_rvalid, mem_rdata => mem_rdata,
              mem_err => mem_err, max_gnt => max_gnt, max_rsp => max_rsp, throttle => throttle,
              done => done, n_fail => n_fail);

  u_dut : entity work.claude_ahb_mst_if
    generic map (DATA_W => DATA_W, ADDR_W => ADDR_W, HAS_HWSTRB => HAS_HWSTRB,
                 HAS_HNONSEC => HAS_HNONSEC)
    port map (HCLK => clk, HRESETn => rst_n, HADDR => HADDR, HTRANS => HTRANS, HWRITE => HWRITE,
              HSIZE => HSIZE, HBURST => HBURST, HPROT => HPROT, HMASTLOCK => HMASTLOCK,
              HNONSEC => HNONSEC, HWDATA => HWDATA, HWSTRB => HWSTRB, HRDATA => HRDATA,
              HREADY => HREADY, HRESP => HRESP,
              mem_req_i => mem_req, mem_gnt_o => mem_gnt, mem_we_i => mem_we,
              mem_addr_i => mem_addr, mem_be_i => mem_be, mem_wdata_i => mem_wdata,
              mem_prot_i => mem_prot, mem_rvalid_o => mem_rvalid, mem_rdata_o => mem_rdata,
              mem_err_o => mem_err);

  u_slv : entity work.claude_ahb_mem_if
    generic map (DATA_W => DATA_W, ADDR_W => ADDR_W)
    port map (HCLK => clk, HRESETn => rst_n, HSEL => '1', HADDR => HADDR, HTRANS => HTRANS,
              HWRITE => HWRITE, HSIZE => HSIZE, HWDATA => HWDATA, HWSTRB => HWSTRB,
              HREADY => HREADY, HRDATA => HRDATA, HREADYOUT => HREADYOUT, HRESP => HRESP,
              mem_req_o => t_req, mem_gnt_i => t_gnt, mem_we_o => t_we, mem_addr_o => t_addr,
              mem_be_o => t_be, mem_wdata_o => t_wdata, mem_rvalid_i => t_rvalid,
              mem_rdata_i => t_rdata, mem_err_i => t_err);

  u_tgt : entity work.claude_mem_model
    generic map (DATA_W => DATA_W, ADDR_W => ADDR_W, SIZE => 1024 * STRB_W, ERR_MSB => 1, SEED => 11)
    port map (clk => clk, rst_n => rst_n, mem_req => t_req, mem_gnt => t_gnt, mem_we => t_we,
              mem_addr => t_addr, mem_be => t_be, mem_wdata => t_wdata, mem_rvalid => t_rvalid,
              mem_rdata => t_rdata, mem_err => t_err, max_gnt => max_gnt, max_rsp => max_rsp,
              proto_errors => tgt_errors);

  -- HREADY throttle: low at random outside the DUT's own data phase.
  p_throttle : process (clk) is
    variable x : unsigned(31 downto 0) := to_unsigned(99, 32);
  begin
    if rising_edge(clk) then
      x := x xor shift_left(x, 13);
      x := x xor shift_right(x, 17);
      x := x xor shift_left(x, 5);
      if throttle = 0 or to_integer(x mod to_unsigned(throttle + 1, 32)) = 0 then
        hr_allow <= '1';
      else
        hr_allow <= '0';
      end if;
    end if;
  end process p_throttle;

  HREADY <= HREADYOUT and (dp_active or hr_allow);

  -- AHB-Lite master-rule monitor and end-to-end check.
  p_mon : process (clk) is
    constant DEPTH : positive := 16;
    type addr_a is array (0 to DEPTH - 1) of std_ulogic_vector(ADDR_W - 1 downto 0);
    type data_a is array (0 to DEPTH - 1) of std_ulogic_vector(DATA_W - 1 downto 0);
    type be_a   is array (0 to DEPTH - 1) of std_ulogic_vector(STRB_W - 1 downto 0);
    type prot_a is array (0 to DEPTH - 1) of std_ulogic_vector(2 downto 0);
    type bit_a  is array (0 to DEPTH - 1) of std_ulogic;
    variable q_we : bit_a;
    variable q_addr : addr_a;
    variable q_data : data_a;
    variable q_be : be_a;
    variable q_prot : prot_a;
    variable wr_p, rd_p : natural := 0;
    variable started, completed, aborted, errs : natural := 0;
    variable seen : boolean := false;
    variable dp : boolean := false;                -- data phase in progress
    variable dp_first : boolean := false;
    variable dp_we : std_ulogic;
    variable dp_be : std_ulogic_vector(STRB_W - 1 downto 0);
    variable dp_wdata, dp_hwdata : std_ulogic_vector(DATA_W - 1 downto 0);
    variable dp_hwstrb : std_ulogic_vector(STRB_W - 1 downto 0);
    variable p_nseq, p_hready, p_hwrite : std_ulogic := '0';
    variable p_haddr : std_ulogic_vector(ADDR_W - 1 downto 0);
    variable p_hsize : std_ulogic_vector(2 downto 0);
    variable p_hprot : std_ulogic_vector(3 downto 0);
    variable k : natural;
    variable e_addr : std_ulogic_vector(ADDR_W - 1 downto 0);
    variable e_size : natural;
    variable e_prot : std_ulogic_vector(3 downto 0);
    variable e_strb : std_ulogic_vector(STRB_W - 1 downto 0);
    variable e_nsec : std_ulogic;

    procedure bad(msg : string) is
    begin
      report "ERROR [ahb mon] " & msg severity error;
      errs := errs + 1;
    end procedure;
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        if not seen and HTRANS /= TR_IDLE and now > 3 * CLK_PERIOD then
          bad("HTRANS not IDLE in reset");
        end if;
        if dp then aborted := aborted + 1; end if;
        dp := false;
        rd_p := wr_p;
        seen := false;
        p_nseq := '0';
      else
        if mem_req = '1' and mem_gnt = '1' and
           (HAS_HWSTRB /= 0 or mem_we = '0' or is_aligned(mem_be)) then
          q_we(wr_p mod DEPTH)   := mem_we;
          q_addr(wr_p mod DEPTH) := mem_addr;
          q_data(wr_p mod DEPTH) := mem_wdata;
          q_be(wr_p mod DEPTH)   := mem_be;
          q_prot(wr_p mod DEPTH) := mem_prot;
          wr_p := wr_p + 1;
        end if;
        if HTRANS /= TR_IDLE and HTRANS /= TR_NSEQ then bad("HTRANS not IDLE / NONSEQ"); end if;
        if HBURST /= "000" then bad("HBURST not SINGLE"); end if;
        if HMASTLOCK /= '0' then bad("HMASTLOCK high"); end if;

        -- address phase held while HREADY is low
        if seen and p_nseq = '1' and p_hready = '0' and
           not (HTRANS = TR_NSEQ and HADDR = p_haddr and HWRITE = p_hwrite and
                HSIZE = p_hsize and HPROT = p_hprot) then
          bad("address phase dropped or changed while HREADY was low");
        end if;

        -- data phase
        if dp then
          if HTRANS = TR_NSEQ then bad("new transfer during a data phase"); end if;
          if dp_first then
            dp_hwdata := HWDATA;
            dp_hwstrb := HWSTRB;
          elsif HWDATA /= dp_hwdata or HWSTRB /= dp_hwstrb then
            bad("HWDATA / HWSTRB changed during a data-phase wait state");
          end if;
          dp_first := false;
          if HREADY = '1' then
            completed := completed + 1;
            dp := false;
            if dp_we = '1' then
              if HAS_HWSTRB /= 0 then e_strb := dp_be; else e_strb := (others => '1'); end if;
              if HWSTRB /= e_strb then
                bad("HWSTRB " & to_string(HWSTRB) & ", expected " & to_string(e_strb));
              end if;
              for b in 0 to STRB_W - 1 loop
                if dp_be(b) = '1' and HWDATA(8 * b + 7 downto 8 * b) /= dp_wdata(8 * b + 7 downto 8 * b) then
                  bad("HWDATA lane " & integer'image(b) & " differs from mem_wdata");
                end if;
              end loop;
            elsif HAS_HWSTRB /= 0 and unsigned(HWSTRB) /= 0 then
              bad("HWSTRB not zero on a read");
            end if;
          end if;
        end if;

        -- address phase
        if HTRANS = TR_NSEQ then
          if 2 ** to_integer(unsigned(HSIZE)) > STRB_W then bad("HSIZE wider than the bus"); end if;
          if to_integer(unsigned(HADDR(2 downto 0))) mod 2 ** to_integer(unsigned(HSIZE)) /= 0 then
            bad("HADDR not aligned to HSIZE");
          end if;
          if HREADY = '1' and not dp then
            if rd_p = wr_p then
              bad("bus transfer without an accepted request");
            else
              k := rd_p mod DEPTH;
              if is_aligned(q_be(k)) then
                e_addr := q_addr(k);
                e_size := clog2(popcount(q_be(k)));
              else
                e_addr := std_ulogic_vector(unsigned(q_addr(k)) and not to_unsigned(STRB_W - 1, ADDR_W));
                e_size := clog2(STRB_W);
              end if;
              e_prot := "00" & q_prot(k)(0) & (not q_prot(k)(2));
              if HAS_HNONSEC /= 0 then e_nsec := q_prot(k)(1); else e_nsec := '0'; end if;
              if HWRITE /= q_we(k) or HADDR /= e_addr or to_integer(unsigned(HSIZE)) /= e_size then
                bad("address phase " & to_string(HWRITE) & " 0x" & to_hstring(HADDR) & " size " &
                    to_hstring(HSIZE) & ", expected " & to_string(q_we(k)) & " 0x" &
                    to_hstring(e_addr) & " size " & integer'image(e_size));
              end if;
              if HPROT /= e_prot then bad("HPROT " & to_string(HPROT) & ", expected " & to_string(e_prot)); end if;
              if HNONSEC /= e_nsec then bad("HNONSEC wrong"); end if;
              dp       := true;
              dp_first := true;
              dp_we    := q_we(k);
              dp_be    := q_be(k);
              dp_wdata := q_data(k);
              rd_p     := rd_p + 1;
              started  := started + 1;
            end if;
          end if;
        end if;
        seen := true;
        if HTRANS = TR_NSEQ and not dp then p_nseq := '1'; else p_nseq := '0'; end if;
      end if;
      p_hready := HREADY; p_haddr := HADDR; p_hwrite := HWRITE; p_hsize := HSIZE; p_hprot := HPROT;
      if done = '1' then
        if rd_p /= wr_p then
          bad(integer'image(wr_p - rd_p) & " accepted requests never appeared on the bus");
          rd_p := wr_p;
        end if;
        if completed + aborted /= started then
          bad(integer'image(started) & " transfers started, " & integer'image(completed) &
              " completed, " & integer'image(aborted) & " aborted");
          completed := started - aborted;
        end if;
      end if;
      if dp then dp_active <= '1'; else dp_active <= '0'; end if;
      bus_errors <= errs;
      bus_xfers  <= completed;
    end if;
  end process p_mon;

  p_end : process is
  begin
    wait until done = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    report "[mst_if] bus transfers " & integer'image(bus_xfers) severity note;
    if n_fail = 0 and bus_errors = 0 and tgt_errors = 0 then
      report "PASS tb_claude_ahb_mst_if" severity note;
    else
      report "FAIL tb_claude_ahb_mst_if: " & integer'image(n_fail) & " test / mem_* failures, " &
             integer'image(bus_errors) & " bus violations, " & integer'image(tgt_errors) &
             " memory-model violations" severity error;
    end if;
    finish;
  end process p_end;

  p_timeout : process is
  begin
    wait for 5 ms;
    report "FAIL tb_claude_ahb_mst_if: timeout" severity failure;
  end process p_timeout;

end architecture sim;
