-- sram_macro_sky130.vhd — SkyWater SKY130 OpenRAM macro tile (TECH_SKY130).
--
-- VHDL-2008 twin of sram_macro_sky130.sv. One OpenRAM 1rw1r macro:
--   32 x 256   sky130_sram_1kbyte_1rw1r_32x256_8   (wmask0(3 downto 0))
--   32 x 512   sky130_sram_2kbyte_1rw1r_32x512_8   (wmask0(3 downto 0))
--    8 x 1024  sky130_sram_1kbyte_1rw1r_8x1024_8   (wmask0(0))
-- Port 0 read/write (csb0 = not cs_i, web0 = not we_i, wmask0 = wbe_i);
-- port 1 deselected (csb1 = 1). Read data valid in the cycle after a read;
-- the simulation clock period must exceed ~8 ns. VERBOSE = 0.
-- ls_i / ds_i / sd_i are unused: no sleep pins (power through UPF).
-- The macros are Verilog models declared as components (vendor primitives).

library ieee;
use ieee.std_logic_1164.all;
use work.sram_pkg.all;

entity sram_macro_sky130 is
  generic (
    MAC_W : positive := 32; -- macro word width
    MAC_D : positive := 512 -- macro words
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
end entity sram_macro_sky130;

architecture rtl of sram_macro_sky130 is

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

  signal csb : std_logic; -- chip select, active low
  signal web : std_logic; -- write enable, active low

begin

  csb <= not cs_i;
  web <= not we_i;

  -- Elaboration-time error: no macro of this size in the curated list.
  assert_size_a : assert (MAC_W = 32 and MAC_D = 256) or (MAC_W = 32 and MAC_D = 512) or
                         (MAC_W = 8 and MAC_D = 1024)
      report "sram_macro_sky130: no macro of this size" severity failure;

  gen_32x256 : if MAC_W = 32 and MAC_D = 256 generate
    signal o : std_logic_vector(31 downto 0);
  begin
    u_macro : sky130_sram_1kbyte_1rw1r_32x256_8
      generic map (
        VERBOSE => 0
      )
      port map (
        clk0   => clk,
        csb0   => csb,
        web0   => web,
        wmask0 => std_logic_vector(wbe_i),
        addr0  => std_logic_vector(addr_i),
        din0   => std_logic_vector(wdata_i),
        dout0  => o,
        clk1   => clk,
        csb1   => '1',
        addr1  => (others => '0'),
        dout1  => open
      );
    rdata_o <= std_ulogic_vector(o);
  end generate gen_32x256;

  gen_32x512 : if MAC_W = 32 and MAC_D = 512 generate
    signal o : std_logic_vector(31 downto 0);
  begin
    u_macro : sky130_sram_2kbyte_1rw1r_32x512_8
      generic map (
        VERBOSE => 0
      )
      port map (
        clk0   => clk,
        csb0   => csb,
        web0   => web,
        wmask0 => std_logic_vector(wbe_i),
        addr0  => std_logic_vector(addr_i),
        din0   => std_logic_vector(wdata_i),
        dout0  => o,
        clk1   => clk,
        csb1   => '1',
        addr1  => (others => '0'),
        dout1  => open
      );
    rdata_o <= std_ulogic_vector(o);
  end generate gen_32x512;

  gen_8x1024 : if MAC_W = 8 and MAC_D = 1024 generate
    signal o : std_logic_vector(7 downto 0);
  begin
    u_macro : sky130_sram_1kbyte_1rw1r_8x1024_8
      generic map (
        VERBOSE => 0
      )
      port map (
        clk0   => clk,
        csb0   => csb,
        web0   => web,
        wmask0 => std_logic_vector(wbe_i),
        addr0  => std_logic_vector(addr_i),
        din0   => std_logic_vector(wdata_i),
        dout0  => o,
        clk1   => clk,
        csb1   => '1',
        addr1  => (others => '0'),
        dout1  => open
      );
    rdata_o <= std_ulogic_vector(o);
  end generate gen_8x1024;

end architecture rtl;
