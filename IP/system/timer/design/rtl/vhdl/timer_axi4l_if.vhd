-- timer_axi4l_if.vhd — AXI4-Lite bus interface for Timer IP (VHDL-2008).
--
-- Translates AXI4-Lite transactions into the flat register-file access bus.
-- Port-for-port equivalent to timer_axi4l_if.sv.
--
-- Implementation notes:
--   AWREADY / WREADY / ARREADY are always asserted (no back-pressure).
--   Write: capture AW+W; generate wr_en; assert BVALID; hold until BREADY.
--   Read:  capture AR; assert rd_en; latch rd_data; assert RVALID.
--   BRESP and RRESP are always OKAY (00).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity timer_axi4l_if is
  generic (
    DATA_W : positive := 32; -- data bus width
    ADDR_W : positive := 4   -- regfile word-address width
  );
  port (
    -- AXI4-Lite global signals
    ACLK    : in  std_ulogic;                                   -- AXI clock
    ARESETn : in  std_ulogic;                                   -- AXI active-low reset

    -- Write address channel
    AWVALID : in  std_ulogic;                                   -- master write address valid
    AWREADY : out std_ulogic;                                   -- slave ready for write address
    AWADDR  : in  std_ulogic_vector(11 downto 0);               -- write byte address

    -- Write data channel
    WVALID  : in  std_ulogic;                                   -- master write data valid
    WREADY  : out std_ulogic;                                   -- slave ready for write data
    WDATA   : in  std_ulogic_vector(DATA_W - 1 downto 0);       -- write data
    WSTRB   : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0);  -- byte enables

    -- Write response channel
    BVALID  : out std_ulogic;                                   -- slave write response valid
    BREADY  : in  std_ulogic;                                   -- master ready for response
    BRESP   : out std_ulogic_vector(1 downto 0);                -- write response (OKAY)

    -- Read address channel
    ARVALID : in  std_ulogic;                                   -- master read address valid
    ARREADY : out std_ulogic;                                   -- slave ready for read address
    ARADDR  : in  std_ulogic_vector(11 downto 0);               -- read byte address

    -- Read data channel
    RVALID  : out std_ulogic;                                   -- slave read data valid
    RREADY  : in  std_ulogic;                                   -- master ready for read data
    RDATA   : out std_ulogic_vector(DATA_W - 1 downto 0);       -- read data
    RRESP   : out std_ulogic_vector(1 downto 0);                -- read response (OKAY)

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
end entity timer_axi4l_if;

architecture rtl of timer_axi4l_if is

  -- Write path registers
  signal aw_captured_q : std_ulogic;
  signal aw_addr_q     : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal w_captured_q  : std_ulogic;
  signal w_data_q      : std_ulogic_vector(DATA_W - 1 downto 0);
  signal w_strb_q      : std_ulogic_vector(DATA_W / 8 - 1 downto 0);
  signal bvalid_q      : std_ulogic;

  -- Read path: two-stage pipeline to match regfile registered-read latency
  --   Stage 1 (ar_captured_q): AR captured → rd_en asserted (combinational)
  --   Stage 2 (ar_rd_pending_q): regfile has now clocked rd_data → latch it
  signal ar_captured_q   : std_ulogic;
  signal ar_addr_q       : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal ar_rd_pending_q : std_ulogic;  -- one-cycle delay after rd_en
  signal rvalid_q        : std_ulogic;
  signal rdata_q         : std_ulogic_vector(DATA_W - 1 downto 0);

begin

  -- -------------------------------------------------------------------------
  -- Write address / data capture and wr_en / BVALID generation
  -- -------------------------------------------------------------------------
  p_write : process(ACLK) is
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
          aw_captured_q <= '0';  -- consumed
        end if;

        -- Capture write data
        if WVALID = '1' and WREADY = '1' then
          w_captured_q <= '1';
          w_data_q     <= WDATA;
          w_strb_q     <= WSTRB;
        elsif aw_captured_q = '1' and w_captured_q = '1' then
          w_captured_q <= '0';  -- consumed
        end if;

        -- Issue BVALID one cycle after both AW and W captured
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
  BRESP   <= "00";  -- OKAY

  -- -------------------------------------------------------------------------
  -- Read address capture and rd_en / RVALID generation
  -- -------------------------------------------------------------------------
  p_read : process(ACLK) is
  begin
    if rising_edge(ACLK) then
      if ARESETn = '0' then
        ar_captured_q   <= '0';
        ar_addr_q       <= (others => '0');
        ar_rd_pending_q <= '0';
        rvalid_q        <= '0';
        rdata_q         <= (others => '0');
      else
        -- Stage 1: capture AR address; rd_en is combinational from ar_captured_q
        if ARVALID = '1' and ARREADY = '1' then
          ar_captured_q <= '1';
          ar_addr_q     <= ARADDR(ADDR_W + 1 downto 2);
        else
          ar_captured_q <= '0';
        end if;

        -- Stage 2: rd_en was high last cycle; regfile has now registered rd_data
        ar_rd_pending_q <= ar_captured_q;
        if ar_rd_pending_q = '1' then
          rdata_q  <= rd_data;  -- rd_data valid one cycle after rd_en
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
  RRESP   <= "00";  -- OKAY

end architecture rtl;
