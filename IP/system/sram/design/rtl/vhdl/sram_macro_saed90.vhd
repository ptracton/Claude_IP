-- sram_macro_saed90.vhd — SAED90 SRAM macro tile (TECH_SAED90).
--
-- VHDL-2008 twin of sram_macro_saed90.sv: one single-port macro of MAC_W x
-- MAC_D chosen by sram_pkg macro_width / macro_depth.
--
-- Pin mapping:
--   CE = clk, CSB = not cs_i (active low), WEB = not write (active low), OEB = 0.
--   Read data is registered on CE: valid in the cycle after a read. The macro
--   has no byte mask; columns lie inside one write lane, so wbe_i is
--   all-equal and wbe_i(0) gates the write.
-- ls_i / ds_i / sd_i are unused: no sleep pins on this macro family (UPF).
-- The macros are Verilog models: they are declared as components (vendor
-- primitives) with std_logic ports, as the Verilog ports map to std_logic.

library ieee;
use ieee.std_logic_1164.all;
use work.sram_pkg.all;

entity sram_macro_saed90 is
  generic (
    MAC_W : positive := 8; -- macro word width
    MAC_D : positive := 64 -- macro words
  );
  port (
    clk     : in  std_ulogic;                                   -- clock (macro CE)
    cs_i    : in  std_ulogic;                                   -- chip select
    we_i    : in  std_ulogic;                                   -- 1 = write, 0 = read
    addr_i  : in  std_ulogic_vector(clog2(MAC_D) - 1 downto 0); -- word address
    wdata_i : in  std_ulogic_vector(MAC_W - 1 downto 0);        -- write data
    wbe_i   : in  std_ulogic_vector(MAC_W / 8 - 1 downto 0);    -- byte write enables
    ls_i    : in  std_ulogic;                                   -- light sleep
    ds_i    : in  std_ulogic;                                   -- deep sleep
    sd_i    : in  std_ulogic;                                   -- shutdown
    rdata_o : out std_ulogic_vector(MAC_W - 1 downto 0)         -- read data
  );
end entity sram_macro_saed90;

