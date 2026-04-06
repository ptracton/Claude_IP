// bus_matrix_base_seq.sv — Base sequence with helper tasks for AXI4-Lite transactions.

`ifndef BUS_MATRIX_BASE_SEQ_SV
`define BUS_MATRIX_BASE_SEQ_SV

class bus_matrix_base_seq extends uvm_sequence #(bus_matrix_axi_seq_item);
  `uvm_object_utils(bus_matrix_base_seq)

  function new(string name = "bus_matrix_base_seq");
    super.new(name);
  endfunction

  // Helper: send a single write transaction
  task do_write(input logic [31:0] addr, input logic [31:0] data,
                input logic [3:0] strb = 4'hF);
    bus_matrix_axi_seq_item item = bus_matrix_axi_seq_item::type_id::create("wr_item");
    start_item(item);
    if (!item.randomize() with { write == 1'b1; addr == local::addr;
                                  wdata == local::data; wstrb == local::strb; })
      `uvm_fatal("SEQ", "Randomize failed in do_write")
    finish_item(item);
    if (item.resp != 2'b00)
      `uvm_error("SEQ", $sformatf("Write to 0x%08x got non-OKAY resp=%02b", addr, item.resp))
  endtask

  // Helper: send a single read transaction, return data
  task do_read(input logic [31:0] addr, output logic [31:0] rdata);
    bus_matrix_axi_seq_item item = bus_matrix_axi_seq_item::type_id::create("rd_item");
    start_item(item);
    if (!item.randomize() with { write == 1'b0; addr == local::addr; wstrb == 4'h0; })
      `uvm_fatal("SEQ", "Randomize failed in do_read")
    finish_item(item);
    rdata = item.rdata;
    if (item.resp != 2'b00)
      `uvm_error("SEQ", $sformatf("Read from 0x%08x got non-OKAY resp=%02b", addr, item.resp))
  endtask

endclass : bus_matrix_base_seq

`endif // BUS_MATRIX_BASE_SEQ_SV
