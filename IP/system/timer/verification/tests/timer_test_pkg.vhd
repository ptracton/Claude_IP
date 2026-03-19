-- timer_test_pkg.vhd — Verbose check helpers for timer directed tests.
--
-- Use: add `use work.timer_test_pkg.all;` to each testbench and call
-- check_eq, test_start, and test_done from the stimulus process.
--
-- Output format (modeled on testing_pkg.vhd):
--
--   === test_reset ===
--   #   | Check                            | Expected   | Got        | Status
--   ------------------------------------------------------------------------------
--   [  0] CTRL reset value                 | 0x00000000 | 0x00000000 | PASS
--   ...
--   -------------------------------------------------------------------------------
--   test_reset: PASS  (4 checks)
--
-- check_eq terminates simulation with severity failure on the first mismatch.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

package timer_test_pkg is

  -- Shared check counter — reset by test_start
  shared variable chk_num : integer := 0;

  procedure test_start (constant name : in string);
  procedure test_done  (constant name : in string);

  procedure check_eq (
    constant actual   : in std_ulogic_vector(31 downto 0);
    constant expected : in std_ulogic_vector(31 downto 0);
    constant msg      : in string
  );

end package timer_test_pkg;

package body timer_test_pkg is

  -- -------------------------------------------------------------------------
  -- print — write a line to stdout
  -- -------------------------------------------------------------------------
  procedure print (msg : string) is
    variable l : line;
  begin
    write(l, msg);
    writeline(output, l);
  end procedure;

  -- -------------------------------------------------------------------------
  -- pad_right — right-pad a string to n characters
  -- -------------------------------------------------------------------------
  function pad_right (s : string; n : integer) return string is
    variable result : string(1 to n) := (others => ' ');
  begin
    if s'length <= n then
      result(1 to s'length) := s;
    else
      result := s(s'low to s'low + n - 1);
    end if;
    return result;
  end function;

  -- -------------------------------------------------------------------------
  -- int_to_str — integer to decimal string
  -- -------------------------------------------------------------------------
  function int_to_str (n : integer) return string is
    variable tmp : line;
  begin
    write(tmp, n);
    return tmp.all;
  end function;

  -- -------------------------------------------------------------------------
  -- test_start
  -- -------------------------------------------------------------------------
  procedure test_start (constant name : in string) is
  begin
    chk_num := 0;
    print("");
    print("=== " & name & " ===");
    print("#    | " & pad_right("Check", 32) &
          " | Expected   | Got        | Status");
    print(string'((1 to 78 => '-')));
  end procedure;

  -- -------------------------------------------------------------------------
  -- check_eq
  -- -------------------------------------------------------------------------
  procedure check_eq (
    constant actual   : in std_ulogic_vector(31 downto 0);
    constant expected : in std_ulogic_vector(31 downto 0);
    constant msg      : in string
  ) is
    variable status : string(1 to 4);
  begin
    if actual = expected then
      status := "PASS";
    else
      status := "FAIL";
    end if;

    print("[" & pad_right(int_to_str(chk_num), 3) & "] " &
          pad_right(msg, 32) &
          " | 0x" & to_hstring(expected) &
          " | 0x" & to_hstring(actual) &
          " | " & status);

    chk_num := chk_num + 1;

    if actual /= expected then
      report "check_eq FAIL: " & msg &
             " expected 0x" & to_hstring(expected) &
             " got 0x" & to_hstring(actual)
        severity failure;
    end if;
  end procedure;

  -- -------------------------------------------------------------------------
  -- test_done
  -- -------------------------------------------------------------------------
  procedure test_done (constant name : in string) is
  begin
    print(string'((1 to 78 => '-')));
    print(name & ": PASS  (" & int_to_str(chk_num) & " checks)");
  end procedure;

end package body timer_test_pkg;
