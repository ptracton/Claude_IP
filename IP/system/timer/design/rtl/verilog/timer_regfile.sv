// timer_regfile.sv - Timer IP synthesizable register file.
// Hand-maintained after initial generation; updated to add:
//   CTRL.RESTART (bit 12, self-clearing), CTRL.IRQ_MODE (bit 13),
//   CTRL.SNAPSHOT (bit 14, self-clearing), STATUS.OVF (bit 2, W1C),
//   CAPTURE register (0x10, RO), LOAD=0 protection pass-through.
// Single source of truth for layout: design/systemrdl/timer.rdl
//
// Interface (bus-agnostic, flat ports - no SV interface constructs):
//
//   Clock / reset:
//     clk       : input  - system clock (rising edge active)
//     rst_n     : input  - synchronous active-low reset
//
//   Write channel:
//     wr_en     : input  - write enable (pulse)
//     wr_addr   : input  [3:0]  - word address (byte_addr >> 2)
//     wr_data   : input  [31:0] - write data
//     wr_strb   : input  [3:0]  - byte write strobes
//
//   Read channel:
//     rd_en     : input  - read enable (pulse)
//     rd_addr   : input  [3:0]  - word address (byte_addr >> 2)
//     rd_data   : output [31:0] - read data (registered, valid next cycle)
//
//   Hardware update ports (driven by timer_core):
//     hw_count_val : input  [31:0] - current count value for COUNT register
//     hw_intr_set  : input         - set STATUS.INTR when asserted
//     hw_ovf_set   : input         - set STATUS.OVF when asserted
//     hw_active    : input         - reflects running state to STATUS.ACTIVE
//
//   Output to core:
//     ctrl_en       : output        - CTRL.EN field
//     ctrl_mode     : output        - CTRL.MODE field
//     ctrl_intr_en  : output        - CTRL.INTR_EN field
//     ctrl_trig_en  : output        - CTRL.TRIG_EN field
//     ctrl_prescale : output [7:0]  - CTRL.PRESCALE field
//     ctrl_restart  : output        - CTRL.RESTART self-clearing pulse
//     ctrl_irq_mode : output        - CTRL.IRQ_MODE field
//     load_val      : output [31:0] - LOAD.VALUE field
//     status_intr   : output        - STATUS.INTR bit (for IRQ masking in core)

module timer_regfile
  import timer_reg_pkg::*;
