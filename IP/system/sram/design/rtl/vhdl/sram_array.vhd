-- sram_array.vhd — Splits the array into NUM_BANKS banks (and, for a dual
-- port with different widths, R slices per bank).
--
-- VHDL-2008 twin of sram_array.sv (see it for the full description). The top
-- index bits select the bank (own sleep pins). Single port: one sram_macro
-- of MW x DEPTH / NUM_BANKS per bank. DUAL_PORT: ports A (MW x DEPTH, clk)
-- and B (MW_B x DEPTH_B, b_clk) share the storage, R = wide / narrow; each
-- bank holds R slices (sram_macro_dp of the narrow stored width). The wide
-- port drives every slice; the narrow port selects slice (index mod R),
-- with a registered slice select on its own clock. Narrow word j is bits
-- [(j mod R) * SW +: SW] of wide word j / R.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sram_pkg.all;

entity sram_array is
  generic (
    TECH       : natural  := TECH_GENERIC_C; -- technology
    MW         : positive := 32;             -- port A stored word width (data + ECC)
    DEPTH      : positive := 1024;           -- port A words
    NUM_BANKS  : positive := 1;              -- banks (power domains)
    NLANES     : positive := 4;              -- port A write lanes
    DUAL_PORT  : natural  := 0;              -- second port b_* (0 / 1)
    MW_B       : positive := 32;             -- port B stored word width
    DEPTH_B    : positive := 1024;           -- port B words
    NLANES_B   : positive := 4;              -- port B write lanes
    COMMON_CLK : natural  := 1;              -- b_clk is clk (0 / 1)
    INIT_FILE  : string   := ""              -- preload (GENERIC/FPGA, NUM_BANKS = 1, R = 1)
  );
  port (
    clk         : in  std_ulogic;                                     -- port A clock
    cs_i        : in  std_ulogic;                                     -- access this cycle
    we_i        : in  std_ulogic;                                     -- 1 = write, 0 = read
    idx_i       : in  std_ulogic_vector(clog2(DEPTH) - 1 downto 0);   -- word index
    wdata_i     : in  std_ulogic_vector(MW - 1 downto 0);             -- stored word to write
    lane_we_i   : in  std_ulogic_vector(NLANES - 1 downto 0);         -- lanes to write
    ls_i        : in  std_ulogic_vector(NUM_BANKS - 1 downto 0);      -- light sleep, per bank
    ds_i        : in  std_ulogic_vector(NUM_BANKS - 1 downto 0);      -- deep sleep, per bank
    sd_i        : in  std_ulogic_vector(NUM_BANKS - 1 downto 0);      -- shutdown, per bank
    rdata_o     : out std_ulogic_vector(MW - 1 downto 0);             -- stored word (read + 1)

    -- Port B (DUAL_PORT; tie inputs to 0 otherwise)
    b_clk       : in  std_ulogic;                                     -- port B clock
    b_cs_i      : in  std_ulogic;                                     -- access this cycle
    b_we_i      : in  std_ulogic;                                     -- 1 = write
    b_idx_i     : in  std_ulogic_vector(clog2(DEPTH_B) - 1 downto 0); -- word index
    b_wdata_i   : in  std_ulogic_vector(MW_B - 1 downto 0);           -- stored word to write
    b_lane_we_i : in  std_ulogic_vector(NLANES_B - 1 downto 0);       -- lanes to write
    b_rdata_o   : out std_ulogic_vector(MW_B - 1 downto 0)            -- stored word (read + 1)
  );
end entity sram_array;

