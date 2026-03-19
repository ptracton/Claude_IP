# Timer Regression Report

**Generated:** 2026-03-18 (from existing results.log files)

**Overall Result:** PASS

---

## Per-Test Results

| Test                     | Simulator  | Protocol | Language | Result |
|--------------------------|------------|----------|----------|--------|
| test_reset               | icarus     | apb      | SV       | PASS   |
| test_rw                  | icarus     | apb      | SV       | PASS   |
| test_back2back           | icarus     | apb      | SV       | PASS   |
| test_strobe              | icarus     | apb      | SV       | PASS   |
| test_timer_ops           | icarus     | apb      | SV       | PASS   |
| test_reset               | icarus     | ahb      | SV       | PASS   |
| test_rw                  | icarus     | ahb      | SV       | PASS   |
| test_back2back           | icarus     | ahb      | SV       | PASS   |
| test_strobe              | icarus     | ahb      | SV       | PASS   |
| test_timer_ops           | icarus     | ahb      | SV       | PASS   |
| test_reset               | icarus     | axi4l    | SV       | PASS   |
| test_rw                  | icarus     | axi4l    | SV       | PASS   |
| test_back2back           | icarus     | axi4l    | SV       | PASS   |
| test_strobe              | icarus     | axi4l    | SV       | PASS   |
| test_timer_ops           | icarus     | axi4l    | SV       | PASS   |
| test_reset               | icarus     | wb       | SV       | PASS   |
| test_rw                  | icarus     | wb       | SV       | PASS   |
| test_back2back           | icarus     | wb       | SV       | PASS   |
| test_strobe              | icarus     | wb       | SV       | PASS   |
| test_timer_ops           | icarus     | wb       | SV       | PASS   |
| test_reset               | ghdl       | apb      | VHDL     | PASS   |
| test_rw                  | ghdl       | apb      | VHDL     | PASS   |
| test_back2back           | ghdl       | apb      | VHDL     | PASS   |
| test_strobe              | ghdl       | apb      | VHDL     | PASS   |
| test_timer_ops           | ghdl       | apb      | VHDL     | PASS   |
| test_reset               | ghdl       | ahb      | VHDL     | PASS   |
| test_rw                  | ghdl       | ahb      | VHDL     | PASS   |
| test_back2back           | ghdl       | ahb      | VHDL     | PASS   |
| test_strobe              | ghdl       | ahb      | VHDL     | PASS   |
| test_timer_ops           | ghdl       | ahb      | VHDL     | PASS   |
| test_reset               | ghdl       | axi4l    | VHDL     | PASS   |
| test_rw                  | ghdl       | axi4l    | VHDL     | PASS   |
| test_back2back           | ghdl       | axi4l    | VHDL     | PASS   |
| test_strobe              | ghdl       | axi4l    | VHDL     | PASS   |
| test_timer_ops           | ghdl       | axi4l    | VHDL     | PASS   |
| test_reset               | ghdl       | wb       | VHDL     | PASS   |
| test_rw                  | ghdl       | wb       | VHDL     | PASS   |
| test_back2back           | ghdl       | wb       | VHDL     | PASS   |
| test_strobe              | ghdl       | wb       | VHDL     | PASS   |
| test_timer_ops           | ghdl       | wb       | VHDL     | PASS   |

---

## Step Summary

| Step                     | Result |
|--------------------------|--------|
| Simulation (icarus/sv)   | PASS   |
| Simulation (ghdl/vhdl)   | PASS   |
| Formal verification      | SKIP   |
| Lint (all languages)     | PASS   |

> **Formal**: No formal run results found. SymbiYosys `.sby` files exist under
> `verification/formal/` but the formal runner has not been executed yet.
> Run `python3 verification/tools/formal_timer.py` to generate results.

---

## Lint Detail

Source: `verification/lint/lint_results.log`

```
[SV] PASS — timer_apb
[SV] PASS — timer_ahb
[SV] PASS — timer_axi4l
[SV] PASS — timer_wb
[VHDL] PASS — design/rtl/vhdl/timer_reg_pkg.vhd
[VHDL] PASS — design/rtl/vhdl/timer_regfile.vhd
[VHDL] PASS — design/rtl/vhdl/timer_core.vhd
[VHDL] PASS — design/rtl/vhdl/timer_apb_if.vhd
[VHDL] PASS — design/rtl/vhdl/timer_apb.vhd
[VHDL] PASS — design/rtl/vhdl/timer_ahb_if.vhd
[VHDL] PASS — design/rtl/vhdl/timer_ahb.vhd
[VHDL] PASS — design/rtl/vhdl/timer_axi4l_if.vhd
[VHDL] PASS — design/rtl/vhdl/timer_axi4l.vhd
[VHDL] PASS — design/rtl/vhdl/timer_wb_if.vhd
[VHDL] PASS — design/rtl/vhdl/timer_wb.vhd
```
