// timer_ahb.sv — AHB-Lite top-level for Timer IP.
//
// Instantiates claude_ahb_if, timer_regfile, and timer_core.
// Contains no logic — only port declarations and submodule wiring.
//
// Parameters:
//   DATA_W  : data bus width              (default 32)
//   ADDR_W  : regfile word-address width  (default 4)
//   RST_POL : reset polarity, 0=active-low (default 0; active-low)

module timer_ahb #(
  parameter int unsigned DATA_W  = 32, // data width
  parameter int unsigned ADDR_W  = 4,  // regfile word-address width
  /* verilator lint_off UNUSEDPARAM */
  parameter int unsigned RST_POL = 0   // 0 = active-low reset; polarity carried by bus pin HRESETn
  /* verilator lint_on UNUSEDPARAM */
) (
  // AHB-Lite bus signals
  input  logic                  HCLK,          // AHB clock
  input  logic                  HRESETn,        // AHB active-low reset

  input  logic                  HSEL,           // slave select
  input  logic [11:0]           HADDR,          // byte address
  input  logic [1:0]            HTRANS,         // transfer type
  input  logic                  HWRITE,         // 1=write
  input  logic [DATA_W-1:0]     HWDATA,         // write data
  input  logic [DATA_W/8-1:0]   HWSTRB,         // byte write enables
  output logic [DATA_W-1:0]     HRDATA,         // read data
  output logic                  HREADY,         // ready
  output logic                  HRESP,          // response

  // IP-level outputs
  output logic                  irq,            // masked interrupt
  output logic                  trigger_out     // one-cycle trigger pulse
);

  // -------------------------------------------------------------------------
  // Internal wires between submodules
  // -------------------------------------------------------------------------

  // Bus interface → regfile write channel
  logic                  if_wr_en;
  logic [ADDR_W-1:0]     if_wr_addr;
  logic [DATA_W-1:0]     if_wr_data;
  logic [DATA_W/8-1:0]   if_wr_strb;

  // Bus interface → regfile read channel
  logic                  if_rd_en;
  logic [ADDR_W-1:0]     if_rd_addr;
  logic [DATA_W-1:0]     if_rd_data;

  // Regfile → core decoded outputs
  logic                  ctrl_en;
  logic                  ctrl_mode;
  logic                  ctrl_intr_en;
  logic                  ctrl_trig_en;
  logic [7:0]            ctrl_prescale;
  logic                  ctrl_restart;
  logic                  ctrl_irq_mode;
  logic [DATA_W-1:0]     load_val;
  logic                  status_intr;

  // Core → regfile hardware update signals
  logic [DATA_W-1:0]     hw_count_val;
  logic                  hw_intr_set;
  logic                  hw_ovf_set;
  logic                  hw_active;

  // -------------------------------------------------------------------------
  // Bus interface submodule
  // -------------------------------------------------------------------------
  claude_ahb_if #(
    .DATA_W (DATA_W),
    .ADDR_W (ADDR_W)
  ) u_ahb_if (
    .HCLK    (HCLK),
    .HRESETn (HRESETn),
    .HSEL    (HSEL),
    .HADDR   (HADDR),
    .HTRANS  (HTRANS),
    .HWRITE  (HWRITE),
    .HWDATA  (HWDATA),
    .HWSTRB  (HWSTRB),
    .HRDATA  (HRDATA),
    .HREADY  (HREADY),
    .HRESP   (HRESP),
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
    .clk          (HCLK),
    .rst_n        (HRESETn),
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
    .clk           (HCLK),
    .rst_n         (HRESETn),
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

endmodule : timer_ahb
