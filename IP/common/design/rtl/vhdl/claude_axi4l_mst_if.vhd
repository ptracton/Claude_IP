-- claude_axi4l_mst_if.vhd — Claude memory bus to AXI4-Lite master adapter (shared component).
--
-- VHDL-2008 twin of claude_axi4l_mst_if.sv; behaviour is identical.
-- Takes requests on the Claude memory bus (mem_*, the adapter is the target)
-- and issues them as AXI4-Lite master transactions. The bus rules are in
-- .agents/IP_SPEC_mem_bus.md (rules 1-5) and .agents/IP_SPEC_mem_bus_initiator.md
-- (rules 6-9, mem_prot, timing).
--
-- Protocol notes (see the SV file for the full list):
--   One transaction at a time. Write: AWVALID and WVALID rise together in cycle 1,
--   each held until its own handshake; BREADY high until the B handshake. Read:
--   ARVALID until ARREADY; RREADY high until the R handshake. mem_rvalid_o the cycle
--   after B / R, mem_err_o = BRESP(1) / RRESP(1). Zero-wait slave: mem_rvalid_o in
--   cycle 3, one transaction per 4 cycles. AxADDR = mem_addr_i, WSTRB = mem_be_i,
--   AxPROT = mem_prot_i. VALID never depends on READY; all outputs registered; every
--   VALID / READY low and mem_gnt_o = 0 in reset. No DFT ports.
--
-- Generics:
--   DATA_W : data width, 32 or 64 (AXI4-Lite), default 32
--   ADDR_W : byte address width, 1..64, default 32

library ieee;
use ieee.std_logic_1164.all;

entity claude_axi4l_mst_if is
  generic (
    DATA_W : positive := 32;  -- data bus width (32 or 64)
    ADDR_W : positive := 32   -- byte address width (1..64)
  );
  port (
    -- AXI4-Lite global signals
    ACLK         : in  std_ulogic;                                  -- AXI clock
    ARESETn      : in  std_ulogic;                                  -- active-low synchronous reset
    -- Write address channel
    AWVALID      : out std_ulogic;                                  -- write address valid
    AWREADY      : in  std_ulogic;                                  -- write address accepted
    AWADDR       : out std_ulogic_vector(ADDR_W - 1 downto 0);      -- write byte address
    AWPROT       : out std_ulogic_vector(2 downto 0);               -- write protection
    -- Write data channel
    WVALID       : out std_ulogic;                                  -- write data valid
    WREADY       : in  std_ulogic;                                  -- write data accepted
    WDATA        : out std_ulogic_vector(DATA_W - 1 downto 0);      -- write data
    WSTRB        : out std_ulogic_vector(DATA_W / 8 - 1 downto 0);  -- write byte strobes
    -- Write response channel
    BVALID       : in  std_ulogic;                                  -- write response valid
    BREADY       : out std_ulogic;                                  -- write response accepted
    BRESP        : in  std_ulogic_vector(1 downto 0);               -- write response
    -- Read address channel
    ARVALID      : out std_ulogic;                                  -- read address valid
    ARREADY      : in  std_ulogic;                                  -- read address accepted
    ARADDR       : out std_ulogic_vector(ADDR_W - 1 downto 0);      -- read byte address
    ARPROT       : out std_ulogic_vector(2 downto 0);               -- read protection
    -- Read data channel
    RVALID       : in  std_ulogic;                                  -- read data valid
    RREADY       : out std_ulogic;                                  -- read data accepted
    RDATA        : in  std_ulogic_vector(DATA_W - 1 downto 0);      -- read data
    RRESP        : in  std_ulogic_vector(1 downto 0);               -- read response

    -- Memory bus (target side)
    mem_req_i    : in  std_ulogic;                                  -- request valid
    mem_gnt_o    : out std_ulogic;                                  -- request accepted (adapter idle)
    mem_we_i     : in  std_ulogic;                                  -- 1 = write
    mem_addr_i   : in  std_ulogic_vector(ADDR_W - 1 downto 0);      -- byte address (rule 6)
    mem_be_i     : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0);  -- byte enables (rules 7-9)
    mem_wdata_i  : in  std_ulogic_vector(DATA_W - 1 downto 0);      -- write data
    mem_prot_i   : in  std_ulogic_vector(2 downto 0);               -- protection (AxPROT encoding)
    mem_rvalid_o : out std_ulogic;                                  -- response valid (one cycle)
    mem_rdata_o  : out std_ulogic_vector(DATA_W - 1 downto 0);      -- read data
    mem_err_o    : out std_ulogic                                   -- response is an error
  );
end entity claude_axi4l_mst_if;

