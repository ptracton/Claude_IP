-- sram_array.vhd — Tiles sram_macro instances into a DEPTH x MW array.
--
-- VHDL-2008 twin of sram_array.sv: NUM_BANKS banks (each with its own sleep
-- pins), each split into rows of MAC_D words and columns of MAC_W bits
-- (MAC_W / MAC_D from sram_pkg macro_width / macro_depth for TECH). The last
-- column is zero-padded when MAC_W does not divide MW. Each column byte takes
-- the write enable of the lane its first bit falls in. rdata_o is valid in
-- the cycle after a read and comes from the tile read in the previous cycle.
-- DUAL_PORT: a second, independent port (b_*) on two-port macros
-- (sram_macro_dp, macro_*_dp) with its own read multiplexer.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sram_pkg.all;

entity sram_array is
  generic (
    TECH      : natural  := TECH_GENERIC_C; -- technology
    MW        : positive := 32;             -- stored word width (data + ECC)
    DEPTH     : positive := 1024;           -- words
    NUM_BANKS : positive := 1;              -- banks (power domains)
    NLANES    : positive := 4;              -- write lanes
    DUAL_PORT : natural  := 0;              -- second port b_* (0 / 1)
    INIT_FILE : string   := ""              -- preload (GENERIC/FPGA, NUM_BANKS = 1)
  );
  port (
    clk         : in  std_ulogic;                                   -- clock
    cs_i        : in  std_ulogic;                                   -- access this cycle
    we_i        : in  std_ulogic;                                   -- 1 = write, 0 = read
    idx_i       : in  std_ulogic_vector(clog2(DEPTH) - 1 downto 0); -- word index
    wdata_i     : in  std_ulogic_vector(MW - 1 downto 0);           -- stored word to write
    lane_we_i   : in  std_ulogic_vector(NLANES - 1 downto 0);       -- lanes to write
    ls_i        : in  std_ulogic_vector(NUM_BANKS - 1 downto 0);    -- light sleep, per bank
    ds_i        : in  std_ulogic_vector(NUM_BANKS - 1 downto 0);    -- deep sleep, per bank
    sd_i        : in  std_ulogic_vector(NUM_BANKS - 1 downto 0);    -- shutdown, per bank
    rdata_o     : out std_ulogic_vector(MW - 1 downto 0);           -- stored word (read + 1)

    -- Port B (DUAL_PORT; tie inputs to 0 otherwise)
    b_cs_i      : in  std_ulogic;                                   -- access this cycle
    b_we_i      : in  std_ulogic;                                   -- 1 = write
    b_idx_i     : in  std_ulogic_vector(clog2(DEPTH) - 1 downto 0); -- word index
    b_wdata_i   : in  std_ulogic_vector(MW - 1 downto 0);           -- stored word to write
    b_lane_we_i : in  std_ulogic_vector(NLANES - 1 downto 0);       -- lanes to write
    b_rdata_o   : out std_ulogic_vector(MW - 1 downto 0)            -- stored word (read + 1)
  );
end entity sram_array;

architecture rtl of sram_array is

  constant LANE_W_C : positive := MW / NLANES;
  function mac_width return positive is
  begin
    if DUAL_PORT /= 0 then
      return macro_width_dp(TECH, MW, NLANES);
    end if;
    return macro_width(TECH, MW, NLANES);
  end function mac_width;

  constant MAC_W_C  : positive := mac_width;
  constant BANK_D_C : positive := DEPTH / NUM_BANKS;

  function mac_depth return positive is
  begin
    if DUAL_PORT /= 0 then
      return macro_depth_dp(TECH, MAC_W_C, BANK_D_C);
    end if;
    return macro_depth(TECH, MAC_W_C, BANK_D_C);
  end function mac_depth;

  constant MAC_D_C  : positive := mac_depth;
  constant MAC_AW_C : natural  := clog2(MAC_D_C);
  constant COLS_C   : positive := (MW + MAC_W_C - 1) / MAC_W_C;
  constant PAD_W_C  : positive := COLS_C * MAC_W_C;

  function rows_of(bank_d : natural; mac_d : natural) return positive is
  begin
    if bank_d > mac_d then
      return bank_d / mac_d;
    end if;
    return 1;
  end function rows_of;

  function tile_shift(bank_d : natural; mac_d : natural) return natural is
  begin
    if mac_d <= bank_d then
      return clog2(mac_d);
    end if;
    return clog2(bank_d);
  end function tile_shift;

  -- Lane of stored bit p (padding bits take the last lane).
  function lane_of(p : natural) return natural is
  begin
    if p < MW then
      return p / LANE_W_C;
    end if;
    return (MW - 1) / LANE_W_C;
  end function lane_of;

  constant ROWS_C     : positive := rows_of(BANK_D_C, MAC_D_C);
  constant TILES_C    : positive := NUM_BANKS * ROWS_C;
  constant TILE_SH_C  : natural  := tile_shift(BANK_D_C, MAC_D_C);
  constant TILE_W_C   : positive := maximum(1, clog2(TILES_C));

  type tile_data_t is array (0 to TILES_C - 1) of std_ulogic_vector(PAD_W_C - 1 downto 0);

  signal tile       : unsigned(TILE_W_C - 1 downto 0); -- tile addressed this cycle
  signal rd_tile_q  : unsigned(TILE_W_C - 1 downto 0) := (others => '0'); -- tile read last cycle
  signal maddr      : std_ulogic_vector(MAC_AW_C - 1 downto 0);
  signal wdata_pad  : std_ulogic_vector(PAD_W_C - 1 downto 0);
  signal tile_rdata : tile_data_t;

  signal b_tile       : unsigned(TILE_W_C - 1 downto 0);
  signal b_rd_tile_q  : unsigned(TILE_W_C - 1 downto 0) := (others => '0');
  signal b_maddr      : std_ulogic_vector(MAC_AW_C - 1 downto 0);
  signal b_wdata_pad  : std_ulogic_vector(PAD_W_C - 1 downto 0);
  signal b_tile_rdata : tile_data_t;

