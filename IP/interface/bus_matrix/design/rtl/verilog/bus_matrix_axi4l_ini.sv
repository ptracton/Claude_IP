// bus_matrix_axi4l_ini.sv — AXI4-Lite initiator adapter for one bus matrix slave port.
//
// Acts as an AXI4-Lite master towards the external slave and runs exactly one
// transaction for each core request:
//   Write: AWVALID and WVALID rise together and each drops after its own
//     handshake; BREADY is high for the whole write and done pulses with
//     BVALID.
//   Read:  ARVALID until its handshake; RREADY is high for the whole read and
//     done pulses with RVALID.
// err is BRESP[1] / RRESP[1] (SLVERR or DECERR from the slave).

module bus_matrix_axi4l_ini #(
  parameter int unsigned DATA_W = 32, // data bus width
  parameter int unsigned ADDR_W = 32  // address width
) (
  input  logic                  clk,   // system clock
  input  logic                  rst_n, // synchronous active-low reset

  // Core handshake
  input  logic                  core_req,   // run one transaction
  input  logic [ADDR_W-1:0]     core_addr,  // byte address
  input  logic [DATA_W-1:0]     core_wdata, // write data
  input  logic                  core_we,    // 1 = write
  input  logic [DATA_W/8-1:0]   core_be,    // byte enables
  output logic                  core_done,  // one-cycle completion
  output logic [DATA_W-1:0]     core_rdata, // read data (valid with done)
  output logic                  core_err,   // error (valid with done)

  // AXI4-Lite master interface (towards the external slave)
  output logic                  AWVALID, // write address valid
  input  logic                  AWREADY, // write address ready
  output logic [ADDR_W-1:0]     AWADDR,  // write byte address
  output logic                  WVALID,  // write data valid
  input  logic                  WREADY,  // write data ready
  output logic [DATA_W-1:0]     WDATA,   // write data
  output logic [DATA_W/8-1:0]   WSTRB,   // write byte strobes
  input  logic                  BVALID,  // write response valid
  output logic                  BREADY,  // write response ready
  input  logic [1:0]            BRESP,   // write response
  output logic                  ARVALID, // read address valid
  input  logic                  ARREADY, // read address ready
  output logic [ADDR_W-1:0]     ARADDR,  // read byte address
  input  logic                  RVALID,  // read data valid
  output logic                  RREADY,  // read data ready
  input  logic [DATA_W-1:0]     RDATA,   // read data
  input  logic [1:0]            RRESP    // read response
);

  typedef enum logic [1:0] {
    IniIdle  = 2'b00,
    IniWrite = 2'b01,
    IniRead  = 2'b10
  } ini_e;

  ini_e state_q, state_d;
  logic aw_ok_q, aw_ok_d; // AW handshake done
  logic w_ok_q,  w_ok_d;  // W handshake done
  logic ar_ok_q, ar_ok_d; // AR handshake done
  logic in_write, in_read;

  assign in_write = (state_q == IniWrite);
  assign in_read  = (state_q == IniRead);

  assign AWVALID = in_write & ~aw_ok_q;
  assign WVALID  = in_write & ~w_ok_q;
  assign BREADY  = in_write;
  assign ARVALID = in_read & ~ar_ok_q;
  assign RREADY  = in_read;

  assign AWADDR = core_addr;
  assign ARADDR = core_addr;
  assign WDATA  = core_wdata;
  assign WSTRB  = core_be;

  // Handshake-done flags: set by READY while in the owning state, cleared in idle.
  assign aw_ok_d = in_write & (aw_ok_q | AWREADY);
  assign w_ok_d  = in_write & (w_ok_q  | WREADY);
  assign ar_ok_d = in_read  & (ar_ok_q | ARREADY);

  always_comb begin : p_next
    state_d = state_q;
    unique case (state_q)
      IniIdle:  if (core_req) state_d = core_we ? IniWrite : IniRead;
      IniWrite: if (BVALID)   state_d = IniIdle;
      IniRead:  if (RVALID)   state_d = IniIdle;
      default:                state_d = IniIdle;
    endcase
  end

  always_ff @(posedge clk) begin : p_state
    if (!rst_n) begin
      state_q <= IniIdle;
      aw_ok_q <= 1'b0;
      w_ok_q  <= 1'b0;
      ar_ok_q <= 1'b0;
    end else begin
      state_q <= state_d;
      aw_ok_q <= aw_ok_d;
      w_ok_q  <= w_ok_d;
      ar_ok_q <= ar_ok_d;
    end
  end

  assign core_done  = (in_write & BVALID) | (in_read & RVALID);
  assign core_err   = in_write ? BRESP[1] : RRESP[1];
  assign core_rdata = RDATA;

endmodule : bus_matrix_axi4l_ini
