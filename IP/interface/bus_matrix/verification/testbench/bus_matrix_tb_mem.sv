// bus_matrix_tb_mem.sv — Testbench memory behind a shared claude_<proto>_if bridge.
//
// Implements the bridge's register-file side (wr_en/wr_addr/wr_data/wr_strb,
// rd_en/rd_addr/rd_data with registered read data) as a 2**ADDR_W-word RAM,
// so each bus matrix slave port is terminated by a protocol-compliant slave.
//
// For arbitration tests it records the word address of every write in order
// (wr_log[0..wr_count-1]); clear_log() restarts the record.

`timescale 1ns / 1ps

module bus_matrix_tb_mem #(
  parameter int unsigned ADDR_W = 10 // word-address width (2**ADDR_W words)
) (
  input  logic              clk,
  input  logic              wr_en,
  input  logic [ADDR_W-1:0] wr_addr,
  input  logic [31:0]       wr_data,
  input  logic [3:0]        wr_strb,
  input  logic              rd_en,
  input  logic [ADDR_W-1:0] rd_addr,
  output logic [31:0]       rd_data
);

  localparam int unsigned LOG_DEPTH = 64;

  logic [31:0]       mem [2**ADDR_W];
  logic [ADDR_W-1:0] wr_log [LOG_DEPTH];
  int unsigned       wr_count;

  initial begin
    for (int i = 0; i < 2**ADDR_W; i++) begin
      mem[i] = 32'h0000_0000;
    end
    rd_data  = 32'h0000_0000;
    wr_count = 0;
  end

  always @(posedge clk) begin
    if (wr_en) begin
      for (int b = 0; b < 4; b++) begin
        if (wr_strb[b]) begin
          mem[wr_addr][b*8+:8] <= wr_data[b*8+:8];
        end
      end
      if (wr_count < LOG_DEPTH) begin
        wr_log[wr_count] <= wr_addr;
      end
      wr_count <= wr_count + 1;
    end
    if (rd_en) begin
      rd_data <= mem[rd_addr];
    end
  end

  function automatic void clear_log();
    wr_count = 0;
  endfunction

endmodule : bus_matrix_tb_mem
