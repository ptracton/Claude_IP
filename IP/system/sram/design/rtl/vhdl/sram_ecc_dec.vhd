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

begin

  -- Syndrome, overall parity and single-bit correction.
  p_decode : process (all) is
    variable data     : std_ulogic_vector(K - 1 downto 0);
    variable syndrome : std_ulogic_vector(R_C - 1 downto 0);
    variable parity   : std_ulogic;
    variable fixed    : std_ulogic_vector(K - 1 downto 0);
  begin
    data     := code_i(K - 1 downto 0);
    syndrome := code_i(K + R_C - 1 downto K);
    for j in 0 to K - 1 loop
      for i in 0 to R_C - 1 loop
        if ((ecc_data_pos(j) / (2 ** i)) mod 2) = 1 then
          syndrome(i) := syndrome(i) xor data(j);
        end if;
      end loop;
    end loop;
    parity := xor code_i;
    fixed  := data;
    for j in 0 to K - 1 loop
      if parity = '1' and unsigned(syndrome) = to_unsigned(ecc_data_pos(j), R_C) then
        fixed(j) := not data(j);
      end if;
    end loop;
    data_o   <= fixed;
    single_o <= parity;
    if parity = '0' and unsigned(syndrome) /= 0 then
      double_o <= '1';
    else
      double_o <= '0';
    end if;
  end process p_decode;

end architecture rtl;
