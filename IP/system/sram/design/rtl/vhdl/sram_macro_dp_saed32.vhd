-- sram_macro_dp_saed32.vhd — SAED32 low-power two-port SRAM wrapper (DUAL_PORT).
--
-- VHDL-2008 twin of sram_macro_dp_saed32.sv.
--
-- A W x D two-port memory built from SAED32 low-power (lib/sram_lp)
-- SRAMLP2RW<d>x<w> primitives: two independent read/write ports, each on
-- its own clock.
-- One primitive size PRIM_W x PRIM_D is picked by sram_pkg prim_width_dp /
-- prim_depth_dp (the sizes in the g_<w>x<d> branches below), and generate loops
-- tile it:
--   rows     ROWS = D / PRIM_D primitives stacked in depth. The address bits
--            above the primitive address select the row (its chip select),
--            and a row register remembers the row read, for the read mux.
--            When D < PRIM_D there is one row and the primitive's top address
--            bits are tied to 0.
--   columns  COLS = ceil(W / PRIM_W) primitives side by side. The last column
--            is zero-padded when PRIM_W does not divide W.
-- Example: W = 32, D = 1024 with 4 byte lanes -> 128x8 primitives, 8 rows
-- x 4 columns.
--
-- Pin mapping (every primitive):
--   CE1 = a_clk, CE2 = b_clk; CSB1/CSB2 = not row select of port A/B (active low);
--   WEB1/WEB2 = not write; OEB1 = OEB2 = 0. LS1 = LS2 = ls_i, DS1 = DS2 =
--   ds_i, SD = sd_i on every primitive (honoured only while both ports are
--   deselected). VDD/VDDL/VSS are not connected in RTL. Each port has its own
--   row decode and row register. Read data is registered: valid in the cycle
--   after a read.
--   No byte mask: each column lies inside one write lane (checked below), and
--   that lane's enable gates the column's WEB. With COMMON_CLK the core keeps
--   the ports off the same word in one cycle when either writes; with separate
--   clocks, such a collision is undefined.
-- The primitives are Verilog models declared as components (vendor
-- primitives) with std_logic ports.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sram_pkg.all;

entity sram_macro_dp_saed32 is
  generic (
    W      : positive := 32;   -- word width
    D      : positive := 1024; -- words (power of two)
    NLANES : positive := 4     -- write lanes of W / NLANES bits
  );
  port (
    a_clk       : in  std_ulogic;                               -- port A clock
    a_cs_i      : in  std_ulogic;                               -- port A chip select
    a_we_i      : in  std_ulogic;                               -- port A 1 = write
    a_addr_i    : in  std_ulogic_vector(clog2(D) - 1 downto 0); -- port A word address
    a_wdata_i   : in  std_ulogic_vector(W - 1 downto 0);        -- port A write data
    a_lane_we_i : in  std_ulogic_vector(NLANES - 1 downto 0);   -- port A lanes to write
    a_rdata_o   : out std_ulogic_vector(W - 1 downto 0);        -- port A read data
    b_clk       : in  std_ulogic;                               -- port B clock
    b_cs_i      : in  std_ulogic;                               -- port B chip select
    b_we_i      : in  std_ulogic;                               -- port B 1 = write
    b_addr_i    : in  std_ulogic_vector(clog2(D) - 1 downto 0); -- port B word address
    b_wdata_i   : in  std_ulogic_vector(W - 1 downto 0);        -- port B write data
    b_lane_we_i : in  std_ulogic_vector(NLANES - 1 downto 0);   -- port B lanes to write
    b_rdata_o   : out std_ulogic_vector(W - 1 downto 0);        -- port B read data
    ls_i        : in  std_ulogic;                               -- light sleep
    ds_i        : in  std_ulogic;                               -- deep sleep
    sd_i        : in  std_ulogic                                -- shutdown
  );
end entity sram_macro_dp_saed32;

