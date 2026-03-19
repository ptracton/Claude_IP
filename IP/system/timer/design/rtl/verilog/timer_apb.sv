// timer_apb.sv — APB4 top-level for Timer IP.
//
// Instantiates claude_apb_if (common), timer_regfile, and timer_core.
// Contains no logic — only port declarations and submodule wiring.
//
// Parameters:
//   DATA_W  : data bus width              (default 32)
//   ADDR_W  : regfile word-address width  (default 4)
//   RST_POL : reset polarity, 0=active-low (default 0; active-low)

module timer_apb #(
  parameter int unsigned DATA_W  = 32, // data width
  parameter int unsigned ADDR_W  = 4,  // regfile word-address width
  /* verilator lint_off UNUSEDPARAM */
  parameter int unsigned RST_POL = 0   // 0 = active-low reset; polarity carried by bus pin PRESETn
  /* verilator lint_on UNUSEDPARAM */
) (
  // APB4 bus signals
  input  logic                  PCLK,          // APB clock
  input  logic                  PRESETn,        // APB active-low reset

  input  logic                  PSEL,           // slave select
  input  logic                  PENABLE,        // enable
  input  logic [11:0]           PADDR,          // byte address
  input  logic                  PWRITE,         // 1=write
  input  logic [DATA_W-1:0]     PWDATA,         // write data
  input  logic [DATA_W/8-1:0]   PSTRB,          // byte write enables
  output logic [DATA_W-1:0]     PRDATA,         // read data
  output logic                  PREADY,         // ready
  output logic                  PSLVERR,        // slave error

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
  claude_apb_if #(
    .DATA_W (DATA_W),
    .ADDR_W (ADDR_W)
  ) u_apb_if (
    .PCLK    (PCLK),
    .PRESETn (PRESETn),
    .PSEL    (PSEL),
    .PENABLE (PENABLE),
    .PADDR   (PADDR),
    .PWRITE  (PWRITE),
    .PWDATA  (PWDATA),
    .PSTRB   (PSTRB),
    .PRDATA  (PRDATA),
    .PREADY  (PREADY),
    .PSLVERR (PSLVERR),
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
    .clk          (PCLK),
    .rst_n        (PRESETn),
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
    .clk           (PCLK),
    .rst_n         (PRESETn),
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

endmodule : timer_apb