architecture rtl of sram_array is

  -- Geometry (see sram_array.sv).
  function a_wide return boolean is
  begin
    return DUAL_PORT = 0 or MW >= MW_B;
  end function a_wide;

  function ratio return positive is
  begin
    if DUAL_PORT = 0 then
      return 1;
    elsif MW >= MW_B then
      return MW / MW_B;
    end if;
    return MW_B / MW;
  end function ratio;

  constant A_WIDE_C   : boolean  := a_wide;
  constant R_C        : positive := ratio;
  constant R_SH_C     : natural  := clog2(R_C);
  constant A_SLICED_C : boolean  := DUAL_PORT /= 0 and not A_WIDE_C and R_C > 1;
  constant B_SLICED_C : boolean  := DUAL_PORT /= 0 and A_WIDE_C and R_C > 1;

  function slice_width return positive is
  begin
    if DUAL_PORT /= 0 and A_WIDE_C then
      return MW_B;
    end if;
    return MW;
  end function slice_width;

  function slice_depth return positive is
  begin
    if A_WIDE_C then
      return DEPTH / NUM_BANKS;
    end if;
    return DEPTH_B / NUM_BANKS;
  end function slice_depth;

  -- Lanes per slice of a port: the wide port's lanes divide over the slices.
  function lanes_per_slice(nl : positive; sliced : boolean) return positive is
  begin
    if sliced then
      return nl;
    elsif nl >= R_C then
      return nl / R_C;
    end if;
    return 1;
  end function lanes_per_slice;

  constant SW_C        : positive := slice_width;
  constant SD_C        : positive := slice_depth;
  constant BANK_AW_A_C : positive := clog2(DEPTH / NUM_BANKS);
  constant BANK_AW_B_C : positive := clog2(DEPTH_B / NUM_BANKS);
  constant SAW_C       : positive := clog2(SD_C);
  constant BANK_W_C    : positive := maximum(1, clog2(NUM_BANKS));
  constant SL_W_C      : positive := maximum(1, R_SH_C);
  constant LPS_A_C     : positive := lanes_per_slice(NLANES, A_SLICED_C);
  constant LPS_B_C     : positive := lanes_per_slice(NLANES_B, B_SLICED_C);

  function slice_lanes_total return positive is
  begin
    if DUAL_PORT = 0 then
      return NLANES;
    end if;
    return maximum(LPS_A_C, LPS_B_C);
  end function slice_lanes_total;

  constant SL_C : positive := slice_lanes_total;

  -- Preload only applies to one slice per bank (R = 1).
  function slice_init return string is
  begin
    if R_C = 1 then
      return INIT_FILE;
    end if;
    return "";
  end function slice_init;

  -- One port's lanes for slice s, expanded to the slice's SL_C lanes.
  function slice_lanes(lanes : std_ulogic_vector; nl : positive; sliced : boolean;
                       lps : positive; s : natural) return std_ulogic_vector is
    variable l : std_ulogic_vector(SL_C - 1 downto 0);
  begin
    for i in 0 to SL_C - 1 loop
      if sliced then
        if lps = SL_C then
          l(i) := lanes(lanes'low + i);
        else
          l(i) := lanes(lanes'low);
        end if;
      elsif nl >= R_C then
        if lps = SL_C then
          l(i) := lanes(lanes'low + s * lps + i);
        else
          l(i) := lanes(lanes'low + s * lps);
        end if;
      else
        l(i) := lanes(lanes'low);
      end if;
    end loop;
    return l;
  end function slice_lanes;

  type a_bank_data_t is array (0 to NUM_BANKS - 1) of std_ulogic_vector(MW - 1 downto 0);
  type b_bank_data_t is array (0 to NUM_BANKS - 1) of std_ulogic_vector(MW_B - 1 downto 0);

  signal a_bank       : unsigned(BANK_W_C - 1 downto 0); -- bank addressed this cycle
  signal a_rd_bank_q  : unsigned(BANK_W_C - 1 downto 0) := (others => '0'); -- bank read last
  signal a_slice      : unsigned(SL_W_C - 1 downto 0);   -- slice (A narrow only)
  signal a_rd_slice_q : unsigned(SL_W_C - 1 downto 0) := (others => '0');
  signal a_saddr      : std_ulogic_vector(SAW_C - 1 downto 0); -- word address in the slice
  signal a_bank_rdata : a_bank_data_t;

  signal b_bank       : unsigned(BANK_W_C - 1 downto 0);
  signal b_rd_bank_q  : unsigned(BANK_W_C - 1 downto 0) := (others => '0');
  signal b_slice      : unsigned(SL_W_C - 1 downto 0);
  signal b_rd_slice_q : unsigned(SL_W_C - 1 downto 0) := (others => '0');
  signal b_saddr      : std_ulogic_vector(SAW_C - 1 downto 0);
  signal b_bank_rdata : b_bank_data_t;

begin

  assert_cap_a : assert DUAL_PORT = 0 or MW * DEPTH = MW_B * DEPTH_B
      report "sram_array: ports A and B must have the same capacity" severity failure;
  assert_ratio_a : assert 2 ** R_SH_C = R_C
      report "sram_array: width ratio is not a power of two" severity failure;
  assert_lanes_a : assert DUAL_PORT = 0 or ((LPS_A_C = SL_C or LPS_A_C = 1) and
                                            (LPS_B_C = SL_C or LPS_B_C = 1))
      report "sram_array: lanes per slice of the two ports do not match" severity failure;

  -----------------------------------------------
  -- Port A decode and read multiplexer (clk)  --
  -----------------------------------------------
  gen_a_bank : if NUM_BANKS > 1 generate
    a_bank <= resize(shift_right(unsigned(idx_i), BANK_AW_A_C), BANK_W_C);
  else generate
    a_bank <= (others => '0');
  end generate gen_a_bank;

  gen_a_slice : if A_SLICED_C generate
    a_slice <= resize(unsigned(idx_i(BANK_AW_A_C - 1 downto 0)), SL_W_C);
    a_saddr <= std_ulogic_vector(resize(shift_right(unsigned(idx_i(BANK_AW_A_C - 1 downto 0)),
                                                    R_SH_C), SAW_C));
  else generate
    a_slice <= (others => '0');
    a_saddr <= std_ulogic_vector(resize(unsigned(idx_i(BANK_AW_A_C - 1 downto 0)), SAW_C));
  end generate gen_a_slice;

  p_a_rd_sel : process (clk) is
  begin
    if rising_edge(clk) then
      if cs_i = '1' and we_i = '0' then
        a_rd_bank_q  <= a_bank;
        a_rd_slice_q <= a_slice;
      end if;
    end if;
  end process p_a_rd_sel;

  rdata_o <= a_bank_rdata(to_integer(a_rd_bank_q)) when NUM_BANKS > 1 else a_bank_rdata(0);

  -------------------------------------------------
  -- Port B decode and read multiplexer (b_clk)  --
  -------------------------------------------------
  gen_b_bank : if NUM_BANKS > 1 generate
    b_bank <= resize(shift_right(unsigned(b_idx_i), BANK_AW_B_C), BANK_W_C);
  else generate
    b_bank <= (others => '0');
  end generate gen_b_bank;

  gen_b_slice : if B_SLICED_C generate
    b_slice <= resize(unsigned(b_idx_i(BANK_AW_B_C - 1 downto 0)), SL_W_C);
    b_saddr <= std_ulogic_vector(resize(shift_right(unsigned(b_idx_i(BANK_AW_B_C - 1 downto 0)),
                                                    R_SH_C), SAW_C));
  else generate
    b_slice <= (others => '0');
    b_saddr <= std_ulogic_vector(resize(unsigned(b_idx_i(BANK_AW_B_C - 1 downto 0)), SAW_C));
  end generate gen_b_slice;

  p_b_rd_sel : process (b_clk) is
  begin
    if rising_edge(b_clk) then
      if b_cs_i = '1' and b_we_i = '0' then
        b_rd_bank_q  <= b_bank;
        b_rd_slice_q <= b_slice;
      end if;
    end if;
  end process p_b_rd_sel;

  b_rdata_o <= (others => '0') when DUAL_PORT = 0 else
               b_bank_rdata(to_integer(b_rd_bank_q)) when NUM_BANKS > 1 else b_bank_rdata(0);

  -----------
  -- Banks --
  -----------
  gen_bank : for k in 0 to NUM_BANKS - 1 generate
    signal a_bank_cs : std_ulogic;
    signal b_bank_cs : std_ulogic;
  begin
    a_bank_cs <= '1' when cs_i = '1' and a_bank = to_unsigned(k, BANK_W_C) else '0';
    b_bank_cs <= '1' when b_cs_i = '1' and b_bank = to_unsigned(k, BANK_W_C) else '0';

    gen_port : if DUAL_PORT /= 0 generate
      type slice_data_t is array (0 to R_C - 1) of std_ulogic_vector(SW_C - 1 downto 0);
      signal a_slice_rdata : slice_data_t;
      signal b_slice_rdata : slice_data_t;
    begin
      gen_slice : for s in 0 to R_C - 1 generate
        signal a_cs : std_ulogic;
        signal b_cs : std_ulogic;
        signal a_wd : std_ulogic_vector(SW_C - 1 downto 0);
        signal b_wd : std_ulogic_vector(SW_C - 1 downto 0);
        signal a_lw : std_ulogic_vector(SL_C - 1 downto 0);
        signal b_lw : std_ulogic_vector(SL_C - 1 downto 0);
      begin
        a_cs <= '1' when a_bank_cs = '1' and (not A_SLICED_C or a_slice = to_unsigned(s, SL_W_C))
                else '0';
        b_cs <= '1' when b_bank_cs = '1' and (not B_SLICED_C or b_slice = to_unsigned(s, SL_W_C))
                else '0';

        gen_a_wd : if A_SLICED_C generate
          a_wd <= std_ulogic_vector(resize(unsigned(wdata_i), SW_C));
        else generate
          a_wd <= wdata_i(s * SW_C + SW_C - 1 downto s * SW_C);
        end generate gen_a_wd;

        gen_b_wd : if B_SLICED_C generate
          b_wd <= std_ulogic_vector(resize(unsigned(b_wdata_i), SW_C));
        else generate
          b_wd <= b_wdata_i(s * SW_C + SW_C - 1 downto s * SW_C);
        end generate gen_b_wd;

        a_lw <= slice_lanes(lane_we_i, NLANES, A_SLICED_C, LPS_A_C, s);
        b_lw <= slice_lanes(b_lane_we_i, NLANES_B, B_SLICED_C, LPS_B_C, s);

        u_macro : entity work.sram_macro_dp(rtl)
          generic map (
            TECH       => TECH,
            W          => SW_C,
            D          => SD_C,
            NLANES     => SL_C,
            COMMON_CLK => COMMON_CLK,
            INIT_FILE  => slice_init
          )
          port map (
            a_clk       => clk,
            a_cs_i      => a_cs,
            a_we_i      => we_i,
            a_addr_i    => a_saddr,
            a_wdata_i   => a_wd,
            a_lane_we_i => a_lw,
            a_rdata_o   => a_slice_rdata(s),
            b_clk       => b_clk,
            b_cs_i      => b_cs,
            b_we_i      => b_we_i,
            b_addr_i    => b_saddr,
            b_wdata_i   => b_wd,
            b_lane_we_i => b_lw,
            b_rdata_o   => b_slice_rdata(s),
            ls_i        => ls_i(k),
            ds_i        => ds_i(k),
            sd_i        => sd_i(k)
          );

        -- The wide port reads every slice.
        gen_a_cat : if not A_SLICED_C generate
          a_bank_rdata(k)(s * SW_C + SW_C - 1 downto s * SW_C) <= a_slice_rdata(s);
        end generate gen_a_cat;
        gen_b_cat : if not B_SLICED_C generate
          b_bank_rdata(k)(s * SW_C + SW_C - 1 downto s * SW_C) <= b_slice_rdata(s);
        end generate gen_b_cat;
      end generate gen_slice;

      -- The narrow port reads the slice it addressed.
      gen_a_mux : if A_SLICED_C generate
        a_bank_rdata(k) <= a_slice_rdata(to_integer(a_rd_slice_q));
      end generate gen_a_mux;
      gen_b_mux : if B_SLICED_C generate
        b_bank_rdata(k) <= b_slice_rdata(to_integer(b_rd_slice_q));
      end generate gen_b_mux;
    else generate
      b_bank_rdata(k) <= (others => '0');

      u_macro : entity work.sram_macro(rtl)
        generic map (
          TECH      => TECH,
          W         => MW,
          D         => SD_C,
          NLANES    => NLANES,
          INIT_FILE => INIT_FILE
        )
        port map (
          clk       => clk,
          cs_i      => a_bank_cs,
          we_i      => we_i,
          addr_i    => a_saddr,
          wdata_i   => wdata_i,
          lane_we_i => lane_we_i,
          ls_i      => ls_i(k),
          ds_i      => ds_i(k),
          sd_i      => sd_i(k),
          rdata_o   => a_bank_rdata(k)
        );
    end generate gen_port;
  end generate gen_bank;

end architecture rtl;
