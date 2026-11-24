// sram_bus_driver.sv — Bus master driver for one sram port, all four protocols.
//
// The protocol comes from sram_uvm_cfg.proto. Items are taken with get()
// (the sequence does not wait for the response; the monitor reports every
// beat to the scoreboard), so AHB and AXI4-Lite can overlap one item's last
// beat with the next item's first. `pending` counts accepted items whose
// beats have not all completed; wait_idle() returns once it is zero, which
// the virtual sequences use as a barrier.
//
//   APB    SETUP / ACCESS per beat, back to back unless the item asks for
//          idle cycles.
//   AHB    address / data pipeline across beats and items; INCR / WRAP
//          bursts as NONSEQ + SEQ, BUSY cycles from item.busy[], sub-word
//          transfers by HSIZE with HWSTRB inside the HSIZE lanes.
//   AXI    AW + W together, AR independently; up to MAX_OUT reads and
//          MAX_OUT writes in flight, issued in order; a beat waits while a
//          transfer of the other direction to the same word is in flight
//          (so the scoreboard's order is the bus order). BREADY / RREADY
//          are randomly withheld (ready_pct).
//   WB     classic single cycles; CYC stays high across the beats of one
//          item, STB drops for the BUSY cycles. In the idle gap before an
//          item (CYC low) STB, WE and ADR toggle at random (must be ignored).
//
// Every output is idle from time 0 (AXI requires VALID low in reset).

`ifndef SRAM_BUS_DRIVER_SV
`define SRAM_BUS_DRIVER_SV

