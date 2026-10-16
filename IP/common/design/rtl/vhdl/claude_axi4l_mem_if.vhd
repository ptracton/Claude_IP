-- claude_axi4l_mem_if.vhd — AXI4-Lite slave to Claude memory bus adapter (shared component).
--
-- VHDL-2008 twin of claude_axi4l_mem_if.sv; behaviour is identical.
-- Turns AXI4-Lite transfers into requests on the Claude memory bus (mem_*),
-- for memory-like targets that may stall and may report errors. The bus
-- rules are in IP/common/design/rtl/mem_bus.md. Register-file IP keeps using
-- claude_axi4l_if; this adapter is for memories.
--
-- Protocol notes:
--   One write and one read may be in flight at once. AW, W and AR are each
--   captured into a one-entry slot (READY is high while the slot is empty);
--   a slot is freed by the B (write) or R (read) handshake.
--   Reads and writes are serialized onto the single memory port and
--   alternate (round robin) when both are ready.
--   BRESP/RRESP: OKAY ("00"), or SLVERR ("10") when mem_err_i was set.
--   Byte enables: WSTRB on writes, all ones on reads.
--
-- Generics:
--   DATA_W : data bus width, multiple of 8 (default 32)
--   ADDR_W : byte address width             (default 32)

library ieee;
use ieee.std_logic_1164.all;

entity claude_axi4l_mem_if is
  generic (
    DATA_W : positive := 32;
    ADDR_W : positive := 32
  );
  port (
    -- AXI4-Lite global signals
    ACLK         : in  std_ulogic;
    ARESETn      : in  std_ulogic;

    -- Write address channel
    AWVALID      : in  std_ulogic;
    AWREADY      : out std_ulogic;
    AWADDR       : in  std_ulogic_vector(ADDR_W - 1 downto 0);

    -- Write data channel
    WVALID       : in  std_ulogic;
    WREADY       : out std_ulogic;
    WDATA        : in  std_ulogic_vector(DATA_W - 1 downto 0);
    WSTRB        : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0);

    -- Write response channel
    BVALID       : out std_ulogic;
    BREADY       : in  std_ulogic;
    BRESP        : out std_ulogic_vector(1 downto 0);

    -- Read address channel
    ARVALID      : in  std_ulogic;
    ARREADY      : out std_ulogic;
    ARADDR       : in  std_ulogic_vector(ADDR_W - 1 downto 0);

    -- Read data channel
    RVALID       : out std_ulogic;
    RREADY       : in  std_ulogic;
    RDATA        : out std_ulogic_vector(DATA_W - 1 downto 0);
    RRESP        : out std_ulogic_vector(1 downto 0);

    -- Memory bus (initiator side)
    mem_req_o    : out std_ulogic;
    mem_gnt_i    : in  std_ulogic;
    mem_we_o     : out std_ulogic;
    mem_addr_o   : out std_ulogic_vector(ADDR_W - 1 downto 0);
    mem_be_o     : out std_ulogic_vector(DATA_W / 8 - 1 downto 0);
    mem_wdata_o  : out std_ulogic_vector(DATA_W - 1 downto 0);
    mem_rvalid_i : in  std_ulogic;
    mem_rdata_i  : in  std_ulogic_vector(DATA_W - 1 downto 0);
    mem_err_i    : in  std_ulogic
  );
end entity claude_axi4l_mem_if;

architecture rtl of claude_axi4l_mem_if is

  constant RESP_OKAY_C   : std_ulogic_vector(1 downto 0) := "00";
  constant RESP_SLVERR_C : std_ulogic_vector(1 downto 0) := "10";

  -- Request slots: one write address, one write data, one read address.
  signal aw_full_q : std_ulogic;
  signal aw_addr_q : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal w_full_q  : std_ulogic;
  signal w_data_q  : std_ulogic_vector(DATA_W - 1 downto 0);
  signal w_strb_q  : std_ulogic_vector(DATA_W / 8 - 1 downto 0);
  signal ar_full_q : std_ulogic;
  signal ar_addr_q : std_ulogic_vector(ADDR_W - 1 downto 0);

  -- Responses waiting for the master.
  signal bvalid_q  : std_ulogic;
  signal bresp_q   : std_ulogic_vector(1 downto 0);
  signal rvalid_q  : std_ulogic;
  signal rdata_q   : std_ulogic_vector(DATA_W - 1 downto 0);
  signal rresp_q   : std_ulogic_vector(1 downto 0);

  -- Channel handshakes.
  signal aw_hs     : std_ulogic;
  signal w_hs      : std_ulogic;
  signal ar_hs     : std_ulogic;
  signal b_hs      : std_ulogic;
  signal r_hs      : std_ulogic;

  -- Request state machine (see claude_axi4l_mem_if.sv for the states).
  type req_state_t is (StIdle, StReq, StWait);

  signal state_d      : req_state_t;
  signal state_q      : req_state_t;
  signal wr_ready     : std_ulogic;  -- a complete write is waiting
  signal rd_ready     : std_ulogic;  -- a read is waiting
  signal pick_write   : std_ulogic;  -- StIdle: which one to issue now
  signal sel_write_d  : std_ulogic;  -- the request in flight is a write
  signal sel_write_q  : std_ulogic;
  signal last_write_d : std_ulogic;  -- last issued request was a write
  signal last_write_q : std_ulogic;
  signal cur_write    : std_ulogic;  -- request on the memory bus is a write
  signal resp_wr      : std_ulogic;  -- memory response for a write
  signal resp_rd      : std_ulogic;  -- memory response for a read

