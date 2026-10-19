-- bus_matrix_ahb_ini.vhd — AHB-Lite initiator adapter for one bus matrix slave port (VHDL-2008).
--
-- Acts as an AHB-Lite master towards the external slave and runs exactly one
-- single transfer for each core request.
--
--   Address phase: presented (HSEL, HTRANS=NONSEQ) while idle and req is
--     high; held until the slave's HREADY is high.
--   Data phase:    HTRANS=IDLE, HWDATA/HWSTRB driven from the core; done
--     pulses in the cycle the slave raises HREADY, with HRDATA and HRESP.
--   HSIZE is rebuilt from core_be (the target adapter's lane mask) and
--     HADDR: the naturally aligned block of 2**k lanes holding the address
--     gives HSIZE = k; any other mask (a full word, or write strobes that do
--     not form that block) gives the bus size, with the lanes in HWSTRB.
--
-- The core keeps req high until done and drops it on the following cycle,
-- so a new address phase is never started for a finished request.
-- Mirrors bus_matrix_ahb_ini.sv.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bus_matrix_ahb_ini is
  generic (
    DATA_W : positive := 32;  -- data bus width
    ADDR_W : positive := 32   -- address width
  );
  port (
    clk    : in  std_ulogic; -- system clock
    rst_n  : in  std_ulogic; -- synchronous active-low reset

    -- Core handshake
    core_req    : in  std_ulogic;                                 -- run one transaction
    core_addr   : in  std_ulogic_vector(ADDR_W - 1 downto 0);     -- byte address
    core_wdata  : in  std_ulogic_vector(DATA_W - 1 downto 0);     -- write data
    core_we     : in  std_ulogic;                                 -- 1 = write
    core_be     : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0); -- byte enables
    core_done   : out std_ulogic;                                 -- one-cycle completion
    core_rdata  : out std_ulogic_vector(DATA_W - 1 downto 0);     -- read data (valid with done)
    core_err    : out std_ulogic;                                 -- error (valid with done)

    -- AHB-Lite master interface (towards the external slave)
    HSEL   : out std_ulogic;                                 -- slave select
    HADDR  : out std_ulogic_vector(ADDR_W - 1 downto 0);     -- byte address
    HTRANS : out std_ulogic_vector(1 downto 0);              -- transfer type
    HWRITE : out std_ulogic;                                 -- 1 = write
    HSIZE  : out std_ulogic_vector(2 downto 0);              -- transfer size, 2**HSIZE bytes
    HWDATA : out std_ulogic_vector(DATA_W - 1 downto 0);     -- write data (data phase)
    HWSTRB : out std_ulogic_vector(DATA_W / 8 - 1 downto 0); -- byte strobes (data phase)
    HRDATA : in  std_ulogic_vector(DATA_W - 1 downto 0);     -- read data
    HREADY : in  std_ulogic;                                 -- transfer done
    HRESP  : in  std_ulogic                                  -- 1 = ERROR
  );
end entity bus_matrix_ahb_ini;

architecture rtl of bus_matrix_ahb_ini is

  constant HTRANS_IDLE   : std_ulogic_vector(1 downto 0) := "00";
  constant HTRANS_NONSEQ : std_ulogic_vector(1 downto 0) := "10";

  constant STRB_W : positive := DATA_W / 8;

  -- ceil(log2(n)).
  function log2(n : positive) return natural is
    variable k : natural := 0;
  begin
    while 2 ** k < n loop
      k := k + 1;
    end loop;
    return k;
  end function log2;

  constant BUS_SIZE : natural := log2(STRB_W);
  -- Byte-offset width (at least 1 bit, as OffW in the SV twin).
  constant OFF_W    : positive := maximum(1, BUS_SIZE);

  -- be_size — HSIZE of a lane mask at byte offset `offset`: k when the mask
  -- is the naturally aligned block of 2**k lanes holding the offset (as the
  -- target adapter built it from the master's HSIZE), otherwise the bus size
  -- (a full mask, or write strobes that do not form such a block).
  function be_size(be : std_ulogic_vector(STRB_W - 1 downto 0); offset : natural)
    return std_ulogic_vector is
    variable size  : natural := BUS_SIZE;
    variable blk   : std_ulogic_vector(STRB_W - 1 downto 0);
    variable base  : natural;
  begin
    for k in 0 to BUS_SIZE - 1 loop
      base := 0;
      while base + 2 ** k <= STRB_W loop
        blk := (others => '0');
        blk(base + 2 ** k - 1 downto base) := (others => '1');
        if be = blk and offset / (2 ** k) = base / (2 ** k) then
          size := k;
        end if;
        base := base + 2 ** k;
      end loop;
    end loop;
    return std_ulogic_vector(to_unsigned(size, 3));
  end function be_size;

  signal dphase_q : std_ulogic;  -- data phase in progress
  signal aphase   : std_ulogic;  -- address phase presented this cycle

begin

  aphase <= core_req and not dphase_q;

  p_dphase : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        dphase_q <= '0';
      elsif HREADY = '1' then
        dphase_q <= aphase;
      end if;
    end if;
  end process p_dphase;

  HSEL   <= aphase;
  HTRANS <= HTRANS_NONSEQ when aphase = '1' else HTRANS_IDLE;
  HADDR  <= core_addr;
  HWRITE <= core_we;
  HSIZE  <= be_size(core_be, to_integer(unsigned(core_addr(OFF_W - 1 downto 0))));
  HWDATA <= core_wdata;
  HWSTRB <= core_be when core_we = '1' else (others => '0');

  core_done  <= dphase_q and HREADY;
  core_rdata <= HRDATA;
  core_err   <= HRESP;

end architecture rtl;
