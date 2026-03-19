-- timer_ahb_if.vhd — AHB-Lite bus interface for Timer IP (VHDL-2008).
--
-- Translates AHB-Lite transactions into the flat register-file access bus.
-- Port-for-port equivalent to timer_ahb_if.sv.
--
-- Protocol notes:
--   Two-phase pipeline: address phase then data phase.
--   HREADY is always asserted (zero wait-states).
--   HRESP is always OKAY.
--   Only HTRANS == NONSEQ (2'b10) initiates a transfer.
--   HSEL qualifies all transactions.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity timer_ahb_if is
  generic (
    DATA_W : positive := 32; -- data bus width
    ADDR_W : positive := 4   -- regfile word-address width
  );
  port (
    -- AHB-Lite bus signals
    HCLK     : in  std_ulogic;                                   -- AHB clock
    HRESETn  : in  std_ulogic;                                   -- AHB active-low reset
    HSEL     : in  std_ulogic;                                   -- slave select
    HADDR    : in  std_ulogic_vector(11 downto 0);               -- byte address
    HTRANS   : in  std_ulogic_vector(1 downto 0);                -- transfer type
    HWRITE   : in  std_ulogic;                                   -- 1=write
    HWDATA   : in  std_ulogic_vector(DATA_W - 1 downto 0);       -- write data
    HWSTRB   : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0);  -- byte strobes
    HRDATA   : out std_ulogic_vector(DATA_W - 1 downto 0);       -- read data
    HREADY   : out std_ulogic;                                   -- always ready
    HRESP    : out std_ulogic;                                   -- always OKAY

    -- Register-file write channel
    wr_en    : out std_ulogic;                                   -- write enable
    wr_addr  : out std_ulogic_vector(ADDR_W - 1 downto 0);      -- word address
    wr_data  : out std_ulogic_vector(DATA_W - 1 downto 0);      -- write data
    wr_strb  : out std_ulogic_vector(DATA_W / 8 - 1 downto 0);  -- byte enables

    -- Register-file read channel
    rd_en    : out std_ulogic;                                   -- read enable
    rd_addr  : out std_ulogic_vector(ADDR_W - 1 downto 0);      -- word address
    rd_data  : in  std_ulogic_vector(DATA_W - 1 downto 0)       -- read data
  );
end entity timer_ahb_if;

architecture rtl of timer_ahb_if is

  -- AHB HTRANS encoding
  constant AHB_TRANS_NONSEQ : std_ulogic_vector(1 downto 0) := "10";

  -- Address-phase pipeline registers
  signal dphase_valid_q : std_ulogic;
  signal dphase_write_q : std_ulogic;
  signal dphase_addr_q  : std_ulogic_vector(ADDR_W - 1 downto 0);

begin

  -- -------------------------------------------------------------------------
  -- Address phase: latch transfer type and address when NONSEQ selected
  -- -------------------------------------------------------------------------
  p_addr_phase : process(HCLK) is
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
          -- byte address bits [ADDR_W+1:2] form the word address
          dphase_addr_q  <= HADDR(ADDR_W + 1 downto 2);
        else
          dphase_valid_q <= '0';
        end if;
      end if;
    end if;
  end process p_addr_phase;

  -- -------------------------------------------------------------------------
  -- Write channel: drive regfile write signals during data phase
  -- -------------------------------------------------------------------------
  wr_en   <= dphase_valid_q and dphase_write_q;
  wr_addr <= dphase_addr_q;
  wr_data <= HWDATA;
  wr_strb <= HWSTRB;

  -- -------------------------------------------------------------------------
  -- Read channel: assert rd_en and provide address during data phase
  -- -------------------------------------------------------------------------
  rd_en   <= dphase_valid_q and (not dphase_write_q);
  rd_addr <= dphase_addr_q;
  HRDATA  <= rd_data;

  -- -------------------------------------------------------------------------
  -- AHB handshake: zero wait-states, always OKAY
  -- -------------------------------------------------------------------------
  HREADY <= '1';
  HRESP  <= '0';  -- OKAY

end architecture rtl;
