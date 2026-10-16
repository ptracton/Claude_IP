-- sram_macro_dp_altera.vhd — Intel/Altera altsyncram true dual-port tile (TECH_ALTERA, DUAL_PORT).
--
-- VHDL-2008 twin of sram_macro_dp_altera.sv: altsyncram BIDIR_DUAL_PORT
-- (M10K, Cyclone V) on one clock, byte enables on both ports, unregistered
-- outputs; clocken0 = a_cs_i or b_cs_i. No sleep pins on M10K. The component
-- is declared here (no "library altera_mf"); only elaborated with TECH_ALTERA.

library ieee;
use ieee.std_logic_1164.all;
use work.sram_pkg.all;

entity sram_macro_dp_altera is
  generic (
    MAC_W     : positive := 32;    -- word width (multiple of 8)
    MAC_D     : positive := 1024;  -- words
    INIT_FILE : string   := ""     -- optional preload
  );
  port (
    clk       : in  std_ulogic;                                    -- clock (both ports)
    a_cs_i    : in  std_ulogic;                                    -- port A chip select
    a_we_i    : in  std_ulogic;                                    -- port A 1 = write
    a_addr_i  : in  std_ulogic_vector(clog2(MAC_D) - 1 downto 0);  -- port A word address
    a_wdata_i : in  std_ulogic_vector(MAC_W - 1 downto 0);         -- port A write data
    a_wbe_i   : in  std_ulogic_vector(MAC_W / 8 - 1 downto 0);     -- port A byte write enables
    a_rdata_o : out std_ulogic_vector(MAC_W - 1 downto 0);         -- port A read data
    b_cs_i    : in  std_ulogic;                                    -- port B chip select
    b_we_i    : in  std_ulogic;                                    -- port B 1 = write
    b_addr_i  : in  std_ulogic_vector(clog2(MAC_D) - 1 downto 0);  -- port B word address
    b_wdata_i : in  std_ulogic_vector(MAC_W - 1 downto 0);         -- port B write data
    b_wbe_i   : in  std_ulogic_vector(MAC_W / 8 - 1 downto 0);     -- port B byte write enables
    b_rdata_o : out std_ulogic_vector(MAC_W - 1 downto 0);         -- port B read data
    ls_i      : in  std_ulogic;                                    -- light sleep
    ds_i      : in  std_ulogic;                                    -- deep sleep
    sd_i      : in  std_ulogic                                     -- shutdown
  );
end entity sram_macro_dp_altera;

