// sram_tb_master_common.svh — Beat list and helpers shared by the sram
// testbench master BFMs (sram_tb_<proto>_master.sv).
//
// `include inside a BFM module that has parameters DW, AW and MAXB. The BFM
// supplies run_beats(n), which issues beats
// 0..n-1 on its bus and fills bt_rdata / bt_err / last_cycles / last_wait.
// Beat fields every protocol understands: direction, address, size (2**size
// bytes; buses without a size signal turn it into byte strobes / selects
// with lane_mask), write data and strobes, BUSY cycles before the beat (idle
// cycles on buses without BUSY). HTRANS / HBURST are used by AHB only.

  localparam logic [1:0] IDLE = 2'b00, BUSY = 2'b01, NONSEQ = 2'b10, SEQ = 2'b11;

  // HBURST encodings
  localparam logic [2:0] B_SINGLE = 3'd0, B_INCR = 3'd1, B_WRAP4 = 3'd2, B_INCR4 = 3'd3,
                         B_WRAP8 = 3'd4, B_INCR8 = 3'd5, B_WRAP16 = 3'd6, B_INCR16 = 3'd7;

  localparam int unsigned StrbW = DW / 8;
  localparam int unsigned OffW  = (StrbW > 1) ? $clog2(StrbW) : 0;

  // Beat list
  logic            bt_we    [MAXB];
  logic [AW-1:0]   bt_addr  [MAXB];
  logic [2:0]      bt_size  [MAXB];
  logic [1:0]      bt_trans [MAXB];
  logic [2:0]      bt_burst [MAXB];
  int unsigned     bt_busy  [MAXB];   // BUSY cycles before this beat
  logic [DW-1:0]   bt_wdata [MAXB];
  logic [DW/8-1:0] bt_strb  [MAXB];
  logic [DW-1:0]   bt_rdata [MAXB];
  logic            bt_err   [MAXB];

  int unsigned last_cycles;
  int unsigned last_wait;

  // Pipelined mode: the AXI4-Lite BFM keeps several transactions in flight
  // (see sram_tb_axi4l_master.sv). The other BFMs ignore it.
  bit          pipelined = 1'b0;

  task automatic set_pipelined(input bit on);
    pipelined = on;
  endtask


  // lane_mask — byte lanes of a 2**size-byte transfer at addr (the naturally
  // aligned block holding the address; a full word or more: every lane).
  function automatic logic [DW/8-1:0] lane_mask(input logic [2:0] size, input logic [AW-1:0] addr);
    logic [DW/8-1:0] m;
    int unsigned     o;
    o = (OffW > 0) ? (addr & ((1 << OffW) - 1)) : 0;
    for (int unsigned b = 0; b < StrbW; b++) m[b] = ((b >> size) == (o >> size));
    return m;
  endfunction

  // ---------------------------------------------------------------------------
  // Beat-list helpers
  // ---------------------------------------------------------------------------
  // set_beat — fill entry i.
  task automatic set_beat(input int unsigned i, input logic we, input logic [AW-1:0] addr,
                          input logic [2:0] size, input logic [1:0] trans,
                          input logic [2:0] burst, input logic [DW-1:0] wdata,
                          input logic [DW/8-1:0] strb, input int unsigned busy = 0);
    bt_we[i]    = we;
    bt_addr[i]  = addr;
    bt_size[i]  = size;
    bt_trans[i] = trans;
    bt_burst[i] = burst;
    bt_wdata[i] = wdata;
    bt_strb[i]  = strb;
    bt_busy[i]  = busy;
    bt_rdata[i] = 'x;
    bt_err[i]   = 1'bx;
  endtask

  // single — one transfer; returns read data and the response.
  task automatic single(input logic we, input logic [AW-1:0] addr, input logic [2:0] size,
                        input logic [DW-1:0] wdata, input logic [DW/8-1:0] strb,
                        output logic [DW-1:0] rdata, output logic err);
    set_beat(0, we, addr, size, NONSEQ, B_SINGLE, wdata, strb);
    run_beats(1);
    rdata = bt_rdata[0];
    err   = bt_err[0];
  endtask

  // burst_addr — address of beat i of a burst of `beats` transfers of
  // 2**size bytes starting at addr; WRAP bursts wrap at beats * 2**size.
  function automatic logic [AW-1:0] burst_addr(input logic [AW-1:0] addr, input logic [2:0] size,
                                               input bit wrap, input int unsigned beats,
                                               input int unsigned i);
    logic [AW-1:0] span, base;
    if (!wrap) return addr + (AW'(i) << size);
    span = AW'(beats) << size;
    base = addr & ~(span - 1);
    return base | ((addr + (AW'(i) << size)) & (span - 1));
  endfunction

  // load_burst — beats 0..beats-1 of a burst (data/strobes are set by the
  // caller in bt_wdata / bt_strb afterwards, or left as given here).
  //   kind: B_INCR (undefined length), B_INCR4/8/16, B_WRAP4/8/16
  //   busy_mask: bit i set = one BUSY cycle before beat i (i >= 1)
  task automatic load_burst(input logic we, input logic [AW-1:0] addr, input logic [2:0] size,
                            input logic [2:0] kind, input int unsigned beats,
                            input logic [MAXB-1:0] busy_mask = '0);
    bit wrap;
    wrap = (kind == B_WRAP4) || (kind == B_WRAP8) || (kind == B_WRAP16);
    for (int unsigned i = 0; i < beats; i++) begin
      set_beat(i, we, burst_addr(addr, size, wrap, beats, i), size, (i == 0) ? NONSEQ : SEQ,
               kind, '0, '1, (i > 0 && busy_mask[i]) ? 1 : 0);
    end
  endtask

