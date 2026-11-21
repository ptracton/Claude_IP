// sram_bus_item.sv — One bus request (sequence item) or one observed beat.
//
// Request (sequence -> driver): a transfer of `beats` beats starting at
// `addr`, `size` = log2(bytes) per beat (AHB HSIZE; the other protocols use
// it to pick the byte lanes), `strb` = write strobes of beat 0 within those
// lanes (later beats of a burst write all lanes), `kind` = AHB burst type
// (the other protocols issue the same address sequence as back-to-back
// single transfers), `busy` = AHB BUSY cycles before each beat (idle cycles
// on the other protocols), `idle` = idle cycles before the transfer.
//
// Observation (monitor -> scoreboard / coverage): one item per beat with
// beats = 1 and the effective byte enables `be`, the response (`rdata`,
// `err`) and the times the beat started (address presented) and ended
// (response).

`ifndef SRAM_BUS_ITEM_SV
`define SRAM_BUS_ITEM_SV

typedef enum int unsigned {
  BurstSingle = 0,
  BurstIncr   = 1,
  BurstWrap4  = 2,
  BurstIncr4  = 3,
  BurstWrap8  = 4,
  BurstIncr8  = 5,
  BurstWrap16 = 6,
  BurstIncr16 = 7
} sram_burst_e;

class sram_bus_item extends uvm_sequence_item;

  localparam int unsigned MAX_BEATS = 16;

  int unsigned      port;                  // 0 = A, 1 = B
  rand bit          we;
  rand bit [31:0]   addr;
  rand int unsigned size;
  rand bit [7:0]    strb;
  rand sram_burst_e kind;
  rand int unsigned beats;
  rand bit [63:0]   wdata [];
  rand int unsigned busy  [];
  rand int unsigned idle;

  // Observation
  bit [7:0]         be;                    // byte enables of the beat
  logic [63:0]      rdata;
  bit               err;
  int unsigned      beat;                  // index in its burst
  realtime          t_start;
  realtime          t_end;
  bit               overlap;               // AXI: another transfer was in flight

  // Limits filled in by the sequence before randomize()
  int unsigned      max_size;

  constraint c_beats {
    beats inside {[1:MAX_BEATS]};
    kind == BurstSingle -> beats == 1;
    kind inside {BurstWrap4, BurstIncr4}   -> beats == 4;
    kind inside {BurstWrap8, BurstIncr8}   -> beats == 8;
    kind inside {BurstWrap16, BurstIncr16} -> beats == 16;
    kind == BurstIncr -> beats inside {[2:MAX_BEATS]};
    wdata.size() == beats;
    busy.size() == beats;
  }
  constraint c_busy {
    foreach (busy[i]) {
      busy[i] dist {0 := 8, [1:3] := 2};
      i == 0 -> busy[i] == 0;
    }
  }
  constraint c_size {
    size <= max_size;
    addr % (1 << size) == 0;
  }
  constraint c_idle {
    idle dist {0 := 6, [1:4] := 3, [5:20] := 1};
  }
  constraint c_kind_default {
    soft kind == BurstSingle;
  }

  `uvm_object_utils_begin(sram_bus_item)
    `uvm_field_int(port, UVM_DEFAULT)
    `uvm_field_int(we, UVM_DEFAULT)
    `uvm_field_int(addr, UVM_DEFAULT)
    `uvm_field_int(size, UVM_DEFAULT)
    `uvm_field_int(strb, UVM_DEFAULT)
    `uvm_field_enum(sram_burst_e, kind, UVM_DEFAULT)
    `uvm_field_int(beats, UVM_DEFAULT)
    `uvm_field_int(be, UVM_DEFAULT)
    `uvm_field_int(rdata, UVM_DEFAULT)
    `uvm_field_int(err, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "sram_bus_item");
    super.new(name);
    max_size = 3;
  endfunction

  function bit is_wrap();
    return kind inside {BurstWrap4, BurstWrap8, BurstWrap16};
  endfunction

  // Address of beat i (AHB INCR / WRAP rules).
  function bit [31:0] beat_addr(int unsigned i);
    bit [31:0] span_b;
    bit [31:0] base;
    if (!is_wrap()) return addr + (32'(i) << size);
    span_b = 32'(beats) << size;
    base   = addr & ~(span_b - 32'd1);
    return base | ((addr + (32'(i) << size)) & (span_b - 32'd1));
  endfunction

  // Byte lanes of a beat of 2**size bytes at address a on a bus of nb bytes.
  static function bit [7:0] lane_mask(int unsigned sz, bit [31:0] a, int unsigned nb);
    bit [7:0]    m;
    int unsigned o;
    o = (nb > 1) ? (a & (nb - 1)) : 0;
    m = '0;
    for (int unsigned b = 0; b < nb; b++) m[b] = ((b >> sz) == (o >> sz));
    return m;
  endfunction

  function string convert2string();
    if (beats > 1) begin
      return $sformatf("P%0d %s 0x%08x size %0d %s x%0d", port, we ? "W" : "R", addr, size,
                       kind.name(), beats);
    end
    return $sformatf("P%0d %s 0x%08x size %0d be 0b%b wdata 0x%h rdata 0x%h err %0b", port,
                     we ? "W" : "R", addr, size, be, (wdata.size() > 0) ? wdata[0] : 64'h0,
                     rdata, err);
  endfunction

endclass : sram_bus_item

`endif // SRAM_BUS_ITEM_SV
