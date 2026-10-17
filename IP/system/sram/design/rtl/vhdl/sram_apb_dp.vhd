-- sram_apb_dp.vhd — APB4 dual-port top-level of the sram IP.
--
-- VHDL-2008 twin of sram_apb_dp.sv: instantiates claude_apb_mem_if (IP/common) per port
-- and sram_core. Contains no logic — only port declarations and submodule
-- wiring. Generics as in sram_apb_dp.sv;
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

entity sram_apb_dp is
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
    A_PCLK           : in  std_ulogic; -- port A bus clock (core, side-band)
    A_PRESETn        : in  std_ulogic; -- port A APB active-low reset
    B_PCLK           : in  std_ulogic; -- port B bus clock
    B_PRESETn        : in  std_ulogic; -- port B APB active-low reset

    -- APB4 bus, port A
    A_PSEL           : in  std_ulogic;                                -- slave select
    A_PENABLE        : in  std_ulogic;                                -- enable (ACCESS phase)
    A_PADDR          : in  std_ulogic_vector(ADDR_W - 1 downto 0);    -- byte address
    A_PWRITE         : in  std_ulogic;                                -- 1 = write
    A_PWDATA         : in  std_ulogic_vector(WIDTH - 1 downto 0);     -- write data
    A_PSTRB          : in  std_ulogic_vector(WIDTH / 8 - 1 downto 0); -- byte write strobes
    A_PRDATA         : out std_ulogic_vector(WIDTH - 1 downto 0);     -- read data
    A_PREADY         : out std_ulogic;                                -- transfer complete
    A_PSLVERR        : out std_ulogic;                                -- transfer failed

    -- APB4 bus, port B
    B_PSEL           : in  std_ulogic;                                  -- slave select
    B_PENABLE        : in  std_ulogic;                                  -- enable (ACCESS phase)
    B_PADDR          : in  std_ulogic_vector(ADDR_W - 1 downto 0);      -- byte address
    B_PWRITE         : in  std_ulogic;                                  -- 1 = write
    B_PWDATA         : in  std_ulogic_vector(WIDTH_B - 1 downto 0);     -- write data
    B_PSTRB          : in  std_ulogic_vector(WIDTH_B / 8 - 1 downto 0); -- byte write strobes
    B_PRDATA         : out std_ulogic_vector(WIDTH_B - 1 downto 0);     -- read data
    B_PREADY         : out std_ulogic;                                  -- transfer complete
    B_PSLVERR        : out std_ulogic;                                  -- transfer failed

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
end entity sram_apb_dp;

architecture rtl of sram_apb_dp is

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

  u_if_a : entity work.claude_apb_mem_if(rtl)
    generic map (
      DATA_W => WIDTH,
      ADDR_W => ADDR_W
    )
    port map (
      PCLK         => A_PCLK,
      PRESETn      => A_PRESETn,
      PSEL         => A_PSEL,
      PENABLE      => A_PENABLE,
      PADDR        => A_PADDR,
      PWRITE       => A_PWRITE,
      PWDATA       => A_PWDATA,
      PSTRB        => A_PSTRB,
      PRDATA       => A_PRDATA,
      PREADY       => A_PREADY,
      PSLVERR      => A_PSLVERR,
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

  u_if_b : entity work.claude_apb_mem_if(rtl)
    generic map (
      DATA_W => WIDTH_B,
      ADDR_W => ADDR_W
    )
    port map (
      PCLK         => B_PCLK,
      PRESETn      => B_PRESETn,
      PSEL         => B_PSEL,
      PENABLE      => B_PENABLE,
      PADDR        => B_PADDR,
      PWRITE       => B_PWRITE,
      PWDATA       => B_PWDATA,
      PSTRB        => B_PSTRB,
      PRDATA       => B_PRDATA,
      PREADY       => B_PREADY,
      PSLVERR      => B_PSLVERR,
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
      clk              => A_PCLK,
      rst_n            => A_PRESETn,
      clk_b            => B_PCLK,
      rst_b_n          => B_PRESETn,
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
