// sram_sb_item.sv — Side-band request (sequence item) and observed side-band
// event (monitor -> scoreboard / coverage).

`ifndef SRAM_SB_ITEM_SV
`define SRAM_SB_ITEM_SV

typedef enum int unsigned {
  SbMode   = 0,   // set the requested power mode of domain `dom`
  SbClear  = 1,   // pulse clr_req
  SbInject = 2,   // pulse ecc_inj = inj
  SbBist   = 3,   // pulse bist_start
  SbFault  = 4,   // read-path fault: bf_on/addr/bit/val = fault_on/addr/bit/val
  SbWait   = 5    // wait `cycles` clock cycles
} sram_sb_op_e;

typedef enum int unsigned {
  ModeRun   = 0,
  ModeLs    = 1,
  ModeDs    = 2,
  ModeSd    = 3
} sram_pwr_mode_e;

class sram_sb_item extends uvm_sequence_item;

  rand sram_sb_op_e    op;
  rand int unsigned    dom;
  rand sram_pwr_mode_e mode;
  rand bit [1:0]       inj;
  bit                  fault_on;
  int unsigned         fault_addr;
  int unsigned         fault_bit = 3;
  bit                  fault_val = 1'b0;
  rand int unsigned    cycles;
  bit                  wait_done = 1'b1;  // block until ack / done

  constraint c_inj {
    inj inside {2'b01, 2'b10};
  }
  constraint c_cycles {
    cycles inside {[1:50]};
  }

  `uvm_object_utils_begin(sram_sb_item)
    `uvm_field_enum(sram_sb_op_e, op, UVM_DEFAULT)
    `uvm_field_int(dom, UVM_DEFAULT)
    `uvm_field_enum(sram_pwr_mode_e, mode, UVM_DEFAULT)
    `uvm_field_int(inj, UVM_DEFAULT)
    `uvm_field_int(cycles, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "sram_sb_item");
    super.new(name);
  endfunction

  function string convert2string();
    case (op)
      SbMode:   return $sformatf("mode dom %0d -> %s", dom, mode.name());
      SbInject: return $sformatf("inject 0b%b", inj);
      SbFault:  return $sformatf("fault %0b word %0d bit %0d stuck at %0b", fault_on,
                                 fault_addr, fault_bit, fault_val);
      SbWait:   return $sformatf("wait %0d", cycles);
      default:  return op.name();
    endcase
  endfunction

endclass : sram_sb_item

typedef enum int unsigned {
  EvReq       = 0,   // requested mode of `dom` changed to `val` (from `old`)
  EvAck       = 1,   // acknowledged mode of `dom` changed
  EvClrReq    = 2,
  EvClrDone   = 3,
  EvBistStart = 4,
  EvBistDone  = 5,   // fail / fail_addr valid
  EvInj       = 6,   // val = ecc_inj
  EvIrq       = 7,   // one cycle with err_irq high
  EvCorr      = 8,
  EvUncorr    = 9,
  EvFault     = 10   // read-path fault knob changed: val = on, dom = word, old = bit, fail = value
} sram_sb_ev_e;

class sram_sb_event extends uvm_object;
  `uvm_object_utils(sram_sb_event)

  sram_sb_ev_e kind;
  int unsigned dom;
  int unsigned val;
  int unsigned old;
  bit          fail;
  int unsigned fail_addr;
  realtime     t;

  function new(string name = "sram_sb_event");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("%s dom %0d %0d->%0d @%0t", kind.name(), dom, old, val, t);
  endfunction

endclass : sram_sb_event

`endif // SRAM_SB_ITEM_SV
