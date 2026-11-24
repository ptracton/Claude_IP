// stubs_altera.sv — Port-only black box of altsyncram (altera_mf) as used by
// sram_macro_altera / sram_macro_dp_altera, for SpyGlass lint on hosts without
// Quartus (verification/tools/lint_sram.py; the project marks it `stop`).
// Only the ports the wrappers connect; the port-B inputs carry altera_mf's
// defaults, so the single-port wrapper may leave them open (as in altera_mf);
// not a model. Lint-only: never in a simulation or synthesis file list.

module altsyncram #(
  parameter operation_mode = "SINGLE_PORT", parameter intended_device_family = "Cyclone V",
  parameter ram_block_type = "AUTO", parameter lpm_type = "altsyncram",
  parameter width_a = 32, parameter width_b = 32, parameter widthad_a = 6,
  parameter widthad_b = 6, parameter numwords_a = 64, parameter numwords_b = 64,
  parameter width_byteena_a = 1, parameter width_byteena_b = 1, parameter byte_size = 8,
  parameter address_reg_b = "CLOCK1", parameter indata_reg_b = "CLOCK1",
  parameter wrcontrol_wraddress_reg_b = "CLOCK1", parameter byteena_reg_b = "CLOCK1",
  parameter outdata_reg_a = "UNREGISTERED", parameter outdata_reg_b = "UNREGISTERED",
  parameter outdata_aclr_a = "NONE", parameter outdata_aclr_b = "NONE",
  parameter clock_enable_input_a = "NORMAL", parameter clock_enable_input_b = "NORMAL",
  parameter clock_enable_output_a = "BYPASS", parameter clock_enable_output_b = "BYPASS",
  parameter read_during_write_mode_mixed_ports = "DONT_CARE",
  parameter read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
  parameter read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
  parameter power_up_uninitialized = "FALSE", parameter init_file = "UNUSED"
) (
  input  wire                        clock0,
  input  wire                        clocken0,
  input  wire                        clock1 = 1'b1,
  input  wire                        clocken1 = 1'b1,
  input  wire [widthad_a-1:0]        address_a,
  input  wire [width_a-1:0]          data_a,
  input  wire                        wren_a,
  input  wire [width_byteena_a-1:0]  byteena_a,
  output wire [width_a-1:0]          q_a,
  input  wire [widthad_b-1:0]        address_b = '1,
  input  wire [width_b-1:0]          data_b = '1,
  input  wire                        wren_b = 1'b0,
  input  wire [width_byteena_b-1:0]  byteena_b = '1,
  output wire [width_b-1:0]          q_b
);
endmodule
