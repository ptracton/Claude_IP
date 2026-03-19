-- timer_axi4l.vhd — AXI4-Lite top-level for Timer IP (VHDL-2008).
--
-- Instantiates timer_axi4l_if, timer_regfile, and timer_core.
-- Contains no logic — only port declarations and submodule wiring.
-- Port-for-port equivalent to timer_axi4l.sv.
--
-- Component instantiation is used so that ghdl -s can check each file
-- individually without requiring a pre-compiled library.
--
-- Generics:
--   DATA_W  : data bus width              (default 32)
--   ADDR_W  : regfile word-address width  (default 4)
--   RST_POL : reset polarity, 0=active-low (default 0)

library ieee;
use ieee.std_logic_1164.all;

entity timer_axi4l is
  generic (
    DATA_W  : positive := 32; -- data bus width
    ADDR_W  : positive := 4;  -- regfile word-address width
    RST_POL : natural  := 0   -- 0 = active-low reset
  );
  port (
    -- AXI4-Lite global signals
    ACLK    : in  std_ulogic;                                   -- AXI clock
    ARESETn : in  std_ulogic;                                   -- AXI active-low reset

    -- Write address channel
    AWVALID : in  std_ulogic;                                   -- master write address valid
    AWREADY : out std_ulogic;                                   -- slave ready
    AWADDR  : in  std_ulogic_vector(11 downto 0);               -- write byte address

    -- Write data channel
    WVALID  : in  std_ulogic;                                   -- master write data valid
    WREADY  : out std_ulogic;                                   -- slave ready
    WDATA   : in  std_ulogic_vector(DATA_W - 1 downto 0);       -- write data
    WSTRB   : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0);  -- byte enables

    -- Write response channel
    BVALID  : out std_ulogic;                                   -- slave response valid
    BREADY  : in  std_ulogic;                                   -- master ready
    BRESP   : out std_ulogic_vector(1 downto 0);                -- response

    -- Read address channel
    ARVALID : in  std_ulogic;                                   -- master read address valid
    ARREADY : out std_ulogic;                                   -- slave ready
    ARADDR  : in  std_ulogic_vector(11 downto 0);               -- read byte address

    -- Read data channel
    RVALID  : out std_ulogic;                                   -- slave data valid
    RREADY  : in  std_ulogic;                                   -- master ready
    RDATA   : out std_ulogic_vector(DATA_W - 1 downto 0);       -- read data
    RRESP   : out std_ulogic_vector(1 downto 0);                -- response

    -- IP-level outputs
    irq         : out std_ulogic;                               -- masked interrupt
    trigger_out : out std_ulogic                                -- one-cycle trigger pulse
  );
end entity timer_axi4l;

architecture rtl of timer_axi4l is

  -- -------------------------------------------------------------------------
  -- Component declarations
  -- -------------------------------------------------------------------------
  component timer_axi4l_if is
    generic (
      DATA_W : positive;
      ADDR_W : positive
    );
    port (
      ACLK    : in  std_ulogic;
      ARESETn : in  std_ulogic;
      AWVALID : in  std_ulogic;
      AWREADY : out std_ulogic;
      AWADDR  : in  std_ulogic_vector(11 downto 0);
      WVALID  : in  std_ulogic;
      WREADY  : out std_ulogic;
      WDATA   : in  std_ulogic_vector(DATA_W - 1 downto 0);
      WSTRB   : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0);
      BVALID  : out std_ulogic;
      BREADY  : in  std_ulogic;
      BRESP   : out std_ulogic_vector(1 downto 0);
      ARVALID : in  std_ulogic;
      ARREADY : out std_ulogic;
      ARADDR  : in  std_ulogic_vector(11 downto 0);
      RVALID  : out std_ulogic;
      RREADY  : in  std_ulogic;
      RDATA   : out std_ulogic_vector(DATA_W - 1 downto 0);
      RRESP   : out std_ulogic_vector(1 downto 0);
      wr_en   : out std_ulogic;
      wr_addr : out std_ulogic_vector(ADDR_W - 1 downto 0);
      wr_data : out std_ulogic_vector(DATA_W - 1 downto 0);
      wr_strb : out std_ulogic_vector(DATA_W / 8 - 1 downto 0);
      rd_en   : out std_ulogic;
      rd_addr : out std_ulogic_vector(ADDR_W - 1 downto 0);
      rd_data : in  std_ulogic_vector(DATA_W - 1 downto 0)
    );
  end component timer_axi4l_if;

  component timer_regfile is
    port (
      clk           : in  std_ulogic;
      rst_n         : in  std_ulogic;
      wr_en         : in  std_ulogic;
      wr_addr       : in  std_ulogic_vector(3 downto 0);
      wr_data       : in  std_ulogic_vector(31 downto 0);
      wr_strb       : in  std_ulogic_vector(3 downto 0);
      rd_en         : in  std_ulogic;
      rd_addr       : in  std_ulogic_vector(3 downto 0);
      rd_data       : out std_ulogic_vector(31 downto 0);
      hw_count_val  : in  std_ulogic_vector(31 downto 0);
      hw_intr_set   : in  std_ulogic;
      hw_ovf_set    : in  std_ulogic;
      hw_active     : in  std_ulogic;
      ctrl_en       : out std_ulogic;
      ctrl_mode     : out std_ulogic;
      ctrl_intr_en  : out std_ulogic;
      ctrl_trig_en  : out std_ulogic;
      ctrl_prescale : out std_ulogic_vector(7 downto 0);
      ctrl_restart  : out std_ulogic;
      ctrl_irq_mode : out std_ulogic;
      load_val      : out std_ulogic_vector(31 downto 0);
      status_intr   : out std_ulogic
    );
  end component timer_regfile;

  component timer_core is
    generic (
      DATA_W : positive
    );
    port (
      clk           : in  std_ulogic;
      rst_n         : in  std_ulogic;
      ctrl_en       : in  std_ulogic;
      ctrl_mode     : in  std_ulogic;
      ctrl_intr_en  : in  std_ulogic;
      ctrl_trig_en  : in  std_ulogic;
      ctrl_prescale : in  std_ulogic_vector(7 downto 0);
      ctrl_restart  : in  std_ulogic;
      ctrl_irq_mode : in  std_ulogic;
      load_val      : in  std_ulogic_vector(DATA_W - 1 downto 0);
      status_intr   : in  std_ulogic;
      hw_count_val  : out std_ulogic_vector(DATA_W - 1 downto 0);
      hw_intr_set   : out std_ulogic;
      hw_ovf_set    : out std_ulogic;
      hw_active     : out std_ulogic;
      irq           : out std_ulogic;
      trigger_out   : out std_ulogic
    );
  end component timer_core;

  -- -------------------------------------------------------------------------
  -- Internal wires between submodules
  -- -------------------------------------------------------------------------
  signal if_wr_en    : std_ulogic;
  signal if_wr_addr  : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal if_wr_data  : std_ulogic_vector(DATA_W - 1 downto 0);
  signal if_wr_strb  : std_ulogic_vector(DATA_W / 8 - 1 downto 0);

  signal if_rd_en    : std_ulogic;
  signal if_rd_addr  : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal if_rd_data  : std_ulogic_vector(DATA_W - 1 downto 0);

  signal ctrl_en        : std_ulogic;
  signal ctrl_mode      : std_ulogic;
  signal ctrl_intr_en   : std_ulogic;
  signal ctrl_trig_en   : std_ulogic;
  signal ctrl_prescale  : std_ulogic_vector(7 downto 0);
  signal ctrl_restart   : std_ulogic;
  signal ctrl_irq_mode  : std_ulogic;
  signal load_val       : std_ulogic_vector(DATA_W - 1 downto 0);
  signal status_intr    : std_ulogic;

  signal hw_count_val   : std_ulogic_vector(DATA_W - 1 downto 0);
  signal hw_intr_set    : std_ulogic;
  signal hw_ovf_set     : std_ulogic;
  signal hw_active      : std_ulogic;

