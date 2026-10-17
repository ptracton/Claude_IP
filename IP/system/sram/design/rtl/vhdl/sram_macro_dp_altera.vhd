-- sram_macro_dp_altera.vhd — Intel/Altera altsyncram true dual-port wrapper
-- (TECH_ALTERA, DUAL_PORT).
--
-- VHDL-2008 twin of sram_macro_dp_altera.sv: one altsyncram of W x D in
-- BIDIR_DUAL_PORT mode (M10K, Cyclone V; not tiled): clock0 for both ports
-- with COMMON_CLK (clocken0 = a_cs_i or b_cs_i), else clock0 = a_clk and
-- clock1 = b_clk with their own clock enables. Lane enables (byte_size =
-- W / NLANES) on both ports, unregistered outputs. No sleep pins on M10K. The component
-- is declared here (no "library altera_mf"); only elaborated with TECH_ALTERA.

library ieee;
use ieee.std_logic_1164.all;
use work.sram_pkg.all;

entity sram_macro_dp_altera is
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
      clock1    : in  std_logic := '1';
      clocken1  : in  std_logic := '1';
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

  -- Port B registers: clock0 with a common clock, else clock1.
  function clk_b_name(common : natural) return string is
  begin
    if common /= 0 then
      return "CLOCK0";
    end if;
    return "CLOCK1";
  end function clk_b_name;

  -- Byte size of the enables (unused with one lane, but must be legal).
  function byte_size_of(w : positive; nlanes : positive) return positive is
  begin
    if nlanes > 1 then
      return w / nlanes;
    end if;
    return 8;
  end function byte_size_of;

  signal clken  : std_logic;
  signal clkenb : std_logic;
  signal qa    : std_logic_vector(W - 1 downto 0);
  signal qb    : std_logic_vector(W - 1 downto 0);

begin

  clken  <= (a_cs_i or b_cs_i) when COMMON_CLK /= 0 else a_cs_i;
  clkenb <= '1' when COMMON_CLK /= 0 else b_cs_i;

  u_altsyncram : altsyncram
    generic map (
      operation_mode                     => "BIDIR_DUAL_PORT",
      intended_device_family             => "Cyclone V",
      ram_block_type                     => "M10K",
      lpm_type                           => "altsyncram",
      width_a                            => W,
      width_b                            => W,
      widthad_a                          => clog2(D),
      widthad_b                          => clog2(D),
      numwords_a                         => D,
      numwords_b                         => D,
      width_byteena_a                    => NLANES,
      width_byteena_b                    => NLANES,
      byte_size                          => byte_size_of(W, NLANES),
      address_reg_b                      => clk_b_name(COMMON_CLK),
      indata_reg_b                       => clk_b_name(COMMON_CLK),
      wrcontrol_wraddress_reg_b          => clk_b_name(COMMON_CLK),
      byteena_reg_b                      => clk_b_name(COMMON_CLK),
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
      clock0    => a_clk,
      clocken0  => clken,
      clock1    => b_clk,
      clocken1  => clkenb,
      address_a => std_logic_vector(a_addr_i),
      data_a    => std_logic_vector(a_wdata_i),
      wren_a    => a_we_i,
      byteena_a => std_logic_vector(a_lane_we_i),
      q_a       => qa,
      address_b => std_logic_vector(b_addr_i),
      data_b    => std_logic_vector(b_wdata_i),
      wren_b    => b_we_i,
      byteena_b => std_logic_vector(b_lane_we_i),
      q_b       => qb
    );

  a_rdata_o <= std_ulogic_vector(qa);
  b_rdata_o <= std_ulogic_vector(qb);

end architecture rtl;
