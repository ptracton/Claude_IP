// claude_mem_fv.sv — Reusable formal checker for the Claude memory bus (mem_*).
//
// The memory bus is the request/response link between a claude_<proto>_mem_if
// adapter (initiator) and a memory (target); its rules are in
// IP/common/design/rtl/mem_bus.md. Every port is an input, so the checker
// can be bound into SV or VHDL designs.
//
// Roles (INITIATOR_IS_DUT):
//   1 (default)  the design is the initiator (an adapter): initiator rules are
//                asserted, target rules are assumed (the solver plays a legal
//                memory that grants and answers within MAX_WAIT cycles).
//   0            the design is the target (a memory): target rules are
//                asserted, initiator rules are assumed.
//
// Initiator rules:
//   i_req_hold        request and payload held until granted (mem_wdata only
//                     for writes: it means nothing on a read)
//   i_one_outstanding no request while one is outstanding (incl. its response cycle)
// Target rules:
//   t_rvalid_needs_req   a response only for an outstanding request
//   t_gnt_bounded        a request is granted within MAX_WAIT cycles
//   t_rvalid_bounded     an outstanding request is answered within MAX_WAIT cycles

module claude_mem_fv #(
  parameter int unsigned DATA_W           = 32,
  parameter int unsigned ADDR_W           = 32,
  parameter bit          INITIATOR_IS_DUT = 1,
  parameter int unsigned MAX_WAIT         = 4
) (
  input  logic                  clk,
  input  logic                  rst,           // active-high
  input  logic                  mem_req,
  input  logic                  mem_gnt,
  input  logic                  mem_we,
  input  logic [ADDR_W-1:0]     mem_addr,
  input  logic [DATA_W/8-1:0]   mem_be,
  input  logic [DATA_W-1:0]     mem_wdata,
  input  logic                  mem_rvalid,
  input  logic [DATA_W-1:0]     mem_rdata,
  input  logic                  mem_err,

  output logic                  outstanding    // granted, response not yet seen
);

  default clocking cb @(posedge clk); endclocking
  default disable iff (rst);

  logic hs;          // request handshake
  logic outst_q;     // outstanding request (set by hs, cleared after rvalid)

  assign hs = mem_req & mem_gnt;

  always_ff @(posedge clk) begin
    if (rst) begin
      outst_q <= 1'b0;
    end else if (hs) begin
      outst_q <= 1'b1;
    end else if (mem_rvalid) begin
      outst_q <= 1'b0;
    end
  end

  assign outstanding = outst_q;

  // Rule of the initiator: asserted when it is the design under test.
  `define _MEM_INIT(NAME, PROP)                                           \
    if (INITIATOR_IS_DUT) begin : g_``NAME                                \
      NAME : assert property (PROP);                                      \
    end else begin : g_``NAME                                             \
      NAME : assume property (PROP);                                      \
    end
  // Rule of the target: assumed when the initiator is the design.
  `define _MEM_TGT(NAME, PROP)                                            \
    if (INITIATOR_IS_DUT) begin : g_``NAME                                \
      NAME : assume property (PROP);                                      \
    end else begin : g_``NAME                                             \
      NAME : assert property (PROP);                                      \
    end

  // -------------------------------------------------------------------------
  // Initiator rules
  // -------------------------------------------------------------------------
  `_MEM_INIT(i_req_hold,
    (mem_req && !mem_gnt) |=> (mem_req && $stable({mem_we, mem_addr, mem_be}) &&
                               (!mem_we || $stable(mem_wdata))))
  `_MEM_INIT(i_one_outstanding, outst_q |-> !mem_req)

  // -------------------------------------------------------------------------
  // Target rules
  // -------------------------------------------------------------------------
  `_MEM_TGT(t_rvalid_needs_req, mem_rvalid |-> outst_q)
  `_MEM_TGT(t_gnt_bounded,      mem_req |-> ##[0:MAX_WAIT] mem_gnt)
  `_MEM_TGT(t_rvalid_bounded,   outst_q |-> ##[0:MAX_WAIT] mem_rvalid)

  `undef _MEM_INIT
  `undef _MEM_TGT

  // -------------------------------------------------------------------------
  // Coverage
  // -------------------------------------------------------------------------
  c_write:       cover property (hs && mem_we);
  c_read:        cover property (hs && !mem_we);
  c_gnt_wait:    cover property (mem_req && !mem_gnt);
  c_rvalid_wait: cover property (outst_q && !mem_rvalid);
  c_err:         cover property (mem_rvalid && mem_err);
  c_back2back:   cover property (mem_rvalid ##1 hs);

endmodule : claude_mem_fv
