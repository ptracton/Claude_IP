// sram_tb_wb_master.sv — Wishbone B4 classic master BFM of any data width.
//
// Used by tb_sram_wb.sv, one instance per master port. Same task API as
// sram_tb_ahb_master.sv (beat list in sram_tb_master_common.svh): load beats,
// run_beats(n), read bt_rdata / bt_err / last_cycles / last_wait.
// CYC_O stays high for the whole beat list; each beat holds STB_O until ACK_I
// or ERR_I, and the next beat is presented at that same edge (classic
// back-to-back cycles). SEL_O is the lanes of the beat's size at its address
// (ANDed with the beat's strobes on writes). The BUSY count of a beat becomes
// wait cycles (STB_O low, CYC_O high) before it.

`timescale 1ns / 1ps

module sram_tb_wb_master #(
  parameter int unsigned DW   = 32,      // data width
  parameter int unsigned AW   = 32,      // address width
  parameter int unsigned MAXB = 64,      // longest beat list
  parameter int unsigned TMO    = 50000    // cycles before a stuck transfer fails
) (
  input  logic            CLK_I,
  output logic            CYC_O,
  output logic            STB_O,
  output logic            WE_O,
  output logic [AW-1:0]   ADR_O,
  output logic [DW-1:0]   DAT_O,
  output logic [DW/8-1:0] SEL_O,
  input  logic [DW-1:0]   DAT_I,
  input  logic            ACK_I,
  input  logic            ERR_I
);

  `include "sram_tb_master_common.svh"

  initial begin
    CYC_O = 1'b0;
    STB_O = 1'b0;
    WE_O  = 1'b0;
    ADR_O = '0;
    DAT_O = '0;
    SEL_O = '0;
  end

  task automatic run_beats(input int unsigned n);
    int unsigned w;
    last_cycles = 0;
    last_wait   = 0;
    @(posedge CLK_I);
    CYC_O <= 1'b1;
    for (int unsigned i = 0; i < n; i++) begin
      if (bt_busy[i] > 0) begin
        STB_O <= 1'b0;
        repeat (bt_busy[i]) begin
          @(posedge CLK_I);
          last_cycles++;
        end
      end
      STB_O <= 1'b1;
      WE_O  <= bt_we[i];
      ADR_O <= bt_addr[i];
      DAT_O <= bt_we[i] ? bt_wdata[i] : '0;
      SEL_O <= lane_mask(bt_size[i], bt_addr[i]) & (bt_we[i] ? bt_strb[i] : '1);
      w = 0;
      do begin
        @(posedge CLK_I);
        last_cycles++;
        if (ACK_I !== 1'b1 && ERR_I !== 1'b1) begin
          last_wait++;
          if (++w > TMO) begin
            $display("FAIL [%m] no ACK/ERR for %0d cycles at %0t", TMO, $time);
            $finish(1);
          end
        end
      end while (ACK_I !== 1'b1 && ERR_I !== 1'b1);
      bt_rdata[i] = DAT_I;
      bt_err[i]   = (ERR_I === 1'b1);
    end
    STB_O <= 1'b0;
    CYC_O <= 1'b0;
    WE_O  <= 1'b0;
  endtask

endmodule : sram_tb_wb_master
