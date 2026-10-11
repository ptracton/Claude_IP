-- bus_matrix_core.vhd — Bus Matrix protocol-agnostic crossbar core (VHDL-2008).
--
-- Routes transactions from NUM_MASTERS master ports to NUM_SLAVES slave ports.
-- One bus_matrix_decoder per master selects the target slave; one
-- bus_matrix_arb per slave picks and locks an owner.
--
-- Internal handshake (identical on every protocol variant):
--   Master side: a target adapter raises mst_req(i) and holds it, together
--     with mst_addr/wdata/we/be, until mst_done(i) pulses for one cycle.
--     mst_rdata(i) and mst_err(i) are valid in that cycle.
--   Slave side: slv_req(j) is high while slave j is granted to a requesting
--     master; its initiator adapter runs exactly one bus transaction and
--     pulses slv_done(j) (with slv_rdata(j), slv_err(j)) when it completes.
--   Decode error: a request that matches no slave never reaches an arbiter;
--     the core answers it itself with mst_done + mst_err one cycle later.
-- Mirrors bus_matrix_core.sv.

library ieee;
use ieee.std_logic_1164.all;

entity bus_matrix_core is
  generic (
    NUM_MASTERS : positive := 2;   -- 1-16 active masters
    NUM_SLAVES  : positive := 4;   -- 1-32 active slaves
    DATA_W      : positive := 32;  -- data bus width
    ADDR_W      : positive := 32;  -- address width (must be 32)
    ARB_MODE    : natural  := 0;   -- 0=fixed-priority, 1=round-robin
    M_PRIORITY  : std_ulogic_vector(16 * 4 - 1 downto 0)  := (others => '0');
    S_BASE      : std_ulogic_vector(32 * 32 - 1 downto 0) := (others => '0');
    S_MASK      : std_ulogic_vector(32 * 32 - 1 downto 0) := (others => '0')
  );
  port (
    clk       : in  std_ulogic;  -- system clock
    rst_n     : in  std_ulogic;  -- synchronous active-low reset

    -- Master side (from target adapters), master i at (i*W+W-1 downto i*W)
    mst_req   : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    mst_addr  : in  std_ulogic_vector(NUM_MASTERS * ADDR_W - 1 downto 0);
    mst_wdata : in  std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);
    mst_we    : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    mst_be    : in  std_ulogic_vector(NUM_MASTERS * DATA_W / 8 - 1 downto 0);
    mst_done  : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    mst_rdata : out std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);
    mst_err   : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);

    -- Slave side (to initiator adapters), slave j at (j*W+W-1 downto j*W)
    slv_req   : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    slv_addr  : out std_ulogic_vector(NUM_SLAVES * ADDR_W - 1 downto 0);
    slv_wdata : out std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);
    slv_we    : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    slv_be    : out std_ulogic_vector(NUM_SLAVES * DATA_W / 8 - 1 downto 0);
    slv_done  : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    slv_rdata : in  std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);
    slv_err   : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0)
  );
end entity bus_matrix_core;

architecture rtl of bus_matrix_core is

  constant STRB_W : positive := DATA_W / 8;
  constant NM     : positive := NUM_MASTERS;
  constant FLD_W  : positive := 1 + STRB_W + DATA_W + ADDR_W;  -- {we, be, wdata, addr}

  type fld_arr_t  is array (natural range <>) of std_ulogic_vector(FLD_W - 1 downto 0);
  type data_arr_t is array (natural range <>) of std_ulogic_vector(DATA_W - 1 downto 0);

  -- dec_sel(i*NUM_SLAVES + j) = master i selects slave j
  signal dec_sel  : std_ulogic_vector(NUM_MASTERS * NUM_SLAVES - 1 downto 0);
  signal dec_err  : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
  -- slv_mreq(j*NM + i) = master i requests slave j
  signal slv_mreq : std_ulogic_vector(NUM_SLAVES * NM - 1 downto 0);
  -- gnt(j*NM + i) = slave j is granted to master i
  signal gnt      : std_ulogic_vector(NUM_SLAVES * NM - 1 downto 0);
  signal derr_q   : std_ulogic_vector(NUM_MASTERS - 1 downto 0);

