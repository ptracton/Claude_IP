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

begin

  -- Hamming check bits and overall parity.
  p_encode : process (all) is
    variable check   : std_ulogic_vector(R_C - 1 downto 0);
    variable overall : std_ulogic;
  begin
    check := (others => '0');
    for j in 0 to K - 1 loop
      for i in 0 to R_C - 1 loop
        if ((ecc_data_pos(j) / (2 ** i)) mod 2) = 1 then
          check(i) := check(i) xor data_i(j);
        end if;
      end loop;
    end loop;
    overall := (xor data_i) xor (xor check);
    code_o  <= overall & check & data_i;
  end process p_encode;

end architecture rtl;
