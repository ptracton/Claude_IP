-- tb_claude_apb_mst_if.vhd — Pure-VHDL loopback testbench for claude_apb_mst_if (GHDL).
--
--   mst_if_stim ─ mem_* ─► claude_apb_mst_if (DUT) ─ APB4 ─► claude_apb_mem_if
--                                                  ─ mem_* ─► claude_mem_model
--
-- VHDL twin of tb_claude_apb_mst_if.sv, so the VHDL adapters are verified on GHDL with no
-- SV. mst_if_stim runs the tests and checks the DUT's mem_* side; the monitor below checks
-- every APB4 master rule and, end to end, that each accepted request appears once on the
-- bus with the same direction, address, PPROT, strobes and write data.
--
-- Generics: DATA_W (8, 16 or 32), ADDR_W (32).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_claude_apb_mst_if is
  generic (
    DATA_W : positive := 32;
    ADDR_W : positive := 32
  );
end entity tb_claude_apb_mst_if;

architecture sim of tb_claude_apb_mst_if is

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

  signal PSEL, PENABLE, PWRITE, PREADY, PSLVERR : std_ulogic;
  signal PADDR  : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal PWDATA : std_ulogic_vector(DATA_W - 1 downto 0);
  signal PRDATA : std_ulogic_vector(DATA_W - 1 downto 0);
  signal PSTRB  : std_ulogic_vector(STRB_W - 1 downto 0);
  signal PPROT  : std_ulogic_vector(2 downto 0);

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
                 LAT_EXP => 3, PERIOD_EXP => 4, CLK_PERIOD => CLK_PERIOD, SEED => 7)
    port map (clk => clk, rst_n => rst_n, mem_req => mem_req, mem_gnt => mem_gnt,
              mem_we => mem_we, mem_addr => mem_addr, mem_be => mem_be, mem_wdata => mem_wdata,
              mem_prot => mem_prot, mem_rvalid => mem_rvalid, mem_rdata => mem_rdata,
              mem_err => mem_err, max_gnt => max_gnt, max_rsp => max_rsp, throttle => throttle,
              done => done, n_fail => n_fail);

  u_dut : entity work.claude_apb_mst_if
    generic map (DATA_W => DATA_W, ADDR_W => ADDR_W)
    port map (PCLK => clk, PRESETn => rst_n, PSEL => PSEL, PENABLE => PENABLE, PADDR => PADDR,
              PWRITE => PWRITE, PWDATA => PWDATA, PSTRB => PSTRB, PPROT => PPROT,
              PRDATA => PRDATA, PREADY => PREADY, PSLVERR => PSLVERR,
              mem_req_i => mem_req, mem_gnt_o => mem_gnt, mem_we_i => mem_we,
              mem_addr_i => mem_addr, mem_be_i => mem_be, mem_wdata_i => mem_wdata,
              mem_prot_i => mem_prot, mem_rvalid_o => mem_rvalid, mem_rdata_o => mem_rdata,
              mem_err_o => mem_err);

  u_slv : entity work.claude_apb_mem_if
    generic map (DATA_W => DATA_W, ADDR_W => ADDR_W)
    port map (PCLK => clk, PRESETn => rst_n, PSEL => PSEL, PENABLE => PENABLE, PADDR => PADDR,
              PWRITE => PWRITE, PWDATA => PWDATA, PSTRB => PSTRB, PRDATA => PRDATA,
              PREADY => PREADY, PSLVERR => PSLVERR,
              mem_req_o => t_req, mem_gnt_i => t_gnt, mem_we_o => t_we, mem_addr_o => t_addr,
              mem_be_o => t_be, mem_wdata_o => t_wdata, mem_rvalid_i => t_rvalid,
              mem_rdata_i => t_rdata, mem_err_i => t_err);

  u_tgt : entity work.claude_mem_model
    generic map (DATA_W => DATA_W, ADDR_W => ADDR_W, SIZE => 1024 * STRB_W, ERR_MSB => 1, SEED => 7)
    port map (clk => clk, rst_n => rst_n, mem_req => t_req, mem_gnt => t_gnt, mem_we => t_we,
              mem_addr => t_addr, mem_be => t_be, mem_wdata => t_wdata, mem_rvalid => t_rvalid,
              mem_rdata => t_rdata, mem_err => t_err, max_gnt => max_gnt, max_rsp => max_rsp,
              proto_errors => tgt_errors);

  -- APB4 master-rule monitor and end-to-end check.
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
    variable started, completed, aborted, flushed, errs : natural := 0;
    variable in_xfer : boolean := false;
    variable seen    : boolean := false;    -- rst_n high at the previous edge
    variable p_sel, p_en, p_wr, p_rdy : std_ulogic := '0';
    variable p_addr : std_ulogic_vector(ADDR_W - 1 downto 0);
    variable p_data : std_ulogic_vector(DATA_W - 1 downto 0);
    variable p_strb : std_ulogic_vector(STRB_W - 1 downto 0);
    variable p_prot : std_ulogic_vector(2 downto 0);
    variable k : natural;

    procedure bad(msg : string) is
    begin
      report "ERROR [apb mon] " & msg severity error;
      errs := errs + 1;
    end procedure;

    impure function same_payload return boolean is
    begin
      return PADDR = p_addr and PWRITE = p_wr and PSTRB = p_strb and PPROT = p_prot and
             (PWRITE = '0' or PWDATA = p_data);
    end function;
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        if seen and (PSEL = '1' or PENABLE = '1') then
          null;  -- the DUT resets at this edge; checked from the next edge on
        elsif not seen and (PSEL = '1' or PENABLE = '1') and now > 3 * CLK_PERIOD then
          bad("PSEL / PENABLE high in reset");
        end if;
        if in_xfer then
          aborted := aborted + 1;
        end if;
        in_xfer := false;
        flushed := flushed + (wr_p - rd_p);
        rd_p    := wr_p;
        seen    := false;
      else
        -- requests the bus should see
        if mem_req = '1' and mem_gnt = '1' then
          q_we(wr_p mod DEPTH)   := mem_we;
          q_addr(wr_p mod DEPTH) := mem_addr;
          q_data(wr_p mod DEPTH) := mem_wdata;
          q_be(wr_p mod DEPTH)   := mem_be;
          q_prot(wr_p mod DEPTH) := mem_prot;
          wr_p := wr_p + 1;
        end if;
        if PENABLE = '1' and PSEL = '0' then
          bad("PENABLE without PSEL");
        end if;
        if seen then
          if p_sel = '1' and p_en = '0' then
            if not (PSEL = '1' and PENABLE = '1') then bad("SETUP not followed by ACCESS"); end if;
            if not same_payload then bad("payload changed from SETUP to ACCESS"); end if;
          end if;
          if p_sel = '1' and p_en = '1' and p_rdy = '0' then
            if not (PSEL = '1' and PENABLE = '1') then bad("ACCESS dropped before PREADY"); end if;
            if not same_payload then bad("payload changed during a wait state"); end if;
          end if;
          if p_sel = '1' and p_en = '1' and p_rdy = '1' and PENABLE = '1' then
            bad("PENABLE high after a completed ACCESS");
          end if;
          if PSEL = '1' and PENABLE = '1' and not (p_sel = '1' and (p_en = '0' or p_rdy = '0')) then
            bad("ACCESS without a preceding SETUP");
          end if;
        end if;
        if PSEL = '1' and PENABLE = '0' and PWRITE = '0' and unsigned(PSTRB) /= 0 then
          bad("PSTRB not zero on a read");
        end if;
        -- first SETUP cycle of a transfer: compare with the next expected request
        if PSEL = '1' and PENABLE = '0' and not (seen and p_sel = '1' and p_en = '0') then
          if rd_p = wr_p then
            bad("bus transfer without an accepted request");
          else
            k := rd_p mod DEPTH;
            if PWRITE /= q_we(k) or PADDR /= q_addr(k) or PPROT /= q_prot(k) then
              bad("SETUP " & to_string(PWRITE) & " 0x" & to_hstring(PADDR) & " prot " &
                  to_string(PPROT) & ", expected " & to_string(q_we(k)) & " 0x" &
                  to_hstring(q_addr(k)) & " prot " & to_string(q_prot(k)));
            end if;
            if q_we(k) = '1' then
              if PSTRB /= q_be(k) then bad("PSTRB differs from mem_be"); end if;
              for b in 0 to STRB_W - 1 loop
                if q_be(k)(b) = '1' and PWDATA(8 * b + 7 downto 8 * b) /= q_data(k)(8 * b + 7 downto 8 * b) then
                  bad("PWDATA differs from mem_wdata");
                end if;
              end loop;
            end if;
            rd_p    := rd_p + 1;
            started := started + 1;
            in_xfer := true;
          end if;
        end if;
        if PSEL = '1' and PENABLE = '1' and PREADY = '1' then
          completed := completed + 1;
          in_xfer   := false;
        end if;
        seen := true;
      end if;
      p_sel := PSEL; p_en := PENABLE; p_wr := PWRITE; p_rdy := PREADY;
      p_addr := PADDR; p_data := PWDATA; p_strb := PSTRB; p_prot := PPROT;
      -- accounting (published every cycle; judged at the end)
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
      report "PASS tb_claude_apb_mst_if" severity note;
    else
      report "FAIL tb_claude_apb_mst_if: " & integer'image(n_fail) & " test / mem_* failures, " &
             integer'image(bus_errors) & " bus violations, " & integer'image(tgt_errors) &
             " memory-model violations" severity error;
    end if;
    finish;
  end process p_end;

  p_timeout : process is
  begin
    wait for 5 ms;
    report "FAIL tb_claude_apb_mst_if: timeout" severity failure;
  end process p_timeout;

end architecture sim;
