-- tb_claude_axi4l_mst_if.vhd — Pure-VHDL loopback testbench for claude_axi4l_mst_if (GHDL).
--
--   mst_if_stim ─ mem_* ─► claude_axi4l_mst_if (DUT) ─ AXI4-Lite ─► claude_axi4l_mem_if
--                                                    ─ mem_* ─► claude_mem_model
--
-- VHDL twin of tb_claude_axi4l_mst_if.sv. The monitor checks: AW / W / AR VALID and payload
-- held until READY, AWVALID and WVALID raised together, one transaction outstanding and never
-- a read and a write at once, BREADY / RREADY only while a response is expected, every VALID /
-- READY low in reset; end to end: AWADDR / ARADDR, AWPROT / ARPROT, WDATA and WSTRB. A channel
-- throttle between the DUT and the slave adapter delays AWREADY / WREADY / ARREADY at random
-- (legal on both sides). Loopback latency 5, period 6.
--
-- Generics: DATA_W (32 or 64), ADDR_W (32).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_claude_axi4l_mst_if is
  generic (
    DATA_W : positive := 32;
    ADDR_W : positive := 32
  );
end entity tb_claude_axi4l_mst_if;

architecture sim of tb_claude_axi4l_mst_if is

  constant STRB_W     : positive := DATA_W / 8;
  constant CLK_PERIOD : time     := 10 ns;

  signal clk   : std_ulogic := '0';
  signal rst_n : std_ulogic;

  signal mem_req, mem_gnt, mem_we, mem_rvalid, mem_err : std_ulogic;
  signal mem_addr  : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal mem_be    : std_ulogic_vector(STRB_W - 1 downto 0);
  signal mem_wdata : std_ulogic_vector(DATA_W - 1 downto 0);
  signal mem_rdata : std_ulogic_vector(DATA_W - 1 downto 0);
  signal mem_prot  : std_ulogic_vector(2 downto 0);

  signal AWVALID, AWREADY, WVALID, WREADY, BVALID, BREADY : std_ulogic;
  signal ARVALID, ARREADY, RVALID, RREADY : std_ulogic;
  signal AWADDR, ARADDR : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal AWPROT, ARPROT : std_ulogic_vector(2 downto 0);
  signal WDATA, RDATA   : std_ulogic_vector(DATA_W - 1 downto 0);
  signal WSTRB          : std_ulogic_vector(STRB_W - 1 downto 0);
  signal BRESP, RRESP   : std_ulogic_vector(1 downto 0);

  -- slave side of the throttle
  signal s_awvalid, s_awready, s_wvalid, s_wready, s_arvalid, s_arready : std_ulogic;
  signal aw_fwd, w_fwd, ar_fwd, aw_allow, w_allow, ar_allow : std_ulogic := '0';
  signal aw_go, w_go, ar_go : std_ulogic;

  signal t_req, t_gnt, t_we, t_rvalid, t_err : std_ulogic;
  signal t_addr  : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal t_be    : std_ulogic_vector(STRB_W - 1 downto 0);
  signal t_wdata : std_ulogic_vector(DATA_W - 1 downto 0);
  signal t_rdata : std_ulogic_vector(DATA_W - 1 downto 0);

  signal max_gnt, max_rsp, throttle, n_fail, tgt_errors : natural;
  signal done       : std_ulogic;
  signal bus_errors : natural := 0;
  signal bus_xfers  : natural := 0;

