// sram_sb_agent.sv — Side-band agent: driver (power modes, clear, ECC
// injection, BIST start, BIST fault knob), monitor (requests, acks, done /
// status pulses) and sequencer. All on port A's clock.

`ifndef SRAM_SB_AGENT_SV
`define SRAM_SB_AGENT_SV

class sram_sb_driver extends uvm_driver #(sram_sb_item);
  `uvm_component_utils(sram_sb_driver)

  localparam int unsigned TMO = 50000;   // cycles to wait for an ack / done

  virtual sram_sb_if vif;
  sram_uvm_cfg       cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual sram_sb_if)::get(this, "", "sb_vif", vif)) begin
      `uvm_fatal("SBDRV", "no virtual interface (sb_vif)")
    end
    if (!uvm_config_db #(sram_uvm_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("SBDRV", "no sram_uvm_cfg (cfg)")
    end
  endfunction


  task run_phase(uvm_phase phase);
    sram_sb_item it;
    int unsigned w;
    vif.idle_all();
    @(posedge vif.rst_n);
    @(posedge vif.clk);
    forever begin
      seq_item_port.get_next_item(it);
      `uvm_info("SBDRV", it.convert2string(), UVM_MEDIUM)
      case (it.op)
        SbMode: begin
          vif.pwr_mode_req[2*it.dom +: 2] <= 2'(it.mode);
          @(posedge vif.clk);
          if (it.wait_done) begin
            w = 0;
            while (vif.pwr_mode_ack[2*it.dom +: 2] !== 2'(it.mode)) begin
              @(posedge vif.clk);
              if (++w > TMO) `uvm_fatal("SBDRV", $sformatf("no ack: %s", it.convert2string()))
            end
          end
        end
        SbClear: begin
          vif.clr_req <= 1'b1;
          @(posedge vif.clk);
          vif.clr_req <= 1'b0;
          if (it.wait_done) begin
            w = 0;
            while (vif.clr_done !== 1'b1) begin
              @(posedge vif.clk);
              if (++w > TMO) `uvm_fatal("SBDRV", "no clr_done")
            end
          end
        end
        SbInject: begin
          vif.ecc_inj <= it.inj;
          @(posedge vif.clk);
          vif.ecc_inj <= 2'b00;
        end
        SbBist: begin
          vif.bist_start <= 1'b1;
          @(posedge vif.clk);
          vif.bist_start <= 1'b0;
          if (it.wait_done) begin
            w = 0;
            while (vif.bist_done !== 1'b1) begin
              @(posedge vif.clk);
              if (++w > 4 * TMO) `uvm_fatal("SBDRV", "no bist_done")
            end
          end
        end
        SbFault: begin
          vif.bf_addr = it.fault_addr;
          vif.bf_bit  = it.fault_bit;
          vif.bf_val  = it.fault_val;
          vif.bf_on   = it.fault_on;
        end
        SbWait: begin
          repeat (it.cycles) @(posedge vif.clk);
        end
        default: `uvm_fatal("SBDRV", "unknown op")
      endcase
      seq_item_port.item_done();
    end
  endtask

endclass : sram_sb_driver

class sram_sb_monitor extends uvm_monitor;
  `uvm_component_utils(sram_sb_monitor)

  virtual sram_sb_if vif;
  sram_uvm_cfg       cfg;

  uvm_analysis_port #(sram_sb_event) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db #(virtual sram_sb_if)::get(this, "", "sb_vif", vif)) begin
      `uvm_fatal("SBMON", "no virtual interface (sb_vif)")
    end
    if (!uvm_config_db #(sram_uvm_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("SBMON", "no sram_uvm_cfg (cfg)")
    end
  endfunction

  function void send(sram_sb_ev_e k, int unsigned d = 0, int unsigned v = 0,
                     int unsigned o = 0);
    sram_sb_event e;
    e      = sram_sb_event::type_id::create("ev");
    e.kind = k;
    e.dom  = d;
    e.val  = v;
    e.old  = o;
    e.t    = $realtime;
    if (k == EvBistDone) begin
      e.fail      = (vif.bist_fail === 1'b1);
      e.fail_addr = vif.bist_fail_addr;
    end
    `uvm_info("SBMON", e.convert2string(), UVM_HIGH)
    ap.write(e);
  endfunction

  task run_phase(uvm_phase phase);
    logic [7:0] req_q;
    logic [7:0] ack_q;
    bit [63:0]  bf_q;        // {on, val, bit, word} as last reported
    bit [63:0]  bf_now;
    sram_sb_event e;
    req_q = '0;
    ack_q = '0;
    bf_q  = '0;
    @(posedge vif.rst_n);
    forever begin
      @(posedge vif.clk);
      if (vif.rst_n !== 1'b1) continue;
      // Requests first: they are inputs sampled at this edge.
      for (int unsigned d = 0; d < cfg.npd; d++) begin
        if (vif.pwr_mode_req[2*d +: 2] !== req_q[2*d +: 2]) begin
          send(EvReq, d, vif.pwr_mode_req[2*d +: 2], req_q[2*d +: 2]);
        end
      end
      if (vif.clr_req === 1'b1) send(EvClrReq);
      if (vif.bist_start === 1'b1) send(EvBistStart);
      if (vif.ecc_inj !== 2'b00) send(EvInj, 0, vif.ecc_inj);
      for (int unsigned d = 0; d < cfg.npd; d++) begin
        if (vif.pwr_mode_ack[2*d +: 2] !== ack_q[2*d +: 2]) begin
          send(EvAck, d, vif.pwr_mode_ack[2*d +: 2], ack_q[2*d +: 2]);
        end
      end
      if (vif.clr_done === 1'b1) send(EvClrDone);
      if (vif.bist_done === 1'b1) send(EvBistDone);
      if (vif.err_irq === 1'b1) send(EvIrq);
      if (vif.ecc_corr === 1'b1) send(EvCorr);
      if (vif.ecc_uncorr === 1'b1) send(EvUncorr);
      // Any change of the knob (off and on again with another bit or value can
      // happen between two edges, so compare all of it).
      bf_now = {vif.bf_on, vif.bf_val, 30'(vif.bf_bit), 32'(vif.bf_addr)};
      if (bf_now != bf_q) begin
        e      = sram_sb_event::type_id::create("ev");
        e.kind = EvFault;
        e.val  = vif.bf_on;
        e.dom  = vif.bf_addr;
        e.old  = vif.bf_bit;
        e.fail = vif.bf_val;
        e.t    = $realtime;
        ap.write(e);
        bf_q   = bf_now;
      end
      req_q = vif.pwr_mode_req;
      ack_q = vif.pwr_mode_ack;
    end
  endtask

endclass : sram_sb_monitor

class sram_sb_agent extends uvm_agent;
  `uvm_component_utils(sram_sb_agent)

  uvm_sequencer #(sram_sb_item) sqr;
  sram_sb_driver                drv;
  sram_sb_monitor               mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sqr = uvm_sequencer #(sram_sb_item)::type_id::create("sqr", this);
    drv = sram_sb_driver::type_id::create("drv", this);
    mon = sram_sb_monitor::type_id::create("mon", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass : sram_sb_agent

`endif // SRAM_SB_AGENT_SV
