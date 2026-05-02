---
name: VCS waveform dumping — use $vcdpluson in testbench
description: How to reliably get VPD waveform output from VCS; command-line approaches fail on VCS W-2024.09
type: feedback
---

Always add `$vcdpluson(0, <module_name>)` directly in each SV testbench as a dedicated `initial` block. This produces `vcdplus.vpd` in the sim work directory.

**Why:** On VCS W-2024.09 (ecs-vdi), command-line approaches all failed:
- `+vcs+vcdpluson` runtime plusarg — produced no file silently
- `-vpd_file waves.vpd` compile-time flag — `UNKWN_OPTVSIM` error, VCS treated it as a source file
- `-ucli -do dump.tcl` with `vcdpluson 0` — `invalid command name "vcdpluson"` (it's a PLI task, not UCLi)

**How to apply:** When adding waveform dumping to any new testbench in this project, embed `initial $vcdpluson(0, <tb_module>);` directly in the SV file. Also add `-debug_acc+all` to the VCS compile command.
