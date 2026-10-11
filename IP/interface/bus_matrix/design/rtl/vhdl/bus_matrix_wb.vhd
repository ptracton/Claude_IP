-- bus_matrix_wb.vhd — Wishbone B4 bus matrix top-level (VHDL-2008).
--
-- Crossbar interconnect connecting NUM_MASTERS Wishbone B4 (classic) masters to
-- NUM_SLAVES Wishbone B4 (classic) slaves. All configuration (address map, arbitration
-- mode, priorities) is set via generics; there are no runtime registers.
-- The defaults (bus_matrix_pkg) are the synthesized configuration.
--
-- Structure: one bus_matrix_wb_tgt per master port, one bus_matrix_wb_ini per slave
-- port, and the protocol-agnostic bus_matrix_core between them. Ports are
-- flat-packed: master i / slave j occupy (i*W+W-1 downto i*W) / (j*W+W-1
-- downto j*W). Mirrors bus_matrix_wb.sv.

library ieee;
use ieee.std_logic_1164.all;

use work.bus_matrix_pkg.all;

entity bus_matrix_wb is
  generic (
    NUM_MASTERS : positive := BM_NUM_MASTERS;  -- 1-16 active masters
    NUM_SLAVES  : positive := BM_NUM_SLAVES;   -- 1-32 active slaves
    DATA_W      : positive := 32;              -- data bus width
    ADDR_W      : positive := 32;              -- address width (must be 32)
    ARB_MODE    : natural  := BM_ARB_MODE;     -- 0=fixed-priority, 1=round-robin
    M_PRIORITY  : std_ulogic_vector(16 * 4 - 1 downto 0)  := BM_M_PRIORITY;  -- master i at (i*4+3 downto i*4)
    S_BASE      : std_ulogic_vector(32 * 32 - 1 downto 0) := BM_S_BASE;      -- slave j at (j*32+31 downto j*32)
    S_MASK      : std_ulogic_vector(32 * 32 - 1 downto 0) := BM_S_MASK       -- slave j at (j*32+31 downto j*32)
  );
  port (
    clk     : in  std_ulogic;                                               -- system clock
    rst_n   : in  std_ulogic;                                               -- synchronous active-low reset

    M_CYC   : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i CYC
    M_STB   : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i STB
    M_WE    : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i WE
    M_ADR   : in  std_ulogic_vector(NUM_MASTERS * ADDR_W - 1 downto 0);     -- master i ADR
    M_DAT_I : in  std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);     -- master i DAT_I
    M_SEL   : in  std_ulogic_vector(NUM_MASTERS * DATA_W / 8 - 1 downto 0); -- master i SEL
    M_DAT_O : out std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);     -- master i DAT_O
    M_ACK   : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i ACK
    M_ERR   : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i ERR

    S_CYC   : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);               -- slave j CYC
    S_STB   : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);               -- slave j STB
    S_WE    : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);               -- slave j WE
    S_ADR   : out std_ulogic_vector(NUM_SLAVES * ADDR_W - 1 downto 0);      -- slave j ADR
    S_DAT_O : out std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);      -- slave j DAT_O
    S_SEL   : out std_ulogic_vector(NUM_SLAVES * DATA_W / 8 - 1 downto 0);  -- slave j SEL
    S_DAT_I : in  std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);      -- slave j DAT_I
    S_ACK   : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0);               -- slave j ACK
    S_ERR   : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0)                -- slave j ERR
  );
end entity bus_matrix_wb;

architecture rtl of bus_matrix_wb is

  constant STRB_W : positive := DATA_W / 8;

  -- Core handshake
  signal mst_req   : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
  signal mst_addr  : std_ulogic_vector(NUM_MASTERS * ADDR_W - 1 downto 0);
  signal mst_wdata : std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);
  signal mst_we    : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
  signal mst_be    : std_ulogic_vector(NUM_MASTERS * STRB_W - 1 downto 0);
  signal mst_done  : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
  signal mst_rdata : std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);
  signal mst_err   : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
  signal slv_req   : std_ulogic_vector(NUM_SLAVES - 1 downto 0);
  signal slv_addr  : std_ulogic_vector(NUM_SLAVES * ADDR_W - 1 downto 0);
  signal slv_wdata : std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);
  signal slv_we    : std_ulogic_vector(NUM_SLAVES - 1 downto 0);
  signal slv_be    : std_ulogic_vector(NUM_SLAVES * STRB_W - 1 downto 0);
  signal slv_done  : std_ulogic_vector(NUM_SLAVES - 1 downto 0);
  signal slv_rdata : std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);
  signal slv_err   : std_ulogic_vector(NUM_SLAVES - 1 downto 0);

