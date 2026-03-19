// timer_wb.sv — Wishbone B4 top-level for Timer IP.
//
// Instantiates claude_wb_if, timer_regfile, and timer_core.
// Contains no logic — only port declarations and submodule wiring.
//
// Parameters:
//   DATA_W  : data bus width              (default 32)
//   ADDR_W  : regfile word-address width  (default 4)
//   RST_POL : reset polarity, 0=active-low (default 0)

module timer_wb #(
  parameter int unsigned DATA_W  = 32, // data width
  parameter int unsigned ADDR_W  = 4,  // regfile word-address width
  /* verilator lint_off UNUSEDPARAM */
  parameter int unsigned RST_POL = 0   // 0 = active-low reset; Wishbone uses active-high RST_I on bus pin
  /* verilator lint_on UNUSEDPARAM */
) (
  // Wishbone B4 signals
  input  logic                  CLK_I,         // Wishbone clock
  input  logic                  RST_I,         // Wishbone synchronous active-high reset

  input  logic                  CYC_I,         // bus cycle valid
  input  logic                  STB_I,         // strobe
  input  logic                  WE_I,          // 1=write
  input  logic [11:0]           ADR_I,         // byte address
  input  logic [DATA_W-1:0]     DAT_I,         // write data
  input  logic [DATA_W/8-1:0]   SEL_I,         // byte selects
  output logic [DATA_W-1:0]     DAT_O,         // read data
  output logic                  ACK_O,         // acknowledge
  output logic                  ERR_O,         // error

  // IP-level outputs
  output logic                  irq,           // masked interrupt
  output logic                  trigger_out    // one-cycle trigger pulse
);

  // -------------------------------------------------------------------------
  // Internal wires between submodules
  // -------------------------------------------------------------------------

  // Wishbone uses active-high synchronous reset; derive active-low rst_n for
  // regfile and core.
  logic rst_n;
  assign rst_n = ~RST_I;

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
  claude_wb_if #(
    .DATA_W (DATA_W),
    .ADDR_W (ADDR_W)
  ) u_wb_if (
    .CLK_I   (CLK_I),
    .RST_I   (RST_I),
    .CYC_I   (CYC_I),
    .STB_I   (STB_I),
    .WE_I    (WE_I),
    .ADR_I   (ADR_I),
    .DAT_I   (DAT_I),
    .SEL_I   (SEL_I),
    .DAT_O   (DAT_O),
    .ACK_O   (ACK_O),
    .ERR_O   (ERR_O),
    .wr_en   (if_wr_en),
    .wr_addr (if_wr_addr),
    .wr_data (if_wr_data),
    .wr_strb (if_wr_strb),
    .rd_en   (if_rd_en),
    .rd_addr (if_rd_addr),
    .rd_data (if_rd_data)
  );

  // -------------------------------------------------------------------------
  // Register file (uses active-low rst_n)
  // -------------------------------------------------------------------------
  timer_regfile u_regfile (
    .clk          (CLK_I),
    .rst_n        (rst_n),
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
  // Core logic (uses active-low rst_n)
  // -------------------------------------------------------------------------
  timer_core #(
    .DATA_W (DATA_W)
  ) u_core (
    .clk           (CLK_I),
    .rst_n         (rst_n),
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

endmodule : timer_wb