architecture rtl of claude_axi4l_mst_if is

  type state_t is (ST_IDLE, ST_WRITE, ST_READ);

  signal state_q   : state_t;
  signal gnt_q     : std_ulogic;  -- registered mem_gnt_o: high in IDLE, low in reset
  signal awvalid_q : std_ulogic;
  signal wvalid_q  : std_ulogic;
  signal bready_q  : std_ulogic;
  signal arvalid_q : std_ulogic;
  signal rready_q  : std_ulogic;
  signal accept    : std_ulogic;  -- request handshake this cycle
  signal b_done    : std_ulogic;  -- write response handshake this cycle
  signal r_done    : std_ulogic;  -- read response handshake this cycle

begin

  -- Parameter checks (IP_SPEC_sideband.md rule 6)
  assert DATA_W = 32 or DATA_W = 64
    report "claude_axi4l_mst_if: DATA_W = " & integer'image(DATA_W) & " out of range (32 or 64)"
    severity failure;
  assert ADDR_W >= 1 and ADDR_W <= 64
    report "claude_axi4l_mst_if: ADDR_W = " & integer'image(ADDR_W) & " out of range [1, 64]"
    severity failure;

  accept <= mem_req_i and gnt_q;
  b_done <= BVALID and bready_q when state_q = ST_WRITE else '0';
  r_done <= RVALID and rready_q when state_q = ST_READ else '0';

  -- State machine and the VALID / READY signals.
  p_fsm : process (ACLK) is
  begin
    if rising_edge(ACLK) then
      if ARESETn = '0' then
        state_q   <= ST_IDLE;
        gnt_q     <= '0';
        awvalid_q <= '0';
        wvalid_q  <= '0';
        bready_q  <= '0';
        arvalid_q <= '0';
        rready_q  <= '0';
      else
        case state_q is
          when ST_IDLE =>
            gnt_q <= '1';
            if accept = '1' then
              gnt_q <= '0';
              if mem_we_i = '1' then
                state_q   <= ST_WRITE;
                awvalid_q <= '1';
                wvalid_q  <= '1';
                bready_q  <= '1';
              else
                state_q   <= ST_READ;
                arvalid_q <= '1';
                rready_q  <= '1';
              end if;
            end if;
          when ST_WRITE =>
            if awvalid_q = '1' and AWREADY = '1' then
              awvalid_q <= '0';
            end if;
            if wvalid_q = '1' and WREADY = '1' then
              wvalid_q <= '0';
            end if;
            if b_done = '1' then
              state_q  <= ST_IDLE;
              gnt_q    <= '1';
              bready_q <= '0';
            end if;
          when ST_READ =>
            if arvalid_q = '1' and ARREADY = '1' then
              arvalid_q <= '0';
            end if;
            if r_done = '1' then
              state_q  <= ST_IDLE;
              gnt_q    <= '1';
              rready_q <= '0';
            end if;
        end case;
      end if;
    end if;
  end process p_fsm;

  -- Address, protection, data and strobes: captured at the handshake.
  p_payload : process (ACLK) is
  begin
    if rising_edge(ACLK) then
      if ARESETn = '0' then
        AWADDR <= (others => '0');
        AWPROT <= (others => '0');
        WDATA  <= (others => '0');
        WSTRB  <= (others => '0');
        ARADDR <= (others => '0');
        ARPROT <= (others => '0');
      elsif accept = '1' then
        if mem_we_i = '1' then
          AWADDR <= mem_addr_i;
          AWPROT <= mem_prot_i;
          WDATA  <= mem_wdata_i;
          WSTRB  <= mem_be_i;
        else
          ARADDR <= mem_addr_i;
          ARPROT <= mem_prot_i;
        end if;
      end if;
    end if;
  end process p_payload;

  -- Response: one-cycle mem_rvalid_o after the B or R handshake.
  p_rsp : process (ACLK) is
  begin
    if rising_edge(ACLK) then
      if ARESETn = '0' then
        mem_rvalid_o <= '0';
        mem_rdata_o  <= (others => '0');
        mem_err_o    <= '0';
      else
        mem_rvalid_o <= b_done or r_done;
        if r_done = '1' then
          mem_rdata_o <= RDATA;
          mem_err_o   <= RRESP(1);
        elsif b_done = '1' then
          mem_rdata_o <= (others => '0');
          mem_err_o   <= BRESP(1);
        end if;
      end if;
    end if;
  end process p_rsp;

  AWVALID   <= awvalid_q;
  WVALID    <= wvalid_q;
  BREADY    <= bready_q;
  ARVALID   <= arvalid_q;
  RREADY    <= rready_q;
  mem_gnt_o <= gnt_q;

end architecture rtl;
