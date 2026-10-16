// claude_axi4l_mem_if.sv — AXI4-Lite slave to Claude memory bus adapter (shared component).
//
// Turns AXI4-Lite transfers into requests on the Claude memory bus (mem_*),
// for memory-like targets that may stall and may report errors. The bus
// rules are in IP/common/design/rtl/mem_bus.md. Register-file IP keeps using
// claude_axi4l_if; this adapter is for memories.
//
// Protocol notes:
//   - One write and one read may be in flight at once. AW, W and AR are each
//     captured into a one-entry slot (READY is high while the slot is empty);
//     a slot is freed by the B (write) or R (read) handshake.
//   - The memory has a single port, so reads and writes are serialized.
//     When both are ready they alternate (round robin), so neither starves.
//   - A request is raised in the cycle after AW+W (or AR) are captured, held
//     until granted, and its response is turned into BVALID or RVALID (with
//     RDATA captured) the cycle after mem_rvalid_i. BVALID/RVALID are held
//     until BREADY/RREADY.
//   - BRESP/RRESP: OKAY (2'b00), or SLVERR (2'b10) when mem_err_i was set.
//   - Byte enables: WSTRB on writes, all ones on reads.
//   - AWPROT/ARPROT are not used and not part of the port list.
//
// Ports (bus side):
//   ACLK, ARESETn       AXI clock and active-low synchronous reset
//   AW channel          AWVALID, AWREADY, AWADDR[ADDR_W-1:0]
//   W  channel          WVALID, WREADY, WDATA, WSTRB
//   B  channel          BVALID, BREADY, BRESP[1:0]
//   AR channel          ARVALID, ARREADY, ARADDR[ADDR_W-1:0]
//   R  channel          RVALID, RREADY, RDATA, RRESP[1:0]
//
// Ports (memory side): see mem_bus.md.

