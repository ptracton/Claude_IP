// bus_matrix_ahb_ini.sv — AHB-Lite initiator adapter for one bus matrix slave port.
//
// Acts as an AHB-Lite master towards the external slave and runs exactly one
// single transfer for each core request.
//
//   Address phase: presented (HSEL, HTRANS=NONSEQ) while idle and req is
//     high; held until the slave's HREADY is high.
//   Data phase:    HTRANS=IDLE, HWDATA/HWSTRB driven from the core; done
//     pulses in the cycle the slave raises HREADY, with HRDATA and HRESP.
//   HSIZE is rebuilt from core_be (the target adapter's lane mask) and
//     HADDR: the naturally aligned block of 2**k lanes holding the address
//     gives HSIZE = k; any other mask (a full word, or write strobes that do
//     not form that block) gives the bus size, with the lanes in HWSTRB.
//     HADDR is aligned to HSIZE (the low address bits below HSIZE are
//     cleared), so a bus-size fallback for a sub-word transfer with sparse
//     strobes is a legal, word-aligned transfer.
//
// The core keeps req high until done and drops it on the following cycle,
// so a new address phase is never started for a finished request.

module bus_matrix_ahb_ini #(
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

  // AHB-Lite master interface (towards the external slave)
  output logic                  HSEL,   // slave select
  output logic [ADDR_W-1:0]     HADDR,  // byte address
  output logic [1:0]            HTRANS, // transfer type
  output logic                  HWRITE, // 1 = write
  output logic [2:0]            HSIZE,  // transfer size, 2**HSIZE bytes
  output logic [DATA_W-1:0]     HWDATA, // write data (data phase)
  output logic [DATA_W/8-1:0]   HWSTRB, // byte strobes (data phase)
  input  logic [DATA_W-1:0]     HRDATA, // read data
  input  logic                  HREADY, // transfer done
  input  logic                  HRESP   // 1 = ERROR
);

  localparam logic [1:0] HTRANS_IDLE   = 2'b00;
  localparam logic [1:0] HTRANS_NONSEQ = 2'b10;

  localparam int unsigned StrbW = DATA_W / 8;
  localparam logic [2:0]  BusSize = (StrbW > 1) ? 3'($clog2(StrbW)) : 3'd0;

  // Byte-offset width (at least 1 bit so the vectors stay legal for DATA_W = 8).
  localparam int unsigned OffW = (StrbW > 1) ? $clog2(StrbW) : 1;

  // be_size — HSIZE of a lane mask at byte offset `offset`: k when the mask
  // is the naturally aligned block of 2**k lanes holding the offset (as the
  // target adapter built it from the master's HSIZE), otherwise the bus size
  // (a full mask, or write strobes that do not form such a block).
  function automatic logic [2:0] be_size(logic [StrbW-1:0] be, logic [OffW-1:0] offset);
    logic [2:0] size;
    size = BusSize;
    for (int unsigned k = 0; (1 << k) < StrbW; k++) begin
      for (int unsigned base = 0; base + (1 << k) <= StrbW; base += (1 << k)) begin
        if (be == StrbW'(((1 << (1 << k)) - 1) << base) &&
            (int'(offset) >> k) == (base >> k)) begin
          size = 3'(k);
        end
      end
    end
    be_size = size;  // not "return": Yosys 0.60 cannot parse it
  endfunction

  logic       dphase_q; // data phase in progress
  logic       aphase;   // address phase presented this cycle
  logic [2:0] size;     // HSIZE of this transfer

  assign aphase = core_req & ~dphase_q;

  always_ff @(posedge clk) begin : p_dphase
    if (!rst_n) begin
      dphase_q <= 1'b0;
    end else if (HREADY) begin
      dphase_q <= aphase;
    end
  end

  assign HSEL   = aphase;
  assign HTRANS = aphase ? HTRANS_NONSEQ : HTRANS_IDLE;
  assign size   = be_size(core_be, core_addr[OffW-1:0]);

  // HADDR aligned to 2**size bytes
  always_comb begin : p_haddr
    HADDR = core_addr;
    for (int unsigned b = 0; b < OffW; b++) begin
      if (b < 32'(size)) begin
        HADDR[b] = 1'b0;
      end
    end
  end

  assign HWRITE = core_we;
  assign HSIZE  = size;
  assign HWDATA = core_wdata;
  assign HWSTRB = core_we ? core_be : '0;

  assign core_done  = dphase_q & HREADY;
  assign core_rdata = HRDATA;
  assign core_err   = HRESP;

endmodule : bus_matrix_ahb_ini
