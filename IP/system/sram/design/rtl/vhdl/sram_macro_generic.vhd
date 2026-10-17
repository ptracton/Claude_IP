-- sram_macro_generic.vhd — Behavioral single-port RAM wrapper (TECH_GENERIC).
--
-- VHDL-2008 twin of sram_macro_generic.sv: synchronous W x D single-port RAM
-- (not tiled; the tool builds it from block RAMs) with per-lane write
-- enables and a one-cycle registered read (rdata_o valid in
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
    W         : positive := 32;   -- word width
    D         : positive := 1024; -- words (power of two)
    NLANES    : positive := 4;    -- write lanes of W / NLANES bits
    INIT_FILE : string   := ""    -- optional hex preload
  );
  port (
    clk       : in  std_ulogic;                               -- clock
    cs_i      : in  std_ulogic;                               -- chip select
    we_i      : in  std_ulogic;                               -- 1 = write, 0 = read
    addr_i    : in  std_ulogic_vector(clog2(D) - 1 downto 0); -- word address
    wdata_i   : in  std_ulogic_vector(W - 1 downto 0);        -- write data
    lane_we_i : in  std_ulogic_vector(NLANES - 1 downto 0);   -- lanes to write
    ls_i      : in  std_ulogic;                               -- light sleep (retention)
    ds_i      : in  std_ulogic;                               -- deep sleep (retention)
    sd_i      : in  std_ulogic;                               -- shutdown
    rdata_o   : out std_ulogic_vector(W - 1 downto 0)         -- read data
  );
end entity sram_macro_generic;

architecture rtl of sram_macro_generic is

  constant LANE_W_C : positive := W / NLANES;

  type mem_t is array (0 to D - 1) of std_ulogic_vector(W - 1 downto 0);

  -- Preload from INIT_FILE (elaboration time); uninitialised otherwise.
  impure function init_mem return mem_t is
    file     f    : text;
    variable l    : line;
    variable word : std_ulogic_vector(W - 1 downto 0);
    variable m    : mem_t := (others => (others => 'U'));
  begin
    if INIT_FILE /= "" then
      file_open(f, INIT_FILE, read_mode);
      for i in 0 to D - 1 loop
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
  signal rdata : std_ulogic_vector(W - 1 downto 0);
  signal sd_q  : std_ulogic := '0'; -- sd_i last cycle (edge detect, simulation only)

begin

  -- Synchronous write (per lane) and registered read.
  p_ram : process (clk) is
  begin
    if rising_edge(clk) then
      if cs_i = '1' then
        if we_i = '1' then
          for l in 0 to NLANES - 1 loop
            if lane_we_i(l) = '1' then
              mem(to_integer(unsigned(addr_i)))(LANE_W_C * (l + 1) - 1 downto LANE_W_C * l) <=
                  wdata_i(LANE_W_C * (l + 1) - 1 downto LANE_W_C * l);
            end if;
          end loop;
        else
          rdata <= mem(to_integer(unsigned(addr_i)));
        end if;
      end if;
      sd_q <= sd_i;
      -- pragma translate_off
      -- Deviation: 'X' assignment, simulation only — models loss of contents
      -- when the memory is shut down (power switched off).
      if sd_i = '1' and sd_q = '0' then
        mem <= (others => (others => 'X'));
      end if;
      -- pragma translate_on
    end if;
  end process p_ram;

  rdata_o <= rdata;

end architecture rtl;
