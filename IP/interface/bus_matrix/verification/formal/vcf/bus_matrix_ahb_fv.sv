// bus_matrix_ahb_fv.sv — VC Formal top-level checker for bus_matrix_ahb (SV and VHDL).
//
// Bound to bus_matrix_ahb by bus_matrix_ahb_fv_bind. Uses only the top-level ports.
//
//   u_mst[i]  shared claude_ahb_fv on master port i: the external master is
//             the environment (its rules are assumed), the matrix must obey
//             the slave rules, answering within M_WAIT cycles.
//   u_slv[j]  shared claude_ahb_fv on slave port j with MASTER_IS_ENV=0: the
//             external slave is the environment (answers within S_WAIT
//             cycles), the matrix must obey the master rules.
//   HSIZE (not in the shared checker, handled here):
//     am_hsize_*   master ports: the master's HSIZE is at most the bus size,
//                  HADDR is aligned to it, and it is held with the address
//     a_hsize_*    slave ports: the matrix obeys the same rules, and write
//                  strobes stay inside the transfer's byte lanes
//   a_e2e_write  a write that completes at slave j was in progress at some
//                master with the same word address, data and strobes; a
//                master's strobes are its HWSTRB limited to the lanes of
//                its HSIZE (the bytes the matrix may write)
//   a_e2e_rd_lanes  a read at slave j covers the same byte lanes as a read
//                in progress at some master with the same word address
//   a_slv_region_wr / a_slv_region_rd  slave j only completes transfers
//                inside its own region (so decode errors never reach a slave)
// The observers report word addresses: ADDR_W = 30 keeps HADDR[31:2].

