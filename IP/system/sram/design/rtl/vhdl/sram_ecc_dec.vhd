-- sram_ecc_dec.vhd — SECDED (extended Hamming) decoder for the sram IP.
--
-- VHDL-2008 twin of sram_ecc_dec.sv. Input layout as produced by
-- sram_ecc_enc: overall & check(R-1 downto 0) & data(K-1 downto 0).
--   parity = 0, syndrome = 0   no error
--   parity = 1                 single error, corrected
--   parity = 0, syndrome /= 0  double error, uncorrectable

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sram_pkg.all;

entity sram_ecc_dec is
  generic (
    K : positive := 32 -- data bits
  );
  port (
    code_i   : in  std_ulogic_vector(K + ecc_check_bits(K) - 1 downto 0); -- stored codeword
    data_o   : out std_ulogic_vector(K - 1 downto 0); -- corrected data
    single_o : out std_ulogic;                        -- corrected error
    double_o : out std_ulogic                         -- uncorrectable error
  );
end entity sram_ecc_dec;

architecture rtl of sram_ecc_dec is

  constant R_C : natural := ecc_hamming_bits(K);

  type pos_t   is array (0 to K - 1) of std_ulogic_vector(R_C - 1 downto 0);
  type cover_t is array (0 to R_C - 1) of std_ulogic_vector(K - 1 downto 0);

  -- True when n is a power of two (n >= 1).
  function is_pow2(n : positive) return boolean is
    variable v : natural := n;
  begin
    while v mod 2 = 0 loop
      v := v / 2;
    end loop;
    return v = 1;
  end function is_pow2;

  -- POS(j) = Hamming position of data bit j (as ecc_data_pos(j)), computed at
  -- elaboration in O(K); COVER_C(i) = data bits whose position has bit i set.
  -- Constants, so no tool runs a position search per bit (see sram_ecc_enc).
  function data_positions return pos_t is
    variable p   : pos_t;
    variable pos : natural := 2;
  begin
    for j in 0 to K - 1 loop
      pos := pos + 1;                       -- next position ...
      if is_pow2(pos) then                  -- ... that is not a power of two
        pos := pos + 1;
      end if;
      p(j) := std_ulogic_vector(to_unsigned(pos, R_C));
    end loop;
    return p;
  end function data_positions;

  constant POS : pos_t := data_positions;

  function cover_masks return cover_t is
    variable m : cover_t := (others => (others => '0'));
  begin
    for j in 0 to K - 1 loop
      for i in 0 to R_C - 1 loop
        m(i)(j) := POS(j)(i);
      end loop;
    end loop;
    return m;
  end function cover_masks;

  constant COVER_C : cover_t := cover_masks;

  signal data     : std_ulogic_vector(K - 1 downto 0);
  signal syndrome : std_ulogic_vector(R_C - 1 downto 0);
  signal parity   : std_ulogic;

begin

  data <= code_i(K - 1 downto 0);

  -- Syndrome and overall parity.
  g_syn : for i in 0 to R_C - 1 generate
    syndrome(i) <= code_i(K + i) xor (xor (data and COVER_C(i)));
  end generate g_syn;
  parity <= xor code_i;

  -- Single-bit correction: flip the data bit whose position equals the
  -- syndrome (a flipped check or parity bit leaves the data intact).
  g_fix : for j in 0 to K - 1 generate
    data_o(j) <= data(j) xor (parity and (syndrome ?= POS(j)));
  end generate g_fix;

  single_o <= parity;
  double_o <= (not parity) and (or syndrome);

end architecture rtl;
