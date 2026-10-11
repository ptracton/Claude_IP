// bus_matrix_apb_fv.sv — VC Formal top-level checker for bus_matrix_apb (SV and VHDL).
//
// Bound to bus_matrix_apb by bus_matrix_apb_fv_bind. Uses only the top-level ports.
//
//   u_mst[i]  shared claude_apb_fv on master port i: the external master is
//             the environment (its rules are assumed), the matrix must obey
//             the slave rules, answering within M_WAIT cycles.
//   u_slv[j]  shared claude_apb_fv on slave port j with MASTER_IS_ENV=0: the
//             external slave is the environment (answers within S_WAIT
//             cycles), the matrix must obey the master rules.
//   a_e2e_write  a write that completes at slave j was in progress at some
//                master with the same word address, data and strobes
//   a_slv_region_wr / a_slv_region_rd  slave j only completes transfers
//                inside its own region (so decode errors never reach a slave)
// The observers report word addresses: ADDR_W = 30 keeps HADDR[31:2].

module bus_matrix_apb_fv #(
  parameter int unsigned NUM_MASTERS = 2,
  parameter int unsigned NUM_SLAVES  = 4,
  parameter logic [NUM_SLAVES*32-1:0] S_BASE = '0,
  parameter logic [NUM_SLAVES*32-1:0] S_MASK = '0,
  parameter int unsigned M_WAIT = 64, // master-port response bound
  parameter int unsigned S_WAIT = 4   // assumed slave response bound
) (
  input  logic clk,
  input  logic rst_n,
  input  logic [NUM_MASTERS-1:0] M_PSEL,
  input  logic [NUM_MASTERS-1:0] M_PENABLE,
  input  logic [NUM_MASTERS*32-1:0] M_PADDR,
  input  logic [NUM_MASTERS-1:0] M_PWRITE,
  input  logic [NUM_MASTERS*32-1:0] M_PWDATA,
  input  logic [NUM_MASTERS*4-1:0] M_PSTRB,
  input  logic [NUM_MASTERS*32-1:0] M_PRDATA,
  input  logic [NUM_MASTERS-1:0] M_PREADY,
  input  logic [NUM_MASTERS-1:0] M_PSLVERR,
  input  logic [NUM_SLAVES-1:0] S_PSEL,
  input  logic [NUM_SLAVES-1:0] S_PENABLE,
  input  logic [NUM_SLAVES*32-1:0] S_PADDR,
  input  logic [NUM_SLAVES-1:0] S_PWRITE,
  input  logic [NUM_SLAVES*32-1:0] S_PWDATA,
  input  logic [NUM_SLAVES*4-1:0] S_PSTRB,
  input  logic [NUM_SLAVES*32-1:0] S_PRDATA,
  input  logic [NUM_SLAVES-1:0] S_PREADY,
  input  logic [NUM_SLAVES-1:0] S_PSLVERR
);

  localparam int unsigned DW = 32;
  localparam int unsigned AW = 32;
  localparam int unsigned SW = DW / 8;
  localparam int unsigned OW = AW - 2; // observer word-address width

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
    claude_apb_fv #(
      .DATA_W        (DW),
      .ADDR_W        (OW),
      .PADDR_W       (AW),
      .MASTER_IS_ENV (1),
      .MAX_WAIT      (M_WAIT)
    ) u_bus (
      .PCLK        (clk),
      .PRESETn     (rst_n),
      .PSEL        (M_PSEL[gi]),
      .PENABLE     (M_PENABLE[gi]),
      .PADDR       (M_PADDR[gi*AW+:AW]),
      .PWRITE      (M_PWRITE[gi]),
      .PWDATA      (M_PWDATA[gi*DW+:DW]),
      .PSTRB       (M_PSTRB[gi*SW+:SW]),
      .PRDATA      (M_PRDATA[gi*DW+:DW]),
      .PREADY      (M_PREADY[gi]),
      .PSLVERR     (M_PSLVERR[gi]),
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
    claude_apb_fv #(
      .DATA_W        (DW),
      .ADDR_W        (OW),
      .PADDR_W       (AW),
      .MASTER_IS_ENV (0),
      .MAX_WAIT      (S_WAIT)
    ) u_bus (
      .PCLK        (clk),
      .PRESETn     (rst_n),
      .PSEL        (S_PSEL[gj]),
      .PENABLE     (S_PENABLE[gj]),
      .PADDR       (S_PADDR[gj*AW+:AW]),
      .PWRITE      (S_PWRITE[gj]),
      .PWDATA      (S_PWDATA[gj*DW+:DW]),
      .PSTRB       (S_PSTRB[gj*SW+:SW]),
      .PRDATA      (S_PRDATA[gj*DW+:DW]),
      .PREADY      (S_PREADY[gj]),
      .PSLVERR     (S_PSLVERR[gj]),
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
            m_wr_strb[i] == s_wr_strb[gj]) begin
          from_master = 1'b1;
        end
      end
    end
    a_e2e_write:     assert property (s_wr_vld[gj] |-> from_master);
    a_slv_region_wr: assert property (s_wr_vld[gj] |-> in_region(gj, s_wr_addr[gj]));
    a_slv_region_rd: assert property (s_rd_vld[gj] |-> in_region(gj, s_rd_addr[gj]));
  end

endmodule : bus_matrix_apb_fv