class sram_bus_driver extends uvm_driver #(sram_bus_item);
  `uvm_component_utils(sram_bus_driver)

  localparam int unsigned MAX_OUT = 4;       // AXI transfers in flight per direction
  localparam int unsigned TMO     = 20000;   // cycles without progress = hang

  virtual sram_bus_if vif;
  sram_uvm_cfg        cfg;
  int unsigned        port;
  int unsigned        ready_pct = 80;        // AXI BREADY / RREADY probability (%)

  int unsigned        pending;               // items not yet completed
  event               idle_ev;

  // One beat to issue
  typedef struct {
    sram_bus_item it;
    int unsigned  idx;      // beat index
    bit [31:0]    addr;
    bit [7:0]     strb;
    bit [63:0]    wdata;
    int unsigned  gap;      // idle / BUSY cycles before it
    bit           last;     // last beat of its item
    bit           first;
  } beat_t;

  beat_t bq [$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual sram_bus_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("DRV", "no virtual interface (vif)")
    end
    if (!uvm_config_db #(sram_uvm_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("DRV", "no sram_uvm_cfg (cfg)")
    end
    void'(uvm_config_db #(int unsigned)::get(this, "", "port", port));
    void'(uvm_config_db #(int unsigned)::get(this, "", "ready_pct", ready_pct));
  endfunction

  task wait_idle();
    while (pending != 0 || bq.size() != 0) @(idle_ev);
  endtask

  function int unsigned nbytes();
    return cfg.bytes_per_word(port);
  endfunction

  function int unsigned word_of(bit [31:0] a);
    return a / cfg.stride[port];
  endfunction

  // Expand an item into beats at the end of bq.
  function void expand(sram_bus_item it);
    beat_t b;
    bit [7:0] lanes;
    pending++;
    for (int unsigned i = 0; i < it.beats; i++) begin
      b.it    = it;
      b.idx   = i;
      b.addr  = it.beat_addr(i);
      lanes   = sram_bus_item::lane_mask(it.size, b.addr, nbytes());
      b.strb  = it.we ? (((i == 0) ? it.strb : 8'hFF) & lanes) : 8'h00;
      b.wdata = it.wdata[i];
      b.gap   = (i == 0) ? it.idle : it.busy[i];
      b.first = (i == 0);
      b.last  = (i == it.beats - 1);
      bq.push_back(b);
    end
  endfunction

  function void beat_done(beat_t b);
    if (b.last) begin
      pending--;
      if (pending == 0) ->idle_ev;
    end
  endfunction

  // Fetch the next item without blocking; true if one was queued.
  task try_fetch(output bit got);
    sram_bus_item it;
    got = 1'b0;
    seq_item_port.try_next_item(it);
    if (it != null) begin
      seq_item_port.item_done();
      expand(it);
      got = 1'b1;
    end
  endtask

  task fetch_blocking();
    sram_bus_item it;
    seq_item_port.get(it);
    expand(it);
  endtask

  task run_phase(uvm_phase phase);
    vif.idle_all();
    @(posedge vif.rst_n);
    @(posedge vif.clk);
    case (cfg.proto)
      "apb":   run_apb();
      "ahb":   run_ahb();
      "axi4l": run_axi();
      "wb":    run_wb();
      default: `uvm_fatal("DRV", $sformatf("unknown protocol %s", cfg.proto))
    endcase
  endtask

  // ---------------------------------------------------------------------------
  // APB4
  // ---------------------------------------------------------------------------
  task run_apb();
    beat_t       b;
    int unsigned w;
    forever begin
      if (bq.size() == 0) begin
        vif.PSEL    <= 1'b0;
        vif.PENABLE <= 1'b0;
        fetch_blocking();
        @(posedge vif.clk);
      end
      b = bq.pop_front();
      if (b.gap > 0) begin
        vif.PSEL    <= 1'b0;
        vif.PENABLE <= 1'b0;
        repeat (b.gap) @(posedge vif.clk);
      end
      vif.PSEL    <= 1'b1;
      vif.PENABLE <= 1'b0;
      vif.PADDR   <= b.addr;
      vif.PWRITE  <= b.it.we;
      vif.PWDATA  <= b.it.we ? b.wdata : '0;
      vif.PSTRB   <= b.strb;
      @(posedge vif.clk);
      vif.PENABLE <= 1'b1;
      w = 0;
      do begin
        @(posedge vif.clk);
        if (++w > TMO) `uvm_fatal("DRV", "APB: PREADY stuck low")
      end while (vif.PREADY !== 1'b1);
      beat_done(b);
      if (bq.size() == 0) begin
        bit got;
        try_fetch(got);
      end
      if (bq.size() == 0 || bq[0].gap > 0) begin
        vif.PSEL    <= 1'b0;
        vif.PENABLE <= 1'b0;
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // AHB-Lite
  // ---------------------------------------------------------------------------
  task ahb_present(beat_t b);
    vif.HSEL   <= 1'b1;
    vif.HADDR  <= b.addr;
    vif.HWRITE <= b.it.we;
    vif.HSIZE  <= 3'(b.it.size);
    vif.HTRANS <= b.first ? 2'b10 : 2'b11;          // NONSEQ / SEQ
  endtask

  task ahb_idle();
    vif.HSEL   <= 1'b0;
    vif.HTRANS <= 2'b00;
    vif.HWRITE <= 1'b0;
  endtask

  task run_ahb();
    beat_t       ap;          // beat in the address phase
    beat_t       dp;          // beat in the data phase
    bit          ap_v;
    bit          dp_v;
    int unsigned w;
    bit          got;
    ap_v = 1'b0;
    dp_v = 1'b0;
    forever begin
      // Nothing anywhere: block for the next item, then start on an edge.
      if (!ap_v && !dp_v && bq.size() == 0) begin
        ahb_idle();
        fetch_blocking();
        @(posedge vif.clk);
      end
      // Choose this cycle's address phase (driven now, sampled next edge).
      if (!ap_v && bq.size() > 0) begin
        if (bq[0].gap > 0) begin
          bq[0].gap--;
          if (bq[0].first) begin
            ahb_idle();
          end else begin
            // BUSY inside a burst: next beat's controls, HTRANS = BUSY
            ahb_present(bq[0]);
            vif.HTRANS <= 2'b01;
          end
        end else begin
          ap   = bq.pop_front();
          ap_v = 1'b1;
          ahb_present(ap);
        end
      end else if (!ap_v) begin
        ahb_idle();
      end
      // Wait for the edge that ends the current data phase (HREADY high).
      w = 0;
      do begin
        @(posedge vif.clk);
        if (++w > TMO) `uvm_fatal("DRV", "AHB: HREADY stuck low")
      end while (vif.HREADY !== 1'b1);
      if (dp_v) beat_done(dp);
      // The address phase (if any) moves to the data phase.
      dp_v = ap_v;
      dp   = ap;
      ap_v = 1'b0;
      if (dp_v) begin
        vif.HWDATA <= dp.it.we ? dp.wdata : '0;
        vif.HWSTRB <= dp.strb;
      end
      if (bq.size() == 0) try_fetch(got);
    end
  endtask

  // ---------------------------------------------------------------------------
  // AXI4-Lite
  // ---------------------------------------------------------------------------
  task run_axi();
    beat_t       wq [$];      // writes in flight (AW/W issued), oldest first
    beat_t       rq [$];      // reads in flight
    beat_t       nb;
    bit          aw_v, w_v, ar_v, bready, rready, hazard, got;
    bit          awr, wr, arr, bv, rv;
    int unsigned stuck;
    aw_v     = 1'b0;
    w_v      = 1'b0;
    ar_v     = 1'b0;
    bready   = 1'b0;
    rready   = 1'b0;
    stuck    = 0;
    forever begin
      if (bq.size() == 0 && wq.size() == 0 && rq.size() == 0 && !aw_v && !w_v && !ar_v) begin
        fetch_blocking();
        @(posedge vif.clk);
        stuck = 0;
      end
      // Inputs as sampled at this edge (outputs still hold last cycle's values)
      awr = (vif.AWREADY === 1'b1);
      wr  = (vif.WREADY === 1'b1);
      arr = (vif.ARREADY === 1'b1);
      bv  = (vif.BVALID === 1'b1);
      rv  = (vif.RVALID === 1'b1);
      stuck++;
      if (aw_v && awr) begin
        aw_v = 1'b0;
        vif.AWVALID <= 1'b0;
      end
      if (w_v && wr) begin
        w_v = 1'b0;
        vif.WVALID <= 1'b0;
      end
      if (ar_v && arr) begin
        ar_v = 1'b0;
        vif.ARVALID <= 1'b0;
      end
      if (bv && bready && wq.size() > 0) begin
        beat_done(wq.pop_front());
        stuck = 0;
      end
      if (rv && rready && rq.size() > 0) begin
        beat_done(rq.pop_front());
        stuck = 0;
      end
      if (stuck > TMO) `uvm_fatal("DRV", "AXI: no response")
      // Random back-pressure on the response channels
      bready = ($urandom_range(99) < ready_pct);
      rready = ($urandom_range(99) < ready_pct);
      vif.BREADY <= bready;
      vif.RREADY <= rready;
      // Issue the next beat
      if (bq.size() == 0) try_fetch(got);
      if (bq.size() > 0) begin
        if (bq[0].gap > 0) begin
          bq[0].gap--;
        end else begin
          nb     = bq[0];
          hazard = 1'b0;
          if (nb.it.we) begin
            foreach (rq[i]) if (word_of(rq[i].addr) == word_of(nb.addr)) hazard = 1'b1;
            if (!aw_v && !w_v && wq.size() < MAX_OUT && !hazard) begin
              void'(bq.pop_front());
              wq.push_back(nb);
              aw_v = 1'b1;
              w_v  = 1'b1;
              vif.AWVALID <= 1'b1;
              vif.AWADDR  <= nb.addr;
              vif.WVALID  <= 1'b1;
              vif.WDATA   <= nb.wdata;
              vif.WSTRB   <= nb.strb;
              stuck = 0;
            end
          end else begin
            foreach (wq[i]) if (word_of(wq[i].addr) == word_of(nb.addr)) hazard = 1'b1;
            if (!ar_v && rq.size() < MAX_OUT && !hazard) begin
              void'(bq.pop_front());
              rq.push_back(nb);
              ar_v = 1'b1;
              vif.ARVALID <= 1'b1;
              vif.ARADDR  <= nb.addr;
              stuck = 0;
            end
          end
        end
      end
      @(posedge vif.clk);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Wishbone B4 classic
  // ---------------------------------------------------------------------------
  task run_wb();
    beat_t       b;
    int unsigned w;
    bit          got;
    forever begin
      if (bq.size() == 0) begin
        vif.CYC <= 1'b0;
        vif.STB <= 1'b0;
        vif.WE  <= 1'b0;
        fetch_blocking();
        @(posedge vif.clk);
      end
      b = bq.pop_front();
      if (b.gap > 0) begin
        vif.STB <= 1'b0;
        if (b.first) begin
          // Outside a cycle: STB_O is meaningless without CYC_O (B4 3.1.3)
          // and the slave must ignore it; drive stray STB / address / WE
          // on about a quarter of the idle cycles.
          vif.CYC <= 1'b0;
          repeat (b.gap) begin
            if ($urandom_range(3) == 0) begin
              vif.STB <= 1'b1;
              vif.WE  <= 1'($urandom);
              vif.ADR <= $urandom;
            end else begin
              vif.STB <= 1'b0;
            end
            @(posedge vif.clk);
          end
        end else begin
          repeat (b.gap) @(posedge vif.clk);
        end
      end
      vif.CYC   <= 1'b1;
      vif.STB   <= 1'b1;
      vif.WE    <= b.it.we;
      vif.ADR   <= b.addr;
      vif.DAT_W <= b.it.we ? b.wdata : '0;
      vif.SEL   <= b.it.we ? b.strb :
                   sram_bus_item::lane_mask(b.it.size, b.addr, nbytes());
      w = 0;
      do begin
        @(posedge vif.clk);
        if (++w > TMO) `uvm_fatal("DRV", "WB: no ACK / ERR")
      end while (vif.ACK !== 1'b1 && vif.ERR !== 1'b1);
      beat_done(b);
      if (bq.size() == 0) try_fetch(got);
      if (bq.size() == 0 || bq[0].first) begin
        vif.STB <= 1'b0;
        vif.CYC <= 1'b0;
        vif.WE  <= 1'b0;
      end else begin
        vif.STB <= 1'b0;
      end
    end
  endtask

endclass : sram_bus_driver

`endif // SRAM_BUS_DRIVER_SV
