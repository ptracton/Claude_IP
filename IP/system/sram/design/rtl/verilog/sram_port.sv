// sram_port.sv — One memory-bus port of the sram core.
//
// Target side of the Claude memory bus (IP/common/design/rtl/mem_bus.md),
// driving the array. Accepts one request at a time (the adapters never
// issue more) and answers it READ_LATENCY cycles after the grant.
//
// Request (cycle s0, mem_req_i high):
//   stall_i (an engine is pending/running)       -> wait (no grant)
//   address beyond DEPTH words                   -> grant, error response
//   partial write with BYTE_EN = 0, PARTIAL_WR_ERR -> grant, error response
//   domain requested DS or SD (dom_err_i)        -> grant, error response
//   domain not awake (LS, or waking)             -> wait, wake_o[domain]
//   otherwise                                    -> grant, array access:
//     read                    read the word
//     write, ECC, partial     read (read-modify-write, finished in s1)
//     write otherwise         write (ECC-encoded when ECC_EN; with BYTE_EN
//                             and no ECC only the strobed lanes)
// Response (cycle s1 for READ_LATENCY = 1, s2 for 2):
//   read data (SECDED-corrected when ECC_EN); error on an uncorrectable
//   word. A read-modify-write merges the strobed bytes into the corrected
//   word and writes it back in s1 (no write if uncorrectable).
//
// ECC error injection: ecc_inj_i[0] / [1] arm a 1-bit / 2-bit flip (stored
// bits 0, or 0 and 1) applied to the next write from this port.
//
// READ_ONLY: every write is answered with a bus error (port B of a SKY130
// dual-port array, whose second macro port cannot write).
// Conflict outputs (req_*, acc_o, rmw_*) let the core keep the two ports of
// a DUAL_PORT array off the same word; stall_i holds a request back.

