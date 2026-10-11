-- bus_matrix_apb_ini.vhd — APB4 initiator adapter for one bus matrix slave port (VHDL-2008).
--
-- Acts as an APB4 master towards the external slave and runs exactly one
-- transfer for each core request:
--   SETUP  (PSEL=1, PENABLE=0) for one cycle, presented while idle and req is high,
--   ACCESS (PSEL=1, PENABLE=1) until PREADY; done pulses in that cycle.
-- PSTRB is zero on reads, as APB4 requires. Mirrors bus_matrix_apb_ini.sv.

library ieee;
use ieee.std_logic_1164.all;

entity bus_matrix_apb_ini is
  generic (
    DATA_W : positive := 32;  -- data bus width
    ADDR_W : positive := 32   -- address width
  );
  port (
    clk     : in  std_ulogic; -- system clock
    rst_n   : in  std_ulogic; -- synchronous active-low reset

    -- Core handshake
    core_req     : in  std_ulogic;                                 -- run one transaction
    core_addr    : in  std_ulogic_vector(ADDR_W - 1 downto 0);     -- byte address
    core_wdata   : in  std_ulogic_vector(DATA_W - 1 downto 0);     -- write data
    core_we      : in  std_ulogic;                                 -- 1 = write
    core_be      : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0); -- byte enables
    core_done    : out std_ulogic;                                 -- one-cycle completion
    core_rdata   : out std_ulogic_vector(DATA_W - 1 downto 0);     -- read data (valid with done)
    core_err     : out std_ulogic;                                 -- error (valid with done)

    -- APB4 master interface (towards the external slave)
    PSEL    : out std_ulogic;                                 -- slave select
    PENABLE : out std_ulogic;                                 -- ACCESS phase
    PADDR   : out std_ulogic_vector(ADDR_W - 1 downto 0);     -- byte address
    PWRITE  : out std_ulogic;                                 -- 1 = write
    PWDATA  : out std_ulogic_vector(DATA_W - 1 downto 0);     -- write data
    PSTRB   : out std_ulogic_vector(DATA_W / 8 - 1 downto 0); -- byte strobes
    PRDATA  : in  std_ulogic_vector(DATA_W - 1 downto 0);     -- read data
    PREADY  : in  std_ulogic;                                 -- transfer done
    PSLVERR : in  std_ulogic                                  -- 1 = error
  );
end entity bus_matrix_apb_ini;

architecture rtl of bus_matrix_apb_ini is

  signal access_q : std_ulogic;  -- ACCESS phase in progress

begin

  p_access : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        access_q <= '0';
      elsif access_q = '1' then
        access_q <= not PREADY;
      else
        access_q <= core_req;
      end if;
    end if;
  end process p_access;

  PSEL    <= core_req or access_q;
  PENABLE <= access_q;
  PADDR   <= core_addr;
  PWRITE  <= core_we;
  PWDATA  <= core_wdata;
  PSTRB   <= core_be when core_we = '1' else (others => '0');

  core_done  <= access_q and PREADY;
  core_rdata <= PRDATA;
  core_err   <= PSLVERR;

end architecture rtl;
