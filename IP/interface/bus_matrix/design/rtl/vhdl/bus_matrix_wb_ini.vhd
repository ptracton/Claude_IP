-- bus_matrix_wb_ini.vhd — Wishbone B4 (classic) initiator adapter for one bus matrix slave port (VHDL-2008).
--
-- Acts as a Wishbone master towards the external slave. CYC and STB follow
-- the core request, which is held until the slave answers with ACK or ERR
-- and dropped on the following cycle, so each grant is exactly one classic
-- single read or write.
--
-- Purely combinational. Mirrors bus_matrix_wb_ini.sv.

library ieee;
use ieee.std_logic_1164.all;

entity bus_matrix_wb_ini is
  generic (
    DATA_W : positive := 32;  -- data bus width
    ADDR_W : positive := 32   -- address width
  );
  port (
    -- Core handshake
    core_req   : in  std_ulogic;                                 -- run one transaction
    core_addr  : in  std_ulogic_vector(ADDR_W - 1 downto 0);     -- byte address
    core_wdata : in  std_ulogic_vector(DATA_W - 1 downto 0);     -- write data
    core_we    : in  std_ulogic;                                 -- 1 = write
    core_be    : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0); -- byte enables
    core_done  : out std_ulogic;                                 -- one-cycle completion
    core_rdata : out std_ulogic_vector(DATA_W - 1 downto 0);     -- read data (valid with done)
    core_err   : out std_ulogic;                                 -- error (valid with done)

    -- Wishbone master interface (towards the external slave)
    CYC   : out std_ulogic;                                 -- bus cycle
    STB   : out std_ulogic;                                 -- strobe
    WE    : out std_ulogic;                                 -- 1 = write
    ADR   : out std_ulogic_vector(ADDR_W - 1 downto 0);     -- byte address
    DAT_W : out std_ulogic_vector(DATA_W - 1 downto 0);     -- write data (matrix -> slave)
    SEL   : out std_ulogic_vector(DATA_W / 8 - 1 downto 0); -- byte selects
    DAT_R : in  std_ulogic_vector(DATA_W - 1 downto 0);     -- read data (slave -> matrix)
    ACK   : in  std_ulogic;                                 -- normal termination
    ERR   : in  std_ulogic                                  -- error termination
  );
end entity bus_matrix_wb_ini;

architecture rtl of bus_matrix_wb_ini is
begin

  CYC   <= core_req;
  STB   <= core_req;
  WE    <= core_we;
  ADR   <= core_addr;
  DAT_W <= core_wdata;
  SEL   <= core_be;

  core_done  <= core_req and (ACK or ERR);
  core_err   <= ERR;
  core_rdata <= DAT_R;

end architecture rtl;