module sram_port #(
  parameter int unsigned ADDR_W         = 32,    // bus byte-address width
  parameter int unsigned WIDTH          = 32,    // data width (multiple of 8)
  parameter int unsigned DEPTH          = 1024,  // words
  parameter bit          BYTE_EN        = 1,     // byte-lane writes
  parameter bit          PARTIAL_WR_ERR = 1,     // BYTE_EN = 0: partial write is an error
  parameter int unsigned READ_LATENCY   = 1,     // 1 or 2
  parameter bit          ECC_EN         = 0,     // SECDED
  parameter int unsigned NPD            = 1,     // power domains
  parameter bit          READ_ONLY      = 0,     // writes are bus errors
  // Derived
  localparam int unsigned MW     = WIDTH + (ECC_EN ? sram_pkg::ecc_check_bits(WIDTH) : 0),
  localparam int unsigned NLANES = (BYTE_EN && !ECC_EN) ? WIDTH / 8 : 1
) (
  input  logic                       clk,          // clock
  input  logic                       rst_n,        // synchronous active-low reset

  // Memory bus (target side)
  input  logic                       mem_req_i,    // request
  output logic                       mem_gnt_o,    // request accepted
  input  logic                       mem_we_i,     // 1 = write
  input  logic [ADDR_W-1:0]          mem_addr_i,   // byte address
  input  logic [WIDTH/8-1:0]         mem_be_i,     // byte enables
  input  logic [WIDTH-1:0]           mem_wdata_i,  // write data
  output logic                       mem_rvalid_o, // response
  output logic [WIDTH-1:0]           mem_rdata_o,  // read data
  output logic                       mem_err_o,    // response is an error

  // Power domains and engines
  input  logic [NPD-1:0]             dom_awake_i,  // domain accepts bus accesses
  input  logic [NPD-1:0]             dom_err_i,    // domain access is a bus error
  input  logic                       stall_i,      // an engine owns the array
  output logic [NPD-1:0]             wake_o,       // a request waits for this domain
  output logic [NPD-1:0]             dom_busy_o,   // access to this domain in flight
  output logic                       idle_o,       // nothing in flight on the array

  // Conflict information (DUAL_PORT)
  output logic [$clog2(DEPTH)-1:0]   req_idx_o,    // word index of the request
  output logic                       req_we_o,     // the request is a write
  output logic                       acc_o,        // granted with an array access now
  output logic                       rmw_pend_o,   // read-modify-write write-back pending
  output logic [$clog2(DEPTH)-1:0]   rmw_idx_o,    // its word index

  // Array
  output logic                       arr_cs_o,     // array access
  output logic                       arr_we_o,     // 1 = write
  output logic [$clog2(DEPTH)-1:0]   arr_idx_o,    // word index
  output logic [MW-1:0]              arr_wdata_o,  // stored word
  output logic [NLANES-1:0]          arr_lane_we_o,// lanes to write
  input  logic [MW-1:0]              arr_rdata_i,  // stored word (cycle after a read)

  // ECC and status
  input  logic [1:0]                 ecc_inj_i,    // arm 1-bit [0] / 2-bit [1] error
  output logic                       ecc_corr_o,   // corrected error (registered pulse)
  output logic                       ecc_uncorr_o, // uncorrectable error (registered pulse)
  output logic                       err_irq_o,    // bus error or ECC event (registered pulse)
  output logic                       busy_o        // read-modify-write in progress
);

  localparam int unsigned StrbW  = WIDTH / 8;
  localparam int unsigned OffW   = (StrbW > 1) ? $clog2(StrbW) : 0;
  localparam int unsigned IdxW   = $clog2(DEPTH);
  localparam int unsigned DomW   = (NPD > 1) ? $clog2(NPD) : 1;
  localparam int unsigned DomSh  = $clog2(DEPTH / NPD);
  localparam int unsigned UpperW = (ADDR_W > OffW + IdxW) ? ADDR_W - OffW - IdxW : 1;

  // -------------------------------------------------------------------------
  // Request decode (s0)
  // -------------------------------------------------------------------------
  logic [IdxW-1:0] idx;
  logic [DomW-1:0] dom;
  logic            oor;        // beyond the last word
  logic            partial;    // write with some byte enables clear
  logic            req_err;    // grant with an error response
  logic            rmw;        // ECC partial write: read first
  logic            grant;      // mem_gnt_o
  logic            do_access;     // grant with an array access

  logic            s1_valid_q;

  assign idx = mem_addr_i[OffW +: IdxW];

  if (NPD > 1) begin : g_dom
    assign dom = DomW'(idx >> DomSh);
  end else begin : g_one_dom
    assign dom = '0;
  end

  if (ADDR_W > OffW + IdxW) begin : g_oor
    assign oor = (mem_addr_i[ADDR_W-1:OffW+IdxW] != UpperW'(0));
  end else begin : g_no_oor
    assign oor = 1'b0;
  end

  assign partial = mem_we_i && (mem_be_i != {StrbW{1'b1}});
  assign req_err = oor || dom_err_i[dom] || (READ_ONLY && mem_we_i) ||
                   (!BYTE_EN && PARTIAL_WR_ERR && partial);
  assign rmw     = ECC_EN && BYTE_EN && partial;

  // Grant: never while an engine owns the array or a response is pending.
  always_comb begin : p_grant
    grant  = 1'b0;
    do_access = 1'b0;
    wake_o = '0;
    if (mem_req_i && !stall_i && !s1_valid_q) begin
      if (req_err) begin
        grant = 1'b1;
      end else if (dom_awake_i[dom]) begin
        grant  = 1'b1;
        do_access = 1'b1;
      end else begin
        wake_o[dom] = 1'b1;
      end
    end
  end

  assign mem_gnt_o = grant;

  // -------------------------------------------------------------------------
  // s1: request registers
  // -------------------------------------------------------------------------
  logic                s1_err_q;    // respond with an error, no array access
  logic                s1_we_q;
  logic                s1_rmw_q;
  logic [IdxW-1:0]     s1_idx_q;
  logic [DomW-1:0]     s1_dom_q;
  logic [StrbW-1:0]    s1_be_q;
  logic [WIDTH-1:0]    s1_wdata_q;

  // Capture the granted request for its response cycle.
  always_ff @(posedge clk) begin : p_s1
    if (!rst_n) begin
      s1_valid_q <= 1'b0;
      s1_err_q   <= 1'b0;
      s1_we_q    <= 1'b0;
      s1_rmw_q   <= 1'b0;
      s1_idx_q   <= '0;
      s1_dom_q   <= '0;
      s1_be_q    <= '0;
      s1_wdata_q <= '0;
    end else begin
      s1_valid_q <= grant;
      if (grant) begin
        s1_err_q   <= req_err;
        s1_we_q    <= mem_we_i;
        s1_rmw_q   <= do_access && rmw;
        s1_idx_q   <= idx;
        s1_dom_q   <= dom;
        s1_be_q    <= mem_be_i;
        s1_wdata_q <= mem_wdata_i;
      end
    end
  end

  // -------------------------------------------------------------------------
  // ECC: decode the word read in s0, merge for read-modify-write, encode
  // -------------------------------------------------------------------------
  logic [WIDTH-1:0] rd_data;     // data read (corrected)
  logic             dec_single;
  logic             dec_double;
  logic [WIDTH-1:0] merged;      // read-modify-write result
  logic             rmw_write;   // s1 write-back of a read-modify-write
  logic [WIDTH-1:0] enc_data;    // data to encode / write
  logic [MW-1:0]    stored;      // word written to the array (before injection)
  logic [1:0]       inj_q;       // armed error injection
  logic             bus_write;   // a write from this port reaches the array
  logic [MW-1:0]    flip;        // injected bit flips

  if (ECC_EN) begin : g_ecc
    sram_ecc_dec #(
      .K(WIDTH)
    ) u_dec (
      .code_i  (arr_rdata_i),
      .data_o  (rd_data),
      .single_o(dec_single),
      .double_o(dec_double)
    );
    sram_ecc_enc #(
      .K(WIDTH)
    ) u_enc (
      .data_i(enc_data),
      .code_o(stored)
    );
  end else begin : g_no_ecc
    assign rd_data    = arr_rdata_i[WIDTH-1:0];
    assign dec_single = 1'b0;
    assign dec_double = 1'b0;
    assign stored     = MW'(enc_data);
  end

  for (genvar b = 0; b < StrbW; b++) begin : g_merge
    assign merged[8*b +: 8] = s1_be_q[b] ? s1_wdata_q[8*b +: 8] : rd_data[8*b +: 8];
  end

  assign rmw_write = s1_valid_q && s1_rmw_q && !dec_double;
  assign enc_data  = rmw_write ? merged : mem_wdata_i;
  assign bus_write = rmw_write || (do_access && mem_we_i && !rmw);
  assign flip      = !ECC_EN    ? '0 :
                     inj_q[1]   ? MW'(2'b11) :
                     inj_q[0]   ? MW'(2'b01) : '0;

  // Armed error injection; consumed by the next write from this port.
  always_ff @(posedge clk) begin : p_inject
    if (!rst_n) begin
      inj_q <= '0;
    end else begin
      inj_q <= (bus_write ? 2'b00 : inj_q) | (ECC_EN ? ecc_inj_i : 2'b00);
    end
  end

  // -------------------------------------------------------------------------
  // Array access: s0 request, or the s1 write-back of a read-modify-write
  // -------------------------------------------------------------------------
  always_comb begin : p_array
    arr_cs_o      = 1'b0;
    arr_we_o      = 1'b0;
    arr_idx_o     = idx;
    arr_wdata_o   = stored ^ flip;
    arr_lane_we_o = '1;
    if (rmw_write) begin
      arr_cs_o  = 1'b1;
      arr_we_o  = 1'b1;
      arr_idx_o = s1_idx_q;
    end else if (do_access) begin
      arr_cs_o = 1'b1;
      arr_we_o = mem_we_i && !rmw;
      if (NLANES > 1) begin
        arr_lane_we_o = NLANES'(mem_be_i);
      end
    end
  end

  // -------------------------------------------------------------------------
  // s1 response
  // -------------------------------------------------------------------------
  logic             checked;    // s1 used read data
  logic             rsp_err;
  logic [WIDTH-1:0] rsp_data;

  assign checked  = s1_valid_q && !s1_err_q && (s1_rmw_q || !s1_we_q);
  assign rsp_err  = s1_err_q || (checked && dec_double);
  assign rsp_data = (s1_valid_q && !s1_err_q && !s1_we_q && !dec_double) ? rd_data : '0;

  // Status pulses are registered (one cycle after the response cycle): the
  // read data behind them comes straight from the macro outputs, so a
  // combinational pulse could glitch at the IP boundary.
  logic ecc_corr_q, ecc_uncorr_q, err_irq_q;

  always_ff @(posedge clk) begin : p_status
    if (!rst_n) begin
      ecc_corr_q   <= 1'b0;
      ecc_uncorr_q <= 1'b0;
      err_irq_q    <= 1'b0;
    end else begin
      ecc_corr_q   <= ECC_EN && checked && dec_single;
      ecc_uncorr_q <= ECC_EN && checked && dec_double;
      err_irq_q    <= (s1_valid_q && rsp_err) || (ECC_EN && checked && dec_single);
    end
  end

  assign ecc_corr_o   = ecc_corr_q;
  assign ecc_uncorr_o = ecc_uncorr_q;
  assign err_irq_o    = err_irq_q;
  assign busy_o       = s1_valid_q && s1_rmw_q;
  assign idle_o       = !s1_valid_q;

  assign req_idx_o  = idx;
  assign req_we_o   = mem_we_i;
  assign acc_o      = do_access;
  assign rmw_pend_o = s1_valid_q && s1_rmw_q;
  assign rmw_idx_o  = s1_idx_q;

  for (genvar d = 0; d < NPD; d++) begin : g_busy
    assign dom_busy_o[d] = (do_access && (dom == DomW'(d))) ||
                           (s1_valid_q && !s1_err_q && (s1_dom_q == DomW'(d)));
  end

  if (READ_LATENCY == 2) begin : g_rl2
    logic             s2_valid_q;
    logic             s2_err_q;
    logic [WIDTH-1:0] s2_data_q;

    // Output register (READ_LATENCY = 2).
    always_ff @(posedge clk) begin : p_s2
      if (!rst_n) begin
        s2_valid_q <= 1'b0;
        s2_err_q   <= 1'b0;
        s2_data_q  <= '0;
      end else begin
        s2_valid_q <= s1_valid_q;
        s2_err_q   <= rsp_err;
        s2_data_q  <= rsp_data;
      end
    end

    assign mem_rvalid_o = s2_valid_q;
    assign mem_err_o    = s2_err_q;
    assign mem_rdata_o  = s2_data_q;
  end else begin : g_rl1
    assign mem_rvalid_o = s1_valid_q;
    assign mem_err_o    = rsp_err;
    assign mem_rdata_o  = rsp_data;
  end

endmodule : sram_port
