-- claude_apb_if.vhd — APB4 bus-to-regfile bridge (shared Claude IP component).
--
-- Translates APB4 transactions into the flat register-file access bus.
-- This module is protocol-generic and contains no IP-specific logic.
-- It is shared across all Claude IP blocks that expose an APB4 slave port.
--
-- APB4 protocol:
--   SETUP phase : PSEL asserted, PENABLE deasserted.
--   ACCESS phase: PSEL and PENABLE both asserted.
--   Transfer completes when PENABLE is asserted and PREADY is sampled high.
--
-- This implementation asserts PREADY in the same cycle as PENABLE (zero
-- wait-states).  Write and read enables are generated only during ACCESS phase.
--
-- Generics:
--   DATA_W : data bus width             (default 32)
--   ADDR_W : regfile word-address width (default 4)

library ieee;
use ieee.std_logic_1164.all;

entity claude_apb_if is
  generic (
    DATA_W : positive := 32;
    ADDR_W : positive := 4
  );
  port (
    -- APB4 bus signals (PCLK/PRESETn are routed to regfile/core above this module)
    PCLK    : in  std_ulogic;
    PRESETn : in  std_ulogic;
    PSEL    : in  std_ulogic;
    PENABLE : in  std_ulogic;
    PADDR   : in  std_ulogic_vector(11 downto 0);
    PWRITE  : in  std_ulogic;
    PWDATA  : in  std_ulogic_vector(DATA_W - 1 downto 0);
    PSTRB   : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0);
    PRDATA  : out std_ulogic_vector(DATA_W - 1 downto 0);
    PREADY  : out std_ulogic;
    PSLVERR : out std_ulogic;

    -- Register-file write channel
    wr_en   : out std_ulogic;
    wr_addr : out std_ulogic_vector(ADDR_W - 1 downto 0);
    wr_data : out std_ulogic_vector(DATA_W - 1 downto 0);
    wr_strb : out std_ulogic_vector(DATA_W / 8 - 1 downto 0);

    -- Register-file read channel
    rd_en   : out std_ulogic;
    rd_addr : out std_ulogic_vector(ADDR_W - 1 downto 0);
    rd_data : in  std_ulogic_vector(DATA_W - 1 downto 0)
  );
end entity claude_apb_if;

architecture rtl of claude_apb_if is
begin

  -- Write path: full access phase, write direction
  wr_en   <= PSEL and PENABLE and PWRITE;
  wr_addr <= PADDR(ADDR_W + 1 downto 2);
  wr_data <= PWDATA;
  wr_strb <= PSTRB;

  -- Read path: issue rd_en in SETUP phase so regfile registered read data is
  -- stable during ACCESS phase when PRDATA must be valid.
  rd_en   <= PSEL and (not PENABLE) and (not PWRITE);
  rd_addr <= PADDR(ADDR_W + 1 downto 2);
  PRDATA  <= rd_data;

  -- APB handshake: zero wait-states, no error
  PREADY  <= '1';
  PSLVERR <= '0';

  -- Suppress unused-port warnings: PCLK and PRESETn are routed above this module
  -- pragma translate_off
  -- pragma translate_on

end architecture rtl;
