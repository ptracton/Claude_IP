-- claude_ahb_if.vhd — AHB-Lite bus-to-regfile bridge (shared Claude IP component).
--
-- Translates AHB-Lite transactions into the flat register-file access bus.
-- This module is protocol-generic and contains no IP-specific logic.
-- It is shared across all Claude IP blocks that expose an AHB-Lite slave port.
--
-- Protocol notes:
--   Two-phase pipeline: address phase then data phase.
--   Writes are zero-wait. Reads insert ONE wait state: the regfile read
--   data is registered (valid the cycle after rd_en), so the first
--   data-phase cycle of a read drives HREADY low and issues rd_en, and the
--   second drives HREADY high with HRDATA = rd_data. Issuing rd_en in the
--   data phase (not the address phase) also means a read that directly
--   follows a write to the same register returns the new value.
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
  signal rd_wait_q      : std_ulogic;  -- first data-phase cycle of a read
  signal hready_i       : std_ulogic;  -- internal copy of HREADY (read back)

begin

  -- -------------------------------------------------------------------------
  -- Address phase: sampled only when HREADY is high (a stalled data phase
  -- keeps its address-phase information; the master holds the next address
  -- phase until HREADY rises).
  -- -------------------------------------------------------------------------
  p_addr_phase : process (HCLK) is
  begin
    if rising_edge(HCLK) then
      if HRESETn = '0' then
        dphase_valid_q <= '0';
        dphase_write_q <= '0';
        dphase_addr_q  <= (others => '0');
        rd_wait_q      <= '0';
      else
        if hready_i = '1' then
          if HSEL = '1' and HTRANS = AHB_TRANS_NONSEQ then
            dphase_valid_q <= '1';
          else
            dphase_valid_q <= '0';
          end if;
          dphase_write_q <= HWRITE;
          dphase_addr_q  <= HADDR(ADDR_W + 1 downto 2);
        end if;
        -- Read wait state: set on an accepted read address phase, cleared
        -- after one cycle (HREADY is low while it is set).
        if hready_i = '1' and HSEL = '1' and HTRANS = AHB_TRANS_NONSEQ and
           HWRITE = '0' then
          rd_wait_q <= '1';
        else
          rd_wait_q <= '0';
        end if;
      end if;
    end if;
  end process p_addr_phase;

  -- Write channel: drive regfile signals during data phase
  wr_en   <= dphase_valid_q and dphase_write_q;
  wr_addr <= dphase_addr_q;
  wr_data <= HWDATA;
  wr_strb <= HWSTRB;

  -- Read channel: rd_en in the first (wait) cycle of the read data phase;
  -- the regfile's registered rd_data is valid in the second cycle.
  rd_en   <= rd_wait_q;
  rd_addr <= dphase_addr_q;
  HRDATA  <= rd_data;

  -- AHB handshake: one wait state on reads, always OKAY
  hready_i <= not rd_wait_q;
  HREADY   <= hready_i;
  HRESP    <= '0';

end architecture rtl;
