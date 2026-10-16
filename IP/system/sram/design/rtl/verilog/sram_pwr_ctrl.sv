// sram_pwr_ctrl.sv — Power-mode state machine for one sram power domain.
//
// A domain is the whole array (BANK_PG = 0) or one bank (BANK_PG = 1).
// Target mode = RUN while wake_i is high (an access or engine needs the
// domain, only raised for RUN/LS requests), else mode_req_i.
//
//   StRun   ── target != RUN and idle_i ──► StEnter (pins on, ENTER cycles)
//   StEnter ── count done ────────────────► StSleep (ack = mode)
//   StSleep ── target != mode ────────────► StWake  (pins off, wake cycles)
//   StWake  ── count done, mode was SD ───► StClear (clr_req_o until clr_done_i)
//           ── count done, otherwise ─────► StRun   (ack = RUN)
//   StClear ── clr_done_i ────────────────► StRun   (ack = RUN)
//
// A move between two sleep modes goes through StWake (and StRun). idle_i
// (no access to the domain this cycle or in flight) gates only StRun ->
// StEnter, so an access in progress always completes with the pins off.
// With PWR_GATE = 0 the domain is permanently in RUN.

module sram_pwr_ctrl #(
  parameter bit          PWR_GATE  = 1,   // power modes enabled
  parameter int unsigned ENTER_CYC = 2,   // pins-on to mode reached
  parameter int unsigned WAKE_LS   = 2,   // wake time from light sleep
  parameter int unsigned WAKE_DS   = 4,   // wake time from deep sleep
  parameter int unsigned WAKE_SD   = 8    // wake time from shutdown
) (
  input  logic       clk,          // clock
  input  logic       rst_n,        // synchronous active-low reset
  input  logic [1:0] mode_req_i,   // requested mode (sram_pkg::PWR_*)
  input  logic       wake_i,       // keep / bring the domain to RUN
  input  logic       idle_i,       // no access to this domain in flight
  input  logic       clr_done_i,   // clear engine finished this domain
  output logic       ls_o,         // light-sleep pin
  output logic       ds_o,         // deep-sleep pin
  output logic       sd_o,         // shutdown pin
  output logic       awake_o,      // RUN: bus accesses allowed
  output logic       engine_ok_o,  // RUN or clearing: engine accesses allowed
  output logic       clr_req_o,    // contents lost: please clear this domain
  output logic       busy_o,       // mode transition in progress
  output logic [1:0] ack_o         // mode in effect
);

  localparam int unsigned CntW = 5;  // counts up to 31 cycles

  if (PWR_GATE) begin : g_pwr

    typedef enum logic [2:0] {
      StRun,
      StEnter,
      StSleep,
      StWake,
      StClear
    } pwr_state_e;

    pwr_state_e      state_d, state_q;
    logic [1:0]      mode_d, mode_q;   // sleep mode entered / being left
    logic [1:0]      ack_d, ack_q;
    logic [CntW-1:0] cnt_d, cnt_q;
    logic [1:0]      target;

    assign target = wake_i ? sram_pkg::PWR_RUN : mode_req_i;

    function automatic logic [CntW-1:0] wake_count(logic [1:0] mode);
      logic [CntW-1:0] c;
      unique case (mode)
        sram_pkg::PWR_LS: c = CntW'(WAKE_LS);
        sram_pkg::PWR_DS: c = CntW'(WAKE_DS);
        sram_pkg::PWR_SD: c = CntW'(WAKE_SD);
        default:          c = CntW'(1);
      endcase
      return c;
    endfunction

    always_comb begin : p_state_comb
      state_d = state_q;
      mode_d  = mode_q;
      ack_d   = ack_q;
      cnt_d   = (cnt_q != '0) ? cnt_q - CntW'(1) : cnt_q;
      unique case (state_q)
        // StRun: full operation; enter a sleep mode once the domain is idle.
        StRun: begin
          if (target != sram_pkg::PWR_RUN && idle_i) begin
            mode_d  = target;
            cnt_d   = CntW'(ENTER_CYC);
            state_d = StEnter;
          end
        end
        // StEnter: pins asserted, waiting for the macro to reach the mode.
        StEnter: begin
          if (cnt_q == '0) begin
            ack_d   = mode_q;
            state_d = StSleep;
          end
        end
        // StSleep: in the mode; leave it when the target changes.
        StSleep: begin
          if (target != mode_q) begin
            cnt_d   = wake_count(mode_q);
            state_d = StWake;
          end
        end
        // StWake: pins released, waiting for the wake-up time.
        StWake: begin
          if (cnt_q == '0) begin
            if (mode_q == sram_pkg::PWR_SD) begin
              state_d = StClear;
            end else begin
              ack_d   = sram_pkg::PWR_RUN;
              state_d = StRun;
            end
          end
        end
        // StClear: contents were lost in shutdown; wait for the clear engine.
        StClear: begin
          if (clr_done_i) begin
            ack_d   = sram_pkg::PWR_RUN;
            state_d = StRun;
          end
        end
        default: state_d = StRun;
      endcase
    end

    // State, mode, acknowledge and counter registers.
    always_ff @(posedge clk) begin : p_state_reg
      if (!rst_n) begin
        state_q <= StRun;
        mode_q  <= sram_pkg::PWR_RUN;
        ack_q   <= sram_pkg::PWR_RUN;
        cnt_q   <= '0;
      end else begin
        state_q <= state_d;
        mode_q  <= mode_d;
        ack_q   <= ack_d;
        cnt_q   <= cnt_d;
      end
    end

    logic pins_on;
    assign pins_on = (state_q == StEnter) || (state_q == StSleep);

    assign ls_o        = pins_on && (mode_q == sram_pkg::PWR_LS);
    assign ds_o        = pins_on && (mode_q == sram_pkg::PWR_DS);
    assign sd_o        = pins_on && (mode_q == sram_pkg::PWR_SD);
    assign awake_o     = (state_q == StRun);
    assign engine_ok_o = (state_q == StRun) || (state_q == StClear);
    assign clr_req_o   = (state_q == StClear);
    assign busy_o      = (state_q == StEnter) || (state_q == StWake) || (state_q == StClear);
    assign ack_o       = ack_q;

  end else begin : g_no_pwr

    // Power modes disabled: always running.
    // Inputs other than the clock-domain basics are not needed.
    assign ls_o        = 1'b0;
    assign ds_o        = 1'b0;
    assign sd_o        = 1'b0;
    assign awake_o     = 1'b1;
    assign engine_ok_o = 1'b1;
    assign clr_req_o   = 1'b0;
    assign busy_o      = 1'b0;
    assign ack_o       = sram_pkg::PWR_RUN;

  end

endmodule : sram_pwr_ctrl