begin

  -- -------------------------------------------------------------------------
  -- Master ports
  -- -------------------------------------------------------------------------
  gen_mst : for gi in 0 to NUM_MASTERS - 1 generate
    u_tgt : entity work.bus_matrix_wb_tgt(rtl)
      generic map (
        DATA_W => DATA_W,
        ADDR_W => ADDR_W
      )
      port map (
        CYC        => M_CYC(gi),
        STB        => M_STB(gi),
        WE         => M_WE(gi),
        ADR        => M_ADR(gi * ADDR_W + ADDR_W - 1 downto gi * ADDR_W),
        DAT_W      => M_DAT_I(gi * DATA_W + DATA_W - 1 downto gi * DATA_W),
        SEL        => M_SEL(gi * STRB_W + STRB_W - 1 downto gi * STRB_W),
        DAT_R      => M_DAT_O(gi * DATA_W + DATA_W - 1 downto gi * DATA_W),
        ACK        => M_ACK(gi),
        ERR        => M_ERR(gi),
        core_req   => mst_req(gi),
        core_addr  => mst_addr(gi * ADDR_W + ADDR_W - 1 downto gi * ADDR_W),
        core_wdata => mst_wdata(gi * DATA_W + DATA_W - 1 downto gi * DATA_W),
        core_we    => mst_we(gi),
        core_be    => mst_be(gi * STRB_W + STRB_W - 1 downto gi * STRB_W),
        core_done  => mst_done(gi),
        core_rdata => mst_rdata(gi * DATA_W + DATA_W - 1 downto gi * DATA_W),
        core_err   => mst_err(gi)
      );
  end generate gen_mst;

  -- -------------------------------------------------------------------------
  -- Slave ports
  -- -------------------------------------------------------------------------
  gen_slv : for gj in 0 to NUM_SLAVES - 1 generate
    u_ini : entity work.bus_matrix_wb_ini(rtl)
      generic map (
        DATA_W => DATA_W,
        ADDR_W => ADDR_W
      )
      port map (
        core_req   => slv_req(gj),
        core_addr  => slv_addr(gj * ADDR_W + ADDR_W - 1 downto gj * ADDR_W),
        core_wdata => slv_wdata(gj * DATA_W + DATA_W - 1 downto gj * DATA_W),
        core_we    => slv_we(gj),
        core_be    => slv_be(gj * STRB_W + STRB_W - 1 downto gj * STRB_W),
        core_done  => slv_done(gj),
        core_rdata => slv_rdata(gj * DATA_W + DATA_W - 1 downto gj * DATA_W),
        core_err   => slv_err(gj),
        CYC        => S_CYC(gj),
        STB        => S_STB(gj),
        WE         => S_WE(gj),
        ADR        => S_ADR(gj * ADDR_W + ADDR_W - 1 downto gj * ADDR_W),
        DAT_W      => S_DAT_O(gj * DATA_W + DATA_W - 1 downto gj * DATA_W),
        SEL        => S_SEL(gj * STRB_W + STRB_W - 1 downto gj * STRB_W),
        DAT_R      => S_DAT_I(gj * DATA_W + DATA_W - 1 downto gj * DATA_W),
        ACK        => S_ACK(gj),
        ERR        => S_ERR(gj)
      );
  end generate gen_slv;

  -- -------------------------------------------------------------------------
  -- Crossbar core
  -- -------------------------------------------------------------------------
  u_core : entity work.bus_matrix_core(rtl)
    generic map (
      NUM_MASTERS => NUM_MASTERS,
      NUM_SLAVES  => NUM_SLAVES,
      DATA_W      => DATA_W,
      ADDR_W      => ADDR_W,
      ARB_MODE    => ARB_MODE,
      M_PRIORITY  => M_PRIORITY,
      S_BASE      => S_BASE,
      S_MASK      => S_MASK
    )
    port map (
      clk       => clk,
      rst_n     => rst_n,
      mst_req   => mst_req,
      mst_addr  => mst_addr,
      mst_wdata => mst_wdata,
      mst_we    => mst_we,
      mst_be    => mst_be,
      mst_done  => mst_done,
      mst_rdata => mst_rdata,
      mst_err   => mst_err,
      slv_req   => slv_req,
      slv_addr  => slv_addr,
      slv_wdata => slv_wdata,
      slv_we    => slv_we,
      slv_be    => slv_be,
      slv_done  => slv_done,
      slv_rdata => slv_rdata,
      slv_err   => slv_err
    );

end architecture rtl;