begin

  gen_tile_sel : if TILES_C > 1 generate
    tile   <= resize(shift_right(unsigned(idx_i), TILE_SH_C), TILE_W_C);
    b_tile <= resize(shift_right(unsigned(b_idx_i), TILE_SH_C), TILE_W_C);
  else generate
    tile   <= (others => '0');
    b_tile <= (others => '0');
  end generate gen_tile_sel;

  gen_maddr : if TILE_SH_C > 0 generate
    maddr   <= std_ulogic_vector(resize(unsigned(idx_i(TILE_SH_C - 1 downto 0)), MAC_AW_C));
    b_maddr <= std_ulogic_vector(resize(unsigned(b_idx_i(TILE_SH_C - 1 downto 0)), MAC_AW_C));
  else generate
    maddr   <= (others => '0');
    b_maddr <= (others => '0');
  end generate gen_maddr;

  wdata_pad   <= std_ulogic_vector(resize(unsigned(wdata_i), PAD_W_C));
  b_wdata_pad <= std_ulogic_vector(resize(unsigned(b_wdata_i), PAD_W_C));

  -- Remember which tile each port read, for the read multiplexers.
  p_rd_tile : process (clk) is
  begin
    if rising_edge(clk) then
      if cs_i = '1' and we_i = '0' then
        rd_tile_q <= tile;
      end if;
      if b_cs_i = '1' and b_we_i = '0' then
        b_rd_tile_q <= b_tile;
      end if;
    end if;
  end process p_rd_tile;

  rdata_o   <= tile_rdata(to_integer(rd_tile_q))(MW - 1 downto 0);
  b_rdata_o <= b_tile_rdata(to_integer(b_rd_tile_q))(MW - 1 downto 0) when DUAL_PORT /= 0
               else (others => '0');

  gen_tile : for t in 0 to TILES_C - 1 generate
    constant BANK_C : natural := t / ROWS_C;
    signal tile_cs   : std_ulogic;
    signal b_tile_cs : std_ulogic;
  begin
    tile_cs   <= '1' when cs_i = '1' and tile = to_unsigned(t, TILE_W_C) else '0';
    b_tile_cs <= '1' when b_cs_i = '1' and b_tile = to_unsigned(t, TILE_W_C) else '0';

    gen_col : for c in 0 to COLS_C - 1 generate
      signal col_wbe   : std_ulogic_vector(MAC_W_C / 8 - 1 downto 0);
      signal b_col_wbe : std_ulogic_vector(MAC_W_C / 8 - 1 downto 0);
    begin
      gen_byte : for k in 0 to MAC_W_C / 8 - 1 generate
        col_wbe(k)   <= lane_we_i(lane_of(c * MAC_W_C + 8 * k));
        b_col_wbe(k) <= b_lane_we_i(lane_of(c * MAC_W_C + 8 * k));
      end generate gen_byte;

      gen_port : if DUAL_PORT /= 0 generate
        u_macro : entity work.sram_macro_dp(rtl)
          generic map (
            TECH      => TECH,
            MAC_W     => MAC_W_C,
            MAC_D     => MAC_D_C,
            INIT_FILE => INIT_FILE
          )
          port map (
            clk       => clk,
            a_cs_i    => tile_cs,
            a_we_i    => we_i,
            a_addr_i  => maddr,
            a_wdata_i => wdata_pad(c * MAC_W_C + MAC_W_C - 1 downto c * MAC_W_C),
            a_wbe_i   => col_wbe,
            a_rdata_o => tile_rdata(t)(c * MAC_W_C + MAC_W_C - 1 downto c * MAC_W_C),
            b_cs_i    => b_tile_cs,
            b_we_i    => b_we_i,
            b_addr_i  => b_maddr,
            b_wdata_i => b_wdata_pad(c * MAC_W_C + MAC_W_C - 1 downto c * MAC_W_C),
            b_wbe_i   => b_col_wbe,
            b_rdata_o => b_tile_rdata(t)(c * MAC_W_C + MAC_W_C - 1 downto c * MAC_W_C),
            ls_i      => ls_i(BANK_C),
            ds_i      => ds_i(BANK_C),
            sd_i      => sd_i(BANK_C)
          );
      else generate
        b_tile_rdata(t)(c * MAC_W_C + MAC_W_C - 1 downto c * MAC_W_C) <= (others => '0');

        u_macro : entity work.sram_macro(rtl)
          generic map (
            TECH      => TECH,
            MAC_W     => MAC_W_C,
            MAC_D     => MAC_D_C,
            INIT_FILE => INIT_FILE
          )
          port map (
            clk     => clk,
            cs_i    => tile_cs,
            we_i    => we_i,
            addr_i  => maddr,
            wdata_i => wdata_pad(c * MAC_W_C + MAC_W_C - 1 downto c * MAC_W_C),
            wbe_i   => col_wbe,
            ls_i    => ls_i(BANK_C),
            ds_i    => ds_i(BANK_C),
            sd_i    => sd_i(BANK_C),
            rdata_o => tile_rdata(t)(c * MAC_W_C + MAC_W_C - 1 downto c * MAC_W_C)
          );
      end generate gen_port;
    end generate gen_col;
  end generate gen_tile;

end architecture rtl;
