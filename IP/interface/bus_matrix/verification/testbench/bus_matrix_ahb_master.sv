// bus_matrix_ahb_master.sv — Non-synthesizable AHB master BFM for bus_matrix testing.
//
// Drives sequential AHB transactions on behalf of the testbench.
// FSM: IDLE → ADDRESS_PHASE → DATA_PHASE → DONE

`ifndef BUS_MATRIX_AHB_MASTER_SV
`define BUS_MATRIX_AHB_MASTER_SV

module bus_matrix_ahb_master #(
  parameter int DATA_W = 32, // data bus width
  parameter int ADDR_W = 32  // address width
) (
  input  logic              clk,       // system clock
  input  logic              rst_n,     // synchronous active-low reset

  // AHB slave port (connects to bus_matrix M_* ports)
  output logic              HSEL,                       // slave select
  output logic [ADDR_W-1:0] HADDR,                      // address
  output logic [1:0]        HTRANS,                     // transfer type
  output logic              HWRITE,                     // 1=write, 0=read
  output logic [DATA_W-1:0] HWDATA,                     // write data
  output logic [DATA_W/8-1:0] HWSTRB,                   // byte enables
  input  logic              HREADY,                     // ready from matrix
  input  logic [DATA_W-1:0] HRDATA,                     // read data from matrix
  input  logic              HRESP,                      // error response from matrix

  // Control interface (testbench drives these)
  input  logic              req,                        // initiate a transaction
  input  logic [ADDR_W-1:0] req_addr,                   // target address
  input  logic              req_write,                  // 1=write, 0=read
  input  logic [DATA_W-1:0] req_wdata,                  // write data
  input  logic [DATA_W/8-1:0] req_strb,                 // byte enables
  output logic              done,                       // transaction complete
  output logic [DATA_W-1:0] rdata,                      // captured read data
  output logic              error                       // error response received
);

  // AHB HTRANS encodings
  localparam logic [1:0] AHB_IDLE   = 2'b00;
  localparam logic [1:0] AHB_NONSEQ = 2'b10;

  // FSM state
  typedef enum logic [1:0] {
    ST_IDLE    = 2'b00,
    ST_ADDR    = 2'b01,
    ST_DATA    = 2'b10,
    ST_DONE    = 2'b11
  } state_t;

  state_t      state_q;
  logic [ADDR_W-1:0] addr_q;   // latched address
  logic              write_q;  // latched write flag
  logic [DATA_W-1:0] wdata_q;  // latched write data
  logic [DATA_W/8-1:0] strb_q; // latched byte enables

  always_ff @(posedge clk) begin : p_fsm
    if (!rst_n) begin
      state_q  <= ST_IDLE;
      addr_q   <= {ADDR_W{1'b0}};
      write_q  <= 1'b0;
      wdata_q  <= {DATA_W{1'b0}};
      strb_q   <= {(DATA_W/8){1'b0}};
      rdata    <= {DATA_W{1'b0}};
      error    <= 1'b0;
      done     <= 1'b0;
    end else begin
      done <= 1'b0; // pulse for one cycle
      case (state_q)
        ST_IDLE: begin
          if (req) begin
            // Latch request parameters
            addr_q  <= req_addr;
            write_q <= req_write;
            wdata_q <= req_wdata;
            strb_q  <= req_strb;
            state_q <= ST_ADDR;
          end
        end

        ST_ADDR: begin
          // Address phase presented; wait for HREADY to move to data phase
          if (HREADY) begin
            state_q <= ST_DATA;
          end
        end

        ST_DATA: begin
          // Data phase: wait for HREADY
          if (HREADY) begin
            rdata   <= HRDATA;
            error   <= HRESP;
            done    <= 1'b1;
            state_q <= ST_DONE;
          end
        end

        ST_DONE: begin
          // Return to idle; done already pulsed.
          // Handle back-to-back: if req arrives in the same cycle done fires,
          // latch it now and skip ST_IDLE so the transaction starts immediately.
          if (req) begin
            addr_q  <= req_addr;
            write_q <= req_write;
            wdata_q <= req_wdata;
            strb_q  <= req_strb;
            state_q <= ST_ADDR;
          end else begin
            state_q <= ST_IDLE;
          end
        end

        default: state_q <= ST_IDLE;
      endcase
    end
  end

  // AHB output drive
  always_comb begin : p_ahb_out
    HSEL   = 1'b0;
    HADDR  = {ADDR_W{1'b0}};
    HTRANS = AHB_IDLE;
    HWRITE = 1'b0;
    HWDATA = {DATA_W{1'b0}};
    HWSTRB = {(DATA_W/8){1'b0}};

    case (state_q)
      ST_ADDR: begin
        HSEL   = 1'b1;
        HADDR  = addr_q;
        HTRANS = AHB_NONSEQ;
        HWRITE = write_q;
        HWSTRB = strb_q;
      end

      ST_DATA: begin
        HSEL   = 1'b0;
        HTRANS = AHB_IDLE;
        HWRITE = write_q;
        HWDATA = wdata_q;
        HWSTRB = strb_q;
      end

      default: begin
        // ST_IDLE, ST_DONE: all idle
      end
    endcase
  end

endmodule : bus_matrix_ahb_master

`endif // BUS_MATRIX_AHB_MASTER_SV