architecture rtl of sram_macro_dp_altera is

  -- Vendor primitive (altera_mf): only the generics and ports used here.
  component altsyncram is
    generic (
      operation_mode                     : string  := "BIDIR_DUAL_PORT";
      intended_device_family             : string  := "Cyclone V";
      ram_block_type                     : string  := "AUTO";
      lpm_type                           : string  := "altsyncram";
      width_a                            : natural := 1;
      width_b                            : natural := 1;
      widthad_a                          : natural := 1;
      widthad_b                          : natural := 1;
      numwords_a                         : natural := 0;
      numwords_b                         : natural := 0;
      width_byteena_a                    : natural := 1;
      width_byteena_b                    : natural := 1;
      byte_size                          : natural := 8;
      address_reg_b                      : string  := "CLOCK0";
      indata_reg_b                       : string  := "CLOCK0";
      wrcontrol_wraddress_reg_b          : string  := "CLOCK0";
      byteena_reg_b                      : string  := "CLOCK0";
      outdata_reg_a                      : string  := "UNREGISTERED";
      outdata_reg_b                      : string  := "UNREGISTERED";
      outdata_aclr_a                     : string  := "NONE";
      outdata_aclr_b                     : string  := "NONE";
      clock_enable_input_a               : string  := "NORMAL";
      clock_enable_input_b               : string  := "NORMAL";
      clock_enable_output_a              : string  := "NORMAL";
      clock_enable_output_b              : string  := "NORMAL";
      read_during_write_mode_mixed_ports : string  := "OLD_DATA";
      read_during_write_mode_port_a      : string  := "NEW_DATA_NO_NBE_READ";
      read_during_write_mode_port_b      : string  := "NEW_DATA_NO_NBE_READ";
      power_up_uninitialized             : string  := "FALSE";
      init_file                          : string  := "UNUSED"
    );
    port (
      clock0    : in  std_logic;
      clocken0  : in  std_logic;
      address_a : in  std_logic_vector(widthad_a - 1 downto 0);
      data_a    : in  std_logic_vector(width_a - 1 downto 0);
      wren_a    : in  std_logic;
      byteena_a : in  std_logic_vector(width_byteena_a - 1 downto 0);
      q_a       : out std_logic_vector(width_a - 1 downto 0);
      address_b : in  std_logic_vector(widthad_b - 1 downto 0);
      data_b    : in  std_logic_vector(width_b - 1 downto 0);
      wren_b    : in  std_logic;
      byteena_b : in  std_logic_vector(width_byteena_b - 1 downto 0);
      q_b       : out std_logic_vector(width_b - 1 downto 0)
    );
  end component altsyncram;

  function init_name(f : string) return string is
  begin
    if f = "" then
      return "UNUSED";
    end if;
    return f;
  end function init_name;

  signal clken : std_logic;
  signal qa    : std_logic_vector(MAC_W - 1 downto 0);
  signal qb    : std_logic_vector(MAC_W - 1 downto 0);

begin

  clken <= a_cs_i or b_cs_i;

  u_altsyncram : altsyncram
    generic map (
      operation_mode                     => "BIDIR_DUAL_PORT",
      intended_device_family             => "Cyclone V",
      ram_block_type                     => "M10K",
      lpm_type                           => "altsyncram",
      width_a                            => MAC_W,
      width_b                            => MAC_W,
      widthad_a                          => clog2(MAC_D),
      widthad_b                          => clog2(MAC_D),
      numwords_a                         => MAC_D,
      numwords_b                         => MAC_D,
      width_byteena_a                    => MAC_W / 8,
      width_byteena_b                    => MAC_W / 8,
      byte_size                          => 8,
      address_reg_b                      => "CLOCK0",
      indata_reg_b                       => "CLOCK0",
      wrcontrol_wraddress_reg_b          => "CLOCK0",
      byteena_reg_b                      => "CLOCK0",
      outdata_reg_a                      => "UNREGISTERED",
      outdata_reg_b                      => "UNREGISTERED",
      outdata_aclr_a                     => "NONE",
      outdata_aclr_b                     => "NONE",
      clock_enable_input_a               => "NORMAL",
      clock_enable_input_b               => "NORMAL",
      clock_enable_output_a              => "BYPASS",
      clock_enable_output_b              => "BYPASS",
      read_during_write_mode_mixed_ports => "OLD_DATA",
      read_during_write_mode_port_a      => "NEW_DATA_NO_NBE_READ",
      read_during_write_mode_port_b      => "NEW_DATA_NO_NBE_READ",
      power_up_uninitialized             => "FALSE",
      init_file                          => init_name(INIT_FILE)
    )
    port map (
      clock0    => clk,
      clocken0  => clken,
      address_a => std_logic_vector(a_addr_i),
      data_a    => std_logic_vector(a_wdata_i),
      wren_a    => a_we_i,
      byteena_a => std_logic_vector(a_wbe_i),
      q_a       => qa,
      address_b => std_logic_vector(b_addr_i),
      data_b    => std_logic_vector(b_wdata_i),
      wren_b    => b_we_i,
      byteena_b => std_logic_vector(b_wbe_i),
      q_b       => qb
    );

  a_rdata_o <= std_ulogic_vector(qa);
  b_rdata_o <= std_ulogic_vector(qb);

end architecture rtl;
