---
name: Timer IP — simulation runner architecture
description: Key design details of sim_timer.py and the timer IP verification setup — six simulators (Icarus, GHDL, ModelSim, xsim, VCS, Xcelium), host-aware defaults, waveform dumping
type: project
---

Main sim runner: `IP/system/timer/verification/tools/sim_timer.py`

**Simulators supported:** `icarus`, `ghdl`, `modelsim`, `xsim` (standard hosts) and
`vcs`, `xcelium` (`*.csun.edu` hosts only).
Host detection: `ON_CSUN = socket.getfqdn().endswith(".csun.edu")`. `--sim` defaults
to `icarus` on standard hosts, `vcs` on csun.edu; `--sim all` expands to
icarus+ghdl or vcs+xcelium accordingly. icarus/ghdl/modelsim/xsim are rejected
with a clear error if explicitly requested on csun.edu.

**Testbenches:** `IP/system/timer/verification/testbench/tb_timer_{apb,ahb,wb,axi4l}.sv`  
Each testbench `include`s task files (`tasks_{proto}.sv`, `ip_test_pkg.sv`, `test_*.sv`)
and has two guarded waveform-dump blocks, both required because they use
simulator-specific PLI tasks that abort other simulators if left unguarded
(see [feedback_vcs_waveform_dumping.md](feedback_vcs_waveform_dumping.md)):
- `` `ifdef VCS`` → `initial $vcdpluson(0, <tb_module>);` (VCS predefines `VCS`)
- `` `ifdef INCA`` → `initial begin $shm_open("waves.shm"); $shm_probe(<tb_module>, "AS"); end` (Xcelium predefines `INCA`)

VHDL testbenches have no PLI hook, so Xcelium's VHDL flow (`xmvhdl` → `xmelab` →
`xmsim`) opens the SHM database via an inline `xmsim -input` command script instead
of a testbench-embedded call.

**Work directory:** `IP/system/timer/verification/work/<sim>/<proto>_<lang>/`
(e.g. `work/vcs/ahb_sv/`, `work/xcelium/wb_vhdl/`) — each holds `results.log`,
`sim.log`, and simulator-specific compile/elab logs.  
- Post-syn sims: `work/postsyn/{pdk}/{proto}/`  
- Waveform output: `vcdplus.vpd` (VCS SV runs) or `waves.shm/` (all Xcelium runs),
  written into the same per-run directory.

**VCS compile flags include:** `-full64 -sverilog -timescale=1ns/1ps -debug_acc+all`  
**Xcelium (SV):** single `xrun -64 -access +rwc` step.  
**Xcelium (VHDL):** `xmvhdl -V200X` → `xmelab` → `xmsim -input <shm script>`.

**Results summary:** Colored ANSI output — green for PASS, red for FAIL.

**Protocols supported:** `apb`, `ahb`, `wb`, `axi4l`  
**PDKs supported:** `saed90`, `saed32`, `saed14`

`run_sims.sh` (a standalone runner alongside `sim_timer.py`) delegates to
`sim_timer.py --sim vcs` on csun.edu instead of invoking Icarus/GHDL directly,
since those tools aren't installed there.

bus_matrix's `sim_bus_matrix.py` mirrors this same host-detection, default, and
waveform-dump design (`tb_bus_matrix_{ahb,axi,wb}.sv` carry the same
`` `ifdef VCS``/`` `ifdef INCA`` blocks) — see the bus_matrix README's
Simulation Results table for its own per-protocol results.
