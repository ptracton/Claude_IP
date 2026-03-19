# Timer IP — UVM Testbench Skeleton

## Simulator requirement
UVM 1.2 requires a commercial simulator: Synopsys VCS, Mentor Questasim, or
Aldec Riviera-PRO.  **This skeleton is NOT compatible with Icarus Verilog or
GHDL.**

## Running with VCS
```
vcs -sverilog -ntb_opts uvm-1.2 \
    +incdir+$UVM_HOME/src \
    $UVM_HOME/src/uvm_pkg.sv \
    timer_apb_if.sv \
    timer_uvm_pkg.sv \
    <path_to_rtl>/timer_*.sv \
    tb_timer_uvm.sv \
    -o simv
./simv +UVM_TESTNAME=timer_base_test +UVM_VERBOSITY=UVM_LOW
```

## Structure
The skeleton demonstrates a complete UVM agent/env/scoreboard topology:
- **seq_item** → **sequencer** → **driver** drive APB4 transactions.
- **monitor** passively observes and forwards items to the **scoreboard**.
- **scoreboard** maintains a shadow register model and reports PASS/FAIL.
- Two sequences cover register read-write and IRQ generation with W1C clear.
