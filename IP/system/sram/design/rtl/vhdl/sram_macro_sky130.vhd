-- sram_macro_sky130.vhd — SkyWater SKY130 OpenRAM SRAM wrapper (TECH_SKY130).
--
-- VHDL-2008 twin of sram_macro_sky130.sv.
--
-- A W x D single-port memory built from the OpenRAM 1rw1r macros in
-- libs.ref/sky130_sram_macros:
--   32 x 256   sky130_sram_1kbyte_1rw1r_32x256_8   (wmask0, one bit per byte)
--   32 x 512   sky130_sram_2kbyte_1rw1r_32x512_8   (wmask0, one bit per byte)
--    8 x 1024  sky130_sram_1kbyte_1rw1r_8x1024_8   (wmask0, one bit)
-- One primitive size PRIM_W x PRIM_D is picked by sram_pkg prim_width /
-- prim_depth (the sizes in the g_<w>x<d> branches below), and generate loops
-- tile it:
--   rows     ROWS = D / PRIM_D primitives stacked in depth. The address bits
--            above the primitive address select the row (its chip select),
--            and a row register remembers the row read, for the read mux.
--            When D < PRIM_D there is one row and the primitive's top address
--            bits are tied to 0.
--   columns  COLS = ceil(W / PRIM_W) primitives side by side. The last column
--            is zero-padded when PRIM_W does not divide W.
-- Example: W = 32, D = 2048 -> 32x512 primitives, 4 rows x 1 column, the
-- row selected by addr_i[10:9].
--
-- Pin mapping (every primitive; port 0 = read/write, port 1 unused):
--   clk0 = clk, csb0 = not row select, web0 = not we_i (both active low),
--   wmask0 = the lane enable of each byte (native byte mask), addr0, din0,
--   dout0. clk1 = clk, csb1 = 1 (deselected), addr1 = 0, dout1 open.
--   vccd1/vssd1 exist only with USE_POWER_PINS (not used in RTL).
--   The model latches inputs on the rising edge and drives dout0 a few ns
--   after the falling edge; it goes X shortly after the next rising edge, so
--   read data is valid exactly in the cycle after the read. The clock period
--   must exceed ~8 ns in simulation. VERBOSE = 0 silences the model.
--   ls_i / ds_i / sd_i are unused: no sleep pins (UPF).
-- The primitives are Verilog models declared as components (vendor
-- primitives) with std_logic ports.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sram_pkg.all;

