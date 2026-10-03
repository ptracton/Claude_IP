// timer_regfile_fv.sv — VC Formal properties for timer_regfile.
//
// Bound to every timer_regfile instance (SV module or VHDL entity) by the
// timer_<proto>_fv_bind modules. Uses only timer_regfile ports.
// Covers the hardware-owned behaviour that the protocol-neutral read-back
// checker (timer_regmap_fv) deliberately leaves out: self-clearing CTRL
// bits, STATUS set/W1C, and the COUNT/CAPTURE mirrors.

module timer_regfile_fv (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        wr_en,
  input  logic [3:0]  wr_addr,
  input  logic [31:0] wr_data,
  input  logic [3:0]  wr_strb,
  input  logic        rd_en,
  input  logic [3:0]  rd_addr,
  input  logic [31:0] rd_data,
  input  logic [31:0] hw_count_val,
  input  logic        hw_intr_set,
  input  logic        hw_ovf_set,
  input  logic        hw_active,
  input  logic        ctrl_en,
  input  logic        ctrl_mode,
  input  logic        ctrl_intr_en,
  input  logic        ctrl_trig_en,
  input  logic [7:0]  ctrl_prescale,
  input  logic        ctrl_restart,
  input  logic        ctrl_irq_mode,
  input  logic [31:0] load_val,
  input  logic        status_intr
);

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  localparam logic [3:0] CTRL    = 4'h0;
  localparam logic [3:0] STATUS  = 4'h1;
  localparam logic [3:0] LOAD    = 4'h2;
  localparam logic [3:0] COUNT   = 4'h3;
  localparam logic [3:0] CAPTURE = 4'h4;

  logic wr_ctrl, wr_status, wr_load;
  logic w1c_intr, w1c_ovf, set_restart, set_snapshot;
  logic ovf_q;      // STATUS.OVF, observed through a STATUS read
  logic snap_pend;  // SNAPSHOT written last cycle

  assign wr_ctrl      = wr_en && wr_addr == CTRL;
  assign wr_status    = wr_en && wr_addr == STATUS;
  assign wr_load      = wr_en && wr_addr == LOAD;
  assign w1c_intr     = wr_status && wr_strb[0] && wr_data[0];
  assign w1c_ovf      = wr_status && wr_strb[0] && wr_data[2];
  assign set_restart  = wr_ctrl && wr_strb[1] && wr_data[12];
  assign set_snapshot = wr_ctrl && wr_strb[1] && wr_data[14];

  // CTRL fields follow byte-strobed writes.
  p_ctrl_byte0: assert property (
    (wr_ctrl && wr_strb[0]) |=>
      ({ctrl_trig_en, ctrl_intr_en, ctrl_mode, ctrl_en} == $past(wr_data[3:0])));
  p_ctrl_hold: assert property (
    !wr_ctrl |=> $stable({ctrl_en, ctrl_mode, ctrl_intr_en, ctrl_trig_en,
                          ctrl_prescale, ctrl_irq_mode}));

  // RESTART is a one-cycle pulse per write.
  p_restart_set:   assert property (set_restart |=> ctrl_restart);
  p_restart_clear: assert property (!set_restart |=> !ctrl_restart);

  // LOAD follows full-word writes and otherwise holds.
  p_load_write: assert property ((wr_load && wr_strb == 4'hF) |=> load_val == $past(wr_data));
  p_load_hold:  assert property (!wr_load |=> $stable(load_val));

  // STATUS.INTR: set by hardware (priority over W1C), sticky, W1C.
  p_intr_set:    assert property (hw_intr_set |=> status_intr);
  p_intr_w1c:    assert property ((w1c_intr && !hw_intr_set) |=> !status_intr);
  p_intr_sticky: assert property ((status_intr && !w1c_intr) |=> status_intr);
  p_intr_no_spurious: assert property ((!status_intr && !hw_intr_set) |=> !status_intr);

  // STATUS read: ACTIVE mirrors hw_active one cycle late, INTR is live.
  p_rd_status: assert property (
    (rd_en && rd_addr == STATUS) |=>
      (rd_data[0] == $past(status_intr) && rd_data[1] == $past(hw_active, 2)));

  // STATUS.OVF shadow (set by hardware, W1C) compared on STATUS reads.
  always_ff @(posedge clk) begin
    if (!rst_n)          ovf_q <= 1'b0;
    else if (hw_ovf_set) ovf_q <= 1'b1;
    else if (w1c_ovf)    ovf_q <= 1'b0;
  end
  p_rd_ovf: assert property ((rd_en && rd_addr == STATUS) |=> rd_data[2] == $past(ovf_q));

  // COUNT reads return hw_count_val sampled the cycle before rd_en.
  p_rd_count: assert property (
    (rd_en && rd_addr == COUNT) |=> rd_data == $past(hw_count_val, 2));

  // CAPTURE latches hw_count_val the cycle after SNAPSHOT is written.
  always_ff @(posedge clk) begin
    if (!rst_n) snap_pend <= 1'b0;
    else        snap_pend <= set_snapshot;
  end
  p_capture: assert property (
    (snap_pend ##1 (rd_en && rd_addr == CAPTURE && !snap_pend)) |=>
      rd_data == $past(hw_count_val, 2));

  // Read data only changes on a read.
  p_rd_hold: assert property (!rd_en |=> $stable(rd_data));

  // Cover goals
  c_rd_ctrl:    cover property (rd_en && rd_addr == CTRL);
  c_rd_status:  cover property (rd_en && rd_addr == STATUS);
  c_rd_load:    cover property (rd_en && rd_addr == LOAD);
  c_rd_count:   cover property (rd_en && rd_addr == COUNT);
  c_rd_capture: cover property (rd_en && rd_addr == CAPTURE);
  c_w1c_intr:   cover property (status_intr ##1 w1c_intr ##1 !status_intr);
  c_snapshot:   cover property (set_snapshot);
  c_ovf:        cover property (hw_ovf_set);

endmodule : timer_regfile_fv
