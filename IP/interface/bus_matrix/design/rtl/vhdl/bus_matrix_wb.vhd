-- bus_matrix_wb.vhd — Wishbone B4 bus matrix top-level (VHDL-2008).
--
-- Crossbar interconnect connecting NUM_MASTERS Wishbone masters to NUM_SLAVES
-- Wishbone slaves. All configuration via generics; no runtime registers.
-- Mirrors bus_matrix_wb.sv.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bus_matrix_wb is
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
    clk    : in  std_ulogic;
    rst_n  : in  std_ulogic;

    -- Master input ports (Wishbone B4 slave-facing, flat-packed)
    M_CYC   : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    M_STB   : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    M_WE    : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    M_ADR   : in  std_ulogic_vector(NUM_MASTERS * ADDR_W - 1 downto 0);
    M_DAT_I : in  std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);
    M_SEL   : in  std_ulogic_vector(NUM_MASTERS * 4 - 1 downto 0);
    M_DAT_O : out std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);
    M_ACK   : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    M_ERR   : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);

    -- Slave output ports (Wishbone B4 master-facing, flat-packed)
    S_CYC   : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    S_STB   : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    S_WE    : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    S_ADR   : out std_ulogic_vector(NUM_SLAVES * ADDR_W - 1 downto 0);
    S_DAT_O : out std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);
    S_SEL   : out std_ulogic_vector(NUM_SLAVES * 4 - 1 downto 0);
    S_DAT_I : in  std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);
    S_ACK   : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    S_ERR   : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0)
  );
end entity bus_matrix_wb;

architecture rtl of bus_matrix_wb is

  component bus_matrix_core is
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
  end component bus_matrix_core;

  -- Internal protocol wires
  signal mst_req_i    : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
  signal mst_addr_i   : std_ulogic_vector(NUM_MASTERS * ADDR_W - 1 downto 0);
  signal mst_wdata_i  : std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);
  signal mst_we_i     : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
  signal mst_be_i     : std_ulogic_vector(NUM_MASTERS * 4 - 1 downto 0);
  signal mst_gnt_i    : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
  signal mst_rdata_i  : std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);
  signal mst_rvalid_i : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
  signal mst_err_i    : std_ulogic_vector(NUM_MASTERS - 1 downto 0);

  signal slv_req_i    : std_ulogic_vector(NUM_SLAVES - 1 downto 0);
  signal slv_addr_i   : std_ulogic_vector(NUM_SLAVES * ADDR_W - 1 downto 0);
  signal slv_wdata_i  : std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);
  signal slv_we_i     : std_ulogic_vector(NUM_SLAVES - 1 downto 0);
  signal slv_be_i     : std_ulogic_vector(NUM_SLAVES * 4 - 1 downto 0);
  signal slv_gnt_i    : std_ulogic_vector(NUM_SLAVES - 1 downto 0);
  signal slv_rdata_i  : std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);
  signal slv_rvalid_i : std_ulogic_vector(NUM_SLAVES - 1 downto 0);

  -- WB master adapter state
  signal wb_stb_prev_q : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
  signal wb_pending_q  : std_ulogic_vector(NUM_MASTERS - 1 downto 0);

begin

  -- Master-side Wishbone adapter
  gen_mst : for gi in 0 to NUM_MASTERS - 1 generate
    p_mst_wb : process(clk) is
    begin
      if rising_edge(clk) then
        if rst_n = '0' then
          wb_stb_prev_q(gi) <= '0';
          wb_pending_q(gi)  <= '0';
        else
          wb_stb_prev_q(gi) <= M_CYC(gi) and M_STB(gi) and not wb_stb_prev_q(gi);
          if M_CYC(gi) = '1' and M_STB(gi) = '1' and wb_stb_prev_q(gi) = '0' then
            wb_pending_q(gi) <= '1';
          elsif mst_gnt_i(gi) = '1' then
            wb_pending_q(gi) <= '0';
          end if;
        end if;
      end if;
    end process p_mst_wb;

    mst_req_i(gi) <= wb_pending_q(gi);
    mst_addr_i((gi+1)*ADDR_W-1 downto gi*ADDR_W) <=
      M_ADR((gi+1)*ADDR_W-1 downto gi*ADDR_W);
    mst_wdata_i((gi+1)*DATA_W-1 downto gi*DATA_W) <=
      M_DAT_I((gi+1)*DATA_W-1 downto gi*DATA_W);
    mst_we_i(gi) <= M_WE(gi);
    mst_be_i((gi+1)*4-1 downto gi*4) <=
      M_SEL((gi+1)*4-1 downto gi*4);

    M_ACK(gi) <= mst_gnt_i(gi);
    M_ERR(gi) <= mst_err_i(gi);
    M_DAT_O((gi+1)*DATA_W-1 downto gi*DATA_W) <=
      mst_rdata_i((gi+1)*DATA_W-1 downto gi*DATA_W);
  end generate gen_mst;

  -- Slave-side Wishbone adapter
  gen_slv : for gi in 0 to NUM_SLAVES - 1 generate
    S_CYC(gi) <= slv_req_i(gi);
    S_STB(gi) <= slv_req_i(gi);
    S_WE(gi)  <= slv_we_i(gi);
    S_ADR((gi+1)*ADDR_W-1 downto gi*ADDR_W) <=
      slv_addr_i((gi+1)*ADDR_W-1 downto gi*ADDR_W);
    S_DAT_O((gi+1)*DATA_W-1 downto gi*DATA_W) <=
      slv_wdata_i((gi+1)*DATA_W-1 downto gi*DATA_W);
    S_SEL((gi+1)*4-1 downto gi*4) <=
      slv_be_i((gi+1)*4-1 downto gi*4);

    slv_gnt_i(gi) <= S_ACK(gi);
    slv_rdata_i((gi+1)*DATA_W-1 downto gi*DATA_W) <=
      S_DAT_I((gi+1)*DATA_W-1 downto gi*DATA_W);
    slv_rvalid_i(gi) <= S_ACK(gi) and not slv_we_i(gi);
  end generate gen_slv;

  -- Core
  u_core : bus_matrix_core
    generic map (
      NUM_MASTERS => NUM_MASTERS,
      NUM_SLAVES  => NUM_SLAVES,
      DATA_W      => DATA_W,
      ADDR_W      => ADDR_W,
      ARB_MODE    => ARB_MODE,
      M_PRIORITY  => M_PRIORITY,
      S_BASE      => S_BASE,
      S_MASK      => S_MASK
    )
    port map (
      clk        => clk,
      rst_n      => rst_n,
      mst_req    => mst_req_i,
      mst_addr   => mst_addr_i,
      mst_wdata  => mst_wdata_i,
      mst_we     => mst_we_i,
      mst_be     => mst_be_i,
      mst_gnt    => mst_gnt_i,
      mst_rdata  => mst_rdata_i,
      mst_rvalid => mst_rvalid_i,
      mst_err    => mst_err_i,
      slv_req    => slv_req_i,
      slv_addr   => slv_addr_i,
      slv_wdata  => slv_wdata_i,
      slv_we     => slv_we_i,
      slv_be     => slv_be_i,
      slv_gnt    => slv_gnt_i,
      slv_rdata  => slv_rdata_i,
      slv_rvalid => slv_rvalid_i
    );

end architecture rtl;
