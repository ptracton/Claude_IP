// claude_wb_mem_if.sv — Wishbone B4 slave to Claude memory bus adapter (shared component).
//
// Turns Wishbone B4 classic cycles into requests on the Claude memory bus
// (mem_*), for memory-like targets that may stall and may report errors.
// The bus rules are in IP/common/design/rtl/mem_bus.md. Register-file IP
// keeps using claude_wb_if; this adapter is for memories.
//
// Protocol notes:
//   - Classic (non-pipelined) cycles: the master holds CYC_I/STB_I and the
//     request fields until ACK_O or ERR_O. Aborting a cycle (dropping
//     CYC_I/STB_I before termination) is not supported.
//   - The request is raised in the first STB_I cycle. ACK_O / ERR_O is the
//     memory response (mem_rvalid_i, with mem_err_i choosing which), so a
//     target that grants at once terminates the cycle one clock after STB_I.
//   - A master may start the next transfer right after the termination
//     cycle by keeping STB_I high; it is issued as a new request.
//   - Byte enables: SEL_I for reads and writes.
//
// Ports (bus side):
//   CLK_I, RST_I        Wishbone clock and active-high synchronous reset
//   CYC_I, STB_I        bus cycle and strobe
//   WE_I                1 = write, 0 = read
//   ADR_I[ADDR_W-1:0]   byte address (passed through unchanged)
//   DAT_I, SEL_I        write data and byte selects
//   DAT_O               read data
//   ACK_O               normal termination
//   ERR_O               error termination
//
// Ports (memory side): see mem_bus.md.

module claude_wb_mem_if #(
  parameter int unsigned DATA_W = 32, // data bus width (multiple of 8)
  parameter int unsigned ADDR_W = 32  // byte address width
) (
  // Wishbone B4 signals
  input  logic                  CLK_I,         // Wishbone clock
  input  logic                  RST_I,         // active-high synchronous reset

  input  logic                  CYC_I,         // bus cycle valid
  input  logic                  STB_I,         // strobe
  input  logic                  WE_I,          // 1 = write
  input  logic [ADDR_W-1:0]     ADR_I,         // byte address
  input  logic [DATA_W-1:0]     DAT_I,         // write data
  input  logic [DATA_W/8-1:0]   SEL_I,         // byte selects
  output logic [DATA_W-1:0]     DAT_O,         // read data
  output logic                  ACK_O,         // normal termination
  output logic                  ERR_O,         // error termination

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

  // A request has been granted and its response has not arrived yet.
  logic pending_q;

  always_ff @(posedge CLK_I) begin : p_pending
    if (RST_I) begin
      pending_q <= 1'b0;
    end else if (mem_req_o && mem_gnt_i) begin
      pending_q <= 1'b1;
    end else if (mem_rvalid_i) begin
      pending_q <= 1'b0;
    end
  end

  // -------------------------------------------------------------------------
  // Request: from the first STB_I cycle until granted. pending_q is still
  // high in the termination cycle, so a finished transfer is never issued
  // twice.
  // -------------------------------------------------------------------------
  assign mem_req_o   = CYC_I & STB_I & ~pending_q;
  assign mem_we_o    = WE_I;
  assign mem_addr_o  = ADR_I;
  assign mem_be_o    = SEL_I;
  assign mem_wdata_o = DAT_I;

  // -------------------------------------------------------------------------
  // Response
  // -------------------------------------------------------------------------
  assign ACK_O = mem_rvalid_i & pending_q & ~mem_err_i;
  assign ERR_O = mem_rvalid_i & pending_q &  mem_err_i;
  assign DAT_O = mem_rdata_i;

endmodule : claude_wb_mem_if
