// timer_seq_item.sv — UVM sequence item for Timer APB4 testbench.
//
// Represents a single APB4 transaction (read or write) to the Timer IP.
// Register map:
//   CTRL   @ 0x000 : EN[0], MODE[1], INTR_EN[2], TRIG_EN[3], PRESCALE[11:4]
//   STATUS @ 0x004 : INTR[0] W1C, ACTIVE[1] RO
//   LOAD   @ 0x008 : VALUE[31:0]
//   COUNT  @ 0x00C : VALUE[31:0] RO
//
// NOTE: Requires a UVM-capable simulator (VCS, Questasim, or Riviera-PRO).
//       Not compatible with Icarus Verilog or GHDL.

class timer_seq_item extends uvm_sequence_item;

  // -------------------------------------------------------------------------
  // Fields
  // -------------------------------------------------------------------------
  rand logic [11:0] addr;   // APB byte address — constrained to valid regs
  rand logic [31:0] data;   // write data
  rand logic [3:0]  strb;   // APB byte strobes (PSTRB)
  rand logic        write;  // 1 = write, 0 = read

  logic [31:0] rdata;       // captured read-data (not randomized)

  // -------------------------------------------------------------------------
  // UVM factory registration
  // -------------------------------------------------------------------------
  `uvm_object_utils_begin(timer_seq_item)
    `uvm_field_int(addr,  UVM_ALL_ON)
    `uvm_field_int(data,  UVM_ALL_ON)
    `uvm_field_int(strb,  UVM_ALL_ON)
    `uvm_field_int(write, UVM_ALL_ON)
    `uvm_field_int(rdata, UVM_ALL_ON)
  `uvm_object_utils_end

  // -------------------------------------------------------------------------
  // Constraints
  // -------------------------------------------------------------------------

  // Only target the four defined register addresses
  constraint c_valid_addr {
    addr inside {12'h000, 12'h004, 12'h008, 12'h00C};
  }

  // Byte strobes must be non-zero on a write
  constraint c_strb_write {
    write -> (strb != 4'h0);
  }

  // Default to full-word strobe when writing (can be overridden)
  constraint c_strb_default {
    write -> (strb == 4'hF);
  }

  // -------------------------------------------------------------------------
  // Constructor
  // -------------------------------------------------------------------------
  function new(string name = "timer_seq_item");
    super.new(name);
  endfunction

  // -------------------------------------------------------------------------
  // convert2string — human-readable for debug messages
  // -------------------------------------------------------------------------
  function string convert2string();
    return $sformatf(
      "timer_seq_item: %s addr=0x%03X data=0x%08X strb=0x%X rdata=0x%08X",
      write ? "WRITE" : "READ",
      addr, data, strb, rdata
    );
  endfunction

endclass : timer_seq_item