module bus_matrix_ahb_fv #(
  parameter int unsigned NUM_MASTERS = 2,
  parameter int unsigned NUM_SLAVES  = 4,
  parameter logic [NUM_SLAVES*32-1:0] S_BASE = '0,
  parameter logic [NUM_SLAVES*32-1:0] S_MASK = '0,
  parameter int unsigned M_WAIT = 64, // master-port response bound
  parameter int unsigned S_WAIT = 4   // assumed slave response bound
) (
  input  logic clk,
  input  logic rst_n,
  input  logic [NUM_MASTERS-1:0] M_HSEL,
  input  logic [NUM_MASTERS*32-1:0] M_HADDR,
  input  logic [NUM_MASTERS*2-1:0] M_HTRANS,
  input  logic [NUM_MASTERS-1:0] M_HWRITE,
  input  logic [NUM_MASTERS*3-1:0] M_HSIZE,
  input  logic [NUM_MASTERS*32-1:0] M_HWDATA,
  input  logic [NUM_MASTERS*4-1:0] M_HWSTRB,
  input  logic [NUM_MASTERS*32-1:0] M_HRDATA,
  input  logic [NUM_MASTERS-1:0] M_HREADY,
  input  logic [NUM_MASTERS-1:0] M_HRESP,
  input  logic [NUM_SLAVES-1:0] S_HSEL,
  input  logic [NUM_SLAVES*32-1:0] S_HADDR,
  input  logic [NUM_SLAVES*2-1:0] S_HTRANS,
  input  logic [NUM_SLAVES-1:0] S_HWRITE,
  input  logic [NUM_SLAVES*3-1:0] S_HSIZE,
  input  logic [NUM_SLAVES*32-1:0] S_HWDATA,
  input  logic [NUM_SLAVES*4-1:0] S_HWSTRB,
  input  logic [NUM_SLAVES*32-1:0] S_HRDATA,
  input  logic [NUM_SLAVES-1:0] S_HREADY,
  input  logic [NUM_SLAVES-1:0] S_HRESP
);

  localparam int unsigned DW = 32;
  localparam int unsigned AW = 32;
  localparam int unsigned SW = DW / 8;
  localparam int unsigned OW = AW - 2; // observer word-address width
  localparam logic [2:0]  BUS_SIZE = 3'd2; // 4-byte bus

  // Byte lanes of a 2**size-byte transfer at byte offset `off`
  function automatic logic [SW-1:0] lane_mask(input logic [2:0] size, input logic [1:0] off);
    logic [SW-1:0] m;
    for (int unsigned b = 0; b < SW; b++) begin
      m[b] = ((2'(b) >> size) == (off >> size));
    end
    return m;
  endfunction

  // HADDR aligned to 2**size bytes
  function automatic logic aligned(input logic [2:0] size, input logic [1:0] off);
    return (size == 3'd0) || (size == 3'd1 && !off[0]) || (size == 3'd2 && off == 2'b00);
  endfunction

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // Observer streams, one per port
  logic [NUM_MASTERS-1:0]    m_wr_vld, m_wr_busy, m_rd_req, m_rd_vld;
  logic [OW-1:0]     m_wr_addr [NUM_MASTERS];
  logic [OW-1:0]     m_rd_addr [NUM_MASTERS];
  logic [DW-1:0]     m_wr_data [NUM_MASTERS];
  logic [DW-1:0]     m_rd_data [NUM_MASTERS];
  logic [SW-1:0]     m_wr_strb [NUM_MASTERS];
  logic [NUM_SLAVES-1:0]    s_wr_vld, s_wr_busy, s_rd_req, s_rd_vld;
  logic [OW-1:0]     s_wr_addr [NUM_SLAVES];
  logic [OW-1:0]     s_rd_addr [NUM_SLAVES];
  logic [DW-1:0]     s_wr_data [NUM_SLAVES];
  logic [DW-1:0]     s_rd_data [NUM_SLAVES];
  logic [SW-1:0]     s_wr_strb [NUM_SLAVES];

  for (genvar gi = 0; gi < NUM_MASTERS; gi++) begin : g_mst
    claude_ahb_fv #(
      .DATA_W        (DW),
      .ADDR_W        (OW),
      .HADDR_W       (AW),
      .MASTER_IS_ENV (1),
      .MAX_WAIT      (M_WAIT)
    ) u_bus (
      .HCLK        (clk),
      .HRESETn     (rst_n),
      .HSEL        (M_HSEL[gi]),
      .HADDR       (M_HADDR[gi*AW+:AW]),
      .HTRANS      (M_HTRANS[gi*2+:2]),
      .HWRITE      (M_HWRITE[gi]),
      .HWDATA      (M_HWDATA[gi*DW+:DW]),
      .HWSTRB      (M_HWSTRB[gi*SW+:SW]),
      .HRDATA      (M_HRDATA[gi*DW+:DW]),
      .HREADY      (M_HREADY[gi]),
      .HRESP       (M_HRESP[gi]),
      .obs_wr_vld  (m_wr_vld[gi]),
      .obs_wr_addr (m_wr_addr[gi]),
      .obs_wr_data (m_wr_data[gi]),
      .obs_wr_strb (m_wr_strb[gi]),
      .obs_wr_busy (m_wr_busy[gi]),
      .obs_rd_req  (m_rd_req[gi]),
      .obs_rd_vld  (m_rd_vld[gi]),
      .obs_rd_addr (m_rd_addr[gi]),
      .obs_rd_data (m_rd_data[gi])
    );
  end

  for (genvar gj = 0; gj < NUM_SLAVES; gj++) begin : g_slv
    claude_ahb_fv #(
      .DATA_W        (DW),
      .ADDR_W        (OW),
      .HADDR_W       (AW),
      .MASTER_IS_ENV (0),
      .MAX_WAIT      (S_WAIT)
    ) u_bus (
      .HCLK        (clk),
      .HRESETn     (rst_n),
      .HSEL        (S_HSEL[gj]),
      .HADDR       (S_HADDR[gj*AW+:AW]),
      .HTRANS      (S_HTRANS[gj*2+:2]),
      .HWRITE      (S_HWRITE[gj]),
      .HWDATA      (S_HWDATA[gj*DW+:DW]),
      .HWSTRB      (S_HWSTRB[gj*SW+:SW]),
      .HRDATA      (S_HRDATA[gj*DW+:DW]),
      .HREADY      (S_HREADY[gj]),
      .HRESP       (S_HRESP[gj]),
      .obs_wr_vld  (s_wr_vld[gj]),
      .obs_wr_addr (s_wr_addr[gj]),
      .obs_wr_data (s_wr_data[gj]),
      .obs_wr_strb (s_wr_strb[gj]),
      .obs_wr_busy (s_wr_busy[gj]),
      .obs_rd_req  (s_rd_req[gj]),
      .obs_rd_vld  (s_rd_vld[gj]),
      .obs_rd_addr (s_rd_addr[gj]),
      .obs_rd_data (s_rd_data[gj])
    );
  end

  // ---------------------------------------------------------------------
  // HSIZE: per-port data-phase lane masks and the HSIZE rules
  // ---------------------------------------------------------------------
  logic [SW-1:0] m_lanes_q [NUM_MASTERS]; // lanes of the master's data phase
  logic [SW-1:0] s_lanes_q [NUM_SLAVES];  // lanes of the slave's data phase
  logic [SW-1:0] m_eff_strb [NUM_MASTERS]; // bytes the master's write may change
  logic [NUM_MASTERS-1:0] m_rd_busy;       // master read data phase in progress

  for (genvar gi = 0; gi < NUM_MASTERS; gi++) begin : g_mst_size
    logic [2:0] sz;
    logic [1:0] off;
    logic       ap;
    assign sz  = M_HSIZE[gi*3+:3];
    assign off = M_HADDR[gi*AW+:2];
    assign ap  = M_HSEL[gi] && M_HTRANS[gi*2+1];
    always_ff @(posedge clk) begin
      if (!rst_n) begin
        m_lanes_q[gi] <= '0;
        m_rd_busy[gi] <= 1'b0;
      end else if (M_HREADY[gi]) begin
        m_lanes_q[gi] <= ap ? lane_mask(sz, off) : '0;
        m_rd_busy[gi] <= ap && !M_HWRITE[gi];
      end
    end
    assign m_eff_strb[gi] = m_lanes_q[gi] & m_wr_strb[gi];

    am_hsize_max:     assume property (ap |-> sz <= BUS_SIZE);
    am_hsize_aligned: assume property (ap |-> aligned(sz, off));
    am_hsize_hold:    assume property ((ap && !M_HREADY[gi]) |=> $stable(sz));
  end

  for (genvar gj = 0; gj < NUM_SLAVES; gj++) begin : g_slv_size
    logic [2:0] sz;
    logic [1:0] off;
    logic       ap;
    logic       dwr_q; // data phase is a write
    assign sz  = S_HSIZE[gj*3+:3];
    assign off = S_HADDR[gj*AW+:2];
    assign ap  = S_HSEL[gj] && S_HTRANS[gj*2+1];
    always_ff @(posedge clk) begin
      if (!rst_n) begin
        s_lanes_q[gj] <= '0;
        dwr_q         <= 1'b0;
      end else if (S_HREADY[gj]) begin
        s_lanes_q[gj] <= ap ? lane_mask(sz, off) : '0;
        dwr_q         <= ap && S_HWRITE[gj];
      end
    end

    a_hsize_max:     assert property (ap |-> sz <= BUS_SIZE);
    a_hsize_aligned: assert property (ap |-> aligned(sz, off));
    a_hsize_hold:    assert property ((ap && !S_HREADY[gj]) |=> $stable(sz));
    a_hsize_strb:    assert property (dwr_q |-> (S_HWSTRB[gj*SW+:SW] & ~s_lanes_q[gj]) == '0);
    c_hsize_byte:    cover property (s_wr_vld[gj] && s_lanes_q[gj] == 4'b0010);
    c_hsize_half:    cover property (s_rd_vld[gj] && s_lanes_q[gj] == 4'b1100);
    c_hsize_sparse:  cover property (s_wr_vld[gj] && s_lanes_q[gj] == 4'b1111 &&
                                     s_wr_strb[gj] == 4'b0101);
  end

  // Word address w lies in slave j's region
  function automatic logic in_region(input int j, input logic [OW-1:0] w);
    logic [31:0] a;
    a = {w, 2'b00};
    return (a & S_MASK[j*32+:32]) == (S_BASE[j*32+:32] & S_MASK[j*32+:32]);
  endfunction

  for (genvar gj = 0; gj < NUM_SLAVES; gj++) begin : g_e2e
    logic from_master;
    always_comb begin
      from_master = 1'b0;
      for (int i = 0; i < NUM_MASTERS; i++) begin
        if ((m_wr_busy[i] || m_wr_vld[i]) &&
            m_wr_addr[i] == s_wr_addr[gj] &&
            m_wr_data[i] == s_wr_data[gj] &&
            m_eff_strb[i] == s_wr_strb[gj]) begin
          from_master = 1'b1;
        end
      end
    end
    logic rd_lanes_ok; // a master is reading this word with the same lanes
    always_comb begin
      rd_lanes_ok = 1'b0;
      for (int i = 0; i < NUM_MASTERS; i++) begin
        if (m_rd_busy[i] && m_rd_addr[i] == s_rd_addr[gj] &&
            m_lanes_q[i] == s_lanes_q[gj]) begin
          rd_lanes_ok = 1'b1;
        end
      end
    end
    a_e2e_write:     assert property (s_wr_vld[gj] |-> from_master);
    a_e2e_rd_lanes:  assert property (s_rd_vld[gj] |-> rd_lanes_ok);
    a_slv_region_wr: assert property (s_wr_vld[gj] |-> in_region(gj, s_wr_addr[gj]));
    a_slv_region_rd: assert property (s_rd_vld[gj] |-> in_region(gj, s_rd_addr[gj]));
  end

endmodule : bus_matrix_ahb_fv
