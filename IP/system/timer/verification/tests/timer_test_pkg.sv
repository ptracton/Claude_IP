// timer_test_pkg.sv — Verbose check helpers for timer directed tests.
//
// `include this file inside the testbench module BEFORE including test_*.sv.
// It defines check_eq and test_start/test_done helpers that print a table
// row for every assertion, whether it passes or fails.
//
// Output format (modeled on testing_pkg.vhd):
//
//   === test_reset ===
//   [  0] CTRL reset value          | exp 0x00000000 | got 0x00000000 | PASS
//   [  1] STATUS reset value        | exp 0x00000000 | got 0x00000000 | PASS
//   ...
//   test_reset: PASS  (4 checks)
//
// check_eq terminates simulation with $finish(1) on the first mismatch,
// mirroring the existing assert_eq contract.

// Shared check counter (static, reset by test_start)
static int _chk_num = 0;

// ---------------------------------------------------------------------------
// test_start — print header, reset counter
// ---------------------------------------------------------------------------
task automatic test_start;
  input string name;
  begin
    _chk_num = 0;
    $display("\n=== %s ===", name);
    $display("%-4s %-32s  %-10s  %-10s  %s",
             "#", "Check", "Expected", "Got", "Status");
    $display("%s", {78{"-"}});
  end
endtask

// ---------------------------------------------------------------------------
// check_eq — compare, print a row, stop on mismatch
// ---------------------------------------------------------------------------
task automatic check_eq;
  input logic [31:0] actual;
  input logic [31:0] expected;
  input string       msg;
  string status;
  begin
    status = (actual === expected) ? "PASS" : "FAIL";
    $display("[%3d] %-32s  0x%08h  0x%08h  %s",
             _chk_num, msg, expected, actual, status);
    _chk_num = _chk_num + 1;
    if (actual !== expected) begin
      $display("      ^^^ mismatch — stopping simulation");
      $finish(1);
    end
  end
endtask

// ---------------------------------------------------------------------------
// test_done — print footer with check count
// ---------------------------------------------------------------------------
task automatic test_done;
  input string name;
  begin
    $display("%s", {78{"-"}});
    $display("%s: PASS  (%0d checks)", name, _chk_num);
  end
endtask