module claude_axi4l_mem_if #(
  parameter int unsigned DATA_W = 32, // data bus width (multiple of 8)
  parameter int unsigned ADDR_W = 32  // byte address width
) (
  // AXI4-Lite global signals
  input  logic                  ACLK,          // AXI clock
  input  logic                  ARESETn,       // AXI active-low reset

  // Write address channel
  input  logic                  AWVALID,       // write address valid
  output logic                  AWREADY,       // write address accepted
  input  logic [ADDR_W-1:0]     AWADDR,        // write byte address

  // Write data channel
  input  logic                  WVALID,        // write data valid
  output logic                  WREADY,        // write data accepted
  input  logic [DATA_W-1:0]     WDATA,         // write data
  input  logic [DATA_W/8-1:0]   WSTRB,         // write byte strobes

  // Write response channel
  output logic                  BVALID,        // write response valid
  input  logic                  BREADY,        // write response accepted
  output logic [1:0]            BRESP,         // OKAY or SLVERR

  // Read address channel
  input  logic                  ARVALID,       // read address valid
  output logic                  ARREADY,       // read address accepted
  input  logic [ADDR_W-1:0]     ARADDR,        // read byte address

  // Read data channel
  output logic                  RVALID,        // read data valid
  input  logic                  RREADY,        // read data accepted
  output logic [DATA_W-1:0]     RDATA,         // read data
  output logic [1:0]            RRESP,         // OKAY or SLVERR

  // Memory bus (initiator side)
  output logic                  mem_req_o,     // request valid
  input  logic                  mem_gnt_i,     // request accepted
  output logic                  mem_we_o,      // 1 = write
  output logic [ADDR_W-1:0]     mem_addr_o,    // byte address
  output logic [DATA_W/8-1:0]   mem_be_o,      // byte enables
  output logic [DATA_W-1:0]     mem_wdata_o,   // write data
  input  logic                  mem_rvalid_i,  // response valid
  input  logic [DATA_W-1:0]     mem_rdata_i,   // read data
  input  logic                  mem_err_i      // response is an error
);

  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;

  // -------------------------------------------------------------------------
  // Request slots: one write address, one write data, one read address.
  // -------------------------------------------------------------------------
  logic                aw_full_q;   // write address captured
  logic [ADDR_W-1:0]   aw_addr_q;
  logic                w_full_q;    // write data captured
  logic [DATA_W-1:0]   w_data_q;
  logic [DATA_W/8-1:0] w_strb_q;
  logic                ar_full_q;   // read address captured
  logic [ADDR_W-1:0]   ar_addr_q;

  logic                bvalid_q;    // write response waiting for BREADY
  logic [1:0]          bresp_q;
  logic                rvalid_q;    // read response waiting for RREADY
  logic [DATA_W-1:0]   rdata_q;
  logic [1:0]          rresp_q;

  logic aw_hs, w_hs, ar_hs, b_hs, r_hs;  // channel handshakes

  assign AWREADY = ~aw_full_q;
  assign WREADY  = ~w_full_q;
  assign ARREADY = ~ar_full_q;

  assign aw_hs = AWVALID & AWREADY;
  assign w_hs  = WVALID  & WREADY;
  assign ar_hs = ARVALID & ARREADY;
  assign b_hs  = bvalid_q & BREADY;
  assign r_hs  = rvalid_q & RREADY;

  always_ff @(posedge ACLK) begin : p_slots
    if (!ARESETn) begin
      aw_full_q <= 1'b0;
      aw_addr_q <= '0;
      w_full_q  <= 1'b0;
      w_data_q  <= '0;
      w_strb_q  <= '0;
      ar_full_q <= 1'b0;
      ar_addr_q <= '0;
    end else begin
      if (aw_hs) begin
        aw_full_q <= 1'b1;
        aw_addr_q <= AWADDR;
      end else if (b_hs) begin
        aw_full_q <= 1'b0;
      end
      if (w_hs) begin
        w_full_q <= 1'b1;
        w_data_q <= WDATA;
        w_strb_q <= WSTRB;
      end else if (b_hs) begin
        w_full_q <= 1'b0;
      end
      if (ar_hs) begin
        ar_full_q <= 1'b1;
        ar_addr_q <= ARADDR;
      end else if (r_hs) begin
        ar_full_q <= 1'b0;
      end
    end
  end

  // -------------------------------------------------------------------------
  // Request state machine
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] {
    StIdle,  // no memory request in flight
    StReq,   // request raised but not yet granted
    StWait   // request granted, waiting for the memory response
  } req_state_e;

  req_state_e state_d, state_q;

  logic wr_ready;     // a complete write is waiting to be issued
  logic rd_ready;     // a read is waiting to be issued
  logic pick_write;   // StIdle: which one to issue now
  logic sel_write_d, sel_write_q;  // the request in flight is a write
  logic last_write_d, last_write_q; // last issued request was a write
  logic cur_write;    // request on the memory bus this cycle is a write

  assign wr_ready   = aw_full_q & w_full_q & ~bvalid_q;
  assign rd_ready   = ar_full_q & ~rvalid_q;
  // Both ready: take the opposite of the last one issued (round robin).
  assign pick_write = (wr_ready && rd_ready) ? ~last_write_q : wr_ready;

  always_comb begin : p_state_comb
    state_d      = state_q;
    sel_write_d  = sel_write_q;
    last_write_d = last_write_q;
    unique case (state_q)
      // StIdle: issue the next ready request at once; it stays on the bus
      // (from StReq) if the memory does not grant it in this cycle.
      StIdle: begin
        if (wr_ready || rd_ready) begin
          sel_write_d  = pick_write;
          last_write_d = pick_write;
          state_d      = mem_gnt_i ? StWait : StReq;
        end
      end
      // StReq: hold the request until granted.
      StReq: begin
        if (mem_gnt_i) begin
          state_d = StWait;
        end
      end
      // StWait: the response returns the state machine to idle.
      StWait: begin
        if (mem_rvalid_i) begin
          state_d = StIdle;
        end
      end
      default: state_d = StIdle;
    endcase
  end

  always_ff @(posedge ACLK) begin : p_state_reg
    if (!ARESETn) begin
      state_q      <= StIdle;
      sel_write_q  <= 1'b0;
      last_write_q <= 1'b0;
    end else begin
      state_q      <= state_d;
      sel_write_q  <= sel_write_d;
      last_write_q <= last_write_d;
    end
  end

  assign cur_write = (state_q == StIdle) ? pick_write : sel_write_q;

  assign mem_req_o   = ((state_q == StIdle) && (wr_ready || rd_ready)) ||
                       (state_q == StReq);
  assign mem_we_o    = cur_write;
  assign mem_addr_o  = cur_write ? aw_addr_q : ar_addr_q;
  assign mem_be_o    = cur_write ? w_strb_q : {(DATA_W/8){1'b1}};
  assign mem_wdata_o = w_data_q;

  // -------------------------------------------------------------------------
  // Responses: captured from the memory, held until the master takes them.
  // -------------------------------------------------------------------------
  logic resp_wr;  // memory response for a write this cycle
  logic resp_rd;  // memory response for a read this cycle

  assign resp_wr = (state_q == StWait) & mem_rvalid_i &  sel_write_q;
  assign resp_rd = (state_q == StWait) & mem_rvalid_i & ~sel_write_q;

  always_ff @(posedge ACLK) begin : p_resp
    if (!ARESETn) begin
      bvalid_q <= 1'b0;
      bresp_q  <= RESP_OKAY;
      rvalid_q <= 1'b0;
      rdata_q  <= '0;
      rresp_q  <= RESP_OKAY;
    end else begin
      if (resp_wr) begin
        bvalid_q <= 1'b1;
        bresp_q  <= mem_err_i ? RESP_SLVERR : RESP_OKAY;
      end else if (b_hs) begin
        bvalid_q <= 1'b0;
      end
      if (resp_rd) begin
        rvalid_q <= 1'b1;
        rdata_q  <= mem_rdata_i;
        rresp_q  <= mem_err_i ? RESP_SLVERR : RESP_OKAY;
      end else if (r_hs) begin
        rvalid_q <= 1'b0;
      end
    end
  end

  assign BVALID = bvalid_q;
  assign BRESP  = bresp_q;
  assign RVALID = rvalid_q;
  assign RDATA  = rdata_q;
  assign RRESP  = rresp_q;

endmodule : claude_axi4l_mem_if
