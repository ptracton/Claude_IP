-- sram_macro_dp_generic.vhd — Behavioral two-port RAM wrapper (TECH_GENERIC, DUAL_PORT).
--
-- VHDL-2008 twin of sram_macro_dp_generic.sv: W x D true dual-port RAM, each
-- port on its own clock (a_clk / b_clk; one clock when the core uses
-- COMMON_CLK), per-lane writes and a one-cycle registered read on each port,
-- in the FPGA tools' dual-clock true dual-port template; nothing is tiled.
-- Same-word collisions with separate clocks are undefined. INIT_FILE (hex)
-- preloads. Simulation only: a rising sd_i (sampled on a_clk) turns every
-- word into 'X'.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.sram_pkg.all;

entity sram_macro_dp_generic is
  generic (
    W         : positive := 32;   -- word width
    D         : positive := 1024; -- words (power of two)
    NLANES    : positive := 4;    -- write lanes of W / NLANES bits
    INIT_FILE : string   := ""    -- optional preload
  );
  port (
    a_clk       : in  std_ulogic;                               -- port A clock
    a_cs_i      : in  std_ulogic;                               -- port A chip select
    a_we_i      : in  std_ulogic;                               -- port A 1 = write
    a_addr_i    : in  std_ulogic_vector(clog2(D) - 1 downto 0); -- port A word address
    a_wdata_i   : in  std_ulogic_vector(W - 1 downto 0);        -- port A write data
    a_lane_we_i : in  std_ulogic_vector(NLANES - 1 downto 0);   -- port A lanes to write
    a_rdata_o   : out std_ulogic_vector(W - 1 downto 0);        -- port A read data
    b_clk       : in  std_ulogic;                               -- port B clock
    b_cs_i      : in  std_ulogic;                               -- port B chip select
    b_we_i      : in  std_ulogic;                               -- port B 1 = write
    b_addr_i    : in  std_ulogic_vector(clog2(D) - 1 downto 0); -- port B word address
    b_wdata_i   : in  std_ulogic_vector(W - 1 downto 0);        -- port B write data
    b_lane_we_i : in  std_ulogic_vector(NLANES - 1 downto 0);   -- port B lanes to write
    b_rdata_o   : out std_ulogic_vector(W - 1 downto 0);        -- port B read data
    ls_i        : in  std_ulogic;                               -- light sleep
    ds_i        : in  std_ulogic;                               -- deep sleep
    sd_i        : in  std_ulogic                                -- shutdown
  );
end entity sram_macro_dp_generic;

architecture rtl of sram_macro_dp_generic is

  constant LANE_W_C : positive := W / NLANES;

  type mem_t is array (0 to D - 1) of std_ulogic_vector(W - 1 downto 0);

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

  -- Deviation: shared variable of an ordinary type (the dual-clock true
  -- dual-port RAM template of the FPGA tools). Both ports write the array
  -- from their own clocks; a signal cannot have two drivers.
  shared variable mem : mem_t := init_mem;

  signal a_rdata : std_ulogic_vector(W - 1 downto 0);
  signal b_rdata : std_ulogic_vector(W - 1 downto 0);
  signal sd_q    : std_ulogic := '0';  -- sd_i last a_clk cycle (simulation only)

begin

  -- Port A: lane writes and registered read.
  p_port_a : process (a_clk) is
    variable word : std_ulogic_vector(W - 1 downto 0);
  begin
    if rising_edge(a_clk) then
      if a_cs_i = '1' then
        if a_we_i = '1' then
          word := mem(to_integer(unsigned(a_addr_i)));
          for l in 0 to NLANES - 1 loop
            if a_lane_we_i(l) = '1' then
              word(LANE_W_C * (l + 1) - 1 downto LANE_W_C * l) :=
                  a_wdata_i(LANE_W_C * (l + 1) - 1 downto LANE_W_C * l);
            end if;
          end loop;
          mem(to_integer(unsigned(a_addr_i))) := word;
        else
          a_rdata <= mem(to_integer(unsigned(a_addr_i)));
        end if;
      end if;
      sd_q <= sd_i;
      -- pragma translate_off
      -- Deviation: 'X' assignment, simulation only — models loss of contents.
      if sd_i = '1' and sd_q = '0' then
        mem := (others => (others => 'X'));
      end if;
      -- pragma translate_on
    end if;
  end process p_port_a;

  -- Port B: lane writes and registered read.
  p_port_b : process (b_clk) is
    variable word : std_ulogic_vector(W - 1 downto 0);
  begin
    if rising_edge(b_clk) then
      if b_cs_i = '1' then
        if b_we_i = '1' then
          word := mem(to_integer(unsigned(b_addr_i)));
          for l in 0 to NLANES - 1 loop
            if b_lane_we_i(l) = '1' then
              word(LANE_W_C * (l + 1) - 1 downto LANE_W_C * l) :=
                  b_wdata_i(LANE_W_C * (l + 1) - 1 downto LANE_W_C * l);
            end if;
          end loop;
          mem(to_integer(unsigned(b_addr_i))) := word;
        else
          b_rdata <= mem(to_integer(unsigned(b_addr_i)));
        end if;
      end if;
    end if;
  end process p_port_b;

  a_rdata_o <= a_rdata;
  b_rdata_o <= b_rdata;

end architecture rtl;
