// claude_reg_fv.sv — Reusable, protocol-neutral register read-back checker.
//
// Consumes the transaction-observer outputs of any claude_<proto>_fv checker
// (obs_* ports) and checks ONE register word address. Instantiate once per
// register (or unmapped address) from an IP's register-map checker.
//
// A shadow model tracks what software last wrote to REG_ADDR (starting from
// RESET_VAL, with byte-strobes applied). When a read of REG_ADDR completes:
//   a_rw_readback   bits in RW_MASK   equal the shadow value
//   a_rsvd_zero     bits in ZERO_MASK read as zero
//   a_reset_value   (before any write) bits in RESET_MASK equal RESET_VAL
//
// RW_MASK must only contain bits that nothing but software writes (exclude
// hardware-updated, self-clearing and W1C bits). Hardware-owned fields are
// the IP's own responsibility (its register-map checker).
//
// A read is only checked when no write was in progress anywhere between the
// read being requested (obs_rd_req) and it completing (obs_rd_vld): the
// order of overlapping read/write accesses is protocol- and design-specific,
// so it is left out rather than guessed at. c_checked covers that the
// comparison is actually reachable.

module claude_reg_fv #(
  parameter int unsigned        DATA_W     = 32,
  parameter int unsigned        ADDR_W     = 4,
  parameter logic [ADDR_W-1:0]  REG_ADDR   = '0,  // word address checked
  parameter logic [DATA_W-1:0]  RESET_VAL  = '0,  // documented reset value
  parameter logic [DATA_W-1:0]  RESET_MASK = '0,  // bits whose reset value is checked
  parameter logic [DATA_W-1:0]  RW_MASK    = '0,  // software read/write bits
  parameter logic [DATA_W-1:0]  ZERO_MASK  = '0   // bits that always read 0
) (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  obs_wr_vld,
  input  logic [ADDR_W-1:0]     obs_wr_addr,
  input  logic [DATA_W-1:0]     obs_wr_data,
  input  logic [DATA_W/8-1:0]   obs_wr_strb,
  input  logic                  obs_wr_busy,
  input  logic                  obs_rd_req,
  input  logic                  obs_rd_vld,
  input  logic [ADDR_W-1:0]     obs_rd_addr,
  input  logic [DATA_W-1:0]     obs_rd_data
);

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  logic [DATA_W-1:0] shadow_q;    // last value written by software
  logic              written_q;   // at least one write since reset
  logic [DATA_W-1:0] snap_q;      // shadow value when the read was requested
  logic              snap_wr_q;   // written_q when the read was requested
  logic              rd_open_q;   // a read is outstanding
  logic              dirty_q;     // write activity overlapped the read
  logic              wr_now;
  logic              rd_same;     // read requested and completed this cycle
  logic              rd_done;     // the open read completes this cycle
  logic              chk;

  function automatic logic [DATA_W-1:0] merge(
    input logic [DATA_W-1:0]   cur,
    input logic [DATA_W-1:0]   wdata,
    input logic [DATA_W/8-1:0] strb
  );
    logic [DATA_W-1:0] res;
    for (int b = 0; b < DATA_W / 8; b++) begin
      res[8*b +: 8] = strb[b] ? wdata[8*b +: 8] : cur[8*b +: 8];
    end
    return res;
  endfunction

  assign wr_now = obs_wr_vld | obs_wr_busy;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      shadow_q  <= RESET_VAL;
      written_q <= 1'b0;
      snap_q    <= RESET_VAL;
      snap_wr_q <= 1'b0;
      rd_open_q <= 1'b0;
      dirty_q   <= 1'b0;
    end else begin
      if (obs_wr_vld && obs_wr_addr == REG_ADDR) begin
        shadow_q  <= merge(shadow_q, obs_wr_data, obs_wr_strb);
        written_q <= 1'b1;
      end
      if (obs_rd_req && !rd_same) begin
        snap_q    <= shadow_q;
        snap_wr_q <= written_q;
        rd_open_q <= 1'b1;
        dirty_q   <= wr_now;
      end else if (rd_done) begin
        rd_open_q <= 1'b0;
      end else if (rd_open_q && wr_now) begin
        dirty_q   <= 1'b1;
      end
    end
  end

  // A completing read is the open (older) one if there is one; otherwise it
  // was requested and completed in the same cycle. A pipelined protocol can
  // request the next read in the cycle the open one completes (AHB).
  assign rd_same = obs_rd_vld && obs_rd_req && !rd_open_q;
  assign rd_done = obs_rd_vld && rd_open_q;

  // Read completing this cycle with no write activity since it was requested.
  assign chk = (obs_rd_addr == REG_ADDR) && !wr_now &&
               (rd_same || (rd_done && !dirty_q));

  a_rw_readback: assert property (
    chk |-> ((obs_rd_data & RW_MASK) ==
             ((rd_same ? shadow_q : snap_q) & RW_MASK)));

  a_rsvd_zero: assert property (
    (obs_rd_vld && obs_rd_addr == REG_ADDR) |-> ((obs_rd_data & ZERO_MASK) == '0));

  a_reset_value: assert property (
    (chk && !(rd_same ? written_q : snap_wr_q)) |->
      ((obs_rd_data & RESET_MASK) == (RESET_VAL & RESET_MASK)));

  c_checked:  cover property (chk);
  c_written:  cover property (obs_wr_vld && obs_wr_addr == REG_ADDR);

endmodule : claude_reg_fv
