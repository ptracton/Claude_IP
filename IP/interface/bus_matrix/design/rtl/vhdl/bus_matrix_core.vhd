-- bus_matrix_core.vhd — Bus Matrix protocol-agnostic crossbar core (VHDL-2008).
--
-- Routes transactions from NUM_MASTERS master ports to NUM_SLAVES slave ports.
-- Instantiates one bus_matrix_decoder per master and one bus_matrix_arb per slave.
-- All configuration via generics — no runtime registers.
-- Mirrors bus_matrix_core.sv.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bus_matrix_core is
  generic (
    NUM_MASTERS : positive := 2;
    NUM_SLAVES  : positive := 2;
    DATA_W      : positive := 32;
    ADDR_W      : positive := 32;
    ARB_MODE    : natural  := 0;
    M_PRIORITY  : std_ulogic_vector(16*4-1 downto 0)  := (others => '0');
    S_BASE      : std_ulogic_vector(32*32-1 downto 0) := (others => '0');
    S_MASK      : std_ulogic_vector(32*32-1 downto 0) := (others => '0')
  );
  port (
    clk        : in  std_ulogic;
    rst_n      : in  std_ulogic;

    mst_req    : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    mst_addr   : in  std_ulogic_vector(NUM_MASTERS * ADDR_W - 1 downto 0);
    mst_wdata  : in  std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);
    mst_we     : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    mst_be     : in  std_ulogic_vector(NUM_MASTERS * 4 - 1 downto 0);
    mst_gnt    : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    mst_rdata  : out std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);
    mst_rvalid : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    mst_err    : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);

    slv_req    : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    slv_addr   : out std_ulogic_vector(NUM_SLAVES * ADDR_W - 1 downto 0);
    slv_wdata  : out std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);
    slv_we     : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    slv_be     : out std_ulogic_vector(NUM_SLAVES * 4 - 1 downto 0);
    slv_gnt    : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    slv_rdata  : in  std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);
    slv_rvalid : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0)
  );
end entity bus_matrix_core;

architecture rtl of bus_matrix_core is

  component bus_matrix_decoder is
    generic (
      NUM_SLAVES : positive;
      ADDR_W     : positive;
      S_BASE     : std_ulogic_vector(32*32-1 downto 0);
      S_MASK     : std_ulogic_vector(32*32-1 downto 0)
    );
    port (
      addr       : in  std_ulogic_vector(ADDR_W - 1 downto 0);
      slave_sel  : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);
      decode_err : out std_ulogic
    );
  end component bus_matrix_decoder;

  component bus_matrix_arb is
    generic (
      NUM_MASTERS : positive;
      ARB_MODE    : natural;
      M_PRIORITY  : std_ulogic_vector(16*4-1 downto 0)
    );
    port (
      clk       : in  std_ulogic;
      rst_n     : in  std_ulogic;
      req       : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);
      valid_trx : in  std_ulogic;
      slv_gnt   : in  std_ulogic;
      gnt       : out std_ulogic_vector(NUM_MASTERS - 1 downto 0)
    );
  end component bus_matrix_arb;

  type slv_sel_array_t is array (0 to NUM_MASTERS - 1) of
    std_ulogic_vector(NUM_SLAVES - 1 downto 0);
  type mst_req_array_t is array (0 to NUM_SLAVES - 1) of
    std_ulogic_vector(NUM_MASTERS - 1 downto 0);

  signal dec_slave_sel : slv_sel_array_t;
  signal dec_err       : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
  signal per_slv_req   : mst_req_array_t;
  signal arb_gnt       : mst_req_array_t;
  signal valid_trx_slv : std_ulogic_vector(NUM_SLAVES - 1 downto 0);

begin

  -- Decoders (one per master)
  gen_dec : for gi in 0 to NUM_MASTERS - 1 generate
    u_dec : bus_matrix_decoder
      generic map (
        NUM_SLAVES => NUM_SLAVES,
        ADDR_W     => ADDR_W,
        S_BASE     => S_BASE,
        S_MASK     => S_MASK
      )
      port map (
        addr       => mst_addr((gi+1)*ADDR_W-1 downto gi*ADDR_W),
        slave_sel  => dec_slave_sel(gi),
        decode_err => dec_err(gi)
      );
  end generate gen_dec;

  -- Per-slave request vectors
  p_per_slv_req : process(mst_req, dec_slave_sel) is
  begin
    for j in 0 to NUM_SLAVES - 1 loop
      per_slv_req(j) <= (others => '0');
      for i in 0 to NUM_MASTERS - 1 loop
        per_slv_req(j)(i) <= mst_req(i) and dec_slave_sel(i)(j);
      end loop;
    end loop;
  end process p_per_slv_req;

  -- Arbiters (one per slave)
  valid_trx_slv <= slv_req;

  gen_arb : for gi in 0 to NUM_SLAVES - 1 generate
    u_arb : bus_matrix_arb
      generic map (
        NUM_MASTERS => NUM_MASTERS,
        ARB_MODE    => ARB_MODE,
        M_PRIORITY  => M_PRIORITY
      )
      port map (
        clk       => clk,
        rst_n     => rst_n,
        req       => per_slv_req(gi),
        valid_trx => valid_trx_slv(gi),
        slv_gnt   => slv_gnt(gi),
        gnt       => arb_gnt(gi)
      );
  end generate gen_arb;

  -- Route master requests to slave ports
  p_slave_route : process(arb_gnt, mst_addr, mst_wdata, mst_we, mst_be) is
  begin
    slv_req   <= (others => '0');
    slv_addr  <= (others => '0');
    slv_wdata <= (others => '0');
    slv_we    <= (others => '0');
    slv_be    <= (others => '0');

    for j in 0 to NUM_SLAVES - 1 loop
      for i in 0 to NUM_MASTERS - 1 loop
        if arb_gnt(j)(i) = '1' then
          slv_req(j) <= '1';
          slv_addr((j+1)*ADDR_W-1 downto j*ADDR_W) <=
            mst_addr((i+1)*ADDR_W-1 downto i*ADDR_W);
          slv_wdata((j+1)*DATA_W-1 downto j*DATA_W) <=
            mst_wdata((i+1)*DATA_W-1 downto i*DATA_W);
          slv_we(j) <= mst_we(i);
          slv_be((j+1)*4-1 downto j*4) <=
            mst_be((i+1)*4-1 downto i*4);
        end if;
      end loop;
    end loop;
  end process p_slave_route;

  -- Route slave responses to masters
  p_master_resp : process(mst_req, dec_err, arb_gnt,
                          slv_gnt, slv_rdata, slv_rvalid) is
  begin
    mst_gnt    <= (others => '0');
    mst_rdata  <= (others => '0');
    mst_rvalid <= (others => '0');
    mst_err    <= (others => '0');

    -- Decode error response
    for i in 0 to NUM_MASTERS - 1 loop
      if mst_req(i) = '1' and dec_err(i) = '1' then
        mst_err(i) <= '1';
        mst_gnt(i) <= '1';
      end if;
    end loop;

    -- Slave responses
    for j in 0 to NUM_SLAVES - 1 loop
      for i in 0 to NUM_MASTERS - 1 loop
        if arb_gnt(j)(i) = '1' then
          mst_gnt(i) <= slv_gnt(j);
          mst_rdata((i+1)*DATA_W-1 downto i*DATA_W) <=
            slv_rdata((j+1)*DATA_W-1 downto j*DATA_W);
          mst_rvalid(i) <= slv_rvalid(j);
        end if;
      end loop;
    end loop;
  end process p_master_resp;

end architecture rtl;
