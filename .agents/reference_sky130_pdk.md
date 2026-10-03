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
`/tmp/pet43490/PDK/sky130A` — a stable symlink to the real, versioned
install (`/tmp/pet43490/PDK/volare/sky130/versions/<hash>/sky130A`, hash
`0fe599b2afb6708d281543108caf8310912f54af` as of 2026-10-03), added after
the versioned path's content was found wiped (see below) so re-fetching a
version only means repointing the symlink, not a code change. Treat
`build_sky130_libs.SKY130_PDK` as the source of truth for the path, not a
volare query — this install isn't through volare's own version bookkeeping
(`volare ls --pdk-root /tmp/pet43490/PDK/volare` returns `[]` for it).

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
so sky130 tooling is the one deliberate exception to that pattern. The same
cache is reused a second time by `synthesis/run_primetime_sta.py` (PrimeTime
STA, a separate script from `run_vendor_synth.py` — see
[reference_primetime_sta](reference_primetime_sta.md)): STA against all
three sky130 corners is exactly why those corners are compiled at all — DC
synthesis itself only ever uses the typical one.

**Why:** compiling all three corners costs real time (~15-30 s combined)
that's wasted if repeated per IP or per run; centralizing it in
`IP/common/` means the first IP to synthesize against sky130 on a given
checkout pays that cost once, and every other IP (and every re-run) reuses
the cache via mtime checking.

**How to apply:** any new IP's Step 10 synthesis work on csun.edu should
add `sky130` as a fourth `PDK_TARGET` following the exact pattern in
`IP/system/timer/synthesis/{run_vendor_synth.py,designcompiler/synth.tcl,clean.sh}`
— see [synthesis.md](synthesis.md) for the concrete template — and, once
that's wired up, add `run_primetime_sta.py` for STA the same way (see
[reference_primetime_sta](reference_primetime_sta.md)). Do **not** let a
new IP's `clean.sh`, `run_vendor_synth.py --clean`, or
`run_primetime_sta.py --clean` remove
`IP/common/synthesis/designcompiler/sky130_lib/`; it isn't that IP's artifact.

`volare` is now in `virtualenv/requirements.txt` (added alongside its
transitive deps: `anyio`, `certifi`, `h11`, `httpcore`, `httpx`, `idna`,
`markdown-it-py`, `mdurl`, `pcpp`, `pygments`, `pyyaml`, `rich`,
`zstandard`; also bumped `typing_extensions` to `4.16.0` for compatibility)
so future PDK version management (`volare fetch`, `volare ls-remote`, etc.)
is available in the project's venv — but no script imports it today; the
existing install is used directly by path.

**This `/tmp`-based install is not durable — confirmed the hard way, then
fixed (2026-10-03).** The entire `sky130A` tree under
`/tmp/pet43490/PDK/volare/sky130/.../sky130A/` was found wiped down to one
unrelated file, 13 days after it was placed — almost certainly routine
`/tmp` cleanup on the host, not anything this project did. `ensure_sky130_dbs()`
hard-fails (`return None`, for every corner, not just the missing one) the
moment any one corner's ASCII `.lib` is gone, since it can't verify the
cached `.db`'s freshness without the source. The compiled `.db` cache in
`IP/common/synthesis/designcompiler/sky130_lib/` survived fine (it's under
the repo, not `/tmp`) throughout.

**Re-fetched via volare** (same pinned version hash, to keep the compiled
`.db` cache meaningfully comparable): `volare fetch --pdk-root
/tmp/pet43490/PDK --pdk sky130 -l all <hash>`. One gotcha during the
re-fetch: volare checks only whether a library's *directory* already
exists under the target version — the libraries whose directories
existed-but-empty from the original wipe (`sky130_fd_sc_hd` among them,
the one this project actually needs) were silently skipped as "already
found" and not re-downloaded on the first `fetch` call. Fix: `rm -rf` the
empty library directories first, then re-run `fetch` — it correctly listed
them as "not found" and downloaded them the second time. This project's
venv also needed rebuilding from scratch to run `volare` at all — it had
no `pyvenv.cfg` and no local `pip` (not a real isolated venv despite
existing on disk), and `virtualenv/requirements.txt` itself was one of a
large batch of tracked files separately found missing from the working
tree (see
[project_timer_wip_2026-09-26](project_timer_wip_2026-09-26.md)) — restored
via `git checkout HEAD -- virtualenv/requirements.txt`.

Re-verified end to end after the fix: `ensure_sky130_dbs(force=True)`
recompiled all three corners cleanly, and `--dcsky130` / `run_primetime_sta.py
--sky130` reproduced the exact same cell count (737) and STA numbers
(ss +1.39 ns, tt +5.64 ns, ff +7.23 ns, all MET) as the pre-wipe
2026-09-26 run — confirming the re-fetched content is identical, as
expected for a pinned version hash.

If this keeps recurring, the real fix is moving the install outside `/tmp`
entirely (not done here).