begin

  -- -------------------------------------------------------------------------
  -- Address decode: one decoder per master
  -- -------------------------------------------------------------------------
  gen_decoder : for gi in 0 to NUM_MASTERS - 1 generate
    u_dec : entity work.bus_matrix_decoder(rtl)
      generic map (
        NUM_SLAVES => NUM_SLAVES,
        ADDR_W     => ADDR_W,
        S_BASE     => S_BASE,
        S_MASK     => S_MASK
      )
      port map (
        addr       => mst_addr(gi * ADDR_W + ADDR_W - 1 downto gi * ADDR_W),
        slave_sel  => dec_sel(gi * NUM_SLAVES + NUM_SLAVES - 1 downto gi * NUM_SLAVES),
        decode_err => dec_err(gi)
      );
  end generate gen_decoder;

  -- -------------------------------------------------------------------------
  -- Per-slave request vectors
  -- -------------------------------------------------------------------------
  p_slv_mreq : process (mst_req, dec_sel) is
  begin
    for j in 0 to NUM_SLAVES - 1 loop
      for i in 0 to NUM_MASTERS - 1 loop
        slv_mreq(j * NM + i) <= mst_req(i) and dec_sel(i * NUM_SLAVES + j);
      end loop;
    end loop;
  end process p_slv_mreq;

  -- -------------------------------------------------------------------------
  -- Arbitration: one arbiter per slave
  -- -------------------------------------------------------------------------
  gen_arb : for gj in 0 to NUM_SLAVES - 1 generate
    u_arb : entity work.bus_matrix_arb(rtl)
      generic map (
        NUM_MASTERS => NUM_MASTERS,
        ARB_MODE    => ARB_MODE,
        M_PRIORITY  => M_PRIORITY
      )
      port map (
        clk   => clk,
        rst_n => rst_n,
        req   => slv_mreq(gj * NM + NM - 1 downto gj * NM),
        done  => slv_done(gj),
        gnt   => gnt(gj * NM + NM - 1 downto gj * NM)
      );
  end generate gen_arb;

  -- -------------------------------------------------------------------------
  -- Slave-side routing: AND-OR mux of the owner's request fields. The grant
  -- is one-hot, so OR-accumulating each master's gated fields along a chain
  -- selects the owner's. Fields packed as {we, be, wdata, addr}.
  -- -------------------------------------------------------------------------
  gen_route : for gj in 0 to NUM_SLAVES - 1 generate
    signal fld_acc : fld_arr_t(0 to NUM_MASTERS);  -- fld_acc(i) = OR of masters < i
    signal fld     : std_ulogic_vector(FLD_W - 1 downto 0);
  begin
    fld_acc(0) <= (others => '0');
    gen_m : for gi in 0 to NUM_MASTERS - 1 generate
      signal mfld : std_ulogic_vector(FLD_W - 1 downto 0);
    begin
      mfld <= mst_we(gi) &
              mst_be(gi * STRB_W + STRB_W - 1 downto gi * STRB_W) &
              mst_wdata(gi * DATA_W + DATA_W - 1 downto gi * DATA_W) &
              mst_addr(gi * ADDR_W + ADDR_W - 1 downto gi * ADDR_W);
      fld_acc(gi + 1) <= fld_acc(gi) or mfld when gnt(gj * NM + gi) = '1' else fld_acc(gi);
    end generate gen_m;

    fld <= fld_acc(NUM_MASTERS);

    -- Registered grant only: the owner holds its request until done and the
    -- grant clears on the done edge, so gating with the request is
    -- redundant and would put the address decoder in front of slv_req.
    slv_req(gj) <= '1' when gnt(gj * NM + NM - 1 downto gj * NM) /= (NM - 1 downto 0 => '0')
                   else '0';
    slv_we(gj)                                           <= fld(FLD_W - 1);
    slv_be(gj * STRB_W + STRB_W - 1 downto gj * STRB_W)  <= fld(ADDR_W + DATA_W + STRB_W - 1 downto ADDR_W + DATA_W);
    slv_wdata(gj * DATA_W + DATA_W - 1 downto gj * DATA_W) <= fld(ADDR_W + DATA_W - 1 downto ADDR_W);
    slv_addr(gj * ADDR_W + ADDR_W - 1 downto gj * ADDR_W)  <= fld(ADDR_W - 1 downto 0);
  end generate gen_route;

  -- -------------------------------------------------------------------------
  -- Decode-error responder: one-cycle done + err, the cycle after a request
  -- that matches no slave.
  -- -------------------------------------------------------------------------
  p_derr : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        derr_q <= (others => '0');
      else
        derr_q <= mst_req and dec_err and not derr_q;
      end if;
    end if;
  end process p_derr;

  -- -------------------------------------------------------------------------
  -- Master-side responses: master i takes the response of the slave it owns
  -- (at most one), or its own decode-error response.
  -- -------------------------------------------------------------------------
  gen_resp : for gi in 0 to NUM_MASTERS - 1 generate
    signal owns      : std_ulogic_vector(NUM_SLAVES - 1 downto 0);  -- master i holds slave j
    signal rdata_acc : data_arr_t(0 to NUM_SLAVES);                -- OR of slaves < j
  begin
    rdata_acc(0) <= (others => '0');
    gen_s : for gj in 0 to NUM_SLAVES - 1 generate
      owns(gj)          <= gnt(gj * NM + gi);
      rdata_acc(gj + 1) <= rdata_acc(gj) or slv_rdata(gj * DATA_W + DATA_W - 1 downto gj * DATA_W)
                           when owns(gj) = '1' else rdata_acc(gj);
    end generate gen_s;

    mst_done(gi) <= '1' when derr_q(gi) = '1' or (owns and slv_done) /= (owns'range => '0') else '0';
    mst_err(gi)  <= '1' when derr_q(gi) = '1' or (owns and slv_err) /= (owns'range => '0') else '0';
    mst_rdata(gi * DATA_W + DATA_W - 1 downto gi * DATA_W) <= rdata_acc(NUM_SLAVES);
  end generate gen_resp;

end architecture rtl;
