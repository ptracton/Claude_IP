// bus_matrix_axi_master.sv — Non-synthesizable AXI4-Lite master BFM for bus_matrix testing.
//
// Drives AXI4-Lite transactions.
// Write FSM: IDLE → AW_W_PHASE → B_PHASE → DONE
// Read  FSM: IDLE → AR_PHASE   → R_PHASE → DONE

`ifndef BUS_MATRIX_AXI_MASTER_SV
`define BUS_MATRIX_AXI_MASTER_SV

module bus_matrix_axi_master #(
  parameter int DATA_W = 32, // data bus width
  parameter int ADDR_W = 32  // address width
) (
  input  logic              clk,      // system clock
  input  logic              rst_n,    // synchronous active-low reset

  // AXI4-Lite slave port (connects to bus_matrix M_* ports)
  // Write address channel
  output logic              AWVALID,                     // write address valid
  input  logic              AWREADY,                     // write address ready
  output logic [ADDR_W-1:0] AWADDR,                      // write address
  // Write data channel
  output logic              WVALID,                      // write data valid
  input  logic              WREADY,                      // write data ready
  output logic [DATA_W-1:0] WDATA,                       // write data
  output logic [DATA_W/8-1:0] WSTRB,                     // byte enables
  // Write response channel
  input  logic              BVALID,                      // write response valid
  output logic              BREADY,                      // write response ready
  input  logic [1:0]        BRESP,                       // write response
  // Read address channel
  output logic              ARVALID,                     // read address valid
  input  logic              ARREADY,                     // read address ready
  output logic [ADDR_W-1:0] ARADDR,                      // read address
  // Read data channel
  input  logic              RVALID,                      // read data valid
  output logic              RREADY,                      // read data ready
  input  logic [DATA_W-1:0] RDATA,                       // read data
  input  logic [1:0]        RRESP,                       // read response

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

  typedef enum logic [2:0] {
    ST_IDLE    = 3'b000,
    ST_AW_W    = 3'b001,  // present AW and W channels
    ST_B       = 3'b010,  // wait for write response
    ST_AR      = 3'b011,  // present AR channel
    ST_R       = 3'b100,  // wait for read data
    ST_DONE    = 3'b101
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
            if (req_write) state_q <= ST_AW_W;
            else           state_q <= ST_AR;
          end
        end

        ST_AW_W: begin
          // Present AW and W; move on when both accepted
          if (AWREADY && WREADY) begin
            state_q <= ST_B;
          end
        end

        ST_B: begin
          if (BVALID) begin
            error   <= (BRESP != 2'b00);
            done    <= 1'b1;
            state_q <= ST_DONE;
          end
        end

        ST_AR: begin
          if (ARREADY) begin
            state_q <= ST_R;
          end
        end

        ST_R: begin
          if (RVALID) begin
            rdata   <= RDATA;
            error   <= (RRESP != 2'b00);
            done    <= 1'b1;
            state_q <= ST_DONE;
          end
        end

        ST_DONE: begin
          // Handle back-to-back: if req arrives while in DONE, latch it and
          // skip ST_IDLE so the next transaction starts immediately.
          if (req) begin
            addr_q  <= req_addr;
            write_q <= req_write;
            wdata_q <= req_wdata;
            strb_q  <= req_strb;
            if (req_write) state_q <= ST_AW_W;
            else           state_q <= ST_AR;
          end else begin
            state_q <= ST_IDLE;
          end
        end

        default: state_q <= ST_IDLE;
      endcase
    end
  end

  // AXI channel drive
  always_comb begin : p_axi_out
    AWVALID = 1'b0;
    AWADDR  = {ADDR_W{1'b0}};
    WVALID  = 1'b0;
    WDATA   = {DATA_W{1'b0}};
    WSTRB   = {(DATA_W/8){1'b0}};
    BREADY  = 1'b0;
    ARVALID = 1'b0;
    ARADDR  = {ADDR_W{1'b0}};
    RREADY  = 1'b0;

    case (state_q)
      ST_AW_W: begin
        AWVALID = 1'b1;
        AWADDR  = addr_q;
        WVALID  = 1'b1;
        WDATA   = wdata_q;
        WSTRB   = strb_q;
      end

      ST_B: begin
        BREADY = 1'b1;
      end

      ST_AR: begin
        ARVALID = 1'b1;
        ARADDR  = addr_q;
      end

      ST_R: begin
        RREADY = 1'b1;
      end

      default: begin end
    endcase
  end

endmodule : bus_matrix_axi_master

`endif // BUS_MATRIX_AXI_MASTER_SV
