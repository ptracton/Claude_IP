-- sram_macro_altera.vhd — Intel/Altera altsyncram single-port RAM tile (TECH_ALTERA).
--
-- VHDL-2008 twin of sram_macro_altera.sv: altsyncram in SINGLE_PORT mode
-- (M10K, Cyclone V) with byte enables and an unregistered output.
-- clocken0 = cs_i, the block's only low-power mode; ls_i / ds_i / sd_i are
-- unused (M10K has no sleep pins; the core never selects a sleeping tile).
-- The component is declared here rather than through "library altera_mf",
-- so the file analyses on any host; it is only elaborated (and bound to
-- altera_mf) when TECH = TECH_ALTERA.

library ieee;
use ieee.std_logic_1164.all;
use work.sram_pkg.all;

entity sram_macro_altera is
  generic (
    MAC_W     : positive := 32;   -- word width (multiple of 8)
    MAC_D     : positive := 1024; -- words
    INIT_FILE : string   := ""    -- optional preload (.mif / .hex)
  );
  port (
    clk     : in  std_ulogic;                                   -- clock
    cs_i    : in  std_ulogic;                                   -- chip select
    we_i    : in  std_ulogic;                                   -- 1 = write, 0 = read
    addr_i  : in  std_ulogic_vector(clog2(MAC_D) - 1 downto 0); -- word address
    wdata_i : in  std_ulogic_vector(MAC_W - 1 downto 0);        -- write data
    wbe_i   : in  std_ulogic_vector(MAC_W / 8 - 1 downto 0);    -- byte write enables
    ls_i    : in  std_ulogic;                                   -- light sleep (unused)
    ds_i    : in  std_ulogic;                                   -- deep sleep (unused)
    sd_i    : in  std_ulogic;                                   -- shutdown (unused)
    rdata_o : out std_ulogic_vector(MAC_W - 1 downto 0)         -- read data
  );
end entity sram_macro_altera;

architecture rtl of sram_macro_altera is

  -- Vendor primitive (altera_mf): only the generics and ports used here.
  component altsyncram is
    generic (
      operation_mode                : string  := "SINGLE_PORT";
      intended_device_family        : string  := "Cyclone V";
      ram_block_type                : string  := "AUTO";
      lpm_type                      : string  := "altsyncram";
      width_a                       : natural := 1;
      widthad_a                     : natural := 1;
      numwords_a                    : natural := 0;
      width_byteena_a               : natural := 1;
      byte_size                     : natural := 8;
      outdata_reg_a                 : string  := "UNREGISTERED";
      outdata_aclr_a                : string  := "NONE";
      clock_enable_input_a          : string  := "NORMAL";
      clock_enable_output_a         : string  := "NORMAL";
      read_during_write_mode_port_a : string  := "NEW_DATA_NO_NBE_READ";
      power_up_uninitialized        : string  := "FALSE";
      init_file                     : string  := "UNUSED"
    );
    port (
      clock0    : in  std_logic;
      clocken0  : in  std_logic;
      address_a : in  std_logic_vector(widthad_a - 1 downto 0);
      data_a    : in  std_logic_vector(width_a - 1 downto 0);
      wren_a    : in  std_logic;
      byteena_a : in  std_logic_vector(width_byteena_a - 1 downto 0);
      q_a       : out std_logic_vector(width_a - 1 downto 0)
    );
  end component altsyncram;

  function init_name(f : string) return string is
  begin
    if f = "" then
      return "UNUSED";
    end if;
    return f;
  end function init_name;

  signal q : std_logic_vector(MAC_W - 1 downto 0);

begin

  u_altsyncram : altsyncram
    generic map (
      operation_mode                => "SINGLE_PORT",
      intended_device_family        => "Cyclone V",
      ram_block_type                => "M10K",
      lpm_type                      => "altsyncram",
      width_a                       => MAC_W,
      widthad_a                     => clog2(MAC_D),
      numwords_a                    => MAC_D,
      width_byteena_a               => MAC_W / 8,
      byte_size                     => 8,
      outdata_reg_a                 => "UNREGISTERED",
      outdata_aclr_a                => "NONE",
      clock_enable_input_a          => "NORMAL",
      clock_enable_output_a         => "BYPASS",
      read_during_write_mode_port_a => "NEW_DATA_NO_NBE_READ",
      power_up_uninitialized        => "FALSE",
      init_file                     => init_name(INIT_FILE)
    )
    port map (
      clock0    => clk,
      clocken0  => cs_i,
      address_a => std_logic_vector(addr_i),
      data_a    => std_logic_vector(wdata_i),
      wren_a    => we_i,
      byteena_a => std_logic_vector(wbe_i),
      q_a       => q
    );

  rdata_o <= std_ulogic_vector(q);

end architecture rtl;
