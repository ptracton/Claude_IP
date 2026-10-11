// bus_matrix_base_seq.sv — Base sequence with helper tasks for AXI4-Lite transactions.

`ifndef BUS_MATRIX_BASE_SEQ_SV
`define BUS_MATRIX_BASE_SEQ_SV

class bus_matrix_base_seq extends uvm_sequence #(bus_matrix_axi_seq_item);
  `uvm_object_utils(bus_matrix_base_seq)

  function new(string name = "bus_matrix_base_seq");
    super.new(name);
  endfunction

  // Helper: send a single write transaction. expect_err: the write must be
  // answered with SLVERR (decode error or slave error) instead of OKAY.
  task do_write(input logic [31:0] addr, input logic [31:0] data,
                input logic [3:0] strb = 4'hF, input bit expect_err = 1'b0);
    bus_matrix_axi_seq_item item = bus_matrix_axi_seq_item::type_id::create("wr_item");
    start_item(item);
    if (!item.randomize() with { write == 1'b1; addr == local::addr;
                                  wdata == local::data; wstrb == local::strb; })
      `uvm_fatal("SEQ", "Randomize failed in do_write")
    finish_item(item);
    if (item.resp != (expect_err ? 2'b10 : 2'b00))
      `uvm_error("SEQ", $sformatf("Write to 0x%08x got resp=%02b, expected %s",
                                  addr, item.resp, expect_err ? "SLVERR" : "OKAY"))
  endtask

  // Helper: send a single read transaction, return data. expect_err as for
  // do_write; the data of an error response is not meaningful.
  task do_read(input logic [31:0] addr, output logic [31:0] rdata,
               input bit expect_err = 1'b0);
    bus_matrix_axi_seq_item item = bus_matrix_axi_seq_item::type_id::create("rd_item");
    start_item(item);
    if (!item.randomize() with { write == 1'b0; addr == local::addr; wstrb == 4'h0; })
      `uvm_fatal("SEQ", "Randomize failed in do_read")
    finish_item(item);
    rdata = item.rdata;
    if (item.resp != (expect_err ? 2'b10 : 2'b00))
      `uvm_error("SEQ", $sformatf("Read from 0x%08x got resp=%02b, expected %s",
                                  addr, item.resp, expect_err ? "SLVERR" : "OKAY"))
  endtask

  // Helper: read and compare (a mismatch is a sequence error).
  task check_read(input logic [31:0] addr, input logic [31:0] exp, input string what);
    logic [31:0] rdata;
    do_read(addr, rdata);
    if (rdata !== exp)
      `uvm_error("SEQ", $sformatf("%s: read 0x%08x got 0x%08x, expected 0x%08x",
                                  what, addr, rdata, exp))
  endtask

  // Slave j's base address and region size, from bus_matrix_pkg.
  function automatic logic [31:0] slv_base(int j);
    return bus_matrix_pkg::BM_S_BASE[j*32+:32];
  endfunction
  function automatic logic [31:0] slv_size(int j);
    return ~bus_matrix_pkg::BM_S_MASK[j*32+:32] + 1;
  endfunction

endclass : bus_matrix_base_seq

`endif // BUS_MATRIX_BASE_SEQ_SV
