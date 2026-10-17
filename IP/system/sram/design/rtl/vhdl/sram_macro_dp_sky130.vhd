-- sram_macro_dp_sky130.vhd — SKY130 OpenRAM SRAM wrapper (TECH_SKY130, DUAL_PORT).
--
-- VHDL-2008 twin of sram_macro_dp_sky130.sv.
--
-- A W x D memory built from the same 1rw1r macros as sram_macro_sky130,
-- with both macro ports used:
--   port 0 = port A, read/write: csb0 = not A row select, web0 = not a_we_i,
--            wmask0 = lane enable of each byte, addr0, din0, dout0
--   port 1 = port B, READ ONLY:  csb1 = not B row select, addr1, dout1
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
-- Example: W = 32, D = 2048 -> 32x512 primitives, 4 rows x 1 column.
--
-- The core turns every port-B write into a bus error for this technology
-- (sram_port READ_ONLY), so b_we_i / b_wdata_i / b_lane_we_i are never needed.
-- Each port has its own row decode and row register on its own clock (clk0 =
-- a_clk, clk1 = b_clk). Read data is valid in the cycle after a read; the
-- simulation clock period must exceed ~8 ns on each port.
-- VERBOSE = 0. ls_i / ds_i / sd_i are unused: no sleep pins (UPF).
-- The primitives are Verilog models declared as components (vendor
-- primitives) with std_logic ports.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sram_pkg.all;

entity sram_macro_dp_sky130 is
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

  constant PRIM_W_C  : positive := prim_width_dp(TECH_SKY130_C, W, NLANES);
  constant PRIM_D_C  : positive := prim_depth_dp(TECH_SKY130_C, PRIM_W_C, D);
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
  signal a_row_rdata : row_data_t; -- port A: read data of each row
  signal b_row       : unsigned(ROW_W_C - 1 downto 0); -- port B: row addressed
  signal b_rd_row_q  : unsigned(ROW_W_C - 1 downto 0) := (others => '0'); -- port B: row read
  signal b_paddr     : std_ulogic_vector(PRIM_AW_C - 1 downto 0); -- port B: primitive address
  signal b_row_rdata : row_data_t; -- port B: read data of each row
  signal a_web       : std_ulogic; -- write enable, active low

