// sram_array.sv — Splits the array into NUM_BANKS banks (and, for a dual
// port with different widths, R slices per bank).
//
// Banks: the top index bits select one of NUM_BANKS banks, each with its own
// sleep pins (the power domains of BANK_PG). Inside a bank, the technology
// wrapper tiles its primitives into rows and columns (sram_macro_<tech>).
//
// Single port: each bank is one sram_macro of MW x DEPTH / NUM_BANKS.
//
// DUAL_PORT: ports A (MW x DEPTH, clock clk) and B (MW_B x DEPTH_B, clock
// b_clk) see the same storage, MW x DEPTH == MW_B x DEPTH_B, with the ratio
// R = wide / narrow a power of two. Narrow word j is bits
// [(j % R) * SW +: SW] of wide word j / R (little-endian, SW = narrow
// stored width). Each bank holds R slices, each one sram_macro_dp of
// SW x (wide depth / NUM_BANKS):
//   wide port    same address to every slice; slice s carries its bits
//                [s * SW +: SW]
//   narrow port  slice = low index bits, slice address = the rest; only that
//                slice is selected, and a registered slice select (on the
//                narrow port's clock) drives its read multiplexer
// With R = 1 there is one slice and both ports are the same width.
// Macro port a is always port A and macro port b port B (SKY130: port B is
// the read-only macro port).
//
// Write lanes: lane_we_i / b_lane_we_i split each port's stored word into
// NLANES / NLANES_B equal lanes. A slice uses SL = max(lanes per slice of
// the two ports) lanes; a port with one lane per slice drives all SL.
//
// Read: each port's rdata is valid in the cycle after its read and comes
// from the bank (and slice) it read, remembered on its own clock.

