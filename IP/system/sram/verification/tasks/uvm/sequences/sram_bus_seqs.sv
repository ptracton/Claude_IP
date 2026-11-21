// sram_bus_seqs.sv — Bus sequences of one sram port.
//
// sram_rand_seq: `n` constrained-random transfers. Knobs (set before start):
//   pct_write, pct_oor (address past the port's span), pct_burst (AHB burst
//   kinds; the other protocols issue the same address run as single
//   transfers), pct_sub (sub-word size), pct_zero_strb, idle_max,
//   win[] (storage-byte windows [lo, hi) the in-range addresses stay in;
//   empty = the whole array; both ports address the same bytes).
//   Addresses favour the first and last word of each window.
// sram_fill_seq: write (or read) every word of a byte range in order.

`ifndef SRAM_BUS_SEQS_SV
`define SRAM_BUS_SEQS_SV

typedef struct {
  int unsigned lo;
  int unsigned hi;
} sram_win_t;

class sram_rand_seq extends uvm_sequence #(sram_bus_item);
  `uvm_object_utils(sram_rand_seq)
  `uvm_declare_p_sequencer(sram_bus_sequencer)

  int unsigned n             = 100;
  int unsigned pct_write     = 50;
  int unsigned pct_oor       = 3;
  int unsigned pct_burst     = 15;
  int unsigned pct_sub       = 25;
  int unsigned pct_zero_strb = 2;
  int unsigned pct_part_strb = 15;
  int unsigned idle_max      = 20;
  sram_win_t   win [$];

  function new(string name = "sram_rand_seq");
    super.new(name);
  endfunction

  // A random in-range byte address of the port, aligned to 2**sz, such that
  // `len` bytes from it stay inside one window (and one 1 KB AHB boundary).
  function bit [31:0] pick_addr(int unsigned sz, int unsigned len, bit wrap = 1'b0);
    sram_uvm_cfg cfg;
    int unsigned p, stride, nb, lo, hi, w, a, r;
    cfg    = p_sequencer.cfg;
    p      = p_sequencer.port;
    stride = cfg.stride[p];
    nb     = cfg.bytes_per_word(p);
    if (win.size() == 0) begin
      lo = 0;
      hi = cfg.span(p);
    end else begin
      w  = $urandom_range(win.size() - 1);
      lo = win[w].lo;
      hi = win[w].hi;
    end
    if (hi - lo < len) len = hi - lo;
    r = $urandom_range(9);
    if (r == 0) a = lo;                                    // first word
    else if (r == 1) a = hi - len;                         // last word(s)
    else a = $urandom_range(hi - len, lo);
    a = a & ~((1 << sz) - 1);
    if (len > 1) a = a - (a % len);                        // keep the run aligned
    if (a < lo) a = lo;
    // AHB: a burst must not cross a 1 KB boundary
    if ((a / 1024) != ((a + len - 1) / 1024)) a = ((a + len - 1) / 1024) * 1024 - len;
    // stay inside the byte lanes of a word (24-bit words have a hole)
    if ((a % stride) >= nb) a = a - (a % stride);
    // WRAP: start anywhere in the aligned block, so the burst wraps
    if (wrap && len > (1 << sz)) a = a + ($urandom_range((len >> sz) - 1) << sz);
    return a;
  endfunction

  task body();
    sram_uvm_cfg  cfg;
    sram_bus_item it;
    int unsigned  p, msz, sz, beats, len;
    bit [31:0]    ad;
    sram_burst_e  k;
    cfg = p_sequencer.cfg;
    p   = p_sequencer.port;
    msz = cfg.max_size(p);
    for (int unsigned i = 0; i < n; i++) begin
      it          = sram_bus_item::type_id::create("it");
      it.port     = p;
      it.max_size = msz;
      sz          = ($urandom_range(99) < pct_sub && msz > 0) ? $urandom_range(msz - 1) : msz;
      k           = BurstSingle;
      if ($urandom_range(99) < pct_burst) begin
        k = sram_burst_e'($urandom_range(7, 1));
      end
      beats = (k == BurstSingle) ? 1 : (k == BurstIncr) ? $urandom_range(16, 2) :
              (k inside {BurstWrap4, BurstIncr4}) ? 4 :
              (k inside {BurstWrap8, BurstIncr8}) ? 8 : 16;
      len   = beats << sz;
      start_item(it);
      if ($urandom_range(99) < pct_oor) begin
        // out of range: just past the end, or far away
        // (the bench's bus address is 16 bits wide: stay below 64 KB)
        ad    = ($urandom_range(1) == 0) ? cfg.span(p) + $urandom_range(cfg.span(p) - 1) :
                $urandom_range(32'hFFFF, cfg.span(p));
        ad    = ad & ~((1 << sz) - 1);
        k     = BurstSingle;
        beats = 1;
      end else begin
        ad = pick_addr(sz, len, k inside {BurstWrap4, BurstWrap8, BurstWrap16});
      end
      if (!it.randomize() with {
            addr == local::ad;
            size == local::sz;
            kind == local::k;
            beats == local::beats;
            we dist {1 := pct_write, 0 := 100 - pct_write};
            idle <= idle_max;
          }) begin
        `uvm_fatal("SEQ", "randomize failed")
      end
      // write strobes of the first beat (within its HSIZE lanes)
      it.strb = 8'hFF;
      if (it.we && $urandom_range(99) < pct_zero_strb) begin
        it.strb = 8'h00;
      end else if (it.we && $urandom_range(99) < pct_part_strb) begin
        it.strb = 8'($urandom());
        if (it.strb == 8'h00) it.strb = 8'h01;
      end
      finish_item(it);
    end
  endtask

endclass : sram_rand_seq

class sram_fill_seq extends uvm_sequence #(sram_bus_item);
  `uvm_object_utils(sram_fill_seq)
  `uvm_declare_p_sequencer(sram_bus_sequencer)

  int unsigned lo = 0;           // storage bytes [lo, hi)
  int unsigned hi = 0;           // 0 = the whole span
  bit          we = 1'b1;
  bit          zero_idle = 1'b1;

  function new(string name = "sram_fill_seq");
    super.new(name);
  endfunction

  task body();
    sram_uvm_cfg  cfg;
    sram_bus_item it;
    int unsigned  p, stride, h;
    cfg    = p_sequencer.cfg;
    p      = p_sequencer.port;
    stride = cfg.stride[p];
    h      = (hi == 0) ? cfg.span(p) : hi;
    for (int unsigned a = lo; a < h; a += stride) begin
      it          = sram_bus_item::type_id::create("it");
      it.port     = p;
      it.max_size = cfg.max_size(p);
      start_item(it);
      if (!it.randomize() with {
            addr == local::a;
            size == local::cfg.max_size(local::p);
            kind == BurstSingle;
            we == local::we;
            zero_idle -> idle == 0;
          }) begin
        `uvm_fatal("SEQ", "randomize failed")
      end
      it.strb = 8'hFF;
      finish_item(it);
    end
  endtask

endclass : sram_fill_seq

`endif // SRAM_BUS_SEQS_SV
