-- sram_macro_xilinx.vhd — Xilinx XPM single-port RAM wrapper (TECH_XILINX).
--
-- VHDL-2008 twin of sram_macro_xilinx.sv: one xpm_memory_spram of W x D (not
-- tiled: Vivado cascades block RAMs) with one cycle of read latency and lane
-- writes (BYTE_WRITE_WIDTH_A = W / NLANES); sleep = ls_i or ds_i or sd_i with
-- WAKEUP_TIME = "use_sleep_pin".
-- The component is declared here rather than through "library xpm", so the
-- file analyses on any host; it is only elaborated (and bound to Vivado's
-- XPM) when TECH = TECH_XILINX.

library ieee;
use ieee.std_logic_1164.all;
use work.sram_pkg.all;

entity sram_macro_xilinx is
  generic (
    W         : positive := 32;   -- word width
    D         : positive := 1024; -- words (power of two)
    NLANES    : positive := 4;    -- write lanes of W / NLANES bits
    INIT_FILE : string   := ""    -- optional preload (.mem)
  );
  port (
    clk       : in  std_ulogic;                               -- clock
    cs_i      : in  std_ulogic;                               -- chip select
    we_i      : in  std_ulogic;                               -- 1 = write, 0 = read
    addr_i    : in  std_ulogic_vector(clog2(D) - 1 downto 0); -- word address
    wdata_i   : in  std_ulogic_vector(W - 1 downto 0);        -- write data
    lane_we_i : in  std_ulogic_vector(NLANES - 1 downto 0);   -- lanes to write
    ls_i      : in  std_ulogic;                               -- light sleep
    ds_i      : in  std_ulogic;                               -- deep sleep
    sd_i      : in  std_ulogic;                               -- shutdown
    rdata_o   : out std_ulogic_vector(W - 1 downto 0)         -- read data
  );
end entity sram_macro_xilinx;

architecture rtl of sram_macro_xilinx is

  -- Vendor primitive (UG953): only the generics set below are declared.
  component xpm_memory_spram is
    generic (
      ADDR_WIDTH_A        : integer := 6;
      AUTO_SLEEP_TIME     : integer := 0;
      BYTE_WRITE_WIDTH_A  : integer := 32;
      ECC_MODE            : string  := "no_ecc";
      MEMORY_INIT_FILE    : string  := "none";
      MEMORY_INIT_PARAM   : string  := "0";
      MEMORY_OPTIMIZATION : string  := "true";
      MEMORY_PRIMITIVE    : string  := "auto";
      MEMORY_SIZE         : integer := 2048;
      MESSAGE_CONTROL     : integer := 0;
      READ_DATA_WIDTH_A   : integer := 32;
      READ_LATENCY_A      : integer := 2;
      READ_RESET_VALUE_A  : string  := "0";
      RST_MODE_A          : string  := "SYNC";
      USE_MEM_INIT        : integer := 1;
      WAKEUP_TIME         : string  := "disable_sleep";
      WRITE_DATA_WIDTH_A  : integer := 32;
      WRITE_MODE_A        : string  := "read_first"
    );
    port (
      clka           : in  std_logic;
      rsta           : in  std_logic;
      ena            : in  std_logic;
      regcea         : in  std_logic;
      wea            : in  std_logic_vector(WRITE_DATA_WIDTH_A / BYTE_WRITE_WIDTH_A - 1 downto 0);
      addra          : in  std_logic_vector(ADDR_WIDTH_A - 1 downto 0);
      dina           : in  std_logic_vector(WRITE_DATA_WIDTH_A - 1 downto 0);
      douta          : out std_logic_vector(READ_DATA_WIDTH_A - 1 downto 0);
      sleep          : in  std_logic;
      injectsbiterra : in  std_logic;
      injectdbiterra : in  std_logic;
      sbiterra       : out std_logic;
      dbiterra       : out std_logic
    );
  end component xpm_memory_spram;

  function init_name(f : string) return string is
  begin
    if f = "" then
      return "none";
    end if;
    return f;
  end function init_name;

  signal wea   : std_logic_vector(NLANES - 1 downto 0);
  signal sleep : std_logic;
  signal douta : std_logic_vector(W - 1 downto 0);

begin

  wea   <= std_logic_vector(lane_we_i) when we_i = '1' else (others => '0');
  sleep <= ls_i or ds_i or sd_i;

  u_xpm : xpm_memory_spram
    generic map (
      ADDR_WIDTH_A        => clog2(D),
      AUTO_SLEEP_TIME     => 0,
      BYTE_WRITE_WIDTH_A  => W / NLANES,
      ECC_MODE            => "no_ecc",
      MEMORY_INIT_FILE    => init_name(INIT_FILE),
      MEMORY_INIT_PARAM   => "0",
      MEMORY_OPTIMIZATION => "true",
      MEMORY_PRIMITIVE    => "auto",
      MEMORY_SIZE         => W * D,
      MESSAGE_CONTROL     => 0,
      READ_DATA_WIDTH_A   => W,
      READ_LATENCY_A      => 1,
      READ_RESET_VALUE_A  => "0",
      RST_MODE_A          => "SYNC",
      USE_MEM_INIT        => 1,
      WAKEUP_TIME         => "use_sleep_pin",
      WRITE_DATA_WIDTH_A  => W,
      WRITE_MODE_A        => "read_first"
    )
    port map (
      clka           => clk,
      rsta           => '0',
      ena            => cs_i,
      regcea         => '1',
      wea            => wea,
      addra          => std_logic_vector(addr_i),
      dina           => std_logic_vector(wdata_i),
      douta          => douta,
      sleep          => sleep,
      injectsbiterra => '0',
      injectdbiterra => '0',
      sbiterra       => open,
      dbiterra       => open
    );

  rdata_o <= std_ulogic_vector(douta);

end architecture rtl;
