-- bus_matrix_decoder.vhd — Bus Matrix address decoder (VHDL-2008).
--
-- Decodes an address to a one-hot slave selection using a base+mask scheme.
-- Match condition: (addr and mask) = (base and mask). The lowest-numbered
-- matching slave wins. Combinational logic only. Mirrors bus_matrix_decoder.sv.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bus_matrix_decoder is
  generic (
    NUM_SLAVES : positive := 2;   -- 1-32 active slaves
    ADDR_W     : positive := 32;  -- address width (must be 32)
    -- Flat-packed address map, slave j at bits (j*32+31 downto j*32);
    -- maximum-width (32 slaves), only NUM_SLAVES entries are used.
    S_BASE     : std_ulogic_vector(32 * 32 - 1 downto 0) := (others => '0');
    S_MASK     : std_ulogic_vector(32 * 32 - 1 downto 0) := (others => '0')
  );
  port (
    addr       : in  std_ulogic_vector(ADDR_W - 1 downto 0);      -- address to decode
    slave_sel  : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);  -- one-hot (0 if no match)
    decode_err : out std_ulogic                                    -- no slave matched
  );
end entity bus_matrix_decoder;

architecture rtl of bus_matrix_decoder is

  signal match : std_ulogic_vector(NUM_SLAVES - 1 downto 0);  -- per-slave match flags
  signal sel   : std_ulogic_vector(NUM_SLAVES - 1 downto 0);  -- one-hot selection

begin

  p_match : process (addr) is
    variable base_j : std_ulogic_vector(ADDR_W - 1 downto 0);
    variable mask_j : std_ulogic_vector(ADDR_W - 1 downto 0);
  begin
    for j in 0 to NUM_SLAVES - 1 loop
      base_j := S_BASE(j * 32 + ADDR_W - 1 downto j * 32);
      mask_j := S_MASK(j * 32 + ADDR_W - 1 downto j * 32);
      if (addr and mask_j) = (base_j and mask_j) then
        match(j) <= '1';
      else
        match(j) <= '0';
      end if;
    end loop;
  end process p_match;

  -- Priority select: lowest-numbered matching slave wins (one-hot output).
  -- x and (not x + 1) isolates the lowest set bit.
  sel <= std_ulogic_vector(unsigned(match) and (unsigned(not match) + 1));

  slave_sel  <= sel;
  decode_err <= '1' when match = (match'range => '0') else '0';

end architecture rtl;
