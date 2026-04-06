-- bus_matrix_ahb.vhd — AHB-Lite bus matrix top-level (VHDL-2008).
--
-- Crossbar interconnect connecting NUM_MASTERS AHB masters to NUM_SLAVES
-- AHB slaves. All configuration via generics; no runtime registers.
-- Mirrors bus_matrix_ahb.sv.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bus_matrix_ahb is
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

    M_HSEL   : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    M_HADDR  : in  std_ulogic_vector(NUM_MASTERS * ADDR_W - 1 downto 0);
    M_HTRANS : in  std_ulogic_vector(NUM_MASTERS * 2 - 1 downto 0);
    M_HWRITE : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    M_HWDATA : in  std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);
    M_HWSTRB : in  std_ulogic_vector(NUM_MASTERS * 4 - 1 downto 0);
    M_HREADY : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    M_HRDATA : out std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);
    M_HRESP  : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);

    S_HSEL   : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    S_HADDR  : out std_ulogic_vector(NUM_SLAVES * ADDR_W - 1 downto 0);
    S_HTRANS : out std_ulogic_vector(NUM_SLAVES * 2 - 1 downto 0);
    S_HWRITE : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    S_HWDATA : out std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);
    S_HWSTRB : out std_ulogic_vector(NUM_SLAVES * 4 - 1 downto 0);
    S_HREADY : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    S_HRDATA : in  std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);
    S_HRESP  : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0)
  );
end entity bus_matrix_ahb;

architecture rtl of bus_matrix_ahb is

  constant AHB_NONSEQ : std_ulogic_vector(1 downto 0) := "10";
  constant AHB_IDLE   : std_ulogic_vector(1 downto 0) := "00";

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

  -- AHB master adapter registers
  type addr_array_t is array (0 to NUM_MASTERS - 1) of
    std_ulogic_vector(ADDR_W - 1 downto 0);
  type strb_array_t is array (0 to NUM_MASTERS - 1) of
    std_ulogic_vector(3 downto 0);

  signal ahb_addr_q   : addr_array_t;
  signal ahb_write_q  : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
  signal ahb_strb_q   : strb_array_t;
  signal ahb_active_q : std_ulogic_vector(NUM_MASTERS - 1 downto 0);

begin

  -- Master-side AHB adapter
  gen_mst : for gi in 0 to NUM_MASTERS - 1 generate
    p_mst : process(clk) is
    begin
      if rising_edge(clk) then
        if rst_n = '0' then
          ahb_addr_q(gi)   <= (others => '0');
          ahb_write_q(gi)  <= '0';
          ahb_strb_q(gi)   <= (others => '0');
          ahb_active_q(gi) <= '0';
        else
          if M_HSEL(gi) = '1' and
             M_HTRANS(gi*2+1 downto gi*2) = AHB_NONSEQ and
             ahb_active_q(gi) = '0' then
            ahb_addr_q(gi)   <= M_HADDR((gi+1)*ADDR_W-1 downto gi*ADDR_W);
            ahb_write_q(gi)  <= M_HWRITE(gi);
            ahb_strb_q(gi)   <= M_HWSTRB((gi+1)*4-1 downto gi*4);
            ahb_active_q(gi) <= '1';
          elsif mst_gnt_i(gi) = '1' then
            ahb_active_q(gi) <= '0';
          end if;
        end if;
      end if;
    end process p_mst;

    mst_req_i(gi)  <= ahb_active_q(gi);
    mst_addr_i((gi+1)*ADDR_W-1 downto gi*ADDR_W) <= ahb_addr_q(gi);
    mst_wdata_i((gi+1)*DATA_W-1 downto gi*DATA_W) <=
      M_HWDATA((gi+1)*DATA_W-1 downto gi*DATA_W);
    mst_we_i(gi)   <= ahb_write_q(gi);
    mst_be_i((gi+1)*4-1 downto gi*4) <= ahb_strb_q(gi);

    M_HREADY(gi)   <= mst_gnt_i(gi) or not ahb_active_q(gi);
    M_HRDATA((gi+1)*DATA_W-1 downto gi*DATA_W) <=
      mst_rdata_i((gi+1)*DATA_W-1 downto gi*DATA_W);
    M_HRESP(gi)    <= mst_err_i(gi);
  end generate gen_mst;

  -- Slave-side AHB adapter
  gen_slv : for gi in 0 to NUM_SLAVES - 1 generate
    S_HSEL(gi)   <= slv_req_i(gi);
    S_HTRANS(gi*2+1 downto gi*2) <=
      AHB_NONSEQ when slv_req_i(gi) = '1' else AHB_IDLE;
    S_HADDR((gi+1)*ADDR_W-1 downto gi*ADDR_W) <=
      slv_addr_i((gi+1)*ADDR_W-1 downto gi*ADDR_W);
    S_HWRITE(gi) <= slv_we_i(gi);
    S_HWSTRB((gi+1)*4-1 downto gi*4) <=
      slv_be_i((gi+1)*4-1 downto gi*4);
    S_HWDATA((gi+1)*DATA_W-1 downto gi*DATA_W) <=
      slv_wdata_i((gi+1)*DATA_W-1 downto gi*DATA_W);

    slv_gnt_i(gi)  <= S_HREADY(gi);
    slv_rdata_i((gi+1)*DATA_W-1 downto gi*DATA_W) <=
      S_HRDATA((gi+1)*DATA_W-1 downto gi*DATA_W);
    slv_rvalid_i(gi) <= S_HREADY(gi) and not slv_we_i(gi);
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
