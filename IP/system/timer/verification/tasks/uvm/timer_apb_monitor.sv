// timer_apb_monitor.sv — UVM monitor for Timer APB4 testbench.
//
// Passively observes the APB4 bus.  On every completed ACCESS phase
// (PSEL=1, PENABLE=1, PREADY=1) a cloned timer_seq_item is broadcast
// on the analysis port `ap` so connected subscribers (e.g. scoreboard)
// can inspect each transaction.
//
// The monitor never drives any signals.
//
// NOTE: Requires a UVM-capable simulator (VCS, Questasim, or Riviera-PRO).
//       Not compatible with Icarus Verilog or GHDL.

class timer_apb_monitor extends uvm_monitor;

  // -------------------------------------------------------------------------
  // UVM factory registration
  // -------------------------------------------------------------------------
  `uvm_component_utils(timer_apb_monitor)

  // -------------------------------------------------------------------------
  // Analysis port — broadcasts completed transactions to subscribers
  // -------------------------------------------------------------------------
  uvm_analysis_port #(timer_seq_item) ap;

  // -------------------------------------------------------------------------
  // Virtual interface handle
  // -------------------------------------------------------------------------
  virtual timer_apb_if vif;

  // -------------------------------------------------------------------------
  // Constructor
  // -------------------------------------------------------------------------
  function new(string name = "timer_apb_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // -------------------------------------------------------------------------
  // build_phase
  // -------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db #(virtual timer_apb_if)::get(
          this, "", "timer_apb_vif", vif)) begin
      `uvm_fatal("CFG_DB",
        "timer_apb_monitor: cannot get timer_apb_vif from config_db")
    end
  endfunction

  // -------------------------------------------------------------------------
  // run_phase — observe APB bus and emit items on analysis port
  // -------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    timer_seq_item item;

    // Wait for reset de-assertion before starting observation
    @(posedge vif.PRESETn);

    forever begin
      // Wait for the start of an ACCESS phase
      @(posedge vif.PCLK);
      if (vif.PSEL && vif.PENABLE) begin
        // Wait for PREADY (slave may insert wait states)
        while (!vif.PREADY) begin
          @(posedge vif.PCLK);
        end

        // Capture transaction details
        item        = timer_seq_item::type_id::create("mon_item");
        item.addr   = vif.PADDR;
        item.write  = vif.PWRITE;
        item.strb   = vif.PSTRB;
        item.data   = vif.PWRITE ? vif.PWDATA  : '0;
        item.rdata  = vif.PWRITE ? '0           : vif.PRDATA;

        `uvm_info("MON",
          $sformatf("observed %s addr=0x%03X data=0x%08X rdata=0x%08X",
                    item.write ? "WRITE" : "READ",
                    item.addr, item.data, item.rdata),
          UVM_HIGH)

        ap.write(item);
      end
    end
  endtask

endclass : timer_apb_monitor
