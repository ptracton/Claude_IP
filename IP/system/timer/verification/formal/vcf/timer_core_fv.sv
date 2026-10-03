// timer_core_fv.sv — VC Formal properties for timer_core.
//
// Bound to every timer_core instance (SV module or VHDL entity) by the
// timer_<proto>_fv_bind modules. Uses only timer_core ports, so it is
// language-neutral. Inputs are driven by the real timer_regfile in the
// bound design, so there are no free-floating control inputs.

module timer_core_fv #(
  parameter int unsigned DATA_W = 32
) (
  input  logic              clk,
  input  logic              rst_n,
  input  logic              ctrl_en,
  input  logic              ctrl_mode,
  input  logic              ctrl_intr_en,
  input  logic              ctrl_trig_en,
  input  logic [7:0]        ctrl_prescale,
  input  logic              ctrl_restart,
  input  logic              ctrl_irq_mode,
  input  logic [DATA_W-1:0] load_val,
  input  logic              status_intr,
  input  logic [DATA_W-1:0] hw_count_val,
  input  logic              hw_intr_set,
  input  logic              hw_ovf_set,
  input  logic              hw_active,
  input  logic              irq,
  input  logic              trigger_out
);

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  logic [DATA_W-1:0] safe_load; // LOAD=0 behaves as LOAD=1 (spec)
  assign safe_load = (load_val == '0) ? DATA_W'(1) : load_val;

  // irq: level mode follows STATUS.INTR, pulse mode follows the set pulse.
  p_irq_def: assert property (
    irq == (ctrl_intr_en & (ctrl_irq_mode ? hw_intr_set : status_intr)));

  // Disabling stops the counter within one cycle and freezes COUNT.
  p_active_off: assert property (!ctrl_en |=> !hw_active);
  p_count_frozen: assert property (!ctrl_en |=> $stable(hw_count_val));

  // Enabling loads COUNT from LOAD.
  p_load_on_enable: assert property (
    (ctrl_en && !$past(ctrl_en)) |=> (hw_count_val == $past(safe_load) && hw_active));

  // While running (no enable edge, no restart), COUNT holds or decrements.
  p_count_step: assert property (
    (ctrl_en && $past(ctrl_en) && !ctrl_restart && hw_active && hw_count_val != '0) |=>
      (hw_count_val == $past(hw_count_val) ||
       hw_count_val == $past(hw_count_val) - DATA_W'(1)));

  // Underflow: repeat mode reloads and keeps running, one-shot stops.
  p_repeat_reload: assert property (
    (hw_intr_set && !$past(ctrl_mode)) |-> (hw_active && hw_count_val == $past(safe_load)));
  p_oneshot_stop: assert property (
    (hw_intr_set && $past(ctrl_mode) && !$past(ctrl_restart)) |-> !hw_active);

  // Event outputs are single-cycle pulses tied to underflow.
  p_intr_pulse: assert property (hw_intr_set |=> !hw_intr_set);
  p_trig_pulse: assert property (trigger_out |=> !trigger_out);
  p_trig_gated: assert property (trigger_out |-> ($past(ctrl_trig_en) && hw_intr_set));
  p_ovf_needs_intr: assert property (hw_ovf_set |-> (hw_intr_set && $past(status_intr)));

  // Cover goals
  c_underflow_repeat: cover property (hw_intr_set && !$past(ctrl_mode));
  c_oneshot_done:     cover property ($fell(hw_active) && ctrl_en);
  c_irq_level:        cover property (irq && !ctrl_irq_mode);
  c_irq_pulse:        cover property (irq &&  ctrl_irq_mode);
  c_trigger:          cover property (trigger_out);
  c_overflow:         cover property (hw_ovf_set);
  c_restart:          cover property (ctrl_restart && hw_active);
  c_prescaled_step:   cover property (ctrl_prescale != 8'h00 && hw_active &&
                                      hw_count_val != $past(hw_count_val) && $past(hw_active));

endmodule : timer_core_fv
