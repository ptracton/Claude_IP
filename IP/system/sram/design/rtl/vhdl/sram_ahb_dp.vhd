-- sram_ahb_dp.vhd — AHB-Lite dual-port top-level of the sram IP.
--
-- VHDL-2008 twin of sram_ahb_dp.sv: instantiates claude_ahb_mem_if (IP/common) per port
-- and sram_core. Contains no logic — only port declarations and submodule
-- wiring. Generics as in sram_ahb_dp.sv;
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

entity sram_ahb_dp is
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
    A_HCLK           : in  std_ulogic; -- port A bus clock (core, side-band)
    A_HRESETn        : in  std_ulogic; -- port A AHB active-low reset
    B_HCLK           : in  std_ulogic; -- port B bus clock
    B_HRESETn        : in  std_ulogic; -- port B AHB active-low reset

    -- AHB-Lite bus, port A
    A_HSEL           : in  std_ulogic;                             -- slave select
    A_HADDR          : in  std_ulogic_vector(ADDR_W - 1 downto 0); -- byte address
    A_HTRANS         : in  std_ulogic_vector(1 downto 0);          -- transfer type
    A_HWRITE         : in  std_ulogic;                             -- 1 = write
    A_HSIZE          : in  std_ulogic_vector(2 downto 0);          -- transfer size
    A_HWDATA         : in  std_ulogic_vector(WIDTH - 1 downto 0);  -- write data
    -- write strobes (all ones if unused)
    A_HWSTRB         : in  std_ulogic_vector(WIDTH / 8 - 1 downto 0);
    A_HREADY         : in  std_ulogic; -- bus ready (= HREADYOUT if alone)
    A_HRDATA         : out std_ulogic_vector(WIDTH - 1 downto 0); -- read data
    A_HREADYOUT      : out std_ulogic;                            -- this slave's ready
    A_HRESP          : out std_ulogic;                            -- 0 = OKAY, 1 = ERROR

    -- AHB-Lite bus, port B
    B_HSEL           : in  std_ulogic;                              -- slave select
    B_HADDR          : in  std_ulogic_vector(ADDR_W - 1 downto 0);  -- byte address
    B_HTRANS         : in  std_ulogic_vector(1 downto 0);           -- transfer type
    B_HWRITE         : in  std_ulogic;                              -- 1 = write
    B_HSIZE          : in  std_ulogic_vector(2 downto 0);           -- transfer size
    B_HWDATA         : in  std_ulogic_vector(WIDTH_B - 1 downto 0); -- write data
    -- write strobes (all ones if unused)
    B_HWSTRB         : in  std_ulogic_vector(WIDTH_B / 8 - 1 downto 0);
    B_HREADY         : in  std_ulogic; -- bus ready (= HREADYOUT if alone)
    B_HRDATA         : out std_ulogic_vector(WIDTH_B - 1 downto 0); -- read data
    B_HREADYOUT      : out std_ulogic;                              -- this slave's ready
    B_HRESP          : out std_ulogic;                              -- 0 = OKAY, 1 = ERROR

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
end entity sram_ahb_dp;

architecture rtl of sram_ahb_dp is

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

  u_if_a : entity work.claude_ahb_mem_if(rtl)
    generic map (
      DATA_W => WIDTH,
      ADDR_W => ADDR_W
    )
    port map (
      HCLK         => A_HCLK,
      HRESETn      => A_HRESETn,
      HSEL         => A_HSEL,
      HADDR        => A_HADDR,
      HTRANS       => A_HTRANS,
      HWRITE       => A_HWRITE,
      HSIZE        => A_HSIZE,
      HWDATA       => A_HWDATA,
      HWSTRB       => A_HWSTRB,
      HREADY       => A_HREADY,
      HRDATA       => A_HRDATA,
      HREADYOUT    => A_HREADYOUT,
      HRESP        => A_HRESP,
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

  u_if_b : entity work.claude_ahb_mem_if(rtl)
    generic map (
      DATA_W => WIDTH_B,
      ADDR_W => ADDR_W
    )
    port map (
      HCLK         => B_HCLK,
      HRESETn      => B_HRESETn,
      HSEL         => B_HSEL,
      HADDR        => B_HADDR,
      HTRANS       => B_HTRANS,
      HWRITE       => B_HWRITE,
      HSIZE        => B_HSIZE,
      HWDATA       => B_HWDATA,
      HWSTRB       => B_HWSTRB,
      HREADY       => B_HREADY,
      HRDATA       => B_HRDATA,
      HREADYOUT    => B_HREADYOUT,
      HRESP        => B_HRESP,
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
      clk              => A_HCLK,
      rst_n            => A_HRESETn,
      clk_b            => B_HCLK,
      rst_b_n          => B_HRESETn,
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
