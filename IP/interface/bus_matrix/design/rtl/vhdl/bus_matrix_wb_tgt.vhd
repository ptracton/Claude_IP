-- bus_matrix_wb_tgt.vhd — Wishbone B4 (classic) target adapter for one bus matrix master port (VHDL-2008).
--
-- Acts as a Wishbone slave towards the external master. CYC and STB is the
-- core request; the master holds it, with address, data and selects stable,
-- until ACK or ERR. ACK/ERR are the core's done split by err. A master that
-- keeps STB high after a termination starts a new transfer (classic
-- back-to-back).
--
-- Not supported: aborting a transfer by dropping CYC/STB before ACK/ERR.
-- Purely combinational. Mirrors bus_matrix_wb_tgt.sv.

library ieee;
use ieee.std_logic_1164.all;

entity bus_matrix_wb_tgt is
  generic (
    DATA_W : positive := 32;  -- data bus width
    ADDR_W : positive := 32   -- address width
  );
  port (
    -- Wishbone slave interface (towards the external master)
    CYC   : in  std_ulogic;                                 -- bus cycle
    STB   : in  std_ulogic;                                 -- strobe
    WE    : in  std_ulogic;                                 -- 1 = write
    ADR   : in  std_ulogic_vector(ADDR_W - 1 downto 0);     -- byte address
    DAT_W : in  std_ulogic_vector(DATA_W - 1 downto 0);     -- write data (master -> matrix)
    SEL   : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0); -- byte selects
    DAT_R : out std_ulogic_vector(DATA_W - 1 downto 0);     -- read data (matrix -> master)
    ACK   : out std_ulogic;                                 -- normal termination
    ERR   : out std_ulogic;                                 -- error termination

    -- Core handshake
    core_req   : out std_ulogic;                                 -- request held until done
    core_addr  : out std_ulogic_vector(ADDR_W - 1 downto 0);     -- byte address
    core_wdata : out std_ulogic_vector(DATA_W - 1 downto 0);     -- write data
    core_we    : out std_ulogic;                                 -- 1 = write
    core_be    : out std_ulogic_vector(DATA_W / 8 - 1 downto 0); -- byte enables
    core_done  : in  std_ulogic;                                 -- one-cycle completion
    core_rdata : in  std_ulogic_vector(DATA_W - 1 downto 0);     -- read data (valid with done)
    core_err   : in  std_ulogic                                  -- error (valid with done)
  );
end entity bus_matrix_wb_tgt;

architecture rtl of bus_matrix_wb_tgt is
begin

  core_req   <= CYC and STB;
  core_addr  <= ADR;
  core_wdata <= DAT_W;
  core_we    <= WE;
  core_be    <= SEL;

  ACK   <= core_done and not core_err;
  ERR   <= core_done and core_err;
  DAT_R <= core_rdata;

end architecture rtl;
