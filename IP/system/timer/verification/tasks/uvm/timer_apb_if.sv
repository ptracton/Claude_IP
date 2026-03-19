// timer_apb_if.sv — SystemVerilog interface for Timer APB4 UVM testbench.
//
// This interface bundles all APB4 signals used by the Timer IP DUT
// (timer_apb).  It is passed to driver and monitor via the UVM config_db
// as a virtual interface.
//
// Signal directions are from the master (testbench) perspective:
//   inputs  to DUT  → driven by the driver
//   outputs from DUT → observed by driver (PRDATA, PREADY, PSLVERR)
//                      and monitor
//
// NOTE: Requires a UVM-capable simulator (VCS, Questasim, or Riviera-PRO).
//       Not compatible with Icarus Verilog or GHDL.

interface timer_apb_if (
  input logic PCLK,
  input logic PRESETn
);

  // -------------------------------------------------------------------------
  // APB4 master-to-slave signals (driven by driver)
  // -------------------------------------------------------------------------
  logic        PSEL;
  logic        PENABLE;
  logic [11:0] PADDR;
  logic        PWRITE;
  logic [31:0] PWDATA;
  logic [3:0]  PSTRB;

  // -------------------------------------------------------------------------
  // APB4 slave-to-master signals (observed by driver and monitor)
  // -------------------------------------------------------------------------
  logic [31:0] PRDATA;
  logic        PREADY;
  logic        PSLVERR;

  // -------------------------------------------------------------------------
  // IP-level outputs (observable by monitor / test)
  // -------------------------------------------------------------------------
  logic        irq;
  logic        trigger_out;

endinterface : timer_apb_if
