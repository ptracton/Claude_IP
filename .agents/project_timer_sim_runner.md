---
name: Timer IP — simulation runner architecture
description: Key design details of sim_timer.py and the timer IP verification setup
type: project
---

Main sim runner: `IP/system/timer/verification/tools/sim_timer.py`

**Testbenches:** `IP/system/timer/verification/testbench/tb_timer_{apb,ahb,wb,axi4l}.sv`  
Each testbench `include`s task files (`tasks_{proto}.sv`, `ip_test_pkg.sv`, `test_*.sv`) and has `initial $vcdpluson(0, <tb_module>);` for waveform capture.

**Work directory:** `IP/system/timer/verification/work/`  
- RTL sims: `work/{proto}/`  
- Post-syn sims: `work/postsyn/{pdk}/{proto}/`  
- Waveform output: `vcdplus.vpd` in each work subdir

**VCS compile flags include:** `-full64 -sverilog -debug_acc+all`

**Results summary:** Colored ANSI output — green for PASS, red for FAIL.

**Protocols supported:** `apb`, `ahb`, `wb`, `axi4l`  
**PDKs supported:** `saed90`, `saed32`, `saed14`
