-- sram_axi4l.vhd — AXI4-Lite top-level of the sram IP.
--
-- VHDL-2008 twin of sram_axi4l.sv: instantiates claude_axi4l_mem_if (IP/common)
-- and sram_core. Contains no logic — only port declarations and submodule
-- wiring. Generics as in sram_axi4l.sv;
-- one-bit options are natural (0 / 1). Side-band ports of disabled options
-- are present; tie their inputs to 0.

library ieee;
use ieee.std_logic_1164.all;
use work.sram_pkg.all;

entity sram_axi4l is
  generic (
    TECH           : natural  := TECH_GENERIC_C; -- technology (TECH_*_C)
    ADDR_W         : positive := 32;             -- bus byte-address width
    WIDTH          : positive := 32;             -- data width (multiple of 8)
    DEPTH          : positive := 1024;           -- words (power of two)
    BYTE_EN        : natural  := 1;              -- byte-lane writes (0 / 1)
    PARTIAL_WR_ERR : natural  := 1;              -- BYTE_EN = 0: partial write is an error
    READ_LATENCY   : positive := 1;              -- 1 or 2
    PWR_GATE       : natural  := 1;              -- power modes (0 / 1)
    ECC_EN         : natural  := 0;              -- SECDED (0 / 1)
    BANK_PG        : natural  := 0;              -- one power domain per bank (0 / 1)
    NUM_BANKS      : positive := 1;              -- banks (power of two)
    BIST_EN        : natural  := 0;              -- March C- engine (0 / 1)
    INIT_FILE      : string   := "";             -- preload (GENERIC/FPGA)
    RST_POL        : natural  := 0               -- 0 = active-low; polarity carried by ARESETn
  );
  port (
    -- AXI4-Lite bus
    ACLK             : in  std_ulogic;                                -- bus clock
    ARESETn          : in  std_ulogic;                                -- AXI active-low reset
    AWVALID          : in  std_ulogic;                                -- write address valid
    AWREADY          : out std_ulogic;                                -- write address accepted
    AWADDR           : in  std_ulogic_vector(ADDR_W - 1 downto 0);    -- write byte address
    WVALID           : in  std_ulogic;                                -- write data valid
    WREADY           : out std_ulogic;                                -- write data accepted
    WDATA            : in  std_ulogic_vector(WIDTH - 1 downto 0);     -- write data
    WSTRB            : in  std_ulogic_vector(WIDTH / 8 - 1 downto 0); -- write byte strobes
    BVALID           : out std_ulogic;                                -- write response valid
    BREADY           : in  std_ulogic;                                -- write response accepted
    BRESP            : out std_ulogic_vector(1 downto 0);             -- OKAY or SLVERR
    ARVALID          : in  std_ulogic;                                -- read address valid
    ARREADY          : out std_ulogic;                                -- read address accepted
    ARADDR           : in  std_ulogic_vector(ADDR_W - 1 downto 0);    -- read byte address
    RVALID           : out std_ulogic;                                -- read data valid
    RREADY           : in  std_ulogic;                                -- read data accepted
    RDATA            : out std_ulogic_vector(WIDTH - 1 downto 0);     -- read data
    RRESP            : out std_ulogic_vector(1 downto 0);             -- OKAY or SLVERR

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
end entity sram_axi4l;

architecture rtl of sram_axi4l is

  -- Memory bus between the adapter and the core
  signal mem_req      : std_ulogic;
  signal mem_gnt      : std_ulogic;
  signal mem_we       : std_ulogic;
  signal mem_addr     : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal mem_be       : std_ulogic_vector(WIDTH / 8 - 1 downto 0);
  signal mem_wdata    : std_ulogic_vector(WIDTH - 1 downto 0);
  signal mem_rvalid   : std_ulogic;
  signal mem_rdata    : std_ulogic_vector(WIDTH - 1 downto 0);
  signal mem_err      : std_ulogic;

begin

  u_if : entity work.claude_axi4l_mem_if(rtl)
    generic map (
      DATA_W => WIDTH,
      ADDR_W => ADDR_W
    )
    port map (
      ACLK         => ACLK,
      ARESETn      => ARESETn,
      AWVALID      => AWVALID,
      AWREADY      => AWREADY,
      AWADDR       => AWADDR,
      WVALID       => WVALID,
      WREADY       => WREADY,
      WDATA        => WDATA,
      WSTRB        => WSTRB,
      BVALID       => BVALID,
      BREADY       => BREADY,
      BRESP        => BRESP,
      ARVALID      => ARVALID,
      ARREADY      => ARREADY,
      ARADDR       => ARADDR,
      RVALID       => RVALID,
      RREADY       => RREADY,
      RDATA        => RDATA,
      RRESP        => RRESP,
      mem_req_o    => mem_req,
      mem_gnt_i    => mem_gnt,
      mem_we_o     => mem_we,
      mem_addr_o   => mem_addr,
      mem_be_o     => mem_be,
      mem_wdata_o  => mem_wdata,
      mem_rvalid_i => mem_rvalid,
      mem_rdata_i  => mem_rdata,
      mem_err_i    => mem_err
    );

  u_core : entity work.sram_core(rtl)
    generic map (
      TECH           => TECH,
      ADDR_W         => ADDR_W,
      WIDTH          => WIDTH,
      DEPTH          => DEPTH,
      BYTE_EN        => BYTE_EN,
      PARTIAL_WR_ERR => PARTIAL_WR_ERR,
      READ_LATENCY   => READ_LATENCY,
      PWR_GATE       => PWR_GATE,
      ECC_EN         => ECC_EN,
      BANK_PG        => BANK_PG,
      NUM_BANKS      => NUM_BANKS,
      BIST_EN        => BIST_EN,
      DUAL_PORT      => 0,
      INIT_FILE      => INIT_FILE
    )
    port map (
      clk              => ACLK,
      rst_n            => ARESETn,
      clk_b            => ACLK,
      rst_b_n          => ARESETn,
      mem_req_i        => mem_req,
      mem_gnt_o        => mem_gnt,
      mem_we_i         => mem_we,
      mem_addr_i       => mem_addr,
      mem_be_i         => mem_be,
      mem_wdata_i      => mem_wdata,
      mem_rvalid_o     => mem_rvalid,
      mem_rdata_o      => mem_rdata,
      mem_err_o        => mem_err,
      mem_b_req_i      => '0',
      mem_b_gnt_o      => open,
      mem_b_we_i       => '0',
      mem_b_addr_i     => (others => '0'),
      mem_b_be_i       => (others => '0'),
      mem_b_wdata_i    => (others => '0'),
      mem_b_rvalid_o   => open,
      mem_b_rdata_o    => open,
      mem_b_err_o      => open,
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
