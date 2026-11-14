// sram_pwr_fv.sv — VC Formal checker for sram_pwr_ctrl (one power domain).
//
// Bound into every sram_pwr_ctrl by sram_fv_block_binds.svh; ports only, so
// it serves the SV module and the VHDL entity. The timing parameters are the
// TECH_GENERIC values (sram_pkg::pwr_enter_cycles / pwr_wake_cycles), passed
// as literals from sram_fv_cfg.svh.
//
//   p_one_pin        at most one sleep pin
//   p_awake_no_pins  awake (bus accesses allowed) only with every pin off
//   p_awake_run      awake only while the acknowledged mode is RUN
//   p_pins_no_engine no engine access (engine_ok) while a pin is on
//   p_enter_*        a pin rises only from an idle domain that is not being
//                    woken, in the requested mode
//   p_enter_time_*   the mode is acknowledged no earlier than ENTER cycles
//                    after its pin rose
//   p_wake_time_*    the domain is awake no earlier than the mode's wake
//                    time after its pin fell
//   p_ack_*          a sleep mode is acknowledged only with its pin on, and
//                    the acknowledge moves between RUN and one sleep mode
//   p_sd_clear       shutdown returns to RUN only after the clear finished

module sram_pwr_fv #(
  parameter bit          PWR_GATE  = 1,
  parameter int unsigned ENTER_CYC = 2,
  parameter int unsigned WAKE_LS   = 2,
  parameter int unsigned WAKE_DS   = 4,
  parameter int unsigned WAKE_SD   = 8
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic [1:0] mode_req_i,
  input  logic       wake_i,
  input  logic       idle_i,
  input  logic       clr_done_i,
  input  logic       ls_o,
  input  logic       ds_o,
  input  logic       sd_o,
  input  logic       awake_o,
  input  logic       engine_ok_o,
  input  logic       clr_req_o,
  input  logic       busy_o,
  input  logic [1:0] ack_o
);

  localparam logic [1:0] RUN = 2'd0, LS = 2'd1, DS = 2'd2, SD = 2'd3;

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  logic pins;
  assign pins = ls_o || ds_o || sd_o;

  if (PWR_GATE) begin : g_pwr
    p_one_pin:        assert property ($onehot0({ls_o, ds_o, sd_o}));
    p_awake_no_pins:  assert property (awake_o |-> !pins);
    p_awake_run:      assert property (awake_o |-> ack_o == RUN);
    p_pins_no_engine: assert property (pins |-> !engine_ok_o);

    p_enter_ls: assert property ($rose(ls_o) |-> $past(idle_i && !wake_i && mode_req_i == LS));
    p_enter_ds: assert property ($rose(ds_o) |-> $past(idle_i && !wake_i && mode_req_i == DS));
    p_enter_sd: assert property ($rose(sd_o) |-> $past(idle_i && !wake_i && mode_req_i == SD));

    p_enter_time_ls: assert property ($rose(ls_o) |-> (ack_o != LS) [*ENTER_CYC]);
    p_enter_time_ds: assert property ($rose(ds_o) |-> (ack_o != DS) [*ENTER_CYC]);
    p_enter_time_sd: assert property ($rose(sd_o) |-> (ack_o != SD) [*ENTER_CYC]);

    p_wake_time_ls: assert property ($fell(ls_o) |-> !awake_o [*WAKE_LS]);
    p_wake_time_ds: assert property ($fell(ds_o) |-> !awake_o [*WAKE_DS]);
    p_wake_time_sd: assert property ($fell(sd_o) |-> !awake_o [*WAKE_SD]);

    p_ack_ls:   assert property (($changed(ack_o) && ack_o == LS) |-> ls_o);
    p_ack_ds:   assert property (($changed(ack_o) && ack_o == DS) |-> ds_o);
    p_ack_sd:   assert property (($changed(ack_o) && ack_o == SD) |-> sd_o);
    p_ack_step: assert property ($changed(ack_o) |-> (ack_o == RUN || $past(ack_o) == RUN));
    p_sd_clear: assert property (($past(ack_o) == SD && ack_o == RUN) |-> $past(clr_done_i));

    c_ls:       cover property (ack_o == LS);
    c_ds:       cover property (ack_o == DS);
    c_sd:       cover property (ack_o == SD);
    c_sd_clear: cover property ($past(ack_o) == SD && ack_o == RUN);
    c_wake_ls:  cover property ($past(ack_o) == LS && ack_o == RUN && $past(wake_i, 2));
  end else begin : g_no_pwr
    p_always_run: assert property (awake_o && engine_ok_o && !pins && ack_o == RUN);
  end

endmodule : sram_pwr_fv
