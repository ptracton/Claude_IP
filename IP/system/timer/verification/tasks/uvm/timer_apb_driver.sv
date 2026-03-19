// timer_apb_driver.sv — UVM driver for Timer APB4 testbench.
//
// Drives APB4 transactions onto the DUT interface.
//
// APB4 two-phase protocol per ARM IHI0024:
//   SETUP  phase: PSEL=1, PENABLE=0  (one clock)
//   ACCESS phase: PSEL=1, PENABLE=1  (wait until PREADY=1)
//
// The driver retrieves a virtual interface handle named "timer_apb_vif"
// from the UVM config_db.  The top-level testbench must set this handle
// before the run phase begins.
//
// NOTE: Requires a UVM-capable simulator (VCS, Questasim, or Riviera-PRO).
//       Not compatible with Icarus Verilog or GHDL.

class timer_apb_driver extends uvm_driver #(timer_seq_item);

  // -------------------------------------------------------------------------
  // UVM factory registration
  // -------------------------------------------------------------------------
  `uvm_component_utils(timer_apb_driver)

  // -------------------------------------------------------------------------
  // Virtual interface handle
  // -------------------------------------------------------------------------
  virtual timer_apb_if vif;

  // -------------------------------------------------------------------------
  // Constructor
  // -------------------------------------------------------------------------
  function new(string name = "timer_apb_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // -------------------------------------------------------------------------
  // build_phase — retrieve virtual interface from config_db
  // -------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual timer_apb_if)::get(
          this, "", "timer_apb_vif", vif)) begin
      `uvm_fatal("CFG_DB",
        "timer_apb_driver: cannot get timer_apb_vif from config_db")
    end
  endfunction

  // -------------------------------------------------------------------------
  // run_phase — main driver loop
  // -------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    timer_seq_item item;

    // Initialise bus to idle state
    vif.PSEL    <= 1'b0;
    vif.PENABLE <= 1'b0;
    vif.PADDR   <= '0;
    vif.PWRITE  <= 1'b0;
    vif.PWDATA  <= '0;
    vif.PSTRB   <= '0;

    // Wait for reset de-assertion
    @(posedge vif.PRESETn);
    @(posedge vif.PCLK);

    forever begin
      seq_item_port.get_next_item(item);
      drive_transaction(item);
      seq_item_port.item_done();
    end
  endtask

  // -------------------------------------------------------------------------
  // drive_transaction — execute one APB4 read or write
  // -------------------------------------------------------------------------
  task drive_transaction(timer_seq_item item);
    // ------------------------------------------------------------------
    // SETUP phase (one clock cycle)
    // ------------------------------------------------------------------
    @(posedge vif.PCLK);
    vif.PSEL    <= 1'b1;
    vif.PENABLE <= 1'b0;
    vif.PADDR   <= item.addr;
    vif.PWRITE  <= item.write;
    vif.PWDATA  <= item.write ? item.data : '0;
    vif.PSTRB   <= item.write ? item.strb : '0;

    // ------------------------------------------------------------------
    // ACCESS phase — assert PENABLE, wait for PREADY
    // ------------------------------------------------------------------
    @(posedge vif.PCLK);
    vif.PENABLE <= 1'b1;

    // Poll until slave signals ready (handles wait-states)
    while (!vif.PREADY) begin
      @(posedge vif.PCLK);
    end

    // ------------------------------------------------------------------
    // Return bus to idle — also the cycle where PRDATA is valid.
    //
    // The regfile uses a registered read path:
    //   SETUP phase  (PSEL=1, PENABLE=0): rd_en=1 → rd_data latched at
    //                                      this posedge's NBA region.
    //   ACCESS phase (PSEL=1, PENABLE=1): PRDATA = rd_data, valid at
    //                                      the NEXT posedge Active region.
    //
    // Capturing PRDATA at the ACCESS posedge's Active region (before the
    // NBA) reads the stale value from the cycle prior.  Capturing at the
    // following posedge (this "idle" clock) reads the correct data.
    // ------------------------------------------------------------------
    @(posedge vif.PCLK);
    vif.PSEL    <= 1'b0;
    vif.PENABLE <= 1'b0;
    vif.PWRITE  <= 1'b0;
    vif.PWDATA  <= '0;
    vif.PSTRB   <= '0;

    if (!item.write) begin
      item.rdata = vif.PRDATA;
      `uvm_info("DRV",
        $sformatf("READ  addr=0x%03X rdata=0x%08X", item.addr, item.rdata),
        UVM_HIGH)
    end else begin
      `uvm_info("DRV",
        $sformatf("WRITE addr=0x%03X data=0x%08X strb=0x%X",
                  item.addr, item.data, item.strb),
        UVM_HIGH)
    end
  endtask

endclass : timer_apb_driver