module sram_array #(
  parameter int unsigned TECH       = sram_pkg::TECH_GENERIC, // technology
  parameter int unsigned MW         = 32,    // port A stored word width (data + ECC)
  parameter int unsigned DEPTH      = 1024,  // port A words
  parameter int unsigned NUM_BANKS  = 1,     // banks (power domains)
  parameter int unsigned NLANES     = 4,     // port A write lanes
  parameter bit          DUAL_PORT  = 0,     // second port (b_*)
  parameter int unsigned MW_B       = MW,    // port B stored word width
  parameter int unsigned DEPTH_B    = DEPTH, // port B words
  parameter int unsigned NLANES_B   = NLANES,// port B write lanes
  parameter bit          COMMON_CLK = 1,     // b_clk is clk
  parameter string       INIT_FILE  = ""     // preload (GENERIC/FPGA, NUM_BANKS = 1, R = 1)
) (
  input  logic                       clk,        // port A clock
  input  logic                       cs_i,       // access this cycle
  input  logic                       we_i,       // 1 = write, 0 = read
  input  logic [$clog2(DEPTH)-1:0]   idx_i,      // word index
  input  logic [MW-1:0]              wdata_i,    // stored word to write
  input  logic [NLANES-1:0]          lane_we_i,  // lanes to write
  input  logic [NUM_BANKS-1:0]       ls_i,       // light sleep, per bank
  input  logic [NUM_BANKS-1:0]       ds_i,       // deep sleep, per bank
  input  logic [NUM_BANKS-1:0]       sd_i,       // shutdown, per bank
  output logic [MW-1:0]              rdata_o,    // stored word (cycle after a read)

  // Port B (DUAL_PORT; tie inputs to 0 otherwise)
  input  logic                       b_clk,      // port B clock
  input  logic                       b_cs_i,     // access this cycle
  input  logic                       b_we_i,     // 1 = write
  input  logic [$clog2(DEPTH_B)-1:0] b_idx_i,    // word index
  input  logic [MW_B-1:0]            b_wdata_i,  // stored word to write
  input  logic [NLANES_B-1:0]        b_lane_we_i,// lanes to write
  output logic [MW_B-1:0]            b_rdata_o   // stored word (cycle after a read)
);

  localparam bit          AWide   = !DUAL_PORT || (MW >= MW_B);  // A is the wide port
  localparam int unsigned R       = !DUAL_PORT ? 1 : AWide ? MW / MW_B : MW_B / MW;
  localparam int unsigned RSh     = (R > 1) ? $clog2(R) : 0;
  localparam int unsigned SW      = AWide ? (DUAL_PORT ? MW_B : MW) : MW;  // slice width
  localparam int unsigned SD      = (AWide ? DEPTH : DEPTH_B) / NUM_BANKS; // slice words
  localparam bit          ASliced = DUAL_PORT && !AWide && (R > 1);       // A narrow
  localparam bit          BSliced = DUAL_PORT && AWide && (R > 1);        // B narrow
  localparam int unsigned BankAwA = $clog2(DEPTH / NUM_BANKS);  // >= 1 (sram_core checks)
  localparam int unsigned BankAwB = $clog2(DEPTH_B / NUM_BANKS);
  localparam int unsigned SAw     = $clog2(SD);
  localparam int unsigned BankW   = (NUM_BANKS > 1) ? $clog2(NUM_BANKS) : 1;
  localparam int unsigned SlW     = (R > 1) ? RSh : 1;
  // Lanes per slice: the wide port's lanes divide over the R slices.
  localparam int unsigned LpsA    = ASliced ? NLANES : (NLANES >= R ? NLANES / R : 1);
  localparam int unsigned LpsB    = BSliced ? NLANES_B : (NLANES_B >= R ? NLANES_B / R : 1);
  localparam int unsigned SL      = !DUAL_PORT ? NLANES : (LpsA > LpsB ? LpsA : LpsB);

  // synopsys translate_off
  initial begin : p_param_check
    if (DUAL_PORT) begin
      if (MW * DEPTH != MW_B * DEPTH_B)
        $fatal(1, "sram_array: ports A and B must have the same capacity");
      if ((R & (R - 1)) != 0)
        $fatal(1, "sram_array: width ratio %0d is not a power of two", R);
      if ((LpsA != SL && LpsA != 1) || (LpsB != SL && LpsB != 1))
        $fatal(1, "sram_array: lanes per slice %0d / %0d do not match", LpsA, LpsB);
    end
  end
  // synopsys translate_on

  // Expand one port's lanes for slice s to the slice's SL lanes.
  function automatic logic [SL-1:0] slice_lanes(logic [63:0] lanes, int unsigned nl,
                                                bit sliced, int unsigned lps,
                                                int unsigned s);
    logic [SL-1:0] l;
    for (int unsigned i = 0; i < SL; i++) begin
      if (sliced) l[i] = (lps == SL) ? lanes[i] : lanes[0];
      else if (nl >= R) l[i] = (lps == SL) ? lanes[s * lps + i] : lanes[s * lps];
      else l[i] = lanes[0];
    end
    return l;
  endfunction

  // -------------------------------------------------------------------------
  // Port A decode and read multiplexer (clk)
  // -------------------------------------------------------------------------
  logic [BankW-1:0]  a_bank, a_rd_bank_q;    // bank addressed / read last
  logic [SlW-1:0]    a_slice, a_rd_slice_q;  // slice (A narrow only)
  logic [SAw-1:0]    a_saddr;                // word address in the slice
  logic [MW-1:0]     a_bank_rdata [NUM_BANKS];

  if (NUM_BANKS > 1) begin : g_a_bank
    assign a_bank = BankW'(idx_i >> BankAwA);
  end else begin : g_a_one_bank
    assign a_bank = '0;
  end

  if (ASliced) begin : g_a_slice
    assign a_slice = SlW'(idx_i[BankAwA-1:0]);
    assign a_saddr = SAw'(idx_i[BankAwA-1:0] >> RSh);
  end else begin : g_a_whole
    assign a_slice = '0;
    assign a_saddr = SAw'(idx_i[BankAwA-1:0]);
  end

  always_ff @(posedge clk) begin : p_a_rd_sel
    if (cs_i && !we_i) begin
      a_rd_bank_q  <= a_bank;
      a_rd_slice_q <= a_slice;
    end
  end

  assign rdata_o = a_bank_rdata[(NUM_BANKS > 1) ? a_rd_bank_q : '0];

  // -------------------------------------------------------------------------
  // Port B decode and read multiplexer (b_clk)
  // -------------------------------------------------------------------------
  logic [BankW-1:0]  b_bank, b_rd_bank_q;
  logic [SlW-1:0]    b_slice, b_rd_slice_q;
  logic [SAw-1:0]    b_saddr;
  logic [MW_B-1:0]   b_bank_rdata [NUM_BANKS];

  if (NUM_BANKS > 1) begin : g_b_bank
    assign b_bank = BankW'(b_idx_i >> BankAwB);
  end else begin : g_b_one_bank
    assign b_bank = '0;
  end

  if (BSliced) begin : g_b_slice
    assign b_slice = SlW'(b_idx_i[BankAwB-1:0]);
    assign b_saddr = SAw'(b_idx_i[BankAwB-1:0] >> RSh);
  end else begin : g_b_whole
    assign b_slice = '0;
    assign b_saddr = SAw'(b_idx_i[BankAwB-1:0]);
  end

  always_ff @(posedge b_clk) begin : p_b_rd_sel
    if (b_cs_i && !b_we_i) begin
      b_rd_bank_q  <= b_bank;
      b_rd_slice_q <= b_slice;
    end
  end

  assign b_rdata_o = DUAL_PORT ? b_bank_rdata[(NUM_BANKS > 1) ? b_rd_bank_q : '0] : '0;

  // -------------------------------------------------------------------------
  // Banks
  // -------------------------------------------------------------------------
  for (genvar k = 0; k < NUM_BANKS; k++) begin : g_bank
    logic a_bank_cs, b_bank_cs;
    assign a_bank_cs = cs_i && (a_bank == BankW'(k));
    assign b_bank_cs = b_cs_i && (b_bank == BankW'(k));

    if (DUAL_PORT) begin : g_dp
      logic [SW-1:0] a_slice_rdata [R];  // per-slice read data, port A
      logic [SW-1:0] b_slice_rdata [R];  // per-slice read data, port B

      for (genvar s = 0; s < R; s++) begin : g_slice
        logic          a_cs, b_cs;
        logic [SW-1:0] a_wd, b_wd;
        logic [SL-1:0] a_lw, b_lw;

        assign a_cs = a_bank_cs && (!ASliced || a_slice == SlW'(s));
        assign b_cs = b_bank_cs && (!BSliced || b_slice == SlW'(s));
        assign a_wd = ASliced ? SW'(wdata_i) : wdata_i[s * SW +: SW];
        assign b_wd = BSliced ? SW'(b_wdata_i) : b_wdata_i[s * SW +: SW];
        assign a_lw = slice_lanes(64'(lane_we_i), NLANES, ASliced, LpsA, s);
        assign b_lw = slice_lanes(64'(b_lane_we_i), NLANES_B, BSliced, LpsB, s);

        sram_macro_dp #(
          .TECH      (TECH),
          .W         (SW),
          .D         (SD),
          .NLANES    (SL),
          .COMMON_CLK(COMMON_CLK),
          .INIT_FILE ((R == 1) ? INIT_FILE : "")
        ) u_macro (
          .a_clk      (clk),
          .a_cs_i     (a_cs),
          .a_we_i     (we_i),
          .a_addr_i   (a_saddr),
          .a_wdata_i  (a_wd),
          .a_lane_we_i(a_lw),
          .a_rdata_o  (a_slice_rdata[s]),
          .b_clk      (b_clk),
          .b_cs_i     (b_cs),
          .b_we_i     (b_we_i),
          .b_addr_i   (b_saddr),
          .b_wdata_i  (b_wd),
          .b_lane_we_i(b_lw),
          .b_rdata_o  (b_slice_rdata[s]),
          .ls_i       (ls_i[k]),
          .ds_i       (ds_i[k]),
          .sd_i       (sd_i[k])
        );

        // The wide port reads every slice.
        if (!ASliced) begin : g_a_cat
          assign a_bank_rdata[k][s * SW +: SW] = a_slice_rdata[s];
        end
        if (!BSliced) begin : g_b_cat
          assign b_bank_rdata[k][s * SW +: SW] = b_slice_rdata[s];
        end
      end

      // The narrow port reads the slice it addressed.
      if (ASliced) begin : g_a_mux
        assign a_bank_rdata[k] = a_slice_rdata[a_rd_slice_q];
      end
      if (BSliced) begin : g_b_mux
        assign b_bank_rdata[k] = b_slice_rdata[b_rd_slice_q];
      end
    end else begin : g_sp
      assign b_bank_rdata[k] = '0;

      sram_macro #(
        .TECH     (TECH),
        .W        (MW),
        .D        (SD),
        .NLANES   (NLANES),
        .INIT_FILE(INIT_FILE)
      ) u_macro (
        .clk      (clk),
        .cs_i     (a_bank_cs),
        .we_i     (we_i),
        .addr_i   (a_saddr),
        .wdata_i  (wdata_i),
        .lane_we_i(lane_we_i),
        .ls_i     (ls_i[k]),
        .ds_i     (ds_i[k]),
        .sd_i     (sd_i[k]),
        .rdata_o  (a_bank_rdata[k])
      );
    end
  end

endmodule : sram_array