begin

  -- Bus interface submodule
  u_axi4l_if : timer_axi4l_if
    generic map (
      DATA_W => DATA_W,
      ADDR_W => ADDR_W
    )
    port map (
      ACLK    => ACLK,
      ARESETn => ARESETn,
      AWVALID => AWVALID,
      AWREADY => AWREADY,
      AWADDR  => AWADDR,
      WVALID  => WVALID,
      WREADY  => WREADY,
      WDATA   => WDATA,
      WSTRB   => WSTRB,
      BVALID  => BVALID,
      BREADY  => BREADY,
      BRESP   => BRESP,
      ARVALID => ARVALID,
      ARREADY => ARREADY,
      ARADDR  => ARADDR,
      RVALID  => RVALID,
      RREADY  => RREADY,
      RDATA   => RDATA,
      RRESP   => RRESP,
      wr_en   => if_wr_en,
      wr_addr => if_wr_addr,
      wr_data => if_wr_data,
      wr_strb => if_wr_strb,
      rd_en   => if_rd_en,
      rd_addr => if_rd_addr,
      rd_data => if_rd_data
    );

  -- Register file
  u_regfile : timer_regfile
    port map (
      clk          => ACLK,
      rst_n        => ARESETn,
      wr_en        => if_wr_en,
      wr_addr      => if_wr_addr,
      wr_data      => if_wr_data,
      wr_strb      => if_wr_strb,
      rd_en        => if_rd_en,
      rd_addr      => if_rd_addr,
      rd_data      => if_rd_data,
      hw_count_val  => hw_count_val,
      hw_intr_set   => hw_intr_set,
      hw_ovf_set    => hw_ovf_set,
      hw_active     => hw_active,
      ctrl_en       => ctrl_en,
      ctrl_mode     => ctrl_mode,
      ctrl_intr_en  => ctrl_intr_en,
      ctrl_trig_en  => ctrl_trig_en,
      ctrl_prescale => ctrl_prescale,
      ctrl_restart  => ctrl_restart,
      ctrl_irq_mode => ctrl_irq_mode,
      load_val      => load_val,
      status_intr   => status_intr
    );

  -- Core logic
  u_core : timer_core
    generic map (
      DATA_W => DATA_W
    )
    port map (
      clk           => ACLK,
      rst_n         => ARESETn,
      ctrl_en       => ctrl_en,
      ctrl_mode     => ctrl_mode,
      ctrl_intr_en  => ctrl_intr_en,
      ctrl_trig_en  => ctrl_trig_en,
      ctrl_prescale => ctrl_prescale,
      ctrl_restart  => ctrl_restart,
      ctrl_irq_mode => ctrl_irq_mode,
      load_val      => load_val,
      status_intr   => status_intr,
      hw_count_val  => hw_count_val,
      hw_intr_set   => hw_intr_set,
      hw_ovf_set    => hw_ovf_set,
      hw_active     => hw_active,
      irq           => irq,
      trigger_out   => trigger_out
    );

end architecture rtl;
