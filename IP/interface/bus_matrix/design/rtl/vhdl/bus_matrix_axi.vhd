-- bus_matrix_axi.vhd — AXI4-Lite bus matrix top-level (VHDL-2008).
--
-- Crossbar interconnect connecting NUM_MASTERS AXI4-Lite masters to NUM_SLAVES
-- AXI4-Lite slaves. All configuration via generics; no runtime registers.
-- Mirrors bus_matrix_axi.sv.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bus_matrix_axi is
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

    -- Master input ports (AXI4-Lite slave-facing, flat-packed)
    M_AWVALID : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    M_AWREADY : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    M_AWADDR  : in  std_ulogic_vector(NUM_MASTERS * ADDR_W - 1 downto 0);
    M_WVALID  : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    M_WREADY  : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    M_WDATA   : in  std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);
    M_WSTRB   : in  std_ulogic_vector(NUM_MASTERS * 4 - 1 downto 0);
    M_BVALID  : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    M_BREADY  : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    M_BRESP   : out std_ulogic_vector(NUM_MASTERS * 2 - 1 downto 0);
    M_ARVALID : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    M_ARREADY : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    M_ARADDR  : in  std_ulogic_vector(NUM_MASTERS * ADDR_W - 1 downto 0);
    M_RVALID  : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    M_RREADY  : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    M_RDATA   : out std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);
    M_RRESP   : out std_ulogic_vector(NUM_MASTERS * 2 - 1 downto 0);

    -- Slave output ports (AXI4-Lite master-facing, flat-packed)
    S_AWVALID : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    S_AWREADY : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    S_AWADDR  : out std_ulogic_vector(NUM_SLAVES * ADDR_W - 1 downto 0);
    S_WVALID  : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    S_WREADY  : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    S_WDATA   : out std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);
    S_WSTRB   : out std_ulogic_vector(NUM_SLAVES * 4 - 1 downto 0);
    S_BVALID  : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    S_BREADY  : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    S_BRESP   : in  std_ulogic_vector(NUM_SLAVES * 2 - 1 downto 0);
    S_ARVALID : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    S_ARREADY : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    S_ARADDR  : out std_ulogic_vector(NUM_SLAVES * ADDR_W - 1 downto 0);
    S_RVALID  : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    S_RREADY  : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    S_RDATA   : in  std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);
    S_RRESP   : in  std_ulogic_vector(NUM_SLAVES * 2 - 1 downto 0)
  );
end entity bus_matrix_axi;

architecture rtl of bus_matrix_axi is

  constant AXI_OKAY : std_ulogic_vector(1 downto 0) := "00";

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

  -- AXI master adapter state
  type axi_mst_state_t is (AXI_MST_IDLE, AXI_MST_WRITE, AXI_MST_READ);
  type state_array_t is array (0 to NUM_MASTERS - 1) of axi_mst_state_t;
  type addr_array_t  is array (0 to NUM_MASTERS - 1) of
    std_ulogic_vector(ADDR_W - 1 downto 0);
  type data_array_t  is array (0 to NUM_MASTERS - 1) of
    std_ulogic_vector(DATA_W - 1 downto 0);
  type strb_array_t  is array (0 to NUM_MASTERS - 1) of
    std_ulogic_vector(3 downto 0);

  signal axi_mst_state_q : state_array_t;
  signal axi_mst_addr_q  : addr_array_t;
  signal axi_mst_wdata_q : data_array_t;
  signal axi_mst_strb_q  : strb_array_t;
  signal axi_bvalid_q    : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
  signal axi_rvalid_q    : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
  signal axi_rdata_q     : data_array_t;

