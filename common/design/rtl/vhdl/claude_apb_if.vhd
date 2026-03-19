-- claude_apb_if.vhd — APB4 bus-to-regfile bridge (shared Claude IP component, VHDL-2008).
--
-- Translates APB4 transactions into the flat register-file access bus.
-- Port-for-port equivalent to claude_apb_if.sv.
-- This entity is protocol-generic and contains no IP-specific logic.
-- It is shared across all Claude IP blocks that expose an APB4 slave port.
--
-- Protocol notes:
--   SETUP phase : PSEL asserted, PENABLE deasserted.
--   ACCESS phase: PSEL and PENABLE both asserted.
--   Zero wait-states: PREADY is always asserted.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity claude_apb_if is
  generic (
    DATA_W : positive := 32; -- data bus width
    ADDR_W : positive := 4   -- regfile word-address width
  );
  port (
    -- APB4 bus signals
    PCLK    : in  std_ulogic;                                   -- APB clock
    PRESETn : in  std_ulogic;                                   -- APB active-low reset
    PSEL    : in  std_ulogic;                                   -- slave select
    PENABLE : in  std_ulogic;                                   -- enable (ACCESS phase)
    PADDR   : in  std_ulogic_vector(11 downto 0);               -- byte address
    PWRITE  : in  std_ulogic;                                   -- 1=write
    PWDATA  : in  std_ulogic_vector(DATA_W - 1 downto 0);       -- write data
    PSTRB   : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0);  -- byte enables
    PRDATA  : out std_ulogic_vector(DATA_W - 1 downto 0);       -- read data
    PREADY  : out std_ulogic;                                   -- always ready
    PSLVERR : out std_ulogic;                                   -- always OKAY

    -- Register-file write channel
    wr_en   : out std_ulogic;                                   -- write enable
    wr_addr : out std_ulogic_vector(ADDR_W - 1 downto 0);      -- word address
    wr_data : out std_ulogic_vector(DATA_W - 1 downto 0);      -- write data
    wr_strb : out std_ulogic_vector(DATA_W / 8 - 1 downto 0);  -- byte enables

    -- Register-file read channel
    rd_en   : out std_ulogic;                                   -- read enable
    rd_addr : out std_ulogic_vector(ADDR_W - 1 downto 0);      -- word address
    rd_data : in  std_ulogic_vector(DATA_W - 1 downto 0)        -- read data
  );
end entity claude_apb_if;

architecture rtl of claude_apb_if is
begin

  -- -------------------------------------------------------------------------
  -- Write path: full ACCESS phase, write direction
  -- -------------------------------------------------------------------------
  wr_en   <= PSEL and PENABLE and PWRITE;
  wr_addr <= PADDR(ADDR_W + 1 downto 2);
  wr_data <= PWDATA;
  wr_strb <= PSTRB;

  -- -------------------------------------------------------------------------
  -- Read path: issue rd_en in SETUP phase so registered read data is ready
  -- during ACCESS phase when PRDATA must be valid.
  -- -------------------------------------------------------------------------
  rd_en   <= PSEL and (not PENABLE) and (not PWRITE);
  rd_addr <= PADDR(ADDR_W + 1 downto 2);
  PRDATA  <= rd_data;

  -- -------------------------------------------------------------------------
  -- APB handshake: zero wait-states, no error
  -- -------------------------------------------------------------------------
  PREADY  <= '1';
  PSLVERR <= '0';

end architecture rtl;
