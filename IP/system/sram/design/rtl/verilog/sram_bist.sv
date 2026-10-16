// sram_bist.sv — March C- built-in self-test engine for the sram IP.
//
// Algorithm (on the raw stored words, ECC bypassed; 0 = all zeros, 1 = all ones):
//   M0 up   (w0)
//   M1 up   (r0, w1)
//   M2 up   (r1, w0)
//   M3 down (r0, w1)
//   M4 down (r1, w0)
//   M5 up   (r0)
// A read element takes two cycles per word: read, then compare (the write of
// the same element is issued in the compare cycle). M0 takes one cycle per
// word. The array ends all-zero, so the previous contents are lost.
//
// Sequence: start_i (pulse) -> pending_o (core stalls the bus) -> once the
// bus port is idle the engine holds force_run_o (every domain is brought to
// RUN) until all_ok_i, runs the march (active_o), then pulses done_o. fail_o and
// fail_idx_o (first failing word) are valid from done_o until the next start.

module sram_bist #(
  parameter int unsigned DEPTH = 1024,  // words
  parameter int unsigned MW    = 32     // stored word width
) (
  input  logic                     clk,          // clock
  input  logic                     rst_n,        // synchronous active-low reset
  input  logic                     start_i,      // start a test (pulse)
  input  logic                     port_idle_i,  // bus port has nothing in flight
  input  logic                     all_ok_i,     // every domain accepts accesses
  output logic                     pending_o,    // requested or running: stall the bus
  output logic                     force_run_o,  // bring every domain to RUN
  output logic                     busy_o,       // test requested or running
  output logic                     active_o,     // march running (array in use)
  output logic                     done_o,       // test finished (pulse)
  output logic                     fail_o,       // a compare failed
  output logic [$clog2(DEPTH)-1:0] fail_idx_o,   // first failing word
  output logic                     cs_o,         // array access this cycle
  output logic                     we_o,         // 1 = write
  output logic [$clog2(DEPTH)-1:0] idx_o,        // word index
  output logic [MW-1:0]            wdata_o,      // pattern to write
  input  logic [MW-1:0]            rdata_i       // stored word (cycle after a read)
);

  localparam int unsigned IdxW = $clog2(DEPTH);
  localparam logic [IdxW-1:0] LastIdx = IdxW'(DEPTH - 1);

  typedef enum logic [2:0] {
    StIdle,     // nothing to do
    StWaitPort, // start requested: waiting for the bus port to drain
    StWaitPwr,  // all domains being brought to RUN
    StRead,     // read the current word
    StCheck,    // compare it, and write the element's value
    StWrite     // M0: write only
  } bist_state_e;

  bist_state_e     state_d, state_q;
  logic [2:0]      elem_d, elem_q;   // march element 0..5
  logic [IdxW-1:0] idx_d, idx_q;
  logic            fail_d, fail_q;
  logic [IdxW-1:0] fidx_d, fidx_q;
  logic            done;

  // Element properties.
  logic elem_down;   // descending addresses (M3, M4)
  logic exp_ones;    // value expected by the read (M2, M4)
  logic wr_ones;     // value written (M1, M3)
  logic elem_write;  // element has a write (all but M5)
  logic elem_end;    // current word is the last of the element

  assign elem_down  = (elem_q == 3'd3) || (elem_q == 3'd4);
  assign exp_ones   = (elem_q == 3'd2) || (elem_q == 3'd4);
  assign wr_ones    = (elem_q == 3'd1) || (elem_q == 3'd3);
  assign elem_write = (elem_q != 3'd5);
  assign elem_end   = elem_down ? (idx_q == '0) : (idx_q == LastIdx);

  // Next word of the element, or the first word of the next element.
  logic [IdxW-1:0] next_idx;
  logic [2:0]      next_elem;
  logic            next_down;
  always_comb begin : p_next
    next_elem = elem_q;
    next_down = elem_down;
    next_idx  = elem_down ? idx_q - IdxW'(1) : idx_q + IdxW'(1);
    if (elem_end) begin
      next_elem = elem_q + 3'd1;
      next_down = (next_elem == 3'd3) || (next_elem == 3'd4);
      next_idx  = next_down ? LastIdx : '0;
    end
  end

  always_comb begin : p_state_comb
    state_d = state_q;
    elem_d  = elem_q;
    idx_d   = idx_q;
    fail_d  = fail_q;
    fidx_d  = fidx_q;
    done    = 1'b0;
    cs_o    = 1'b0;
    we_o    = 1'b0;
    wdata_o = '0;
    unique case (state_q)
      // StIdle: wait for a start request.
      StIdle: begin
        if (start_i) begin
          fail_d  = 1'b0;
          fidx_d  = '0;
          state_d = StWaitPort;
        end
      end
      // StWaitPort: the core has stopped granting; wait for the port to drain.
      StWaitPort: begin
        if (port_idle_i) begin
          state_d = StWaitPwr;
        end
      end
      // StWaitPwr: force_run_o is high; wait until every domain is in RUN.
      StWaitPwr: begin
        if (all_ok_i) begin
          elem_d  = 3'd0;
          idx_d   = '0;
          state_d = StWrite;
        end
      end
      // StWrite: M0 — write zero to every word.
      StWrite: begin
        cs_o = 1'b1;
        we_o = 1'b1;
        if (elem_end) begin
          elem_d  = next_elem;
          idx_d   = next_idx;
          state_d = StRead;
        end else begin
          idx_d = next_idx;
        end
      end
      // StRead: read the current word.
      StRead: begin
        cs_o    = 1'b1;
        state_d = StCheck;
      end
      // StCheck: compare the word read last cycle; write the element value.
      StCheck: begin
        if (rdata_i != (exp_ones ? {MW{1'b1}} : {MW{1'b0}})) begin
          if (!fail_q) begin
            fidx_d = idx_q;
          end
          fail_d = 1'b1;
        end
        if (elem_write) begin
          cs_o    = 1'b1;
          we_o    = 1'b1;
          wdata_o = wr_ones ? {MW{1'b1}} : {MW{1'b0}};
        end
        if (elem_end && elem_q == 3'd5) begin
          done    = 1'b1;
          state_d = StIdle;
        end else begin
          elem_d  = next_elem;
          idx_d   = next_idx;
          state_d = StRead;
        end
      end
      default: state_d = StIdle;
    endcase
  end

  // State, element, word index and result registers.
  always_ff @(posedge clk) begin : p_state_reg
    if (!rst_n) begin
      state_q <= StIdle;
      elem_q  <= '0;
      idx_q   <= '0;
      fail_q  <= 1'b0;
      fidx_q  <= '0;
    end else begin
      state_q <= state_d;
      elem_q  <= elem_d;
      idx_q   <= idx_d;
      fail_q  <= fail_d;
      fidx_q  <= fidx_d;
    end
  end

  assign idx_o       = idx_q;
  assign pending_o   = (state_q != StIdle);
  assign force_run_o = (state_q != StIdle) && (state_q != StWaitPort);
  assign busy_o      = (state_q != StIdle);
  assign active_o    = (state_q == StWrite) || (state_q == StRead) || (state_q == StCheck);
  assign done_o      = done;
  assign fail_o      = fail_q;
  assign fail_idx_o  = fidx_q;

endmodule : sram_bist
