// bus_matrix_ahb_tgt.sv — AHB-Lite target adapter for one bus matrix master port.
//
// Acts as an AHB-Lite slave towards the external master and turns each
// transfer into one request on the core's internal handshake.
//
//   Address phase: accepted when HREADY is high and HSEL & HTRANS[1]
//     (NONSEQ or SEQ; every beat is treated as a single transfer).
//   Data phase:    mst_req is held, HREADY low, until the core reports done.
//     HWDATA/HWSTRB are passed through live: the master holds them for the
//     whole data phase.
//   Response:      OKAY ends the data phase in the done cycle. ERROR takes
//     two cycles (HREADY low + HRESP high, then HREADY high + HRESP high).
//
// HREADY is this port's HREADYOUT; the port is the only slave on the master's
// bus, so it is also the HREADY the master and this adapter sample.

module bus_matrix_ahb_tgt #(
  parameter int unsigned DATA_W = 32, // data bus width
  parameter int unsigned ADDR_W = 32  // address width
) (
  input  logic                  clk,   // system clock
  input  logic                  rst_n, // synchronous active-low reset

  // AHB-Lite slave interface (towards the external master)
  input  logic                  HSEL,   // slave select
  input  logic [ADDR_W-1:0]     HADDR,  // byte address
  // Only HTRANS[1] is used: NONSEQ and SEQ are handled the same.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [1:0]            HTRANS, // transfer type
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic                  HWRITE, // 1 = write
  input  logic [DATA_W-1:0]     HWDATA, // write data (data phase)
  input  logic [DATA_W/8-1:0]   HWSTRB, // byte strobes (data phase)
  output logic [DATA_W-1:0]     HRDATA, // read data
  output logic                  HREADY, // transfer done
  output logic                  HRESP,  // 1 = ERROR

  // Core handshake
  output logic                  core_req,   // request held until done
  output logic [ADDR_W-1:0]     core_addr,  // byte address
  output logic [DATA_W-1:0]     core_wdata, // write data
  output logic                  core_we,    // 1 = write
  output logic [DATA_W/8-1:0]   core_be,    // byte enables
  input  logic                  core_done,  // one-cycle completion
  input  logic [DATA_W-1:0]     core_rdata, // read data (valid with done)
  input  logic                  core_err    // error (valid with done)
);

  typedef enum logic [1:0] {
    TgtIdle = 2'b00,  // no data phase in progress
    TgtBusy = 2'b01,  // data phase, waiting for the core
    TgtErr2 = 2'b10   // second cycle of an ERROR response
  } tgt_state_e;

  tgt_state_e        state_q, state_d;
  logic [ADDR_W-1:0] addr_q;
  logic              we_q;
  logic              aphase; // an address phase is presented

  assign aphase = HSEL & HTRANS[1];

  always_comb begin : p_hready
    HREADY = 1'b1;
    HRESP  = 1'b0;
    unique case (state_q)
      TgtBusy: begin
        HREADY = core_done & ~core_err;
        HRESP  = core_done & core_err;
      end
      TgtErr2: begin
        HRESP  = 1'b1;
      end
      default: ;
    endcase
  end

  always_comb begin : p_next
    state_d = state_q;
    if (state_q == TgtBusy && core_done && core_err) begin
      state_d = TgtErr2;
    end else if (HREADY && aphase) begin
      state_d = TgtBusy;
    end else if (HREADY) begin
      state_d = TgtIdle;
    end
  end

  always_ff @(posedge clk) begin : p_state
    if (!rst_n) begin
      state_q <= TgtIdle;
    end else begin
      state_q <= state_d;
    end
  end

  always_ff @(posedge clk) begin : p_aphase
    if (!rst_n) begin
      addr_q <= '0;
      we_q   <= 1'b0;
    end else if (HREADY && aphase) begin
      addr_q <= HADDR;
      we_q   <= HWRITE;
    end
  end

  assign core_req   = (state_q == TgtBusy);
  assign core_addr  = addr_q;
  assign core_we    = we_q;
  assign core_wdata = HWDATA;
  assign core_be    = HWSTRB;
  assign HRDATA     = core_rdata;

endmodule : bus_matrix_ahb_tgt
