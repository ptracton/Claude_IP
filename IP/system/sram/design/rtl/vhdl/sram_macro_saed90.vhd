-- sram_macro_saed90.vhd — SAED90 SRAM wrapper (TECH_SAED90).
--
-- VHDL-2008 twin of sram_macro_saed90.sv.
--
-- A W x D single-port memory built from SAED90 (SAED_EDK90nm Memories)
-- SRAM<w>x<d>_1rw primitives.
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
-- Example: W = 16, D = 2048 -> 1024x8 primitives, 2 rows x 2 columns, the
-- row selected by addr_i[10].
--
-- Pin mapping (every primitive):
--   CE = clk, CSB = not row select (active low), WEB = not write (active low),
--   OEB = 0. Read data is registered on CE: valid in the cycle after a read.
--   No byte mask: each column lies inside one write lane (checked below), and
--   that lane's enable gates the column's WEB.
--   ls_i / ds_i / sd_i are unused: no sleep pins on this family (UPF).
-- The primitives are Verilog models declared as components (vendor
-- primitives) with std_logic ports.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sram_pkg.all;

entity sram_macro_saed90 is
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

  constant PRIM_W_C  : positive := prim_width(TECH_SAED90_C, W, NLANES);
  constant PRIM_D_C  : positive := prim_depth(TECH_SAED90_C, PRIM_W_C, D);
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
  signal col_web   : std_ulogic_vector(COLS_C - 1 downto 0); -- column WEB
  signal row_rdata : row_data_t; -- read data of each row

