-- bus_matrix_decoder.vhd — Bus Matrix address decoder (VHDL-2008).
--
-- Decodes an address to a one-hot slave selection using base+mask scheme.
-- Match condition: (addr & mask) == (base & mask)
-- Address map is fully static via generics. Combinational logic only.
-- Mirrors bus_matrix_decoder.sv.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bus_matrix_decoder is
  generic (
    NUM_SLAVES : positive := 2;  -- 1-32 active slaves
    ADDR_W     : positive := 32; -- address width
    -- Flat-packed address map: slave j at bits [(j+1)*32-1 : j*32]
    -- Maximum 32 slaves = 1024 bits. Only NUM_SLAVES entries used.
    S_BASE     : std_ulogic_vector(32*32-1 downto 0) := (others => '0');
    S_MASK     : std_ulogic_vector(32*32-1 downto 0) := (others => '0')
  );
  port (
    addr       : in  std_ulogic_vector(ADDR_W - 1 downto 0);
    slave_sel  : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    decode_err : out std_ulogic
  );
end entity bus_matrix_decoder;

architecture rtl of bus_matrix_decoder is
  signal match_v : std_ulogic_vector(NUM_SLAVES - 1 downto 0);
begin

  -- Generate match flags for each active slave (use process to re-index slices)
  p_match : process(addr) is
    variable base_j : std_ulogic_vector(31 downto 0);
    variable mask_j : std_ulogic_vector(31 downto 0);
  begin
    for j in 0 to NUM_SLAVES - 1 loop
      base_j := S_BASE((j+1)*32-1 downto j*32);
      mask_j := S_MASK((j+1)*32-1 downto j*32);
      if (addr and mask_j(ADDR_W-1 downto 0)) = (base_j(ADDR_W-1 downto 0) and mask_j(ADDR_W-1 downto 0)) then
        match_v(j) <= '1';
      else
        match_v(j) <= '0';
      end if;
    end loop;
  end process p_match;

  -- Priority encoder: lowest-numbered matching slave wins
  p_priority_encode : process(match_v) is
    variable result : std_ulogic_vector(NUM_SLAVES - 1 downto 0);
    variable found  : boolean;
  begin
    result := (others => '0');
    found  := false;
    for j in 0 to NUM_SLAVES - 1 loop
      if match_v(j) = '1' and not found then
        result(j) := '1';
        found     := true;
      end if;
    end loop;
    slave_sel <= result;
  end process p_priority_encode;

  decode_err <= '1' when slave_sel = (slave_sel'range => '0') else '0';

end architecture rtl;
