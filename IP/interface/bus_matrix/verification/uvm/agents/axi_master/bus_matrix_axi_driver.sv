// bus_matrix_axi_driver.sv — UVM driver for AXI4-Lite master port.
//
// Drives AXI4-Lite transactions onto the virtual interface.
// Write path: AW+W channels simultaneously, then poll B channel.
// Read path: AR channel, then poll R channel.

`ifndef BUS_MATRIX_AXI_DRIVER_SV
`define BUS_MATRIX_AXI_DRIVER_SV

class bus_matrix_axi_driver extends uvm_driver #(bus_matrix_axi_seq_item);
  `uvm_component_utils(bus_matrix_axi_driver)

  virtual bus_matrix_axi_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual bus_matrix_axi_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "No virtual interface found for bus_matrix_axi_driver")
  endfunction

  task run_phase(uvm_phase phase);
    bus_matrix_axi_seq_item item;
    // Wait for reset de-assertion
    @(posedge vif.rst_n);
    @(posedge vif.clk);
    // Idle all outputs via clocking block
    vif.driver_cb.AWVALID <= 1'b0; vif.driver_cb.AWADDR <= '0;
    vif.driver_cb.WVALID  <= 1'b0; vif.driver_cb.WDATA  <= '0; vif.driver_cb.WSTRB <= '0;
    vif.driver_cb.BREADY  <= 1'b0;
    vif.driver_cb.ARVALID <= 1'b0; vif.driver_cb.ARADDR <= '0;
    vif.driver_cb.RREADY  <= 1'b0;

    forever begin
      seq_item_port.get_next_item(item);
      if (item.write)
        drive_write(item);
      else
        drive_read(item);
      seq_item_port.item_done();
    end
  endtask

  task drive_write(bus_matrix_axi_seq_item item);
    // Drive AW+W via clocking block
    @(vif.driver_cb);
    vif.driver_cb.AWVALID <= 1'b1; vif.driver_cb.AWADDR <= item.addr;
    vif.driver_cb.WVALID  <= 1'b1; vif.driver_cb.WDATA  <= item.wdata;
    vif.driver_cb.WSTRB   <= item.wstrb;
    // Wait for handshake: AWREADY && WREADY sampled via clocking block input
    @(vif.driver_cb);
    while (!(vif.driver_cb.AWREADY && vif.driver_cb.WREADY)) @(vif.driver_cb);
    // De-assert
    vif.driver_cb.AWVALID <= 1'b0; vif.driver_cb.AWADDR <= '0;
    vif.driver_cb.WVALID  <= 1'b0; vif.driver_cb.WDATA  <= '0;
    vif.driver_cb.WSTRB   <= '0;
    // Wait for write response
    vif.driver_cb.BREADY <= 1'b1;
    @(vif.driver_cb);
    while (!vif.driver_cb.BVALID) @(vif.driver_cb);
    item.resp = vif.driver_cb.BRESP;
    vif.driver_cb.BREADY <= 1'b0;
  endtask

  task drive_read(bus_matrix_axi_seq_item item);
    // Drive AR via clocking block
    @(vif.driver_cb);
    vif.driver_cb.ARVALID <= 1'b1; vif.driver_cb.ARADDR <= item.addr;
    // Wait for ARREADY
    @(vif.driver_cb);
    while (!vif.driver_cb.ARREADY) @(vif.driver_cb);
    vif.driver_cb.ARVALID <= 1'b0; vif.driver_cb.ARADDR <= '0;
    // Wait for read data
    vif.driver_cb.RREADY <= 1'b1;
    @(vif.driver_cb);
    while (!vif.driver_cb.RVALID) @(vif.driver_cb);
    item.rdata = vif.driver_cb.RDATA;
    item.resp  = vif.driver_cb.RRESP;
    vif.driver_cb.RREADY <= 1'b0;
  endtask

endclass : bus_matrix_axi_driver

`endif // BUS_MATRIX_AXI_DRIVER_SV
