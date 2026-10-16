-- sram_macro_saed14.vhd — SAED14 SRAM macro tile (TECH_SAED14).
--
-- VHDL-2008 twin of sram_macro_saed14.sv: one single-port macro of MAC_W x
-- MAC_D chosen by sram_pkg macro_width / macro_depth.
--
-- Pin mapping:
--   CE = clk, CSB = cs_i (ACTIVE HIGH: SAED14nm Memories databook),
--   WEB = not write (active low), OEB = 0.
--   Quirk: SRAM1RW32x8 has a 32-bit I bus (model and liberty); its data is
--   zero-extended.
--   Read data is registered on CE: valid in the cycle after a read. The macro
--   has no byte mask; columns lie inside one write lane, so wbe_i is
--   all-equal and wbe_i(0) gates the write.
-- ls_i / ds_i / sd_i are unused: no sleep pins on this macro family (UPF).
-- The macros are Verilog models: they are declared as components (vendor
-- primitives) with std_logic ports, as the Verilog ports map to std_logic.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sram_pkg.all;

entity sram_macro_saed14 is
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
end entity sram_macro_saed14;

architecture rtl of sram_macro_saed14 is

  component SRAM1RW16x8 is
    port (
      A   : in  std_logic_vector(3 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(7 downto 0);
      O   : out std_logic_vector(7 downto 0)
    );
  end component SRAM1RW16x8;
  component SRAM1RW32x8 is
    port (
      A   : in  std_logic_vector(4 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(31 downto 0); -- 32 bits: macro quirk
      O   : out std_logic_vector(7 downto 0)
    );
  end component SRAM1RW32x8;
  component SRAM1RW64x8 is
    port (
      A   : in  std_logic_vector(5 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(7 downto 0);
      O   : out std_logic_vector(7 downto 0)
    );
  end component SRAM1RW64x8;
  component SRAM1RW128x8 is
    port (
      A   : in  std_logic_vector(6 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(7 downto 0);
      O   : out std_logic_vector(7 downto 0)
    );
  end component SRAM1RW128x8;
  component SRAM1RW256x8 is
    port (
      A   : in  std_logic_vector(7 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(7 downto 0);
      O   : out std_logic_vector(7 downto 0)
    );
  end component SRAM1RW256x8;
  component SRAM1RW512x8 is
    port (
      A   : in  std_logic_vector(8 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(7 downto 0);
      O   : out std_logic_vector(7 downto 0)
    );
  end component SRAM1RW512x8;
  component SRAM1RW16x32 is
    port (
      A   : in  std_logic_vector(3 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(31 downto 0);
      O   : out std_logic_vector(31 downto 0)
    );
  end component SRAM1RW16x32;
  component SRAM1RW32x32 is
    port (
      A   : in  std_logic_vector(4 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(31 downto 0);
      O   : out std_logic_vector(31 downto 0)
    );
  end component SRAM1RW32x32;
  component SRAM1RW64x32 is
    port (
      A   : in  std_logic_vector(5 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(31 downto 0);
      O   : out std_logic_vector(31 downto 0)
    );
  end component SRAM1RW64x32;
  component SRAM1RW128x32 is
    port (
      A   : in  std_logic_vector(6 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(31 downto 0);
      O   : out std_logic_vector(31 downto 0)
    );
  end component SRAM1RW128x32;
  component SRAM1RW256x32 is
    port (
      A   : in  std_logic_vector(7 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(31 downto 0);
      O   : out std_logic_vector(31 downto 0)
    );
  end component SRAM1RW256x32;
  component SRAM1RW512x32 is
    port (
      A   : in  std_logic_vector(8 downto 0);
      CE  : in  std_logic;
      WEB : in  std_logic;
      OEB : in  std_logic;
      CSB : in  std_logic;
      I   : in  std_logic_vector(31 downto 0);
      O   : out std_logic_vector(31 downto 0)
    );
  end component SRAM1RW512x32;

  signal csb : std_logic; -- chip select, macro polarity
  signal web : std_logic; -- write enable, active low

begin

  csb <= cs_i;
  web <= not (we_i and wbe_i(0));

  -- Elaboration-time error: no macro of this size in the curated list.
  assert_size_a : assert (MAC_W = 8 and MAC_D = 16) or
                            (MAC_W = 8 and MAC_D = 32) or
                            (MAC_W = 8 and MAC_D = 64) or
                            (MAC_W = 8 and MAC_D = 128) or
                            (MAC_W = 8 and MAC_D = 256) or
                            (MAC_W = 8 and MAC_D = 512) or
                            (MAC_W = 32 and MAC_D = 16) or
                            (MAC_W = 32 and MAC_D = 32) or
                            (MAC_W = 32 and MAC_D = 64) or
                            (MAC_W = 32 and MAC_D = 128) or
                            (MAC_W = 32 and MAC_D = 256) or
                            (MAC_W = 32 and MAC_D = 512)
      report "sram_macro_saed14: no macro of this size" severity failure;

  gen_8x16 : if MAC_W = 8 and MAC_D = 16 generate
    signal o : std_logic_vector(7 downto 0);
  begin
    u_macro : SRAM1RW16x8
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
  end generate gen_8x16;

  gen_8x32 : if MAC_W = 8 and MAC_D = 32 generate
    signal o : std_logic_vector(7 downto 0);
  begin
    u_macro : SRAM1RW32x8
      port map (
        A   => std_logic_vector(addr_i),
        CE  => clk,
        WEB => web,
        OEB => '0',
        CSB => csb,
        I   => std_logic_vector(resize(unsigned(wdata_i), 32)),
        O   => o
      );
    rdata_o <= std_ulogic_vector(o);
  end generate gen_8x32;

  gen_8x64 : if MAC_W = 8 and MAC_D = 64 generate
    signal o : std_logic_vector(7 downto 0);
  begin
    u_macro : SRAM1RW64x8
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
    u_macro : SRAM1RW128x8
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
    u_macro : SRAM1RW256x8
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
    u_macro : SRAM1RW512x8
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

  gen_32x16 : if MAC_W = 32 and MAC_D = 16 generate
    signal o : std_logic_vector(31 downto 0);
  begin
    u_macro : SRAM1RW16x32
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
  end generate gen_32x16;

  gen_32x32 : if MAC_W = 32 and MAC_D = 32 generate
    signal o : std_logic_vector(31 downto 0);
  begin
    u_macro : SRAM1RW32x32
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
  end generate gen_32x32;

  gen_32x64 : if MAC_W = 32 and MAC_D = 64 generate
    signal o : std_logic_vector(31 downto 0);
  begin
    u_macro : SRAM1RW64x32
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

  gen_32x128 : if MAC_W = 32 and MAC_D = 128 generate
    signal o : std_logic_vector(31 downto 0);
  begin
    u_macro : SRAM1RW128x32
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
  end generate gen_32x128;

  gen_32x256 : if MAC_W = 32 and MAC_D = 256 generate
    signal o : std_logic_vector(31 downto 0);
  begin
    u_macro : SRAM1RW256x32
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
    u_macro : SRAM1RW512x32
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
