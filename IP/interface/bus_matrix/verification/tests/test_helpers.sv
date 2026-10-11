// test_helpers.sv — Address-map helpers shared by the bus_matrix directed tests.
//
// Included inside every tb_bus_matrix_<proto> module after ip_test_pkg.sv.
// The testbench provides u_m0 / u_m1 (bus_matrix_<proto>_bfm, shared task
// library) and gen_slv[j].u_mem (bus_matrix_tb_mem behind slave j).
//
// Each slave's memory is 4 KB (the shared bridges decode HADDR[11:0]), so
// tests keep their offsets below 0x1000.

// Byte address of offset `off` inside slave j's region.
function automatic logic [31:0] slv_addr(input int j, input logic [11:0] off);
  return bus_matrix_pkg::BM_S_BASE[j*32+:32] | {20'h0_0000, off};
endfunction

// Addresses that match no slave in the default map.
localparam logic [31:0] UNMAPPED_ADDR [4] = '{
  32'h1000_0000,  // gap between Boot ROM and SRAM
  32'h0001_0000,  // just past the 64 KB Boot ROM
  32'h2002_0000,  // just past the 128 KB SRAM
  32'hF000_0000   // top of the address space
};
