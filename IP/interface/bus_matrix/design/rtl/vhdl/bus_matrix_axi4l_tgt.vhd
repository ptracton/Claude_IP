-- bus_matrix_axi4l_tgt.vhd — AXI4-Lite target adapter for one bus matrix master port (VHDL-2008).
--
-- Acts as an AXI4-Lite slave towards the external master. One write and one
-- read may be outstanding at the same time; each is turned into one request
-- on the core's internal handshake (writes first when both are waiting).
--
--   Write: AW and W are accepted independently, in either order. Once both
--     have been taken the write is issued; its response is held on B until
--     BREADY. AWREADY/WREADY stay low from acceptance until the B handshake.
--   Read:  AR is accepted, the read is issued, and RDATA/RRESP are held on R
--     until RREADY. ARREADY stays low until the R handshake.
--   Errors (decode or slave) are returned as SLVERR.
-- Mirrors bus_matrix_axi4l_tgt.sv.

library ieee;
use ieee.std_logic_1164.all;

entity bus_matrix_axi4l_tgt is
  generic (
    DATA_W : positive := 32;  -- data bus width
    ADDR_W : positive := 32   -- address width
  );
  port (
    clk        : in  std_ulogic;                                  -- system clock
    rst_n      : in  std_ulogic;                                  -- synchronous active-low reset

    -- AXI4-Lite slave interface (towards the external master)
    AWVALID    : in  std_ulogic;                                  -- write address valid
    AWREADY    : out std_ulogic;                                  -- write address ready
    AWADDR     : in  std_ulogic_vector(ADDR_W - 1 downto 0);      -- write byte address
    WVALID     : in  std_ulogic;                                  -- write data valid
    WREADY     : out std_ulogic;                                  -- write data ready
    WDATA      : in  std_ulogic_vector(DATA_W - 1 downto 0);      -- write data
    WSTRB      : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0);  -- write byte strobes
    BVALID     : out std_ulogic;                                  -- write response valid
    BREADY     : in  std_ulogic;                                  -- write response ready
    BRESP      : out std_ulogic_vector(1 downto 0);               -- write response
    ARVALID    : in  std_ulogic;                                  -- read address valid
    ARREADY    : out std_ulogic;                                  -- read address ready
    ARADDR     : in  std_ulogic_vector(ADDR_W - 1 downto 0);      -- read byte address
    RVALID     : out std_ulogic;                                  -- read data valid
    RREADY     : in  std_ulogic;                                  -- read data ready
    RDATA      : out std_ulogic_vector(DATA_W - 1 downto 0);      -- read data
    RRESP      : out std_ulogic_vector(1 downto 0);               -- read response

    -- Core handshake
    core_req   : out std_ulogic;                                  -- request held until done
    core_addr  : out std_ulogic_vector(ADDR_W - 1 downto 0);      -- byte address
    core_wdata : out std_ulogic_vector(DATA_W - 1 downto 0);      -- write data
    core_we    : out std_ulogic;                                  -- 1 = write
    core_be    : out std_ulogic_vector(DATA_W / 8 - 1 downto 0);  -- byte enables
    core_done  : in  std_ulogic;                                  -- one-cycle completion
    core_rdata : in  std_ulogic_vector(DATA_W - 1 downto 0);      -- read data (valid with done)
    core_err   : in  std_ulogic                                   -- error (valid with done)
  );
end entity bus_matrix_axi4l_tgt;

architecture rtl of bus_matrix_axi4l_tgt is

  constant RESP_OKAY   : std_ulogic_vector(1 downto 0) := "00";
  constant RESP_SLVERR : std_ulogic_vector(1 downto 0) := "10";

  type cur_t is (CUR_NONE, CUR_WRITE, CUR_READ);

  -- Write path
  signal aw_got_q : std_ulogic;  -- AW accepted
  signal w_got_q  : std_ulogic;  -- W accepted
  signal awaddr_q : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal wdata_q  : std_ulogic_vector(DATA_W - 1 downto 0);
  signal wstrb_q  : std_ulogic_vector(DATA_W / 8 - 1 downto 0);
  signal bvalid_q : std_ulogic;
  signal bresp_q  : std_ulogic_vector(1 downto 0);

  -- Read path
  signal ar_got_q : std_ulogic;  -- AR accepted
  signal araddr_q : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal rvalid_q : std_ulogic;
  signal rdata_q  : std_ulogic_vector(DATA_W - 1 downto 0);
  signal rresp_q  : std_ulogic_vector(1 downto 0);

  signal cur_q    : cur_t;

  signal awready_i  : std_ulogic;
  signal wready_i   : std_ulogic;
  signal arready_i  : std_ulogic;
  signal aw_hs      : std_ulogic;
  signal w_hs       : std_ulogic;
  signal ar_hs      : std_ulogic;
  signal wr_pending : std_ulogic;  -- a fully received write not yet routed
  signal rd_pending : std_ulogic;  -- a received read not yet routed
  signal wr_done    : std_ulogic;  -- the routed write completes
  signal rd_done    : std_ulogic;  -- the routed read completes
  signal aw_got_d   : std_ulogic;
  signal w_got_d    : std_ulogic;
  signal ar_got_d   : std_ulogic;

