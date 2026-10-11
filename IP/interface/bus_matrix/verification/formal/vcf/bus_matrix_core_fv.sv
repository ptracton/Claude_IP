// bus_matrix_core_fv.sv — VC Formal properties for bus_matrix_core.
//
// Bound to bus_matrix_core (SV module or VHDL entity) by the
// bus_matrix_<proto>_fv_bind modules. Uses only the core's ports, so it is
// language-neutral. The address decode is restated here from S_BASE/S_MASK
// (lowest matching slave wins).
//
//   a_route        a slave request carries the fields of a requesting master
//                  whose address decodes to that slave
//   a_decerr       a request that matches no slave is answered by the core,
//                  with an error, on the next cycle
//   a_done_req     a master only completes while it is requesting
//   a_resp         a slave completion is returned, with its read data and
//                  error flag, to a master that addressed that slave
//   a_no_lost_done every slave completion reaches a master

module bus_matrix_core_fv #(
  parameter int unsigned NUM_MASTERS = 2,
  parameter int unsigned NUM_SLAVES  = 4,
  parameter int unsigned DATA_W      = 32,
  parameter int unsigned ADDR_W      = 32,
  parameter logic [NUM_SLAVES*32-1:0] S_BASE = '0,
  parameter logic [NUM_SLAVES*32-1:0] S_MASK = '0
) (
  input  logic                            clk,
  input  logic                            rst_n,
  input  logic [NUM_MASTERS-1:0]          mst_req,
  input  logic [NUM_MASTERS*ADDR_W-1:0]   mst_addr,
  input  logic [NUM_MASTERS*DATA_W-1:0]   mst_wdata,
  input  logic [NUM_MASTERS-1:0]          mst_we,
  input  logic [NUM_MASTERS*DATA_W/8-1:0] mst_be,
  input  logic [NUM_MASTERS-1:0]          mst_done,
  input  logic [NUM_MASTERS*DATA_W-1:0]   mst_rdata,
  input  logic [NUM_MASTERS-1:0]          mst_err,
  input  logic [NUM_SLAVES-1:0]           slv_req,
  input  logic [NUM_SLAVES*ADDR_W-1:0]    slv_addr,
  input  logic [NUM_SLAVES*DATA_W-1:0]    slv_wdata,
  input  logic [NUM_SLAVES-1:0]           slv_we,
  input  logic [NUM_SLAVES*DATA_W/8-1:0]  slv_be,
  input  logic [NUM_SLAVES-1:0]           slv_done,
  input  logic [NUM_SLAVES*DATA_W-1:0]    slv_rdata,
  input  logic [NUM_SLAVES-1:0]           slv_err
);

  localparam int unsigned SW = DATA_W / 8;

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  function automatic logic [NUM_SLAVES-1:0] decode(input logic [ADDR_W-1:0] a);
    logic [NUM_SLAVES-1:0] sel;
    sel = '0;
    for (int j = NUM_SLAVES - 1; j >= 0; j--) begin
      if ((a & S_MASK[j*32+:32]) == (S_BASE[j*32+:32] & S_MASK[j*32+:32])) begin
        sel = '0;
        sel[j] = 1'b1;
      end
    end
    return sel;
  endfunction

  logic [NUM_SLAVES-1:0] msel [NUM_MASTERS]; // slave selected by master i
  logic [NUM_MASTERS-1:0] mdecerr;            // master i's address matches no slave
  for (genvar gi = 0; gi < NUM_MASTERS; gi++) begin : g_dec
    assign msel[gi]    = decode(mst_addr[gi*ADDR_W+:ADDR_W]);
    assign mdecerr[gi] = (msel[gi] == '0);
  end

  // Slave j carries master i's request fields
  function automatic logic same_req(input int j, input int i);
    return (slv_addr[j*ADDR_W+:ADDR_W]  == mst_addr[i*ADDR_W+:ADDR_W]) &&
           (slv_wdata[j*DATA_W+:DATA_W] == mst_wdata[i*DATA_W+:DATA_W]) &&
           (slv_we[j]                   == mst_we[i]) &&
           (slv_be[j*SW+:SW]            == mst_be[i*SW+:SW]);
  endfunction

  for (genvar gj = 0; gj < NUM_SLAVES; gj++) begin : g_slv
    logic from_master; // some requesting master addressed slave j with these fields
    logic to_master;   // slave j's completion is delivered to such a master
    always_comb begin
      from_master = 1'b0;
      to_master   = 1'b0;
      for (int i = 0; i < NUM_MASTERS; i++) begin
        if (mst_req[i] && msel[i][gj] && same_req(gj, i)) begin
          from_master = 1'b1;
          if (mst_done[i] &&
              mst_rdata[i*DATA_W+:DATA_W] == slv_rdata[gj*DATA_W+:DATA_W] &&
              mst_err[i] == slv_err[gj]) begin
            to_master = 1'b1;
          end
        end
      end
    end
    a_route:        assert property (slv_req[gj] |-> from_master);
    a_no_lost_done: assert property ((slv_req[gj] && slv_done[gj]) |-> to_master);
    c_slv_done:     cover property (slv_req[gj] && slv_done[gj]);
  end

  for (genvar gi = 0; gi < NUM_MASTERS; gi++) begin : g_mst
    logic from_slave; // master i's completion comes from the slave it addressed
    always_comb begin
      from_slave = 1'b0;
      for (int j = 0; j < NUM_SLAVES; j++) begin
        if (msel[gi][j] && slv_req[j] && slv_done[j] && same_req(j, gi) &&
            mst_rdata[gi*DATA_W+:DATA_W] == slv_rdata[j*DATA_W+:DATA_W] &&
            mst_err[gi] == slv_err[j]) begin
          from_slave = 1'b1;
        end
      end
    end
    a_done_req: assert property (mst_done[gi] |-> mst_req[gi]);
    a_decerr:   assert property ((mst_req[gi] && mdecerr[gi] && !mst_done[gi]) |=>
                                 (mst_done[gi] && mst_err[gi]));
    a_resp:     assert property ((mst_done[gi] && !mdecerr[gi]) |-> from_slave);
    c_decerr:   cover property (mst_done[gi] && mdecerr[gi]);
    for (genvar gj = 0; gj < NUM_SLAVES; gj++) begin : g_path
      c_path: cover property (mst_done[gi] && msel[gi][gj]);
    end
  end

  c_parallel:   cover property (slv_done[0] && slv_done[1]);
  c_contention: cover property (mst_req[0] && mst_req[1] && msel[0] == msel[1] && !mdecerr[0]);

endmodule : bus_matrix_core_fv
