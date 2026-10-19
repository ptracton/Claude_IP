// sram_tb_axi4l_master.sv — AXI4-Lite master BFM of any data width.
//
// Used by tb_sram_axi4l.sv, one instance per master port. Same task API as
// sram_tb_ahb_master.sv (beat list in sram_tb_master_common.svh): load beats,
// run_beats(n), read bt_rdata / bt_err / last_cycles / last_wait.
// One transaction at a time: a write raises AWVALID and WVALID together
// (each drops on its own handshake) and ends with the B response; a read
// raises ARVALID and ends with the R beat. BREADY / RREADY are always high.
// AXI4-Lite has no size signal: a write's WSTRB is the beat's strobes ANDed
// with the lanes of its size at its address; reads return the whole word.
// Any response other than OKAY is an error. The BUSY count of a beat becomes
// idle cycles before it.

`timescale 1ns / 1ps

module sram_tb_axi4l_master #(
  parameter int unsigned DW   = 32,      // data width
  parameter int unsigned AW   = 32,      // address width
  parameter int unsigned MAXB = 64,      // longest beat list
  parameter int unsigned TMO    = 50000    // cycles before a stuck transfer fails
) (
  input  logic            ACLK,
  output logic            AWVALID,
  input  logic            AWREADY,
  output logic [AW-1:0]   AWADDR,
  output logic            WVALID,
  input  logic            WREADY,
  output logic [DW-1:0]   WDATA,
  output logic [DW/8-1:0] WSTRB,
  input  logic            BVALID,
  output logic            BREADY,
  input  logic [1:0]      BRESP,
  output logic            ARVALID,
  input  logic            ARREADY,
  output logic [AW-1:0]   ARADDR,
  input  logic            RVALID,
  output logic            RREADY,
  input  logic [DW-1:0]   RDATA,
  input  logic [1:0]      RRESP
);

  `include "sram_tb_master_common.svh"

  initial begin
    AWVALID = 1'b0;
    AWADDR  = '0;
    WVALID  = 1'b0;
    WDATA   = '0;
    WSTRB   = '0;
    BREADY  = 1'b1;
    ARVALID = 1'b0;
    ARADDR  = '0;
    RREADY  = 1'b1;
  end

  task automatic run_beats(input int unsigned n);
    bit          aw_done, w_done, ar_done;
    int unsigned w;
    last_cycles = 0;
    last_wait   = 0;
    @(posedge ACLK);
    for (int unsigned i = 0; i < n; i++) begin
      repeat (bt_busy[i]) begin
        @(posedge ACLK);
        last_cycles++;
      end
      w = 0;
      if (bt_we[i]) begin
        AWVALID <= 1'b1;
        AWADDR  <= bt_addr[i];
        WVALID  <= 1'b1;
        WDATA   <= bt_wdata[i];
        WSTRB   <= bt_strb[i] & lane_mask(bt_size[i], bt_addr[i]);
        aw_done = 1'b0;
        w_done  = 1'b0;
        forever begin
          @(posedge ACLK);
          last_cycles++;
          if (!aw_done && AWREADY === 1'b1) begin
            aw_done = 1'b1;
            AWVALID <= 1'b0;
          end
          if (!w_done && WREADY === 1'b1) begin
            w_done = 1'b1;
            WVALID <= 1'b0;
          end
          if (BVALID === 1'b1) begin
            bt_err[i]   = (BRESP !== 2'b00);
            bt_rdata[i] = '0;
            break;
          end
          last_wait++;
          if (++w > TMO) begin
            $display("FAIL [%m] write stuck for %0d cycles at %0t", TMO, $time);
            $finish(1);
          end
        end
      end else begin
        ARVALID <= 1'b1;
        ARADDR  <= bt_addr[i];
        ar_done = 1'b0;
        forever begin
          @(posedge ACLK);
          last_cycles++;
          if (!ar_done && ARREADY === 1'b1) begin
            ar_done = 1'b1;
            ARVALID <= 1'b0;
          end
          if (RVALID === 1'b1) begin
            bt_err[i]   = (RRESP !== 2'b00);
            bt_rdata[i] = RDATA;
            break;
          end
          last_wait++;
          if (++w > TMO) begin
            $display("FAIL [%m] read stuck for %0d cycles at %0t", TMO, $time);
            $finish(1);
          end
        end
      end
    end
  endtask

endmodule : sram_tb_axi4l_master
