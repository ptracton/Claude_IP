-- bus_matrix_pkg.vhd — Default configuration of the bus matrix (VHDL-2008).
--
-- Mirrors bus_matrix_pkg.sv. The defaults describe a small
-- microcontroller-style system and are the configuration that is
-- synthesized, timed, simulated at gate level and power-analyzed.
--
--   Masters: M0 = CPU, M1 = DMA, served round robin so neither can starve
--            the other (a fixed-priority CPU issuing back-to-back AHB or
--            Wishbone transfers would lock the DMA out). The priorities
--            below apply only if ARB_MODE is set to 0 (fixed priority).
--
--   Slave  Region       Base         Mask         Size
--   S0     Boot ROM     0x0000_0000  0xFFFF_0000   64 KB
--   S1     SRAM         0x2000_0000  0xFFFE_0000  128 KB
--   S2     Peripherals  0x4000_0000  0xFFFF_0000   64 KB
--   S3     External     0x6000_0000  0xF000_0000  256 MB
--
-- Any other address is a decode error. The generic vectors are maximum-width
-- (16 masters x 4 bits, 32 slaves x 32 bits) because VHDL-2008 generics
-- cannot be sized by other generics; only the low NUM_MASTERS / NUM_SLAVES
-- entries are used. Slave j occupies bits (j*32+31 downto j*32).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package bus_matrix_pkg is

  constant BM_MAX_MASTERS : positive := 16;
  constant BM_MAX_SLAVES  : positive := 32;

  constant BM_NUM_MASTERS : positive := 2;
  constant BM_NUM_SLAVES  : positive := 4;
  constant BM_ARB_MODE    : natural  := 1;  -- 0 = fixed priority, 1 = round robin

  constant BM_M_PRIORITY_USED : std_ulogic_vector(BM_NUM_MASTERS * 4 - 1 downto 0) :=
    x"1" &  -- M1 DMA
    x"0";   -- M0 CPU

  constant BM_S_BASE_USED : std_ulogic_vector(BM_NUM_SLAVES * 32 - 1 downto 0) :=
    x"60000000" &  -- S3 External
    x"40000000" &  -- S2 Peripherals
    x"20000000" &  -- S1 SRAM
    x"00000000";   -- S0 Boot ROM

  constant BM_S_MASK_USED : std_ulogic_vector(BM_NUM_SLAVES * 32 - 1 downto 0) :=
    x"F0000000" &  -- S3 External     256 MB
    x"FFFF0000" &  -- S2 Peripherals   64 KB
    x"FFFE0000" &  -- S1 SRAM         128 KB
    x"FFFF0000";   -- S0 Boot ROM      64 KB

  -- Maximum-width forms used as generic defaults
  constant BM_M_PRIORITY : std_ulogic_vector(BM_MAX_MASTERS * 4 - 1 downto 0) :=
    std_ulogic_vector(resize(unsigned(BM_M_PRIORITY_USED), BM_MAX_MASTERS * 4));
  constant BM_S_BASE : std_ulogic_vector(BM_MAX_SLAVES * 32 - 1 downto 0) :=
    std_ulogic_vector(resize(unsigned(BM_S_BASE_USED), BM_MAX_SLAVES * 32));
  constant BM_S_MASK : std_ulogic_vector(BM_MAX_SLAVES * 32 - 1 downto 0) :=
    std_ulogic_vector(resize(unsigned(BM_S_MASK_USED), BM_MAX_SLAVES * 32));

end package bus_matrix_pkg;
