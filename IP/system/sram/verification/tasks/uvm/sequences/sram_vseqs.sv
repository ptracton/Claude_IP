// sram_vseqs.sv — Virtual sequences of the sram UVM bench (one per test).
//
//   sram_base_vseq    helpers: traffic, fill, side-band ops, barriers
//   sram_smoke_vseq   fill + read back through every port (cross-port on a dual port)
//   sram_random_vseq  constrained-random traffic, all ports (dual port: epochs)
//   sram_power_vseq   random power-mode walk per domain with traffic around it
//   sram_clear_vseq   clear quiet and under traffic, banked modes at the request
//   sram_ecc_vseq     single / double injection, consumed by full writes and RMWs,
//                     detected by reads and RMWs, then rewritten
//   sram_bist_vseq    BIST quiet, under traffic, and with a stuck-at fault
//   sram_dp_vseq      ownership epochs: each port writes its blocks, the other reads them
//   sram_stress_vseq  everything at once (except ECC injection, which needs port A quiet)
//
// Dual port on separate clocks: the two ports never touch the same word at the
// same time (undefined on a true dual-port RAM); traffic of the two ports runs
// in disjoint 64-byte blocks whose owner changes between epochs, at a barrier.

`ifndef SRAM_VSEQS_SV
`define SRAM_VSEQS_SV

