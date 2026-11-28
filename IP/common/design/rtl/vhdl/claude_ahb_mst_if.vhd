-- claude_ahb_mst_if.vhd — Claude memory bus to AHB-Lite master adapter (shared component).
--
-- VHDL-2008 twin of claude_ahb_mst_if.sv; behaviour is identical.
-- Takes requests on the Claude memory bus (mem_*, the adapter is the target)
-- and issues them as single AHB-Lite master transfers. The bus rules are in
-- .agents/IP_SPEC_mem_bus.md (rules 1-5) and .agents/IP_SPEC_mem_bus_initiator.md
-- (rules 6-9, mem_prot, timing).
--
-- Protocol notes (see the SV file for the full list):
--   HTRANS = NONSEQ for the address phase, then IDLE; HBURST = SINGLE, HMASTLOCK = 0.
--   Zero-wait slave: mem_rvalid_o in cycle 3, one transfer per 4 cycles.
--   Aligned power-of-two byte enables: HADDR = mem_addr_i, HSIZE = log2(bytes);
--   other write patterns: full width at the word-aligned address, HWSTRB selects.
--   HAS_HWSTRB = 0: HWSTRB driven all ones, and a non-aligned write pattern is
--   answered with mem_err_o in the next cycle without a bus access (rule 8).
--   HPROT = {0, 0, mem_prot_i(0), not mem_prot_i(2)}; HNONSEC = mem_prot_i(1) when
--   HAS_HNONSEC = 1. HRESP ERROR -> mem_err_o. All outputs registered. Bus idle and
--   mem_gnt_o = 0 in reset. No DFT ports.
--
-- Generics:
--   DATA_W      : data width, a power of two, 8..1024 (default 32)
--   ADDR_W      : byte address width, 1..64 (default 32)
--   HAS_HWSTRB  : 1 = drive HWSTRB, any write pattern (default 1)
--   HAS_HNONSEC : 1 = drive HNONSEC from mem_prot_i(1) (default 0)
--   (integers, not booleans, so SV and VHDL instances map one to one)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity claude_ahb_mst_if is
  generic (
    DATA_W      : positive := 32;     -- data bus width (power of two, 8..1024)
    ADDR_W      : positive := 32;     -- byte address width (1..64)
    HAS_HWSTRB  : natural  := 1;      -- 1 = AHB5 write strobes (0 or 1)
    HAS_HNONSEC : natural  := 0       -- 1 = AHB5 HNONSEC (0 or 1)
  );
  port (
    -- AHB-Lite bus signals (master side)
    HCLK         : in  std_ulogic;                                  -- AHB clock
    HRESETn      : in  std_ulogic;                                  -- active-low synchronous reset
    HADDR        : out std_ulogic_vector(ADDR_W - 1 downto 0);      -- byte address
    HTRANS       : out std_ulogic_vector(1 downto 0);               -- IDLE (00) or NONSEQ (10)
    HWRITE       : out std_ulogic;                                  -- 1 = write
    HSIZE        : out std_ulogic_vector(2 downto 0);               -- 2**HSIZE bytes
    HBURST       : out std_ulogic_vector(2 downto 0);               -- SINGLE
    HPROT        : out std_ulogic_vector(3 downto 0);               -- protection
    HMASTLOCK    : out std_ulogic;                                  -- 0
    HNONSEC      : out std_ulogic;                                  -- AHB5 non-secure
    HWDATA       : out std_ulogic_vector(DATA_W - 1 downto 0);      -- write data (data phase)
    HWSTRB       : out std_ulogic_vector(DATA_W / 8 - 1 downto 0);  -- write strobes (data phase)
    HRDATA       : in  std_ulogic_vector(DATA_W - 1 downto 0);      -- read data
    HREADY       : in  std_ulogic;                                  -- transfer complete / bus ready
    HRESP        : in  std_ulogic;                                  -- 0 = OKAY, 1 = ERROR

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
end entity claude_ahb_mst_if;

architecture rtl of claude_ahb_mst_if is

  constant STRB_W : positive := DATA_W / 8;

  -- ceil(log2(n)) for 1 <= n <= 2**16 (static loop bound, synthesizable on signals)
  function clog2(n : positive) return natural is
  begin
    for i in 0 to 16 loop
      if 2 ** i >= n then
        return i;
      end if;
    end loop;
    return 16;
  end function;

  function is_pow2(n : positive) return boolean is
  begin
    return 2 ** clog2(n) = n;
  end function;

  -- Naturally aligned power-of-two block of byte lanes?
  function be_aligned(be : std_ulogic_vector) return boolean is
    variable lo  : natural := be'length;
    variable n   : natural := 0;
    variable gap : boolean := false;
    variable ok  : boolean := true;
  begin
    for b in 0 to be'length - 1 loop
      if be(be'low + b) = '1' then
        if lo = be'length then
          lo := b;
        end if;
        if gap then
          ok := false;
        end if;
        n := n + 1;
      elsif lo /= be'length then
        gap := true;
      end if;
    end loop;
    if n = 0 then
      return false;
    end if;
    return ok and is_pow2(n) and (lo mod n) = 0;
  end function;

  function be_size(be : std_ulogic_vector) return std_ulogic_vector is
    variable n : natural := 0;
  begin
    for b in be'range loop
      if be(b) = '1' then
        n := n + 1;
      end if;
    end loop;
    if n = 0 then
      return "000";
    end if;
    return std_ulogic_vector(to_unsigned(clog2(n), 3));
  end function;

  constant FULL_SZ : std_ulogic_vector(2 downto 0) := std_ulogic_vector(to_unsigned(clog2(STRB_W), 3));
  constant TR_IDLE : std_ulogic_vector(1 downto 0) := "00";
  constant TR_NSEQ : std_ulogic_vector(1 downto 0) := "10";
  -- Mask that clears the byte-offset bits of an address.
  constant OFF_MASK : unsigned(ADDR_W - 1 downto 0) := to_unsigned(STRB_W - 1, ADDR_W);

  type state_t is (ST_IDLE, ST_ADDR, ST_DATA);

  signal state_q : state_t;
  signal gnt_q   : std_ulogic;  -- registered mem_gnt_o: high in IDLE, low in reset
  signal accept  : std_ulogic;  -- request handshake this cycle
  signal aligned : boolean;     -- byte enables are an aligned block
  signal illegal : boolean;     -- rule 8: write pattern the bus cannot carry
  signal done    : std_ulogic;  -- data phase completes this cycle

begin

  -- Parameter checks (IP_SPEC_sideband.md rule 6)
  assert DATA_W >= 8 and DATA_W <= 1024 and is_pow2(DATA_W)
    report "claude_ahb_mst_if: DATA_W = " & integer'image(DATA_W) &
           " out of range (power of two, 8..1024)"
    severity failure;
  assert HAS_HWSTRB <= 1 and HAS_HNONSEC <= 1
    report "claude_ahb_mst_if: HAS_HWSTRB / HAS_HNONSEC must be 0 or 1"
    severity failure;
  assert ADDR_W >= 1 and ADDR_W <= 64
    report "claude_ahb_mst_if: ADDR_W = " & integer'image(ADDR_W) & " out of range [1, 64]"
    severity failure;

  accept  <= mem_req_i and gnt_q;
  aligned <= be_aligned(mem_be_i);
  illegal <= HAS_HWSTRB = 0 and mem_we_i = '1' and not aligned;
  done    <= HREADY when state_q = ST_DATA else '0';

  -- State machine and HTRANS.
  p_fsm : process (HCLK) is
  begin
    if rising_edge(HCLK) then
      if HRESETn = '0' then
        state_q <= ST_IDLE;
        gnt_q   <= '0';
        HTRANS  <= TR_IDLE;
      else
        case state_q is
          when ST_IDLE =>
            gnt_q <= '1';
            if accept = '1' and not illegal then
              state_q <= ST_ADDR;
              gnt_q   <= '0';
              HTRANS  <= TR_NSEQ;
            end if;
          when ST_ADDR =>
            if HREADY = '1' then      -- address phase accepted
              state_q <= ST_DATA;
              HTRANS  <= TR_IDLE;
            end if;
          when ST_DATA =>
            if HREADY = '1' then      -- data phase complete
              state_q <= ST_IDLE;
              gnt_q   <= '1';
            end if;
        end case;
      end if;
    end if;
  end process p_fsm;

  -- Address phase and data phase payload, captured at the handshake.
  p_payload : process (HCLK) is
  begin
    if rising_edge(HCLK) then
      if HRESETn = '0' then
        HADDR   <= (others => '0');
        HWRITE  <= '0';
        HSIZE   <= "000";
        HPROT   <= "0011";
        HNONSEC <= '0';
        HWDATA  <= (others => '0');
        HWSTRB  <= (others => '0');
      elsif accept = '1' and not illegal then
        HWRITE <= mem_we_i;
        HPROT  <= "00" & mem_prot_i(0) & (not mem_prot_i(2));
        if HAS_HNONSEC = 1 then
          HNONSEC <= mem_prot_i(1);
        else
          HNONSEC <= '0';
        end if;
        HWDATA <= mem_wdata_i;
        if aligned then
          HADDR <= mem_addr_i;
          HSIZE <= be_size(mem_be_i);
        else
          -- Sparse write (HAS_HWSTRB only): full width at the aligned address.
          HADDR <= std_ulogic_vector(unsigned(mem_addr_i) and not OFF_MASK);
          HSIZE <= FULL_SZ;
        end if;
        if HAS_HWSTRB = 0 then
          HWSTRB <= (others => '1');
        elsif mem_we_i = '1' then
          HWSTRB <= mem_be_i;
        else
          HWSTRB <= (others => '0');
        end if;
      end if;
    end if;
  end process p_payload;

  -- Response: one cycle after the data phase, or after the handshake for an
  -- illegal write pattern (rule 8, no bus access).
  p_rsp : process (HCLK) is
  begin
    if rising_edge(HCLK) then
      if HRESETn = '0' then
        mem_rvalid_o <= '0';
        mem_rdata_o  <= (others => '0');
        mem_err_o    <= '0';
      else
        mem_rvalid_o <= '0';
        if done = '1' then
          mem_rvalid_o <= '1';
          mem_rdata_o  <= HRDATA;
          mem_err_o    <= HRESP;
        elsif accept = '1' and illegal then
          mem_rvalid_o <= '1';
          mem_rdata_o  <= (others => '0');
          mem_err_o    <= '1';
        end if;
      end if;
    end if;
  end process p_rsp;

  HBURST    <= "000";   -- SINGLE
  HMASTLOCK <= '0';
  mem_gnt_o <= gnt_q;

end architecture rtl;