architecture rtl of sram_macro_saed90 is

  component SRAM8x64_1rw is
    port (
      A   : in  std_logic_vector(5 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(7 downto 0);
      O   : out std_logic_vector(7 downto 0)
    );
  end component SRAM8x64_1rw;
  component SRAM8x128_1rw is
    port (
      A   : in  std_logic_vector(6 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(7 downto 0);
      O   : out std_logic_vector(7 downto 0)
    );
  end component SRAM8x128_1rw;
  component SRAM8x256_1rw is
    port (
      A   : in  std_logic_vector(7 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(7 downto 0);
      O   : out std_logic_vector(7 downto 0)
    );
  end component SRAM8x256_1rw;
  component SRAM8x512_1rw is
    port (
      A   : in  std_logic_vector(8 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(7 downto 0);
      O   : out std_logic_vector(7 downto 0)
    );
  end component SRAM8x512_1rw;
  component SRAM8x1024_1rw is
    port (
      A   : in  std_logic_vector(9 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(7 downto 0);
      O   : out std_logic_vector(7 downto 0)
    );
  end component SRAM8x1024_1rw;
  component SRAM32x64_1rw is
    port (
      A   : in  std_logic_vector(5 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(31 downto 0);
      O   : out std_logic_vector(31 downto 0)
    );
  end component SRAM32x64_1rw;
  component SRAM32x256_1rw is
    port (
      A   : in  std_logic_vector(7 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(31 downto 0);
      O   : out std_logic_vector(31 downto 0)
    );
  end component SRAM32x256_1rw;
  component SRAM32x512_1rw is
    port (
      A   : in  std_logic_vector(8 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(31 downto 0);
      O   : out std_logic_vector(31 downto 0)
    );
  end component SRAM32x512_1rw;

  signal csb : std_logic; -- chip select, macro polarity
  signal web : std_logic; -- write enable, active low

begin

  csb <= not cs_i;
  web <= not (we_i and wbe_i(0));

  -- Elaboration-time error: no macro of this size in the curated list.
  assert_size_a : assert (MAC_W = 8 and MAC_D = 64) or
                            (MAC_W = 8 and MAC_D = 128) or
                            (MAC_W = 8 and MAC_D = 256) or
                            (MAC_W = 8 and MAC_D = 512) or
                            (MAC_W = 8 and MAC_D = 1024) or
                            (MAC_W = 32 and MAC_D = 64) or
                            (MAC_W = 32 and MAC_D = 256) or
                            (MAC_W = 32 and MAC_D = 512)
      report "sram_macro_saed90: no macro of this size" severity failure;

  gen_8x64 : if MAC_W = 8 and MAC_D = 64 generate
    signal o : std_logic_vector(7 downto 0);
  begin
    u_macro : SRAM8x64_1rw
      port map (
        A   => std_logic_vector(addr_i),
        CE  => clk,
        WEB => web,
        OEB => '0',
        CSB => csb,
        I   => std_logic_vector(wdata_i),
        O   => o
      );
    rdata_o <= std_ulogic_vector(o);
  end generate gen_8x64;

  gen_8x128 : if MAC_W = 8 and MAC_D = 128 generate
    signal o : std_logic_vector(7 downto 0);
  begin
    u_macro : SRAM8x128_1rw
      port map (
        A   => std_logic_vector(addr_i),
        CE  => clk,
        WEB => web,
        OEB => '0',
        CSB => csb,
        I   => std_logic_vector(wdata_i),
        O   => o
      );
    rdata_o <= std_ulogic_vector(o);
  end generate gen_8x128;

  gen_8x256 : if MAC_W = 8 and MAC_D = 256 generate
    signal o : std_logic_vector(7 downto 0);
  begin
    u_macro : SRAM8x256_1rw
      port map (
        A   => std_logic_vector(addr_i),
        CE  => clk,
        WEB => web,
        OEB => '0',
        CSB => csb,
        I   => std_logic_vector(wdata_i),
        O   => o
      );
    rdata_o <= std_ulogic_vector(o);
  end generate gen_8x256;

  gen_8x512 : if MAC_W = 8 and MAC_D = 512 generate
    signal o : std_logic_vector(7 downto 0);
  begin
    u_macro : SRAM8x512_1rw
      port map (
        A   => std_logic_vector(addr_i),
        CE  => clk,
        WEB => web,
        OEB => '0',
        CSB => csb,
        I   => std_logic_vector(wdata_i),
        O   => o
      );
    rdata_o <= std_ulogic_vector(o);
  end generate gen_8x512;

  gen_8x1024 : if MAC_W = 8 and MAC_D = 1024 generate
    signal o : std_logic_vector(7 downto 0);
  begin
    u_macro : SRAM8x1024_1rw
      port map (
        A   => std_logic_vector(addr_i),
        CE  => clk,
        WEB => web,
        OEB => '0',
        CSB => csb,
        I   => std_logic_vector(wdata_i),
        O   => o
      );
    rdata_o <= std_ulogic_vector(o);
  end generate gen_8x1024;

  gen_32x64 : if MAC_W = 32 and MAC_D = 64 generate
    signal o : std_logic_vector(31 downto 0);
  begin
    u_macro : SRAM32x64_1rw
      port map (
        A   => std_logic_vector(addr_i),
        CE  => clk,
        WEB => web,
        OEB => '0',
        CSB => csb,
        I   => std_logic_vector(wdata_i),
        O   => o
      );
    rdata_o <= std_ulogic_vector(o);
  end generate gen_32x64;

  gen_32x256 : if MAC_W = 32 and MAC_D = 256 generate
    signal o : std_logic_vector(31 downto 0);
  begin
    u_macro : SRAM32x256_1rw
      port map (
        A   => std_logic_vector(addr_i),
        CE  => clk,
        WEB => web,
        OEB => '0',
        CSB => csb,
        I   => std_logic_vector(wdata_i),
        O   => o
      );
    rdata_o <= std_ulogic_vector(o);
  end generate gen_32x256;

  gen_32x512 : if MAC_W = 32 and MAC_D = 512 generate
    signal o : std_logic_vector(31 downto 0);
  begin
    u_macro : SRAM32x512_1rw
      port map (
        A   => std_logic_vector(addr_i),
        CE  => clk,
        WEB => web,
        OEB => '0',
        CSB => csb,
        I   => std_logic_vector(wdata_i),
        O   => o
      );
    rdata_o <= std_ulogic_vector(o);
  end generate gen_32x512;

end architecture rtl;