architecture rtl of sram_macro_dp_saed32 is

  component SRAMLP2RW16x8 is
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
      O2   : out std_logic_vector(7 downto 0);
      SD   : in  std_logic;
      LS1  : in  std_logic;
      LS2  : in  std_logic;
      DS1  : in  std_logic;
      DS2  : in  std_logic
    );
  end component SRAMLP2RW16x8;
  component SRAMLP2RW32x8 is
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
      O2   : out std_logic_vector(7 downto 0);
      SD   : in  std_logic;
      LS1  : in  std_logic;
      LS2  : in  std_logic;
      DS1  : in  std_logic;
      DS2  : in  std_logic
    );
  end component SRAMLP2RW32x8;
  component SRAMLP2RW64x8 is
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
      O2   : out std_logic_vector(7 downto 0);
      SD   : in  std_logic;
      LS1  : in  std_logic;
      LS2  : in  std_logic;
      DS1  : in  std_logic;
      DS2  : in  std_logic
    );
  end component SRAMLP2RW64x8;
  component SRAMLP2RW128x8 is
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
      O2   : out std_logic_vector(7 downto 0);
      SD   : in  std_logic;
      LS1  : in  std_logic;
      LS2  : in  std_logic;
      DS1  : in  std_logic;
      DS2  : in  std_logic
    );
  end component SRAMLP2RW128x8;
  component SRAMLP2RW16x32 is
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
      O2   : out std_logic_vector(31 downto 0);
      SD   : in  std_logic;
      LS1  : in  std_logic;
      LS2  : in  std_logic;
      DS1  : in  std_logic;
      DS2  : in  std_logic
    );
  end component SRAMLP2RW16x32;
  component SRAMLP2RW32x32 is
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
      O2   : out std_logic_vector(31 downto 0);
      SD   : in  std_logic;
      LS1  : in  std_logic;
      LS2  : in  std_logic;
      DS1  : in  std_logic;
      DS2  : in  std_logic
    );
  end component SRAMLP2RW32x32;
  component SRAMLP2RW64x32 is
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
      O2   : out std_logic_vector(31 downto 0);
      SD   : in  std_logic;
      LS1  : in  std_logic;
      LS2  : in  std_logic;
      DS1  : in  std_logic;
      DS2  : in  std_logic
    );
  end component SRAMLP2RW64x32;
  component SRAMLP2RW128x32 is
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
      O2   : out std_logic_vector(31 downto 0);
      SD   : in  std_logic;
      LS1  : in  std_logic;
      LS2  : in  std_logic;
      DS1  : in  std_logic;
      DS2  : in  std_logic
    );
  end component SRAMLP2RW128x32;

  constant PRIM_W_C  : positive := prim_width_dp(TECH_SAED32_C, W, NLANES);
  constant PRIM_D_C  : positive := prim_depth_dp(TECH_SAED32_C, PRIM_W_C, D);
  constant PRIM_AW_C : natural  := clog2(PRIM_D_C);
  constant ROWS_C    : positive := tile_rows(D, PRIM_D_C);
  constant COLS_C    : positive := (W + PRIM_W_C - 1) / PRIM_W_C;
  constant PAD_W_C   : positive := COLS_C * PRIM_W_C;
  constant ROW_W_C   : positive := maximum(1, clog2(ROWS_C));

  type row_data_t is array (0 to ROWS_C - 1) of std_ulogic_vector(PAD_W_C - 1 downto 0);

  signal a_row       : unsigned(ROW_W_C - 1 downto 0); -- port A: row addressed
  signal a_rd_row_q  : unsigned(ROW_W_C - 1 downto 0) := (others => '0'); -- port A: row read
  signal a_paddr     : std_ulogic_vector(PRIM_AW_C - 1 downto 0); -- port A: primitive address
  signal a_wdata_pad : std_ulogic_vector(PAD_W_C - 1 downto 0); -- port A: padded write data
  signal a_col_web   : std_ulogic_vector(COLS_C - 1 downto 0); -- port A: column WEB
  signal a_row_rdata : row_data_t; -- port A: read data of each row
  signal b_row       : unsigned(ROW_W_C - 1 downto 0); -- port B: row addressed
  signal b_rd_row_q  : unsigned(ROW_W_C - 1 downto 0) := (others => '0'); -- port B: row read
  signal b_paddr     : std_ulogic_vector(PRIM_AW_C - 1 downto 0); -- port B: primitive address
  signal b_wdata_pad : std_ulogic_vector(PAD_W_C - 1 downto 0); -- port B: padded write data
  signal b_col_web   : std_ulogic_vector(COLS_C - 1 downto 0); -- port B: column WEB
  signal b_row_rdata : row_data_t; -- port B: read data of each row