begin

  AWREADY <= not aw_full_q;
  WREADY  <= not w_full_q;
  ARREADY <= not ar_full_q;

  aw_hs <= AWVALID and not aw_full_q;
  w_hs  <= WVALID and not w_full_q;
  ar_hs <= ARVALID and not ar_full_q;
  b_hs  <= bvalid_q and BREADY;
  r_hs  <= rvalid_q and RREADY;

  p_slots : process (ACLK) is
  begin
    if rising_edge(ACLK) then
      if ARESETn = '0' then
        aw_full_q <= '0';
        aw_addr_q <= (others => '0');
        w_full_q  <= '0';
        w_data_q  <= (others => '0');
        w_strb_q  <= (others => '0');
        ar_full_q <= '0';
        ar_addr_q <= (others => '0');
      else
        if aw_hs = '1' then
          aw_full_q <= '1';
          aw_addr_q <= AWADDR;
        elsif b_hs = '1' then
          aw_full_q <= '0';
        end if;
        if w_hs = '1' then
          w_full_q <= '1';
          w_data_q <= WDATA;
          w_strb_q <= WSTRB;
        elsif b_hs = '1' then
          w_full_q <= '0';
        end if;
        if ar_hs = '1' then
          ar_full_q <= '1';
          ar_addr_q <= ARADDR;
        elsif r_hs = '1' then
          ar_full_q <= '0';
        end if;
      end if;
    end if;
  end process p_slots;

  wr_ready <= aw_full_q and w_full_q and not bvalid_q;
  rd_ready <= ar_full_q and not rvalid_q;
  -- Both ready: take the opposite of the last one issued (round robin).
  pick_write <= not last_write_q when (wr_ready = '1' and rd_ready = '1') else wr_ready;

  p_state_comb : process (all) is
  begin
    state_d      <= state_q;
    sel_write_d  <= sel_write_q;
    last_write_d <= last_write_q;
    case state_q is
      -- StIdle: issue the next ready request at once; it stays on the bus
      -- (from StReq) if the memory does not grant it in this cycle.
      when StIdle =>
        if wr_ready = '1' or rd_ready = '1' then
          sel_write_d  <= pick_write;
          last_write_d <= pick_write;
          if mem_gnt_i = '1' then
            state_d <= StWait;
          else
            state_d <= StReq;
          end if;
        end if;
      -- StReq: hold the request until granted.
      when StReq =>
        if mem_gnt_i = '1' then
          state_d <= StWait;
        end if;
      -- StWait: the response returns the state machine to idle.
      when StWait =>
        if mem_rvalid_i = '1' then
          state_d <= StIdle;
        end if;
      when others =>
        state_d <= StIdle;
    end case;
  end process p_state_comb;

  p_state_reg : process (ACLK) is
  begin
    if rising_edge(ACLK) then
      if ARESETn = '0' then
        state_q      <= StIdle;
        sel_write_q  <= '0';
        last_write_q <= '0';
      else
        state_q      <= state_d;
        sel_write_q  <= sel_write_d;
        last_write_q <= last_write_d;
      end if;
    end if;
  end process p_state_reg;

  cur_write <= pick_write when state_q = StIdle else sel_write_q;

  mem_req_o   <= '1' when (state_q = StIdle and (wr_ready = '1' or rd_ready = '1')) or
                          (state_q = StReq)
                 else '0';
  mem_we_o    <= cur_write;
  mem_addr_o  <= aw_addr_q when cur_write = '1' else ar_addr_q;
  mem_be_o    <= w_strb_q when cur_write = '1' else (others => '1');
  mem_wdata_o <= w_data_q;

  -- Responses: captured from the memory, held until the master takes them.
  resp_wr <= '1' when state_q = StWait and mem_rvalid_i = '1' and sel_write_q = '1' else '0';
  resp_rd <= '1' when state_q = StWait and mem_rvalid_i = '1' and sel_write_q = '0' else '0';

  p_resp : process (ACLK) is
  begin
    if rising_edge(ACLK) then
      if ARESETn = '0' then
        bvalid_q <= '0';
        bresp_q  <= RESP_OKAY_C;
        rvalid_q <= '0';
        rdata_q  <= (others => '0');
        rresp_q  <= RESP_OKAY_C;
      else
        if resp_wr = '1' then
          bvalid_q <= '1';
          if mem_err_i = '1' then
            bresp_q <= RESP_SLVERR_C;
          else
            bresp_q <= RESP_OKAY_C;
          end if;
        elsif b_hs = '1' then
          bvalid_q <= '0';
        end if;
        if resp_rd = '1' then
          rvalid_q <= '1';
          rdata_q  <= mem_rdata_i;
          if mem_err_i = '1' then
            rresp_q <= RESP_SLVERR_C;
          else
            rresp_q <= RESP_OKAY_C;
          end if;
        elsif r_hs = '1' then
          rvalid_q <= '0';
        end if;
      end if;
    end if;
  end process p_resp;

  BVALID <= bvalid_q;
  BRESP  <= bresp_q;
  RVALID <= rvalid_q;
  RDATA  <= rdata_q;
  RRESP  <= rresp_q;

end architecture rtl;
