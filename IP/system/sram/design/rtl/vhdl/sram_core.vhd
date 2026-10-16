-- sram_core.vhd — Protocol-independent core of the sram IP.
--
-- VHDL-2008 twin of sram_core.sv (see it for the full description):
-- sram_port, one sram_pwr_ctrl per power domain, sram_clr, sram_bist and
-- sram_array. Array ownership, highest first: BIST, clear engine, bus port.
-- With ECC_EN the array is cleared after reset. pwr_mode_req_i /
-- pwr_mode_ack_o carry 2 bits per domain (domain d in bits 2d+1 downto 2d).
-- DUAL_PORT: a second bus port (mem_b_*) on a two-port array; same-word
-- conflicts complete in the order A then B (B waits, or a port waits for the
-- other port's pending read-modify-write); port B is read-only with
-- TECH_SKY130; ECC error injection applies to port A writes.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sram_pkg.all;

entity sram_core is
  generic (
    TECH           : natural  := TECH_GENERIC_C; -- technology
    ADDR_W         : positive := 32;             -- bus byte-address width
    WIDTH          : positive := 32;             -- data width (multiple of 8)
    DEPTH          : positive := 1024;           -- words (power of two)
    BYTE_EN        : natural  := 1;              -- byte-lane writes (0 / 1)
    PARTIAL_WR_ERR : natural  := 1;              -- BYTE_EN = 0: partial write is an error
    READ_LATENCY   : positive := 1;              -- 1 or 2
    PWR_GATE       : natural  := 1;              -- power modes (0 / 1)
    ECC_EN         : natural  := 0;              -- SECDED (0 / 1)
    BANK_PG        : natural  := 0;              -- one power domain per bank (0 / 1)
    NUM_BANKS      : positive := 1;              -- banks (power of two)
    BIST_EN        : natural  := 0;              -- March C- engine (0 / 1)
    DUAL_PORT      : natural  := 0;              -- second bus port mem_b_* (0 / 1)
    INIT_FILE      : string   := ""              -- preload (GENERIC/FPGA)
  );
  port (
    clk              : in  std_ulogic; -- clock
    rst_n            : in  std_ulogic; -- synchronous active-low reset

    -- Memory bus (target side)
    mem_req_i        : in  std_ulogic;                                -- request
    mem_gnt_o        : out std_ulogic;                                -- request accepted
    mem_we_i         : in  std_ulogic;                                -- 1 = write
    mem_addr_i       : in  std_ulogic_vector(ADDR_W - 1 downto 0);    -- byte address
    mem_be_i         : in  std_ulogic_vector(WIDTH / 8 - 1 downto 0); -- byte enables
    mem_wdata_i      : in  std_ulogic_vector(WIDTH - 1 downto 0);     -- write data
    mem_rvalid_o     : out std_ulogic;                                -- response
    mem_rdata_o      : out std_ulogic_vector(WIDTH - 1 downto 0);     -- read data
    mem_err_o        : out std_ulogic;                                -- response is an error

    -- Memory bus, port B (DUAL_PORT; tie inputs to 0 otherwise)
    mem_b_req_i      : in  std_ulogic;                                -- request
    mem_b_gnt_o      : out std_ulogic;                                -- request accepted
    mem_b_we_i       : in  std_ulogic;                                -- 1 = write
    mem_b_addr_i     : in  std_ulogic_vector(ADDR_W - 1 downto 0);    -- byte address
    mem_b_be_i       : in  std_ulogic_vector(WIDTH / 8 - 1 downto 0); -- byte enables
    mem_b_wdata_i    : in  std_ulogic_vector(WIDTH - 1 downto 0);     -- write data
    mem_b_rvalid_o   : out std_ulogic;                                -- response
    mem_b_rdata_o    : out std_ulogic_vector(WIDTH - 1 downto 0);     -- read data
    mem_b_err_o      : out std_ulogic;                                -- response is an error

    -- Power
    -- requested mode
    pwr_mode_req_i   : in  std_ulogic_vector(2 * num_domains(BANK_PG, NUM_BANKS) - 1 downto 0);
    -- mode in effect
    pwr_mode_ack_o   : out std_ulogic_vector(2 * num_domains(BANK_PG, NUM_BANKS) - 1 downto 0);

    -- Clear, status
    clr_req_i        : in  std_ulogic; -- clear the array (pulse)
    clr_done_o       : out std_ulogic; -- clear pass finished (pulse)
    busy_o           : out std_ulogic; -- clear/BIST/wake/RMW in progress
    err_irq_o        : out std_ulogic; -- bus error or ECC event (pulse)

    -- ECC (ECC_EN)
    ecc_inj_i        : in  std_ulogic_vector(1 downto 0); -- arm 1-bit (0) / 2-bit (1) error
    ecc_corr_o       : out std_ulogic;                    -- corrected error (pulse)
    ecc_uncorr_o     : out std_ulogic;                    -- uncorrectable error (pulse)

    -- BIST (BIST_EN)
    bist_start_i     : in  std_ulogic;                                  -- start March C- (pulse)
    bist_done_o      : out std_ulogic;                                  -- test finished (pulse)
    bist_fail_o      : out std_ulogic;                                  -- a word failed
    bist_fail_addr_o : out std_ulogic_vector(clog2(DEPTH) - 1 downto 0) -- first failing word
  );
end entity sram_core;

architecture rtl of sram_core is

  constant NPD_C           : positive := num_domains(BANK_PG, NUM_BANKS);
  constant IDX_W_C         : positive := clog2(DEPTH);
  constant MW_C            : positive := mem_width(WIDTH, ECC_EN);
  constant NLANES_C        : positive := num_lanes(WIDTH, BYTE_EN, ECC_EN);
  constant BANKS_PER_DOM_C : positive := NUM_BANKS / NPD_C;

  signal dom_awake    : std_ulogic_vector(NPD_C - 1 downto 0);
  signal dom_ok       : std_ulogic_vector(NPD_C - 1 downto 0);
  signal dom_err      : std_ulogic_vector(NPD_C - 1 downto 0);
  signal dom_wakeable : std_ulogic_vector(NPD_C - 1 downto 0);
  signal dom_busy     : std_ulogic_vector(NPD_C - 1 downto 0);
  signal dom_clr_req  : std_ulogic_vector(NPD_C - 1 downto 0);
  signal dom_clr_done : std_ulogic_vector(NPD_C - 1 downto 0);
  signal dom_pwr_busy : std_ulogic_vector(NPD_C - 1 downto 0);
  signal port_wake    : std_ulogic_vector(NPD_C - 1 downto 0);
  signal clr_wake     : std_ulogic_vector(NPD_C - 1 downto 0);
  signal dom_ls       : std_ulogic_vector(NPD_C - 1 downto 0);
  signal dom_ds       : std_ulogic_vector(NPD_C - 1 downto 0);
  signal dom_sd       : std_ulogic_vector(NPD_C - 1 downto 0);
  signal port_idle    : std_ulogic;
  signal port_busy    : std_ulogic;
  signal port_stall   : std_ulogic;

  -- Per-port signals (A = mem_*, B = mem_b_*)
  signal a_wake       : std_ulogic_vector(NPD_C - 1 downto 0);
  signal b_wake       : std_ulogic_vector(NPD_C - 1 downto 0);
  signal a_dom_busy   : std_ulogic_vector(NPD_C - 1 downto 0);
  signal b_dom_busy   : std_ulogic_vector(NPD_C - 1 downto 0);
  signal a_idle       : std_ulogic;
  signal b_idle       : std_ulogic;
  signal a_busy       : std_ulogic;
  signal b_busy       : std_ulogic;
  signal a_stall      : std_ulogic;
  signal b_stall      : std_ulogic;
  signal a_ecc_corr   : std_ulogic;
  signal b_ecc_corr   : std_ulogic;
  signal a_ecc_uncorr : std_ulogic;
  signal b_ecc_uncorr : std_ulogic;
  signal a_irq        : std_ulogic;
  signal b_irq        : std_ulogic;
  signal a_req_idx    : std_ulogic_vector(IDX_W_C - 1 downto 0);
  signal b_req_idx    : std_ulogic_vector(IDX_W_C - 1 downto 0);
  signal a_rmw_idx    : std_ulogic_vector(IDX_W_C - 1 downto 0);
  signal b_rmw_idx    : std_ulogic_vector(IDX_W_C - 1 downto 0);
  signal a_req_we     : std_ulogic;
  signal b_req_we     : std_ulogic;
  signal a_acc        : std_ulogic;
  signal b_acc        : std_ulogic;
  signal a_rmw_pend   : std_ulogic;
  signal b_rmw_pend   : std_ulogic;
  signal b_cs         : std_ulogic;
  signal b_we         : std_ulogic;
  signal b_idx        : std_ulogic_vector(IDX_W_C - 1 downto 0);
  signal b_wdata      : std_ulogic_vector(MW_C - 1 downto 0);
  signal b_rdata      : std_ulogic_vector(MW_C - 1 downto 0);
  signal b_lane_we    : std_ulogic_vector(NLANES_C - 1 downto 0);

  signal clr_pending  : std_ulogic;
  signal clr_busy     : std_ulogic;
  signal clr_cs       : std_ulogic;
  signal clr_idx      : std_ulogic_vector(IDX_W_C - 1 downto 0);
  signal clr_idle     : std_ulogic;

  signal bist_pending : std_ulogic;
  signal bist_busy    : std_ulogic;
  signal bist_active  : std_ulogic;
  signal bist_force   : std_ulogic;
  signal bist_cs      : std_ulogic;
  signal bist_we      : std_ulogic;
  signal bist_idx     : std_ulogic_vector(IDX_W_C - 1 downto 0);
  signal bist_wdata   : std_ulogic_vector(MW_C - 1 downto 0);
  signal bist_all_ok  : std_ulogic;

  signal p_cs         : std_ulogic;
  signal p_we         : std_ulogic;
  signal p_idx        : std_ulogic_vector(IDX_W_C - 1 downto 0);
  signal p_wdata      : std_ulogic_vector(MW_C - 1 downto 0);
  signal p_lane_we    : std_ulogic_vector(NLANES_C - 1 downto 0);

  signal arr_cs       : std_ulogic;
  signal arr_we       : std_ulogic;
  signal arr_idx      : std_ulogic_vector(IDX_W_C - 1 downto 0);
  signal arr_wdata    : std_ulogic_vector(MW_C - 1 downto 0);
  signal arr_rdata    : std_ulogic_vector(MW_C - 1 downto 0);
  signal arr_lane_we  : std_ulogic_vector(NLANES_C - 1 downto 0);

  signal bank_ls      : std_ulogic_vector(NUM_BANKS - 1 downto 0);
  signal bank_ds      : std_ulogic_vector(NUM_BANKS - 1 downto 0);
  signal bank_sd      : std_ulogic_vector(NUM_BANKS - 1 downto 0);

begin

  -- Parameter checks (elaboration time).
  assert_width_a : assert WIDTH mod 8 = 0 and WIDTH >= 8 and WIDTH <= 128
      report "sram_core: WIDTH must be a multiple of 8 in 8..128" severity failure;
  assert_depth_a : assert DEPTH >= 2 and 2 ** clog2(DEPTH) = DEPTH
      report "sram_core: DEPTH must be a power of two >= 2" severity failure;
  assert_banks_a : assert 2 ** clog2(NUM_BANKS) = NUM_BANKS and NUM_BANKS <= DEPTH / 2
      report "sram_core: NUM_BANKS must be a power of two <= DEPTH/2" severity failure;
  assert_rl_a : assert READ_LATENCY = 1 or READ_LATENCY = 2
      report "sram_core: READ_LATENCY must be 1 or 2" severity failure;
  assert_bankpg_a : assert BANK_PG = 0 or PWR_GATE /= 0
      report "sram_core: BANK_PG needs PWR_GATE" severity failure;

  ---------------
  -- Bus port --
  ---------------
  port_stall <= clr_pending or bist_pending;

  -- A waits while B's read-modify-write of the same word is pending.
  a_stall <= '1' when port_stall = '1' or
                      (DUAL_PORT /= 0 and b_rmw_pend = '1' and a_req_idx = b_rmw_idx) else '0';

  u_port : entity work.sram_port(rtl)
    generic map (
      ADDR_W         => ADDR_W,
      WIDTH          => WIDTH,
      DEPTH          => DEPTH,
      BYTE_EN        => BYTE_EN,
      PARTIAL_WR_ERR => PARTIAL_WR_ERR,
      READ_LATENCY   => READ_LATENCY,
      ECC_EN         => ECC_EN,
      NPD            => NPD_C
    )
    port map (
      clk           => clk,
      rst_n         => rst_n,
      mem_req_i     => mem_req_i,
      mem_gnt_o     => mem_gnt_o,
      mem_we_i      => mem_we_i,
      mem_addr_i    => mem_addr_i,
      mem_be_i      => mem_be_i,
      mem_wdata_i   => mem_wdata_i,
      mem_rvalid_o  => mem_rvalid_o,
      mem_rdata_o   => mem_rdata_o,
      mem_err_o     => mem_err_o,
      dom_awake_i   => dom_awake,
      dom_err_i     => dom_err,
      stall_i       => a_stall,
      wake_o        => a_wake,
      dom_busy_o    => a_dom_busy,
      idle_o        => a_idle,
      req_idx_o     => a_req_idx,
      req_we_o      => a_req_we,
      acc_o         => a_acc,
      rmw_pend_o    => a_rmw_pend,
      rmw_idx_o     => a_rmw_idx,
      arr_cs_o      => p_cs,
      arr_we_o      => p_we,
      arr_idx_o     => p_idx,
      arr_wdata_o   => p_wdata,
      arr_lane_we_o => p_lane_we,
      arr_rdata_i   => arr_rdata,
      ecc_inj_i     => ecc_inj_i,
      ecc_corr_o    => a_ecc_corr,
      ecc_uncorr_o  => a_ecc_uncorr,
      err_irq_o     => a_irq,
      busy_o        => a_busy
    );

  -----------------------------------------------------
  -- Bus port B (DUAL_PORT) and same-word conflicts --
  -----------------------------------------------------
  gen_port_b : if DUAL_PORT /= 0 generate
    -- B waits when A accesses the same word this cycle and either writes, or
    -- while A's read-modify-write of that word is pending.
    b_stall <= '1' when port_stall = '1' or
                        (a_acc = '1' and a_req_idx = b_req_idx and
                         (a_req_we = '1' or b_req_we = '1')) or
                        (a_rmw_pend = '1' and b_req_idx = a_rmw_idx) else '0';

    u_port_b : entity work.sram_port(rtl)
      generic map (
        ADDR_W         => ADDR_W,
        WIDTH          => WIDTH,
        DEPTH          => DEPTH,
        BYTE_EN        => BYTE_EN,
        PARTIAL_WR_ERR => PARTIAL_WR_ERR,
        READ_LATENCY   => READ_LATENCY,
        ECC_EN         => ECC_EN,
        NPD            => NPD_C,
        READ_ONLY      => boolean'pos(TECH = TECH_SKY130_C)
      )
      port map (
        clk           => clk,
        rst_n         => rst_n,
        mem_req_i     => mem_b_req_i,
        mem_gnt_o     => mem_b_gnt_o,
        mem_we_i      => mem_b_we_i,
        mem_addr_i    => mem_b_addr_i,
        mem_be_i      => mem_b_be_i,
        mem_wdata_i   => mem_b_wdata_i,
        mem_rvalid_o  => mem_b_rvalid_o,
        mem_rdata_o   => mem_b_rdata_o,
        mem_err_o     => mem_b_err_o,
        dom_awake_i   => dom_awake,
        dom_err_i     => dom_err,
        stall_i       => b_stall,
        wake_o        => b_wake,
        dom_busy_o    => b_dom_busy,
        idle_o        => b_idle,
        req_idx_o     => b_req_idx,
        req_we_o      => b_req_we,
        acc_o         => b_acc,
        rmw_pend_o    => b_rmw_pend,
        rmw_idx_o     => b_rmw_idx,
        arr_cs_o      => b_cs,
        arr_we_o      => b_we,
        arr_idx_o     => b_idx,
        arr_wdata_o   => b_wdata,
        arr_lane_we_o => b_lane_we,
        arr_rdata_i   => b_rdata,
        ecc_inj_i     => "00",
        ecc_corr_o    => b_ecc_corr,
        ecc_uncorr_o  => b_ecc_uncorr,
        err_irq_o     => b_irq,
        busy_o        => b_busy
      );
  else generate
    b_stall        <= '0';
    mem_b_gnt_o    <= '0';
    mem_b_rvalid_o <= '0';
    mem_b_rdata_o  <= (others => '0');
    mem_b_err_o    <= '0';
    b_wake         <= (others => '0');
    b_dom_busy     <= (others => '0');
    b_idle         <= '1';
    b_req_idx      <= (others => '0');
    b_req_we       <= '0';
    b_acc          <= '0';
    b_rmw_pend     <= '0';
    b_rmw_idx      <= (others => '0');
    b_cs           <= '0';
    b_we           <= '0';
    b_idx          <= (others => '0');
    b_wdata        <= (others => '0');
    b_lane_we      <= (others => '0');
    b_ecc_corr     <= '0';
    b_ecc_uncorr   <= '0';
    b_irq          <= '0';
    b_busy         <= '0';
  end generate gen_port_b;

  port_wake    <= a_wake or b_wake;
  dom_busy     <= a_dom_busy or b_dom_busy;
  port_idle    <= a_idle and b_idle;
  port_busy    <= a_busy or b_busy;
  ecc_corr_o   <= a_ecc_corr or b_ecc_corr;
  ecc_uncorr_o <= a_ecc_uncorr or b_ecc_uncorr;
  err_irq_o    <= a_irq or b_irq;

  -------------------
  -- Power domains --
  -------------------
  gen_dom : for d in 0 to NPD_C - 1 generate
    signal req     : std_ulogic_vector(1 downto 0); -- requested mode (RUN while BIST)
    signal wake    : std_ulogic;
    signal idle    : std_ulogic;
  begin
    req <= PWR_RUN_C when bist_force = '1' else pwr_mode_req_i(2 * d + 1 downto 2 * d);

    -- Access to a domain requested into deep sleep or shutdown is an error;
    -- a domain requested RUN or light sleep may be woken.
    dom_err(d) <= '1' when PWR_GATE /= 0 and
                           (pwr_mode_req_i(2 * d + 1 downto 2 * d) = PWR_DS_C or
                            pwr_mode_req_i(2 * d + 1 downto 2 * d) = PWR_SD_C) else '0';
    dom_wakeable(d) <= not dom_err(d);
    wake            <= port_wake(d) or clr_wake(d);
    idle            <= not dom_busy(d);

    u_pwr : entity work.sram_pwr_ctrl(rtl)
      generic map (
        PWR_GATE  => PWR_GATE,
        ENTER_CYC => pwr_enter_cycles(TECH),
        WAKE_LS   => pwr_wake_cycles(TECH, 1),
        WAKE_DS   => pwr_wake_cycles(TECH, 2),
        WAKE_SD   => pwr_wake_cycles(TECH, 3)
      )
      port map (
        clk         => clk,
        rst_n       => rst_n,
        mode_req_i  => req,
        wake_i      => wake,
        idle_i      => idle,
        clr_done_i  => dom_clr_done(d),
        ls_o        => dom_ls(d),
        ds_o        => dom_ds(d),
        sd_o        => dom_sd(d),
        awake_o     => dom_awake(d),
        engine_ok_o => dom_ok(d),
        clr_req_o   => dom_clr_req(d),
        busy_o      => dom_pwr_busy(d),
        ack_o       => pwr_mode_ack_o(2 * d + 1 downto 2 * d)
      );
  end generate gen_dom;

  ------------------
  -- Clear engine --
  ------------------
  -- Not while the march uses the array; a clear needed while BIST waits for
  -- power (shutdown -> RUN) must still run, or BIST would wait forever.
  clr_idle <= port_idle and not bist_active;

  -- With ECC every word must hold a valid codeword before it is read, so the
  -- array is cleared after reset (bus requests stall until it is done).
  u_clr : entity work.sram_clr(rtl)
    generic map (
      DEPTH          => DEPTH,
      NPD            => NPD_C,
      CLEAR_ON_RESET => ECC_EN
    )
    port map (
      clk         => clk,
      rst_n       => rst_n,
      start_i     => clr_req_i,
      mask_i      => (others => '1'),
      auto_i      => dom_clr_req,
      port_idle_i => clr_idle,
      ok_i        => dom_ok,
      wakeable_i  => dom_wakeable,
      wake_o      => clr_wake,
      pending_o   => clr_pending,
      busy_o      => clr_busy,
      done_o      => clr_done_o,
      dom_done_o  => dom_clr_done,
      cs_o        => clr_cs,
      idx_o       => clr_idx
    );

  ----------
  -- BIST --
  ----------
  gen_bist : if BIST_EN /= 0 generate
    bist_all_ok <= '1' when dom_awake = (dom_awake'range => '1') and clr_pending = '0' else '0';

    u_bist : entity work.sram_bist(rtl)
      generic map (
        DEPTH => DEPTH,
        MW    => MW_C
      )
      port map (
        clk         => clk,
        rst_n       => rst_n,
        start_i     => bist_start_i,
        port_idle_i => port_idle,
        all_ok_i    => bist_all_ok,
        pending_o   => bist_pending,
        force_run_o => bist_force,
        busy_o      => bist_busy,
        active_o    => bist_active,
        done_o      => bist_done_o,
        fail_o      => bist_fail_o,
        fail_idx_o  => bist_fail_addr_o,
        cs_o        => bist_cs,
        we_o        => bist_we,
        idx_o       => bist_idx,
        wdata_o     => bist_wdata,
        rdata_i     => arr_rdata
      );
  else generate
    bist_all_ok      <= '0';
    bist_pending     <= '0';
    bist_force       <= '0';
    bist_busy        <= '0';
    bist_active      <= '0';
    bist_done_o      <= '0';
    bist_fail_o      <= '0';
    bist_fail_addr_o <= (others => '0');
    bist_cs          <= '0';
    bist_we          <= '0';
    bist_idx         <= (others => '0');
    bist_wdata       <= (others => '0');
  end generate gen_bist;

  --------------------------------------------------------
  -- Array ownership: BIST, then clear engine, then port --
  --------------------------------------------------------
  p_arbiter : process (all) is
  begin
    if bist_cs = '1' then
      arr_cs      <= '1';
      arr_we      <= bist_we;
      arr_idx     <= bist_idx;
      arr_wdata   <= bist_wdata;
      arr_lane_we <= (others => '1');
    elsif clr_cs = '1' then
      arr_cs      <= '1';
      arr_we      <= '1';
      arr_idx     <= clr_idx;
      arr_wdata   <= (others => '0'); -- all-zero is also the SECDED codeword of zero
      arr_lane_we <= (others => '1');
    else
      arr_cs      <= p_cs;
      arr_we      <= p_we;
      arr_idx     <= p_idx;
      arr_wdata   <= p_wdata;
      arr_lane_we <= p_lane_we;
    end if;
  end process p_arbiter;

  -- Sleep pins per bank from the bank's domain.
  gen_bank_pins : for b in 0 to NUM_BANKS - 1 generate
    bank_ls(b) <= dom_ls(b / BANKS_PER_DOM_C);
    bank_ds(b) <= dom_ds(b / BANKS_PER_DOM_C);
    bank_sd(b) <= dom_sd(b / BANKS_PER_DOM_C);
  end generate gen_bank_pins;

  u_array : entity work.sram_array(rtl)
    generic map (
      TECH      => TECH,
      MW        => MW_C,
      DEPTH     => DEPTH,
      NUM_BANKS => NUM_BANKS,
      NLANES    => NLANES_C,
      DUAL_PORT => DUAL_PORT,
      INIT_FILE => INIT_FILE
    )
    port map (
      clk       => clk,
      cs_i      => arr_cs,
      we_i      => arr_we,
      idx_i     => arr_idx,
      wdata_i   => arr_wdata,
      lane_we_i => arr_lane_we,
      ls_i      => bank_ls,
      ds_i      => bank_ds,
      sd_i        => bank_sd,
      rdata_o     => arr_rdata,
      b_cs_i      => b_cs,
      b_we_i      => b_we,
      b_idx_i     => b_idx,
      b_wdata_i   => b_wdata,
      b_lane_we_i => b_lane_we,
      b_rdata_o   => b_rdata
    );

  busy_o <= '1' when clr_pending = '1' or bist_busy = '1' or
                     unsigned(dom_pwr_busy) /= 0 or port_busy = '1' else '0';

end architecture rtl;
