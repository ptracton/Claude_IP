// bus_matrix_pkg.sv — Default configuration of the bus matrix.
//
// The defaults describe a small microcontroller-style system and are the
// configuration that is synthesized, timed, simulated at gate level and
// power-analyzed (a gate-level netlist cannot be re-parameterized).
//
//   Masters: M0 = CPU, M1 = DMA, served round robin so neither can starve
//            the other (a fixed-priority CPU issuing back-to-back AHB or
//            Wishbone transfers would lock the DMA out). The priorities
//            below apply only if ARB_MODE is set to 0 (fixed priority).
//
//   Slave  Region       Base         Mask         Size
//   S0     Boot ROM     0x0000_0000  0xFFFF_0000   64 KB
//   S1     SRAM         0x2000_0000  0xFFFE_0000  128 KB
//   S2     Peripherals  0x4000_0000  0xFFFF_0000   64 KB
//   S3     External     0x6000_0000  0xF000_0000  256 MB
//
// Any other address is a decode error. Slave j occupies [j*32+:32] of
// BM_S_BASE / BM_S_MASK; master i's priority occupies [i*4+:4] of
// BM_M_PRIORITY (lower value = higher priority).

package bus_matrix_pkg;

  localparam int unsigned BM_NUM_MASTERS = 2;
  localparam int unsigned BM_NUM_SLAVES  = 4;
  localparam int unsigned BM_ARB_MODE    = 1; // 0 = fixed priority, 1 = round robin

  localparam logic [BM_NUM_MASTERS*4-1:0] BM_M_PRIORITY = {
    4'h1,  // M1 DMA
    4'h0   // M0 CPU
  };

  localparam logic [BM_NUM_SLAVES*32-1:0] BM_S_BASE = {
    32'h6000_0000,  // S3 External
    32'h4000_0000,  // S2 Peripherals
    32'h2000_0000,  // S1 SRAM
    32'h0000_0000   // S0 Boot ROM
  };

  localparam logic [BM_NUM_SLAVES*32-1:0] BM_S_MASK = {
    32'hF000_0000,  // S3 External     256 MB
    32'hFFFF_0000,  // S2 Peripherals   64 KB
    32'hFFFE_0000,  // S1 SRAM         128 KB
    32'hFFFF_0000   // S0 Boot ROM      64 KB
  };

endpackage : bus_matrix_pkg
