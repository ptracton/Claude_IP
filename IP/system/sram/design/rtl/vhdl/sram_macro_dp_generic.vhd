-- sram_macro_dp_generic.vhd — Behavioral two-port RAM tile (TECH_GENERIC, DUAL_PORT).
--
-- VHDL-2008 twin of sram_macro_dp_generic.sv: true dual-port RAM on one clock,
-- per-byte writes and a one-cycle registered read on each port, written so
-- FPGA tools infer a true dual-port block RAM. INIT_FILE (hex) preloads.
-- Simulation only: a rising sd_i turns every word into 'X'.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.sram_pkg.all;

entity sram_macro_dp_generic is
  generic (
    MAC_W     : positive := 32;    -- word width (multiple of 8)
    MAC_D     : positive := 1024;  -- words
    INIT_FILE : string   := ""     -- optional preload
  );
  port (
    clk       : in  std_ulogic;                                    -- clock (both ports)
    a_cs_i    : in  std_ulogic;                                    -- port A chip select
    a_we_i    : in  std_ulogic;                                    -- port A 1 = write
    a_addr_i  : in  std_ulogic_vector(clog2(MAC_D) - 1 downto 0);  -- port A word address
    a_wdata_i : in  std_ulogic_vector(MAC_W - 1 downto 0);         -- port A write data
    a_wbe_i   : in  std_ulogic_vector(MAC_W / 8 - 1 downto 0);     -- port A byte write enables
    a_rdata_o : out std_ulogic_vector(MAC_W - 1 downto 0);         -- port A read data
    b_cs_i    : in  std_ulogic;                                    -- port B chip select
    b_we_i    : in  std_ulogic;                                    -- port B 1 = write
    b_addr_i  : in  std_ulogic_vector(clog2(MAC_D) - 1 downto 0);  -- port B word address
    b_wdata_i : in  std_ulogic_vector(MAC_W - 1 downto 0);         -- port B write data
    b_wbe_i   : in  std_ulogic_vector(MAC_W / 8 - 1 downto 0);     -- port B byte write enables
    b_rdata_o : out std_ulogic_vector(MAC_W - 1 downto 0);         -- port B read data
    ls_i      : in  std_ulogic;                                    -- light sleep
    ds_i      : in  std_ulogic;                                    -- deep sleep
    sd_i      : in  std_ulogic                                     -- shutdown
  );
end entity sram_macro_dp_generic;

architecture rtl of sram_macro_dp_generic is

  type mem_t is array (0 to MAC_D - 1) of std_ulogic_vector(MAC_W - 1 downto 0);

  impure function init_mem return mem_t is
    file     f    : text;
    variable l    : line;
    variable word : std_ulogic_vector(MAC_W - 1 downto 0);
    variable m    : mem_t := (others => (others => 'U'));
  begin
    if INIT_FILE /= "" then
      file_open(f, INIT_FILE, read_mode);
      for i in 0 to MAC_D - 1 loop
        exit when endfile(f);
        readline(f, l);
        hread(l, word);
        m(i) := word;
      end loop;
      file_close(f);
    end if;
    return m;
  end function init_mem;

  signal mem     : mem_t := init_mem;
  signal a_rdata : std_ulogic_vector(MAC_W - 1 downto 0);
  signal b_rdata : std_ulogic_vector(MAC_W - 1 downto 0);
  signal sd_q    : std_ulogic := '0';  -- sd_i last cycle (simulation only)

begin

  -- Both ports' writes and registered reads (one process: one array driver).
  p_ram : process (clk) is
  begin
    if rising_edge(clk) then
      if a_cs_i = '1' then
        if a_we_i = '1' then
          for b in 0 to MAC_W / 8 - 1 loop
            if a_wbe_i(b) = '1' then
              mem(to_integer(unsigned(a_addr_i)))(8 * b + 7 downto 8 * b) <=
                  a_wdata_i(8 * b + 7 downto 8 * b);
            end if;
          end loop;
        else
          a_rdata <= mem(to_integer(unsigned(a_addr_i)));
        end if;
      end if;
      if b_cs_i = '1' then
        if b_we_i = '1' then
          for b in 0 to MAC_W / 8 - 1 loop
            if b_wbe_i(b) = '1' then
              mem(to_integer(unsigned(b_addr_i)))(8 * b + 7 downto 8 * b) <=
                  b_wdata_i(8 * b + 7 downto 8 * b);
            end if;
          end loop;
        else
          b_rdata <= mem(to_integer(unsigned(b_addr_i)));
        end if;
      end if;
      sd_q <= sd_i;
      -- pragma translate_off
      -- Deviation: 'X' assignment, simulation only — models loss of contents.
      if sd_i = '1' and sd_q = '0' then
        mem <= (others => (others => 'X'));
      end if;
      -- pragma translate_on
    end if;
  end process p_ram;

  a_rdata_o <= a_rdata;
  b_rdata_o <= b_rdata;

end architecture rtl;
