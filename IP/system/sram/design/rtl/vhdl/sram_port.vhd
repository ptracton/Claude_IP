-- sram_port.vhd — One memory-bus port of the sram core.
--
-- VHDL-2008 twin of sram_port.sv (see it for the full description): target
-- side of the Claude memory bus, one request at a time, response
-- READ_LATENCY cycles after the grant (one cycle later for an ECC
-- read-modify-write with READ_LATENCY 1). Checks (engine stall, range, partial
-- write without byte enables, domain in DS/SD, domain asleep -> wake),
-- SECDED decode per codeword (WIDTH / CW codewords, one write lane each;
-- a partial write inside a codeword is a read-modify-write that writes back
-- only the strobed codewords), and error injection (codeword 0) on the next
-- write. Status pulses are registered.
-- s2 stage (READ_LATENCY 2, and every ECC read-modify-write): the word read
-- is registered at the array output (rd_q) and decoded in s2; a
-- read-modify-write merges, encodes and writes back in s2.
-- READ_ONLY: every write is a bus error (port B of a SKY130 dual-port array).
-- req_* / acc_o / rmw_* let the core keep two ports off the same word.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sram_pkg.all;

entity sram_port is
  generic (
    ADDR_W         : positive := 32;   -- bus byte-address width
    WIDTH          : positive := 32;   -- data width (multiple of 8)
    DEPTH          : positive := 1024; -- words
    BYTE_EN        : natural  := 1;    -- byte-lane writes (0 / 1)
    PARTIAL_WR_ERR : natural  := 1;    -- BYTE_EN = 0: partial write is an error
    READ_LATENCY   : positive := 1;    -- 1 or 2
    ECC_EN         : natural  := 0;    -- SECDED (0 / 1)
    NPD            : positive := 1;    -- power domains
    READ_ONLY      : natural  := 0;    -- writes are bus errors (0 / 1)
    CW             : positive := 32    -- ECC codeword data width (= WIDTH, or the
                                       -- narrow width of a dual port)
  );
  port (
    clk           : in  std_ulogic; -- clock
    rst_n         : in  std_ulogic; -- synchronous active-low reset

    -- Memory bus (target side)
    mem_req_i     : in  std_ulogic;                                -- request
    mem_gnt_o     : out std_ulogic;                                -- request accepted
    mem_we_i      : in  std_ulogic;                                -- 1 = write
    mem_addr_i    : in  std_ulogic_vector(ADDR_W - 1 downto 0);    -- byte address
    mem_be_i      : in  std_ulogic_vector(WIDTH / 8 - 1 downto 0); -- byte enables
    mem_wdata_i   : in  std_ulogic_vector(WIDTH - 1 downto 0);     -- write data
    mem_rvalid_o  : out std_ulogic;                                -- response
    mem_rdata_o   : out std_ulogic_vector(WIDTH - 1 downto 0);     -- read data
    mem_err_o     : out std_ulogic;                                -- response is an error

    -- Power domains and engines
    dom_awake_i   : in  std_ulogic_vector(NPD - 1 downto 0); -- domain accepts bus accesses
    dom_err_i     : in  std_ulogic_vector(NPD - 1 downto 0); -- domain access is a bus error
    stall_i       : in  std_ulogic;                          -- an engine owns the array
    wake_o        : out std_ulogic_vector(NPD - 1 downto 0); -- a request waits for this domain
    dom_busy_o    : out std_ulogic_vector(NPD - 1 downto 0); -- access to this domain in flight
    idle_o        : out std_ulogic;                          -- nothing in flight on the array

    -- Conflict information (DUAL_PORT)
    req_idx_o     : out std_ulogic_vector(clog2(DEPTH) - 1 downto 0); -- request word index
    req_we_o      : out std_ulogic;                                   -- request is a write
    acc_o         : out std_ulogic;                                   -- array access granted now
    rmw_pend_o    : out std_ulogic;                                   -- RMW write-back pending
    rmw_idx_o     : out std_ulogic_vector(clog2(DEPTH) - 1 downto 0); -- its word index

    -- Array
    arr_cs_o      : out std_ulogic;                                   -- array access
    arr_we_o      : out std_ulogic;                                   -- 1 = write
    arr_idx_o     : out std_ulogic_vector(clog2(DEPTH) - 1 downto 0); -- word index
    arr_wdata_o   : out std_ulogic_vector(stored_width(WIDTH, CW, ECC_EN) - 1 downto 0); -- word
    arr_lane_we_o : out std_ulogic_vector(stored_lanes(WIDTH, CW, BYTE_EN, ECC_EN) - 1
                                          downto 0); -- lanes to write
    -- stored word (cycle after a read)
    arr_rdata_i   : in  std_ulogic_vector(stored_width(WIDTH, CW, ECC_EN) - 1 downto 0);

    -- ECC and status
    ecc_inj_i     : in  std_ulogic_vector(1 downto 0); -- arm 1-bit (0) / 2-bit (1) error
    ecc_corr_o    : out std_ulogic;                    -- corrected error (registered pulse)
    ecc_uncorr_o  : out std_ulogic;                    -- uncorrectable error (registered pulse)
    err_irq_o     : out std_ulogic;                    -- bus error or ECC event (registered pulse)
    busy_o        : out std_ulogic                     -- read-modify-write in progress
  );