begin

  assert_d_a : assert D >= 2 and 2 ** clog2(D) = D
      report "sram_macro_dp_saed32: D must be a power of two >= 2" severity failure;
  assert_lanes_a : assert W mod NLANES = 0
      report "sram_macro_dp_saed32: NLANES must divide W" severity failure;
  assert_col_a : assert NLANES = 1 or (W / NLANES) mod PRIM_W_C = 0
      report "sram_macro_dp_saed32: a column crosses a write lane" severity failure;
  -- Elaboration-time error: no primitive of this size in the curated list.
  assert_size_a : assert (PRIM_W_C = 8 and PRIM_D_C = 16) or (PRIM_W_C = 8 and PRIM_D_C = 32) or
                         (PRIM_W_C = 8 and PRIM_D_C = 64) or (PRIM_W_C = 8 and PRIM_D_C = 128) or
                         (PRIM_W_C = 32 and PRIM_D_C = 16) or
                         (PRIM_W_C = 32 and PRIM_D_C = 32) or
                         (PRIM_W_C = 32 and PRIM_D_C = 64) or (PRIM_W_C = 32 and PRIM_D_C = 128)
      report "sram_macro_dp_saed32: no primitive of this size" severity failure;

  -- Low address bits go to every primitive (zero-extended when D < PRIM_D).
  a_paddr     <= std_ulogic_vector(resize(unsigned(a_addr_i), PRIM_AW_C));
  b_paddr     <= std_ulogic_vector(resize(unsigned(b_addr_i), PRIM_AW_C));
  a_wdata_pad <= std_ulogic_vector(resize(unsigned(a_wdata_i), PAD_W_C));
  b_wdata_pad <= std_ulogic_vector(resize(unsigned(b_wdata_i), PAD_W_C));

  -- Row select from the address bits above the primitive address; each port
  -- remembers the row it read, for its read multiplexer.
  gen_rows : if ROWS_C > 1 generate
    a_row <= resize(shift_right(unsigned(a_addr_i), PRIM_AW_C), ROW_W_C);
    b_row <= resize(shift_right(unsigned(b_addr_i), PRIM_AW_C), ROW_W_C);

    p_a_rd_row : process (a_clk) is
    begin
      if rising_edge(a_clk) then
        if a_cs_i = '1' and a_we_i = '0' then
          a_rd_row_q <= a_row;
        end if;
      end if;
    end process p_a_rd_row;

    p_b_rd_row : process (b_clk) is
    begin
      if rising_edge(b_clk) then
        if b_cs_i = '1' and b_we_i = '0' then
          b_rd_row_q <= b_row;
        end if;
      end if;
    end process p_b_rd_row;
  else generate
    a_row      <= (others => '0');
    a_rd_row_q <= (others => '0');
    b_row      <= (others => '0');
    b_rd_row_q <= (others => '0');
  end generate gen_rows;

  a_rdata_o <= a_row_rdata(to_integer(a_rd_row_q))(W - 1 downto 0);
  b_rdata_o <= b_row_rdata(to_integer(b_rd_row_q))(W - 1 downto 0);

  -- Each column takes the write enable of the lane it lies in.
  gen_col_we : for c in 0 to COLS_C - 1 generate
    a_col_web(c) <= not (a_we_i and a_lane_we_i(lane_of(c * PRIM_W_C, W, NLANES)));
    b_col_web(c) <= not (b_we_i and b_lane_we_i(lane_of(c * PRIM_W_C, W, NLANES)));
  end generate gen_col_we;

  gen_row : for r in 0 to ROWS_C - 1 generate
    signal a_csb : std_logic; -- this row's port A chip select, active low
    signal b_csb : std_logic; -- this row's port B chip select, active low
  begin
    a_csb <= '0' when a_cs_i = '1' and a_row = to_unsigned(r, ROW_W_C) else '1';
    b_csb <= '0' when b_cs_i = '1' and b_row = to_unsigned(r, ROW_W_C) else '1';

    gen_col : for c in 0 to COLS_C - 1 generate
      constant LO_C : natural := c * PRIM_W_C; -- lowest bit of this column
    begin
      gen_8x16 : if PRIM_W_C = 8 and PRIM_D_C = 16 generate
        signal o1 : std_logic_vector(7 downto 0);
        signal o2 : std_logic_vector(7 downto 0);
      begin
        u_prim : SRAMLP2RW16x8
          port map (
            A1   => std_logic_vector(a_paddr),
            A2   => std_logic_vector(b_paddr),
            CE1  => a_clk,
            CE2  => b_clk,
            WEB1 => a_col_web(c),
            WEB2 => b_col_web(c),
            OEB1 => '0',
            OEB2 => '0',
            CSB1 => a_csb,
            CSB2 => b_csb,
            I1   => std_logic_vector(a_wdata_pad(LO_C + 7 downto LO_C)),
            I2   => std_logic_vector(b_wdata_pad(LO_C + 7 downto LO_C)),
            O1   => o1,
            O2   => o2,
            SD   => sd_i,
            LS1  => ls_i,
            LS2  => ls_i,
            DS1  => ds_i,
            DS2  => ds_i
          );
        a_row_rdata(r)(LO_C + 7 downto LO_C) <= std_ulogic_vector(o1);
        b_row_rdata(r)(LO_C + 7 downto LO_C) <= std_ulogic_vector(o2);
      end generate gen_8x16;

      gen_8x32 : if PRIM_W_C = 8 and PRIM_D_C = 32 generate
        signal o1 : std_logic_vector(7 downto 0);
        signal o2 : std_logic_vector(7 downto 0);
      begin
        u_prim : SRAMLP2RW32x8
          port map (
            A1   => std_logic_vector(a_paddr),
            A2   => std_logic_vector(b_paddr),
            CE1  => a_clk,
            CE2  => b_clk,
            WEB1 => a_col_web(c),
            WEB2 => b_col_web(c),
            OEB1 => '0',
            OEB2 => '0',
            CSB1 => a_csb,
            CSB2 => b_csb,
            I1   => std_logic_vector(a_wdata_pad(LO_C + 7 downto LO_C)),
            I2   => std_logic_vector(b_wdata_pad(LO_C + 7 downto LO_C)),
            O1   => o1,
            O2   => o2,
            SD   => sd_i,
            LS1  => ls_i,
            LS2  => ls_i,
            DS1  => ds_i,
            DS2  => ds_i
          );
        a_row_rdata(r)(LO_C + 7 downto LO_C) <= std_ulogic_vector(o1);
        b_row_rdata(r)(LO_C + 7 downto LO_C) <= std_ulogic_vector(o2);
      end generate gen_8x32;

      gen_8x64 : if PRIM_W_C = 8 and PRIM_D_C = 64 generate
        signal o1 : std_logic_vector(7 downto 0);
        signal o2 : std_logic_vector(7 downto 0);
      begin
        u_prim : SRAMLP2RW64x8
          port map (
            A1   => std_logic_vector(a_paddr),
            A2   => std_logic_vector(b_paddr),
            CE1  => a_clk,
            CE2  => b_clk,
            WEB1 => a_col_web(c),
            WEB2 => b_col_web(c),
            OEB1 => '0',
            OEB2 => '0',
            CSB1 => a_csb,
            CSB2 => b_csb,
            I1   => std_logic_vector(a_wdata_pad(LO_C + 7 downto LO_C)),
            I2   => std_logic_vector(b_wdata_pad(LO_C + 7 downto LO_C)),
            O1   => o1,
            O2   => o2,
            SD   => sd_i,
            LS1  => ls_i,
            LS2  => ls_i,
            DS1  => ds_i,
            DS2  => ds_i
          );
        a_row_rdata(r)(LO_C + 7 downto LO_C) <= std_ulogic_vector(o1);
        b_row_rdata(r)(LO_C + 7 downto LO_C) <= std_ulogic_vector(o2);
      end generate gen_8x64;

      gen_8x128 : if PRIM_W_C = 8 and PRIM_D_C = 128 generate
        signal o1 : std_logic_vector(7 downto 0);
        signal o2 : std_logic_vector(7 downto 0);
      begin
        u_prim : SRAMLP2RW128x8
          port map (
            A1   => std_logic_vector(a_paddr),
            A2   => std_logic_vector(b_paddr),
            CE1  => a_clk,
            CE2  => b_clk,
            WEB1 => a_col_web(c),
            WEB2 => b_col_web(c),
            OEB1 => '0',
            OEB2 => '0',
            CSB1 => a_csb,
            CSB2 => b_csb,
            I1   => std_logic_vector(a_wdata_pad(LO_C + 7 downto LO_C)),
            I2   => std_logic_vector(b_wdata_pad(LO_C + 7 downto LO_C)),
            O1   => o1,
            O2   => o2,
            SD   => sd_i,
            LS1  => ls_i,
            LS2  => ls_i,
            DS1  => ds_i,
            DS2  => ds_i
          );
        a_row_rdata(r)(LO_C + 7 downto LO_C) <= std_ulogic_vector(o1);
        b_row_rdata(r)(LO_C + 7 downto LO_C) <= std_ulogic_vector(o2);
      end generate gen_8x128;

      gen_32x16 : if PRIM_W_C = 32 and PRIM_D_C = 16 generate
        signal o1 : std_logic_vector(31 downto 0);
        signal o2 : std_logic_vector(31 downto 0);
      begin
        u_prim : SRAMLP2RW16x32
          port map (
            A1   => std_logic_vector(a_paddr),
            A2   => std_logic_vector(b_paddr),
            CE1  => a_clk,
            CE2  => b_clk,
            WEB1 => a_col_web(c),
            WEB2 => b_col_web(c),
            OEB1 => '0',
            OEB2 => '0',
            CSB1 => a_csb,
            CSB2 => b_csb,
            I1   => std_logic_vector(a_wdata_pad(LO_C + 31 downto LO_C)),
            I2   => std_logic_vector(b_wdata_pad(LO_C + 31 downto LO_C)),
            O1   => o1,
            O2   => o2,
            SD   => sd_i,
            LS1  => ls_i,
            LS2  => ls_i,
            DS1  => ds_i,
            DS2  => ds_i
          );
        a_row_rdata(r)(LO_C + 31 downto LO_C) <= std_ulogic_vector(o1);
        b_row_rdata(r)(LO_C + 31 downto LO_C) <= std_ulogic_vector(o2);
      end generate gen_32x16;

      gen_32x32 : if PRIM_W_C = 32 and PRIM_D_C = 32 generate
        signal o1 : std_logic_vector(31 downto 0);
        signal o2 : std_logic_vector(31 downto 0);
      begin
        u_prim : SRAMLP2RW32x32
          port map (
            A1   => std_logic_vector(a_paddr),
            A2   => std_logic_vector(b_paddr),
            CE1  => a_clk,
            CE2  => b_clk,
            WEB1 => a_col_web(c),
            WEB2 => b_col_web(c),
            OEB1 => '0',
            OEB2 => '0',
            CSB1 => a_csb,
            CSB2 => b_csb,
            I1   => std_logic_vector(a_wdata_pad(LO_C + 31 downto LO_C)),
            I2   => std_logic_vector(b_wdata_pad(LO_C + 31 downto LO_C)),
            O1   => o1,
            O2   => o2,
            SD   => sd_i,
            LS1  => ls_i,
            LS2  => ls_i,
            DS1  => ds_i,
            DS2  => ds_i
          );
        a_row_rdata(r)(LO_C + 31 downto LO_C) <= std_ulogic_vector(o1);
        b_row_rdata(r)(LO_C + 31 downto LO_C) <= std_ulogic_vector(o2);
      end generate gen_32x32;

      gen_32x64 : if PRIM_W_C = 32 and PRIM_D_C = 64 generate
        signal o1 : std_logic_vector(31 downto 0);
        signal o2 : std_logic_vector(31 downto 0);
      begin
        u_prim : SRAMLP2RW64x32
          port map (
            A1   => std_logic_vector(a_paddr),
            A2   => std_logic_vector(b_paddr),
            CE1  => a_clk,
            CE2  => b_clk,
            WEB1 => a_col_web(c),
            WEB2 => b_col_web(c),
            OEB1 => '0',
            OEB2 => '0',
            CSB1 => a_csb,
            CSB2 => b_csb,
            I1   => std_logic_vector(a_wdata_pad(LO_C + 31 downto LO_C)),
            I2   => std_logic_vector(b_wdata_pad(LO_C + 31 downto LO_C)),
            O1   => o1,
            O2   => o2,
            SD   => sd_i,
            LS1  => ls_i,
            LS2  => ls_i,
            DS1  => ds_i,
            DS2  => ds_i
          );
        a_row_rdata(r)(LO_C + 31 downto LO_C) <= std_ulogic_vector(o1);
        b_row_rdata(r)(LO_C + 31 downto LO_C) <= std_ulogic_vector(o2);
      end generate gen_32x64;

      gen_32x128 : if PRIM_W_C = 32 and PRIM_D_C = 128 generate
        signal o1 : std_logic_vector(31 downto 0);
        signal o2 : std_logic_vector(31 downto 0);
      begin
        u_prim : SRAMLP2RW128x32
          port map (
            A1   => std_logic_vector(a_paddr),
            A2   => std_logic_vector(b_paddr),
            CE1  => a_clk,
            CE2  => b_clk,
            WEB1 => a_col_web(c),
            WEB2 => b_col_web(c),
            OEB1 => '0',
            OEB2 => '0',
            CSB1 => a_csb,
            CSB2 => b_csb,
            I1   => std_logic_vector(a_wdata_pad(LO_C + 31 downto LO_C)),
            I2   => std_logic_vector(b_wdata_pad(LO_C + 31 downto LO_C)),
            O1   => o1,
            O2   => o2,
            SD   => sd_i,
            LS1  => ls_i,
            LS2  => ls_i,
            DS1  => ds_i,
            DS2  => ds_i
          );
        a_row_rdata(r)(LO_C + 31 downto LO_C) <= std_ulogic_vector(o1);
        b_row_rdata(r)(LO_C + 31 downto LO_C) <= std_ulogic_vector(o2);
      end generate gen_32x128;
    end generate gen_col;
  end generate gen_row;

end architecture rtl;
