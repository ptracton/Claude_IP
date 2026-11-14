// sram_tb_apb_master.sv — APB4 master BFM of any data width.
//
// Used by tb_sram_apb.sv, one instance per master port. Same task API as
// sram_tb_ahb_master.sv (beat list in sram_tb_master_common.svh): load beats,
// run_beats(n), read bt_rdata / bt_err / last_cycles / last_wait.
// Each beat is one APB transfer (SETUP then ACCESS until PREADY); the next
// beat's SETUP follows the previous ACCESS directly. APB has no size
// signal: a write's PSTRB is the beat's strobes ANDed with the lanes of its
// size at its address; reads drive PSTRB = 0 and return the whole word. The
// BUSY count of a beat becomes idle cycles (PSEL low) before it.

`timescale 1ns / 1ps

module sram_tb_apb_master #(
  parameter int unsigned DW   = 32,      // data width
  parameter int unsigned AW   = 32,      // address width
  parameter int unsigned MAXB = 64,      // longest beat list
  parameter int unsigned TMO    = 50000    // cycles before a stuck transfer fails
) (
  input  logic            PCLK,
  output logic            PSEL,
  output logic            PENABLE,
  output logic [AW-1:0]   PADDR,
  output logic            PWRITE,
  output logic [DW-1:0]   PWDATA,
  output logic [DW/8-1:0] PSTRB,
  input  logic            PREADY,
  input  logic [DW-1:0]   PRDATA,
  input  logic            PSLVERR
);

  `include "sram_tb_master_common.svh"

  initial begin
    PSEL    = 1'b0;
    PENABLE = 1'b0;
    PADDR   = '0;
    PWRITE  = 1'b0;
    PWDATA  = '0;
    PSTRB   = '0;
  end

  task automatic run_beats(input int unsigned n);
    int unsigned w;
    last_cycles = 0;
    last_wait   = 0;
    @(posedge PCLK);
    `TB_DRV;
    for (int unsigned i = 0; i < n; i++) begin
      if (bt_busy[i] > 0) begin
        PSEL    <= 1'b0;
        PENABLE <= 1'b0;
        repeat (bt_busy[i]) begin
          @(posedge PCLK);
          last_cycles++;
        end
        `TB_DRV;
      end
      // SETUP
      PSEL    <= 1'b1;
      PENABLE <= 1'b0;
      PADDR   <= bt_addr[i];
      PWRITE  <= bt_we[i];
      PWDATA  <= bt_we[i] ? bt_wdata[i] : '0;
      PSTRB   <= bt_we[i] ? (bt_strb[i] & lane_mask(bt_size[i], bt_addr[i])) : '0;
      @(posedge PCLK);
      last_cycles++;
      `TB_DRV;
      // ACCESS until PREADY
      PENABLE <= 1'b1;
      w = 0;
      do begin
        @(posedge PCLK);
        last_cycles++;
        if (PREADY !== 1'b1) begin
          last_wait++;
          if (++w > TMO) begin
            $display("FAIL [%m] PREADY stuck low for %0d cycles at %0t", TMO, $time);
            $finish(1);
          end
        end
      end while (PREADY !== 1'b1);
      bt_rdata[i] = PRDATA;
      bt_err[i]   = (PSLVERR === 1'b1);
      `TB_DRV;
    end
    PSEL    <= 1'b0;
    PENABLE <= 1'b0;
  endtask

endmodule : sram_tb_apb_master
