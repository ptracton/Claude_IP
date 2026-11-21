// sram_bus_monitor.sv — Passive monitor of one sram bus port, all four protocols.
//
// Writes one sram_bus_item per completed beat to `ap`, at the clock edge
// that completes it. Fields: we, addr, size, be (effective byte enables:
// the HSIZE lanes, masked by the write strobes for a write), wdata[0],
// rdata, err, t_start (edge at which the DUT first saw the request), t_end
// (edge of the response), beat (AHB: index inside a NONSEQ/SEQ run).
// Inputs are read right after the clock edge, before any nonblocking update
// of that edge, i.e. the values the DUT sampled.

`ifndef SRAM_BUS_MONITOR_SV
`define SRAM_BUS_MONITOR_SV

class sram_bus_monitor extends uvm_monitor;
  `uvm_component_utils(sram_bus_monitor)

  virtual sram_bus_if vif;
  sram_uvm_cfg        cfg;
  int unsigned        port;

  uvm_analysis_port #(sram_bus_item) ap;

  int unsigned n_beats;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db #(virtual sram_bus_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("MON", "no virtual interface (vif)")
    end
    if (!uvm_config_db #(sram_uvm_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("MON", "no sram_uvm_cfg (cfg)")
    end
    void'(uvm_config_db #(int unsigned)::get(this, "", "port", port));
  endfunction

  function int unsigned nbytes();
    return cfg.bytes_per_word(port);
  endfunction

  function bit [7:0] full_mask();
    return 8'((1 << nbytes()) - 1);
  endfunction

  // Size implied by a strobe/select pattern (protocols without HSIZE): the
  // whole word unless the strobes fit one naturally aligned smaller unit.
  function int unsigned size_of(bit [7:0] m);
    for (int unsigned s = 0; s < cfg.max_size(port); s++) begin
      for (int unsigned o = 0; o < nbytes(); o += (1 << s)) begin
        bit [7:0] u;
        u = 8'(((1 << (1 << s)) - 1) << o);
        if (m != 8'h00 && (m & ~u) == 8'h00) return s;
      end
    end
    return cfg.max_size(port);
  endfunction

  function sram_bus_item new_item(bit we, bit [31:0] addr, realtime t0);
    sram_bus_item it;
    it          = sram_bus_item::type_id::create("mon_item");
    it.port     = port;
    it.we       = we;
    it.addr     = addr;
    it.beats    = 1;
    it.kind     = BurstSingle;
    it.wdata    = new [1];
    it.busy     = new [1];
    it.busy[0]  = 0;
    it.t_start  = t0;
    return it;
  endfunction

  function void emit(sram_bus_item it);
    it.t_end = $realtime;
    n_beats++;
    `uvm_info("MON", it.convert2string(), UVM_HIGH)
    ap.write(it);
  endfunction

  task run_phase(uvm_phase phase);
    @(posedge vif.rst_n);
    case (cfg.proto)
      "apb":   mon_apb();
      "ahb":   mon_ahb();
      "axi4l": mon_axi();
      "wb":    mon_wb();
      default: `uvm_fatal("MON", $sformatf("unknown protocol %s", cfg.proto))
    endcase
  endtask

  // ---------------------------------------------------------------------------
  task mon_apb();
    realtime      t0;
    sram_bus_item it;
    forever begin
      @(posedge vif.clk);
      if (vif.PSEL === 1'b1 && vif.PENABLE !== 1'b1) t0 = $realtime;   // SETUP
      if (vif.PSEL === 1'b1 && vif.PENABLE === 1'b1 && vif.PREADY === 1'b1) begin
        it          = new_item(vif.PWRITE, vif.PADDR, t0);
        it.be       = vif.PWRITE ? vif.PSTRB & full_mask() : full_mask();
        it.size     = vif.PWRITE ? size_of(it.be) : cfg.max_size(port);
        it.wdata[0] = vif.PWDATA;
        it.rdata    = vif.PRDATA;
        it.err      = (vif.PSLVERR === 1'b1);
        emit(it);
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  task mon_ahb();
    sram_bus_item dp;          // beat in the data phase
    realtime      t_ap;        // first edge of the pending address phase
    bit           ap_seen;
    int unsigned  run;
    int unsigned  nbusy;       // BUSY cycles since the last accepted beat
    dp      = null;
    ap_seen = 1'b0;
    run     = 0;
    nbusy   = 0;
    forever begin
      @(posedge vif.clk);
      if (vif.HSEL === 1'b1 && vif.HTRANS[1] === 1'b1 && !ap_seen) begin
        ap_seen = 1'b1;
        t_ap    = $realtime;
      end
      if (vif.HSEL === 1'b1 && vif.HTRANS === 2'b01 && vif.HREADY === 1'b1) nbusy++;
      if (vif.HREADY === 1'b1) begin
        // Data phase completes
        if (dp != null) begin
          if (dp.we) begin
            dp.wdata[0] = vif.HWDATA;
            dp.be       = vif.HWSTRB & sram_bus_item::lane_mask(dp.size, dp.addr, nbytes());
          end
          dp.rdata = vif.HRDATA;
          dp.err   = (vif.HRESP === 1'b1);
          emit(dp);
          dp = null;
        end
        // Address phase accepted
        if (vif.HSEL === 1'b1 && vif.HTRANS[1] === 1'b1) begin
          dp      = new_item(vif.HWRITE, vif.HADDR, t_ap);
          dp.size = vif.HSIZE;
          dp.be   = sram_bus_item::lane_mask(dp.size, dp.addr, nbytes());
          run     = (vif.HTRANS == 2'b10) ? 0 : run + 1;
          dp.beat    = run;
          dp.busy[0] = nbusy;
          nbusy      = 0;
          ap_seen    = 1'b0;
        end
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  task mon_axi();
    typedef struct {
      bit [31:0] addr;
      realtime   t0;
    } a_t;
    typedef struct {
      bit [63:0] data;
      bit [7:0]  strb;
    } w_t;
    a_t           awq [$];
    w_t           wq  [$];
    a_t           arq [$];
    a_t           a;
    w_t           w;
    realtime      t_aw, t_ar;
    bit           aw_seen, ar_seen;
    int unsigned  wr_out, rd_out;    // in flight (address taken, no response)
    sram_bus_item it;
    aw_seen = 1'b0;
    ar_seen = 1'b0;
    wr_out  = 0;
    rd_out  = 0;
    forever begin
      @(posedge vif.clk);
      if (vif.AWVALID === 1'b1 && !aw_seen) begin
        aw_seen = 1'b1;
        t_aw    = $realtime;
      end
      if (vif.ARVALID === 1'b1 && !ar_seen) begin
        ar_seen = 1'b1;
        t_ar    = $realtime;
      end
      // Responses first: a response at this edge belongs to an earlier request
      if (vif.BVALID === 1'b1 && vif.BREADY === 1'b1) begin
        if (awq.size() == 0 || wq.size() == 0) begin
          `uvm_error("MON", "AXI: B response without AW and W")
        end else begin
          a           = awq.pop_front();
          w           = wq.pop_front();
          it          = new_item(1'b1, a.addr, a.t0);
          it.be       = w.strb & full_mask();
          it.size     = size_of(it.be);
          it.wdata[0] = w.data;
          it.rdata    = '0;
          it.err      = (vif.BRESP != 2'b00);
          it.overlap  = (rd_out > 0);
          wr_out--;
          emit(it);
        end
      end
      if (vif.RVALID === 1'b1 && vif.RREADY === 1'b1) begin
        if (arq.size() == 0) begin
          `uvm_error("MON", "AXI: R response without AR")
        end else begin
          a          = arq.pop_front();
          it         = new_item(1'b0, a.addr, a.t0);
          it.be      = full_mask();
          it.size    = cfg.max_size(port);
          it.rdata   = vif.RDATA;
          it.err     = (vif.RRESP != 2'b00);
          it.overlap = (wr_out > 0);
          rd_out--;
          emit(it);
        end
      end
      if (vif.AWVALID === 1'b1 && vif.AWREADY === 1'b1) begin
        a.addr = vif.AWADDR;
        a.t0   = t_aw;
        awq.push_back(a);
        aw_seen = 1'b0;
        wr_out++;
      end
      if (vif.WVALID === 1'b1 && vif.WREADY === 1'b1) begin
        w.data = vif.WDATA;
        w.strb = vif.WSTRB;
        wq.push_back(w);
      end
      if (vif.ARVALID === 1'b1 && vif.ARREADY === 1'b1) begin
        a.addr = vif.ARADDR;
        a.t0   = t_ar;
        arq.push_back(a);
        ar_seen = 1'b0;
        rd_out++;
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  task mon_wb();
    realtime      t0;
    bit           seen;
    sram_bus_item it;
    seen = 1'b0;
    forever begin
      @(posedge vif.clk);
      if (vif.CYC === 1'b1 && vif.STB === 1'b1 && !seen) begin
        seen = 1'b1;
        t0   = $realtime;
      end
      if (vif.CYC === 1'b1 && vif.STB === 1'b1 && (vif.ACK === 1'b1 || vif.ERR === 1'b1)) begin
        it          = new_item(vif.WE, vif.ADR, t0);
        it.be       = vif.SEL & full_mask();
        it.size     = vif.WE ? size_of(it.be) : cfg.max_size(port);
        it.wdata[0] = vif.DAT_W;
        it.rdata    = vif.DAT_R;
        it.err      = (vif.ERR === 1'b1);
        seen        = 1'b0;
        emit(it);
      end
    end
  endtask

endclass : sram_bus_monitor

`endif // SRAM_BUS_MONITOR_SV