begin

  clk <= not clk after CLK_PERIOD / 2;

  u_stim : entity work.mst_if_stim
    generic map (DATA_W => DATA_W, ADDR_W => ADDR_W, SPARSE_WR_OK => 1,
                 LAT_EXP => 5, PERIOD_EXP => 6, CLK_PERIOD => CLK_PERIOD, SEED => 13)
    port map (clk => clk, rst_n => rst_n, mem_req => mem_req, mem_gnt => mem_gnt,
              mem_we => mem_we, mem_addr => mem_addr, mem_be => mem_be, mem_wdata => mem_wdata,
              mem_prot => mem_prot, mem_rvalid => mem_rvalid, mem_rdata => mem_rdata,
              mem_err => mem_err, max_gnt => max_gnt, max_rsp => max_rsp, throttle => throttle,
              done => done, n_fail => n_fail);

  u_dut : entity work.claude_axi4l_mst_if
    generic map (DATA_W => DATA_W, ADDR_W => ADDR_W)
    port map (ACLK => clk, ARESETn => rst_n,
              AWVALID => AWVALID, AWREADY => AWREADY, AWADDR => AWADDR, AWPROT => AWPROT,
              WVALID => WVALID, WREADY => WREADY, WDATA => WDATA, WSTRB => WSTRB,
              BVALID => BVALID, BREADY => BREADY, BRESP => BRESP,
              ARVALID => ARVALID, ARREADY => ARREADY, ARADDR => ARADDR, ARPROT => ARPROT,
              RVALID => RVALID, RREADY => RREADY, RDATA => RDATA, RRESP => RRESP,
              mem_req_i => mem_req, mem_gnt_o => mem_gnt, mem_we_i => mem_we,
              mem_addr_i => mem_addr, mem_be_i => mem_be, mem_wdata_i => mem_wdata,
              mem_prot_i => mem_prot, mem_rvalid_o => mem_rvalid, mem_rdata_o => mem_rdata,
              mem_err_o => mem_err);

  u_slv : entity work.claude_axi4l_mem_if
    generic map (DATA_W => DATA_W, ADDR_W => ADDR_W)
    port map (ACLK => clk, ARESETn => rst_n,
              AWVALID => s_awvalid, AWREADY => s_awready, AWADDR => AWADDR,
              WVALID => s_wvalid, WREADY => s_wready, WDATA => WDATA, WSTRB => WSTRB,
              BVALID => BVALID, BREADY => BREADY, BRESP => BRESP,
              ARVALID => s_arvalid, ARREADY => s_arready, ARADDR => ARADDR,
              RVALID => RVALID, RREADY => RREADY, RDATA => RDATA, RRESP => RRESP,
              mem_req_o => t_req, mem_gnt_i => t_gnt, mem_we_o => t_we, mem_addr_o => t_addr,
              mem_be_o => t_be, mem_wdata_o => t_wdata, mem_rvalid_i => t_rvalid,
              mem_rdata_i => t_rdata, mem_err_i => t_err);

  u_tgt : entity work.claude_mem_model
    generic map (DATA_W => DATA_W, ADDR_W => ADDR_W, SIZE => 1024 * STRB_W, ERR_MSB => 1, SEED => 13)
    port map (clk => clk, rst_n => rst_n, mem_req => t_req, mem_gnt => t_gnt, mem_we => t_we,
              mem_addr => t_addr, mem_be => t_be, mem_wdata => t_wdata, mem_rvalid => t_rvalid,
              mem_rdata => t_rdata, mem_err => t_err, max_gnt => max_gnt, max_rsp => max_rsp,
              proto_errors => tgt_errors);

  -- Channel throttle (AW, W, AR): go = pass this cycle; fwd keeps passing a VALID the slave
  -- has seen until its handshake.
  p_throttle : process (clk) is
    variable x : unsigned(31 downto 0) := to_unsigned(77, 32);
    impure function allow return std_ulogic is
    begin
      x := x xor shift_left(x, 13);
      x := x xor shift_right(x, 17);
      x := x xor shift_left(x, 5);
      if throttle = 0 or to_integer(x mod to_unsigned(throttle + 1, 32)) = 0 then
        return '1';
      end if;
      return '0';
    end function;
  begin
    if rising_edge(clk) then
      aw_allow <= allow;
      w_allow  <= allow;
      ar_allow <= allow;
      if rst_n = '0' then
        aw_fwd <= '0';
        w_fwd  <= '0';
        ar_fwd <= '0';
      else
        aw_fwd <= s_awvalid and not s_awready;
        w_fwd  <= s_wvalid and not s_wready;
        ar_fwd <= s_arvalid and not s_arready;
      end if;
    end if;
  end process p_throttle;

  aw_go     <= aw_fwd or aw_allow;
  w_go      <= w_fwd or w_allow;
  ar_go     <= ar_fwd or ar_allow;
  s_awvalid <= AWVALID and aw_go;
  s_wvalid  <= WVALID and w_go;
  s_arvalid <= ARVALID and ar_go;
  AWREADY   <= s_awready and aw_go;
  WREADY    <= s_wready and w_go;
  ARREADY   <= s_arready and ar_go;

  -- AXI4-Lite master-rule monitor and end-to-end check.
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
    variable wr_out, rd_out, w_pend : boolean := false;
    variable w_be : std_ulogic_vector(STRB_W - 1 downto 0);
    variable w_data : std_ulogic_vector(DATA_W - 1 downto 0);
    variable p_awv, p_awr, p_wv, p_wr, p_arv, p_arr : std_ulogic := '0';
    variable p_awaddr, p_araddr : std_ulogic_vector(ADDR_W - 1 downto 0);
    variable p_awprot, p_arprot : std_ulogic_vector(2 downto 0);
    variable p_wdata : std_ulogic_vector(DATA_W - 1 downto 0);
    variable p_wstrb : std_ulogic_vector(STRB_W - 1 downto 0);
    variable k : natural;

    procedure bad(msg : string) is
    begin
      report "ERROR [axi mon] " & msg severity error;
      errs := errs + 1;
    end procedure;
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        if not seen and (AWVALID = '1' or WVALID = '1' or ARVALID = '1' or BREADY = '1' or RREADY = '1')
           and now > 3 * CLK_PERIOD then
          bad("VALID / READY high in reset");
        end if;
        if wr_out or rd_out then aborted := aborted + 1; end if;
        wr_out := false;
        rd_out := false;
        w_pend := false;
        rd_p   := wr_p;
        seen   := false;
      else
        if mem_req = '1' and mem_gnt = '1' then
          q_we(wr_p mod DEPTH)   := mem_we;
          q_addr(wr_p mod DEPTH) := mem_addr;
          q_data(wr_p mod DEPTH) := mem_wdata;
          q_be(wr_p mod DEPTH)   := mem_be;
          q_prot(wr_p mod DEPTH) := mem_prot;
          wr_p := wr_p + 1;
        end if;
        if seen then
          if p_awv = '1' and p_awr = '0' and not (AWVALID = '1' and AWADDR = p_awaddr and AWPROT = p_awprot) then
            bad("AW dropped or changed before AWREADY");
          end if;
          if p_wv = '1' and p_wr = '0' and not (WVALID = '1' and WDATA = p_wdata and WSTRB = p_wstrb) then
            bad("W dropped or changed before WREADY");
          end if;
          if p_arv = '1' and p_arr = '0' and not (ARVALID = '1' and ARADDR = p_araddr and ARPROT = p_arprot) then
            bad("AR dropped or changed before ARREADY");
          end if;
        end if;
        -- new write
        if AWVALID = '1' and not (seen and p_awv = '1') then
          if WVALID /= '1' then bad("AWVALID raised without WVALID"); end if;
          if wr_out or rd_out then bad("write issued while a transaction is outstanding"); end if;
          if rd_p = wr_p then
            bad("bus write without an accepted request");
          else
            k := rd_p mod DEPTH;
            if q_we(k) /= '1' or AWADDR /= q_addr(k) or AWPROT /= q_prot(k) then
              bad("AW 0x" & to_hstring(AWADDR) & " prot " & to_string(AWPROT) & ", expected 0x" &
                  to_hstring(q_addr(k)) & " prot " & to_string(q_prot(k)));
            end if;
            w_be   := q_be(k);
            w_data := q_data(k);
            w_pend := true;
            rd_p   := rd_p + 1;
            started := started + 1;
          end if;
          wr_out := true;
        elsif WVALID = '1' and not (seen and p_wv = '1') and AWVALID = '0' and not w_pend then
          bad("WVALID raised without AWVALID");
        end if;
        if WVALID = '1' and w_pend then
          if WSTRB /= w_be then bad("WSTRB " & to_string(WSTRB) & ", expected " & to_string(w_be)); end if;
          for b in 0 to STRB_W - 1 loop
            if w_be(b) = '1' and WDATA(8 * b + 7 downto 8 * b) /= w_data(8 * b + 7 downto 8 * b) then
              bad("WDATA lane " & integer'image(b) & " differs from mem_wdata");
            end if;
          end loop;
          w_pend := false;
        end if;
        -- new read
        if ARVALID = '1' and not (seen and p_arv = '1') then
          if wr_out or rd_out or AWVALID = '1' then bad("read issued while a transaction is outstanding"); end if;
          if rd_p = wr_p then
            bad("bus read without an accepted request");
          else
            k := rd_p mod DEPTH;
            if q_we(k) /= '0' or ARADDR /= q_addr(k) or ARPROT /= q_prot(k) then
              bad("AR 0x" & to_hstring(ARADDR) & " prot " & to_string(ARPROT) & ", expected 0x" &
                  to_hstring(q_addr(k)) & " prot " & to_string(q_prot(k)));
            end if;
            rd_p    := rd_p + 1;
            started := started + 1;
          end if;
          rd_out := true;
        end if;
        if (BREADY = '1' and not wr_out) or (RREADY = '1' and not rd_out) then
          bad("BREADY / RREADY high with no response expected");
        end if;
        if BVALID = '1' and BREADY = '1' then
          if not wr_out then bad("B handshake without an outstanding write"); end if;
          completed := completed + 1;
          wr_out    := false;
        end if;
        if RVALID = '1' and RREADY = '1' then
          if not rd_out then bad("R handshake without an outstanding read"); end if;
          completed := completed + 1;
          rd_out    := false;
        end if;
        seen := true;
      end if;
      p_awv := AWVALID; p_awr := AWREADY; p_awaddr := AWADDR; p_awprot := AWPROT;
      p_wv := WVALID; p_wr := WREADY; p_wdata := WDATA; p_wstrb := WSTRB;
      p_arv := ARVALID; p_arr := ARREADY; p_araddr := ARADDR; p_arprot := ARPROT;
      if done = '1' then
        if rd_p /= wr_p then
          bad(integer'image(wr_p - rd_p) & " accepted requests never appeared on the bus");
          rd_p := wr_p;
        end if;
        if completed + aborted /= started then
          bad(integer'image(started) & " transactions started, " & integer'image(completed) &
              " completed, " & integer'image(aborted) & " aborted");
          completed := started - aborted;
        end if;
      end if;
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
      report "PASS tb_claude_axi4l_mst_if" severity note;
    else
      report "FAIL tb_claude_axi4l_mst_if: " & integer'image(n_fail) & " test / mem_* failures, " &
             integer'image(bus_errors) & " bus violations, " & integer'image(tgt_errors) &
             " memory-model violations" severity error;
    end if;
    finish;
  end process p_end;

  p_timeout : process is
  begin
    wait for 5 ms;
    report "FAIL tb_claude_axi4l_mst_if: timeout" severity failure;
  end process p_timeout;

end architecture sim;
