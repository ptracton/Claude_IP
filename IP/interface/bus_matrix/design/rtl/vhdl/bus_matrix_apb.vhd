-- bus_matrix_apb.vhd — APB4 bus matrix top-level (VHDL-2008).
--
-- Crossbar interconnect connecting NUM_MASTERS APB4 masters to
-- NUM_SLAVES APB4 slaves. All configuration (address map, arbitration
-- mode, priorities) is set via generics; there are no runtime registers.
-- The defaults (bus_matrix_pkg) are the synthesized configuration.
--
-- Structure: one bus_matrix_apb_tgt per master port, one bus_matrix_apb_ini per slave
-- port, and the protocol-agnostic bus_matrix_core between them. Ports are
-- flat-packed: master i / slave j occupy (i*W+W-1 downto i*W) / (j*W+W-1
-- downto j*W). Mirrors bus_matrix_apb.sv.

library ieee;
use ieee.std_logic_1164.all;

use work.bus_matrix_pkg.all;

entity bus_matrix_apb is
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
    clk       : in  std_ulogic;                                               -- system clock
    rst_n     : in  std_ulogic;                                               -- synchronous active-low reset

    M_PSEL    : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i PSEL
    M_PENABLE : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i PENABLE
    M_PADDR   : in  std_ulogic_vector(NUM_MASTERS * ADDR_W - 1 downto 0);     -- master i PADDR
    M_PWRITE  : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i PWRITE
    M_PWDATA  : in  std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);     -- master i PWDATA
    M_PSTRB   : in  std_ulogic_vector(NUM_MASTERS * DATA_W / 8 - 1 downto 0); -- master i PSTRB
    M_PRDATA  : out std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);     -- master i PRDATA
    M_PREADY  : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i PREADY
    M_PSLVERR : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i PSLVERR

    S_PSEL    : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);               -- slave j PSEL
    S_PENABLE : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);               -- slave j PENABLE
    S_PADDR   : out std_ulogic_vector(NUM_SLAVES * ADDR_W - 1 downto 0);      -- slave j PADDR
    S_PWRITE  : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);               -- slave j PWRITE
    S_PWDATA  : out std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);      -- slave j PWDATA
    S_PSTRB   : out std_ulogic_vector(NUM_SLAVES * DATA_W / 8 - 1 downto 0);  -- slave j PSTRB
    S_PRDATA  : in  std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);      -- slave j PRDATA
    S_PREADY  : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0);               -- slave j PREADY
    S_PSLVERR : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0)                -- slave j PSLVERR
  );
end entity bus_matrix_apb;

architecture rtl of bus_matrix_apb is

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
    u_tgt : entity work.bus_matrix_apb_tgt(rtl)
      generic map (
        DATA_W => DATA_W,
        ADDR_W => ADDR_W
      )
      port map (
        PSEL       => M_PSEL(gi),
        PENABLE    => M_PENABLE(gi),
        PADDR      => M_PADDR(gi * ADDR_W + ADDR_W - 1 downto gi * ADDR_W),
        PWRITE     => M_PWRITE(gi),
        PWDATA     => M_PWDATA(gi * DATA_W + DATA_W - 1 downto gi * DATA_W),
        PSTRB      => M_PSTRB(gi * STRB_W + STRB_W - 1 downto gi * STRB_W),
        PRDATA     => M_PRDATA(gi * DATA_W + DATA_W - 1 downto gi * DATA_W),
        PREADY     => M_PREADY(gi),
        PSLVERR    => M_PSLVERR(gi),
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
    u_ini : entity work.bus_matrix_apb_ini(rtl)
      generic map (
        DATA_W => DATA_W,
        ADDR_W => ADDR_W
      )
      port map (
        clk        => clk,
        rst_n      => rst_n,
        core_req   => slv_req(gj),
        core_addr  => slv_addr(gj * ADDR_W + ADDR_W - 1 downto gj * ADDR_W),
        core_wdata => slv_wdata(gj * DATA_W + DATA_W - 1 downto gj * DATA_W),
        core_we    => slv_we(gj),
        core_be    => slv_be(gj * STRB_W + STRB_W - 1 downto gj * STRB_W),
        core_done  => slv_done(gj),
        core_rdata => slv_rdata(gj * DATA_W + DATA_W - 1 downto gj * DATA_W),
        core_err   => slv_err(gj),
        PSEL       => S_PSEL(gj),
        PENABLE    => S_PENABLE(gj),
        PADDR      => S_PADDR(gj * ADDR_W + ADDR_W - 1 downto gj * ADDR_W),
        PWRITE     => S_PWRITE(gj),
        PWDATA     => S_PWDATA(gj * DATA_W + DATA_W - 1 downto gj * DATA_W),
        PSTRB      => S_PSTRB(gj * STRB_W + STRB_W - 1 downto gj * STRB_W),
        PRDATA     => S_PRDATA(gj * DATA_W + DATA_W - 1 downto gj * DATA_W),
        PREADY     => S_PREADY(gj),
        PSLVERR    => S_PSLVERR(gj)
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
