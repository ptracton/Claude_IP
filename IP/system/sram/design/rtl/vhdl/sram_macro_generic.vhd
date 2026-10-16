-- sram_macro_generic.vhd — Behavioral single-port RAM tile (TECH_GENERIC).
--
-- VHDL-2008 twin of sram_macro_generic.sv: synchronous single-port RAM with
-- per-byte write enables and a one-cycle registered read (rdata_o valid in
-- the cycle after a read, held until the next read), written so FPGA tools
-- infer block RAM. INIT_FILE (hex, one word per line, $readmemh layout)
-- preloads the contents at elaboration.
-- Simulation only: a rising sd_i (shutdown) turns every word into 'X'.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.sram_pkg.all;

entity sram_macro_generic is
  generic (
    MAC_W     : positive := 32;   -- word width (multiple of 8)
    MAC_D     : positive := 1024; -- words
    INIT_FILE : string   := ""    -- optional hex preload
  );
  port (
    clk     : in  std_ulogic;                                   -- clock
    cs_i    : in  std_ulogic;                                   -- chip select
    we_i    : in  std_ulogic;                                   -- 1 = write, 0 = read
    addr_i  : in  std_ulogic_vector(clog2(MAC_D) - 1 downto 0); -- word address
    wdata_i : in  std_ulogic_vector(MAC_W - 1 downto 0);        -- write data
    wbe_i   : in  std_ulogic_vector(MAC_W / 8 - 1 downto 0);    -- byte write enables
    ls_i    : in  std_ulogic;                                   -- light sleep (retention)
    ds_i    : in  std_ulogic;                                   -- deep sleep (retention)
    sd_i    : in  std_ulogic;                                   -- shutdown
    rdata_o : out std_ulogic_vector(MAC_W - 1 downto 0)         -- read data
  );
end entity sram_macro_generic;

architecture rtl of sram_macro_generic is

  type mem_t is array (0 to MAC_D - 1) of std_ulogic_vector(MAC_W - 1 downto 0);

  -- Preload from INIT_FILE (elaboration time); uninitialised otherwise.
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

  signal mem   : mem_t := init_mem;
  signal rdata : std_ulogic_vector(MAC_W - 1 downto 0);
  signal sd_q  : std_ulogic := '0'; -- sd_i last cycle (edge detect, simulation only)

begin

  -- Synchronous write (per byte) and registered read.
  p_ram : process (clk) is
  begin
    if rising_edge(clk) then
      if cs_i = '1' then
        if we_i = '1' then
          for b in 0 to MAC_W / 8 - 1 loop
            if wbe_i(b) = '1' then
              mem(to_integer(unsigned(addr_i)))(8 * b + 7 downto 8 * b) <=
                  wdata_i(8 * b + 7 downto 8 * b);
            end if;
          end loop;
        else
          rdata <= mem(to_integer(unsigned(addr_i)));
        end if;
      end if;
      sd_q <= sd_i;
      -- pragma translate_off
      -- Deviation: 'X' assignment, simulation only — models loss of contents
      -- when the tile is shut down (power switched off).
      if sd_i = '1' and sd_q = '0' then
        mem <= (others => (others => 'X'));
      end if;
      -- pragma translate_on
    end if;
  end process p_ram;

  rdata_o <= rdata;

end architecture rtl;
