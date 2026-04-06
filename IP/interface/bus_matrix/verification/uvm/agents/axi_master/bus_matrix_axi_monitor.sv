// bus_matrix_axi_monitor.sv — UVM monitor for AXI4-Lite master port.
//
// Observes completed AXI4-Lite transactions and broadcasts them on the
// analysis port for the scoreboard and coverage collector.

`ifndef BUS_MATRIX_AXI_MONITOR_SV
`define BUS_MATRIX_AXI_MONITOR_SV

class bus_matrix_axi_monitor extends uvm_monitor;
  `uvm_component_utils(bus_matrix_axi_monitor)

  virtual bus_matrix_axi_if vif;
  uvm_analysis_port #(bus_matrix_axi_seq_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db #(virtual bus_matrix_axi_if)::get(this, "", "vif", vif))
      `uvm_fatal("MON", "No virtual interface found for bus_matrix_axi_monitor")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      bus_matrix_axi_seq_item item;
      // Detect write: AWVALID && AWREADY
      fork
        detect_write();
        detect_read();
      join_any
      disable fork;
    end
  endtask

  task detect_write();
    bus_matrix_axi_seq_item item = bus_matrix_axi_seq_item::type_id::create("mon_wr");
    item.write = 1'b1;
    // Capture address
    @(posedge vif.clk iff (vif.AWVALID && vif.AWREADY));
    item.addr = vif.AWADDR;
    // Capture data (may arrive same or different cycle; grab when WVALID+WREADY)
    if (!(vif.WVALID && vif.WREADY))
      @(posedge vif.clk iff (vif.WVALID && vif.WREADY));
    item.wdata = vif.WDATA;
    item.wstrb = vif.WSTRB;
    // Capture response
    @(posedge vif.clk iff (vif.BVALID && vif.BREADY));
    item.resp = vif.BRESP;
    `uvm_info("MON", $sformatf("Write observed: %s", item.convert2string()), UVM_HIGH)
    ap.write(item);
  endtask

  task detect_read();
    bus_matrix_axi_seq_item item = bus_matrix_axi_seq_item::type_id::create("mon_rd");
    item.write = 1'b0;
    // Capture address
    @(posedge vif.clk iff (vif.ARVALID && vif.ARREADY));
    item.addr = vif.ARADDR;
    // Capture data
    @(posedge vif.clk iff (vif.RVALID && vif.RREADY));
    item.rdata = vif.RDATA;
    item.resp  = vif.RRESP;
    `uvm_info("MON", $sformatf("Read observed: %s", item.convert2string()), UVM_HIGH)
    ap.write(item);
  endtask

endclass : bus_matrix_axi_monitor

`endif // BUS_MATRIX_AXI_MONITOR_SV