begin

  assert_d_a : assert D >= 2 and 2 ** clog2(D) = D
      report "sram_macro_dp_sky130: D must be a power of two >= 2" severity failure;
  assert_lanes_a : assert W mod NLANES = 0
      report "sram_macro_dp_sky130: NLANES must divide W" severity failure;
  assert_col_a : assert NLANES = 1 or (W / NLANES) mod 8 = 0
      report "sram_macro_dp_sky130: a byte crosses a write lane" severity failure;
  -- Elaboration-time error: no primitive of this size in the curated list.
  assert_size_a : assert (PRIM_W_C = 32 and PRIM_D_C = 256) or
                         (PRIM_W_C = 32 and PRIM_D_C = 512) or (PRIM_W_C = 8 and PRIM_D_C = 1024)
      report "sram_macro_dp_sky130: no primitive of this size" severity failure;

  -- Low address bits go to every primitive (zero-extended when D < PRIM_D).
  a_paddr     <= std_ulogic_vector(resize(unsigned(a_addr_i), PRIM_AW_C));
  b_paddr     <= std_ulogic_vector(resize(unsigned(b_addr_i), PRIM_AW_C));
  a_wdata_pad <= std_ulogic_vector(resize(unsigned(a_wdata_i), PAD_W_C));
  a_web       <= not a_we_i;

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
        if b_cs_i = '1' then
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

  gen_row : for r in 0 to ROWS_C - 1 generate
    signal a_csb : std_logic; -- this row's port A chip select, active low
    signal b_csb : std_logic; -- this row's port B chip select, active low
  begin
    a_csb <= '0' when a_cs_i = '1' and a_row = to_unsigned(r, ROW_W_C) else '1';
    b_csb <= '0' when b_cs_i = '1' and b_row = to_unsigned(r, ROW_W_C) else '1';

    gen_col : for c in 0 to COLS_C - 1 generate
      constant LO_C : natural := c * PRIM_W_C; -- lowest bit of this column
      signal a_wmask : std_ulogic_vector(PRIM_W_C / 8 - 1 downto 0); -- byte write mask
    begin
      gen_byte : for k in 0 to PRIM_W_C / 8 - 1 generate
        a_wmask(k) <= a_lane_we_i(lane_of(LO_C + 8 * k, W, NLANES));
      end generate gen_byte;

      gen_32x256 : if PRIM_W_C = 32 and PRIM_D_C = 256 generate
        signal o1 : std_logic_vector(31 downto 0);
        signal o2 : std_logic_vector(31 downto 0);
      begin
        u_prim : sky130_sram_1kbyte_1rw1r_32x256_8
          generic map (
            VERBOSE => 0
          )
          port map (
            clk0   => a_clk,
            csb0   => a_csb,
            web0   => a_web,
            wmask0 => std_logic_vector(a_wmask),
            addr0  => std_logic_vector(a_paddr),
            din0   => std_logic_vector(a_wdata_pad(LO_C + 31 downto LO_C)),
            dout0  => o1,
            clk1   => b_clk,
            csb1   => b_csb,
            addr1  => std_logic_vector(b_paddr),
            dout1  => o2
          );
        a_row_rdata(r)(LO_C + 31 downto LO_C) <= std_ulogic_vector(o1);
        b_row_rdata(r)(LO_C + 31 downto LO_C) <= std_ulogic_vector(o2);
      end generate gen_32x256;

      gen_32x512 : if PRIM_W_C = 32 and PRIM_D_C = 512 generate
        signal o1 : std_logic_vector(31 downto 0);
        signal o2 : std_logic_vector(31 downto 0);
      begin
        u_prim : sky130_sram_2kbyte_1rw1r_32x512_8
          generic map (
            VERBOSE => 0
          )
          port map (
            clk0   => a_clk,
            csb0   => a_csb,
            web0   => a_web,
            wmask0 => std_logic_vector(a_wmask),
            addr0  => std_logic_vector(a_paddr),
            din0   => std_logic_vector(a_wdata_pad(LO_C + 31 downto LO_C)),
            dout0  => o1,
            clk1   => b_clk,
            csb1   => b_csb,
            addr1  => std_logic_vector(b_paddr),
            dout1  => o2
          );
        a_row_rdata(r)(LO_C + 31 downto LO_C) <= std_ulogic_vector(o1);
        b_row_rdata(r)(LO_C + 31 downto LO_C) <= std_ulogic_vector(o2);
      end generate gen_32x512;

      gen_8x1024 : if PRIM_W_C = 8 and PRIM_D_C = 1024 generate
        signal o1 : std_logic_vector(7 downto 0);
        signal o2 : std_logic_vector(7 downto 0);
      begin
        u_prim : sky130_sram_1kbyte_1rw1r_8x1024_8
          generic map (
            VERBOSE => 0
          )
          port map (
            clk0   => a_clk,
            csb0   => a_csb,
            web0   => a_web,
            wmask0 => std_logic_vector(a_wmask),
            addr0  => std_logic_vector(a_paddr),
            din0   => std_logic_vector(a_wdata_pad(LO_C + 7 downto LO_C)),
            dout0  => o1,
            clk1   => b_clk,
            csb1   => b_csb,
            addr1  => std_logic_vector(b_paddr),
            dout1  => o2
          );
        a_row_rdata(r)(LO_C + 7 downto LO_C) <= std_ulogic_vector(o1);
        b_row_rdata(r)(LO_C + 7 downto LO_C) <= std_ulogic_vector(o2);
      end generate gen_8x1024;
    end generate gen_col;
  end generate gen_row;

end architecture rtl;
