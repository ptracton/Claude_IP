// timer_regfile_props.sv — Formal verification properties for timer_regfile.
//
// Attach via bind:
//   bind timer_regfile timer_regfile_props u_props (.*);
//
// Properties verified:
//   P1: CTRL.EN reflects last written value (write-then-stable)
//   P2: W1C clears STATUS.INTR when hw_intr_set is not simultaneously firing
//   P3: hw_intr_set pulse sets status_intr
//   P4: CTRL reserved bits [7:4] of prescale are always zero
//   P5: load_val stable when no write to LOAD register

`default_nettype none

module timer_regfile_props (
  input wire        clk,
  input wire        rst_n,
  // Write channel
  input wire        wr_en,
  input wire [3:0]  wr_addr,
  input wire [31:0] wr_data,
  input wire [3:0]  wr_strb,
  // Hardware update inputs
  input wire        hw_intr_set,
  input wire        hw_active,
  input wire [31:0] hw_count_val,
  // Decoded output ports
  input wire        ctrl_en,
  input wire        ctrl_mode,
  input wire        ctrl_intr_en,
  input wire        ctrl_trig_en,
  input wire [7:0]  ctrl_prescale,
  input wire [31:0] load_val,
  input wire        status_intr
);

  localparam [3:0] CTRL_ADDR   = 4'h0;
  localparam [3:0] STATUS_ADDR = 4'h1;
  localparam [3:0] LOAD_ADDR   = 4'h2;

  // ---------------------------------------------------------------------------
  // P1 — After a full-strobe write to CTRL[0] (byte0), ctrl_en matches wr_data[0]
  // ---------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n)
      p_ctrl_en_write: assert (
        ($past(wr_en) && $past(wr_addr) == CTRL_ADDR && $past(wr_strb[0]))
          ? (ctrl_en == $past(wr_data[0])) : 1'b1
      );
  end

  // ---------------------------------------------------------------------------
  // P2 — W1C: writing 1 to STATUS[0] clears status_intr (if hw doesn't set it)
  // ---------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n)
      p_w1c_clears_intr: assert (
        ($past(wr_en) && $past(wr_addr) == STATUS_ADDR &&
         $past(wr_strb[0]) && $past(wr_data[0]) && !$past(hw_intr_set))
          ? !status_intr : 1'b1
      );
  end

  // ---------------------------------------------------------------------------
  // P3 — hw_intr_set pulse sets status_intr the next cycle
  // ---------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n)
      p_hw_sets_intr: assert ($past(hw_intr_set) ? status_intr : 1'b1);
  end

  // ---------------------------------------------------------------------------
  // P4 — Upper prescale nibble [7:4] is always zero (reserved in CTRL[11:8])
  // ---------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n)
      p_ctrl_prescale_reserved: assert (ctrl_prescale[7:4] == 4'h0);
  end

  // ---------------------------------------------------------------------------
  // P5 — load_val only changes on a write to LOAD_ADDR
  // ---------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n)
      p_load_stable: assert (
        (!$past(wr_en) || $past(wr_addr) != LOAD_ADDR)
          ? (load_val == $past(load_val)) : 1'b1
      );
  end

  // ---------------------------------------------------------------------------
  // Cover goals
  // ---------------------------------------------------------------------------
  always @(posedge clk) begin
    c_intr_set:   cover (rst_n && status_intr);
    c_intr_clear: cover (rst_n && $past(status_intr) && !status_intr);
    c_ctrl_en:    cover (rst_n && ctrl_en);
  end

endmodule : timer_regfile_props
`default_nettype wire
