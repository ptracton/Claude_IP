-- sram_axi4l_dp.vhd — AXI4-Lite dual-port top-level of the sram IP.
--
-- VHDL-2008 twin of sram_axi4l_dp.sv: instantiates claude_axi4l_mem_if (IP/common) per port
-- and sram_core. Contains no logic — only port declarations and submodule
-- wiring. Generics as in sram_axi4l_dp.sv;
-- one-bit options are natural (0 / 1). Side-band ports of disabled options
-- are present; tie their inputs to 0.
-- Dual-port variant: two slave ports (A_*, B_*) on a two-port array (sram_core
-- DUAL_PORT = 1). Port B may be narrower or wider (WIDTH_B, same capacity).
-- Each port has its own clock and reset pins: with COMMON_CLK = 1 drive the
-- B clock from the same clock as the A clock (same-word conflicts complete
-- in the order A then B); with COMMON_CLK = 0 they are unrelated and
-- same-word collisions are undefined. With TECH_SKY130 port B is read-only;
-- TECH_SAED14 needs COMMON_CLK = 1.

library ieee;
use ieee.std_logic_1164.all;
use work.sram_pkg.all;

entity sram_axi4l_dp is
  generic (
    TECH             : natural  := TECH_GENERIC_C; -- technology (TECH_*_C)
    ADDR_W           : positive := 32;             -- bus byte-address width
    WIDTH            : positive := 32;             -- data width (multiple of 8)
    DEPTH            : positive := 1024;           -- words (power of two)
    BYTE_EN          : natural  := 1;              -- byte-lane writes (0 / 1)
    PARTIAL_WR_ERR   : natural  := 1;              -- BYTE_EN = 0: partial write errors
    READ_LATENCY     : positive := 1;              -- 1 or 2
    PWR_GATE         : natural  := 1;              -- power modes (0 / 1)
    ECC_EN           : natural  := 0;              -- SECDED (0 / 1)
    BANK_PG          : natural  := 0;              -- one power domain per bank (0 / 1)
    NUM_BANKS        : positive := 1;              -- banks (power of two)
    BIST_EN          : natural  := 0;              -- March C- engine (0 / 1)
    WIDTH_B          : positive := WIDTH;          -- port B data width (multiple of 8)
    BYTE_EN_B        : natural  := BYTE_EN;        -- port B byte-lane writes
    PARTIAL_WR_ERR_B : natural  := PARTIAL_WR_ERR; -- port B partial-write error
    READ_LATENCY_B   : positive := READ_LATENCY;   -- port B: 1 or 2
    COMMON_CLK       : natural  := 1;              -- 1: B clock is A's clock; 0: separate
    INIT_FILE        : string   := "";             -- preload (GENERIC/FPGA)
    RST_POL          : natural  := 0               -- 0 = active-low (reset pins)
  );
  port (
    -- Clocks and resets (B = A's clock when COMMON_CLK = 1)
    A_ACLK           : in  std_ulogic; -- port A bus clock (core, side-band)
    A_ARESETn        : in  std_ulogic; -- port A AXI active-low reset
    B_ACLK           : in  std_ulogic; -- port B bus clock
    B_ARESETn        : in  std_ulogic; -- port B AXI active-low reset

    -- AXI4-Lite bus, port A
    A_AWVALID        : in  std_ulogic;                                -- write address valid
    A_AWREADY        : out std_ulogic;                                -- write address accepted
    A_AWADDR         : in  std_ulogic_vector(ADDR_W - 1 downto 0);    -- write byte address
    A_WVALID         : in  std_ulogic;                                -- write data valid
    A_WREADY         : out std_ulogic;                                -- write data accepted
    A_WDATA          : in  std_ulogic_vector(WIDTH - 1 downto 0);     -- write data
    A_WSTRB          : in  std_ulogic_vector(WIDTH / 8 - 1 downto 0); -- write byte strobes
    A_BVALID         : out std_ulogic;                                -- write response valid
    A_BREADY         : in  std_ulogic;                                -- write response accepted
    A_BRESP          : out std_ulogic_vector(1 downto 0);             -- OKAY or SLVERR
    A_ARVALID        : in  std_ulogic;                                -- read address valid
    A_ARREADY        : out std_ulogic;                                -- read address accepted
    A_ARADDR         : in  std_ulogic_vector(ADDR_W - 1 downto 0);    -- read byte address
    A_RVALID         : out std_ulogic;                                -- read data valid
    A_RREADY         : in  std_ulogic;                                -- read data accepted
    A_RDATA          : out std_ulogic_vector(WIDTH - 1 downto 0);     -- read data
    A_RRESP          : out std_ulogic_vector(1 downto 0);             -- OKAY or SLVERR

    -- AXI4-Lite bus, port B
    B_AWVALID        : in  std_ulogic;                                  -- write address valid
    B_AWREADY        : out std_ulogic;                                  -- write address accepted
    B_AWADDR         : in  std_ulogic_vector(ADDR_W - 1 downto 0);      -- write byte address
    B_WVALID         : in  std_ulogic;                                  -- write data valid
    B_WREADY         : out std_ulogic;                                  -- write data accepted
    B_WDATA          : in  std_ulogic_vector(WIDTH_B - 1 downto 0);     -- write data
    B_WSTRB          : in  std_ulogic_vector(WIDTH_B / 8 - 1 downto 0); -- write byte strobes
    B_BVALID         : out std_ulogic;                                  -- write response valid
    B_BREADY         : in  std_ulogic;                                  -- write response accepted
    B_BRESP          : out std_ulogic_vector(1 downto 0);               -- OKAY or SLVERR
    B_ARVALID        : in  std_ulogic;                                  -- read address valid
    B_ARREADY        : out std_ulogic;                                  -- read address accepted
    B_ARADDR         : in  std_ulogic_vector(ADDR_W - 1 downto 0);      -- read byte address
    B_RVALID         : out std_ulogic;                                  -- read data valid
    B_RREADY         : in  std_ulogic;                                  -- read data accepted
    B_RDATA          : out std_ulogic_vector(WIDTH_B - 1 downto 0);     -- read data
    B_RRESP          : out std_ulogic_vector(1 downto 0);               -- OKAY or SLVERR

    -- Side-band: power, clear, status, ECC, BIST
    -- requested power mode per domain
    pwr_mode_req_i   : in  std_ulogic_vector(2 * num_domains(BANK_PG, NUM_BANKS) - 1 downto 0);
    -- power mode in effect per domain
    pwr_mode_ack_o   : out std_ulogic_vector(2 * num_domains(BANK_PG, NUM_BANKS) - 1 downto 0);
    clr_req_i        : in  std_ulogic;                                  -- clear the array (pulse)
    clr_done_o       : out std_ulogic; -- clear pass finished (pulse)
    busy_o           : out std_ulogic; -- clear/BIST/wake/RMW in progress
    err_irq_o        : out std_ulogic; -- bus error or ECC event (pulse)
    ecc_inj_i        : in  std_ulogic_vector(1 downto 0); -- ECC: arm 1-bit (0) / 2-bit (1) error
    ecc_corr_o       : out std_ulogic; -- ECC: corrected error (pulse)
    ecc_uncorr_o     : out std_ulogic; -- ECC: uncorrectable error (pulse)
    bist_start_i     : in  std_ulogic; -- BIST: start March C- (pulse)
    bist_done_o      : out std_ulogic;                                  -- BIST: finished (pulse)
    bist_fail_o      : out std_ulogic;                                  -- BIST: a word failed
    bist_fail_addr_o : out std_ulogic_vector(clog2(DEPTH) - 1 downto 0) -- BIST: first failing word
  );
end entity sram_axi4l_dp;

architecture rtl of sram_axi4l_dp is

  -- Memory bus between the adapters and the core
  signal a_mem_req    : std_ulogic;
  signal a_mem_gnt    : std_ulogic;
  signal a_mem_we     : std_ulogic;
  signal a_mem_addr   : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal a_mem_be     : std_ulogic_vector(WIDTH / 8 - 1 downto 0);
  signal a_mem_wdata  : std_ulogic_vector(WIDTH - 1 downto 0);
  signal a_mem_rvalid : std_ulogic;
  signal a_mem_rdata  : std_ulogic_vector(WIDTH - 1 downto 0);
  signal a_mem_err    : std_ulogic;
  signal b_mem_req    : std_ulogic;
  signal b_mem_gnt    : std_ulogic;
  signal b_mem_we     : std_ulogic;
  signal b_mem_addr   : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal b_mem_be     : std_ulogic_vector(WIDTH_B / 8 - 1 downto 0);
  signal b_mem_wdata  : std_ulogic_vector(WIDTH_B - 1 downto 0);
  signal b_mem_rvalid : std_ulogic;
  signal b_mem_rdata  : std_ulogic_vector(WIDTH_B - 1 downto 0);
  signal b_mem_err    : std_ulogic;

begin

  u_if_a : entity work.claude_axi4l_mem_if(rtl)
    generic map (
      DATA_W => WIDTH,
      ADDR_W => ADDR_W
    )
    port map (
      ACLK         => A_ACLK,
      ARESETn      => A_ARESETn,
      AWVALID      => A_AWVALID,
      AWREADY      => A_AWREADY,
      AWADDR       => A_AWADDR,
      WVALID       => A_WVALID,
      WREADY       => A_WREADY,
      WDATA        => A_WDATA,
      WSTRB        => A_WSTRB,
      BVALID       => A_BVALID,
      BREADY       => A_BREADY,
      BRESP        => A_BRESP,
      ARVALID      => A_ARVALID,
      ARREADY      => A_ARREADY,
      ARADDR       => A_ARADDR,
      RVALID       => A_RVALID,
      RREADY       => A_RREADY,
      RDATA        => A_RDATA,
      RRESP        => A_RRESP,
      mem_req_o    => a_mem_req,
      mem_gnt_i    => a_mem_gnt,
      mem_we_o     => a_mem_we,
      mem_addr_o   => a_mem_addr,
      mem_be_o     => a_mem_be,
      mem_wdata_o  => a_mem_wdata,
      mem_rvalid_i => a_mem_rvalid,
      mem_rdata_i  => a_mem_rdata,
      mem_err_i    => a_mem_err
    );

  u_if_b : entity work.claude_axi4l_mem_if(rtl)
    generic map (
      DATA_W => WIDTH_B,
      ADDR_W => ADDR_W
    )
    port map (
      ACLK         => B_ACLK,
      ARESETn      => B_ARESETn,
      AWVALID      => B_AWVALID,
      AWREADY      => B_AWREADY,
      AWADDR       => B_AWADDR,
      WVALID       => B_WVALID,
      WREADY       => B_WREADY,
      WDATA        => B_WDATA,
      WSTRB        => B_WSTRB,
      BVALID       => B_BVALID,
      BREADY       => B_BREADY,
      BRESP        => B_BRESP,
      ARVALID      => B_ARVALID,
      ARREADY      => B_ARREADY,
      ARADDR       => B_ARADDR,
      RVALID       => B_RVALID,
      RREADY       => B_RREADY,
      RDATA        => B_RDATA,
      RRESP        => B_RRESP,
      mem_req_o    => b_mem_req,
      mem_gnt_i    => b_mem_gnt,
      mem_we_o     => b_mem_we,
      mem_addr_o   => b_mem_addr,
      mem_be_o     => b_mem_be,
      mem_wdata_o  => b_mem_wdata,
      mem_rvalid_i => b_mem_rvalid,
      mem_rdata_i  => b_mem_rdata,
      mem_err_i    => b_mem_err
    );

  u_core : entity work.sram_core(rtl)
    generic map (
      TECH             => TECH,
      ADDR_W           => ADDR_W,
      WIDTH            => WIDTH,
      DEPTH            => DEPTH,
      BYTE_EN          => BYTE_EN,
      PARTIAL_WR_ERR   => PARTIAL_WR_ERR,
      READ_LATENCY     => READ_LATENCY,
      PWR_GATE         => PWR_GATE,
      ECC_EN           => ECC_EN,
      BANK_PG          => BANK_PG,
      NUM_BANKS        => NUM_BANKS,
      BIST_EN          => BIST_EN,
      DUAL_PORT        => 1,
      WIDTH_B          => WIDTH_B,
      BYTE_EN_B        => BYTE_EN_B,
      PARTIAL_WR_ERR_B => PARTIAL_WR_ERR_B,
      READ_LATENCY_B   => READ_LATENCY_B,
      COMMON_CLK       => COMMON_CLK,
      INIT_FILE        => INIT_FILE
    )
    port map (
      clk              => A_ACLK,
      rst_n            => A_ARESETn,
      clk_b            => B_ACLK,
      rst_b_n          => B_ARESETn,
      mem_req_i        => a_mem_req,
      mem_gnt_o        => a_mem_gnt,
      mem_we_i         => a_mem_we,
      mem_addr_i       => a_mem_addr,
      mem_be_i         => a_mem_be,
      mem_wdata_i      => a_mem_wdata,
      mem_rvalid_o     => a_mem_rvalid,
      mem_rdata_o      => a_mem_rdata,
      mem_err_o        => a_mem_err,
      mem_b_req_i      => b_mem_req,
      mem_b_gnt_o      => b_mem_gnt,
      mem_b_we_i       => b_mem_we,
      mem_b_addr_i     => b_mem_addr,
      mem_b_be_i       => b_mem_be,
      mem_b_wdata_i    => b_mem_wdata,
      mem_b_rvalid_o   => b_mem_rvalid,
      mem_b_rdata_o    => b_mem_rdata,
      mem_b_err_o      => b_mem_err,
      pwr_mode_req_i   => pwr_mode_req_i,
      pwr_mode_ack_o   => pwr_mode_ack_o,
      clr_req_i        => clr_req_i,
      clr_done_o       => clr_done_o,
      busy_o           => busy_o,
      err_irq_o        => err_irq_o,
      ecc_inj_i        => ecc_inj_i,
      ecc_corr_o       => ecc_corr_o,
      ecc_uncorr_o     => ecc_uncorr_o,
      bist_start_i     => bist_start_i,
      bist_done_o      => bist_done_o,
      bist_fail_o      => bist_fail_o,
      bist_fail_addr_o => bist_fail_addr_o
    );

end architecture rtl;
