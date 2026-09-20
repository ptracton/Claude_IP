---
name: sky130 PDK + Design Compiler on csun.edu — shared tooling
description: SKY130 is now a regular fourth Design Compiler PDK target on csun.edu (alongside SAED90/32/14); lc_shell compile gotcha and where the shared tooling lives
type: reference
---

sky130 (SkyWater 130nm open-source PDK) joined SAED90/SAED32/SAED14 as a
regular Design Compiler synthesis target on csun.edu. First wired up in
`IP/system/timer/synthesis/`, then generalized — see
[synthesis.md](synthesis.md) (Step 10) for the full spec any new IP's
synthesis step should follow.

**PDK location (csun.edu, per-user, not `/opt/ECE_Lib`):**
`/tmp/pet43490/PDK/volare/sky130/versions/0fe599b2afb6708d281543108caf8310912f54af/sky130A`
— installed manually via `volare` by the user, not through volare's own
version bookkeeping (`volare ls --pdk-root /tmp/pet43490/PDK/volare` returns
`[]` for it). Treat `build_sky130_libs.SKY130_PDK` as the source of truth
for the path, not a volare query.

**The gotcha that cost real debugging time:** sky130 ships only ASCII
`.lib`, no pre-compiled `.db` (unlike every SAED PDK). Pointing
`target_library`/`link_library` at the `.lib` directly does **not** fail
loudly — `dc_shell` logs `Error: ... is not a DB file. (DB-1)` but still
**exits 0**, silently falling back to black-box/unmapped cells. A first
attempt "passed" with a plausible-looking cell count that was actually
garbage from an unmapped design. Always grep the DC log for `black-box`,
`unmapped components`, or `DB-1` — exit code 0 does not mean the netlist is
real. `dc_shell`'s own `read_lib` command also can't do the compile on this
host (`Check the installation of Library Compiler`, LCSH-3); the fix is the
separate `lc_shell` binary (`read_lib "<file>"` then
`write_lib <name> -output "<db>"`).

**Shared, not duplicated:** the compile-and-cache logic lives once, in
`IP/common/synthesis/designcompiler/build_sky130_libs.py`, and caches
compiled `.db` files (all three corners: `ss_100C_1v60` worst-case,
`tt_025C_1v80` typical/synthesis, `ff_n40C_1v95` best-case) in
`IP/common/synthesis/designcompiler/sky130_lib/`. Every IP's
`run_vendor_synth.py` imports this module via `IP_COMMON_PATH` rather than
reimplementing it — this repo's IPs otherwise keep their `synthesis/`
directories fully self-contained/duplicated (see `bus_matrix` vs `timer`),
so sky130 tooling is the one deliberate exception to that pattern.

**Why:** compiling all three corners costs real time (~15-30 s combined)
that's wasted if repeated per IP or per run; centralizing it in
`IP/common/` means the first IP to synthesize against sky130 on a given
checkout pays that cost once, and every other IP (and every re-run) reuses
the cache via mtime checking.

**How to apply:** any new IP's Step 10 synthesis work on csun.edu should
add `sky130` as a fourth `PDK_TARGET` following the exact pattern in
`IP/system/timer/synthesis/{run_vendor_synth.py,designcompiler/synth.tcl,clean.sh}`
— see [synthesis.md](synthesis.md) for the concrete template. Do **not** let
a new IP's `clean.sh` or `--clean` remove
`IP/common/synthesis/designcompiler/sky130_lib/`; it isn't that IP's artifact.

`volare` is now in `virtualenv/requirements.txt` (added alongside its
transitive deps: `anyio`, `certifi`, `h11`, `httpcore`, `httpx`, `idna`,
`markdown-it-py`, `mdurl`, `pcpp`, `pygments`, `pyyaml`, `rich`,
`zstandard`; also bumped `typing_extensions` to `4.16.0` for compatibility)
so future PDK version management (`volare fetch`, `volare ls-remote`, etc.)
is available in the project's venv — but no script imports it today; the
existing install is used directly by path.
