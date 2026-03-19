// timer_axi4l.sv — AXI4-Lite top-level for Timer IP.
//
// Instantiates timer_axi4l_if, timer_regfile, and timer_core.
// Contains no logic — only port declarations and submodule wiring.
//
// Parameters:
//   DATA_W  : data bus width              (default 32)
//   ADDR_W  : regfile word-address width  (default 4)
//   RST_POL : reset polarity, 0=active-low (default 0; active-low)

module timer_axi4l #(
  parameter int unsigned DATA_W  = 32, // data width
  parameter int unsigned ADDR_W  = 4,  // regfile word-address width
  /* verilator lint_off UNUSEDPARAM */
  parameter int unsigned RST_POL = 0   // 0 = active-low reset; polarity carried by bus pin ARESETn
  /* verilator lint_on UNUSEDPARAM */
) (
  // AXI4-Lite global signals
  input  logic                  ACLK,          // AXI clock
  input  logic                  ARESETn,        // AXI active-low reset

  // Write address channel
  input  logic                  AWVALID,        // master write address valid
  output logic                  AWREADY,        // slave ready
  input  logic [11:0]           AWADDR,         // write byte address

  // Write data channel
  input  logic                  WVALID,         // master write data valid
  output logic                  WREADY,         // slave ready
  input  logic [DATA_W-1:0]     WDATA,          // write data
  input  logic [DATA_W/8-1:0]   WSTRB,          // byte write enables

  // Write response channel
  output logic                  BVALID,         // slave response valid
  input  logic                  BREADY,         // master ready
  output logic [1:0]            BRESP,          // response

  // Read address channel
  input  logic                  ARVALID,        // master read address valid
  output logic                  ARREADY,        // slave ready
  input  logic [11:0]           ARADDR,         // read byte address

  // Read data channel
  output logic                  RVALID,         // slave data valid
  input  logic                  RREADY,         // master ready
  output logic [DATA_W-1:0]     RDATA,          // read data
  output logic [1:0]            RRESP,          // response

  // IP-level outputs
  output logic                  irq,            // masked interrupt
  output logic                  trigger_out     // one-cycle trigger pulse
);

  // -------------------------------------------------------------------------
  // Internal wires between submodules
  // -------------------------------------------------------------------------

  logic                  if_wr_en;
  logic [ADDR_W-1:0]     if_wr_addr;
  logic [DATA_W-1:0]     if_wr_data;
  logic [DATA_W/8-1:0]   if_wr_strb;

  logic                  if_rd_en;
  logic [ADDR_W-1:0]     if_rd_addr;
  logic [DATA_W-1:0]     if_rd_data;

  logic                  ctrl_en;
  logic                  ctrl_mode;
  logic                  ctrl_intr_en;
  logic                  ctrl_trig_en;
  logic [7:0]            ctrl_prescale;
  logic                  ctrl_restart;
  logic                  ctrl_irq_mode;
  logic [DATA_W-1:0]     load_val;
  logic                  status_intr;

  logic [DATA_W-1:0]     hw_count_val;
  logic                  hw_intr_set;
  logic                  hw_ovf_set;
  logic                  hw_active;

  // -------------------------------------------------------------------------
  // Bus interface submodule
  // -------------------------------------------------------------------------
  timer_axi4l_if #(
    .DATA_W (DATA_W),
    .ADDR_W (ADDR_W)
  ) u_axi4l_if (
    .ACLK    (ACLK),
    .ARESETn (ARESETn),
    .AWVALID (AWVALID),
    .AWREADY (AWREADY),
    .AWADDR  (AWADDR),
    .WVALID  (WVALID),
    .WREADY  (WREADY),
    .WDATA   (WDATA),
    .WSTRB   (WSTRB),
    .BVALID  (BVALID),
    .BREADY  (BREADY),
    .BRESP   (BRESP),
    .ARVALID (ARVALID),
    .ARREADY (ARREADY),
    .ARADDR  (ARADDR),
    .RVALID  (RVALID),
    .RREADY  (RREADY),
    .RDATA   (RDATA),
    .RRESP   (RRESP),
    .wr_en   (if_wr_en),
    .wr_addr (if_wr_addr),
    .wr_data (if_wr_data),
    .wr_strb (if_wr_strb),
    .rd_en   (if_rd_en),
    .rd_addr (if_rd_addr),
    .rd_data (if_rd_data)
  );

  // -------------------------------------------------------------------------
  // Register file
  // -------------------------------------------------------------------------
  timer_regfile u_regfile (
    .clk          (ACLK),
    .rst_n        (ARESETn),
    .wr_en        (if_wr_en),
    .wr_addr      (if_wr_addr),
    .wr_data      (if_wr_data),
    .wr_strb      (if_wr_strb),
    .rd_en        (if_rd_en),
    .rd_addr      (if_rd_addr),
    .rd_data      (if_rd_data),
    .hw_count_val (hw_count_val),
    .hw_intr_set  (hw_intr_set),
    .hw_ovf_set   (hw_ovf_set),
    .hw_active    (hw_active),
    .ctrl_en      (ctrl_en),
    .ctrl_mode    (ctrl_mode),
    .ctrl_intr_en (ctrl_intr_en),
    .ctrl_trig_en (ctrl_trig_en),
    .ctrl_prescale(ctrl_prescale),
    .ctrl_restart (ctrl_restart),
    .ctrl_irq_mode(ctrl_irq_mode),
    .load_val     (load_val),
    .status_intr  (status_intr)
  );

  // -------------------------------------------------------------------------
  // Core logic
  // -------------------------------------------------------------------------
  timer_core #(
    .DATA_W (DATA_W)
  ) u_core (
    .clk           (ACLK),
    .rst_n         (ARESETn),
    .ctrl_en       (ctrl_en),
    .ctrl_mode     (ctrl_mode),
    .ctrl_intr_en  (ctrl_intr_en),
    .ctrl_trig_en  (ctrl_trig_en),
    .ctrl_prescale (ctrl_prescale),
    .ctrl_restart  (ctrl_restart),
    .ctrl_irq_mode (ctrl_irq_mode),
    .load_val      (load_val),
    .status_intr   (status_intr),
    .hw_count_val  (hw_count_val),
    .hw_intr_set   (hw_intr_set),
    .hw_ovf_set    (hw_ovf_set),
    .hw_active     (hw_active),
    .irq           (irq),
    .trigger_out   (trigger_out)
  );

endmodule : timer_axi4l
