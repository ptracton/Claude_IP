-- sram_macro_dp_xilinx.vhd — Xilinx XPM true dual-port RAM wrapper (TECH_XILINX, DUAL_PORT).
--
-- VHDL-2008 twin of sram_macro_dp_xilinx.sv: one xpm_memory_tdpram of W x D
-- (not tiled), CLOCKING_MODE "common_clock" with COMMON_CLK, else
-- "independent_clock" (a_clk / b_clk); one cycle of read latency, lane
-- writes (W / NLANES bits) on both ports; sleep = ls_i or ds_i or sd_i. The component is declared here (no "library xpm") so
-- the file analyses on any host; it is only elaborated with TECH_XILINX.

library ieee;
use ieee.std_logic_1164.all;
use work.sram_pkg.all;

entity sram_macro_dp_xilinx is
  generic (
    W          : positive := 32;   -- word width
    D          : positive := 1024; -- words (power of two)
    NLANES     : positive := 4;    -- write lanes of W / NLANES bits
    COMMON_CLK : natural  := 1;    -- 1: a_clk and b_clk are the same clock
    INIT_FILE  : string   := ""    -- optional preload
  );
  port (
    a_clk       : in  std_ulogic;                               -- port A clock
    a_cs_i      : in  std_ulogic;                               -- port A chip select
    a_we_i      : in  std_ulogic;                               -- port A 1 = write
    a_addr_i    : in  std_ulogic_vector(clog2(D) - 1 downto 0); -- port A word address
    a_wdata_i   : in  std_ulogic_vector(W - 1 downto 0);        -- port A write data
    a_lane_we_i : in  std_ulogic_vector(NLANES - 1 downto 0);   -- port A lanes to write
    a_rdata_o   : out std_ulogic_vector(W - 1 downto 0);        -- port A read data
    b_clk       : in  std_ulogic;                               -- port B clock
    b_cs_i      : in  std_ulogic;                               -- port B chip select
    b_we_i      : in  std_ulogic;                               -- port B 1 = write
    b_addr_i    : in  std_ulogic_vector(clog2(D) - 1 downto 0); -- port B word address
    b_wdata_i   : in  std_ulogic_vector(W - 1 downto 0);        -- port B write data
    b_lane_we_i : in  std_ulogic_vector(NLANES - 1 downto 0);   -- port B lanes to write
    b_rdata_o   : out std_ulogic_vector(W - 1 downto 0);        -- port B read data
    ls_i        : in  std_ulogic;                               -- light sleep
    ds_i        : in  std_ulogic;                               -- deep sleep
    sd_i        : in  std_ulogic                                -- shutdown
  );
end entity sram_macro_dp_xilinx;

architecture rtl of sram_macro_dp_xilinx is

  -- Vendor primitive (UG953): only the generics set below are declared.
  component xpm_memory_tdpram is
    generic (
      ADDR_WIDTH_A        : integer := 6;
      ADDR_WIDTH_B        : integer := 6;
      AUTO_SLEEP_TIME     : integer := 0;
      BYTE_WRITE_WIDTH_A  : integer := 32;
      BYTE_WRITE_WIDTH_B  : integer := 32;
      CLOCKING_MODE       : string  := "common_clock";
      ECC_MODE            : string  := "no_ecc";
      MEMORY_INIT_FILE    : string  := "none";
      MEMORY_INIT_PARAM   : string  := "0";
      MEMORY_OPTIMIZATION : string  := "true";
      MEMORY_PRIMITIVE    : string  := "auto";
      MEMORY_SIZE         : integer := 2048;
      MESSAGE_CONTROL     : integer := 0;
      READ_DATA_WIDTH_A   : integer := 32;
      READ_DATA_WIDTH_B   : integer := 32;
      READ_LATENCY_A      : integer := 2;
      READ_LATENCY_B      : integer := 2;
      READ_RESET_VALUE_A  : string  := "0";
      READ_RESET_VALUE_B  : string  := "0";
      RST_MODE_A          : string  := "SYNC";
      RST_MODE_B          : string  := "SYNC";
      USE_MEM_INIT        : integer := 1;
      WAKEUP_TIME         : string  := "disable_sleep";
      WRITE_DATA_WIDTH_A  : integer := 32;
      WRITE_DATA_WIDTH_B  : integer := 32;
      WRITE_MODE_A        : string  := "no_change";
      WRITE_MODE_B        : string  := "no_change"
    );
    port (
      clka           : in  std_logic;
      clkb           : in  std_logic;
      rsta           : in  std_logic;
      rstb           : in  std_logic;
      ena            : in  std_logic;
      enb            : in  std_logic;
      regcea         : in  std_logic;
      regceb         : in  std_logic;
      wea            : in  std_logic_vector(WRITE_DATA_WIDTH_A / BYTE_WRITE_WIDTH_A - 1 downto 0);
      web            : in  std_logic_vector(WRITE_DATA_WIDTH_B / BYTE_WRITE_WIDTH_B - 1 downto 0);
      addra          : in  std_logic_vector(ADDR_WIDTH_A - 1 downto 0);
      addrb          : in  std_logic_vector(ADDR_WIDTH_B - 1 downto 0);
      dina           : in  std_logic_vector(WRITE_DATA_WIDTH_A - 1 downto 0);
      dinb           : in  std_logic_vector(WRITE_DATA_WIDTH_B - 1 downto 0);
      douta          : out std_logic_vector(READ_DATA_WIDTH_A - 1 downto 0);
      doutb          : out std_logic_vector(READ_DATA_WIDTH_B - 1 downto 0);
      sleep          : in  std_logic;
      injectsbiterra : in  std_logic;
      injectdbiterra : in  std_logic;
      injectsbiterrb : in  std_logic;
      injectdbiterrb : in  std_logic;
      sbiterra       : out std_logic;
      dbiterra       : out std_logic;
      sbiterrb       : out std_logic;
      dbiterrb       : out std_logic
    );
  end component xpm_memory_tdpram;

  function init_name(f : string) return string is
  begin
    if f = "" then
      return "none";
    end if;
    return f;
  end function init_name;

  function clocking_mode(common : natural) return string is
  begin
    if common /= 0 then
      return "common_clock";
    end if;
    return "independent_clock";
  end function clocking_mode;

  signal wea   : std_logic_vector(NLANES - 1 downto 0);
  signal web   : std_logic_vector(NLANES - 1 downto 0);
  signal sleep : std_logic;
  signal douta : std_logic_vector(W - 1 downto 0);
  signal doutb : std_logic_vector(W - 1 downto 0);

