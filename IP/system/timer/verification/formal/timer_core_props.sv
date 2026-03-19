// timer_core_props.sv — Formal verification properties for timer_core.
//
// Attach via bind:
//   bind timer_core timer_core_props #(.DATA_W(DATA_W)) u_props (.*);
//
// Properties verified:
//   P1: irq is the combinational AND of status_intr & ctrl_intr_en
//   P2: hw_active de-asserts within one cycle of ctrl_en de-asserting
//   P3: hw_intr_set is a maximum one-cycle-wide pulse
//   P4: trigger_out is a maximum one-cycle-wide pulse
//   P5: trigger_out is gated by ctrl_trig_en
//   P6: hw_count_val == load_val one cycle after EN rises (counter loaded)
//
// Cover goals:
//   C1: hw_intr_set fires (timer underflows)
//   C2: one-shot mode completes (hw_active falls while ctrl_en stays high)
//   C3: trigger_out asserts

`default_nettype none

module timer_core_props #(
  parameter integer DATA_W = 32
) (
  input wire                clk,
  input wire                rst_n,
  // Control inputs
  input wire                ctrl_en,
  input wire                ctrl_mode,
  input wire                ctrl_intr_en,
  input wire                ctrl_trig_en,
  input wire [7:0]          ctrl_prescale,
  input wire [DATA_W-1:0]   load_val,
  // Status feedback
  input wire                status_intr,
  // Outputs under test
  input wire [DATA_W-1:0]   hw_count_val,
  input wire                hw_intr_set,
  input wire                hw_active,
  input wire                irq,
  input wire                trigger_out
);

  // ---------------------------------------------------------------------------
  // P1 — IRQ is purely combinational: status_intr AND ctrl_intr_en
  // ---------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n)
      p_irq_def: assert (irq == (status_intr & ctrl_intr_en));
  end

  // ---------------------------------------------------------------------------
  // P2 — hw_active de-asserts within one cycle of ctrl_en going low
  //      i.e. if ctrl_en was 0 last cycle, hw_active must be 0 now
  // ---------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n)
      p_active_requires_en: assert (!$past(ctrl_en, 1) ? !hw_active : 1'b1);
  end

  // ---------------------------------------------------------------------------
  // P3 — hw_intr_set is a one-cycle pulse (never two consecutive cycles)
  // ---------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n)
      p_intr_set_pulse: assert ($past(hw_intr_set) ? !hw_intr_set : 1'b1);
  end

  // ---------------------------------------------------------------------------
  // P4 — trigger_out is a one-cycle pulse
  // ---------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n)
      p_trig_pulse: assert ($past(trigger_out) ? !trigger_out : 1'b1);
  end

  // ---------------------------------------------------------------------------
  // P5 — trigger_out cannot assert when ctrl_trig_en is low
  // ---------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n)
      p_trig_requires_en: assert (!ctrl_trig_en ? !trigger_out : 1'b1);
  end

  // ---------------------------------------------------------------------------
  // P6 — One cycle after EN rises, hw_count_val == load_val (counter loaded)
  // ---------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n)
      p_load_on_enable: assert ($rose(ctrl_en) ? (hw_count_val == $past(load_val)) : 1'b1);
  end

  // ---------------------------------------------------------------------------
  // Cover goals
  // ---------------------------------------------------------------------------
  always @(posedge clk) begin
    c_intr_set: cover (rst_n && hw_intr_set);
    c_oneshot:  cover (rst_n && ctrl_en && ctrl_mode && $fell(hw_active));
    c_trig_out: cover (rst_n && trigger_out);
  end

endmodule : timer_core_props
`default_nettype wire
