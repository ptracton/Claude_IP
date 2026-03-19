// timer_base_seq.sv — UVM sequences for Timer APB4 testbench.
//
// Contains:
//   timer_base_seq    : abstract base; provides helper tasks write_reg/read_reg
//   timer_reg_rw_seq  : write CTRL and LOAD, read back and verify
//   timer_irq_seq     : write LOAD/CTRL, poll STATUS until INTR=1, then W1C
//
// Register map (APB byte addresses):
//   CTRL   @ 0x000
//   STATUS @ 0x004
//   LOAD   @ 0x008
//   COUNT  @ 0x00C
//
// NOTE: Requires a UVM-capable simulator (VCS, Questasim, or Riviera-PRO).
//       Not compatible with Icarus Verilog or GHDL.

// =============================================================================
// timer_base_seq
// =============================================================================
class timer_base_seq extends uvm_sequence #(timer_seq_item);

  `uvm_object_utils(timer_base_seq)

  // Register address constants
  localparam logic [11:0] ADDR_CTRL   = 12'h000;
  localparam logic [11:0] ADDR_STATUS = 12'h004;
  localparam logic [11:0] ADDR_LOAD   = 12'h008;
  localparam logic [11:0] ADDR_COUNT  = 12'h00C;

  function new(string name = "timer_base_seq");
    super.new(name);
  endfunction

  // -------------------------------------------------------------------------
  // write_reg — send a single APB write transaction
  // -------------------------------------------------------------------------
  task write_reg(input logic [11:0] addr,
                 input logic [31:0] data,
                 input logic [3:0]  strb = 4'hF);
    timer_seq_item item;
    `uvm_create(item)
    item.addr  = addr;
    item.data  = data;
    item.strb  = strb;
    item.write = 1'b1;
    `uvm_send(item)
    `uvm_info("SEQ",
      $sformatf("write_reg addr=0x%03X data=0x%08X strb=0x%X",
                addr, data, strb),
      UVM_MEDIUM)
  endtask

  // -------------------------------------------------------------------------
  // read_reg — send a single APB read transaction; returns data in rdata_out
  // -------------------------------------------------------------------------
  task read_reg(input  logic [11:0] addr,
                output logic [31:0] rdata_out);
    timer_seq_item item;
    `uvm_create(item)
    item.addr  = addr;
    item.write = 1'b0;
    item.strb  = 4'h0;
    `uvm_send(item)
    rdata_out = item.rdata;
    `uvm_info("SEQ",
      $sformatf("read_reg  addr=0x%03X rdata=0x%08X", addr, item.rdata),
      UVM_MEDIUM)
  endtask

  virtual task body();
    // Base class body is empty; override in derived sequences
  endtask

endclass : timer_base_seq


// =============================================================================
// timer_reg_rw_seq
//
// 1. Write CTRL = 0x5  (EN=1, MODE=0, INTR_EN=1, TRIG_EN=0, PRESCALE=0)
// 2. Write LOAD = 8
// 3. Read  back CTRL — compare against expected 0x5
// 4. Read  back LOAD — compare against expected 8
// =============================================================================
class timer_reg_rw_seq extends timer_base_seq;

  `uvm_object_utils(timer_reg_rw_seq)

  function new(string name = "timer_reg_rw_seq");
    super.new(name);
  endfunction

  task body();
    logic [31:0] rdata;

    `uvm_info("SEQ", "--- timer_reg_rw_seq START ---", UVM_LOW)

    // Write CTRL: EN[0]=1, INTR_EN[2]=1  =>  0x0000_0005
    write_reg(ADDR_CTRL, 32'h0000_0005);

    // Write LOAD: VALUE = 8
    write_reg(ADDR_LOAD, 32'h0000_0008);

    // Read back CTRL
    read_reg(ADDR_CTRL, rdata);
    if ((rdata & 32'h00000FFF) !== 32'h0000_0005) begin
      `uvm_error("SEQ",
        $sformatf("timer_reg_rw_seq: CTRL mismatch exp=0x00000005 got=0x%08X",
                  rdata & 32'h00000FFF))
    end else begin
      `uvm_info("SEQ", "CTRL read-back PASS", UVM_LOW)
    end

    // Read back LOAD
    read_reg(ADDR_LOAD, rdata);
    if (rdata !== 32'h0000_0008) begin
      `uvm_error("SEQ",
        $sformatf("timer_reg_rw_seq: LOAD mismatch exp=0x00000008 got=0x%08X",
                  rdata))
    end else begin
      `uvm_info("SEQ", "LOAD read-back PASS", UVM_LOW)
    end

    `uvm_info("SEQ", "--- timer_reg_rw_seq END ---", UVM_LOW)
  endtask

endclass : timer_reg_rw_seq


// =============================================================================
// timer_irq_seq
//
// 1. Write LOAD = 4  (short count so IRQ fires quickly)
// 2. Write CTRL = 0x5  (EN=1, INTR_EN=1)
// 3. Poll STATUS[INTR] (bit 0) for up to 200 read iterations
// 4. If INTR seen: W1C — write STATUS = 0x1 to clear; verify cleared
// 5. If timeout:   report uvm_error
// =============================================================================
class timer_irq_seq extends timer_base_seq;

  `uvm_object_utils(timer_irq_seq)

  // Maximum number of STATUS polls before declaring a timeout
  int unsigned max_poll = 200;

  function new(string name = "timer_irq_seq");
    super.new(name);
  endfunction

  task body();
    logic [31:0] rdata;
    int unsigned poll_count;
    bit          irq_seen;

    `uvm_info("SEQ", "--- timer_irq_seq START ---", UVM_LOW)

    // Load a short count value so the interrupt fires quickly
    write_reg(ADDR_LOAD, 32'h0000_0004);

    // Enable timer and interrupt: EN[0]=1, INTR_EN[2]=1 => 0x5
    write_reg(ADDR_CTRL, 32'h0000_0005);

    // Poll STATUS until INTR bit (bit 0) is set
    irq_seen   = 1'b0;
    poll_count = 0;

    while (poll_count < max_poll) begin
      read_reg(ADDR_STATUS, rdata);
      if (rdata[0]) begin
        irq_seen = 1'b1;
        `uvm_info("SEQ",
          $sformatf("IRQ seen after %0d polls, STATUS=0x%08X",
                    poll_count + 1, rdata),
          UVM_LOW)
        break;
      end
      poll_count++;
    end

    if (!irq_seen) begin
      `uvm_error("SEQ",
        $sformatf("timer_irq_seq: INTR not seen within %0d polls", max_poll))
    end else begin
      // W1C — write 1 to STATUS[INTR] to clear it
      write_reg(ADDR_STATUS, 32'h0000_0001);

      // Verify INTR bit is now clear
      read_reg(ADDR_STATUS, rdata);
      if (rdata[0] !== 1'b0) begin
        `uvm_error("SEQ",
          $sformatf("timer_irq_seq: W1C failed, STATUS=0x%08X still set",
                    rdata))
      end else begin
        `uvm_info("SEQ", "W1C clear PASS — INTR bit cleared", UVM_LOW)
      end
    end

    `uvm_info("SEQ", "--- timer_irq_seq END ---", UVM_LOW)
  endtask

endclass : timer_irq_seq
