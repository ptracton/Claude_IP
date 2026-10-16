-- claude_ahb_mem_if.vhd — AHB-Lite slave to Claude memory bus adapter (shared component).
--
-- VHDL-2008 twin of claude_ahb_mem_if.sv; behaviour is identical.
-- Turns AHB-Lite transfers into requests on the Claude memory bus (mem_*),
-- for memory-like targets that may stall and may report errors. The bus
-- rules are in IP/common/design/rtl/mem_bus.md. Register-file IP keeps using
-- claude_ahb_if; this adapter is for memories.
--
-- Protocol notes:
--   Any burst: NONSEQ and SEQ are both transfers; IDLE and BUSY are not
--   (they get the zero-wait OKAY response). HBURST is not needed.
--   HREADY is the bus-wide ready (input) and HREADYOUT this slave's ready
--   (output). With a single slave, connect HREADY to HREADYOUT.
--   An address phase is accepted when HSEL & HTRANS(1) & HREADY. The memory
--   request is raised in the first data-phase cycle, so every beat has at
--   least one wait state.
--   Byte enables come from HSIZE and HADDR (the naturally aligned lanes of
--   the transfer); on writes they are ANDed with HWSTRB.
--   mem_err_i gives the two-cycle ERROR response.
--
-- Generics:
--   DATA_W : data bus width, multiple of 8 (default 32)
--   ADDR_W : byte address width             (default 32)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity claude_ahb_mem_if is
  generic (
    DATA_W : positive := 32;
    ADDR_W : positive := 32
  );
  port (
    -- AHB-Lite bus signals
    HCLK         : in  std_ulogic;
    HRESETn      : in  std_ulogic;
    HSEL         : in  std_ulogic;
    HADDR        : in  std_ulogic_vector(ADDR_W - 1 downto 0);
    HTRANS       : in  std_ulogic_vector(1 downto 0);
    HWRITE       : in  std_ulogic;
    HSIZE        : in  std_ulogic_vector(2 downto 0);
    HWDATA       : in  std_ulogic_vector(DATA_W - 1 downto 0);
    HWSTRB       : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0);
    HREADY       : in  std_ulogic;
    HRDATA       : out std_ulogic_vector(DATA_W - 1 downto 0);
    HREADYOUT    : out std_ulogic;
    HRESP        : out std_ulogic;

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
end entity claude_ahb_mem_if;

architecture rtl of claude_ahb_mem_if is

  constant STRB_W_C : positive := DATA_W / 8;

  -- Width of the byte offset within a bus word (at least 1 bit so the
  -- vectors below stay legal when DATA_W = 8).
  function offset_width(strb_w : positive) return positive is
    variable width : positive := 1;
  begin
    while (2 ** width) < strb_w loop
      width := width + 1;
    end loop;
    return width;
  end function offset_width;

  constant OFF_W_C : positive := offset_width(STRB_W_C);

  -- Byte lanes covered by a transfer of 2**size bytes at byte offset
  -- `offset`: lane b is enabled when it lies in the same naturally aligned
  -- 2**size-byte block as the address. Sizes of a full word or more enable
  -- every lane.
  function lane_mask(
    size   : std_ulogic_vector(2 downto 0);
    offset : std_ulogic_vector(OFF_W_C - 1 downto 0)
  ) return std_ulogic_vector is
    variable mask  : std_ulogic_vector(STRB_W_C - 1 downto 0);
    variable shift : natural;
  begin
    mask  := (others => '0');
    shift := to_integer(unsigned(size));
    for b in 0 to STRB_W_C - 1 loop
      if shift_right(to_unsigned(b, OFF_W_C), shift) =
         shift_right(unsigned(offset), shift) then
        mask(b) := '1';
      end if;
    end loop;
    if STRB_W_C = 1 then
      mask := (others => '1');
    end if;
    return mask;
  end function lane_mask;

  -- Data-phase state machine (see claude_ahb_mem_if.sv for the states).
  type dphase_state_t is (StIdle, StReq, StWait, StErr);

  signal state_d    : dphase_state_t;
  signal state_q    : dphase_state_t;

  signal aphase     : std_ulogic;  -- valid transfer in the address phase
  signal accept     : std_ulogic;  -- address phase accepted this cycle
  signal dp_write_q : std_ulogic;  -- data phase is a write
  signal dp_addr_q  : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal dp_mask_q  : std_ulogic_vector(STRB_W_C - 1 downto 0);

begin

  aphase <= HSEL and HTRANS(1);  -- NONSEQ ("10") or SEQ ("11")
  accept <= aphase and HREADY;

  p_state_comb : process (all) is
  begin
    state_d <= state_q;
    if accept = '1' then
      -- An accepted address phase starts the next data phase. HREADY is
      -- high, so the current data phase (if any) ends in this same cycle.
      state_d <= StReq;
    else
      case state_q is
        -- StIdle: nothing to do until an address phase is accepted.
        when StIdle =>
          null;
        -- StReq: hold the request until the memory grants it.
        when StReq =>
          if mem_gnt_i = '1' then
            state_d <= StWait;
          end if;
        -- StWait: the response ends the data phase, or starts an ERROR response.
        when StWait =>
          if mem_rvalid_i = '1' then
            if mem_err_i = '1' then
              state_d <= StErr;
            else
              state_d <= StIdle;
            end if;
          end if;
        -- StErr: second ERROR cycle (HREADYOUT high), then idle.
        when StErr =>
          state_d <= StIdle;
        when others =>
          state_d <= StIdle;
      end case;
    end if;
  end process p_state_comb;

  p_state_reg : process (HCLK) is
  begin
    if rising_edge(HCLK) then
      if HRESETn = '0' then
        state_q <= StIdle;
      else
        state_q <= state_d;
      end if;
    end if;
  end process p_state_reg;

  -- Address-phase information for the data phase.
  p_dphase_info : process (HCLK) is
  begin
    if rising_edge(HCLK) then
      if HRESETn = '0' then
        dp_write_q <= '0';
        dp_addr_q  <= (others => '0');
        dp_mask_q  <= (others => '0');
      elsif accept = '1' then
        dp_write_q <= HWRITE;
        dp_addr_q  <= HADDR;
        dp_mask_q  <= lane_mask(HSIZE, HADDR(OFF_W_C - 1 downto 0));
      end if;
    end if;
  end process p_dphase_info;

  -- Memory request. HWDATA/HWSTRB are held by the master while HREADYOUT is
  -- low, so they are stable from request to grant.
  mem_req_o   <= '1' when state_q = StReq else '0';
  mem_we_o    <= dp_write_q;
  mem_addr_o  <= dp_addr_q;
  mem_be_o    <= (dp_mask_q and HWSTRB) when dp_write_q = '1' else dp_mask_q;
  mem_wdata_o <= HWDATA;

  -- Bus response
  HREADYOUT <= '1' when (state_q = StIdle) or (state_q = StErr) or
                        (state_q = StWait and mem_rvalid_i = '1' and mem_err_i = '0')
               else '0';
  HRESP     <= '1' when (state_q = StErr) or
                        (state_q = StWait and mem_rvalid_i = '1' and mem_err_i = '1')
               else '0';
  HRDATA    <= mem_rdata_i;

end architecture rtl;
