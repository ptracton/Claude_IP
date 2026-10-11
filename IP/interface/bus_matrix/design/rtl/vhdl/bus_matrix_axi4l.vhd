-- bus_matrix_axi4l.vhd — AXI4-Lite bus matrix top-level (VHDL-2008).
--
-- Crossbar interconnect connecting NUM_MASTERS AXI4-Lite masters to
-- NUM_SLAVES AXI4-Lite slaves. All configuration (address map, arbitration
-- mode, priorities) is set via generics; there are no runtime registers.
-- The defaults (bus_matrix_pkg) are the synthesized configuration.
--
-- Structure: one bus_matrix_axi4l_tgt per master port, one bus_matrix_axi4l_ini per slave
-- port, and the protocol-agnostic bus_matrix_core between them. Ports are
-- flat-packed: master i / slave j occupy (i*W+W-1 downto i*W) / (j*W+W-1
-- downto j*W). Mirrors bus_matrix_axi4l.sv.

library ieee;
use ieee.std_logic_1164.all;

use work.bus_matrix_pkg.all;

entity bus_matrix_axi4l is
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

    M_AWVALID : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i AWVALID
    M_AWREADY : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i AWREADY
    M_AWADDR  : in  std_ulogic_vector(NUM_MASTERS * ADDR_W - 1 downto 0);     -- master i AWADDR
    M_WVALID  : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i WVALID
    M_WREADY  : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i WREADY
    M_WDATA   : in  std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);     -- master i WDATA
    M_WSTRB   : in  std_ulogic_vector(NUM_MASTERS * DATA_W / 8 - 1 downto 0); -- master i WSTRB
    M_BVALID  : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i BVALID
    M_BREADY  : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i BREADY
    M_BRESP   : out std_ulogic_vector(NUM_MASTERS * 2 - 1 downto 0);          -- master i BRESP
    M_ARVALID : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i ARVALID
    M_ARREADY : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i ARREADY
    M_ARADDR  : in  std_ulogic_vector(NUM_MASTERS * ADDR_W - 1 downto 0);     -- master i ARADDR
    M_RVALID  : out std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i RVALID
    M_RREADY  : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);              -- master i RREADY
    M_RDATA   : out std_ulogic_vector(NUM_MASTERS * DATA_W - 1 downto 0);     -- master i RDATA
    M_RRESP   : out std_ulogic_vector(NUM_MASTERS * 2 - 1 downto 0);          -- master i RRESP

    S_AWVALID : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);               -- slave j AWVALID
    S_AWREADY : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0);               -- slave j AWREADY
    S_AWADDR  : out std_ulogic_vector(NUM_SLAVES * ADDR_W - 1 downto 0);      -- slave j AWADDR
    S_WVALID  : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);               -- slave j WVALID
    S_WREADY  : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0);               -- slave j WREADY
    S_WDATA   : out std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);      -- slave j WDATA
    S_WSTRB   : out std_ulogic_vector(NUM_SLAVES * DATA_W / 8 - 1 downto 0);  -- slave j WSTRB
    S_BVALID  : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0);               -- slave j BVALID
    S_BREADY  : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);               -- slave j BREADY
    S_BRESP   : in  std_ulogic_vector(NUM_SLAVES * 2 - 1 downto 0);           -- slave j BRESP
    S_ARVALID : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);               -- slave j ARVALID
    S_ARREADY : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0);               -- slave j ARREADY
    S_ARADDR  : out std_ulogic_vector(NUM_SLAVES * ADDR_W - 1 downto 0);      -- slave j ARADDR
    S_RVALID  : in  std_ulogic_vector(NUM_SLAVES - 1 downto 0);               -- slave j RVALID
    S_RREADY  : out std_ulogic_vector(NUM_SLAVES - 1 downto 0);               -- slave j RREADY
    S_RDATA   : in  std_ulogic_vector(NUM_SLAVES * DATA_W - 1 downto 0);      -- slave j RDATA
    S_RRESP   : in  std_ulogic_vector(NUM_SLAVES * 2 - 1 downto 0)            -- slave j RRESP
  );
end entity bus_matrix_axi4l;

architecture rtl of bus_matrix_axi4l is

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
    u_tgt : entity work.bus_matrix_axi4l_tgt(rtl)
      generic map (
        DATA_W => DATA_W,
        ADDR_W => ADDR_W
      )
      port map (
        clk        => clk,
        rst_n      => rst_n,
        AWVALID    => M_AWVALID(gi),
        AWREADY    => M_AWREADY(gi),
        AWADDR     => M_AWADDR(gi * ADDR_W + ADDR_W - 1 downto gi * ADDR_W),
        WVALID     => M_WVALID(gi),
        WREADY     => M_WREADY(gi),
        WDATA      => M_WDATA(gi * DATA_W + DATA_W - 1 downto gi * DATA_W),
        WSTRB      => M_WSTRB(gi * STRB_W + STRB_W - 1 downto gi * STRB_W),
        BVALID     => M_BVALID(gi),
        BREADY     => M_BREADY(gi),
        BRESP      => M_BRESP(gi * 2 + 1 downto gi * 2),
        ARVALID    => M_ARVALID(gi),
        ARREADY    => M_ARREADY(gi),
        ARADDR     => M_ARADDR(gi * ADDR_W + ADDR_W - 1 downto gi * ADDR_W),
        RVALID     => M_RVALID(gi),
        RREADY     => M_RREADY(gi),
        RDATA      => M_RDATA(gi * DATA_W + DATA_W - 1 downto gi * DATA_W),
        RRESP      => M_RRESP(gi * 2 + 1 downto gi * 2),
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
    u_ini : entity work.bus_matrix_axi4l_ini(rtl)
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
        AWVALID    => S_AWVALID(gj),
        AWREADY    => S_AWREADY(gj),
        AWADDR     => S_AWADDR(gj * ADDR_W + ADDR_W - 1 downto gj * ADDR_W),
        WVALID     => S_WVALID(gj),
        WREADY     => S_WREADY(gj),
        WDATA      => S_WDATA(gj * DATA_W + DATA_W - 1 downto gj * DATA_W),
        WSTRB      => S_WSTRB(gj * STRB_W + STRB_W - 1 downto gj * STRB_W),
        BVALID     => S_BVALID(gj),
        BREADY     => S_BREADY(gj),
        BRESP      => S_BRESP(gj * 2 + 1 downto gj * 2),
        ARVALID    => S_ARVALID(gj),
        ARREADY    => S_ARREADY(gj),
        ARADDR     => S_ARADDR(gj * ADDR_W + ADDR_W - 1 downto gj * ADDR_W),
        RVALID     => S_RVALID(gj),
        RREADY     => S_RREADY(gj),
        RDATA      => S_RDATA(gj * DATA_W + DATA_W - 1 downto gj * DATA_W),
        RRESP      => S_RRESP(gj * 2 + 1 downto gj * 2)
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