entity sram_macro_sky130 is
  generic (
    W      : positive := 32;   -- word width
    D      : positive := 1024; -- words (power of two)
    NLANES : positive := 4     -- write lanes of W / NLANES bits
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

  constant PRIM_W_C  : positive := prim_width(TECH_SKY130_C, W, NLANES);
  constant PRIM_D_C  : positive := prim_depth(TECH_SKY130_C, PRIM_W_C, D);
  constant PRIM_AW_C : natural  := clog2(PRIM_D_C);
  constant ROWS_C    : positive := tile_rows(D, PRIM_D_C);
  constant COLS_C    : positive := (W + PRIM_W_C - 1) / PRIM_W_C;
  constant PAD_W_C   : positive := COLS_C * PRIM_W_C;
  constant ROW_W_C   : positive := maximum(1, clog2(ROWS_C));

  type row_data_t is array (0 to ROWS_C - 1) of std_ulogic_vector(PAD_W_C - 1 downto 0);

  signal row       : unsigned(ROW_W_C - 1 downto 0); -- row addressed
  signal rd_row_q  : unsigned(ROW_W_C - 1 downto 0) := (others => '0'); -- row read
  signal paddr     : std_ulogic_vector(PRIM_AW_C - 1 downto 0); -- primitive address
  signal wdata_pad : std_ulogic_vector(PAD_W_C - 1 downto 0); -- padded write data
  signal row_rdata : row_data_t; -- read data of each row
  signal web       : std_ulogic; -- write enable, active low

begin

  assert_d_a : assert D >= 2 and 2 ** clog2(D) = D
      report "sram_macro_sky130: D must be a power of two >= 2" severity failure;
  assert_lanes_a : assert W mod NLANES = 0
      report "sram_macro_sky130: NLANES must divide W" severity failure;
  assert_col_a : assert NLANES = 1 or (W / NLANES) mod 8 = 0
      report "sram_macro_sky130: a byte crosses a write lane" severity failure;
  -- Elaboration-time error: no primitive of this size in the curated list.
  assert_size_a : assert (PRIM_W_C = 32 and PRIM_D_C = 256) or
                         (PRIM_W_C = 32 and PRIM_D_C = 512) or (PRIM_W_C = 8 and PRIM_D_C = 1024)
      report "sram_macro_sky130: no primitive of this size" severity failure;

  -- Low address bits go to every primitive (zero-extended when D < PRIM_D).
  paddr     <= std_ulogic_vector(resize(unsigned(addr_i), PRIM_AW_C));
  wdata_pad <= std_ulogic_vector(resize(unsigned(wdata_i), PAD_W_C));
  web       <= not we_i;

  -- Row select from the address bits above the primitive address; the row
  -- read is remembered for the read multiplexer.
  gen_rows : if ROWS_C > 1 generate
    row <= resize(shift_right(unsigned(addr_i), PRIM_AW_C), ROW_W_C);

    p_rd_row : process (clk) is
    begin
      if rising_edge(clk) then
        if cs_i = '1' and we_i = '0' then
          rd_row_q <= row;
        end if;
      end if;
    end process p_rd_row;
  else generate
    row      <= (others => '0');
    rd_row_q <= (others => '0');
  end generate gen_rows;

  rdata_o <= row_rdata(to_integer(rd_row_q))(W - 1 downto 0);

  gen_row : for r in 0 to ROWS_C - 1 generate
    signal csb : std_logic; -- this row's chip select, active low
  begin
    csb <= '0' when cs_i = '1' and row = to_unsigned(r, ROW_W_C) else '1';

    gen_col : for c in 0 to COLS_C - 1 generate
      constant LO_C : natural := c * PRIM_W_C; -- lowest bit of this column
      signal wmask : std_ulogic_vector(PRIM_W_C / 8 - 1 downto 0); -- byte write mask
    begin
      gen_byte : for k in 0 to PRIM_W_C / 8 - 1 generate
        wmask(k) <= lane_we_i(lane_of(LO_C + 8 * k, W, NLANES));
      end generate gen_byte;

      gen_32x256 : if PRIM_W_C = 32 and PRIM_D_C = 256 generate
        signal o : std_logic_vector(31 downto 0);
      begin
        u_prim : sky130_sram_1kbyte_1rw1r_32x256_8
          generic map (
            VERBOSE => 0
          )
          port map (
            clk0   => clk,
            csb0   => csb,
            web0   => web,
            wmask0 => std_logic_vector(wmask),
            addr0  => std_logic_vector(paddr),
            din0   => std_logic_vector(wdata_pad(LO_C + 31 downto LO_C)),
            dout0  => o,
            clk1   => clk,
            csb1   => '1',
            addr1  => (others => '0'),
            dout1  => open
          );
        row_rdata(r)(LO_C + 31 downto LO_C) <= std_ulogic_vector(o);
      end generate gen_32x256;

      gen_32x512 : if PRIM_W_C = 32 and PRIM_D_C = 512 generate
        signal o : std_logic_vector(31 downto 0);
      begin
        u_prim : sky130_sram_2kbyte_1rw1r_32x512_8
          generic map (
            VERBOSE => 0
          )
          port map (
            clk0   => clk,
            csb0   => csb,
            web0   => web,
            wmask0 => std_logic_vector(wmask),
            addr0  => std_logic_vector(paddr),
            din0   => std_logic_vector(wdata_pad(LO_C + 31 downto LO_C)),
            dout0  => o,
            clk1   => clk,
            csb1   => '1',
            addr1  => (others => '0'),
            dout1  => open
          );
        row_rdata(r)(LO_C + 31 downto LO_C) <= std_ulogic_vector(o);
      end generate gen_32x512;

      gen_8x1024 : if PRIM_W_C = 8 and PRIM_D_C = 1024 generate
        signal o : std_logic_vector(7 downto 0);
      begin
        u_prim : sky130_sram_1kbyte_1rw1r_8x1024_8
          generic map (
            VERBOSE => 0
          )
          port map (
            clk0   => clk,
            csb0   => csb,
            web0   => web,
            wmask0 => std_logic_vector(wmask),
            addr0  => std_logic_vector(paddr),
            din0   => std_logic_vector(wdata_pad(LO_C + 7 downto LO_C)),
            dout0  => o,
            clk1   => clk,
            csb1   => '1',
            addr1  => (others => '0'),
            dout1  => open
          );
        row_rdata(r)(LO_C + 7 downto LO_C) <= std_ulogic_vector(o);
      end generate gen_8x1024;
    end generate gen_col;
  end generate gen_row;

end architecture rtl;
