-- claude_wb_if.vhd — Wishbone B4 bus-to-regfile bridge (shared Claude IP component).
--
-- Translates Wishbone B4 (registered feedback) transactions into the flat
-- register-file access bus.
-- This module is protocol-generic and contains no IP-specific logic.
-- It is shared across all Claude IP blocks that expose a Wishbone B4 slave port.
--
-- Wishbone B4 protocol (registered feedback / pipelined variant):
--   A transaction is valid when CYC_I & STB_I are asserted.
--   ACK_O is asserted the cycle after STB_I (single-cycle latency).
--   ERR_O is never asserted.
--
-- Generics:
--   DATA_W : data bus width             (default 32)
--   ADDR_W : regfile word-address width (default 4)

library ieee;
use ieee.std_logic_1164.all;

entity claude_wb_if is
  generic (
    DATA_W : positive := 32;
    ADDR_W : positive := 4
  );
  port (
    -- Wishbone B4 signals
    CLK_I   : in  std_ulogic;
    RST_I   : in  std_ulogic;   -- synchronous active-high reset
    CYC_I   : in  std_ulogic;
    STB_I   : in  std_ulogic;
    WE_I    : in  std_ulogic;
    ADR_I   : in  std_ulogic_vector(11 downto 0);
    DAT_I   : in  std_ulogic_vector(DATA_W - 1 downto 0);
    SEL_I   : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0);
    DAT_O   : out std_ulogic_vector(DATA_W - 1 downto 0);
    ACK_O   : out std_ulogic;
    ERR_O   : out std_ulogic;

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
end entity claude_wb_if;

architecture rtl of claude_wb_if is

  signal stb_prev_q : std_ulogic;

begin

  -- -------------------------------------------------------------------------
  -- Capture STB to generate one-cycle ACK and rd_en/wr_en pulses
  -- -------------------------------------------------------------------------
  p_ack : process (CLK_I) is
  begin
    if rising_edge(CLK_I) then
      if RST_I = '1' then
        stb_prev_q <= '0';
      else
        stb_prev_q <= CYC_I and STB_I and (not stb_prev_q);
      end if;
    end if;
  end process p_ack;

  -- wr_en / rd_en fire in the cycle when STB_I is first seen
  wr_en   <= CYC_I and STB_I and WE_I         and (not stb_prev_q);
  rd_en   <= CYC_I and STB_I and (not WE_I)   and (not stb_prev_q);
  wr_addr <= ADR_I(ADDR_W + 1 downto 2);
  rd_addr <= ADR_I(ADDR_W + 1 downto 2);
  wr_data <= DAT_I;
  wr_strb <= SEL_I;

  -- -------------------------------------------------------------------------
  -- ACK_O: registered one cycle after wr_en/rd_en
  -- -------------------------------------------------------------------------
  p_ack_out : process (CLK_I) is
  begin
    if rising_edge(CLK_I) then
      if RST_I = '1' then
        ACK_O <= '0';
      else
        ACK_O <= CYC_I and STB_I and (not stb_prev_q);
      end if;
    end if;
  end process p_ack_out;

  DAT_O <= rd_data;
  ERR_O <= '0';

end architecture rtl;
