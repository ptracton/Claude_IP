-- claude_wb_if.vhd — Wishbone B4 bus-to-regfile bridge (shared Claude IP component, VHDL-2008).
--
-- Translates Wishbone B4 transactions into the flat register-file access bus.
-- Port-for-port equivalent to claude_wb_if.sv.
-- This entity is protocol-generic and contains no IP-specific logic.
-- It is shared across all Claude IP blocks that expose a Wishbone B4 slave port.
--
-- Protocol notes:
--   A transaction is valid when CYC_I and STB_I are asserted.
--   ACK_O is asserted one cycle after a valid STB_I (single-cycle latency).
--   RST_I is synchronous active-high (Wishbone convention).
--   ERR_O is never asserted.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity claude_wb_if is
  generic (
    DATA_W : positive := 32; -- data bus width
    ADDR_W : positive := 4   -- regfile word-address width
  );
  port (
    CLK_I   : in  std_ulogic;
    RST_I   : in  std_ulogic;
    CYC_I   : in  std_ulogic;
    STB_I   : in  std_ulogic;
    WE_I    : in  std_ulogic;
    ADR_I   : in  std_ulogic_vector(11 downto 0);
    DAT_I   : in  std_ulogic_vector(DATA_W - 1 downto 0);
    SEL_I   : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0);
    DAT_O   : out std_ulogic_vector(DATA_W - 1 downto 0);
    ACK_O   : out std_ulogic;
    ERR_O   : out std_ulogic;

    wr_en   : out std_ulogic;
    wr_addr : out std_ulogic_vector(ADDR_W - 1 downto 0);
    wr_data : out std_ulogic_vector(DATA_W - 1 downto 0);
    wr_strb : out std_ulogic_vector(DATA_W / 8 - 1 downto 0);

    rd_en   : out std_ulogic;
    rd_addr : out std_ulogic_vector(ADDR_W - 1 downto 0);
    rd_data : in  std_ulogic_vector(DATA_W - 1 downto 0)
  );
end entity claude_wb_if;

architecture rtl of claude_wb_if is

  signal stb_prev_q : std_ulogic;
  signal stb_pulse  : std_ulogic;

begin

  p_ack : process(CLK_I) is
  begin
    if rising_edge(CLK_I) then
      if RST_I = '1' then
        stb_prev_q <= '0';
      else
        stb_prev_q <= CYC_I and STB_I and (not stb_prev_q);
      end if;
    end if;
  end process p_ack;

  stb_pulse <= CYC_I and STB_I and (not stb_prev_q);

  wr_en   <= stb_pulse and WE_I;
  rd_en   <= stb_pulse and (not WE_I);
  wr_addr <= ADR_I(ADDR_W + 1 downto 2);
  rd_addr <= ADR_I(ADDR_W + 1 downto 2);
  wr_data <= DAT_I;
  wr_strb <= SEL_I;

  p_ack_out : process(CLK_I) is
  begin
    if rising_edge(CLK_I) then
      if RST_I = '1' then
        ACK_O <= '0';
      else
        ACK_O <= stb_pulse;
      end if;
    end if;
  end process p_ack_out;

  DAT_O <= rd_data;
  ERR_O <= '0';

end architecture rtl;
