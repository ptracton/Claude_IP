-- claude_apb_mem_if.vhd — APB4 slave to Claude memory bus adapter (shared component).
--
-- VHDL-2008 twin of claude_apb_mem_if.sv; behaviour is identical.
-- Turns APB4 transfers into requests on the Claude memory bus (mem_*), for
-- memory-like targets that may stall and may report errors. The bus rules
-- are in IP/common/design/rtl/mem_bus.md. Register-file IP keeps using
-- claude_apb_if; this adapter is for memories.
--
-- Protocol notes:
--   The request is raised in the SETUP phase (APB4 holds PADDR, PWRITE,
--   PWDATA and PSTRB stable from SETUP to the end of ACCESS), so a target
--   that grants at once and answers the next cycle gives a zero-wait
--   transfer. A slower target stretches ACCESS with PREADY low.
--   PREADY is the memory response (mem_rvalid_i); PSLVERR is mem_err_i in
--   that same cycle. PRDATA is mem_rdata_i.
--   Byte enables: PSTRB on writes, all ones on reads.
--   PENABLE is part of the APB4 port but not needed: the request is issued
--   from SETUP and completion is signalled by PREADY alone.
--
-- Generics:
--   DATA_W : data bus width, multiple of 8 (default 32)
--   ADDR_W : byte address width             (default 32)

library ieee;
use ieee.std_logic_1164.all;

entity claude_apb_mem_if is
  generic (
    DATA_W : positive := 32;
    ADDR_W : positive := 32
  );
  port (
    -- APB4 bus signals
    PCLK         : in  std_ulogic;
    PRESETn      : in  std_ulogic;
    PSEL         : in  std_ulogic;
    PENABLE      : in  std_ulogic;
    PADDR        : in  std_ulogic_vector(ADDR_W - 1 downto 0);
    PWRITE       : in  std_ulogic;
    PWDATA       : in  std_ulogic_vector(DATA_W - 1 downto 0);
    PSTRB        : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0);
    PRDATA       : out std_ulogic_vector(DATA_W - 1 downto 0);
    PREADY       : out std_ulogic;
    PSLVERR      : out std_ulogic;

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
end entity claude_apb_mem_if;

architecture rtl of claude_apb_mem_if is

  -- A request has been granted and its response has not arrived yet.
  signal pending_q : std_ulogic;
  -- Internal copy of mem_req_o (read back by p_pending).
  signal mem_req   : std_ulogic;

begin

  p_pending : process (PCLK) is
  begin
    if rising_edge(PCLK) then
      if PRESETn = '0' then
        pending_q <= '0';
      elsif mem_req = '1' and mem_gnt_i = '1' then
        pending_q <= '1';
      elsif mem_rvalid_i = '1' then
        pending_q <= '0';
      end if;
    end if;
  end process p_pending;

  -- Request: from SETUP until granted. pending_q is still high in the
  -- response cycle, so a completed transfer is never issued twice.
  mem_req     <= PSEL and not pending_q;
  mem_req_o   <= mem_req;
  mem_we_o    <= PWRITE;
  mem_addr_o  <= PADDR;
  mem_be_o    <= PSTRB when PWRITE = '1' else (others => '1');
  mem_wdata_o <= PWDATA;

  -- Response
  PREADY  <= mem_rvalid_i and pending_q;
  PSLVERR <= mem_rvalid_i and pending_q and mem_err_i;
  PRDATA  <= mem_rdata_i;

end architecture rtl;
