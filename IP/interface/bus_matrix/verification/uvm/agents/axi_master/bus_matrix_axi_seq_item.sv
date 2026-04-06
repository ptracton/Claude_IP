// bus_matrix_axi_seq_item.sv — UVM sequence item for AXI4-Lite transactions.

`ifndef BUS_MATRIX_AXI_SEQ_ITEM_SV
`define BUS_MATRIX_AXI_SEQ_ITEM_SV

class bus_matrix_axi_seq_item extends uvm_sequence_item;
  `uvm_object_utils(bus_matrix_axi_seq_item)

  // Transaction fields
  rand logic [31:0] addr;   // target address
  rand logic        write;  // 1=write, 0=read
  rand logic [31:0] wdata;  // write data
  rand logic [3:0]  wstrb;  // write byte enables
       logic [31:0] rdata;  // captured read data (output)
       logic [1:0]  resp;   // AXI response (output)

  // Constraints
  constraint c_aligned { addr[1:0] == 2'b00; }
  constraint c_strb_wr { write == 1'b1 -> wstrb inside {4'hF, 4'hC, 4'h3, 4'h1, 4'h2, 4'h4, 4'h8}; }
  constraint c_strb_rd { write == 1'b0 -> wstrb == 4'h0; }

  function new(string name = "bus_matrix_axi_seq_item");
    super.new(name);
    resp  = 2'b00;
    rdata = 32'h0;
  endfunction

  function string convert2string();
    return $sformatf("addr=0x%08x %s data=0x%08x strb=%04b resp=%02b",
      addr, write ? "WR" : "RD", write ? wdata : rdata, wstrb, resp);
  endfunction

  function void do_copy(uvm_object rhs);
    bus_matrix_axi_seq_item rhs_c;
    if (!$cast(rhs_c, rhs)) `uvm_fatal("SEQ_ITEM", "Cast failed in do_copy")
    super.do_copy(rhs);
    addr  = rhs_c.addr;  write = rhs_c.write;
    wdata = rhs_c.wdata; wstrb = rhs_c.wstrb;
    rdata = rhs_c.rdata; resp  = rhs_c.resp;
  endfunction

  function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    bus_matrix_axi_seq_item rhs_c;
    if (!$cast(rhs_c, rhs)) return 0;
    return (super.do_compare(rhs, comparer) &&
            addr == rhs_c.addr && write == rhs_c.write &&
            wdata == rhs_c.wdata && wstrb == rhs_c.wstrb);
  endfunction

endclass : bus_matrix_axi_seq_item

`endif // BUS_MATRIX_AXI_SEQ_ITEM_SV
