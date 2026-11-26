-- sram_ecc_enc.vhd — SECDED (extended Hamming) encoder for the sram IP.
--
-- VHDL-2008 twin of sram_ecc_enc.sv. Codeword layout:
--   code_o = overall parity & hamming check(R-1 downto 0) & data(K-1 downto 0)
-- All-zero data encodes to an all-zero codeword.

library ieee;
use ieee.std_logic_1164.all;
use work.sram_pkg.all;

entity sram_ecc_enc is
  generic (
    K : positive := 32 -- data bits
  );
  port (
    data_i : in  std_ulogic_vector(K - 1 downto 0);                    -- data to protect
    code_o : out std_ulogic_vector(K + ecc_check_bits(K) - 1 downto 0) -- stored codeword
  );
end entity sram_ecc_enc;

architecture rtl of sram_ecc_enc is

  constant R_C : natural := ecc_hamming_bits(K);

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

  -- COVER_C(i) = the data bits whose Hamming position has bit i set. Computed at
  -- elaboration in O(K) (ecc_data_pos(j) for every j, without its 1024-step
  -- search), so no tool evaluates or unrolls a position search per bit (VC
  -- Formal timed out on the VHDL ecc job with the per-bit search).
  function cover_masks return cover_t is
    variable m   : cover_t := (others => (others => '0'));
    variable pos : natural := 2;
  begin
    for j in 0 to K - 1 loop
      pos := pos + 1;                       -- next position ...
      if is_pow2(pos) then                  -- ... that is not a power of two
        pos := pos + 1;
      end if;
      for i in 0 to R_C - 1 loop
        if ((pos / (2 ** i)) mod 2) = 1 then
          m(i)(j) := '1';
        end if;
      end loop;
    end loop;
    return m;
  end function cover_masks;

  constant COVER_C : cover_t := cover_masks;

  signal check : std_ulogic_vector(R_C - 1 downto 0);

begin

  -- Hamming check bits and overall parity.
  g_check : for i in 0 to R_C - 1 generate
    check(i) <= red_xor(data_i and COVER_C(i));
  end generate g_check;

  code_o <= (red_xor(data_i) xor red_xor(check)) & check & data_i;

end architecture rtl;
