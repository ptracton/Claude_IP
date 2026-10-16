-- sram_macro.vhd — Technology dispatcher for one sram array tile.
--
-- VHDL-2008 twin of sram_macro.sv: instantiates the leaf for TECH
-- (sram_pkg TECH_*_C). Only the selected branch is elaborated, so a host only
-- needs the macro library (or XPM / altera_mf) of the technology it builds.

library ieee;
use ieee.std_logic_1164.all;
use work.sram_pkg.all;

entity sram_macro is
  generic (
    TECH      : natural  := TECH_GENERIC_C; -- technology
    MAC_W     : positive := 32;             -- tile word width
    MAC_D     : positive := 1024;           -- tile words
    INIT_FILE : string   := ""              -- preload (GENERIC/FPGA)
  );
  port (
    clk     : in  std_ulogic;                                   -- clock
    cs_i    : in  std_ulogic;                                   -- chip select
    we_i    : in  std_ulogic;                                   -- 1 = write, 0 = read
    addr_i  : in  std_ulogic_vector(clog2(MAC_D) - 1 downto 0); -- word address
    wdata_i : in  std_ulogic_vector(MAC_W - 1 downto 0);        -- write data
    wbe_i   : in  std_ulogic_vector(MAC_W / 8 - 1 downto 0);    -- byte write enables
    ls_i    : in  std_ulogic;                                   -- light sleep
    ds_i    : in  std_ulogic;                                   -- deep sleep
    sd_i    : in  std_ulogic;                                   -- shutdown
    rdata_o : out std_ulogic_vector(MAC_W - 1 downto 0)         -- read data (cycle after a read)
  );
end entity sram_macro;

architecture rtl of sram_macro is
begin

  gen_tech : if TECH = TECH_SAED90_C generate
    u_leaf : entity work.sram_macro_saed90(rtl)
      generic map (
        MAC_W => MAC_W,
        MAC_D => MAC_D
      )
      port map (
        clk     => clk,
        cs_i    => cs_i,
        we_i    => we_i,
        addr_i  => addr_i,
        wdata_i => wdata_i,
        wbe_i   => wbe_i,
        ls_i    => ls_i,
        ds_i    => ds_i,
        sd_i    => sd_i,
        rdata_o => rdata_o
      );
  elsif TECH = TECH_SAED32_C generate
    u_leaf : entity work.sram_macro_saed32(rtl)
      generic map (
        MAC_W => MAC_W,
        MAC_D => MAC_D
      )
      port map (
        clk     => clk,
        cs_i    => cs_i,
        we_i    => we_i,
        addr_i  => addr_i,
        wdata_i => wdata_i,
        wbe_i   => wbe_i,
        ls_i    => ls_i,
        ds_i    => ds_i,
        sd_i    => sd_i,
        rdata_o => rdata_o
      );
  elsif TECH = TECH_SAED14_C generate
    u_leaf : entity work.sram_macro_saed14(rtl)
      generic map (
        MAC_W => MAC_W,
        MAC_D => MAC_D
      )
      port map (
        clk     => clk,
        cs_i    => cs_i,
        we_i    => we_i,
        addr_i  => addr_i,
        wdata_i => wdata_i,
        wbe_i   => wbe_i,
        ls_i    => ls_i,
        ds_i    => ds_i,
        sd_i    => sd_i,
        rdata_o => rdata_o
      );
  elsif TECH = TECH_SKY130_C generate
    u_leaf : entity work.sram_macro_sky130(rtl)
      generic map (
        MAC_W => MAC_W,
        MAC_D => MAC_D
      )
      port map (
        clk     => clk,
        cs_i    => cs_i,
        we_i    => we_i,
        addr_i  => addr_i,
        wdata_i => wdata_i,
        wbe_i   => wbe_i,
        ls_i    => ls_i,
        ds_i    => ds_i,
        sd_i    => sd_i,
        rdata_o => rdata_o
      );
  elsif TECH = TECH_XILINX_C generate
    u_leaf : entity work.sram_macro_xilinx(rtl)
      generic map (
        MAC_W     => MAC_W,
        MAC_D     => MAC_D,
        INIT_FILE => INIT_FILE
      )
      port map (
        clk     => clk,
        cs_i    => cs_i,
        we_i    => we_i,
        addr_i  => addr_i,
        wdata_i => wdata_i,
        wbe_i   => wbe_i,
        ls_i    => ls_i,
        ds_i    => ds_i,
        sd_i    => sd_i,
        rdata_o => rdata_o
      );
  elsif TECH = TECH_ALTERA_C generate
    u_leaf : entity work.sram_macro_altera(rtl)
      generic map (
        MAC_W     => MAC_W,
        MAC_D     => MAC_D,
        INIT_FILE => INIT_FILE
      )
      port map (
        clk     => clk,
        cs_i    => cs_i,
        we_i    => we_i,
        addr_i  => addr_i,
        wdata_i => wdata_i,
        wbe_i   => wbe_i,
        ls_i    => ls_i,
        ds_i    => ds_i,
        sd_i    => sd_i,
        rdata_o => rdata_o
      );
  else generate
    u_leaf : entity work.sram_macro_generic(rtl)
      generic map (
        MAC_W     => MAC_W,
        MAC_D     => MAC_D,
        INIT_FILE => INIT_FILE
      )
      port map (
        clk     => clk,
        cs_i    => cs_i,
        we_i    => we_i,
        addr_i  => addr_i,
        wdata_i => wdata_i,
        wbe_i   => wbe_i,
        ls_i    => ls_i,
        ds_i    => ds_i,
        sd_i    => sd_i,
        rdata_o => rdata_o
      );
  end generate gen_tech;

end architecture rtl;
