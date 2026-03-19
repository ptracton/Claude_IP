// timer_core.sv — Timer IP core logic.
//
// Implements the 32-bit down-counter with 8-bit pre-scaler, two operating
// modes (repeating / one-shot), interrupt generation, and trigger output.
// Extended with: RESTART force-reload, IRQ_MODE level/pulse select,
// OVF overrun detection, and LOAD=0 minimum-count protection.
//
// This module is bus-protocol-agnostic.  All register-file decoded outputs
// come in as inputs and all hardware-update signals go out as outputs.
//
// Ports:
//   clk            : input  — system clock (rising-edge active)
//   rst_n          : input  — synchronous active-low reset
//   ctrl_en        : input  — CTRL.EN; enables counter operation
//   ctrl_mode      : input  — CTRL.MODE; 0=repeat, 1=one-shot
//   ctrl_intr_en   : input  — CTRL.INTR_EN; interrupt mask
//   ctrl_trig_en   : input  — CTRL.TRIG_EN; trigger-output gate
//   ctrl_prescale  : input  [7:0]  — CTRL.PRESCALE; prescaler reload value
//   ctrl_restart   : input  — CTRL.RESTART self-clearing pulse; force-reload
//   ctrl_irq_mode  : input  — CTRL.IRQ_MODE; 0=level, 1=pulse irq output
//   load_val       : input  [31:0] — LOAD register value; counter reload
//   status_intr    : input  — STATUS.INTR bit (from regfile); for IRQ masking
//   hw_count_val   : output [31:0] — current count to regfile COUNT register
//   hw_intr_set    : output — one-cycle pulse; sets STATUS.INTR in regfile
//   hw_ovf_set     : output — one-cycle pulse; sets STATUS.OVF (underflow while INTR pending)
//   hw_active      : output — asserted while counter is running
//   irq            : output — masked interrupt output
//   trigger_out    : output — one-cycle pulse on underflow (gated by TRIG_EN)

