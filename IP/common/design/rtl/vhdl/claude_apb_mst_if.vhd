-- claude_apb_mst_if.vhd — Claude memory bus to APB4 master adapter (shared component).
--
-- VHDL-2008 twin of claude_apb_mst_if.sv; behaviour is identical.
-- Takes requests on the Claude memory bus (mem_*, the adapter is the target)
-- and issues them as APB4 master transfers. It is the initiator-side
-- counterpart of claude_apb_mem_if. The bus rules are in
-- .agents/IP_SPEC_mem_bus.md (rules 1-5) and .agents/IP_SPEC_mem_bus_initiator.md
-- (rules 6-9, mem_prot, timing).
--
-- Protocol notes:
--   One transfer at a time. mem_gnt_o is high whenever the adapter is idle;
--   a request is captured in its handshake cycle (cycle 0).
--   Cycle 1: SETUP (PSEL = 1, PENABLE = 0). Cycle 2 onwards: ACCESS
--   (PENABLE = 1) until PREADY. The cycle after PREADY: mem_rvalid_o, with
--   mem_rdata_o = PRDATA and mem_err_o = PSLVERR captured at PREADY.
--   Zero-wait slave: mem_rvalid_o in cycle 3, one transfer per 4 cycles.
--   Every APB output and every mem_* output comes from a flop.
--   PSTRB = mem_be_i on writes and 0 on reads (APB4 rule). PADDR is the byte
--   address mem_addr_i unchanged. PPROT = mem_prot_i (AxPROT encoding).
--   During reset the bus is idle (PSEL = PENABLE = 0) and mem_gnt_o is 0.
--   No DFT ports: no clock, reset or memory logic of its own (spec).
--
-- Generics:
--   DATA_W : data width, a multiple of 8, 8..32 for APB4 (default 32)
--   ADDR_W : byte address width, 1..32 (default 32)

library ieee;
use ieee.std_logic_1164.all;

entity claude_apb_mst_if is
  generic (
    DATA_W : positive := 32;  -- data bus width (multiple of 8, 8..32)
    ADDR_W : positive := 32   -- byte address width (1..32)
  );
  port (
    -- APB4 bus signals (master side)
    PCLK         : in  std_ulogic;                                  -- APB clock
    PRESETn      : in  std_ulogic;                                  -- active-low synchronous reset
    PSEL         : out std_ulogic;                                  -- slave select
    PENABLE      : out std_ulogic;                                  -- ACCESS phase
    PADDR        : out std_ulogic_vector(ADDR_W - 1 downto 0);      -- byte address
    PWRITE       : out std_ulogic;                                  -- 1 = write
    PWDATA       : out std_ulogic_vector(DATA_W - 1 downto 0);      -- write data
    PSTRB        : out std_ulogic_vector(DATA_W / 8 - 1 downto 0);  -- write strobes (0 on reads)
    PPROT        : out std_ulogic_vector(2 downto 0);               -- protection (AxPROT encoding)
    PRDATA       : in  std_ulogic_vector(DATA_W - 1 downto 0);      -- read data
    PREADY       : in  std_ulogic;                                  -- transfer complete
    PSLVERR      : in  std_ulogic;                                  -- transfer failed

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
end entity claude_apb_mst_if;

architecture rtl of claude_apb_mst_if is

  -- Transfer state: IDLE, SETUP, ACCESS.
  type state_t is (ST_IDLE, ST_SETUP, ST_ACCESS);

  signal state_q  : state_t;
  signal gnt_q    : std_ulogic;  -- registered mem_gnt_o: high in IDLE, low in reset
  signal psel_q   : std_ulogic;
  signal penable_q: std_ulogic;
  signal accept   : std_ulogic;  -- request handshake this cycle
  signal done     : std_ulogic;  -- ACCESS completes this cycle

begin

  -- Parameter checks (IP_SPEC_sideband.md rule 6)
  assert DATA_W >= 8 and DATA_W <= 32 and DATA_W mod 8 = 0
    report "claude_apb_mst_if: DATA_W = " & integer'image(DATA_W) &
           " out of range (8, 16, 24 or 32)"
    severity failure;
  assert ADDR_W >= 1 and ADDR_W <= 32
    report "claude_apb_mst_if: ADDR_W = " & integer'image(ADDR_W) & " out of range [1, 32]"
    severity failure;

  accept <= mem_req_i and gnt_q;
  done   <= PREADY when state_q = ST_ACCESS else '0';

  -- State machine and the APB control signals.
  p_fsm : process (PCLK) is
  begin
    if rising_edge(PCLK) then
      if PRESETn = '0' then
        state_q   <= ST_IDLE;
        gnt_q     <= '0';
        psel_q    <= '0';
        penable_q <= '0';
      else
        case state_q is
          when ST_IDLE =>
            gnt_q <= '1';
            if accept = '1' then
              state_q <= ST_SETUP;
              gnt_q   <= '0';
              psel_q  <= '1';
            end if;
          when ST_SETUP =>
            state_q   <= ST_ACCESS;
            penable_q <= '1';
          when ST_ACCESS =>
            if PREADY = '1' then
              state_q   <= ST_IDLE;
              gnt_q     <= '1';
              psel_q    <= '0';
              penable_q <= '0';
            end if;
        end case;
      end if;
    end if;
  end process p_fsm;

  -- Address, control and write data: captured at the handshake, held for the
  -- whole transfer (APB4 SETUP-to-ACCESS stability).
  p_payload : process (PCLK) is
  begin
    if rising_edge(PCLK) then
      if PRESETn = '0' then
        PADDR  <= (others => '0');
        PWRITE <= '0';
        PWDATA <= (others => '0');
        PSTRB  <= (others => '0');
        PPROT  <= (others => '0');
      elsif accept = '1' then
        PADDR  <= mem_addr_i;
        PWRITE <= mem_we_i;
        PWDATA <= mem_wdata_i;
        if mem_we_i = '1' then
          PSTRB <= mem_be_i;
        else
          PSTRB <= (others => '0');
        end if;
        PPROT  <= mem_prot_i;
      end if;
    end if;
  end process p_payload;

  -- Response: one-cycle mem_rvalid_o after PREADY, data and error captured.
  p_rsp : process (PCLK) is
  begin
    if rising_edge(PCLK) then
      if PRESETn = '0' then
        mem_rvalid_o <= '0';
        mem_rdata_o  <= (others => '0');
        mem_err_o    <= '0';
      else
        mem_rvalid_o <= done;
        if done = '1' then
          mem_rdata_o <= PRDATA;
          mem_err_o   <= PSLVERR;
        end if;
      end if;
    end if;
  end process p_rsp;

  PSEL      <= psel_q;
  PENABLE   <= penable_q;
  mem_gnt_o <= gnt_q;

end architecture rtl;
