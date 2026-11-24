// stubs_xilinx.sv — Port-only black boxes of the Xilinx XPM memories used by
// sram_macro_xilinx / sram_macro_dp_xilinx, for SpyGlass lint on hosts without
// Vivado (verification/tools/lint_sram.py; the project marks them `stop`).
// Ports and parameters as used by the wrappers (UG974 names); not a model.
// Lint-only: never in a simulation or synthesis file list.

module xpm_memory_spram #(
  parameter ADDR_WIDTH_A = 6, parameter AUTO_SLEEP_TIME = 0, parameter BYTE_WRITE_WIDTH_A = 32,
  parameter ECC_MODE = "no_ecc", parameter MEMORY_INIT_FILE = "none",
  parameter MEMORY_INIT_PARAM = "0", parameter MEMORY_OPTIMIZATION = "true",
  parameter MEMORY_PRIMITIVE = "auto", parameter MEMORY_SIZE = 2048, parameter MESSAGE_CONTROL = 0,
  parameter READ_DATA_WIDTH_A = 32, parameter READ_LATENCY_A = 2,
  parameter READ_RESET_VALUE_A = "0", parameter RST_MODE_A = "SYNC", parameter USE_MEM_INIT = 1,
  parameter WAKEUP_TIME = "disable_sleep", parameter WRITE_DATA_WIDTH_A = 32,
  parameter WRITE_MODE_A = "read_first"
) (
  input  wire                                              clka,
  input  wire                                              rsta,
  input  wire                                              ena,
  input  wire                                              regcea,
  input  wire [WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-1:0]  wea,
  input  wire [ADDR_WIDTH_A-1:0]                           addra,
  input  wire [WRITE_DATA_WIDTH_A-1:0]                     dina,
  output wire [READ_DATA_WIDTH_A-1:0]                      douta,
  input  wire                                              sleep,
  input  wire                                              injectsbiterra,
  input  wire                                              injectdbiterra,
  output wire                                              sbiterra,
  output wire                                              dbiterra
);
endmodule

module xpm_memory_tdpram #(
  parameter ADDR_WIDTH_A = 6, parameter ADDR_WIDTH_B = 6, parameter AUTO_SLEEP_TIME = 0,
  parameter BYTE_WRITE_WIDTH_A = 32, parameter BYTE_WRITE_WIDTH_B = 32,
  parameter CLOCKING_MODE = "common_clock", parameter ECC_MODE = "no_ecc",
  parameter MEMORY_INIT_FILE = "none", parameter MEMORY_INIT_PARAM = "0",
  parameter MEMORY_OPTIMIZATION = "true", parameter MEMORY_PRIMITIVE = "auto",
  parameter MEMORY_SIZE = 2048, parameter MESSAGE_CONTROL = 0,
  parameter READ_DATA_WIDTH_A = 32, parameter READ_DATA_WIDTH_B = 32,
  parameter READ_LATENCY_A = 2, parameter READ_LATENCY_B = 2,
  parameter READ_RESET_VALUE_A = "0", parameter READ_RESET_VALUE_B = "0",
  parameter RST_MODE_A = "SYNC", parameter RST_MODE_B = "SYNC", parameter USE_MEM_INIT = 1,
  parameter WAKEUP_TIME = "disable_sleep", parameter WRITE_DATA_WIDTH_A = 32,
  parameter WRITE_DATA_WIDTH_B = 32, parameter WRITE_MODE_A = "no_change",
  parameter WRITE_MODE_B = "no_change"
) (
  input  wire                                              clka,
  input  wire                                              clkb,
  input  wire                                              rsta,
  input  wire                                              rstb,
  input  wire                                              ena,
  input  wire                                              enb,
  input  wire                                              regcea,
  input  wire                                              regceb,
  input  wire [WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-1:0]  wea,
  input  wire [WRITE_DATA_WIDTH_B/BYTE_WRITE_WIDTH_B-1:0]  web,
  input  wire [ADDR_WIDTH_A-1:0]                           addra,
  input  wire [ADDR_WIDTH_B-1:0]                           addrb,
  input  wire [WRITE_DATA_WIDTH_A-1:0]                     dina,
  input  wire [WRITE_DATA_WIDTH_B-1:0]                     dinb,
  output wire [READ_DATA_WIDTH_A-1:0]                      douta,
  output wire [READ_DATA_WIDTH_B-1:0]                      doutb,
  input  wire                                              sleep,
  input  wire                                              injectsbiterra,
  input  wire                                              injectdbiterra,
  input  wire                                              injectsbiterrb,
  input  wire                                              injectdbiterrb,
  output wire                                              sbiterra,
  output wire                                              dbiterra,
  output wire                                              sbiterrb,
  output wire                                              dbiterrb
);
endmodule
