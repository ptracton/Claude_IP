// claude_ahb_mem_if.sv — AHB-Lite slave to Claude memory bus adapter (shared component).
//
// Turns AHB-Lite transfers into requests on the Claude memory bus (mem_*),
// for memory-like targets that may stall and may report errors. The bus
// rules are in IP/common/design/rtl/mem_bus.md. Register-file IP keeps using
// claude_ahb_if; this adapter is for memories.
//
// Protocol notes:
//   - Any burst: NONSEQ and SEQ are both transfers; IDLE and BUSY are not
//     (they get the zero-wait OKAY response). HBURST is not needed, because
//     every beat carries its own address.
//   - HREADY is the bus-wide ready (input) and HREADYOUT this slave's
//     ready (output), as in a multi-slave AHB-Lite system. With a single
//     slave, connect HREADY to HREADYOUT.
//   - An address phase is accepted when HSEL & HTRANS[1] & HREADY. The
//     memory request is raised in the first data-phase cycle (write data is
//     only valid then), so every beat has at least one wait state.
//   - Byte enables come from HSIZE and HADDR (the naturally aligned lanes
//     of the transfer). On writes they are ANDed with HWSTRB (AHB5 write
//     strobes); a master without HWSTRB ties it to all ones.
//   - mem_err_i gives the two-cycle ERROR response: HRESP high with
//     HREADYOUT low, then HRESP high with HREADYOUT high.
//
// Ports (bus side):
//   HCLK, HRESETn       AHB clock and active-low synchronous reset
//   HSEL                slave select
//   HADDR[ADDR_W-1:0]   byte address (passed through unchanged)
//   HTRANS[1:0]         IDLE / BUSY / NONSEQ / SEQ
//   HWRITE              1 = write, 0 = read
//   HSIZE[2:0]          transfer size, 2**HSIZE bytes (<= DATA_W/8)
//   HWDATA, HWSTRB      write data and byte strobes (data phase)
//   HREADY              bus ready (input)
//   HRDATA              read data
//   HREADYOUT           this slave's ready (output)
//   HRESP               0 = OKAY, 1 = ERROR
//
// Ports (memory side): see mem_bus.md.

