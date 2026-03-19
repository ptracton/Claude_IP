// timer_model.sv — Behavioral reference model for Timer IP.
//
// Non-synthesizable functional model used by the UVM scoreboard (Step 6).
// Models the expected register state and IP outputs for any sequence of
// register reads and writes applied through the flat register-access bus.
//
// This model operates on the same bus-agnostic register interface as the
// synthesizable regfile so it can be driven by any protocol BFM.
//
// Behavioral model assumptions:
//   - Single-cycle write / two-cycle read (matches synthesizable regfile).
//   - Prescaler and counter advance on every clock edge when enabled.
//   - hw_intr_set and trigger_out are one-cycle pulses.
//   - IRQ = STATUS.INTR & CTRL.INTR_EN (combinational).
//
// This file uses non-synthesizable constructs (initial blocks, $display,
// automatic functions) and must NOT be placed in synthesis file lists.

`ifndef SYNTHESIS

module timer_model #(
  parameter int unsigned DATA_W = 32,
  parameter int unsigned ADDR_W = 4
) (
  // Clock and synchronous active-low reset
  input  logic                  clk,           // system clock
  input  logic                  rst_n,         // synchronous active-low reset

  // Register-file write channel (driven by BFM)
  input  logic                  wr_en,         // write enable
  input  logic [ADDR_W-1:0]     wr_addr,       // word address
  input  logic [DATA_W-1:0]     wr_data,       // write data
  input  logic [DATA_W/8-1:0]   wr_strb,       // byte enables

  // Register-file read channel (driven by BFM)
  input  logic                  rd_en,         // read enable
  input  logic [ADDR_W-1:0]     rd_addr,       // word address
  output logic [DATA_W-1:0]     rd_data,       // read data (registered, valid next cycle)

  // Expected IP outputs (for scoreboard comparison)
  output logic                  irq,           // expected IRQ level
  output logic                  trigger_out,   // expected trigger pulse
  output logic                  hw_active,     // expected active flag
  output logic [DATA_W-1:0]     hw_count_val   // expected count value
);

  // -------------------------------------------------------------------------
  // Register address constants (word offsets)
  // -------------------------------------------------------------------------
  localparam logic [ADDR_W-1:0] ADDR_CTRL   = 4'h0;
  localparam logic [ADDR_W-1:0] ADDR_STATUS = 4'h1;
  localparam logic [ADDR_W-1:0] ADDR_LOAD   = 4'h2;
  localparam logic [ADDR_W-1:0] ADDR_COUNT  = 4'h3;

  // CTRL bit positions
  localparam int CTRL_EN_BIT       = 0;
  localparam int CTRL_MODE_BIT     = 1;
  localparam int CTRL_INTR_EN_BIT  = 2;
  localparam int CTRL_TRIG_EN_BIT  = 3;
  localparam int CTRL_PRESCALE_LSB = 4;

  // STATUS bit positions
  localparam int STATUS_INTR_BIT  = 0;
  localparam int STATUS_ACTIVE_BIT = 1;

  // -------------------------------------------------------------------------
  // Register storage
  // -------------------------------------------------------------------------
  logic [DATA_W-1:0] ctrl_q;
  logic [DATA_W-1:0] status_q;
  logic [DATA_W-1:0] load_q;

  // -------------------------------------------------------------------------
  // Core state
  // -------------------------------------------------------------------------
  logic [7:0]        prescale_cnt;
  logic [DATA_W-1:0] count;
  logic              active;
  logic              en_prev;

  // -------------------------------------------------------------------------
  // Helper: apply byte strobes to current value
  // -------------------------------------------------------------------------
  function automatic logic [DATA_W-1:0] apply_strb_fn(
    input logic [DATA_W-1:0] current,
    input logic [DATA_W-1:0] wdata,
    input logic [DATA_W/8-1:0] strb
  );
    logic [DATA_W-1:0] result;
    int b;
    result = current;
    for (b = 0; b < DATA_W / 8; b++) begin
      if (strb[b]) begin
        result[b*8 +: 8] = wdata[b*8 +: 8];
      end
    end
    return result;
  endfunction

  // -------------------------------------------------------------------------
  // Model clock process
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin : p_model
    if (!rst_n) begin
      ctrl_q       <= {DATA_W{1'b0}};
      status_q     <= {DATA_W{1'b0}};
      load_q       <= {DATA_W{1'b0}};
      count        <= {DATA_W{1'b0}};
      prescale_cnt <= 8'h00;
      active       <= 1'b0;
      en_prev      <= 1'b0;
      trigger_out  <= 1'b0;
      rd_data      <= {DATA_W{1'b0}};
    end else begin
      // -----------------------------------------------------------------------
      // Register writes
      // -----------------------------------------------------------------------
      if (wr_en) begin
        case (wr_addr)
          ADDR_CTRL: begin
            // Write only to defined fields [11:0]; reserved bits stay zero
            ctrl_q <= apply_strb_fn(ctrl_q, wr_data, wr_strb) & {{(DATA_W-12){1'b0}}, 12'hFFF};
          end
          ADDR_STATUS: begin
            // INTR is W1C: writing bit 0 set in wr_data clears it
            if (wr_strb[0] && wr_data[STATUS_INTR_BIT]) begin
              status_q[STATUS_INTR_BIT] <= 1'b0;
            end
            // ACTIVE is RO — ignore writes
          end
          ADDR_LOAD: begin
            load_q <= apply_strb_fn(load_q, wr_data, wr_strb);
          end
          // COUNT is RO — ignore writes
          default: begin
            // Decode error; ignore.
          end
        endcase
      end

      // -----------------------------------------------------------------------
      // Register read
      // -----------------------------------------------------------------------
      if (rd_en) begin
        case (rd_addr)
          ADDR_CTRL:   rd_data <= ctrl_q;
          ADDR_STATUS: rd_data <= status_q;
          ADDR_LOAD:   rd_data <= load_q;
          ADDR_COUNT:  rd_data <= count;
          default:     rd_data <= {DATA_W{1'b0}};
        endcase
      end

      // -----------------------------------------------------------------------
      // Core model: EN edge detect and prescaler
      // -----------------------------------------------------------------------
      en_prev <= ctrl_q[CTRL_EN_BIT];

      // Default: clear one-cycle outputs
      trigger_out             <= 1'b0;
      status_q[STATUS_INTR_BIT] <= status_q[STATUS_INTR_BIT]; // hold

      if (!ctrl_q[CTRL_EN_BIT]) begin
        // Timer disabled: reset prescaler, deactivate
        prescale_cnt <= ctrl_q[CTRL_PRESCALE_LSB +: 8];
        active       <= 1'b0;
      end else if (ctrl_q[CTRL_EN_BIT] && !en_prev) begin
        // Rising edge of EN: load counter
        count        <= load_q;
        active       <= 1'b1;
        prescale_cnt <= ctrl_q[CTRL_PRESCALE_LSB +: 8];
      end else if (active) begin
        // Prescaler advance
        if (prescale_cnt == 8'h00) begin
          prescale_cnt <= ctrl_q[CTRL_PRESCALE_LSB +: 8];
          // Counter tick
          if (count == {DATA_W{1'b0}}) begin
            // Underflow
            status_q[STATUS_INTR_BIT] <= 1'b1;
            if (ctrl_q[CTRL_TRIG_EN_BIT]) begin
              trigger_out <= 1'b1;
            end
            if (ctrl_q[CTRL_MODE_BIT]) begin
              // One-shot: stop
              active <= 1'b0;
              count  <= {DATA_W{1'b0}};
            end else begin
              // Repeat: reload
              count <= load_q;
            end
          end else begin
            count <= count - {{(DATA_W-1){1'b0}}, 1'b1};
          end
        end else begin
          prescale_cnt <= prescale_cnt - 8'h01;
        end
      end

      // ACTIVE status mirrors running state
      status_q[STATUS_ACTIVE_BIT] <= active;
      // Reserved bits in STATUS stay zero
      status_q[DATA_W-1:2] <= {(DATA_W-2){1'b0}};
    end
  end

  // -------------------------------------------------------------------------
  // Combinational outputs
  // -------------------------------------------------------------------------
  assign irq          = status_q[STATUS_INTR_BIT] & ctrl_q[CTRL_INTR_EN_BIT];
  assign hw_active    = active;
  assign hw_count_val = count;

endmodule : timer_model

`endif // SYNTHESIS
