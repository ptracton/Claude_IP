---
name: VCS tools reference
description: DVE waveform GUI, VCS/urg code coverage commands and merge gotchas, backdoor deposit limits on csun.edu
type: reference
---

Launch DVE (VCS waveform GUI) with: `dve -full64`

Open a VPD file directly: `dve -full64 -vpd vcdplus.vpd`


## Code coverage (VCS + urg)

- Compile: `vcs ... -cm line+cond+fsm+tgl+branch -cm_dir run/cov.vdb -cm_hier cov_hier.cfg`.
- Simulate: `./simv ... -cm line+cond+fsm+tgl+branch -cm_dir run/cov.vdb`.
- `cov_hier.cfg` lines: `+moduletree <top>` to include a subtree, `-moduletree <glob>` to
  exclude one (wildcards work, e.g. `-moduletree SRAM*`).
- Merge runs of **different designs** (different tops / generate choices):
  `urg -full64 -lca -flex_merge modules -format both -report <dir> -dbname <db> -dir a.vdb -dir b.vdb ...`
  - Without `-flex_merge modules`, urg keeps only the first `-dir`'s design and drops the rest
    (`Warning-[CMR-VCINF] ... is not found in base design`) while exiting 0.
  - `-flex_merge union` and `-map <module>` do not fix it.
  - `-flex_merge modules` is an LCA feature: without `-lca` urg fails with
    `Error-[URG-LCA-FEATURE]`.
- Report files: `dashboard.txt` (totals), `modlist.txt` (per module definition; the first line
  per module is the merged one), `hierarchy.txt`, `dashboard.html`.
- In use: `IP/system/sram/verification/tools/sim_sram.py --coverage`.

## Backdoor deposit

- `$deposit(<var>, value)` on a variable written in `always_ff` is a compile error in VCS
  (`Error-[ICPD] Illegal combination of drivers`), with or without `-debug_access+all`. VCS
  does not accept a string path in `$deposit` either.
- Use the DPI/VPI helper `IP/common/verification/dpi/claude_backdoor.c` (compile with
  `-debug_access+r+w`). It works on VCS and Xcelium (`-access +rw`).