begin

  -- Master-side AXI adapter
  gen_mst : for gi in 0 to NUM_MASTERS - 1 generate
    p_mst_axi : process(clk) is
    begin
      if rising_edge(clk) then
        if rst_n = '0' then
          axi_mst_state_q(gi) <= AXI_MST_IDLE;
          axi_mst_addr_q(gi)  <= (others => '0');
          axi_mst_wdata_q(gi) <= (others => '0');
          axi_mst_strb_q(gi)  <= (others => '0');
          axi_bvalid_q(gi)    <= '0';
          axi_rvalid_q(gi)    <= '0';
          axi_rdata_q(gi)     <= (others => '0');
        else
          case axi_mst_state_q(gi) is
            when AXI_MST_IDLE =>
              axi_bvalid_q(gi) <= '0';
              axi_rvalid_q(gi) <= '0';
              if M_AWVALID(gi) = '1' and M_WVALID(gi) = '1' then
                axi_mst_state_q(gi) <= AXI_MST_WRITE;
                axi_mst_addr_q(gi)  <= M_AWADDR((gi+1)*ADDR_W-1 downto gi*ADDR_W);
                axi_mst_wdata_q(gi) <= M_WDATA((gi+1)*DATA_W-1 downto gi*DATA_W);
                axi_mst_strb_q(gi)  <= M_WSTRB((gi+1)*4-1 downto gi*4);
              elsif M_ARVALID(gi) = '1' then
                axi_mst_state_q(gi) <= AXI_MST_READ;
                axi_mst_addr_q(gi)  <= M_ARADDR((gi+1)*ADDR_W-1 downto gi*ADDR_W);
              end if;

            when AXI_MST_WRITE =>
              if mst_gnt_i(gi) = '1' then
                axi_bvalid_q(gi)    <= '1';
                axi_mst_state_q(gi) <= AXI_MST_IDLE;
              end if;
              if axi_bvalid_q(gi) = '1' and M_BREADY(gi) = '1' then
                axi_bvalid_q(gi) <= '0';
              end if;

            when AXI_MST_READ =>
              if mst_rvalid_i(gi) = '1' then
                axi_rvalid_q(gi)    <= '1';
                axi_rdata_q(gi)     <= mst_rdata_i((gi+1)*DATA_W-1 downto gi*DATA_W);
                axi_mst_state_q(gi) <= AXI_MST_IDLE;
              end if;
              if axi_rvalid_q(gi) = '1' and M_RREADY(gi) = '1' then
                axi_rvalid_q(gi) <= '0';
              end if;

            when others =>
              axi_mst_state_q(gi) <= AXI_MST_IDLE;
          end case;
        end if;
      end if;
    end process p_mst_axi;

    -- Internal protocol signals
    mst_req_i(gi) <= '1' when axi_mst_state_q(gi) /= AXI_MST_IDLE else '0';
    mst_addr_i((gi+1)*ADDR_W-1 downto gi*ADDR_W) <= axi_mst_addr_q(gi);
    mst_wdata_i((gi+1)*DATA_W-1 downto gi*DATA_W) <= axi_mst_wdata_q(gi);
    mst_we_i(gi) <= '1' when axi_mst_state_q(gi) = AXI_MST_WRITE else '0';
    mst_be_i((gi+1)*4-1 downto gi*4) <= axi_mst_strb_q(gi);

    -- AXI handshake outputs
    M_AWREADY(gi) <= '1' when axi_mst_state_q(gi) = AXI_MST_IDLE else '0';
    M_WREADY(gi)  <= '1' when axi_mst_state_q(gi) = AXI_MST_IDLE else '0';
    M_ARREADY(gi) <= '1' when axi_mst_state_q(gi) = AXI_MST_IDLE and
                              M_AWVALID(gi) = '0' else '0';
    M_BVALID(gi)  <= axi_bvalid_q(gi);
    M_BRESP(gi*2+1 downto gi*2) <= AXI_OKAY;
    M_RVALID(gi)  <= axi_rvalid_q(gi);
    M_RDATA((gi+1)*DATA_W-1 downto gi*DATA_W) <= axi_rdata_q(gi);
    M_RRESP(gi*2+1 downto gi*2) <=
      "10" when mst_err_i(gi) = '1' else AXI_OKAY;
  end generate gen_mst;

  -- Slave-side AXI adapter
  gen_slv : for gi in 0 to NUM_SLAVES - 1 generate
    S_AWVALID(gi) <= slv_req_i(gi) and slv_we_i(gi);
    S_AWADDR((gi+1)*ADDR_W-1 downto gi*ADDR_W) <=
      slv_addr_i((gi+1)*ADDR_W-1 downto gi*ADDR_W);
    S_WVALID(gi)  <= slv_req_i(gi) and slv_we_i(gi);
    S_WDATA((gi+1)*DATA_W-1 downto gi*DATA_W) <=
      slv_wdata_i((gi+1)*DATA_W-1 downto gi*DATA_W);
    S_WSTRB((gi+1)*4-1 downto gi*4) <=
      slv_be_i((gi+1)*4-1 downto gi*4);
    S_BREADY(gi)  <= '1';

    S_ARVALID(gi) <= slv_req_i(gi) and not slv_we_i(gi);
    S_ARADDR((gi+1)*ADDR_W-1 downto gi*ADDR_W) <=
      slv_addr_i((gi+1)*ADDR_W-1 downto gi*ADDR_W);
    S_RREADY(gi)  <= '1';

    slv_gnt_i(gi) <= S_BVALID(gi) when slv_we_i(gi) = '1'
                     else S_RVALID(gi);
    slv_rdata_i((gi+1)*DATA_W-1 downto gi*DATA_W) <=
      S_RDATA((gi+1)*DATA_W-1 downto gi*DATA_W);
    slv_rvalid_i(gi) <= S_RVALID(gi);
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
