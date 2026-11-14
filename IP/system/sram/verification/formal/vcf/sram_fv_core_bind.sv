// sram_fv_core_bind.sv — bind-only module of the core-level formal jobs
// (top-level sram_core). VC Formal applies it with
// "elaborate sram_core ... -sva_bind_enable sram_fv_core_bind", for the SV
// module and the VHDL entity alike.

`include "sram_fv_cfg.svh"

module sram_fv_core_bind;
`include "sram_fv_block_binds.svh"
endmodule : sram_fv_core_bind