begin

  wea   <= std_logic_vector(a_lane_we_i) when a_we_i = '1' else (others => '0');
  web   <= std_logic_vector(b_lane_we_i) when b_we_i = '1' else (others => '0');
  sleep <= ls_i or ds_i or sd_i;

  u_xpm : xpm_memory_tdpram
    generic map (
      ADDR_WIDTH_A        => clog2(D),
      ADDR_WIDTH_B        => clog2(D),
      AUTO_SLEEP_TIME     => 0,
      BYTE_WRITE_WIDTH_A  => W / NLANES,
      BYTE_WRITE_WIDTH_B  => W / NLANES,
      CLOCKING_MODE       => clocking_mode(COMMON_CLK),
      ECC_MODE            => "no_ecc",
      MEMORY_INIT_FILE    => init_name(INIT_FILE),
      MEMORY_INIT_PARAM   => "0",
      MEMORY_OPTIMIZATION => "true",
      MEMORY_PRIMITIVE    => "auto",
      MEMORY_SIZE         => W * D,
      MESSAGE_CONTROL     => 0,
      READ_DATA_WIDTH_A   => W,
      READ_DATA_WIDTH_B   => W,
      READ_LATENCY_A      => 1,
      READ_LATENCY_B      => 1,
      READ_RESET_VALUE_A  => "0",
      READ_RESET_VALUE_B  => "0",
      RST_MODE_A          => "SYNC",
      RST_MODE_B          => "SYNC",
      USE_MEM_INIT        => 1,
      WAKEUP_TIME         => "use_sleep_pin",
      WRITE_DATA_WIDTH_A  => W,
      WRITE_DATA_WIDTH_B  => W,
      WRITE_MODE_A        => "read_first",
      WRITE_MODE_B        => "read_first"
    )
    port map (
      clka           => a_clk,
      clkb           => b_clk,
      rsta           => '0',
      rstb           => '0',
      ena            => a_cs_i,
      enb            => b_cs_i,
      regcea         => '1',
      regceb         => '1',
      wea            => wea,
      web            => web,
      addra          => std_logic_vector(a_addr_i),
      addrb          => std_logic_vector(b_addr_i),
      dina           => std_logic_vector(a_wdata_i),
      dinb           => std_logic_vector(b_wdata_i),
      douta          => douta,
      doutb          => doutb,
      sleep          => sleep,
      injectsbiterra => '0',
      injectdbiterra => '0',
      injectsbiterrb => '0',
      injectdbiterrb => '0',
      sbiterra       => open,
      dbiterra       => open,
      sbiterrb       => open,
      dbiterrb       => open
    );

  a_rdata_o <= std_ulogic_vector(douta);
  b_rdata_o <= std_ulogic_vector(doutb);

end architecture rtl;
