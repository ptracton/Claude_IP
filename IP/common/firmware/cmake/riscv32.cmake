# riscv32.cmake — CMake toolchain file for RISC-V 32-bit bare-metal
#
# Shared Claude IP component — used by every IP block that targets RISC-V 32-bit.
# Reference via ${IP_COMMON_PATH}/firmware/cmake/riscv32.cmake
#
# Requires: xPack RISC-V Embedded GCC (riscv-none-elf-gcc)
# Location: /opt/xpack-riscv-none-elf-gcc-15.2.0-1/bin
# Added to PATH by setup.sh — source it before running cmake.
#
# Architecture: rv32imac_zicsr  (integer + multiply + atomics + compressed + CSR)
# ABI:          ilp32           (32-bit integer, 32-bit pointers, soft-float)
#
# To target a device with hardware FPU (e.g. rv32imafc), change -march and
# set -mabi=ilp32f accordingly.

set(CMAKE_SYSTEM_NAME      Generic)
set(CMAKE_SYSTEM_PROCESSOR riscv)

set(CMAKE_C_COMPILER  riscv-none-elf-gcc)
set(CMAKE_AR          riscv-none-elf-ar)
set(CMAKE_RANLIB      riscv-none-elf-ranlib)
set(CMAKE_OBJCOPY     riscv-none-elf-objcopy)
set(CMAKE_SIZE        riscv-none-elf-size)

# RV32IMAC architecture flags
set(CMAKE_C_FLAGS_INIT
    "-march=rv32imac_zicsr -mabi=ilp32"
)

# nano.specs reduces code size; nosys.specs satisfies link-time syscall references.
# Only relevant if <IP_NAME>_BUILD_EXAMPLE=ON; the library itself needs no linker flags.
set(CMAKE_EXE_LINKER_FLAGS_INIT "--specs=nano.specs --specs=nosys.specs")

# Do not search host paths for libraries/includes
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