module claude_ahb_mem_if #(
  parameter int unsigned DATA_W = 32, // data bus width (multiple of 8)
  parameter int unsigned ADDR_W = 32  // byte address width
) (
  // AHB-Lite bus signals
  input  logic                  HCLK,          // AHB clock
  input  logic                  HRESETn,       // AHB active-low reset

  input  logic                  HSEL,          // slave select
  input  logic [ADDR_W-1:0]     HADDR,         // byte address
  input  logic [1:0]            HTRANS,        // transfer type
  input  logic                  HWRITE,        // 1 = write
  input  logic [2:0]            HSIZE,         // transfer size
  input  logic [DATA_W-1:0]     HWDATA,        // write data (data phase)
  input  logic [DATA_W/8-1:0]   HWSTRB,        // write strobes (data phase)
  input  logic                  HREADY,        // bus ready (all slaves)
  output logic [DATA_W-1:0]     HRDATA,        // read data
  output logic                  HREADYOUT,     // this slave's ready
  output logic                  HRESP,         // 0 = OKAY, 1 = ERROR

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

  localparam int unsigned StrbW = DATA_W / 8;
  // Width of the byte offset within a bus word (at least 1 bit so the
  // vectors below stay legal when DATA_W = 8).
  localparam int unsigned OffW  = (StrbW > 1) ? $clog2(StrbW) : 1;

  // -------------------------------------------------------------------------
  // lane_mask — byte lanes covered by a transfer of 2**size bytes at byte
  // offset `offset`: lane b is enabled when it lies in the same naturally
  // aligned 2**size-byte block as the address. Sizes of a full word or more
  // enable every lane.
  // -------------------------------------------------------------------------
  function automatic logic [StrbW-1:0] lane_mask(logic [2:0] size, logic [OffW-1:0] offset);
    logic [StrbW-1:0] mask;
    logic [OffW-1:0]  lane;
    mask = '0;
    for (int unsigned b = 0; b < StrbW; b++) begin
      lane = OffW'(b);
      mask[b] = ((lane >> size) == (offset >> size)) ? 1'b1 : 1'b0;
    end
    if (StrbW == 1) begin
      mask = '1;
    end
    return mask;
  endfunction

  // -------------------------------------------------------------------------
  // Data-phase state machine
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] {
    StIdle,  // no data phase of ours (or an IDLE/BUSY one): ready, OKAY
    StReq,   // data phase started: memory request raised, waiting for grant
    StWait,  // request granted: waiting for the memory response
    StErr    // second cycle of the two-cycle ERROR response
  } dphase_state_e;

  dphase_state_e state_d, state_q;

  logic                aphase;      // valid transfer in the address phase
  logic                accept;      // address phase accepted this cycle
  logic                dp_write_q;  // data phase is a write
  logic [ADDR_W-1:0]   dp_addr_q;   // data phase byte address
  logic [StrbW-1:0]    dp_mask_q;   // data phase byte lanes (from HSIZE/HADDR)

  assign aphase = HSEL & HTRANS[1];  // NONSEQ (2'b10) or SEQ (2'b11)
  assign accept = aphase & HREADY;

  always_comb begin : p_state_comb
    state_d = state_q;
    if (accept) begin
      // An accepted address phase starts the next data phase. HREADY is
      // high, so the current data phase (if any) ends in this same cycle.
      state_d = StReq;
    end else begin
      unique case (state_q)
        // StIdle: nothing to do until an address phase is accepted.
        StIdle: ;
        // StReq: hold the request until the memory grants it.
        StReq: begin
          if (mem_gnt_i) begin
            state_d = StWait;
          end
        end
        // StWait: the response ends the data phase, or starts an ERROR response.
        StWait: begin
          if (mem_rvalid_i) begin
            state_d = mem_err_i ? StErr : StIdle;
          end
        end
        // StErr: second ERROR cycle (HREADYOUT high), then idle.
        StErr: state_d = StIdle;
        default: state_d = StIdle;
      endcase
    end
  end

  always_ff @(posedge HCLK) begin : p_state_reg
    if (!HRESETn) begin
      state_q <= StIdle;
    end else begin
      state_q <= state_d;
    end
  end

  // Address-phase information for the data phase.
  always_ff @(posedge HCLK) begin : p_dphase_info
    if (!HRESETn) begin
      dp_write_q <= 1'b0;
      dp_addr_q  <= '0;
      dp_mask_q  <= '0;
    end else if (accept) begin
      dp_write_q <= HWRITE;
      dp_addr_q  <= HADDR;
      dp_mask_q  <= lane_mask(HSIZE, HADDR[OffW-1:0]);
    end
  end

  // -------------------------------------------------------------------------
  // Memory request. HWDATA/HWSTRB are held by the master while HREADYOUT is
  // low, so they are stable from request to grant.
  // -------------------------------------------------------------------------
  assign mem_req_o   = (state_q == StReq);
  assign mem_we_o    = dp_write_q;
  assign mem_addr_o  = dp_addr_q;
  assign mem_be_o    = dp_write_q ? (dp_mask_q & HWSTRB) : dp_mask_q;
  assign mem_wdata_o = HWDATA;

  // -------------------------------------------------------------------------
  // Bus response
  // -------------------------------------------------------------------------
  assign HREADYOUT = (state_q == StIdle) || (state_q == StErr) ||
                     ((state_q == StWait) && mem_rvalid_i && !mem_err_i);
  assign HRESP     = (state_q == StErr) ||
                     ((state_q == StWait) && mem_rvalid_i && mem_err_i);
  assign HRDATA    = mem_rdata_i;

endmodule : claude_ahb_mem_if
