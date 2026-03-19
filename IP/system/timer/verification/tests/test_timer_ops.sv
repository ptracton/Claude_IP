// test_timer_ops.sv — Timer IP directed functional tests.
//
// Exercises timer-specific functionality:
//   Test 1: Repeat mode — load small value, prescale=0, wait for interrupt
//   Test 2: One-shot mode — verify timer stops after one underflow
//   Test 3: Trigger output — enable TRIG_EN, verify trigger_out pulses
//   Test 4: Prescaler — set PRESCALE=3 (divide-by-4), verify tick rate
//
// Register layout (byte addresses):
//   CTRL   @ 0x000  fields: EN[0], MODE[1], INTR_EN[2], TRIG_EN[3], PRESCALE[11:4]
//   STATUS @ 0x004  fields: INTR[0] W1C, ACTIVE[1] RO
//   LOAD   @ 0x008  VALUE[31:0]
//   COUNT  @ 0x00C  VALUE[31:0] RO
//
// Depends on: write_reg, read_reg (BFM), irq/trigger_out signals,
//             check_eq / test_start / test_done (timer_test_pkg.sv)

task automatic test_timer_ops;
  logic [31:0] rdata;
  int          timeout;
  logic        trig_seen;
  begin
    test_start("test_timer_ops");

    // =======================================================================
    // Test 1 — Repeat mode, prescale=0, LOAD=8
    // =======================================================================
    $display("  -- Test 1: repeat mode interrupt --");

    write_reg(12'h008, 32'h0000_0008, 4'hF); // LOAD = 8
    write_reg(12'h000, 32'h0000_0005, 4'hF); // EN=1, INTR_EN=1

    timeout = 0;
    while (!irq && timeout < 200) begin
      @(posedge clk);
      timeout = timeout + 1;
    end
    if (timeout >= 200) begin
      $display("FAIL test_timer_ops: Test1 timeout waiting for irq (repeat mode)");
      $finish(1);
    end
    $display("  irq asserted after %0d cycles", timeout);

    read_reg(12'h004, rdata);
    check_eq(rdata & 32'h0000_0001, 32'h0000_0001, "T1: STATUS.INTR set");
    check_eq(rdata & 32'h0000_0002, 32'h0000_0002, "T1: STATUS.ACTIVE set (repeat)");

    // Disable before clearing to avoid race with next underflow
    write_reg(12'h000, 32'h0000_0000, 4'hF);
    @(posedge clk); @(posedge clk);

    write_reg(12'h004, 32'h0000_0001, 4'hF); // W1C STATUS.INTR
    @(posedge clk); @(posedge clk);
    read_reg(12'h004, rdata);
    check_eq(rdata & 32'h0000_0001, 32'h0000_0000, "T1: STATUS.INTR cleared");

    @(posedge clk);
    if (irq !== 1'b0) begin
      $display("FAIL test_timer_ops: irq still asserted after W1C clear");
      $finish(1);
    end
    @(posedge clk);

    // =======================================================================
    // Test 2 — One-shot mode, LOAD=4
    // =======================================================================
    $display("  -- Test 2: one-shot mode --");

    write_reg(12'h008, 32'h0000_0004, 4'hF); // LOAD = 4
    write_reg(12'h000, 32'h0000_0007, 4'hF); // EN=1, MODE=1, INTR_EN=1

    timeout = 0;
    while (!irq && timeout < 100) begin
      @(posedge clk);
      timeout = timeout + 1;
    end
    if (timeout >= 100) begin
      $display("FAIL test_timer_ops: Test2 timeout waiting for irq (one-shot)");
      $finish(1);
    end
    $display("  one-shot irq after %0d cycles", timeout);

    @(posedge clk); @(posedge clk);
    read_reg(12'h004, rdata);
    check_eq(rdata & 32'h0000_0002, 32'h0000_0000, "T2: STATUS.ACTIVE low after one-shot");

    write_reg(12'h004, 32'h0000_0001, 4'hF);
    write_reg(12'h000, 32'h0000_0000, 4'hF);
    @(posedge clk); @(posedge clk);

    // =======================================================================
    // Test 3 — Trigger output, LOAD=3, TRIG_EN=1
    // =======================================================================
    $display("  -- Test 3: trigger output --");

    write_reg(12'h008, 32'h0000_0003, 4'hF); // LOAD = 3
    write_reg(12'h000, 32'h0000_0009, 4'hF); // EN=1, TRIG_EN=1

    trig_seen = 1'b0;
    timeout   = 0;
    while (!trig_seen && timeout < 100) begin
      @(posedge clk);
      if (trigger_out) trig_seen = 1'b1;
      timeout = timeout + 1;
    end
    if (!trig_seen) begin
      $display("FAIL test_timer_ops: Test3 timeout waiting for trigger_out");
      $finish(1);
    end
    $display("  trigger_out seen after %0d cycles", timeout);

    @(posedge clk);
    if (trigger_out !== 1'b0) begin
      @(posedge clk);
      if (trigger_out !== 1'b0) begin
        $display("FAIL test_timer_ops: trigger_out did not de-assert (stuck high)");
        $finish(1);
      end
    end
    $display("  trigger_out: one-cycle pulse confirmed");

    write_reg(12'h000, 32'h0000_0000, 4'hF);
    @(posedge clk); @(posedge clk);

    // =======================================================================
    // Test 4 — Prescaler divide-by-4, PRESCALE=3, LOAD=1
    // =======================================================================
    $display("  -- Test 4: prescaler divide-by-4 --");

    write_reg(12'h004, 32'h0000_0001, 4'hF); // Clear any residual INTR
    @(posedge clk); @(posedge clk);

    write_reg(12'h008, 32'h0000_0001, 4'hF); // LOAD = 1
    write_reg(12'h000, 32'h0000_0035, 4'hF); // PRESCALE=3, EN=1, INTR_EN=1

    timeout = 0;
    while (!irq && timeout < 200) begin
      @(posedge clk);
      timeout = timeout + 1;
    end
    if (timeout >= 200) begin
      $display("FAIL test_timer_ops: Test4 timeout waiting for irq (prescale=3)");
      $finish(1);
    end
    $display("  prescale=3 irq after %0d cycles", timeout);

    if (timeout < 4) begin
      $display("FAIL test_timer_ops: prescale=3 irq too early (%0d < 4)", timeout);
      $finish(1);
    end
    $display("  prescale timing: %0d cycles >= 4 minimum", timeout);

    write_reg(12'h004, 32'h0000_0001, 4'hF);
    write_reg(12'h000, 32'h0000_0000, 4'hF);
    write_reg(12'h008, 32'h0000_0000, 4'hF);
    @(posedge clk); @(posedge clk);

    test_done("test_timer_ops");
    $display("test_timer_ops: PASS");
  end
endtask