end entity sram_port;

architecture rtl of sram_port is

  constant MW_C     : positive := stored_width(WIDTH, CW, ECC_EN);
  constant NLANES_C : positive := stored_lanes(WIDTH, CW, BYTE_EN, ECC_EN);
  constant NCW_C    : positive := WIDTH / CW;  -- codewords
  constant CWS_C    : positive := MW_C / NCW_C;  -- stored codeword width
  constant CWB_C    : positive := CW / 8;      -- bytes per codeword
  constant HAS_RMW_C : boolean := ECC_EN /= 0 and BYTE_EN /= 0;       -- read-modify-write possible
  constant HAS_S2_C  : boolean := READ_LATENCY = 2 or HAS_RMW_C;      -- s2 stage exists
  constant STRB_W_C : positive := WIDTH / 8;
  constant OFF_W_C  : natural  := clog2(STRB_W_C);
  constant IDX_W_C  : positive := clog2(DEPTH);
  constant DOM_SH_C : natural  := clog2(DEPTH / NPD);
  constant ALL_BE_C : std_ulogic_vector(STRB_W_C - 1 downto 0) := (others => '1');

  -- Request decode (s0)
  signal idx       : std_ulogic_vector(IDX_W_C - 1 downto 0);
  signal dom       : natural range 0 to NPD - 1;
  signal oor       : std_ulogic; -- beyond the last word
  signal partial   : std_ulogic; -- write with some byte enables clear
  signal cw_touch  : std_ulogic_vector(NCW_C - 1 downto 0); -- codewords with a strobed byte
  signal cw_part   : std_ulogic_vector(NCW_C - 1 downto 0); -- codewords partly strobed
  signal req_err   : std_ulogic; -- grant with an error response
  signal rmw       : std_ulogic; -- ECC partial write: read first
  signal grant     : std_ulogic;
  signal do_access : std_ulogic; -- grant with an array access

  -- s1: request registers
  signal s1_valid_q : std_ulogic;
  signal s1_err_q   : std_ulogic;
  signal s1_we_q    : std_ulogic;
  signal s1_rmw_q   : std_ulogic;
  signal s1_idx_q   : std_ulogic_vector(IDX_W_C - 1 downto 0);
  signal s1_dom_q   : natural range 0 to NPD - 1;
  signal s1_be_q    : std_ulogic_vector(STRB_W_C - 1 downto 0);
  signal s1_wdata_q : std_ulogic_vector(WIDTH - 1 downto 0);

  -- s2: request and raw word read, registered at the array output
  signal s2_valid_q : std_ulogic; -- s2 holds a request (READ_LATENCY 2, or a read-modify-write)
  signal s2_rmw_q   : std_ulogic; -- ... which is a read-modify-write (write-back this cycle)
  signal s2_err_q   : std_ulogic;
  signal s2_we_q    : std_ulogic;
  signal s2_idx_q   : std_ulogic_vector(IDX_W_C - 1 downto 0);
  signal s2_dom_q   : natural range 0 to NPD - 1;
  signal s2_be_q    : std_ulogic_vector(STRB_W_C - 1 downto 0);
  signal s2_wdata_q : std_ulogic_vector(WIDTH - 1 downto 0);
  signal rd_q       : std_ulogic_vector(MW_C - 1 downto 0); -- stored word read (raw)

  -- Response stage x: s2 for READ_LATENCY 2 and a read-modify-write, else s1
  signal x_sel      : std_ulogic;
  signal x_valid    : std_ulogic;
  signal x_err      : std_ulogic;
  signal x_we       : std_ulogic;
  signal x_rmw      : std_ulogic;
  signal x_be       : std_ulogic_vector(STRB_W_C - 1 downto 0);
  signal x_rdata    : std_ulogic_vector(MW_C - 1 downto 0);  -- stored word to decode

  -- ECC
  signal rd_data    : std_ulogic_vector(WIDTH - 1 downto 0); -- data read (corrected)
  signal cw_single  : std_ulogic_vector(NCW_C - 1 downto 0); -- per codeword: corrected
  signal cw_double  : std_ulogic_vector(NCW_C - 1 downto 0); -- per codeword: uncorrectable
  signal cw_used    : std_ulogic_vector(NCW_C - 1 downto 0); -- codewords that matter
  signal x_touch    : std_ulogic_vector(NCW_C - 1 downto 0); -- codewords strobed by x
  signal dec_single : std_ulogic;
  signal dec_double : std_ulogic;
  signal merged     : std_ulogic_vector(WIDTH - 1 downto 0); -- read-modify-write result
  signal rmw_write  : std_ulogic;                            -- s2 write-back
  signal enc_data   : std_ulogic_vector(WIDTH - 1 downto 0); -- data to encode / write
  signal stored     : std_ulogic_vector(MW_C - 1 downto 0);  -- word to write (before injection)
  signal inj_q      : std_ulogic_vector(1 downto 0);         -- armed error injection
  signal bus_write  : std_ulogic; -- a write from this port reaches the array
  signal flip       : std_ulogic_vector(MW_C - 1 downto 0);  -- injected bit flips

  -- Response (stage x)
  signal checked    : std_ulogic; -- the response used read data
  signal rsp_err    : std_ulogic;
  signal rsp_data   : std_ulogic_vector(WIDTH - 1 downto 0);

  signal ecc_corr_q   : std_ulogic;
  signal ecc_uncorr_q : std_ulogic;
  signal err_irq_q    : std_ulogic;

