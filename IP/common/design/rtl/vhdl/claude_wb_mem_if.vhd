-- claude_wb_mem_if.vhd — Wishbone B4 slave to Claude memory bus adapter (shared component).
--
-- VHDL-2008 twin of claude_wb_mem_if.sv; behaviour is identical.
-- Turns Wishbone B4 classic cycles into requests on the Claude memory bus
-- (mem_*), for memory-like targets that may stall and may report errors.
-- The bus rules are in IP/common/design/rtl/mem_bus.md. Register-file IP
-- keeps using claude_wb_if; this adapter is for memories.
--
-- Protocol notes:
--   Classic (non-pipelined) cycles: the master holds CYC_I/STB_I and the
--   request fields until ACK_O or ERR_O. Aborting a cycle (dropping
--   CYC_I/STB_I before termination) is not supported.
--   The request is raised in the first STB_I cycle. ACK_O / ERR_O is the
--   memory response (mem_rvalid_i, with mem_err_i choosing which).
--   A master may start the next transfer right after the termination cycle
--   by keeping STB_I high; it is issued as a new request.
--   Byte enables: SEL_I for reads and writes.
--
-- Generics:
--   DATA_W : data bus width, multiple of 8 (default 32)
--   ADDR_W : byte address width             (default 32)

library ieee;
use ieee.std_logic_1164.all;

entity claude_wb_mem_if is
  generic (
    DATA_W : positive := 32;
    ADDR_W : positive := 32
  );
  port (
    -- Wishbone B4 signals
    CLK_I        : in  std_ulogic;
    RST_I        : in  std_ulogic;
    CYC_I        : in  std_ulogic;
    STB_I        : in  std_ulogic;
    WE_I         : in  std_ulogic;
    ADR_I        : in  std_ulogic_vector(ADDR_W - 1 downto 0);
    DAT_I        : in  std_ulogic_vector(DATA_W - 1 downto 0);
    SEL_I        : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0);
    DAT_O        : out std_ulogic_vector(DATA_W - 1 downto 0);
    ACK_O        : out std_ulogic;
    ERR_O        : out std_ulogic;

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
end entity claude_wb_mem_if;

architecture rtl of claude_wb_mem_if is

  -- A request has been granted and its response has not arrived yet.
  signal pending_q : std_ulogic;
  -- Internal copy of mem_req_o (read back by p_pending).
  signal mem_req   : std_ulogic;

begin

  p_pending : process (CLK_I) is
  begin
    if rising_edge(CLK_I) then
      if RST_I = '1' then
        pending_q <= '0';
      elsif mem_req = '1' and mem_gnt_i = '1' then
        pending_q <= '1';
      elsif mem_rvalid_i = '1' then
        pending_q <= '0';
      end if;
    end if;
  end process p_pending;

  -- Request: from the first STB_I cycle until granted. pending_q is still
  -- high in the termination cycle, so a finished transfer is never issued
  -- twice.
  mem_req     <= CYC_I and STB_I and not pending_q;
  mem_req_o   <= mem_req;
  mem_we_o    <= WE_I;
  mem_addr_o  <= ADR_I;
  mem_be_o    <= SEL_I;
  mem_wdata_o <= DAT_I;

  -- Response
  ACK_O <= mem_rvalid_i and pending_q and not mem_err_i;
  ERR_O <= mem_rvalid_i and pending_q and mem_err_i;
  DAT_O <= mem_rdata_i;

end architecture rtl;
