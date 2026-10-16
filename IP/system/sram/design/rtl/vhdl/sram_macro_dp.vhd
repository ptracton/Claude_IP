-- sram_macro_dp.vhd — Technology dispatcher for one two-port sram array tile (DUAL_PORT).
--
-- VHDL-2008 twin of sram_macro_dp.sv: instantiates sram_macro_dp_<tech>.
-- Only the selected branch is elaborated.

library ieee;
use ieee.std_logic_1164.all;
use work.sram_pkg.all;

entity sram_macro_dp is
  generic (
    TECH      : natural  := TECH_GENERIC_C;  -- technology
    MAC_W     : positive := 32;              -- tile word width
    MAC_D     : positive := 1024;            -- tile words
    INIT_FILE : string   := ""               -- preload (GENERIC/FPGA)
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
end entity sram_macro_dp;

architecture rtl of sram_macro_dp is
begin

  gen_tech : if TECH = TECH_SAED90_C generate
    u_leaf : entity work.sram_macro_dp_saed90(rtl)
      generic map (
        MAC_W => MAC_W,
        MAC_D => MAC_D
      )
      port map (
        clk       => clk,
        a_cs_i    => a_cs_i,
        a_we_i    => a_we_i,
        a_addr_i  => a_addr_i,
        a_wdata_i => a_wdata_i,
        a_wbe_i   => a_wbe_i,
        a_rdata_o => a_rdata_o,
        b_cs_i    => b_cs_i,
        b_we_i    => b_we_i,
        b_addr_i  => b_addr_i,
        b_wdata_i => b_wdata_i,
        b_wbe_i   => b_wbe_i,
        b_rdata_o => b_rdata_o,
        ls_i      => ls_i,
        ds_i      => ds_i,
        sd_i      => sd_i
      );
  elsif TECH = TECH_SAED32_C generate
    u_leaf : entity work.sram_macro_dp_saed32(rtl)
      generic map (
        MAC_W => MAC_W,
        MAC_D => MAC_D
      )
      port map (
        clk       => clk,
        a_cs_i    => a_cs_i,
        a_we_i    => a_we_i,
        a_addr_i  => a_addr_i,
        a_wdata_i => a_wdata_i,
        a_wbe_i   => a_wbe_i,
        a_rdata_o => a_rdata_o,
        b_cs_i    => b_cs_i,
        b_we_i    => b_we_i,
        b_addr_i  => b_addr_i,
        b_wdata_i => b_wdata_i,
        b_wbe_i   => b_wbe_i,
        b_rdata_o => b_rdata_o,
        ls_i      => ls_i,
        ds_i      => ds_i,
        sd_i      => sd_i
      );
  elsif TECH = TECH_SAED14_C generate
    u_leaf : entity work.sram_macro_dp_saed14(rtl)
      generic map (
        MAC_W => MAC_W,
        MAC_D => MAC_D
      )
      port map (
        clk       => clk,
        a_cs_i    => a_cs_i,
        a_we_i    => a_we_i,
        a_addr_i  => a_addr_i,
        a_wdata_i => a_wdata_i,
        a_wbe_i   => a_wbe_i,
        a_rdata_o => a_rdata_o,
        b_cs_i    => b_cs_i,
        b_we_i    => b_we_i,
        b_addr_i  => b_addr_i,
        b_wdata_i => b_wdata_i,
        b_wbe_i   => b_wbe_i,
        b_rdata_o => b_rdata_o,
        ls_i      => ls_i,
        ds_i      => ds_i,
        sd_i      => sd_i
      );
  elsif TECH = TECH_SKY130_C generate
    u_leaf : entity work.sram_macro_dp_sky130(rtl)
      generic map (
        MAC_W => MAC_W,
        MAC_D => MAC_D
      )
      port map (
        clk       => clk,
        a_cs_i    => a_cs_i,
        a_we_i    => a_we_i,
        a_addr_i  => a_addr_i,
        a_wdata_i => a_wdata_i,
        a_wbe_i   => a_wbe_i,
        a_rdata_o => a_rdata_o,
        b_cs_i    => b_cs_i,
        b_we_i    => b_we_i,
        b_addr_i  => b_addr_i,
        b_wdata_i => b_wdata_i,
        b_wbe_i   => b_wbe_i,
        b_rdata_o => b_rdata_o,
        ls_i      => ls_i,
        ds_i      => ds_i,
        sd_i      => sd_i
      );
  elsif TECH = TECH_XILINX_C generate
    u_leaf : entity work.sram_macro_dp_xilinx(rtl)
      generic map (
        MAC_W     => MAC_W,
        MAC_D     => MAC_D,
        INIT_FILE => INIT_FILE
      )
      port map (
        clk       => clk,
        a_cs_i    => a_cs_i,
        a_we_i    => a_we_i,
        a_addr_i  => a_addr_i,
        a_wdata_i => a_wdata_i,
        a_wbe_i   => a_wbe_i,
        a_rdata_o => a_rdata_o,
        b_cs_i    => b_cs_i,
        b_we_i    => b_we_i,
        b_addr_i  => b_addr_i,
        b_wdata_i => b_wdata_i,
        b_wbe_i   => b_wbe_i,
        b_rdata_o => b_rdata_o,
        ls_i      => ls_i,
        ds_i      => ds_i,
        sd_i      => sd_i
      );
  elsif TECH = TECH_ALTERA_C generate
    u_leaf : entity work.sram_macro_dp_altera(rtl)
      generic map (
        MAC_W     => MAC_W,
        MAC_D     => MAC_D,
        INIT_FILE => INIT_FILE
      )
      port map (
        clk       => clk,
        a_cs_i    => a_cs_i,
        a_we_i    => a_we_i,
        a_addr_i  => a_addr_i,
        a_wdata_i => a_wdata_i,
        a_wbe_i   => a_wbe_i,
        a_rdata_o => a_rdata_o,
        b_cs_i    => b_cs_i,
        b_we_i    => b_we_i,
        b_addr_i  => b_addr_i,
        b_wdata_i => b_wdata_i,
        b_wbe_i   => b_wbe_i,
        b_rdata_o => b_rdata_o,
        ls_i      => ls_i,
        ds_i      => ds_i,
        sd_i      => sd_i
      );
  else generate
    u_leaf : entity work.sram_macro_dp_generic(rtl)
      generic map (
        MAC_W     => MAC_W,
        MAC_D     => MAC_D,
        INIT_FILE => INIT_FILE
      )
      port map (
        clk       => clk,
        a_cs_i    => a_cs_i,
        a_we_i    => a_we_i,
        a_addr_i  => a_addr_i,
        a_wdata_i => a_wdata_i,
        a_wbe_i   => a_wbe_i,
        a_rdata_o => a_rdata_o,
        b_cs_i    => b_cs_i,
        b_we_i    => b_we_i,
        b_addr_i  => b_addr_i,
        b_wdata_i => b_wdata_i,
        b_wbe_i   => b_wbe_i,
        b_rdata_o => b_rdata_o,
        ls_i      => ls_i,
        ds_i      => ds_i,
        sd_i      => sd_i
      );
  end generate gen_tech;

end architecture rtl;