begin

  awready_i <= not aw_got_q and not bvalid_q;
  wready_i  <= not w_got_q and not bvalid_q;
  arready_i <= not ar_got_q and not rvalid_q;

  aw_hs <= AWVALID and awready_i;
  w_hs  <= WVALID and wready_i;
  ar_hs <= ARVALID and arready_i;

  wr_pending <= aw_got_q and w_got_q and not bvalid_q when cur_q /= CUR_WRITE else '0';
  rd_pending <= ar_got_q and not rvalid_q when cur_q /= CUR_READ else '0';

  -- Accepted-flag next state: set by the handshake, cleared when the routed
  -- transaction completes (a new handshake cannot coincide with completion,
  -- since READY is low while the flag is set).
  wr_done  <= core_done when cur_q = CUR_WRITE else '0';
  rd_done  <= core_done when cur_q = CUR_READ else '0';
  aw_got_d <= (aw_got_q or aw_hs) and not wr_done;
  w_got_d  <= (w_got_q or w_hs) and not wr_done;
  ar_got_d <= (ar_got_q or ar_hs) and not rd_done;

  p_got : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        aw_got_q <= '0';
        w_got_q  <= '0';
        ar_got_q <= '0';
      else
        aw_got_q <= aw_got_d;
        w_got_q  <= w_got_d;
        ar_got_q <= ar_got_d;
      end if;
    end if;
  end process p_got;

  p_write : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        awaddr_q <= (others => '0');
        wdata_q  <= (others => '0');
        wstrb_q  <= (others => '0');
        bvalid_q <= '0';
        bresp_q  <= RESP_OKAY;
      else
        if aw_hs = '1' then
          awaddr_q <= AWADDR;
        end if;
        if w_hs = '1' then
          wdata_q <= WDATA;
          wstrb_q <= WSTRB;
        end if;
        if wr_done = '1' then
          bvalid_q <= '1';
          if core_err = '1' then
            bresp_q <= RESP_SLVERR;
          else
            bresp_q <= RESP_OKAY;
          end if;
        elsif bvalid_q = '1' and BREADY = '1' then
          bvalid_q <= '0';
        end if;
      end if;
    end if;
  end process p_write;

  p_read : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        araddr_q <= (others => '0');
        rvalid_q <= '0';
        rdata_q  <= (others => '0');
        rresp_q  <= RESP_OKAY;
      else
        if ar_hs = '1' then
          araddr_q <= ARADDR;
        end if;
        if rd_done = '1' then
          rvalid_q <= '1';
          rdata_q  <= core_rdata;
          if core_err = '1' then
            rresp_q <= RESP_SLVERR;
          else
            rresp_q <= RESP_OKAY;
          end if;
        elsif rvalid_q = '1' and RREADY = '1' then
          rvalid_q <= '0';
        end if;
      end if;
    end if;
  end process p_read;

  -- Core port ownership: hold the routed direction until done.
  p_cur : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        cur_q <= CUR_NONE;
      elsif cur_q /= CUR_NONE then
        if core_done = '1' then
          cur_q <= CUR_NONE;
        end if;
      elsif wr_pending = '1' then
        cur_q <= CUR_WRITE;
      elsif rd_pending = '1' then
        cur_q <= CUR_READ;
      end if;
    end if;
  end process p_cur;

  core_req   <= '0' when cur_q = CUR_NONE else '1';
  core_we    <= '1' when cur_q = CUR_WRITE else '0';
  core_addr  <= awaddr_q when cur_q = CUR_WRITE else araddr_q;
  core_wdata <= wdata_q;
  core_be    <= wstrb_q;

  AWREADY <= awready_i;
  WREADY  <= wready_i;
  ARREADY <= arready_i;
  BVALID  <= bvalid_q;
  BRESP   <= bresp_q;
  RVALID  <= rvalid_q;
  RDATA   <= rdata_q;
  RRESP   <= rresp_q;

end architecture rtl;
