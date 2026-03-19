-- claude_axi4l_if.vhd — AXI4-Lite bus-to-regfile bridge (shared Claude IP component).
--
-- Translates AXI4-Lite transactions into the flat register-file access bus.
-- This module is protocol-generic and contains no IP-specific logic.
-- It is shared across all Claude IP blocks that expose an AXI4-Lite slave port.
--
-- Implementation notes:
--   Single outstanding transaction per channel (no pipelining).
--   AWREADY / WREADY / ARREADY are always asserted (combinational '1').
--   Write: capture AW and W simultaneously; generate wr_en and BVALID next
--     cycle; hold BVALID until master asserts BREADY.
--   Read: capture AR; assert rd_en; present RVALID/RDATA the cycle after
--     rd_en (matched to regfile registered read latency).
--   BRESP and RRESP are always OKAY (00).
--
-- Generics:
--   DATA_W : data bus width             (default 32)
--   ADDR_W : regfile word-address width (default 4)

library ieee;
use ieee.std_logic_1164.all;

entity claude_axi4l_if is
  generic (
    DATA_W : positive := 32;
    ADDR_W : positive := 4
  );
  port (
    -- AXI4-Lite global signals
    ACLK    : in  std_ulogic;
    ARESETn : in  std_ulogic;

    -- Write address channel
    AWVALID : in  std_ulogic;
    AWREADY : out std_ulogic;
    AWADDR  : in  std_ulogic_vector(11 downto 0);

    -- Write data channel
    WVALID  : in  std_ulogic;
    WREADY  : out std_ulogic;
    WDATA   : in  std_ulogic_vector(DATA_W - 1 downto 0);
    WSTRB   : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0);

    -- Write response channel
    BVALID  : out std_ulogic;
    BREADY  : in  std_ulogic;
    BRESP   : out std_ulogic_vector(1 downto 0);

    -- Read address channel
    ARVALID : in  std_ulogic;
    ARREADY : out std_ulogic;
    ARADDR  : in  std_ulogic_vector(11 downto 0);

    -- Read data channel
    RVALID  : out std_ulogic;
    RREADY  : in  std_ulogic;
    RDATA   : out std_ulogic_vector(DATA_W - 1 downto 0);
    RRESP   : out std_ulogic_vector(1 downto 0);

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
end entity claude_axi4l_if;

architecture rtl of claude_axi4l_if is

  -- Write path registers
  signal aw_captured_q : std_ulogic;
  signal aw_addr_q     : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal w_captured_q  : std_ulogic;
  signal w_data_q      : std_ulogic_vector(DATA_W - 1 downto 0);
  signal w_strb_q      : std_ulogic_vector(DATA_W / 8 - 1 downto 0);
  signal bvalid_q      : std_ulogic;

  -- Read path registers
  signal ar_captured_q   : std_ulogic;
  signal ar_addr_q       : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal ar_rd_pending_q : std_ulogic;
  signal rvalid_q        : std_ulogic;
  signal rdata_q         : std_ulogic_vector(DATA_W - 1 downto 0);

begin

  -- -------------------------------------------------------------------------
  -- Write address / data capture and wr_en generation
  -- -------------------------------------------------------------------------
  p_write : process (ACLK) is
  begin
    if rising_edge(ACLK) then
      if ARESETn = '0' then
        aw_captured_q <= '0';
        aw_addr_q     <= (others => '0');
        w_captured_q  <= '0';
        w_data_q      <= (others => '0');
        w_strb_q      <= (others => '0');
        bvalid_q      <= '0';
      else
        -- Capture write address
        if AWVALID = '1' and AWREADY = '1' then
          aw_captured_q <= '1';
          aw_addr_q     <= AWADDR(ADDR_W + 1 downto 2);
        elsif aw_captured_q = '1' and w_captured_q = '1' then
          aw_captured_q <= '0';
        end if;

        -- Capture write data
        if WVALID = '1' and WREADY = '1' then
          w_captured_q <= '1';
          w_data_q     <= WDATA;
          w_strb_q     <= WSTRB;
        elsif aw_captured_q = '1' and w_captured_q = '1' then
          w_captured_q <= '0';
        end if;

        -- BVALID: assert one cycle after both AW and W captured
        if aw_captured_q = '1' and w_captured_q = '1' then
          bvalid_q <= '1';
        elsif BREADY = '1' then
          bvalid_q <= '0';
        end if;
      end if;
    end if;
  end process p_write;

  wr_en   <= aw_captured_q and w_captured_q;
  wr_addr <= aw_addr_q;
  wr_data <= w_data_q;
  wr_strb <= w_strb_q;

  AWREADY <= '1';
  WREADY  <= '1';
  BVALID  <= bvalid_q;
  BRESP   <= "00";

  -- -------------------------------------------------------------------------
  -- Read address capture and rd_en / RVALID generation
  -- -------------------------------------------------------------------------
  p_read : process (ACLK) is
  begin
    if rising_edge(ACLK) then
      if ARESETn = '0' then
        ar_captured_q   <= '0';
        ar_addr_q       <= (others => '0');
        ar_rd_pending_q <= '0';
        rvalid_q        <= '0';
        rdata_q         <= (others => '0');
      else
        -- Stage 1: capture AR
        if ARVALID = '1' and ARREADY = '1' then
          ar_captured_q <= '1';
          ar_addr_q     <= ARADDR(ADDR_W + 1 downto 2);
        else
          ar_captured_q <= '0';
        end if;

        -- Stage 2: rd_data valid one cycle after rd_en
        ar_rd_pending_q <= ar_captured_q;
        if ar_rd_pending_q = '1' then
          rdata_q  <= rd_data;
          rvalid_q <= '1';
        elsif RREADY = '1' and rvalid_q = '1' then
          rvalid_q <= '0';
        end if;
      end if;
    end if;
  end process p_read;

  rd_en   <= ar_captured_q;
  rd_addr <= ar_addr_q;

  ARREADY <= '1';
  RVALID  <= rvalid_q;
  RDATA   <= rdata_q;
  RRESP   <= "00";

end architecture rtl;
