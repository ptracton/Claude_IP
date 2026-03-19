// timer_regfile_synth.sv — Yosys-compatible copy of timer_regfile.sv.
//
// Yosys 0.60's SV frontend does not support the SV2012
// "module X import pkg::*;" syntax.  This file is FUNCTIONALLY IDENTICAL
// to timer_regfile.sv but replaces the package import with inline localparams.
// Used ONLY by the synthesis/yosys scripts; all other flows use the original.

module timer_regfile (
  // Clock and synchronous active-low reset
  input  logic        clk,
  input  logic        rst_n,

  // Write channel
  input  logic        wr_en,
  input  logic [3:0]  wr_addr,
  input  logic [31:0] wr_data,
  input  logic [3:0]  wr_strb,

  // Read channel
  input  logic        rd_en,
  input  logic [3:0]  rd_addr,
  output logic [31:0] rd_data,

  // Hardware update ports (from timer_core)
  input  logic [31:0] hw_count_val,
  input  logic        hw_intr_set,
  input  logic        hw_active,

  // Output to timer_core
  output logic        ctrl_en,
  output logic        ctrl_mode,
  output logic        ctrl_intr_en,
  output logic        ctrl_trig_en,
  output logic [7:0]  ctrl_prescale,
  output logic [31:0] load_val,
  output logic        status_intr
);

  // -----------------------------------------------------------------------
  // Register-address and field constants (inlined from timer_reg_pkg)
  // -----------------------------------------------------------------------
  localparam logic [3:0]  TIMER_CTRL_OFFSET   = 4'h0;
  localparam logic [3:0]  TIMER_STATUS_OFFSET = 4'h1;
  localparam logic [3:0]  TIMER_LOAD_OFFSET   = 4'h2;
  localparam logic [3:0]  TIMER_COUNT_OFFSET  = 4'h3;

  localparam logic [31:0] TIMER_CTRL_RESET    = 32'h0000_0000;
  localparam logic [31:0] TIMER_STATUS_RESET  = 32'h0000_0000;
  localparam logic [31:0] TIMER_LOAD_RESET    = 32'h0000_0000;
  localparam logic [31:0] TIMER_COUNT_RESET   = 32'h0000_0000;

  localparam int unsigned TIMER_CTRL_EN_BIT       = 0;
  localparam int unsigned TIMER_CTRL_MODE_BIT     = 1;
  localparam int unsigned TIMER_CTRL_INTR_EN_BIT  = 2;
  localparam int unsigned TIMER_CTRL_TRIG_EN_BIT  = 3;
  localparam int unsigned TIMER_CTRL_PRESCALE_LSB = 4;

  localparam int unsigned TIMER_STATUS_INTR_BIT   = 0;
  localparam int unsigned TIMER_STATUS_ACTIVE_BIT = 1;

  // -----------------------------------------------------------------------
  // Internal register storage
  // -----------------------------------------------------------------------
  logic [31:0] ctrl_q;
  logic [31:0] status_q;
  logic [31:0] load_q;
  logic [31:0] count_q;

  // -----------------------------------------------------------------------
  // Byte-enable merge helper
  // -----------------------------------------------------------------------
  function automatic [31:0] apply_strb(
    input [31:0] current,
    input [31:0] wdata,
    input [3:0]  strb
  );
    apply_strb[7:0]   = strb[0] ? wdata[7:0]   : current[7:0];
    apply_strb[15:8]  = strb[1] ? wdata[15:8]  : current[15:8];
    apply_strb[23:16] = strb[2] ? wdata[23:16] : current[23:16];
    apply_strb[31:24] = strb[3] ? wdata[31:24] : current[31:24];
  endfunction

  // -----------------------------------------------------------------------
  // CTRL register
  // -----------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      ctrl_q <= TIMER_CTRL_RESET;
    end else if (wr_en && (wr_addr == TIMER_CTRL_OFFSET)) begin
      ctrl_q <= apply_strb(ctrl_q, wr_data, wr_strb) & 32'h0000_0FFF;
    end
  end

  // -----------------------------------------------------------------------
  // STATUS register (W1C INTR, RO ACTIVE)
  // -----------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      status_q <= TIMER_STATUS_RESET;
    end else begin
      status_q[TIMER_STATUS_ACTIVE_BIT] <= hw_active;
      if (hw_intr_set) begin
        status_q[TIMER_STATUS_INTR_BIT] <= 1'b1;
      end else if (wr_en && (wr_addr == TIMER_STATUS_OFFSET) &&
                   wr_strb[0] && wr_data[TIMER_STATUS_INTR_BIT]) begin
        status_q[TIMER_STATUS_INTR_BIT] <= 1'b0;
      end
      status_q[31:2] <= 30'h0;
    end
  end

  // -----------------------------------------------------------------------
  // LOAD register
  // -----------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      load_q <= TIMER_LOAD_RESET;
    end else if (wr_en && (wr_addr == TIMER_LOAD_OFFSET)) begin
      load_q <= apply_strb(load_q, wr_data, wr_strb);
    end
  end

  // -----------------------------------------------------------------------
  // COUNT register
  // -----------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      count_q <= TIMER_COUNT_RESET;
    end else begin
      count_q <= hw_count_val;
    end
  end

  // -----------------------------------------------------------------------
  // Read path (registered)
  // -----------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rd_data <= 32'h0000_0000;
    end else if (rd_en) begin
      case (rd_addr)
        TIMER_CTRL_OFFSET:   rd_data <= ctrl_q;
        TIMER_STATUS_OFFSET: rd_data <= status_q;
        TIMER_LOAD_OFFSET:   rd_data <= load_q;
        TIMER_COUNT_OFFSET:  rd_data <= count_q;
        default:             rd_data <= 32'h0000_0000;
      endcase
    end
  end

  // -----------------------------------------------------------------------
  // Output assignments
  // -----------------------------------------------------------------------
  assign ctrl_en       = ctrl_q[TIMER_CTRL_EN_BIT];
  assign ctrl_mode     = ctrl_q[TIMER_CTRL_MODE_BIT];
  assign ctrl_intr_en  = ctrl_q[TIMER_CTRL_INTR_EN_BIT];
  assign ctrl_trig_en  = ctrl_q[TIMER_CTRL_TRIG_EN_BIT];
  assign ctrl_prescale = ctrl_q[TIMER_CTRL_PRESCALE_LSB +: 8];
  assign load_val      = load_q;
  assign status_intr   = status_q[TIMER_STATUS_INTR_BIT];

endmodule : timer_regfile
