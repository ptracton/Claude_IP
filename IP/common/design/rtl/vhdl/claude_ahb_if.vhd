-- claude_ahb_if.vhd — AHB-Lite bus-to-regfile bridge (shared Claude IP component).
--
-- Translates AHB-Lite transactions into the flat register-file access bus.
-- This module is protocol-generic and contains no IP-specific logic.
-- It is shared across all Claude IP blocks that expose an AHB-Lite slave port.
--
-- Protocol notes:
--   Two-phase pipeline: address phase then data phase.
--   HREADY is always asserted (zero wait-states).
--   HRESP is always OKAY (no error response).
--   Only HTRANS == NONSEQ (2'b10) initiates a transfer.
--   HSEL qualifies all transactions.
--
-- Generics:
--   DATA_W : data bus width             (default 32)
--   ADDR_W : regfile word-address width (default 4)

library ieee;
use ieee.std_logic_1164.all;

entity claude_ahb_if is
  generic (
    DATA_W : positive := 32;
    ADDR_W : positive := 4
  );
  port (
    -- AHB-Lite bus signals
    HCLK    : in  std_ulogic;
    HRESETn : in  std_ulogic;
    HSEL    : in  std_ulogic;
    HADDR   : in  std_ulogic_vector(11 downto 0);
    HTRANS  : in  std_ulogic_vector(1 downto 0);
    HWRITE  : in  std_ulogic;
    HWDATA  : in  std_ulogic_vector(DATA_W - 1 downto 0);
    HWSTRB  : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0);
    HRDATA  : out std_ulogic_vector(DATA_W - 1 downto 0);
    HREADY  : out std_ulogic;
    HRESP   : out std_ulogic;

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
end entity claude_ahb_if;

architecture rtl of claude_ahb_if is

  -- AHB HTRANS encoding: NONSEQ = "10"
  constant AHB_TRANS_NONSEQ : std_ulogic_vector(1 downto 0) := "10";

  -- Address-phase pipeline registers
  signal dphase_valid_q : std_ulogic;
  signal dphase_write_q : std_ulogic;
  signal dphase_addr_q  : std_ulogic_vector(ADDR_W - 1 downto 0);

begin

  -- -------------------------------------------------------------------------
  -- Address phase: latch when a valid NONSEQ transfer is selected
  -- -------------------------------------------------------------------------
  p_addr_phase : process (HCLK) is
  begin
    if rising_edge(HCLK) then
      if HRESETn = '0' then
        dphase_valid_q <= '0';
        dphase_write_q <= '0';
        dphase_addr_q  <= (others => '0');
      else
        if HSEL = '1' and HTRANS = AHB_TRANS_NONSEQ and HREADY = '1' then
          dphase_valid_q <= '1';
          dphase_write_q <= HWRITE;
          dphase_addr_q  <= HADDR(ADDR_W + 1 downto 2);
        else
          dphase_valid_q <= '0';
        end if;
      end if;
    end if;
  end process p_addr_phase;

  -- Write channel: drive regfile signals during data phase
  wr_en   <= dphase_valid_q and dphase_write_q;
  wr_addr <= dphase_addr_q;
  wr_data <= HWDATA;
  wr_strb <= HWSTRB;

  -- Read channel
  rd_en   <= dphase_valid_q and (not dphase_write_q);
  rd_addr <= dphase_addr_q;
  HRDATA  <= rd_data;

  -- AHB handshake: zero wait-states, always OKAY
  HREADY <= '1';
  HRESP  <= '0';

end architecture rtl;