class sram_base_vseq extends uvm_sequence;
  `uvm_object_utils(sram_base_vseq)
  `uvm_declare_p_sequencer(sram_vsequencer)

  localparam int unsigned BLK = 64;   // dual-port ownership block (bytes)

  sram_uvm_cfg cfg;
  int unsigned scale = 1;             // +SCALE=<n> multiplies the transfer counts

  function new(string name = "sram_base_vseq");
    super.new(name);
  endfunction

  task pre_body();
    cfg = p_sequencer.cfg;
    void'($value$plusargs("SCALE=%d", scale));
    if (scale == 0) scale = 1;
  endtask

  // ---- bus ----------------------------------------------------------------------
  task traffic(int unsigned p, int unsigned n, sram_win_t win [$] = {},
               int unsigned pct_write = 50, int unsigned pct_oor = 3,
               int unsigned idle_max = 20);
    sram_rand_seq s;
    s           = sram_rand_seq::type_id::create($sformatf("rand_%0d", p));
    s.n         = n * scale;
    s.win       = win;
    s.pct_write = pct_write;
    s.pct_oor   = pct_oor;
    s.idle_max  = idle_max;
    if (cfg.proto != "ahb") s.pct_burst = 5;
    s.start(p_sequencer.bus_sqr[p], this);
  endtask

  // Write (or read) every word of storage bytes [lo, hi) through port p.
  task fill(int unsigned p, bit we = 1'b1, int unsigned lo = 0, int unsigned hi = 0);
    sram_fill_seq s;
    s    = sram_fill_seq::type_id::create($sformatf("fill_%0d", p));
    s.we = we;
    s.lo = lo;
    s.hi = hi;
    s.start(p_sequencer.bus_sqr[p], this);
  endtask

  // One transfer through port p.
  task xfer(int unsigned p, bit we, bit [31:0] addr, int unsigned size = 99,
            bit [7:0] strb = 8'hFF, bit [63:0] data = '0, bit rnd_data = 1'b1);
    sram_bus_item it;
    it          = sram_bus_item::type_id::create("x");
    it.port     = p;
    it.max_size = cfg.max_size(p);
    if (size == 99) size = cfg.max_size(p);
    start_item(it, -1, p_sequencer.bus_sqr[p]);
    if (!it.randomize() with {
          addr == local::addr;
          size == local::size;
          kind == BurstSingle;
          we == local::we;
          idle == 0;
        }) begin
      `uvm_fatal("VSEQ", "randomize failed")
    end
    it.strb = strb;
    if (!rnd_data) it.wdata[0] = data;
    finish_item(it);
  endtask

  task quiesce();
    for (int unsigned p = 0; p < cfg.nports(); p++) p_sequencer.bus_sqr[p].wait_idle();
  endtask

  // Whole array through every port, read back (makes later reads comparable).
  task fill_all();
    fill(0);
    quiesce();
  endtask

  task read_all();
    for (int unsigned p = 0; p < cfg.nports(); p++) fill(p, 1'b0);
    quiesce();
  endtask

  // ---- side band ----------------------------------------------------------------
  task sb_op(sram_sb_op_e op, int unsigned dom = 0, sram_pwr_mode_e mode = ModeRun,
             bit [1:0] inj = 2'b01, int unsigned cycles = 1, bit wait_done = 1'b1,
             bit fault_on = 1'b0, int unsigned fault_addr = 0,
             int unsigned fault_bit = 3, bit fault_val = 1'b0);
    sram_sb_item it;
    it            = sram_sb_item::type_id::create("sb");
    it.op         = op;
    it.dom        = dom;
    it.mode       = mode;
    it.inj        = inj;
    it.cycles     = cycles;
    it.wait_done  = wait_done;
    it.fault_on   = fault_on;
    it.fault_addr = fault_addr;
    it.fault_bit  = fault_bit;
    it.fault_val  = fault_val;
    start_item(it, -1, p_sequencer.sb_sqr);
    finish_item(it);
  endtask

  task set_mode(int unsigned d, sram_pwr_mode_e m, bit wait_done = 1'b1);
    sb_op(SbMode, d, m, 2'b01, 1, wait_done);
  endtask

  task all_run();
    for (int unsigned d = 0; d < cfg.npd; d++) set_mode(d, ModeRun);
  endtask

  task wait_cycles(int unsigned n);
    sb_op(SbWait, 0, ModeRun, 2'b01, n);
  endtask

  // ---- dual-port ownership --------------------------------------------------------
  // Split the array into BLK-byte blocks; each goes to port A, port B or neither.
  task epoch_windows(output sram_win_t wa [$], output sram_win_t wb [$]);
    sram_win_t w;
    wa.delete();
    wb.delete();
    for (int unsigned b = 0; b < cfg.total_bytes / BLK; b++) begin
      w.lo = b * BLK;
      w.hi = (b + 1) * BLK;
      case ($urandom_range(2))
        0: wa.push_back(w);
        1: wb.push_back(w);
        default: ;
      endcase
    end
    if (wa.size() == 0) begin
      w.lo = 0;
      w.hi = BLK;
      wa.push_back(w);
    end
    if (wb.size() == 0) begin
      w.lo = cfg.total_bytes - BLK;
      w.hi = cfg.total_bytes;
      wb.push_back(w);
    end
  endtask

  // Random traffic on every port; a dual port runs `epochs` ownership epochs.
  task traffic_all(int unsigned n, int unsigned epochs = 4, int unsigned pct_oor = 3);
    if (!cfg.dual_port) begin
      traffic(0, n, {}, 50, pct_oor);
      p_sequencer.bus_sqr[0].wait_idle();
      return;
    end
    for (int unsigned e = 0; e < epochs; e++) begin
      sram_win_t wa [$];
      sram_win_t wb [$];
      epoch_windows(wa, wb);
      fork
        traffic(0, n / epochs, wa, 50, pct_oor);
        traffic(1, (n / epochs) * cfg.width[0] / cfg.width[1] / 2, wb, 50, pct_oor);
      join
      quiesce();
    end
  endtask

endclass : sram_base_vseq

// ---------------------------------------------------------------------------------
class sram_smoke_vseq extends sram_base_vseq;
  `uvm_object_utils(sram_smoke_vseq)

  function new(string name = "sram_smoke_vseq");
    super.new(name);
  endfunction

  task body();
    // before anything is written: zero after the reset clear (ECC), else unknown
    fill(0, 1'b0, 0, cfg.total_bytes / 8);
    quiesce();
    fill(0);
    quiesce();
    read_all();
    if (cfg.dual_port) begin
      // port B writes the first quarter (errors on a read-only port B), A reads it
      fill(1, 1'b1, 0, cfg.total_bytes / 4);
      quiesce();
      fill(0, 1'b0);
      quiesce();
    end
    for (int unsigned p = 0; p < cfg.nports(); p++) begin
      sram_win_t none [$];
      traffic(p, 200, none, 50, 5);
      quiesce();
    end
  endtask

endclass : sram_smoke_vseq

// ---------------------------------------------------------------------------------
class sram_random_vseq extends sram_base_vseq;
  `uvm_object_utils(sram_random_vseq)

  function new(string name = "sram_random_vseq");
    super.new(name);
  endfunction

  task body();
    fill_all();
    traffic_all(3000, 8);
    read_all();
  endtask

endclass : sram_random_vseq

// ---------------------------------------------------------------------------------
class sram_power_vseq extends sram_base_vseq;
  `uvm_object_utils(sram_power_vseq)

  function new(string name = "sram_power_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned    d;
    sram_pwr_mode_e m;
    bit             w;
    if (!cfg.pwr_gate) begin
      `uvm_info("VSEQ", "PWR_GATE = 0: power test skipped", UVM_NONE)
      return;
    end
    fill_all();
    for (int unsigned i = 0; i < 40 * scale; i++) begin
      d = $urandom_range(cfg.npd - 1);
      m = sram_pwr_mode_e'($urandom_range(3));
      w = ($urandom_range(3) != 0);
      fork
        set_mode(d, m, w);
        traffic_all(60, 1, 0);
      join
      // traffic in the settled mode (errors in DS / SD, wait states in LS)
      traffic_all(40, 1, 0);
      if ($urandom_range(3) == 0) begin
        // wake everything and look at the contents (SD domains read zero)
        all_run();
        read_all();
      end
    end
    all_run();
    read_all();
  endtask

endclass : sram_power_vseq

// ---------------------------------------------------------------------------------
class sram_clear_vseq extends sram_base_vseq;
  `uvm_object_utils(sram_clear_vseq)

  function new(string name = "sram_clear_vseq");
    super.new(name);
  endfunction

  task body();
    // quiet clear
    fill_all();
    sb_op(SbClear);
    read_all();
    // clear under traffic (beats spanning the request are ambiguous)
    for (int unsigned i = 0; i < 4 * scale; i++) begin
      fill_all();
      fork
        traffic_all(200, 1);
        begin
          wait_cycles($urandom_range(200, 20));
          sb_op(SbClear);
        end
      join
      read_all();
    end
    // modes at the request: RUN / LS cleared, DS kept, SD lost
    if (cfg.pwr_gate) begin
      for (int unsigned i = 0; i < 3 * scale; i++) begin
        fill_all();
        for (int unsigned d = 0; d < cfg.npd; d++) begin
          set_mode(d, sram_pwr_mode_e'($urandom_range(3)));
        end
        sb_op(SbClear);
        all_run();
        read_all();
      end
    end
  endtask

endclass : sram_clear_vseq

// ---------------------------------------------------------------------------------
class sram_ecc_vseq extends sram_base_vseq;
  `uvm_object_utils(sram_ecc_vseq)

  function new(string name = "sram_ecc_vseq");
    super.new(name);
  endfunction

  task body();
    bit [31:0]   a;
    bit [1:0]    k;
    int unsigned nb;
    if (!cfg.ecc) begin
      `uvm_info("VSEQ", "ECC_EN = 0: ECC test skipped", UVM_NONE)
      return;
    end
    nb = cfg.bytes_per_word(0);
    fill_all();
    for (int unsigned i = 0; i < 30 * scale; i++) begin
      a = $urandom_range(cfg.depth[0] - 1) * cfg.stride[0];
      k = ($urandom_range(1) == 0) ? 2'b01 : 2'b10;
      quiesce();
      sb_op(SbInject, 0, ModeRun, k);
      // consumed by a full write or by a partial write (read-modify-write)
      if ($urandom_range(1) == 0) xfer(0, 1'b1, a);
      else xfer(0, 1'b1, a, cfg.max_size(0), 8'(1 << $urandom_range(nb - 1)));
      xfer(0, 1'b0, a);                                      // detect by a read
      xfer(0, 1'b1, a, 0, 8'h01);                            // ... and by an RMW
      xfer(0, 1'b0, a);
      xfer(0, 1'b1, a);                                      // rewrite: clean again
      xfer(0, 1'b0, a);
      quiesce();
      traffic(0, 50);
      quiesce();
    end
    // A single error at every data bit position: the read-path knob holds
    // bit j of one word at 0 and then at 1 (one of the two differs from the
    // stored bit); sometimes a byte write (RMW) corrects and rewrites it.
    a = $urandom_range(cfg.depth[0] - 1);
    xfer(0, 1'b1, a * cfg.stride[0]);
    for (int unsigned j = 0; j < cfg.width[0]; j++) begin
      for (int unsigned v = 0; v < 2; v++) begin
        quiesce();
        sb_op(SbFault, 0, ModeRun, 2'b01, 1, 1'b1, 1'b1, a, j, v[0]);
        xfer(0, 1'b0, a * cfg.stride[0]);
        if ($urandom_range(3) == 0) xfer(0, 1'b1, a * cfg.stride[0] + j / 8, 0, 8'h01);
        quiesce();
        sb_op(SbFault, 0, ModeRun, 2'b01, 1, 1'b1, 1'b0, a, j, v[0]);
      end
    end
    xfer(0, 1'b0, a * cfg.stride[0]);
    // Double errors with every syndrome the knob can add to an injected
    // single error on bit 0: inject, write the word, sweep the knob.
    quiesce();
    sb_op(SbInject, 0, ModeRun, 2'b01);
    xfer(0, 1'b1, a * cfg.stride[0]);
    for (int unsigned j = 0; j < cfg.width[0]; j++) begin
      for (int unsigned v = 0; v < 2; v++) begin
        quiesce();
        sb_op(SbFault, 0, ModeRun, 2'b01, 1, 1'b1, 1'b1, a, j, v[0]);
        xfer(0, 1'b0, a * cfg.stride[0]);
        quiesce();
        sb_op(SbFault, 0, ModeRun, 2'b01, 1, 1'b1, 1'b0, a, j, v[0]);
      end
    end
    xfer(0, 1'b1, a * cfg.stride[0]);                        // clean again
    xfer(0, 1'b0, a * cfg.stride[0]);
    quiesce();
  endtask

endclass : sram_ecc_vseq

// ---------------------------------------------------------------------------------
class sram_bist_vseq extends sram_base_vseq;
  `uvm_object_utils(sram_bist_vseq)

  function new(string name = "sram_bist_vseq");
    super.new(name);
  endfunction

  task body();
    if (!cfg.bist) begin
      `uvm_info("VSEQ", "BIST_EN = 0: BIST test skipped", UVM_NONE)
      return;
    end
    // quiet, passing
    fill_all();
    sb_op(SbBist);
    read_all();
    // stuck-at-0 fault: fails at that word
    for (int unsigned i = 0; i < 2; i++) begin
      int unsigned w;
      w = $urandom_range(cfg.depth[0] - 1);
      sb_op(SbFault, 0, ModeRun, 2'b01, 1, 1'b1, 1'b1, w);
      sb_op(SbBist);
      sb_op(SbFault, 0, ModeRun, 2'b01, 1, 1'b1, 1'b0, 0);
      read_all();
    end
    // under traffic (beats spanning the start are ambiguous)
    for (int unsigned i = 0; i < 2 * scale; i++) begin
      fill_all();
      fork
        traffic_all(300, 1);
        begin
          wait_cycles($urandom_range(100, 10));
          sb_op(SbBist);
        end
      join
      read_all();
    end
  endtask

endclass : sram_bist_vseq

// ---------------------------------------------------------------------------------
class sram_dp_vseq extends sram_base_vseq;
  `uvm_object_utils(sram_dp_vseq)

  function new(string name = "sram_dp_vseq");
    super.new(name);
  endfunction

  task body();
    if (!cfg.dual_port) begin
      `uvm_info("VSEQ", "single port: dual-port test skipped", UVM_NONE)
      return;
    end
    fill_all();
    traffic_all(4000, 20, 2);
    read_all();
  endtask

endclass : sram_dp_vseq

// ---------------------------------------------------------------------------------
class sram_stress_vseq extends sram_base_vseq;
  `uvm_object_utils(sram_stress_vseq)

  function new(string name = "sram_stress_vseq");
    super.new(name);
  endfunction

  task body();
    bit done;
    fill_all();
    done = 1'b0;
    fork
      begin
        traffic_all(4000, 10);
        done = 1'b1;
      end
      begin
        // side-band walker: modes, clears, BIST, in random order
        while (!done) begin
          int unsigned r;
          r = $urandom_range(9);
          if (r < 6 && cfg.pwr_gate) begin
            set_mode($urandom_range(cfg.npd - 1), sram_pwr_mode_e'($urandom_range(3)),
                     $urandom_range(1));
          end else if (r < 8) begin
            sb_op(SbClear);
          end else if (cfg.bist) begin
            all_run();
            sb_op(SbBist);
          end
          wait_cycles($urandom_range(400, 50));
        end
      end
    join
    all_run();
    read_all();
  endtask

endclass : sram_stress_vseq

`endif // SRAM_VSEQS_SV
