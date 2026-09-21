# Memory Index

- [VCS waveform viewer command](reference_vcs_tools.md) — `dve -full64` launches DVE; `dve -full64 -vpd vcdplus.vpd` opens a waveform file
- [VCS waveform dumping — use $vcdpluson in testbench](feedback_vcs_waveform_dumping.md) — embed `$vcdpluson` in SV testbench; command-line approaches fail on VCS W-2024.09
- [Timer IP — post-synthesis simulation setup](project_timer_postsyn_sim.md) — PDK paths, SDF annotation scope, VCS flags for `--postsyn` mode in sim_timer.py
- [Timer IP — simulation runner architecture](project_timer_sim_runner.md) — sim_timer.py: 6 simulators incl. VCS/Xcelium, csun.edu host detection, waveform dumping (vcdplus.vpd / waves.shm), work dirs, protocols, PDKs
- [Power analysis — PrimePower (PTPX) flow](power.md) — `--power` flag, vcd2saif→pt_shell flow, liberty DB paths, report structure
- [sky130 PDK + Design Compiler on csun.edu](reference_sky130_pdk.md) — 4th DC PDK target; ASCII `.lib`→`.db` via `lc_shell` (dc_shell's own `read_lib` fails); shared cache in `IP/common/synthesis/designcompiler/`; `volare` added to venv
- [SpyGlass lint on csun.edu](reference_spyglass_lint.md) — replaces Verilator for SV lint; pass/fail from `moresimple.rpt` not exit code; VHDL-2008 has no working path (tried 6+ approaches) so VHDL lint is `SKIPPED` there
- [PrimeTime STA on csun.edu](reference_primetime_sta.md) — separate script (`run_primetime_sta.py`) from DC synthesis; covers SAED90/32/14 (one corner each) and SKY130 (all 3 corners); surfaced a pre-existing bug where SV variants synthesized fully unconstrained (hardcoded `clk` port name); timer fails timing at the ss_100C_1v60 corner (real finding, not a bug)
