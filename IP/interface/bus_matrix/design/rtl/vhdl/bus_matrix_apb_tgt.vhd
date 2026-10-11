-- bus_matrix_apb_tgt.vhd — APB4 target adapter for one bus matrix master port (VHDL-2008).
--
-- Acts as an APB4 slave towards the external master. The ACCESS phase
-- (PSEL and PENABLE) is the core request; the master holds it, with address,
-- control and write data stable, until PREADY. PREADY and PSLVERR are the
-- core's done and err, so the ACCESS phase lasts as long as the routed
-- transaction (including any wait for arbitration).
--
-- Purely combinational: APB4 already holds every request field for the
-- whole transfer. Mirrors bus_matrix_apb_tgt.sv.

library ieee;
use ieee.std_logic_1164.all;

entity bus_matrix_apb_tgt is
  generic (
    DATA_W : positive := 32;  -- data bus width
    ADDR_W : positive := 32   -- address width
  );
  port (
    -- APB4 slave interface (towards the external master)
    PSEL    : in  std_ulogic;                                 -- slave select
    PENABLE : in  std_ulogic;                                 -- ACCESS phase
    PADDR   : in  std_ulogic_vector(ADDR_W - 1 downto 0);     -- byte address
    PWRITE  : in  std_ulogic;                                 -- 1 = write
    PWDATA  : in  std_ulogic_vector(DATA_W - 1 downto 0);     -- write data
    PSTRB   : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0); -- byte strobes
    PRDATA  : out std_ulogic_vector(DATA_W - 1 downto 0);     -- read data
    PREADY  : out std_ulogic;                                 -- transfer done
    PSLVERR : out std_ulogic;                                 -- 1 = error

    -- Core handshake
    core_req     : out std_ulogic;                                 -- request held until done
    core_addr    : out std_ulogic_vector(ADDR_W - 1 downto 0);     -- byte address
    core_wdata   : out std_ulogic_vector(DATA_W - 1 downto 0);     -- write data
    core_we      : out std_ulogic;                                 -- 1 = write
    core_be      : out std_ulogic_vector(DATA_W / 8 - 1 downto 0); -- byte enables
    core_done    : in  std_ulogic;                                 -- one-cycle completion
    core_rdata   : in  std_ulogic_vector(DATA_W - 1 downto 0);     -- read data (valid with done)
    core_err     : in  std_ulogic                                  -- error (valid with done)
  );
end entity bus_matrix_apb_tgt;

architecture rtl of bus_matrix_apb_tgt is
begin

  core_req   <= PSEL and PENABLE;
  core_addr  <= PADDR;
  core_wdata <= PWDATA;
  core_we    <= PWRITE;
  core_be    <= PSTRB;

  PREADY  <= core_done;
  PSLVERR <= core_done and core_err;
  PRDATA  <= core_rdata;

end architecture rtl;
