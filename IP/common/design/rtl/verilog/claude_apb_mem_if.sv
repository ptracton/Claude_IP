// claude_apb_mem_if.sv — APB4 slave to Claude memory bus adapter (shared component).
//
// Turns APB4 transfers into requests on the Claude memory bus (mem_*), for
// memory-like targets that may stall and may report errors. The bus rules
// are in IP/common/design/rtl/mem_bus.md. Register-file IP keeps using
// claude_apb_if; this adapter is for memories.
//
// Protocol notes:
//   - The request is raised in the SETUP phase (APB4 holds PADDR, PWRITE,
//     PWDATA and PSTRB stable from SETUP to the end of ACCESS), so a target
//     that grants at once and answers the next cycle gives a zero-wait
//     transfer. A slower target stretches ACCESS with PREADY low.
//   - PREADY is the memory response (mem_rvalid_i); PSLVERR is mem_err_i in
//     that same cycle. PRDATA is mem_rdata_i.
//   - Byte enables: PSTRB on writes, all ones on reads (APB4 drives PSTRB
//     to zero on reads).
//
// Ports (bus side):
//   PCLK, PRESETn       APB clock and active-low synchronous reset
//   PSEL, PENABLE       select and enable (ACCESS phase)
//   PADDR[ADDR_W-1:0]   byte address (passed through unchanged)
//   PWRITE              1 = write, 0 = read
//   PWDATA, PSTRB       write data and byte strobes
//   PRDATA              read data
//   PREADY              transfer complete
//   PSLVERR             transfer failed
//
// Ports (memory side): see mem_bus.md.

module claude_apb_mem_if #(
  parameter int unsigned DATA_W = 32, // data bus width (multiple of 8)
  parameter int unsigned ADDR_W = 32  // byte address width
) (
  // APB4 bus signals
  input  logic                  PCLK,          // APB clock
  input  logic                  PRESETn,       // APB active-low reset

  input  logic                  PSEL,          // slave select
  // PENABLE is part of the APB4 port but not needed: the request is issued
  // from SETUP and completion is signalled by PREADY alone.
  /* verilator lint_off UNUSEDSIGNAL */
  //spyglass disable_block W240
  input  logic                  PENABLE,       // enable (ACCESS phase)
  //spyglass enable_block W240
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic [ADDR_W-1:0]     PADDR,         // byte address
  input  logic                  PWRITE,        // 1 = write
  input  logic [DATA_W-1:0]     PWDATA,        // write data
  input  logic [DATA_W/8-1:0]   PSTRB,         // byte write strobes
  output logic [DATA_W-1:0]     PRDATA,        // read data
  output logic                  PREADY,        // transfer complete
  output logic                  PSLVERR,       // transfer failed

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

  always_ff @(posedge PCLK) begin : p_pending
    if (!PRESETn) begin
      pending_q <= 1'b0;
    end else if (mem_req_o && mem_gnt_i) begin
      pending_q <= 1'b1;
    end else if (mem_rvalid_i) begin
      pending_q <= 1'b0;
    end
  end

  // -------------------------------------------------------------------------
  // Request: from SETUP until granted. pending_q is still high in the
  // response cycle, so a completed transfer is never issued twice; the
  // next transfer starts with its own SETUP phase one cycle later.
  // -------------------------------------------------------------------------
  assign mem_req_o   = PSEL & ~pending_q;
  assign mem_we_o    = PWRITE;
  assign mem_addr_o  = PADDR;
  assign mem_be_o    = PWRITE ? PSTRB : {(DATA_W/8){1'b1}};
  assign mem_wdata_o = PWDATA;

  // -------------------------------------------------------------------------
  // Response
  // -------------------------------------------------------------------------
  assign PREADY  = mem_rvalid_i & pending_q;
  assign PSLVERR = mem_rvalid_i & pending_q & mem_err_i;
  assign PRDATA  = mem_rdata_i;

endmodule : claude_apb_mem_if
