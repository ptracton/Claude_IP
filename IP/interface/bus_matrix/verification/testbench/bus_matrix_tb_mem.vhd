-- bus_matrix_tb_mem.vhd — Testbench memory behind a shared claude_<proto>_if bridge (VHDL-2008).
--
-- Implements the bridge's register-file side (wr_en/wr_addr/wr_data/wr_strb,
-- rd_en/rd_addr/rd_data with registered read data) as a 2**ADDR_W-word RAM,
-- so each bus matrix slave port is terminated by a protocol-compliant slave.
--
-- For arbitration tests it counts writes (wr_count) and records the word
-- addresses of the first two (wr_log0, wr_log1); log_clear restarts the log.
-- Mirrors bus_matrix_tb_mem.sv.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bus_matrix_tb_mem is
  generic (
    ADDR_W : positive := 10  -- word-address width (2**ADDR_W words)
  );
  port (
    clk       : in  std_ulogic;
    wr_en     : in  std_ulogic;
    wr_addr   : in  std_ulogic_vector(ADDR_W - 1 downto 0);
    wr_data   : in  std_ulogic_vector(31 downto 0);
    wr_strb   : in  std_ulogic_vector(3 downto 0);
    rd_en     : in  std_ulogic;
    rd_addr   : in  std_ulogic_vector(ADDR_W - 1 downto 0);
    rd_data   : out std_ulogic_vector(31 downto 0);
    log_clear : in  std_ulogic;
    wr_count  : out natural;
    wr_log0   : out std_ulogic_vector(ADDR_W - 1 downto 0);
    wr_log1   : out std_ulogic_vector(ADDR_W - 1 downto 0)
  );
end entity bus_matrix_tb_mem;

architecture sim of bus_matrix_tb_mem is

  type mem_t is array (0 to 2 ** ADDR_W - 1) of std_ulogic_vector(31 downto 0);

begin

  p_mem : process (clk, log_clear) is
    variable mem   : mem_t := (others => (others => '0'));
    variable count : natural := 0;
    variable word  : std_ulogic_vector(31 downto 0);
  begin
    if log_clear = '1' then
      count    := 0;
      wr_count <= 0;
    elsif rising_edge(clk) then
      if wr_en = '1' then
        word := mem(to_integer(unsigned(wr_addr)));
        for b in 0 to 3 loop
          if wr_strb(b) = '1' then
            word(b * 8 + 7 downto b * 8) := wr_data(b * 8 + 7 downto b * 8);
          end if;
        end loop;
        mem(to_integer(unsigned(wr_addr))) := word;
        if count = 0 then
          wr_log0 <= wr_addr;
        elsif count = 1 then
          wr_log1 <= wr_addr;
        end if;
        count    := count + 1;
        wr_count <= count;
      end if;
      if rd_en = '1' then
        rd_data <= mem(to_integer(unsigned(rd_addr)));
      end if;
    end if;
  end process p_mem;

end architecture sim;