module timer_core #(
  parameter int unsigned DATA_W = 32  // counter / load value width
) (
  // Clock and synchronous active-low reset
  input  logic                  clk,          // system clock
  input  logic                  rst_n,        // synchronous active-low reset

  // Decoded register outputs (from timer_regfile)
  input  logic                  ctrl_en,       // CTRL.EN
  input  logic                  ctrl_mode,     // CTRL.MODE (0=repeat, 1=one-shot)
  input  logic                  ctrl_intr_en,  // CTRL.INTR_EN
  input  logic                  ctrl_trig_en,  // CTRL.TRIG_EN
  input  logic [7:0]            ctrl_prescale, // CTRL.PRESCALE (divide = PRESCALE+1)
  input  logic                  ctrl_restart,  // CTRL.RESTART self-clearing pulse
  input  logic                  ctrl_irq_mode, // CTRL.IRQ_MODE: 0=level, 1=pulse
  input  logic [DATA_W-1:0]     load_val,      // LOAD register value

  // Status feedback from regfile (needed to compute masked IRQ and OVF)
  input  logic                  status_intr,   // STATUS.INTR sticky bit

  // Hardware update outputs (to timer_regfile)
  output logic [DATA_W-1:0]     hw_count_val,  // current count value
  output logic                  hw_intr_set,   // one-cycle pulse to set STATUS.INTR
  output logic                  hw_ovf_set,    // one-cycle pulse to set STATUS.OVF
  output logic                  hw_active,     // counter is enabled and running

  // External IP outputs
  output logic                  irq,           // masked interrupt output
  output logic                  trigger_out    // one-cycle trigger pulse on underflow
);

  // -------------------------------------------------------------------------
  // Internal signals
  // -------------------------------------------------------------------------
  logic [7:0]        prescale_cnt_q; // prescaler down-counter
  logic [DATA_W-1:0] count_q;        // main 32-bit down-counter
  logic              active_q;       // counter running flag
  logic              tick;           // one-cycle pulse from prescaler

  logic              en_prev_q;      // previous-cycle ctrl_en for edge detect
  logic              load_pulse;     // asserted one cycle when EN asserts

  // LOAD=0 protection: minimum reload value is 1 to prevent infinite underflow
  // in repeat mode.  One-shot mode already halts after one underflow.
  logic [DATA_W-1:0] safe_load_val;

  // -------------------------------------------------------------------------
  // EN rising-edge detection: reload counter when EN transitions 0->1
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin : p_en_edge
    if (!rst_n) begin
      en_prev_q <= 1'b0;
    end else begin
      en_prev_q <= ctrl_en;
    end
  end

  assign load_pulse    = ctrl_en & ~en_prev_q;
  assign safe_load_val = (load_val == {DATA_W{1'b0}}) ?
                         {{(DATA_W-1){1'b0}}, 1'b1} : load_val;

  // -------------------------------------------------------------------------
  // Pre-scaler: counts from ctrl_prescale down to 0, then wraps and asserts
  // tick for one cycle.  When ctrl_prescale == 0 tick fires every cycle.
  // RESTART resets the prescaler to ctrl_prescale (same as disable state).
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin : p_prescaler
    if (!rst_n) begin
      prescale_cnt_q <= 8'h00;
    end else if (!ctrl_en) begin
      // Hold prescaler in reset while timer is disabled.
      prescale_cnt_q <= ctrl_prescale;
    end else if (ctrl_restart) begin
      // Force-reload: reset prescaler so next tick starts a fresh period.
      prescale_cnt_q <= ctrl_prescale;
    end else begin
      if (prescale_cnt_q == 8'h00) begin
        prescale_cnt_q <= ctrl_prescale; // reload prescaler
      end else begin
        prescale_cnt_q <= prescale_cnt_q - 8'h01;
      end
    end
  end

  // tick fires when the prescaler wraps to zero (output phase)
  assign tick = ctrl_en & (prescale_cnt_q == 8'h00);

  // -------------------------------------------------------------------------
  // Main 32-bit down-counter and active flag
  // Uses safe_load_val (min 1) to prevent infinite zero-period loops.
  // RESTART force-reloads the counter without toggling EN.
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin : p_counter
    if (!rst_n) begin
      count_q  <= {DATA_W{1'b0}};
      active_q <= 1'b0;
    end else begin
      if (load_pulse) begin
        // EN just asserted: load counter and mark as active.
        count_q  <= safe_load_val;
        active_q <= 1'b1;
      end else if (ctrl_en && ctrl_restart && active_q) begin
        // Force-reload: reload without disabling; active_q stays 1.
        // Guard with ctrl_en to match prescaler behavior — RESTART is a no-op
        // when the timer is disabled, so !ctrl_en always wins.
        count_q <= safe_load_val;
      end else if (active_q && tick) begin
        if (count_q == {DATA_W{1'b0}}) begin
          // Underflow event
          if (ctrl_mode == 1'b0) begin
            // Repeat mode: reload with LOAD=0 protection and continue.
            count_q  <= safe_load_val;
            active_q <= 1'b1;
          end else begin
            // One-shot mode: stop after underflow.
            count_q  <= {DATA_W{1'b0}};
            active_q <= 1'b0;
          end
        end else begin
          count_q <= count_q - {{(DATA_W-1){1'b0}}, 1'b1};
        end
      end else if (!ctrl_en) begin
        // EN deasserted externally: stop counter.
        active_q <= 1'b0;
      end
    end
  end

  // -------------------------------------------------------------------------
  // Underflow detection — combinational, one cycle ahead of register update
  // Underflow occurs when count_q == 0 AND tick fires AND counter is active.
  // -------------------------------------------------------------------------
  logic underflow;
  assign underflow = active_q & tick & (count_q == {DATA_W{1'b0}});

  // -------------------------------------------------------------------------
  // hw_intr_set: one-cycle pulse to regfile on underflow
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin : p_intr_set
    if (!rst_n) begin
      hw_intr_set <= 1'b0;
    end else begin
      hw_intr_set <= underflow;
    end
  end

  // -------------------------------------------------------------------------
  // hw_ovf_set: one-cycle pulse when underflow fires while INTR is already set.
  // Indicates a missed interrupt (overrun): timer fired again before SW cleared it.
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin : p_ovf_set
    if (!rst_n) begin
      hw_ovf_set <= 1'b0;
    end else begin
      hw_ovf_set <= underflow & status_intr;
    end
  end

  // -------------------------------------------------------------------------
  // trigger_out: one-cycle pulse on underflow, gated by ctrl_trig_en
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin : p_trigger
    if (!rst_n) begin
      trigger_out <= 1'b0;
    end else begin
      trigger_out <= underflow & ctrl_trig_en;
    end
  end

  // -------------------------------------------------------------------------
  // hw_count_val and hw_active: combinational from register state
  // -------------------------------------------------------------------------
  assign hw_count_val = count_q;
  assign hw_active    = active_q;

  // -------------------------------------------------------------------------
  // irq: masked interrupt output, mode-selectable
  //   Level mode (ctrl_irq_mode=0): irq is asserted as long as STATUS.INTR is set
  //   Pulse mode (ctrl_irq_mode=1): irq is a one-cycle pulse per underflow event
  // -------------------------------------------------------------------------
  assign irq = ctrl_intr_en & (ctrl_irq_mode ? hw_intr_set : status_intr);

endmodule : timer_core
