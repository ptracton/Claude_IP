-- sram_macro.vhd — Technology dispatcher for one sram bank.
--
-- VHDL-2008 twin of sram_macro.sv: instantiates the W x D wrapper for TECH
-- (sram_pkg TECH_*_C). The ASIC wrappers tile their primitives; GENERIC /
-- XILINX / ALTERA infer one memory and leave tiling to the tool. Only the
-- selected branch is elaborated, so a host only needs the macro library (or
-- XPM / altera_mf) of the technology it builds.

library ieee;
use ieee.std_logic_1164.all;
use work.sram_pkg.all;

entity sram_macro is
  generic (
    TECH      : natural  := TECH_GENERIC_C; -- technology
    W         : positive := 32;             -- word width
    D         : positive := 1024;           -- words (power of two)
    NLANES    : positive := 4;              -- write lanes of W / NLANES bits
    INIT_FILE : string   := ""              -- preload (GENERIC/FPGA)
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
    rdata_o   : out std_ulogic_vector(W - 1 downto 0)         -- read data (cycle after a read)
  );
end entity sram_macro;

architecture rtl of sram_macro is
begin

  gen_tech : if TECH = TECH_SAED90_C generate
    u_leaf : entity work.sram_macro_saed90(rtl)
      generic map (
        W      => W,
        D      => D,
        NLANES => NLANES
      )
      port map (
        clk       => clk,
        cs_i      => cs_i,
        we_i      => we_i,
        addr_i    => addr_i,
        wdata_i   => wdata_i,
        lane_we_i => lane_we_i,
        ls_i      => ls_i,
        ds_i      => ds_i,
        sd_i      => sd_i,
        rdata_o   => rdata_o
      );
  elsif TECH = TECH_SAED32_C generate
    u_leaf : entity work.sram_macro_saed32(rtl)
      generic map (
        W      => W,
        D      => D,
        NLANES => NLANES
      )
      port map (
        clk       => clk,
        cs_i      => cs_i,
        we_i      => we_i,
        addr_i    => addr_i,
        wdata_i   => wdata_i,
        lane_we_i => lane_we_i,
        ls_i      => ls_i,
        ds_i      => ds_i,
        sd_i      => sd_i,
        rdata_o   => rdata_o
      );
  elsif TECH = TECH_SAED14_C generate
    u_leaf : entity work.sram_macro_saed14(rtl)
      generic map (
        W      => W,
        D      => D,
        NLANES => NLANES
      )
      port map (
        clk       => clk,
        cs_i      => cs_i,
        we_i      => we_i,
        addr_i    => addr_i,
        wdata_i   => wdata_i,
        lane_we_i => lane_we_i,
        ls_i      => ls_i,
        ds_i      => ds_i,
        sd_i      => sd_i,
        rdata_o   => rdata_o
      );
  elsif TECH = TECH_SKY130_C generate
    u_leaf : entity work.sram_macro_sky130(rtl)
      generic map (
        W      => W,
        D      => D,
        NLANES => NLANES
      )
      port map (
        clk       => clk,
        cs_i      => cs_i,
        we_i      => we_i,
        addr_i    => addr_i,
        wdata_i   => wdata_i,
        lane_we_i => lane_we_i,
        ls_i      => ls_i,
        ds_i      => ds_i,
        sd_i      => sd_i,
        rdata_o   => rdata_o
      );
  elsif TECH = TECH_XILINX_C generate
    u_leaf : entity work.sram_macro_xilinx(rtl)
      generic map (
        W         => W,
        D         => D,
        NLANES    => NLANES,
        INIT_FILE => INIT_FILE
      )
      port map (
        clk       => clk,
        cs_i      => cs_i,
        we_i      => we_i,
        addr_i    => addr_i,
        wdata_i   => wdata_i,
        lane_we_i => lane_we_i,
        ls_i      => ls_i,
        ds_i      => ds_i,
        sd_i      => sd_i,
        rdata_o   => rdata_o
      );
  elsif TECH = TECH_ALTERA_C generate
    u_leaf : entity work.sram_macro_altera(rtl)
      generic map (
        W         => W,
        D         => D,
        NLANES    => NLANES,
        INIT_FILE => INIT_FILE
      )
      port map (
        clk       => clk,
        cs_i      => cs_i,
        we_i      => we_i,
        addr_i    => addr_i,
        wdata_i   => wdata_i,
        lane_we_i => lane_we_i,
        ls_i      => ls_i,
        ds_i      => ds_i,
        sd_i      => sd_i,
        rdata_o   => rdata_o
      );
  else generate
    u_leaf : entity work.sram_macro_generic(rtl)
      generic map (
        W         => W,
        D         => D,
        NLANES    => NLANES,
        INIT_FILE => INIT_FILE
      )
      port map (
        clk       => clk,
        cs_i      => cs_i,
        we_i      => we_i,
        addr_i    => addr_i,
        wdata_i   => wdata_i,
        lane_we_i => lane_we_i,
        ls_i      => ls_i,
        ds_i      => ds_i,
        sd_i      => sd_i,
        rdata_o   => rdata_o
      );
  end generate gen_tech;

end architecture rtl;
