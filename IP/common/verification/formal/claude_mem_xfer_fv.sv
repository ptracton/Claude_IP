// claude_mem_xfer_fv.sv — End-to-end checker for a claude_<proto>_mem_if adapter.
//
// Protocol-neutral: it compares the memory-bus side of an adapter (mem_*)
// with a summary of the bus side that the per-protocol wrapper computes:
//
//   bus_busy    a bus transfer of the kind on mem_we is in progress, so a
//               memory request of that kind is allowed
//   bus_done    one-cycle pulse: a bus transfer completed (OKAY or error)
//   bus_we      ... it was a write
//   bus_addr    ... its byte address
//   bus_be      ... the byte enables the memory must have seen
//   bus_wdata   ... its write data
//   bus_rdata   ... the read data returned to the master
//   bus_err     ... it completed with the protocol's error response
//
// Properties:
//   a_req_needs_bus   no memory request without a matching bus transfer
//   a_one_req_per_xfer no second memory request before the bus transfer completes
//   a_done_has_resp   a bus transfer completes only after its memory response
//   a_done_kind / a_done_addr / a_done_be / a_done_wdata
//                     the memory request carried the bus transfer's fields
//   a_done_rdata      read data returned to the master = memory read data
//   a_done_err        error response on the bus <=> mem_err
// Together with the bounded-response rules of the bus and memory-bus
// checkers this proves a 1:1, field-exact mapping in both directions.
//
// WRITES / READS: which transfer kinds this instance sees. Both 1 (default)
// for adapters that complete one transfer at a time. An adapter that can
// complete a write and a read in the same cycle (AXI4-Lite) uses one
// instance per kind; the properties and covers of the other kind are then
// left out instead of being vacuous / uncoverable.

module claude_mem_xfer_fv #(
  parameter int unsigned DATA_W = 32,
  parameter int unsigned ADDR_W = 32,
  parameter bit          WRITES = 1,
  parameter bit          READS  = 1
) (
  input  logic                  clk,
  input  logic                  rst,          // active-high

  // Memory-bus side of the adapter
  input  logic                  mem_req,
  input  logic                  mem_gnt,
  input  logic                  mem_we,
  input  logic [ADDR_W-1:0]     mem_addr,
  input  logic [DATA_W/8-1:0]   mem_be,
  input  logic [DATA_W-1:0]     mem_wdata,
  input  logic                  mem_rvalid,
  input  logic [DATA_W-1:0]     mem_rdata,
  input  logic                  mem_err,

  // Bus side, summarized by the per-protocol wrapper
  input  logic                  bus_busy,
  input  logic                  bus_done,
  input  logic                  bus_we,
  input  logic [ADDR_W-1:0]     bus_addr,
  input  logic [DATA_W/8-1:0]   bus_be,
  input  logic [DATA_W-1:0]     bus_wdata,
  input  logic [DATA_W-1:0]     bus_rdata,
  input  logic                  bus_err
);

  default clocking cb @(posedge clk); endclocking
  default disable iff (rst);

  logic                hs;          // memory request handshake
  logic                cap_vld_q;   // a memory request belongs to the current bus transfer
  logic                cap_we_q;
  logic [ADDR_W-1:0]   cap_addr_q;
  logic [DATA_W/8-1:0] cap_be_q;
  logic [DATA_W-1:0]   cap_wdata_q;
  logic                resp_q;      // its memory response has been seen
  logic [DATA_W-1:0]   resp_rdata_q;
  logic                resp_err_q;

  logic [DATA_W-1:0]   exp_rdata;   // memory read data for this transfer
  logic                exp_err;     // memory error flag for this transfer

  assign hs = mem_req & mem_gnt;

  always_ff @(posedge clk) begin
    if (rst) begin
      cap_vld_q    <= 1'b0;
      cap_we_q     <= 1'b0;
      cap_addr_q   <= '0;
      cap_be_q     <= '0;
      cap_wdata_q  <= '0;
      resp_q       <= 1'b0;
      resp_rdata_q <= '0;
      resp_err_q   <= 1'b0;
    end else begin
      if (hs) begin
        cap_vld_q   <= 1'b1;
        cap_we_q    <= mem_we;
        cap_addr_q  <= mem_addr;
        cap_be_q    <= mem_be;
        cap_wdata_q <= mem_wdata;
      end else if (bus_done) begin
        cap_vld_q <= 1'b0;
      end
      if (mem_rvalid && cap_vld_q && !bus_done) begin
        resp_q       <= 1'b1;
        resp_rdata_q <= mem_rdata;
        resp_err_q   <= mem_err;
      end else if (bus_done) begin
        resp_q <= 1'b0;
      end
    end
  end

  // The response may arrive in the completion cycle itself (APB, AHB, WB)
  // or earlier (AXI holds it in BVALID/RVALID).
  assign exp_rdata = resp_q ? resp_rdata_q : mem_rdata;
  assign exp_err   = resp_q ? resp_err_q   : mem_err;

  a_req_needs_bus:    assert property (mem_req |-> bus_busy);
  a_one_req_per_xfer: assert property (hs |-> !cap_vld_q);
  a_done_has_resp:    assert property (bus_done |-> (cap_vld_q && (resp_q || mem_rvalid)));
  a_done_kind:        assert property (bus_done |-> (bus_we == cap_we_q));
  a_done_addr:        assert property (bus_done |-> (bus_addr == cap_addr_q));
  a_done_be:          assert property (bus_done |-> (bus_be == cap_be_q));
  a_done_err:         assert property (bus_done |-> (bus_err == exp_err));
  c_done_err:         cover property (bus_done && bus_err);

  if (WRITES) begin : g_writes
    a_done_wdata: assert property ((bus_done && bus_we) |-> (bus_wdata == cap_wdata_q));
    c_done_write: cover property (bus_done && bus_we && !bus_err);
  end
  if (READS) begin : g_reads
    a_done_rdata: assert property ((bus_done && !bus_we && !bus_err) |->
                                   (bus_rdata == exp_rdata));
    c_done_read:  cover property (bus_done && !bus_we && !bus_err);
  end

endmodule : claude_mem_xfer_fv
