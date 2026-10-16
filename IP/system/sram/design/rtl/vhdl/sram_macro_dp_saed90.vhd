-- sram_macro_dp_saed90.vhd — SAED90 two-port SRAM macro tile (DUAL_PORT).
--
-- VHDL-2008 twin of sram_macro_dp_saed90.sv: one SAED90 (two-port) macro of
-- MAC_W x MAC_D (sram_pkg macro_width_dp / macro_depth_dp), two independent
-- read/write ports on one clock.
--
-- Pin mapping:
--   CE1 = CE2 = clk; CSB1/CSB2 = not cs (active low); WEB1/WEB2 = not write;
--   OEB1 = OEB2 = 0.
--   Read data is registered: valid in the cycle after a read. No byte mask:
--   *_wbe_i is all-equal and bit 0 gates the write.
-- ls_i / ds_i / sd_i are unused: no sleep pins on this macro family (UPF).
-- The macros are Verilog models declared as components (vendor primitives).

library ieee;
use ieee.std_logic_1164.all;
use work.sram_pkg.all;

entity sram_macro_dp_saed90 is
  generic (
    MAC_W : positive := 8;   -- macro word width
    MAC_D : positive := 64   -- macro words
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
end entity sram_macro_dp_saed90;

architecture rtl of sram_macro_dp_saed90 is

  component SRAM8x16 is
    port (
      A1   : in  std_logic_vector(3 downto 0);
      A2   : in  std_logic_vector(3 downto 0);
      CE1  : in  std_logic;
      CE2  : in  std_logic;
      WEB1 : in  std_logic;
      WEB2 : in  std_logic;
      OEB1 : in  std_logic;
      OEB2 : in  std_logic;
      CSB1 : in  std_logic;
      CSB2 : in  std_logic;
      I1   : in  std_logic_vector(7 downto 0);
      I2   : in  std_logic_vector(7 downto 0);
      O1   : out std_logic_vector(7 downto 0);
      O2   : out std_logic_vector(7 downto 0)
    );
  end component SRAM8x16;
  component SRAM8x32 is
    port (
      A1   : in  std_logic_vector(4 downto 0);
      A2   : in  std_logic_vector(4 downto 0);
      CE1  : in  std_logic;
      CE2  : in  std_logic;
      WEB1 : in  std_logic;
      WEB2 : in  std_logic;
      OEB1 : in  std_logic;
      OEB2 : in  std_logic;
      CSB1 : in  std_logic;
      CSB2 : in  std_logic;
      I1   : in  std_logic_vector(7 downto 0);
      I2   : in  std_logic_vector(7 downto 0);
      O1   : out std_logic_vector(7 downto 0);
      O2   : out std_logic_vector(7 downto 0)
    );
  end component SRAM8x32;
  component SRAM8x64 is
    port (
      A1   : in  std_logic_vector(5 downto 0);
      A2   : in  std_logic_vector(5 downto 0);
      CE1  : in  std_logic;
      CE2  : in  std_logic;
      WEB1 : in  std_logic;
      WEB2 : in  std_logic;
      OEB1 : in  std_logic;
      OEB2 : in  std_logic;
      CSB1 : in  std_logic;
      CSB2 : in  std_logic;
      I1   : in  std_logic_vector(7 downto 0);
      I2   : in  std_logic_vector(7 downto 0);
      O1   : out std_logic_vector(7 downto 0);
      O2   : out std_logic_vector(7 downto 0)
    );
  end component SRAM8x64;
  component SRAM8x128 is
    port (
      A1   : in  std_logic_vector(6 downto 0);
      A2   : in  std_logic_vector(6 downto 0);
      CE1  : in  std_logic;
      CE2  : in  std_logic;
      WEB1 : in  std_logic;
      WEB2 : in  std_logic;
      OEB1 : in  std_logic;
      OEB2 : in  std_logic;
      CSB1 : in  std_logic;
      CSB2 : in  std_logic;
      I1   : in  std_logic_vector(7 downto 0);
      I2   : in  std_logic_vector(7 downto 0);
      O1   : out std_logic_vector(7 downto 0);
      O2   : out std_logic_vector(7 downto 0)
    );
  end component SRAM8x128;
  component SRAM32x16 is
    port (
      A1   : in  std_logic_vector(3 downto 0);
      A2   : in  std_logic_vector(3 downto 0);
      CE1  : in  std_logic;
      CE2  : in  std_logic;
      WEB1 : in  std_logic;
      WEB2 : in  std_logic;
      OEB1 : in  std_logic;
      OEB2 : in  std_logic;
      CSB1 : in  std_logic;
      CSB2 : in  std_logic;
      I1   : in  std_logic_vector(31 downto 0);
      I2   : in  std_logic_vector(31 downto 0);
      O1   : out std_logic_vector(31 downto 0);
      O2   : out std_logic_vector(31 downto 0)
    );
  end component SRAM32x16;
  component SRAM32x32 is
    port (
      A1   : in  std_logic_vector(4 downto 0);
      A2   : in  std_logic_vector(4 downto 0);
      CE1  : in  std_logic;
      CE2  : in  std_logic;
      WEB1 : in  std_logic;
      WEB2 : in  std_logic;
      OEB1 : in  std_logic;
      OEB2 : in  std_logic;
      CSB1 : in  std_logic;
      CSB2 : in  std_logic;
      I1   : in  std_logic_vector(31 downto 0);
      I2   : in  std_logic_vector(31 downto 0);
      O1   : out std_logic_vector(31 downto 0);
      O2   : out std_logic_vector(31 downto 0)
    );
  end component SRAM32x32;
  component SRAM32x64 is
    port (
      A1   : in  std_logic_vector(5 downto 0);
      A2   : in  std_logic_vector(5 downto 0);
      CE1  : in  std_logic;
      CE2  : in  std_logic;
      WEB1 : in  std_logic;
      WEB2 : in  std_logic;
      OEB1 : in  std_logic;
      OEB2 : in  std_logic;
      CSB1 : in  std_logic;
      CSB2 : in  std_logic;
      I1   : in  std_logic_vector(31 downto 0);
      I2   : in  std_logic_vector(31 downto 0);
      O1   : out std_logic_vector(31 downto 0);
      O2   : out std_logic_vector(31 downto 0)
    );
  end component SRAM32x64;
  component SRAM32x128 is
    port (
      A1   : in  std_logic_vector(6 downto 0);
      A2   : in  std_logic_vector(6 downto 0);
      CE1  : in  std_logic;
      CE2  : in  std_logic;
      WEB1 : in  std_logic;
      WEB2 : in  std_logic;
      OEB1 : in  std_logic;
      OEB2 : in  std_logic;
      CSB1 : in  std_logic;
      CSB2 : in  std_logic;
      I1   : in  std_logic_vector(31 downto 0);
      I2   : in  std_logic_vector(31 downto 0);
      O1   : out std_logic_vector(31 downto 0);
      O2   : out std_logic_vector(31 downto 0)
    );
  end component SRAM32x128;
  component SRAM39x32 is
    port (
      A1   : in  std_logic_vector(4 downto 0);
      A2   : in  std_logic_vector(4 downto 0);
      CE1  : in  std_logic;
      CE2  : in  std_logic;
      WEB1 : in  std_logic;
      WEB2 : in  std_logic;
      OEB1 : in  std_logic;
      OEB2 : in  std_logic;
      CSB1 : in  std_logic;
      CSB2 : in  std_logic;
      I1   : in  std_logic_vector(38 downto 0);
      I2   : in  std_logic_vector(38 downto 0);
      O1   : out std_logic_vector(38 downto 0);
      O2   : out std_logic_vector(38 downto 0)
    );
  end component SRAM39x32;

  signal a_csb : std_logic;  -- port A chip select, active low
  signal b_csb : std_logic;  -- port B chip select, active low
  signal a_web : std_logic;  -- port A write enable, active low
  signal b_web : std_logic;  -- port B write enable, active low

begin

  a_csb <= not a_cs_i;
  b_csb <= not b_cs_i;
  a_web <= not (a_we_i and a_wbe_i(0));
  b_web <= not (b_we_i and b_wbe_i(0));

  -- Elaboration-time error: no macro of this size in the curated list.
  assert_size_a : assert (MAC_W = 8 and MAC_D = 16) or
                         (MAC_W = 8 and MAC_D = 32) or
                         (MAC_W = 8 and MAC_D = 64) or
                         (MAC_W = 8 and MAC_D = 128) or
                         (MAC_W = 32 and MAC_D = 16) or
                         (MAC_W = 32 and MAC_D = 32) or
                         (MAC_W = 32 and MAC_D = 64) or
                         (MAC_W = 32 and MAC_D = 128) or
                         (MAC_W = 39 and MAC_D = 32)
      report "sram_macro_dp_saed90: no macro of this size" severity failure;

  gen_8x16 : if MAC_W = 8 and MAC_D = 16 generate
    signal o1 : std_logic_vector(7 downto 0);
    signal o2 : std_logic_vector(7 downto 0);
  begin
    u_macro : SRAM8x16
      port map (
        A1   => std_logic_vector(a_addr_i),
        A2   => std_logic_vector(b_addr_i),
        CE1  => clk,
        CE2  => clk,
        WEB1 => a_web,
        WEB2 => b_web,
        OEB1 => '0',
        OEB2 => '0',
        CSB1 => a_csb,
        CSB2 => b_csb,
        I1   => std_logic_vector(a_wdata_i),
        I2   => std_logic_vector(b_wdata_i),
        O1   => o1,
        O2   => o2
      );
    a_rdata_o <= std_ulogic_vector(o1);
    b_rdata_o <= std_ulogic_vector(o2);
  end generate gen_8x16;

  gen_8x32 : if MAC_W = 8 and MAC_D = 32 generate
    signal o1 : std_logic_vector(7 downto 0);
    signal o2 : std_logic_vector(7 downto 0);
  begin
    u_macro : SRAM8x32
      port map (
        A1   => std_logic_vector(a_addr_i),
        A2   => std_logic_vector(b_addr_i),
        CE1  => clk,
        CE2  => clk,
        WEB1 => a_web,
        WEB2 => b_web,
        OEB1 => '0',
        OEB2 => '0',
        CSB1 => a_csb,
        CSB2 => b_csb,
        I1   => std_logic_vector(a_wdata_i),
        I2   => std_logic_vector(b_wdata_i),
        O1   => o1,
        O2   => o2
      );
    a_rdata_o <= std_ulogic_vector(o1);
    b_rdata_o <= std_ulogic_vector(o2);
  end generate gen_8x32;

  gen_8x64 : if MAC_W = 8 and MAC_D = 64 generate
    signal o1 : std_logic_vector(7 downto 0);
    signal o2 : std_logic_vector(7 downto 0);
  begin
    u_macro : SRAM8x64
      port map (
        A1   => std_logic_vector(a_addr_i),
        A2   => std_logic_vector(b_addr_i),
        CE1  => clk,
        CE2  => clk,
        WEB1 => a_web,
        WEB2 => b_web,
        OEB1 => '0',
        OEB2 => '0',
        CSB1 => a_csb,
        CSB2 => b_csb,
        I1   => std_logic_vector(a_wdata_i),
        I2   => std_logic_vector(b_wdata_i),
        O1   => o1,
        O2   => o2
      );
    a_rdata_o <= std_ulogic_vector(o1);
    b_rdata_o <= std_ulogic_vector(o2);
  end generate gen_8x64;

  gen_8x128 : if MAC_W = 8 and MAC_D = 128 generate
    signal o1 : std_logic_vector(7 downto 0);
    signal o2 : std_logic_vector(7 downto 0);
  begin
    u_macro : SRAM8x128
      port map (
        A1   => std_logic_vector(a_addr_i),
        A2   => std_logic_vector(b_addr_i),
        CE1  => clk,
        CE2  => clk,
        WEB1 => a_web,
        WEB2 => b_web,
        OEB1 => '0',
        OEB2 => '0',
        CSB1 => a_csb,
        CSB2 => b_csb,
        I1   => std_logic_vector(a_wdata_i),
        I2   => std_logic_vector(b_wdata_i),
        O1   => o1,
        O2   => o2
      );
    a_rdata_o <= std_ulogic_vector(o1);
    b_rdata_o <= std_ulogic_vector(o2);
  end generate gen_8x128;

  gen_32x16 : if MAC_W = 32 and MAC_D = 16 generate
    signal o1 : std_logic_vector(31 downto 0);
    signal o2 : std_logic_vector(31 downto 0);
  begin
    u_macro : SRAM32x16
      port map (
        A1   => std_logic_vector(a_addr_i),
        A2   => std_logic_vector(b_addr_i),
        CE1  => clk,
        CE2  => clk,
        WEB1 => a_web,
        WEB2 => b_web,
        OEB1 => '0',
        OEB2 => '0',
        CSB1 => a_csb,
        CSB2 => b_csb,
        I1   => std_logic_vector(a_wdata_i),
        I2   => std_logic_vector(b_wdata_i),
        O1   => o1,
        O2   => o2
      );
    a_rdata_o <= std_ulogic_vector(o1);
    b_rdata_o <= std_ulogic_vector(o2);
  end generate gen_32x16;

  gen_32x32 : if MAC_W = 32 and MAC_D = 32 generate
    signal o1 : std_logic_vector(31 downto 0);
    signal o2 : std_logic_vector(31 downto 0);
  begin
    u_macro : SRAM32x32
      port map (
        A1   => std_logic_vector(a_addr_i),
        A2   => std_logic_vector(b_addr_i),
        CE1  => clk,
        CE2  => clk,
        WEB1 => a_web,
        WEB2 => b_web,
        OEB1 => '0',
        OEB2 => '0',
        CSB1 => a_csb,
        CSB2 => b_csb,
        I1   => std_logic_vector(a_wdata_i),
        I2   => std_logic_vector(b_wdata_i),
        O1   => o1,
        O2   => o2
      );
    a_rdata_o <= std_ulogic_vector(o1);
    b_rdata_o <= std_ulogic_vector(o2);
  end generate gen_32x32;

  gen_32x64 : if MAC_W = 32 and MAC_D = 64 generate
    signal o1 : std_logic_vector(31 downto 0);
    signal o2 : std_logic_vector(31 downto 0);
  begin
    u_macro : SRAM32x64
      port map (
        A1   => std_logic_vector(a_addr_i),
        A2   => std_logic_vector(b_addr_i),
        CE1  => clk,
        CE2  => clk,
        WEB1 => a_web,
        WEB2 => b_web,
        OEB1 => '0',
        OEB2 => '0',
        CSB1 => a_csb,
        CSB2 => b_csb,
        I1   => std_logic_vector(a_wdata_i),
        I2   => std_logic_vector(b_wdata_i),
        O1   => o1,
        O2   => o2
      );
    a_rdata_o <= std_ulogic_vector(o1);
    b_rdata_o <= std_ulogic_vector(o2);
  end generate gen_32x64;

  gen_32x128 : if MAC_W = 32 and MAC_D = 128 generate
    signal o1 : std_logic_vector(31 downto 0);
    signal o2 : std_logic_vector(31 downto 0);
  begin
    u_macro : SRAM32x128
      port map (
        A1   => std_logic_vector(a_addr_i),
        A2   => std_logic_vector(b_addr_i),
        CE1  => clk,
        CE2  => clk,
        WEB1 => a_web,
        WEB2 => b_web,
        OEB1 => '0',
        OEB2 => '0',
        CSB1 => a_csb,
        CSB2 => b_csb,
        I1   => std_logic_vector(a_wdata_i),
        I2   => std_logic_vector(b_wdata_i),
        O1   => o1,
        O2   => o2
      );
    a_rdata_o <= std_ulogic_vector(o1);
    b_rdata_o <= std_ulogic_vector(o2);
  end generate gen_32x128;

  gen_39x32 : if MAC_W = 39 and MAC_D = 32 generate
    signal o1 : std_logic_vector(38 downto 0);
    signal o2 : std_logic_vector(38 downto 0);
  begin
    u_macro : SRAM39x32
      port map (
        A1   => std_logic_vector(a_addr_i),
        A2   => std_logic_vector(b_addr_i),
        CE1  => clk,
        CE2  => clk,
        WEB1 => a_web,
        WEB2 => b_web,
        OEB1 => '0',
        OEB2 => '0',
        CSB1 => a_csb,
        CSB2 => b_csb,
        I1   => std_logic_vector(a_wdata_i),
        I2   => std_logic_vector(b_wdata_i),
        O1   => o1,
        O2   => o2
      );
    a_rdata_o <= std_ulogic_vector(o1);
    b_rdata_o <= std_ulogic_vector(o2);
  end generate gen_39x32;

end architecture rtl;