begin

  assert_d_a : assert D >= 2 and 2 ** clog2(D) = D
      report "sram_macro_saed90: D must be a power of two >= 2" severity failure;
  assert_lanes_a : assert W mod NLANES = 0
      report "sram_macro_saed90: NLANES must divide W" severity failure;
  assert_col_a : assert NLANES = 1 or (W / NLANES) mod PRIM_W_C = 0
      report "sram_macro_saed90: a column crosses a write lane" severity failure;
  -- Elaboration-time error: no primitive of this size in the curated list.
  assert_size_a : assert (PRIM_W_C = 8 and PRIM_D_C = 64) or (PRIM_W_C = 8 and PRIM_D_C = 128) or
                         (PRIM_W_C = 8 and PRIM_D_C = 256) or
                         (PRIM_W_C = 8 and PRIM_D_C = 512) or
                         (PRIM_W_C = 8 and PRIM_D_C = 1024) or
                         (PRIM_W_C = 32 and PRIM_D_C = 64) or
                         (PRIM_W_C = 32 and PRIM_D_C = 256) or (PRIM_W_C = 32 and PRIM_D_C = 512)
      report "sram_macro_saed90: no primitive of this size" severity failure;

  -- Low address bits go to every primitive (zero-extended when D < PRIM_D).
  paddr     <= std_ulogic_vector(resize(unsigned(addr_i), PRIM_AW_C));
  wdata_pad <= std_ulogic_vector(resize(unsigned(wdata_i), PAD_W_C));

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

  -- Each column takes the write enable of the lane it lies in.
  gen_col_we : for c in 0 to COLS_C - 1 generate
    col_web(c) <= not (we_i and lane_we_i(lane_of(c * PRIM_W_C, W, NLANES)));
  end generate gen_col_we;

  gen_row : for r in 0 to ROWS_C - 1 generate
    signal csb : std_logic; -- this row's chip select, active low
  begin
    csb <= '0' when cs_i = '1' and row = to_unsigned(r, ROW_W_C) else '1';

    gen_col : for c in 0 to COLS_C - 1 generate
      constant LO_C : natural := c * PRIM_W_C; -- lowest bit of this column
    begin
      gen_8x64 : if PRIM_W_C = 8 and PRIM_D_C = 64 generate
        signal o : std_logic_vector(7 downto 0);
      begin
        u_prim : SRAM8x64_1rw
          port map (
            A   => std_logic_vector(paddr),
            CE  => clk,
            WEB => col_web(c),
            OEB => '0',
            CSB => csb,
            I   => std_logic_vector(wdata_pad(LO_C + 7 downto LO_C)),
            O   => o
          );
        row_rdata(r)(LO_C + 7 downto LO_C) <= std_ulogic_vector(o);
      end generate gen_8x64;

      gen_8x128 : if PRIM_W_C = 8 and PRIM_D_C = 128 generate
        signal o : std_logic_vector(7 downto 0);
      begin
        u_prim : SRAM8x128_1rw
          port map (
            A   => std_logic_vector(paddr),
            CE  => clk,
            WEB => col_web(c),
            OEB => '0',
            CSB => csb,
            I   => std_logic_vector(wdata_pad(LO_C + 7 downto LO_C)),
            O   => o
          );
        row_rdata(r)(LO_C + 7 downto LO_C) <= std_ulogic_vector(o);
      end generate gen_8x128;

      gen_8x256 : if PRIM_W_C = 8 and PRIM_D_C = 256 generate
        signal o : std_logic_vector(7 downto 0);
      begin
        u_prim : SRAM8x256_1rw
          port map (
            A   => std_logic_vector(paddr),
            CE  => clk,
            WEB => col_web(c),
            OEB => '0',
            CSB => csb,
            I   => std_logic_vector(wdata_pad(LO_C + 7 downto LO_C)),
            O   => o
          );
        row_rdata(r)(LO_C + 7 downto LO_C) <= std_ulogic_vector(o);
      end generate gen_8x256;

      gen_8x512 : if PRIM_W_C = 8 and PRIM_D_C = 512 generate
        signal o : std_logic_vector(7 downto 0);
      begin
        u_prim : SRAM8x512_1rw
          port map (
            A   => std_logic_vector(paddr),
            CE  => clk,
            WEB => col_web(c),
            OEB => '0',
            CSB => csb,
            I   => std_logic_vector(wdata_pad(LO_C + 7 downto LO_C)),
            O   => o
          );
        row_rdata(r)(LO_C + 7 downto LO_C) <= std_ulogic_vector(o);
      end generate gen_8x512;

      gen_8x1024 : if PRIM_W_C = 8 and PRIM_D_C = 1024 generate
        signal o : std_logic_vector(7 downto 0);
      begin
        u_prim : SRAM8x1024_1rw
          port map (
            A   => std_logic_vector(paddr),
            CE  => clk,
            WEB => col_web(c),
            OEB => '0',
            CSB => csb,
            I   => std_logic_vector(wdata_pad(LO_C + 7 downto LO_C)),
            O   => o
          );
        row_rdata(r)(LO_C + 7 downto LO_C) <= std_ulogic_vector(o);
      end generate gen_8x1024;

      gen_32x64 : if PRIM_W_C = 32 and PRIM_D_C = 64 generate
        signal o : std_logic_vector(31 downto 0);
      begin
        u_prim : SRAM32x64_1rw
          port map (
            A   => std_logic_vector(paddr),
            CE  => clk,
            WEB => col_web(c),
            OEB => '0',
            CSB => csb,
            I   => std_logic_vector(wdata_pad(LO_C + 31 downto LO_C)),
            O   => o
          );
        row_rdata(r)(LO_C + 31 downto LO_C) <= std_ulogic_vector(o);
      end generate gen_32x64;

      gen_32x256 : if PRIM_W_C = 32 and PRIM_D_C = 256 generate
        signal o : std_logic_vector(31 downto 0);
      begin
        u_prim : SRAM32x256_1rw
          port map (
            A   => std_logic_vector(paddr),
            CE  => clk,
            WEB => col_web(c),
            OEB => '0',
            CSB => csb,
            I   => std_logic_vector(wdata_pad(LO_C + 31 downto LO_C)),
            O   => o
          );
        row_rdata(r)(LO_C + 31 downto LO_C) <= std_ulogic_vector(o);
      end generate gen_32x256;

      gen_32x512 : if PRIM_W_C = 32 and PRIM_D_C = 512 generate
        signal o : std_logic_vector(31 downto 0);
      begin
        u_prim : SRAM32x512_1rw
          port map (
            A   => std_logic_vector(paddr),
            CE  => clk,
            WEB => col_web(c),
            OEB => '0',
            CSB => csb,
            I   => std_logic_vector(wdata_pad(LO_C + 31 downto LO_C)),
            O   => o
          );
        row_rdata(r)(LO_C + 31 downto LO_C) <= std_ulogic_vector(o);
      end generate gen_32x512;
    end generate gen_col;
  end generate gen_row;

end architecture rtl;