begin

  -----------------------------
  -- Request decode (s0) --
  -----------------------------
  idx <= mem_addr_i(OFF_W_C + IDX_W_C - 1 downto OFF_W_C);

  gen_dom : if NPD > 1 generate
    dom <= to_integer(shift_right(unsigned(idx), DOM_SH_C));
  end generate gen_dom;
  gen_dom_n : if not (NPD > 1) generate
    dom <= 0;
  end generate gen_dom_n;

  gen_oor : if ADDR_W > OFF_W_C + IDX_W_C generate
    oor <= '1' when unsigned(mem_addr_i(ADDR_W - 1 downto OFF_W_C + IDX_W_C)) /= 0 else '0';
  end generate gen_oor;
  gen_oor_n : if not (ADDR_W > OFF_W_C + IDX_W_C) generate
    oor <= '0';
  end generate gen_oor_n;

  partial <= '1' when mem_we_i = '1' and mem_be_i /= ALL_BE_C else '0';
  req_err <= '1' when oor = '1' or dom_err_i(dom) = '1' or
                      (READ_ONLY /= 0 and mem_we_i = '1') or
                      (BYTE_EN = 0 and PARTIAL_WR_ERR /= 0 and partial = '1') else '0';
  gen_cw_strobe : for c in 0 to NCW_C - 1 generate
    cw_touch(c) <= red_or(mem_be_i(c * CWB_C + CWB_C - 1 downto c * CWB_C));
    cw_part(c)  <= cw_touch(c) and not red_and(mem_be_i(c * CWB_C + CWB_C - 1 downto c * CWB_C));
  end generate gen_cw_strobe;

  -- ECC: a write that covers whole codewords stores them directly.
  rmw     <= '1' when ECC_EN /= 0 and BYTE_EN /= 0 and mem_we_i = '1' and
                      unsigned(cw_part) /= 0 else '0';

  -- Grant: never while an engine owns the array, a response is pending or a
  -- read-modify-write is writing back.
  p_grant : process (all) is
  begin
    grant  <= '0';
    do_access <= '0';
    wake_o <= (others => '0');
    if mem_req_i = '1' and stall_i = '0' and s1_valid_q = '0' and
       not (s2_valid_q = '1' and s2_rmw_q = '1') then
      if req_err = '1' then
        grant <= '1';
      elsif dom_awake_i(dom) = '1' then
        grant  <= '1';
        do_access <= '1';
      else
        wake_o(dom) <= '1';
      end if;
    end if;
  end process p_grant;

  mem_gnt_o <= grant;

  -- Capture the granted request for its response cycle.
  p_s1 : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        s1_valid_q <= '0';
        s1_err_q   <= '0';
        s1_we_q    <= '0';
        s1_rmw_q   <= '0';
        s1_idx_q   <= (others => '0');
        s1_dom_q   <= 0;
        s1_be_q    <= (others => '0');
        s1_wdata_q <= (others => '0');
      else
        s1_valid_q <= grant;
        if grant = '1' then
          s1_err_q   <= req_err;
          s1_we_q    <= mem_we_i;
          s1_rmw_q   <= do_access and rmw;
          s1_idx_q   <= idx;
          s1_dom_q   <= dom;
          s1_be_q    <= mem_be_i;
          s1_wdata_q <= mem_wdata_i;
        end if;
      end if;
    end if;
  end process p_s1;

  -- s2: the request and the raw word read in s0 (READ_LATENCY 2: every
  -- request; otherwise read-modify-writes).
  gen_s2 : if HAS_S2_C generate
    p_s2 : process (clk) is
    begin
      if rising_edge(clk) then
        if rst_n = '0' then
          s2_valid_q <= '0';
          s2_rmw_q   <= '0';
          s2_err_q   <= '0';
          s2_we_q    <= '0';
          s2_idx_q   <= (others => '0');
          s2_dom_q   <= 0;
          s2_be_q    <= (others => '0');
          s2_wdata_q <= (others => '0');
          rd_q       <= (others => '0');
        else
          if READ_LATENCY = 2 then
            s2_valid_q <= s1_valid_q;
          else
            s2_valid_q <= s1_valid_q and s1_rmw_q;
          end if;
          s2_rmw_q <= s1_valid_q and s1_rmw_q;
          if s1_valid_q = '1' then
            s2_err_q   <= s1_err_q;
            s2_we_q    <= s1_we_q;
            s2_idx_q   <= s1_idx_q;
            s2_dom_q   <= s1_dom_q;
            s2_be_q    <= s1_be_q;
            s2_wdata_q <= s1_wdata_q;
            rd_q       <= arr_rdata_i;
          end if;
        end if;
      end if;
    end process p_s2;
  end generate gen_s2;
  gen_s2_n : if not HAS_S2_C generate
    s2_valid_q <= '0';
    s2_rmw_q   <= '0';
    s2_err_q   <= '0';
    s2_we_q    <= '0';
    s2_idx_q   <= (others => '0');
    s2_dom_q   <= 0;
    s2_be_q    <= (others => '0');
    s2_wdata_q <= (others => '0');
    rd_q       <= (others => '0');
  end generate gen_s2_n;

  -- Response stage x.
  gen_x_rl2 : if READ_LATENCY = 2 generate
    x_sel <= '1';
  end generate gen_x_rl2;
  gen_x_rl1 : if READ_LATENCY /= 2 generate
    x_sel <= s2_valid_q;
  end generate gen_x_rl1;
  x_valid <= s2_valid_q when x_sel = '1' else s1_valid_q and not s1_rmw_q;
  x_err   <= s2_err_q   when x_sel = '1' else s1_err_q;
  x_we    <= s2_we_q    when x_sel = '1' else s1_we_q;
  x_rmw   <= x_sel and s2_rmw_q;
  x_be    <= s2_be_q    when x_sel = '1' else s1_be_q;
  x_rdata <= rd_q       when x_sel = '1' else arr_rdata_i;

  ---------
  -- ECC --
  ---------
  gen_ecc : if ECC_EN /= 0 generate
    gen_cw : for c in 0 to NCW_C - 1 generate
      u_dec : entity work.sram_ecc_dec(rtl)
        generic map (
          K => CW
        )
        port map (
          code_i   => x_rdata(c * CWS_C + CWS_C - 1 downto c * CWS_C),
          data_o   => rd_data(c * CW + CW - 1 downto c * CW),
          single_o => cw_single(c),
          double_o => cw_double(c)
        );
      u_enc : entity work.sram_ecc_enc(rtl)
        generic map (
          K => CW
        )
        port map (
          data_i => enc_data(c * CW + CW - 1 downto c * CW),
          code_o => stored(c * CWS_C + CWS_C - 1 downto c * CWS_C)
        );
    end generate gen_cw;
  end generate gen_ecc;
  gen_ecc_n : if not (ECC_EN /= 0) generate
    rd_data   <= x_rdata(WIDTH - 1 downto 0);
    cw_single <= (others => '0');
    cw_double <= (others => '0');
    stored    <= std_ulogic_vector(resize(unsigned(enc_data), MW_C));
  end generate gen_ecc_n;

  -- A read checks every codeword; a read-modify-write only the codewords it
  -- writes back.
  gen_x_touch : for c in 0 to NCW_C - 1 generate
    x_touch(c) <= red_or(x_be(c * CWB_C + CWB_C - 1 downto c * CWB_C));
  end generate gen_x_touch;
  cw_used    <= x_touch when x_rmw = '1' else (others => '1');
  dec_single <= red_or(cw_single and cw_used);
  dec_double <= red_or(cw_double and cw_used);

  gen_merge : for b in 0 to STRB_W_C - 1 generate
    merged(8 * b + 7 downto 8 * b) <= s2_wdata_q(8 * b + 7 downto 8 * b) when x_be(b) = '1'
                                      else rd_data(8 * b + 7 downto 8 * b);
  end generate gen_merge;

  rmw_write <= x_valid and x_rmw and not dec_double;
  enc_data  <= merged when rmw_write = '1' else mem_wdata_i;
  bus_write <= '1' when rmw_write = '1' or
                       (do_access = '1' and mem_we_i = '1' and rmw = '0') else '0';

  p_flip : process (all) is
  begin
    flip <= (others => '0');
    if ECC_EN /= 0 then
      if inj_q(1) = '1' then
        flip(1 downto 0) <= "11";
      elsif inj_q(0) = '1' then
        flip(0) <= '1';
      end if;
    end if;
  end process p_flip;

  -- Armed error injection; consumed by the next write from this port.
  p_inject : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        inj_q <= (others => '0');
      else
        if bus_write = '1' then
          inj_q <= (others => '0');
        end if;
        if ECC_EN /= 0 then
          if bus_write = '1' then
            inj_q <= ecc_inj_i;
          else
            inj_q <= inj_q or ecc_inj_i;
          end if;
        end if;
      end if;
    end if;
  end process p_inject;

  ------------------
  -- Array access --
  ------------------
  p_array : process (all) is
  begin
    arr_cs_o      <= '0';
    arr_we_o      <= '0';
    arr_idx_o     <= idx;
    arr_wdata_o   <= stored xor flip;
    arr_lane_we_o <= (others => '1');
    if rmw_write = '1' then
      arr_cs_o  <= '1';
      arr_we_o  <= '1';
      arr_idx_o <= s2_idx_q;
      if ECC_EN /= 0 and BYTE_EN /= 0 then
        arr_lane_we_o <= std_ulogic_vector(resize(unsigned(x_touch), NLANES_C));
      end if;
    elsif do_access = '1' then
      arr_cs_o <= '1';
      arr_we_o <= mem_we_i and not rmw;
      if ECC_EN /= 0 and BYTE_EN /= 0 then
        arr_lane_we_o <= std_ulogic_vector(resize(unsigned(cw_touch), NLANES_C));
      elsif BYTE_EN /= 0 then
        -- One lane per byte (also for an 8-bit word: an all-zero strobe
        -- writes nothing).
        arr_lane_we_o <= mem_be_i(NLANES_C - 1 downto 0);
      end if;
    end if;
  end process p_array;

  ----------------------------
  -- Response (stage x)     --
  ----------------------------
  checked  <= x_valid and not x_err and (x_rmw or not x_we);
  rsp_err  <= x_err or (checked and dec_double);
  rsp_data <= rd_data when x_valid = '1' and x_err = '0' and x_we = '0' and
                           dec_double = '0' else (others => '0');

  -- Status pulses, registered (read data comes through the decoder).
  p_status : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        ecc_corr_q   <= '0';
        ecc_uncorr_q <= '0';
        err_irq_q    <= '0';
      else
        if ECC_EN /= 0 then
          ecc_corr_q   <= checked and dec_single;
          ecc_uncorr_q <= checked and dec_double;
          err_irq_q    <= (x_valid and rsp_err) or (checked and dec_single);
        else
          ecc_corr_q   <= '0';
          ecc_uncorr_q <= '0';
          err_irq_q    <= x_valid and rsp_err;
        end if;
      end if;
    end if;
  end process p_status;

  ecc_corr_o   <= ecc_corr_q;
  ecc_uncorr_o <= ecc_uncorr_q;
  err_irq_o    <= err_irq_q;
  mem_rvalid_o <= x_valid;
  mem_err_o    <= rsp_err;
  mem_rdata_o  <= rsp_data;

  -- A read-modify-write is pending from its s1 (read) to its s2 (write-back).
  busy_o       <= (s1_valid_q and s1_rmw_q) or s2_rmw_q;
  idle_o       <= not s1_valid_q and not s2_rmw_q;

  req_idx_o  <= idx;
  req_we_o   <= mem_we_i;
  acc_o      <= do_access;
  rmw_pend_o <= (s1_valid_q and s1_rmw_q) or s2_rmw_q;
  rmw_idx_o  <= s2_idx_q when s2_rmw_q = '1' else s1_idx_q;

  gen_busy : for d in 0 to NPD - 1 generate
    dom_busy_o(d) <= '1' when (do_access = '1' and dom = d) or
                              (s1_valid_q = '1' and s1_err_q = '0' and s1_dom_q = d) or
                              (s2_rmw_q = '1' and s2_dom_q = d) else '0';
  end generate gen_busy;

end architecture rtl;