(
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
  input  logic        hw_ovf_set,
  input  logic        hw_active,

  // Output to timer_core
  output logic        ctrl_en,
  output logic        ctrl_mode,
  output logic        ctrl_intr_en,
  output logic        ctrl_trig_en,
  output logic [7:0]  ctrl_prescale,
  output logic        ctrl_restart,   // CTRL.RESTART self-clearing pulse (1 cycle)
  output logic        ctrl_irq_mode,  // CTRL.IRQ_MODE: 0=level, 1=pulse
  output logic [31:0] load_val,
  output logic        status_intr   // STATUS.INTR bit for IRQ masking
);

  // -----------------------------------------------------------------------
  // Internal register storage
  // -----------------------------------------------------------------------
  logic [31:0] ctrl_q;
  logic [31:0] status_q;
  logic [31:0] load_q;
  logic [31:0] count_q;    // mirror of hw_count_val, captured each cycle
  logic [31:0] capture_q;  // CAPTURE: latched snapshot of hw_count_val

  // -----------------------------------------------------------------------
  // Byte-enable merge helper: apply wr_strb to current register value
  // -----------------------------------------------------------------------
  function automatic logic [31:0] apply_strb(
    input logic [31:0] current,
    input logic [31:0] wdata,
    input logic [3:0]  strb
  );
    logic [31:0] result;
    result[7:0]   = strb[0] ? wdata[7:0]   : current[7:0];
    result[15:8]  = strb[1] ? wdata[15:8]  : current[15:8];
    result[23:16] = strb[2] ? wdata[23:16] : current[23:16];
    result[31:24] = strb[3] ? wdata[31:24] : current[31:24];
    return result;
  endfunction

  // -----------------------------------------------------------------------
  // CTRL register - RW, reset 0x0
  // Fields: EN[0], MODE[1], INTR_EN[2], TRIG_EN[3], PRESCALE[11:4],
  //         RESTART[12] (self-clearing), IRQ_MODE[13], SNAPSHOT[14] (self-clearing)
  // Reserved bits [31:15] always read as zero and ignore writes.
  // RESTART and SNAPSHOT auto-clear to 0 every cycle unless written.
  // -----------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      ctrl_q <= TIMER_CTRL_RESET;
    end else if (wr_en && (wr_addr == TIMER_CTRL_OFFSET)) begin
      // Capture write; mask reserved bits [31:15] to zero.
      // Self-clearing bits (RESTART[12], SNAPSHOT[14]) are held for 1 cycle.
      ctrl_q <= apply_strb(ctrl_q, wr_data, wr_strb) & 32'h0000_7FFF;
    end else begin
      // Auto-clear self-clearing command bits when not writing.
      ctrl_q[TIMER_CTRL_RESTART_BIT]  <= 1'b0;
      ctrl_q[TIMER_CTRL_SNAPSHOT_BIT] <= 1'b0;
    end
  end

  // -----------------------------------------------------------------------
  // STATUS register
  //   INTR  (bit 0) : W1C — set by hw_intr_set; cleared by writing 1.
  //   ACTIVE(bit 1) : RO  — driven by hw_active.
  //   OVF   (bit 2) : W1C — set when underflow fires while INTR is already 1;
  //                         cleared by writing 1.
  // -----------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      status_q <= TIMER_STATUS_RESET;
    end else begin
      // ACTIVE tracks hw_active directly.
      status_q[TIMER_STATUS_ACTIVE_BIT] <= hw_active;

      // INTR: set by hw_intr_set; cleared by W1C write.
      if (hw_intr_set) begin
        status_q[TIMER_STATUS_INTR_BIT] <= 1'b1;
      end else if (wr_en && (wr_addr == TIMER_STATUS_OFFSET) &&
                   wr_strb[0] && wr_data[TIMER_STATUS_INTR_BIT]) begin
        status_q[TIMER_STATUS_INTR_BIT] <= 1'b0;
      end

      // OVF: set by hw_ovf_set; cleared by W1C write.
      if (hw_ovf_set) begin
        status_q[TIMER_STATUS_OVF_BIT] <= 1'b1;
      end else if (wr_en && (wr_addr == TIMER_STATUS_OFFSET) &&
                   wr_strb[0] && wr_data[TIMER_STATUS_OVF_BIT]) begin
        status_q[TIMER_STATUS_OVF_BIT] <= 1'b0;
      end

      // Reserved bits stay zero
      status_q[31:3] <= 29'h0;
    end
  end

  // -----------------------------------------------------------------------
  // LOAD register - fully RW, reset 0x0
  // -----------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      load_q <= TIMER_LOAD_RESET;
    end else if (wr_en && (wr_addr == TIMER_LOAD_OFFSET)) begin
      load_q <= apply_strb(load_q, wr_data, wr_strb);
    end
  end

  // -----------------------------------------------------------------------
  // COUNT register - RO mirror of hw_count_val, updated every cycle
  // -----------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      count_q <= TIMER_COUNT_RESET;
    end else begin
      count_q <= hw_count_val;
    end
  end

  // -----------------------------------------------------------------------
  // CAPTURE register - RO; latched from hw_count_val when CTRL.SNAPSHOT fires.
  // hw_count_val is the combinational (live) counter value from timer_core.
  // -----------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      capture_q <= TIMER_CAPTURE_RESET;
    end else if (ctrl_q[TIMER_CTRL_SNAPSHOT_BIT]) begin
      capture_q <= hw_count_val;
    end
  end

  // -----------------------------------------------------------------------
  // Read path - registered (valid the cycle after rd_en)
  // -----------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rd_data <= 32'h0000_0000;
    end else if (rd_en) begin
      unique case (rd_addr)
        TIMER_CTRL_OFFSET:    rd_data <= ctrl_q;
        TIMER_STATUS_OFFSET:  rd_data <= status_q;
        TIMER_LOAD_OFFSET:    rd_data <= load_q;
        TIMER_COUNT_OFFSET:   rd_data <= count_q;
        TIMER_CAPTURE_OFFSET: rd_data <= capture_q;
        default:              rd_data <= 32'h0000_0000;
      endcase
    end
  end

  // -----------------------------------------------------------------------
  // Output assignments to timer_core
  // -----------------------------------------------------------------------
  assign ctrl_en       = ctrl_q[TIMER_CTRL_EN_BIT];
  assign ctrl_mode     = ctrl_q[TIMER_CTRL_MODE_BIT];
  assign ctrl_intr_en  = ctrl_q[TIMER_CTRL_INTR_EN_BIT];
  assign ctrl_trig_en  = ctrl_q[TIMER_CTRL_TRIG_EN_BIT];
  assign ctrl_prescale = ctrl_q[TIMER_CTRL_PRESCALE_LSB +: 8];
  assign ctrl_restart  = ctrl_q[TIMER_CTRL_RESTART_BIT];
  assign ctrl_irq_mode = ctrl_q[TIMER_CTRL_IRQ_MODE_BIT];
  assign load_val      = load_q;
  assign status_intr   = status_q[TIMER_STATUS_INTR_BIT];

endmodule : timer_regfile
