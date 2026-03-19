# arm-cortex-m33.cmake — CMake toolchain file for ARM Cortex-M33 (bare-metal)
#
# Requires: arm-none-eabi-gcc (e.g. GNU Arm Embedded Toolchain or arm-gnu-toolchain)
# Install:  sudo apt install gcc-arm-none-eabi   (Debian/Ubuntu)
#           brew install --cask gcc-arm-embedded  (macOS)

set(CMAKE_SYSTEM_NAME      Generic)
set(CMAKE_SYSTEM_PROCESSOR arm)

# Cross-compiler binaries
set(CMAKE_C_COMPILER   arm-none-eabi-gcc)
set(CMAKE_AR           arm-none-eabi-ar)
set(CMAKE_RANLIB       arm-none-eabi-ranlib)
set(CMAKE_OBJCOPY      arm-none-eabi-objcopy)
set(CMAKE_SIZE         arm-none-eabi-size)

# Cortex-M33 architecture flags (Thumb-2, soft-float ABI)
# Swap -mfloat-abi=soft for -mfpu=fpv5-sp-d16 -mfloat-abi=hard if the target
# has FPU and the calling convention matches.
set(CMAKE_C_FLAGS_INIT
    "-mcpu=cortex-m33 -mthumb -mfloat-abi=soft"
)

# nano.specs reduces code size; nosys.specs satisfies link-time syscall references.
# Only relevant if TIMER_BUILD_EXAMPLE=ON; the library itself needs no linker flags.
set(CMAKE_EXE_LINKER_FLAGS_INIT "--specs=nano.specs --specs=nosys.specs")

# Do not search host paths for libraries/includes
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
