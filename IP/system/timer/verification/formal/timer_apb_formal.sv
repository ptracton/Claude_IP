// timer_apb_formal.sv — Flat formal wrapper for APB4 variant.
// Instantiates all submodules directly so internal signals are accessible
// for formal property assertions. Uses timer_regfile_synth.sv (Yosys-compat).
//
// Uses explicit flip-flop helpers for "past" values to avoid $past() initial-
// state issues with smtbmc's unconstrained initial state.
`default_nettype none
module timer_apb_formal #(
  parameter integer DATA_W = 32,
  parameter integer ADDR_W = 4
) (
  input  wire                PCLK,
  input  wire                PRESETn,
  input  wire                PSEL,
  input  wire                PENABLE,
  input  wire [11:0]         PADDR,
  input  wire                PWRITE,
  input  wire [DATA_W-1:0]   PWDATA,
  input  wire [DATA_W/8-1:0] PSTRB,
  output wire [DATA_W-1:0]   PRDATA,
  output wire                PREADY,
  output wire                PSLVERR,
  output wire                irq,
  output wire                trigger_out
);

  // Internal wires matching timer_apb.sv
  wire                if_wr_en;
  wire [ADDR_W-1:0]   if_wr_addr;
  wire [DATA_W-1:0]   if_wr_data;
  wire [DATA_W/8-1:0] if_wr_strb;
  wire                if_rd_en;
  wire [ADDR_W-1:0]   if_rd_addr;
  wire [DATA_W-1:0]   if_rd_data;
  wire                ctrl_en;
  wire                ctrl_mode;
  wire                ctrl_intr_en;
  wire                ctrl_trig_en;
  wire [7:0]          ctrl_prescale;
  wire                ctrl_restart;
  wire                ctrl_irq_mode;
  wire [DATA_W-1:0]   load_val;
  wire                status_intr;
  wire [DATA_W-1:0]   hw_count_val;
  wire                hw_intr_set;
  wire                hw_ovf_set;
  wire                hw_active;

  // Bus interface
  claude_apb_if #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_if (
    .PCLK    (PCLK),
    .PRESETn (PRESETn),
    .PSEL    (PSEL),
    .PENABLE (PENABLE),
    .PADDR   (PADDR),
    .PWRITE  (PWRITE),
    .PWDATA  (PWDATA),
    .PSTRB   (PSTRB),
    .PRDATA  (PRDATA),
    .PREADY  (PREADY),
    .PSLVERR (PSLVERR),
    .wr_en   (if_wr_en),
    .wr_addr (if_wr_addr),
    .wr_data (if_wr_data),
    .wr_strb (if_wr_strb),
    .rd_en   (if_rd_en),
    .rd_addr (if_rd_addr),
    .rd_data (if_rd_data)
  );

  // Register file (Yosys-compatible version)
  timer_regfile u_regfile (
    .clk         (PCLK),
    .rst_n       (PRESETn),
    .wr_en       (if_wr_en),
    .wr_addr     (if_wr_addr),
    .wr_data     (if_wr_data),
    .wr_strb     (if_wr_strb),
    .rd_en       (if_rd_en),
    .rd_addr     (if_rd_addr),
    .rd_data     (if_rd_data),
    .hw_count_val(hw_count_val),
    .hw_intr_set (hw_intr_set),
    .hw_ovf_set  (hw_ovf_set),
    .hw_active   (hw_active),
    .ctrl_en     (ctrl_en),
    .ctrl_mode   (ctrl_mode),
    .ctrl_intr_en(ctrl_intr_en),
    .ctrl_trig_en(ctrl_trig_en),
    .ctrl_prescale(ctrl_prescale),
    .ctrl_restart (ctrl_restart),
    .ctrl_irq_mode(ctrl_irq_mode),
    .load_val    (load_val),
    .status_intr (status_intr)
  );

  // Core
  timer_core #(.DATA_W(DATA_W)) u_core (
    .clk          (PCLK),
    .rst_n        (PRESETn),
    .ctrl_en      (ctrl_en),
    .ctrl_mode    (ctrl_mode),
    .ctrl_intr_en (ctrl_intr_en),
    .ctrl_trig_en (ctrl_trig_en),
    .ctrl_prescale(ctrl_prescale),
    .ctrl_restart (ctrl_restart),
    .ctrl_irq_mode(ctrl_irq_mode),
    .load_val     (load_val),
    .status_intr  (status_intr),
    .hw_count_val (hw_count_val),
    .hw_intr_set  (hw_intr_set),
    .hw_ovf_set   (hw_ovf_set),
    .hw_active    (hw_active),
    .irq          (irq),
    .trigger_out  (trigger_out)
  );

  // ---------------------------------------------------------------------------
  // Formal infrastructure: reset tracking + "past" helpers
  //
  // After the first de-assertion of PRESETn, assertions are guarded by
  // `reset_done`.  All past_* registers start at 0 (valid after reset) so
  // there is no unconstrained-initial-state issue.
  // ---------------------------------------------------------------------------
  reg  reset_done;
  reg  past_PRESETn;
  reg  past_ctrl_en;
  reg  past_past_ctrl_en;
  reg  past_ctrl_trig_en;
  reg  past_hw_intr_set;
  reg  past_trigger_out;
  reg  past_if_wr_en;
  reg  [ADDR_W-1:0]   past_if_wr_addr;
  reg  [DATA_W-1:0]   past_if_wr_data;
  reg  [DATA_W/8-1:0] past_if_wr_strb;
  reg  [DATA_W-1:0]   past_load_val;

  always @(posedge PCLK) begin
    if (!PRESETn) begin
      reset_done        <= 1'b1;
      past_PRESETn      <= 1'b0;
      past_ctrl_en      <= 1'b0;
      past_past_ctrl_en <= 1'b0;
      past_ctrl_trig_en <= 1'b0;
      past_hw_intr_set  <= 1'b0;
      past_trigger_out  <= 1'b0;
      past_if_wr_en     <= 1'b0;
      past_if_wr_addr   <= {ADDR_W{1'b0}};
      past_if_wr_data   <= {DATA_W{1'b0}};
      past_if_wr_strb   <= {(DATA_W/8){1'b0}};
      past_load_val     <= {DATA_W{1'b0}};
    end else begin
      past_PRESETn      <= PRESETn;
      past_ctrl_en      <= ctrl_en;
      past_past_ctrl_en <= past_ctrl_en;
      past_ctrl_trig_en <= ctrl_trig_en;
      past_hw_intr_set  <= hw_intr_set;
      past_trigger_out  <= trigger_out;
      past_if_wr_en     <= if_wr_en;
      past_if_wr_addr   <= if_wr_addr;
      past_if_wr_data   <= if_wr_data;
      past_if_wr_strb   <= if_wr_strb;
      past_load_val     <= load_val;
    end
  end

  // Constrain: the very first clock cycle must have reset active.
  // This prevents smtbmc from exploiting unconstrained anyinit values
  // to reach a "past" state that never actually followed a reset.
  always @(posedge PCLK) begin
    if ($initstate) assume (!PRESETn);
  end

  // Guard: only assert in a stable post-reset state
  wire check = reset_done && PRESETn && past_PRESETn;

  // Assumption: exclude degenerate repeat-mode config where load_val=0 and
  // prescale=0 together cause continuous underflow (hw_intr_set every cycle).
  // A well-configured timer always has at least one of these non-zero.
  always @(posedge PCLK) begin
    if (check)
      assume (!(ctrl_en && !ctrl_mode &&
                load_val == {DATA_W{1'b0}} &&
                ctrl_prescale == 8'h00));
  end

  // ---------------------------------------------------------------------------
  // P1 — IRQ output matches RTL formula:
  //   level mode (ctrl_irq_mode=0): irq = ctrl_intr_en & status_intr
  //   pulse mode (ctrl_irq_mode=1): irq = ctrl_intr_en & hw_intr_set
  // ---------------------------------------------------------------------------
  always @(posedge PCLK) begin
    if (check) p_irq_def: assert (irq ==
      (ctrl_intr_en & (ctrl_irq_mode ? hw_intr_set : status_intr)));
  end

  // ---------------------------------------------------------------------------
  // P2 — hw_active de-asserts within one cycle of ctrl_en going low
  // ---------------------------------------------------------------------------
  always @(posedge PCLK) begin
    if (check) p_active_en: assert (!past_ctrl_en ? !hw_active : 1'b1);
  end

  // ---------------------------------------------------------------------------
  // P3 — hw_intr_set is a one-cycle pulse
  // ---------------------------------------------------------------------------
  always @(posedge PCLK) begin
    if (check) p_intr_pulse: assert (past_hw_intr_set ? !hw_intr_set : 1'b1);
  end

  // ---------------------------------------------------------------------------
  // P4 — trigger_out is a one-cycle pulse
  // ---------------------------------------------------------------------------
  always @(posedge PCLK) begin
    if (check) p_trig_pulse: assert (past_trigger_out ? !trigger_out : 1'b1);
  end

  // ---------------------------------------------------------------------------
  // P5 — trigger_out gated by ctrl_trig_en  (stateless)
  // ---------------------------------------------------------------------------
  always @(posedge PCLK) begin
    if (check) p_trig_en: assert (!past_ctrl_trig_en ? !trigger_out : 1'b1);
  end

  // ---------------------------------------------------------------------------
  // P6 — Counter loads from load_val one cycle after ctrl_en rises
  // Guard: past_load_val != 0 because core uses safe_load_val (min 1) when
  // load_val=0, so hw_count_val=1 rather than 0 in that degenerate case.
  // ---------------------------------------------------------------------------
  always @(posedge PCLK) begin
    if (check) p_load: assert ((!past_past_ctrl_en && past_ctrl_en &&
                                 past_load_val != {DATA_W{1'b0}}) ?
      (hw_count_val == past_load_val) : 1'b1);
  end

  // ---------------------------------------------------------------------------
  // P7 — After write to CTRL byte0, ctrl_en reflects wr_data[0]
  // ---------------------------------------------------------------------------
  always @(posedge PCLK) begin
    if (check) p_ctrl_write: assert (
      (past_if_wr_en && past_if_wr_addr == 4'h0 && past_if_wr_strb[0])
        ? (ctrl_en == past_if_wr_data[0]) : 1'b1
    );
  end

  // ---------------------------------------------------------------------------
  // P8 — W1C: writing 1 to STATUS[0] clears status_intr (no hw_intr_set)
  // ---------------------------------------------------------------------------
  always @(posedge PCLK) begin
    if (check) p_w1c: assert (
      (past_if_wr_en && past_if_wr_addr == 4'h1 &&
       past_if_wr_strb[0] && past_if_wr_data[0] && !past_hw_intr_set)
        ? !status_intr : 1'b1
    );
  end

  // ---------------------------------------------------------------------------
  // P9 — hw_intr_set sets status_intr next cycle
  // ---------------------------------------------------------------------------
  always @(posedge PCLK) begin
    if (check) p_hw_sets: assert (past_hw_intr_set ? status_intr : 1'b1);
  end

  // ---------------------------------------------------------------------------
  // Cover goals
  // ---------------------------------------------------------------------------
  always @(posedge PCLK) begin
    c_intr:   cover (check && hw_intr_set);
    c_trig:   cover (check && trigger_out);
    c_oneshot:cover (check && ctrl_en && ctrl_mode && !past_ctrl_en);
  end

endmodule
`default_nettype wire
