// bus_matrix_wb_master.sv — Non-synthesizable Wishbone master BFM for bus_matrix testing.
//
// Drives Wishbone B4 transactions. Asserts CYC+STB, waits for ACK.

`ifndef BUS_MATRIX_WB_MASTER_SV
`define BUS_MATRIX_WB_MASTER_SV

module bus_matrix_wb_master #(
  parameter int DATA_W = 32, // data bus width
  parameter int ADDR_W = 32  // address width
) (
  input  logic              clk,     // system clock
  input  logic              rst_n,   // synchronous active-low reset

  // Wishbone slave port (connects to bus_matrix M_* ports)
  output logic              CYC,                         // bus cycle valid
  output logic              STB,                         // strobe
  output logic              WE,                          // 1=write, 0=read
  output logic [ADDR_W-1:0] ADR,                         // address
  output logic [DATA_W-1:0] DAT_O,                       // write data
  output logic [DATA_W/8-1:0] SEL,                       // byte selects
  input  logic [DATA_W-1:0] DAT_I,                       // read data
  input  logic              ACK,                         // acknowledge
  input  logic              ERR,                         // error

  // Control interface
  input  logic              req,                         // initiate a transaction
  input  logic [ADDR_W-1:0] req_addr,                    // target address
  input  logic              req_write,                   // 1=write, 0=read
  input  logic [DATA_W-1:0] req_wdata,                   // write data
  input  logic [DATA_W/8-1:0] req_strb,                  // byte enables
  output logic              done,                        // transaction complete
  output logic [DATA_W-1:0] rdata,                       // captured read data
  output logic              error                        // error response received
);

  typedef enum logic [1:0] {
    ST_IDLE  = 2'b00,
    ST_TRANS = 2'b01,  // CYC+STB asserted, waiting for ACK
    ST_DONE  = 2'b10
  } state_t;

  state_t          state_q;
  logic [ADDR_W-1:0]   addr_q;
  logic                write_q;
  logic [DATA_W-1:0]   wdata_q;
  logic [DATA_W/8-1:0] strb_q;

  always_ff @(posedge clk) begin : p_fsm
    if (!rst_n) begin
      state_q <= ST_IDLE;
      addr_q  <= {ADDR_W{1'b0}};
      write_q <= 1'b0;
      wdata_q <= {DATA_W{1'b0}};
      strb_q  <= {(DATA_W/8){1'b0}};
      rdata   <= {DATA_W{1'b0}};
      error   <= 1'b0;
      done    <= 1'b0;
    end else begin
      done <= 1'b0;
      case (state_q)
        ST_IDLE: begin
          if (req) begin
            addr_q  <= req_addr;
            write_q <= req_write;
            wdata_q <= req_wdata;
            strb_q  <= req_strb;
            state_q <= ST_TRANS;
          end
        end

        ST_TRANS: begin
          if (ACK) begin
            rdata   <= DAT_I;
            error   <= ERR;
            done    <= 1'b1;
            state_q <= ST_DONE;
          end
        end

        ST_DONE: begin
          // Handle back-to-back: latch next req if it arrives in DONE cycle.
          if (req) begin
            addr_q  <= req_addr;
            write_q <= req_write;
            wdata_q <= req_wdata;
            strb_q  <= req_strb;
            state_q <= ST_TRANS;
          end else begin
            state_q <= ST_IDLE;
          end
        end

        default: state_q <= ST_IDLE;
      endcase
    end
  end

  // Wishbone output drive
  always_comb begin : p_wb_out
    CYC   = 1'b0;
    STB   = 1'b0;
    WE    = 1'b0;
    ADR   = {ADDR_W{1'b0}};
    DAT_O = {DATA_W{1'b0}};
    SEL   = {(DATA_W/8){1'b0}};

    if (state_q == ST_TRANS) begin
      CYC   = 1'b1;
      STB   = 1'b1;
      WE    = write_q;
      ADR   = addr_q;
      DAT_O = wdata_q;
      SEL   = strb_q;
    end
  end

endmodule : bus_matrix_wb_master

`endif // BUS_MATRIX_WB_MASTER_SV
