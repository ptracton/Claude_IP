-- sram_macro_dp_sky130.vhd — SKY130 OpenRAM macro tile (TECH_SKY130, DUAL_PORT).
--
-- VHDL-2008 twin of sram_macro_dp_sky130.sv: port 0 = port A (read/write),
-- port 1 = port B (READ ONLY; the core turns port-B writes into bus errors,
-- so b_we_i / b_wdata_i / b_wbe_i are unused). Read data valid in the cycle
-- after a read; simulation clock period > ~8 ns. No sleep pins (UPF).

library ieee;
use ieee.std_logic_1164.all;
use work.sram_pkg.all;

entity sram_macro_dp_sky130 is
  generic (
    MAC_W : positive := 32;   -- macro word width
    MAC_D : positive := 512   -- macro words
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
end entity sram_macro_dp_sky130;

architecture rtl of sram_macro_dp_sky130 is

  component sky130_sram_1kbyte_1rw1r_32x256_8 is
    generic (
      VERBOSE : integer := 1
    );
    port (
      clk0   : in  std_logic;
      csb0   : in  std_logic;
      web0   : in  std_logic;
      wmask0 : in  std_logic_vector(3 downto 0);
      addr0  : in  std_logic_vector(7 downto 0);
      din0   : in  std_logic_vector(31 downto 0);
      dout0  : out std_logic_vector(31 downto 0);
      clk1   : in  std_logic;
      csb1   : in  std_logic;
      addr1  : in  std_logic_vector(7 downto 0);
      dout1  : out std_logic_vector(31 downto 0)
    );
  end component sky130_sram_1kbyte_1rw1r_32x256_8;
  component sky130_sram_2kbyte_1rw1r_32x512_8 is
    generic (
      VERBOSE : integer := 1
    );
    port (
      clk0   : in  std_logic;
      csb0   : in  std_logic;
      web0   : in  std_logic;
      wmask0 : in  std_logic_vector(3 downto 0);
      addr0  : in  std_logic_vector(8 downto 0);
      din0   : in  std_logic_vector(31 downto 0);
      dout0  : out std_logic_vector(31 downto 0);
      clk1   : in  std_logic;
      csb1   : in  std_logic;
      addr1  : in  std_logic_vector(8 downto 0);
      dout1  : out std_logic_vector(31 downto 0)
    );
  end component sky130_sram_2kbyte_1rw1r_32x512_8;
  component sky130_sram_1kbyte_1rw1r_8x1024_8 is
    generic (
      VERBOSE : integer := 1
    );
    port (
      clk0   : in  std_logic;
      csb0   : in  std_logic;
      web0   : in  std_logic;
      wmask0 : in  std_logic_vector(0 downto 0);
      addr0  : in  std_logic_vector(9 downto 0);
      din0   : in  std_logic_vector(7 downto 0);
      dout0  : out std_logic_vector(7 downto 0);
      clk1   : in  std_logic;
      csb1   : in  std_logic;
      addr1  : in  std_logic_vector(9 downto 0);
      dout1  : out std_logic_vector(7 downto 0)
    );
  end component sky130_sram_1kbyte_1rw1r_8x1024_8;

  signal a_csb : std_logic;  -- port A chip select, active low
  signal b_csb : std_logic;  -- port B chip select, active low
  signal a_web : std_logic;  -- port A write enable, active low

begin

  a_csb <= not a_cs_i;
  b_csb <= not b_cs_i;
  a_web <= not a_we_i;

  -- Elaboration-time error: no macro of this size in the curated list.
  assert_size_a : assert (MAC_W = 32 and MAC_D = 256) or (MAC_W = 32 and MAC_D = 512) or
                         (MAC_W = 8 and MAC_D = 1024)
      report "sram_macro_dp_sky130: no macro of this size" severity failure;

  gen_32x256 : if MAC_W = 32 and MAC_D = 256 generate
    signal o0 : std_logic_vector(31 downto 0);
    signal o1 : std_logic_vector(31 downto 0);
  begin
    u_macro : sky130_sram_1kbyte_1rw1r_32x256_8
      generic map (
        VERBOSE => 0
      )
      port map (
        clk0   => clk,
        csb0   => a_csb,
        web0   => a_web,
        wmask0 => std_logic_vector(a_wbe_i),
        addr0  => std_logic_vector(a_addr_i),
        din0   => std_logic_vector(a_wdata_i),
        dout0  => o0,
        clk1   => clk,
        csb1   => b_csb,
        addr1  => std_logic_vector(b_addr_i),
        dout1  => o1
      );
    a_rdata_o <= std_ulogic_vector(o0);
    b_rdata_o <= std_ulogic_vector(o1);
  end generate gen_32x256;

  gen_32x512 : if MAC_W = 32 and MAC_D = 512 generate
    signal o0 : std_logic_vector(31 downto 0);
    signal o1 : std_logic_vector(31 downto 0);
  begin
    u_macro : sky130_sram_2kbyte_1rw1r_32x512_8
      generic map (
        VERBOSE => 0
      )
      port map (
        clk0   => clk,
        csb0   => a_csb,
        web0   => a_web,
        wmask0 => std_logic_vector(a_wbe_i),
        addr0  => std_logic_vector(a_addr_i),
        din0   => std_logic_vector(a_wdata_i),
        dout0  => o0,
        clk1   => clk,
        csb1   => b_csb,
        addr1  => std_logic_vector(b_addr_i),
        dout1  => o1
      );
    a_rdata_o <= std_ulogic_vector(o0);
    b_rdata_o <= std_ulogic_vector(o1);
  end generate gen_32x512;

  gen_8x1024 : if MAC_W = 8 and MAC_D = 1024 generate
    signal o0 : std_logic_vector(7 downto 0);
    signal o1 : std_logic_vector(7 downto 0);
  begin
    u_macro : sky130_sram_1kbyte_1rw1r_8x1024_8
      generic map (
        VERBOSE => 0
      )
      port map (
        clk0   => clk,
        csb0   => a_csb,
        web0   => a_web,
        wmask0 => std_logic_vector(a_wbe_i),
        addr0  => std_logic_vector(a_addr_i),
        din0   => std_logic_vector(a_wdata_i),
        dout0  => o0,
        clk1   => clk,
        csb1   => b_csb,
        addr1  => std_logic_vector(b_addr_i),
        dout1  => o1
      );
    a_rdata_o <= std_ulogic_vector(o0);
    b_rdata_o <= std_ulogic_vector(o1);
  end generate gen_8x1024;

end architecture rtl;
