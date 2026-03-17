# VHDL-2008 Coding Style Guide

## Basics

### Summary

VHDL-2008 is the primary logic design language for production-quality RTL
development. VHDL can be written in vastly different styles, which can lead
to code conflicts and review latency. This style guide aims to promote
VHDL readability across groups. To quote the
[Google C++ style guide](https://google.github.io/styleguide/cppguide.html):
"Creating common, required idioms and patterns makes code much easier to
understand."

This guide defines the preferred style for VHDL-2008. The goals are to:

*   promote consistency across hardware development projects
*   promote best practices
*   increase code sharing and re-use

This style guide defines style for synthesizable RTL and test bench code
targeting IEEE 1076-2008 (VHDL-2008). Where relevant, improvements introduced
in VHDL-2008 over VHDL-93/2002 are called out explicitly and their use is
encouraged.

See the [Appendix](#appendix---condensed-style-guide) for a condensed tabular
representation of this style guide.

**Table of Contents**

- [VHDL-2008 Coding Style Guide](#vhdl-2008-coding-style-guide)
  - [Basics](#basics)
    - [Summary](#summary)
    - [Terminology Conventions](#terminology-conventions)
    - [Default to Ada-like Formatting](#default-to-ada-like-formatting)
    - [Style Guide Exceptions](#style-guide-exceptions)
    - [Which VHDL to Use](#which-vhdl-to-use)
  - [VHDL Conventions](#vhdl-conventions)
    - [Summary](#summary-1)
    - [File Extensions](#file-extensions)
    - [General File Appearance](#general-file-appearance)
      - [Characters](#characters)
      - [POSIX File Endings](#posix-file-endings)
      - [Line Length](#line-length)
      - [No Tabs](#no-tabs)
      - [No Trailing Spaces](#no-trailing-spaces)
    - [Begin / End](#begin--end)
    - [Indentation](#indentation)
      - [Indented Sections](#indented-sections)
      - [Line Wrapping](#line-wrapping)
    - [Spacing](#spacing)
      - [Comma-delimited Lists](#comma-delimited-lists)
      - [Tabular Alignment](#tabular-alignment)
      - [Expressions](#expressions)
      - [Array Dimensions in Declarations](#array-dimensions-in-declarations)
      - [Labels](#labels)
      - [Case Items](#case-items)
      - [Function and Procedure Calls](#function-and-procedure-calls)
      - [Space Around Keywords](#space-around-keywords)
    - [Parentheses](#parentheses)
    - [Comments](#comments)
    - [Declarations](#declarations)
    - [Basic Template](#basic-template)
  - [Naming](#naming)
    - [Summary](#summary-2)
    - [Constants](#constants)
      - [Parameterized Objects (entities, etc.)](#parameterized-objects-entities-etc)
    - [Suffixes](#suffixes)
    - [Enumerations](#enumerations)
    - [Signal Naming](#signal-naming)
      - [Use Descriptive Names](#use-descriptive-names)
      - [Prefixes](#prefixes)
      - [Hierarchical Consistency](#hierarchical-consistency)
    - [Clocks](#clocks)
    - [Resets](#resets)
  - [Language Features](#language-features)
    - [Preferred VHDL-2008 Constructs](#preferred-vhdl-2008-constructs)
    - [Package Dependencies](#package-dependencies)
    - [Entity Declaration](#entity-declaration)
    - [Architecture Body](#architecture-body)
    - [Component Instantiation and Direct Entity Instantiation](#component-instantiation-and-direct-entity-instantiation)
    - [Constants and Generics](#constants-and-generics)
    - [Signal Widths and Types](#signal-widths-and-types)
      - [Always be explicit about the widths of number literals](#always-be-explicit-about-the-widths-of-number-literals)
      - [Port connections must always match widths correctly](#port-connections-must-always-match-widths-correctly)
      - [Do not use multi-bit signals in a boolean context](#do-not-use-multi-bit-signals-in-a-boolean-context)
      - [Bit Slicing](#bit-slicing)
      - [Handling Width Overflow](#handling-width-overflow)
    - [Signal Assignments: Sequential vs. Combinational](#signal-assignments-sequential-vs-combinational)
    - [Delay Modeling](#delay-modeling)
    - [Sequential Logic (Latches)](#sequential-logic-latches)
    - [Sequential Logic (Registers)](#sequential-logic-registers)
    - [Unknown and Uninitialized Values](#unknown-and-uninitialized-values)
      - [Catching Errors Where Invalid Values Are Consumed](#catching-errors-where-invalid-values-are-consumed)
      - [Guidance on Case Statements and Conditional Assignments](#guidance-on-case-statements-and-conditional-assignments)
      - [Dynamic Array Indexing](#dynamic-array-indexing)
    - [Combinational Logic](#combinational-logic)
    - [Case Statements](#case-statements)
    - [Generate Constructs](#generate-constructs)
    - [Signed and Unsigned Arithmetic](#signed-and-unsigned-arithmetic)
    - [Number Formatting](#number-formatting)
    - [Functions and Procedures](#functions-and-procedures)
    - [Problematic Language Features and Constructs](#problematic-language-features-and-constructs)
      - [Shared Variables](#shared-variables)
      - [Hierarchical References via External Names](#hierarchical-references-via-external-names)
  - [Design Conventions](#design-conventions)
    - [Summary](#summary-3)
    - [Declare All Signals](#declare-all-signals)
    - [Use std_logic for Synthesis](#use-std_logic-for-synthesis)
    - [Logical vs. Bitwise Operators](#logical-vs-bitwise-operators)
    - [Array Ordering](#array-ordering)
    - [Finite State Machines](#finite-state-machines)
    - [Active-Low Signals](#active-low-signals)
    - [Differential Pairs](#differential-pairs)
    - [Delays](#delays)
    - [Library and Package Use Clauses](#library-and-package-use-clauses)
    - [Assertion Statements](#assertion-statements)
      - [A Note on Security-Critical Applications](#a-note-on-security-critical-applications)
  - [Appendix - Condensed Style Guide](#appendix---condensed-style-guide)
    - [Basic Style Elements](#basic-style-elements)
    - [Construct Naming](#construct-naming)
    - [Suffixes for Signals and Types](#suffixes-for-signals-and-types)
    - [Language Features](#language-features-1)


### Terminology Conventions

Unless otherwise noted, the following terminology conventions apply to this
style guide:

*   The word ***must*** indicates a mandatory requirement. Similarly, ***do
    not*** indicates a prohibition. Imperative and declarative statements
    correspond to ***must***.
*   The word ***recommended*** indicates that a certain course of action is
    preferred or is most suitable. Similarly, ***not recommended*** indicates
    that a course of action is unsuitable, but not prohibited. There may be
    reasons to use other options, but the implications and reasons for doing so
    must be fully understood.
*   The word ***may*** indicates a course of action is permitted and optional.
*   The word ***can*** indicates a course of action is possible given material,
    physical, or causal constraints.

### Default to Ada-like Formatting

***Where appropriate, format code consistent with clean, structured Ada-like
style emphasizing readability.***

VHDL is strongly influenced by Ada, and where appropriate the formatting
guidelines below are derived from that heritage:

*   Generally, [names](#naming) should be descriptive and avoid abbreviations.
*   Non-ASCII characters are forbidden.
*   Indentation uses spaces, no tabs. Indentation is two spaces per nesting
    level, four spaces for line continuation.
*   Place a space between keywords such as `if`, `while`, `case` and any
    following expression.
*   Use horizontal whitespace around operators, and avoid trailing whitespace
    at the end of lines.
*   Maintain consistent and good punctuation, spelling, and grammar within
    comments.
*   Use standard formatting for comments, including
    [TODO](https://google.github.io/styleguide/cppguide.html#TODO_Comments)
    and deprecation notation.

### Style Guide Exceptions

***Justify all exceptions with a comment.***

No style guide is perfect. There are times when the best path to a working
design, or for working around a tool issue, is to deviate from this style
guide. It is always acceptable to deviate from the style guide by necessity,
as long as that necessity is clearly justified by a brief comment, and a lint
waiver annotation is added where appropriate.

### Which VHDL to Use

***Prefer VHDL-2008 (IEEE 1076-2008).***

All RTL and test benches should be developed targeting the
[IEEE 1076-2008 (VHDL-2008)](https://ieeexplore.ieee.org/document/4772740)
standard, except for [prohibited features](#problematic-language-features-and-constructs).

Key VHDL-2008 improvements over earlier revisions that must be preferred
include:

*   `process(all)` instead of manually maintained sensitivity lists.
*   Conditional signal assignments (`signal <= value when condition else ...`)
    and selected signal assignments (`with expr select signal <= ...`) as
    concurrent statements.
*   `generic` on packages, enabling parameterized packages.
*   `context` clauses for grouping commonly used library/use declarations.
*   Unresolved types (`std_ulogic`, `std_ulogic_vector`) preferred over
    resolved types (`std_logic`, `std_logic_vector`) for internal signals.
*   Enhanced port maps: generics and signals may share a common map section.
*   `matching` case statements (`case?`) for wildcard matching.
*   Integer types on ports (though `std_logic_vector` remains preferred for
    physical ports).

---

## VHDL Conventions

### Summary

This section addresses primarily aesthetic aspects of style: line length,
indentation, spacing, and so on. The goal is uniform, readable code across all
files in a project.

### File Extensions

***Use the `.vhd` extension for VHDL source files.***

File extensions have the following meanings:

*   `.vhd` indicates a VHDL-2008 source file defining an entity/architecture
    pair, a package, or a package body.
*   `.vhdl` is an acceptable alternative extension but `.vhd` is preferred for
    consistency.

Only `.vhd` (or `.vhdl`) files are compilation units. VHDL has no textual
include mechanism equivalent to the Verilog preprocessor; shared definitions
must be placed in packages and referenced via `library` / `use` clauses.

Each `.vhd` file should contain one primary design unit (entity or package)
and its corresponding secondary unit (architecture or package body). The file
name must match the primary design unit name. For example, `foo.vhd` should
contain `entity foo` and `architecture rtl of foo`.

### General File Appearance

#### Characters

***Use only ASCII characters with UNIX-style line endings (`"\n"`).***

#### POSIX File Endings

***All lines in non-empty files must end with a newline (`"\n"`).***

#### Line Length

***Wrap code at 100 characters per line.***

The maximum line length for style-compliant VHDL code is 100 characters per
line.

Exceptions:

-   Any place where line wraps are impossible (for example, a string literal
    in a `report` statement might extend past 100 characters).

[Line Wrapping](#line-wrapping) contains additional guidelines on how to
wrap long lines.

#### No Tabs

***Do not use tabs anywhere.***

Use spaces to indent or align text. See [Indentation](#indentation) for
rules about indentation and wrapping.

To convert tabs to spaces in any file, use the
[UNIX `expand`](http://linux.die.net/man/1/expand) utility.

#### No Trailing Spaces

***Delete trailing whitespace at the end of lines.***

### Begin / End

***VHDL uses paired keywords to delimit blocks. Always place paired closing
keywords on their own lines.***

VHDL uses matched keyword pairs such as `begin`/`end`, `process`/`end process`,
`if`/`end if`, `case`/`end case`, `loop`/`end loop`, and
`entity`/`end entity`. The closing keyword must always begin a new line.

The opening `begin` (or equivalent structure opener) must appear on the same
line as the keyword that introduces the structure (e.g., `process`, `if`,
`architecture`, etc.).

Optionally repeat the design unit name after the closing `end` keyword; this
is recommended for all top-level structures and for any nested block that
exceeds 20 lines. When a label is repeated after `end`, place one space before
and after any separating keyword.

✅
```vhdl
-- Wrapped process block: begin and end process on separate lines.
process(all) is
begin
  q <= d;
end process;
```

✅
```vhdl
-- if/end if on own lines, else on same line as end if of prior branch.
if (rst_n = '0') then
  q <= (others => '0');
elsif (enable = '1') then
  q <= d;
end if;
```

❌
```vhdl
-- Incorrect: end if must start a new line.
if (rst_n = '0') then q <= (others => '0'); end if;
```

The above style also applies to individual `when` alternatives within a `case`
statement.

✅
```vhdl
case state_q is
  when ST_IDLE =>
    state_d <= ST_A;
  when ST_A =>
    state_d <= ST_B;
  when ST_B =>
    state_d <= ST_IDLE;
    foo <= bar;
  when others =>
    state_d <= ST_IDLE;
end case;
```

❌
```vhdl
-- Incorrect: each when alternative must have its body on a new line.
case state_q is
  when ST_IDLE => state_d <= ST_A; when ST_A => state_d <= ST_B;
end case;
```

### Indentation

***Indentation is two spaces per level.***

Use spaces for indentation. Do not use tabs. Configure your editor to emit
spaces when the tab key is pressed.

#### Indented Sections

Always add an additional level of indentation (two spaces) to the enclosed
sections of all paired VHDL keyword structures. Examples of VHDL keyword
pairs:

*   `entity` / `end entity`
*   `architecture` / `end architecture`
*   `package` / `end package`
*   `process` / `end process`
*   `if` / `end if`
*   `case` / `end case`
*   `for` / `end loop` (generate or sequential loop)
*   `if generate` / `end generate`
*   `block` / `end block`

The `begin` keyword that separates the declarative region from the statement
region of an `architecture` or `process` body is not indented relative to the
enclosing unit; the statements that follow it are.

#### Line Wrapping

When wrapping a long expression, indent the continued part of the expression
by four spaces, like this:

✅
```vhdl
request_valid <= enabled and (
    alpha < bravo and
    charlie < delta
);

result <= addr_gen_function(
    thing, other_thing, long_parameter_name, x, y,
    extra_param1, extra_param2
);
```

Or, if it improves readability, align the continued part of the expression
with a grouping open parenthesis, like this:

✅
```vhdl
request_valid <= enabled and (alpha < bravo and
                              charlie < delta);

result <= addr_gen_function(thing, other_thing,
                            long_parameter_name,
                            x, y);
```

Operators in a wrapped expression can be placed at either the end or the
beginning of each line, but this must be done consistently within a file.

Port maps and generic maps that are wrapped across lines should have each
mapping on its own line, with the closing parenthesis on its own line:

✅
```vhdl
u_submodule : submodule
  generic map (
    Width => WIDTH,
    Depth => DEPTH
  )
  port map (
    clk_i       => clk_i,
    rst_n_i     => rst_n_i,
    data_valid_i => data_valid,
    data_value_i => data_value,
    data_ready_o => data_ready
  );
```

### Spacing

#### Comma-delimited Lists

***For multiple items on a line, one space must separate the comma and the
next character.***

Additional whitespace is allowed for readability.

✅
```vhdl
signal a, b, c : std_ulogic;
result <= my_func(lorem, ipsum, dolor, sit, amet, consectetur,
                  adipiscing, elit);
```

❌
```vhdl
signal a,b,c : std_ulogic;
result <= my_func(a,b,c);
```

#### Tabular Alignment

Tabular alignment groups two or more similar lines so that identical parts
are directly above one another. This alignment makes it easy to see which
characters are the same and which are different between lines.

***The use of tabular alignment is generally encouraged.***

***The use of tabular alignment is required for port map associations and
signal declarations that form a logical group.***

Each block of code, separated by an empty line, is treated as a separate
"table."

Use spaces, not tabs. For example:

✅
```vhdl
signal my_interface_data    : std_ulogic_vector(7 downto 0);
signal my_interface_address : std_ulogic_vector(15 downto 0);
signal my_interface_enable  : std_ulogic;

signal another_signal  : std_ulogic;
signal something_else  : std_ulogic_vector(7 downto 0);
```

✅
```vhdl
u_mod : mod
  port map (
    clk_i          => clk_i,
    rst_n_i        => rst_n_i,
    sig_i          => my_signal_in,
    sig2_i         => my_signal_out,
    -- comment with no blank line maintains the block
    in_same_block_i => my_signal_in,
    sig3_i          => something,

    in_another_block_i => my_signal_in,
    sig4_i             => something
  );
```

#### Expressions

***Include whitespace on both sides of all binary operators.***

Use spaces around binary operators. Add sufficient whitespace to aid
readability.

✅
```vhdl
a <= ((addr and mask) = MY_ADDR_C) ? b(1) : not b(0);  -- good
```

❌
```vhdl
a<=((addr and mask)=MY_ADDR_C)?b(1):not b(0);  -- bad
```

**Exception:** when declaring a vector constraint it is acceptable to use
compact notation. For example:

✅
```vhdl
signal foo : std_ulogic_vector(WIDTH - 1 downto 0);  -- fine
signal foo : std_ulogic_vector(WIDTH-1 downto 0);    -- also acceptable
```

When expressing conditional signal assignments across multiple lines, format
them like an equivalent if-then-else structure:

✅
```vhdl
a <= matches_value    when (addr and mask) = MY_ADDR_C else
     doesnt_match_value;
```

#### Array Dimensions in Declarations

Add a space around range constraints (i.e., around `downto` or `to`).

Do not add a space between the type name and its constraint in a subtype or
signal declaration.

✅
```vhdl
signal data   : std_ulogic_vector(7 downto 0);
signal matrix : std_ulogic_vector(31 downto 0);
type   word_t is std_ulogic_vector(31 downto 0);
```

❌
```vhdl
signal data:std_ulogic_vector(7 downto 0);       -- missing spaces around ':'
signal data : std_ulogic_vector (7 downto 0);    -- space before '(' is wrong
```

#### Labels

***When labeling processes, blocks, or generate regions, add one space
before and after the colon.***

✅
```vhdl
p_reg : process(all) is
begin
  ...
end process p_reg;

gen_foo : if TypeIsPosedge generate
  ...
end generate gen_foo;
```

❌
```vhdl
p_reg:process(all) is  -- missing spaces around ':'
end process;           -- label not repeated (acceptable but less clear)
```

#### Case Items

There must be no whitespace before the `=>` of a `when` alternative; there
must be at least one space after `=>`.

The `when others` alternative must always be present.

✅
```vhdl
case my_state is
  when ST_INIT  => report "Shall we begin";
  when ST_ERROR => report "Oh boy this is bad" severity error;
  when others =>
    my_state <= ST_INIT;
    interrupt <= '1';
end case;
```

❌
```vhdl
case my_state is
  when ST_ERROR  => interrupt <= '1';   -- excess whitespace before =>: avoid
  when others=>null;                    -- missing space after =>
end case;
```

#### Function and Procedure Calls

***Function and procedure calls must not have any spaces between the
subprogram name and the opening parenthesis.***

✅
```vhdl
process_packet(pkt);
result <= to_integer(unsigned(data_slv));
```

❌
```vhdl
process_packet (pkt);     -- must not have space before '('
result <= to_integer (unsigned(data_slv));
```

#### Space Around Keywords

***Include whitespace before and after VHDL keywords.***

Do not include whitespace:

-   before keywords that immediately follow a grouping opener such as `(`.
-   before a keyword at the beginning of a line.
-   after a keyword at the end of a line.

```vhdl
-- Normal indentation before if. Include a space after if.
if (foo = '1') then
end if;

-- Include a space after process.
process(all) is
begin
end process;
```

### Parentheses

***Use parentheses to make operations unambiguous.***

In any instance where a reasonable human would need to expend thought or
consult an operator precedence chart, use parentheses to make the order of
operations unambiguous.

VHDL has relatively few precedence levels and its operator precedence rules
differ from C. In particular:

*   `and`, `or`, `nand`, `nor`, `xor`, `xnor` all have the same precedence
    and do not associate — parentheses are mandatory when mixing them.
*   The `not` operator has higher precedence than all binary logical operators.

✅
```vhdl
-- Parentheses are mandatory when mixing and/or.
result <= (a and b) or (c and d);

-- Conditional assignment: parenthesize conditions for clarity.
foo <= (condition_a_x ? x : y) when condition_a else b;
```

❌
```vhdl
-- This is a compile error in VHDL: cannot mix and/or without parentheses.
result <= a and b or c and d;
```

### Comments

***VHDL single-line comments (`-- foo`) are the standard. Block-style
comment headers may use repeated `--` lines.***

A comment on its own line describes the code that follows. A comment on a
line with code describes that line of code.

```vhdl
-- This comment describes the following entity.
entity foo is
  ...
end entity foo;

constant VAL_BAZ_C : boolean := true;  -- This comment describes the item to the left.
```

It can sometimes be useful to structure the code using header-style comments
to separate different functional parts (such as FSMs, the main datapath, or
register blocks) within an architecture. The preferred style is a single-line
section name framed with `--` comment lines:

```vhdl
architecture rtl of foo is

begin

  ----------------
  -- Controller --
  ----------------
  ...

  -----------------------
  -- Main ALU Datapath --
  -----------------------
  ...

end architecture rtl;
```

When marking the beginning and end of a loop or generate region for
readability, use a single-line comment with no extra delineators:

✅
```vhdl
-- begin: iterate over foobar
for i in 0 to N - 1 loop
  ...
end loop;
-- end: iterate over foobar
```

✅
```vhdl
for i in 0 to N - 1 loop  -- iterate over foobar
  ...
end loop;  -- iterate over foobar
```

❌
```vhdl
---------------------------------- iterate over foobar ----------------------------------
for i in 0 to N - 1 loop
  ...
end loop;
---------------------------------- iterate over foobar ----------------------------------
```

### Declarations

***All signals must be declared before they are used.***

Within architectures, it is **recommended** that signals, constants, subtypes,
and enumeration types be declared in the architecture's declarative region,
close to their first use where the tool allows. This makes it easier for the
reader to find the declaration and see the signal type.

VHDL requires all declarations to appear in the declarative region before
the `begin` of the architecture or process. Within that constraint, group
related declarations together and order them logically.

### Basic Template

***A template that demonstrates many of the items in this guide is given
below.***

```vhdl
-- Copyright <organization>.
-- Licensed under the Apache License, Version 2.0, see LICENSE for details.
-- SPDX-License-Identifier: Apache-2.0
--
-- One-line description of the entity.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity my_module is
  generic (
    Width  : positive := 80;
    Height : positive := 24
  );
  port (
    clk_i       : in  std_ulogic;
    rst_n_i     : in  std_ulogic;
    req_valid_i : in  std_ulogic;
    req_data_i  : in  std_ulogic_vector(Width - 1 downto 0);
    req_ready_o : out std_ulogic
  );
end entity my_module;

architecture rtl of my_module is

  signal req_data_masked : std_ulogic_vector(Width - 1 downto 0);

begin

  u_submodule : entity work.submodule
    generic map (
      Width => Width
    )
    port map (
      clk_i        => clk_i,
      rst_n_i      => rst_n_i,
      req_valid_i  => req_valid_i,
      req_data_i   => req_data_masked,
      req_ready_o  => req_ready_o
    );

  p_comb : process(all) is
  begin
    req_data_masked <= req_data_i;
    case fsm_state_q is
      when ST_IDLE =>
        req_data_masked <= req_data_i and MASK_IDLE_C;
      when others =>
        null;
    end case;
  end process p_comb;

end architecture rtl;
```

---

## Naming

### Summary

| Construct | Style |
| --- | --- |
| Entity, architecture, package names | `lower_snake_case` |
| Instance labels | `lower_snake_case` with `u_` prefix |
| Signals, variables, aliases | `lower_snake_case` |
| Subprogram names (functions, procedures) | `lower_snake_case` |
| Named process and generate labels | `lower_snake_case` with `p_` / `gen_` prefix |
| Generics (tunable) | `UpperCamelCase` |
| Constants | `ALL_CAPS_C` (with `_C` suffix) or `UpperCamelCase` |
| Enumeration types | `lower_snake_case_t` (using `_t` suffix) |
| Enumerated values | `UpperCamelCase` or `ALL_CAPS` |
| Other type definitions (subtypes, records, arrays) | `lower_snake_case_t` |

### Constants

***Declare global constants using `constant` declarations in a project
package file.***

In this context, **constants** are distinct from tunable generics for
parameterized entities.

When declaring a constant:

*   within a package, use `constant`.
*   within an architecture or process, use `constant` in the local
    declarative region.

The preferred method of defining constants is to declare a `package` and
declare all constants within it. If constants are used in only one file, it
is acceptable to keep them within that file's architecture declarative region
rather than a separate package.

Define project-wide constants in the project's main package. Other packages
may also declare constants to facilitate IP re-use across projects.

The preferred naming convention for all immutable constants is `ALL_CAPS`
with a `_C` suffix (e.g., `NUM_CPU_CORES_C`). The `_C` suffix distinguishes
constants from signals and generics and is a clear visual indicator. When
`UpperCamelCase` feels more natural (e.g., for values that are enumeration-
like), it may be used, but the `_C` suffix must still be applied
(e.g., `DefaultDepthBytes_C`).

| Constant Type | Style Preference | Notes |
| --- | --- | --- |
| Package constant | `ALL_CAPS_C` | Truly constant, shared across design |
| Entity generic | `UpperCamelCase` | Modifiable at instantiation |
| Derived local constant (from generic) | `UpperCamelCase_C` | Tracks generic value |
| Locally tunable constant | `UpperCamelCase_C` | Used by designer to explore design space |
| True local constant | `ALL_CAPS_C` | Example: `OP_JALR_C` |
| Enumerated constant member | `ALL_CAPS` or `UpperCamelCase` | Example: `StIdle`, `OP_JALR` |

The units for a constant should be described in the symbol name unless the
constant is unitless or the units are bits. For example, `FOO_LENGTH_BYTES_C`.

✅
```vhdl
-- package-scope constant
package my_pkg is
  constant NUM_CPU_CORES_C : natural := 64;
  -- referenced elsewhere as my_pkg.NUM_CPU_CORES_C
end package my_pkg;
```

#### Parameterized Objects (entities, etc.)

***Use `generic` to parameterize entities and packages. Use local
`constant` declarations for architecture-scoped constants.***

You can create parameterized entities to facilitate design re-use.

Use the `generic` clause in the entity declaration to declare parameters that
the user is expected to tune at instantiation. The preferred naming convention
for all generics is `UpperCamelCase`. Some projects may choose `ALL_CAPS_C`
to differentiate tunable generics from signals, but consistency within a
project is mandatory.

Derived constants within an architecture should be declared as local
`constant` declarations. An example is shown below.

```vhdl
entity my_module is
  generic (
    Depth : positive := 2048;          -- 8 kB default
    Width : positive := 32
  );
  port (
    ...
  );
end entity my_module;

architecture rtl of my_module is
  constant AW_C : natural := integer(ceil(log2(real(Depth))));
begin
  ...
end architecture rtl;
```

**VHDL-2008 improvement:** Packages may also have generics (`package foo is
generic (...); end package foo;`), enabling parameterized shared type
definitions. Use this feature to create reusable, width-parameterized data
types without resorting to unconstrained types or global constants.

`defparam` does not exist in VHDL; generic defaults and `generic map` at
instantiation are the only mechanisms, and they must always be used explicitly.

Examples of when to use generics:

-   When multiple instances of an entity will be instantiated and need to be
    differentiated by a parameter.
-   As a means of specializing an entity for a specific bus width.
-   As a means of documenting which global parameters are permitted to change
    within the entity.

Explicitly declare the type for all generics. Use `positive` or `natural` for
non-negative integer generics, `boolean` for boolean flags. Any further
restrictions on generic values must be documented with `assert` statements in
the architecture body or, for static checks, in the entity's declarative
region.

Tunable generics must always have reasonable defaults.

### Suffixes

Suffixes are used in several places to communicate intent. The following table
lists suffixes that have special meaning.

| Suffix(es) | Arena | Intent |
| --- | :---: | --- |
| `_t` | type definition | All user-defined types (subtypes, records, arrays, enumerations) |
| `_C` | constant name | Constant (package, architecture, or process scope) |
| `_n` | signal name | Active-low signal |
| `_n`, `_p` | signal name | Differential pair, active-low and active-high respectively |
| `_d`, `_q` | signal name | Combinational next value and registered output of a flip-flop |
| `_q2`, `_q3`, etc. | signal name | Pipelined versions of signals; `_q` is one cycle, `_q2` two cycles, etc. |
| `_i`, `_o`, `_io` | signal name | Entity port inputs, outputs, and bidirectionals |

When multiple suffixes are necessary, use the following guidelines:

*   Guidance suffixes are combined without additional `_` separators
    (`_ni` not `_n_i`).
*   If the signal is active-low, `_n` will be the first suffix.
*   If the signal is a port, the direction suffix (`_i`, `_o`, `_io`) comes
    last.
*   It is not mandatory to propagate `_d` and `_q` to entity port boundaries.

Example:

✅
```vhdl
entity simple is
  port (
    clk_i     : in  std_ulogic;
    rst_n_i   : in  std_ulogic;   -- active-low reset

    -- writer interface
    data_i    : in  std_ulogic_vector(15 downto 0);
    valid_i   : in  std_ulogic;
    ready_o   : out std_ulogic;

    -- bidirectional bus
    driver_io : inout std_logic_vector(7 downto 0);

    -- differential pair output
    lvds_p_o  : out std_ulogic;   -- positive half
    lvds_n_o  : out std_ulogic    -- negative half
  );
end entity simple;

architecture rtl of simple is

  signal valid_d  : std_ulogic;
  signal valid_q  : std_ulogic;
  signal valid_q2 : std_ulogic;
  signal valid_q3 : std_ulogic;

begin

  valid_d <= valid_i;  -- next-state assignment

  p_reg : process(clk_i, rst_n_i) is
  begin
    if (rst_n_i = '0') then
      valid_q  <= '0';
      valid_q2 <= '0';
      valid_q3 <= '0';
    elsif rising_edge(clk_i) then
      valid_q  <= valid_d;
      valid_q2 <= valid_q;
      valid_q3 <= valid_q2;
    end if;
  end process p_reg;

  ready_o <= valid_q3;  -- three clock cycles delay

end architecture rtl;
```

### Enumerations

***Name enumeration types `snake_case_t`. Name enumeration values `ALL_CAPS`
or `UpperCamelCase`.***

Always name enumeration types using a `type` declaration. The `_t` suffix
must be applied to all user-defined type names.

Anonymous enumeration types assigned directly to a signal without a `type`
declaration are not allowed. They make it harder to use the type in other
contexts and across projects.

Enumeration type names should contain only lowercase alphanumeric characters
and underscores, and must be suffixed with `_t`.

Enumeration value names should typically be `ALL_CAPS` to reflect their
constant nature (for example, `READY_TO_SEND`). `UpperCamelCase` may be
preferred when the enumerated type represents states in a state machine whose
exact encoding is a don't-care to the designer (for example, `StIdle`,
`StFrameStart`).

✅
```vhdl
type opcode_t is (
  OP_JALR,   -- 0xA0 semantics
  OP_ADDI,   -- 0x47 semantics
  OP_LDW     -- 0x0B semantics
);
signal op_val : opcode_t;
```

✅
```vhdl
type access_t is (
  ACC_WRITE,
  ACC_READ,
  ACC_PAUSE
);
signal req_access  : access_t;
signal resp_access : access_t;
```

✅
```vhdl
-- UpperCamelCase style for FSM states where encoding is a don't-care.
type alcor_state_t is (
  StIdle, StFrameStart, StDynInstrRead, StBandCorr, StAccStoreWrite, StBandEnd
);
```

❌
```vhdl
-- Bad: no type declaration, anonymous enum.
signal req_access : (Write, Read);
```

**Note on encoding:** VHDL enumerations are unencoded by default; the
synthesis tool assigns binary encodings. To control encoding explicitly (for
one-hot, Gray code, etc.), use a `std_ulogic_vector` signal with named
constants, or use synthesis tool attributes such as `attribute enum_encoding`.
See the [Finite State Machines](#finite-state-machines) section for the
recommended FSM pattern.

### Signal Naming

***Use `lower_snake_case` when naming signals.***

In this context, a **signal** means any VHDL signal, variable, or port within
a design.

Signal names may contain lowercase alphanumeric characters and underscores.

Signal names should never end with an underscore followed only by a number
(for example, `foo_1`, `foo_2`). Many synthesis tools map buses into nets
using that naming convention, and similarly named nets can cause confusion when
examining a synthesized netlist.

Reserved [VHDL keywords](https://www.ics.uci.edu/~jmoorkan/vhdlref/reserv.html)
must never be used as names. When interoperating with other languages, be
mindful not to use keywords from those languages either.

#### Use Descriptive Names

***Names should describe what a signal's purpose is.***

Use whole words. Avoid abbreviations and contractions except in the most
common and universally understood cases. Favor descriptive signal names over
brevity.

#### Prefixes

Use common prefixes to identify groups of signals that operate together. For
example, all elements of an AXI-Stream interface would share a prefix:
`foo_valid`, `foo_ready`, and `foo_data`.

Additionally, prefixes should be used to clearly label which clock domain a
signal belongs to, in any module with multiple clocks. See the section on
[Clocks](#clocks) for more details.

Examples:

-   Signals associated with controlling a block RAM might share a `bram_`
    prefix.
-   Signals synchronous with `clk_dram_i` rather than `clk_i` should share a
    `dram_` prefix.

Use the following conventional prefixes for labeled constructs:

| Construct | Prefix |
| --- | --- |
| Process labels | `p_` |
| Generate labels | `gen_` |
| Instance labels | `u_` |
| Block labels | `b_` |

Code example:

✅
```vhdl
entity fifo_controller is
  port (
    clk_i         : in  std_ulogic;
    rst_n_i       : in  std_ulogic;

    -- writer interface
    wr_data_i     : in  std_ulogic_vector(15 downto 0);
    wr_valid_i    : in  std_ulogic;
    wr_ready_o    : out std_ulogic;

    -- reader interface
    rd_data_o     : out std_ulogic_vector(15 downto 0);
    rd_valid_o    : out std_ulogic;
    rd_fullness_o : out std_ulogic_vector(7 downto 0);
    rd_ack_i      : in  std_ulogic;

    -- memory interface
    mem_addr_o    : out std_ulogic_vector(7 downto 0);
    mem_wdata_o   : out std_ulogic_vector(15 downto 0);
    mem_we_o      : out std_ulogic;
    mem_rdata_i   : in  std_ulogic_vector(15 downto 0)
  );
end entity fifo_controller;
```

#### Hierarchical Consistency

***The same signal should have the same name at any level of the hierarchy.***

A signal that connects to a port of an instance should have the same name as
that port (minus the direction suffix `_i`/`_o`). By proceeding in this
manner, signals that are directly connected maintain the same name at any
level of hierarchy.

Expected exceptions to this convention include:

*   When connecting a port to an element of an array of signals.
*   When mapping a generic port name to something more specific to the design.
    For example, two generic blocks, one with a `host_bus` port and one with a
    `device_bus` port, might be connected by a `foo_bar_bus` signal.

In each exceptional case, take care to make the mapping of port names to
signal names as unambiguous and consistent as possible.

### Clocks

***All clock signals must begin with `clk`.***

The main system clock for a design must be named `clk_i` (as a port) or
`clk` (as an internal signal). It is acceptable to use `clk` to refer to
the default clock with which the majority of the logic in a module is
synchronous.

If a module contains multiple clocks, non-primary clocks should be named
with a unique identifier preceded by `clk_`. For example: `clk_dram_i`,
`clk_axi_i`. This prefix is then used to identify signals in that clock
domain.

### Resets

***Resets are active-low and asynchronous by default. The default port name
is `rst_n_i`.***

Unless a specific synchronous reset topology is required, resets are
defined as active-low and asynchronous. They are tied to the asynchronous
reset input of standard-cell flip-flops.

The default port name is `rst_n_i`. If resets must be distinguished by their
clock domain, include the clock name: `rst_dram_n_i`.

The preferred reset style in VHDL-2008 is:

```vhdl
-- preferred: asynchronous active-low reset
p_reg : process(clk_i, rst_n_i) is
begin
  if (rst_n_i = '0') then
    q <= '0';
  elsif rising_edge(clk_i) then
    q <= d;
  end if;
end process p_reg;
```

For synchronous resets (where required by the target technology or design
policy), use `process(all)` with the reset checked inside the clocked branch:

```vhdl
-- synchronous active-low reset (use only when required)
p_reg : process(clk_i) is
begin
  if rising_edge(clk_i) then
    if (rst_n_i = '0') then
      q <= '0';
    else
      q <= d;
    end if;
  end if;
end process p_reg;
```

**Note:** The choice between synchronous and asynchronous reset must be
consistent across a design and must be documented. Mixing reset styles within
a clock domain is not permitted without explicit justification.

---

## Language Features

### Preferred VHDL-2008 Constructs

Use these VHDL-2008 constructs instead of their older VHDL-93/2002
equivalents:

-   `process(all)` is required over manually written sensitivity lists for
    combinational processes.
-   `std_ulogic` / `std_ulogic_vector` are preferred over `std_logic` /
    `std_logic_vector` for internal signals (see
    [Use std_logic for Synthesis](#use-std_logic-for-synthesis)).
-   Concurrent conditional signal assignments (`<=  ... when ... else ...`)
    and selected signal assignments (`with ... select ...`) are preferred
    over equivalent `process` blocks for simple combinational logic.
-   `ieee.numeric_std` with `unsigned` / `signed` types is required over the
    non-standard `std_logic_arith` / `std_logic_unsigned` packages.
-   Entity instantiation (`entity work.foo(rtl)`) is preferred over component
    declarations and component instantiation.
-   Package-scoped constants are preferred over locally repeated magic numbers.
-   `context` clauses are preferred when the same set of `library`/`use`
    declarations is shared across many files in a project.

**VHDL-2008 context clause example:**

```vhdl
-- File: my_project_context.vhd
context my_project_ctx is
  library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  library work;
  use work.my_project_pkg.all;
end context my_project_ctx;

-- Usage in other files:
context work.my_project_ctx;
```

### Package Dependencies

***Packages must not have cyclic dependencies.***

Package files may depend on constants and types in other package files, but
there must not be any cyclic dependencies. If package A depends on a type
from package B, package B must not depend on anything from package A. While
VHDL tool behavior with cyclic dependencies is tool-dependent, their use
creates ordering problems and is prohibited.

```vhdl
-- In package foo:
library work;
use work.bar_pkg.all;

package foo_pkg is
  -- bar_pkg must not depend on anything in foo_pkg.
  constant PAGE_SIZE_BYTES_C : natural := 16 * bar_pkg.KIBI_C;
end package foo_pkg;
```

### Entity Declaration

***Use the full port declaration style with a distinct generic clause and
port clause.***

The entity declaration must fully specify all port names, modes, and types.
Use `entity work.foo` direct instantiation and avoid legacy component
declaration style where possible.

The opening of the generic and port clauses must be on the same line as the
`generic` or `port` keyword, with the first entry on the following line.

The closing parenthesis of each clause must be on its own line.

The clock port(s) must be declared first in the port list, followed by all
reset inputs, then all other ports.

Port mode keywords (`in`, `out`, `inout`, `buffer`) must be aligned in
tabular style within each port clause.

Example without generics:

✅
```vhdl
entity foo is
  port (
    clk_i : in  std_ulogic;
    rst_n_i : in  std_ulogic;
    d_i   : in  std_ulogic_vector(7 downto 0);
    q_o   : out std_ulogic_vector(7 downto 0)
  );
end entity foo;
```

Example with generics:

✅
```vhdl
entity foo is
  generic (
    Width : positive := 8
  );
  port (
    clk_i   : in  std_ulogic;
    rst_n_i : in  std_ulogic;
    d_i     : in  std_ulogic_vector(Width - 1 downto 0);
    q_o     : out std_ulogic_vector(Width - 1 downto 0)
  );
end entity foo;
```

Do not use positional association in port maps or generic maps (with the
exception of a single generic whose meaning is unambiguous, such as bus
width).

❌
```vhdl
-- Bad: positional port association is not allowed.
u_foo : entity work.foo port map(clk_i, rst_n_i, d_in, q_out);
```

### Architecture Body

***Use a single named architecture per entity. Name the primary synthesis
architecture `rtl`. Name a behavioral simulation-only architecture `behav`
or `sim`.***

The architecture name must be included after the closing `end` keyword:

```vhdl
architecture rtl of my_module is
  -- declarative region
begin
  -- concurrent statements
end architecture rtl;
```

All signal, constant, type, and subprogram declarations must appear in the
architecture's declarative region (between `architecture ... is` and
`begin`). No declarations may appear in the statement region.

### Component Instantiation and Direct Entity Instantiation

***Use direct entity instantiation. Avoid component declarations unless
required for third-party IP or legacy compatibility.***

VHDL-2008 direct entity instantiation eliminates the need for a separate
component declaration, reducing verbosity and the risk of interface mismatch.

✅ Direct entity instantiation (preferred):
```vhdl
u_my_instance : entity work.my_module(rtl)
  generic map (
    Width => 16
  )
  port map (
    clk_i   => clk_i,
    rst_n_i => rst_n_i,
    d_i     => from_here,
    q_o     => to_there
  );
```

❌ Component instantiation (avoid in new code):
```vhdl
-- Requires a matching component declaration above.
component my_module is
  generic (Width : positive := 8);
  port (clk_i : in std_ulogic; ...);
end component;

u_my_instance : my_module
  generic map (Width => 16)
  port map (clk_i => clk_i, ...);
```

Use component instantiation only when:

-   Instantiating vendor-provided primitives or IP for which no VHDL source is
    compiled into the work library.
-   Interfacing with encrypted or netlist IP.

All declared ports must be present in the port map. Unconnected output ports
must be explicitly marked with `open`. Unused input ports must be explicitly
tied to their inactive value (e.g., `'0'` or `(others => '0')`).

✅
```vhdl
u_my_instance : entity work.my_module(rtl)
  port map (
    clk_i        => clk_i,
    rst_n_i      => rst_n_i,
    d_i          => from_here,
    q_o          => to_there,
    unused_out_o => open,           -- explicitly unconnected
    unused_in_i  => (others => '0') -- explicitly tied off
  );
```

Instantiate ports in the same order as they are defined in the entity. Align
port map associations in tabular style. Do not include whitespace after `=>`
before the connected signal.

Do not instantiate recursively.

***Use named association for all generic maps and port maps.***

```vhdl
u_my_module : entity work.my_module(rtl)
  generic map (
    Height => 5,
    Width  => 10
  )
  port map (
    clk_i   => clk_i,
    rst_n_i => rst_n_i,
    d_i     => data_in,
    q_o     => data_out
  );
```

### Constants and Generics

***It is recommended to use symbolically named constants instead of raw
numbers.***

Try to give commonly used constants symbolic names rather than repeatedly
typing raw numbers.

Local constants must always be declared using `constant` in the appropriate
declarative region (architecture, process, or package).

Global constants must always be declared in a package.

Include the units for a constant as a suffix in the constant's symbolic name.
The exceptions are for constants that are inherently unitless, or if the
constant describes the default unit type (bits).

```vhdl
constant INTERFACE_WIDTH_C       : natural := 64;
constant INTERFACE_WIDTH_BYTES_C : natural := (INTERFACE_WIDTH_C + 7) / 8;
constant IMAGE_WIDTH_PIXELS_C    : natural := 640;
constant MEGA_C                  : natural := 1000 * 1000;  -- unitless
constant MEBI_C                  : natural := 1024 * 1024;  -- unitless
constant SYSTEM_CLOCK_HZ_C       : natural := 200 * MEGA_C;
```

### Signal Widths and Types

***Be careful about signal widths.***

#### Always be explicit about the widths of number literals

When assigning numeric literals to `std_ulogic_vector` or `unsigned`/`signed`
signals, the literal must have an unambiguous length. Use appropriately sized
string literals or convert via numeric types.

✅
```vhdl
constant BAR_C : std_ulogic_vector(3 downto 0) := x"4";  -- 4-bit hex literal
signal foo     : std_ulogic_vector(7 downto 0);
...
foo <= x"02";  -- explicit 8-bit value
foo <= std_ulogic_vector(to_unsigned(2, 8));  -- explicit width conversion
```

❌
```vhdl
-- Bad: implicit conversion, width may be ambiguous.
foo <= "10";      -- how wide is this?
foo <= "0000010"; -- seven bits, not eight
```

For `integer` or `natural` signals (rare in RTL), a plain decimal literal
is acceptable:

```vhdl
constant DEPTH_C : natural := 256;  -- unitless integer literal is fine
```

#### Port connections must always match widths correctly

Explicit width matching is required. Do not rely on implicit zero-extension
or truncation. Use `resize` from `ieee.numeric_std` or explicit
concatenation to adjust widths.

✅
```vhdl
u_module : entity work.my_module(rtl)
  port map (
    -- Explicit zero-extension from 16 to 32 bits.
    thirty_two_bit_input_i => std_ulogic_vector(
        resize(unsigned(sixteen_bit_word), 32))
  );
```

❌
```vhdl
u_module : entity work.my_module(rtl)
  port map (
    -- Bad: implicit extension, VHDL will error on width mismatch.
    thirty_two_bit_input_i => sixteen_bit_word
  );
```

#### Do not use multi-bit signals in a boolean context

Rather than using a multi-bit signal directly in an `if` condition or as a
boolean expression, explicitly compare the signal to zero. The implicit
reduction can hide subtle logic bugs and is not even valid VHDL for
`std_ulogic_vector` signals (VHDL requires scalar boolean conditions in `if`
statements).

✅
```vhdl
signal a, b : std_ulogic_vector(3 downto 0);
signal out  : std_ulogic;

out <= '1' when (a /= x"0") and (b = x"0") else '0';

p_comb : process(all) is
begin
  if (a /= x"0") then
    ...
  end if;
end process p_comb;
```

❌
```vhdl
-- Bad: std_ulogic_vector cannot be used as a boolean condition directly.
-- This is a compile error in VHDL.
if (a) then  -- illegal
  ...
end if;
```

#### Bit Slicing

Only use slice notation when the intent is to refer to a portion of a vector.
Do not redundantly slice a signal to its full range, as this masks linter
warnings about width mismatches.

✅
```vhdl
signal a, b : std_ulogic_vector(7 downto 0);
signal c    : std_ulogic_vector(6 downto 0);

a <= x"07";          -- good: full assignment
a(7 downto 1) <= "0000101";  -- good: partial assignment
a <= b;              -- good: width must match; tools warn on mismatch
```

❌
```vhdl
a(7 downto 0) <= x"07";   -- bad: redundant, masks linter warnings
a <= b(7 downto 0);        -- bad: redundant slice, masks linter warnings
```

#### Handling Width Overflow

Beware of arithmetic operations that can produce a result wider than the
operands. Use `resize` explicitly to manage width, or use the
`ieee.numeric_std` arithmetic operators which preserve precision:

```vhdl
signal cnt_d, cnt_q : unsigned(3 downto 0);

-- Drop carry explicitly using resize:
cnt_d <= resize(cnt_q + to_unsigned(1, cnt_q'length), cnt_q'length);

-- Or, equivalently, truncate via slice after addition:
cnt_d <= (cnt_q + 1)(3 downto 0);
```

### Signal Assignments: Sequential vs. Combinational

***Sequential processes use signal assignment (`<=`). Combinational processes
also use signal assignment.***

Unlike Verilog, VHDL does not have separate blocking and non-blocking
assignment operators for signals. Signal assignments (`<=`) within a process
are always scheduled (non-blocking in Verilog terms); their updated values
are not immediately visible within the same process. This is the correct
behavior for both sequential and combinational logic described using
`process`.

Within a process, **do not use variable assignments** (`variable v : ...; v := ...`)
to perform sequential logic. Variables update immediately and can introduce
simulation/synthesis mismatches if misused. Variables are permitted as local
temporaries within combinational processes.

***Rules:***

*   Sequential processes: use only signal assignments (`<=`).
*   Combinational processes: use only signal assignments (`<=`). Variables
    may be used as local temporaries, but must not be shared via `shared
    variable`.
*   Never mix sequential and combinational logic in the same process.

### Delay Modeling

***Do not use `after` delays in synthesizable design modules.***

Synthesizable design modules must be designed around a zero-delay simulation
methodology. All forms of `after`, including `after 0 ns`, are not permitted
in synthesizable RTL. The `after` clause is only permitted in simulation test
benches.

### Sequential Logic (Latches)

***The use of latches is discouraged. Use flip-flops when possible.***

Unless absolutely necessary, use registers instead of latches.

If a latch is required, describe it explicitly with a level-sensitive
process whose sensitivity list includes both the enable and data inputs, and
use a clear comment to document the intent:

```vhdl
-- Intentional latch: use only if required by design specification.
p_latch : process(all) is
begin
  if (enable = '1') then
    q <= d;  -- latch: transparent when enable is high
  end if;
  -- Note: no else branch => latch behavior
end process p_latch;
```

Incomplete `if` or `case` statements in a combinational process
(`process(all)`) infer latches. Every signal assigned in a combinational
process must be assigned in all branches. Assign defaults before any
conditional logic to ensure complete coverage.

### Sequential Logic (Registers)

***Use the standard format for describing sequential processes.***

Sequential statements for state assignments should contain only the reset
values and the next-state to state assignment. Use a separate combinational
process to generate the next-state value.

A correctly implemented 8-bit register with an asynchronous active-low reset
and an initial value of `0xAB`:

✅
```vhdl
signal foo_q  : std_ulogic_vector(7 downto 0);
signal foo_d  : std_ulogic_vector(7 downto 0);
signal foo_en : std_ulogic;

p_reg : process(clk_i, rst_n_i) is
begin
  if (rst_n_i = '0') then
    foo_q <= x"AB";
  elsif rising_edge(clk_i) then
    if (foo_en = '1') then
      foo_q <= foo_d;
    end if;
  end if;
end process p_reg;
```

Do not assign the same signal in multiple conditional branches that could
both be true simultaneously. For example, assigning `foo_q` in both an `if`
and a subsequent `if` (rather than `elsif`) within a process is a style
violation.

Exception: it is fine to establish default values for signals first and then
override them in specific branches. However, it is preferred to do this work
in a separate combinational process.

Example showing preferred two-process FSM style:

```vhdl
-- Sequential process: only reset and state register.
p_state_reg : process(clk_i, rst_n_i) is
begin
  if (rst_n_i = '0') then
    state_q <= StIdle;
  elsif rising_edge(clk_i) then
    state_q <= state_d;
  end if;
end process p_state_reg;

-- Combinational process: next-state and output decode.
p_state_comb : process(all) is
begin
  state_d <= state_q;   -- default: stay in current state
  case state_q is
    when StIdle =>
      if (conditional = '1') then
        state_d <= StInit;
      end if;
    when StInit =>
      if (conditional = '1') then
        state_d <= StIdle;
      else
        state_d <= StCalc;
      end if;
    when StCalc =>
      if (conditional = '1') then
        state_d <= StResult;
      end if;
    when StResult =>
      state_d <= StIdle;
    when others =>
      state_d <= StIdle;
  end case;
end process p_state_comb;
```

Keep work in sequential processes simple. If a sequential process becomes
sufficiently complicated, split the combinational logic into a separate
combinational process. Ideally, sequential processes should contain only a
register instantiation with a possible load enable.

### Unknown and Uninitialized Values

***The use of `'X'` literals in RTL code is strongly discouraged. RTL must
not assert `'X'` to indicate "don't care" to synthesis. To flag and detect
invalid conditions, designs should fully define all signal values and make
extensive use of VHDL `assert` statements to indicate invalid conditions.***

If not strictly controlled, the use of `'X'` assignments in RTL to flag
invalid or don't-care conditions can lead to simulation/synthesis mismatches.

Instead of assigning and propagating `'X'` in order to flag and detect invalid
conditions, it is encouraged to make **extensive use of VHDL assertions**. The
added benefits of this approach are:

- No special code style is required to properly propagate unknown conditions.
- The chance of accidentally introducing simulation/synthesis mismatches is
  systematically reduced.
- Simulation fails quickly and less signal backtracking is needed to root-cause
  bugs.
- In several cases, formal property verification (FPV) can be used to prove
  whether these assertions can always be fulfilled.
- In a security context, deterministic/defined behavior is desired even for
  illegal/invalid/unreachable input combinations.

**VHDL-2008 note:** VHDL does not have a direct equivalent to SystemVerilog's
`$isunknown()`. The recommended idiom for simulation-only unknown checking
is to use an `is_x()` function (available in some simulation libraries) or
to test each bit of a signal against `'X'` and `'U'`. For synthesizable RTL,
rely on `assert` statements with qualifying valid signals rather than checking
for unknown logic values.

#### Catching Errors Where Invalid Values Are Consumed

For an internally generated signal that could be invalid and is used to
trigger some action (such as a register write-enable), add an `assert`
statement to check that when the enable is true, the signal is in a valid
state. This triggers a clear failure when an invalid value has been
accidentally used.

```vhdl
signal reg_addr    : std_ulogic_vector(7 downto 0);
signal reg_wr_en   : std_ulogic;
signal special_reg_en : std_ulogic;

-- Combinational decode
special_reg_en <= '1' when (reg_addr = SPECIAL_REG_ADDR_C) and
                             (reg_wr_en = '1') else '0';

-- Assertion: special_reg_en implies reg_wr_en must be asserted.
p_assert_special_reg : process(all) is
begin
  assert not (special_reg_en = '1' and reg_wr_en = '0')
    report "special_reg_en asserted without reg_wr_en" severity error;
end process p_assert_special_reg;
```

#### Guidance on Case Statements and Conditional Assignments

Add assertions to signals that form the conditions of `case` statements or
conditional signal assignments. At minimum, assert that the controlling
signal is in a valid enumeration state or falls within an expected range.

```vhdl
type mode_t is (MODE_ENC, MODE_DEC);
type len_t  is (LEN_128, LEN_192, LEN_256);

signal mode_i : mode_t;
signal len_i  : len_t;
signal val    : std_ulogic_vector(7 downto 0);

-- Concurrent conditional assignment
val <= x"01" when (mode_i = MODE_ENC) else
       x"36" when (mode_i = MODE_DEC and len_i = LEN_128) else
       x"80" when (mode_i = MODE_DEC and len_i = LEN_192) else
       x"40" when (mode_i = MODE_DEC and len_i = LEN_256) else
       x"00";

-- Optional: explicit assertion for combinations used in conditional
p_val_sel_assert : process(all) is
begin
  assert (mode_i = MODE_ENC) or (mode_i = MODE_DEC)
    report "mode_i is in unexpected state" severity error;
end process p_val_sel_assert;
```

#### Dynamic Array Indexing

Dynamic array indexing operations can lead to out-of-range conditions that
produce `'X'` in simulation or incorrect behavior in synthesis. Avoid this
by either aligning indexed arrays to powers of two or by adding guarding
conditions around the indexing operation.

❌
```vhdl
signal selected : std_ulogic;
signal idx      : unsigned(3 downto 0);
signal foo      : std_ulogic_vector(11 downto 0);  -- problematic: not a power of 2

foo      <= x"AF0";
selected <= foo(to_integer(idx));  -- out of range if idx >= 12
```

✅
```vhdl
signal selected : std_ulogic;
signal idx      : unsigned(3 downto 0);
signal foo      : std_ulogic_vector(15 downto 0);  -- aligned to power of 2

foo      <= x"0AF0";
selected <= foo(to_integer(idx));  -- safe: 0..15 all valid indices
```

✅
```vhdl
signal selected : std_ulogic;
signal idx      : unsigned(3 downto 0);
signal foo      : std_ulogic_vector(11 downto 0);

foo <= x"AF0";
-- Guarding condition prevents out-of-range access.
selected <= foo(to_integer(idx)) when (to_integer(idx) < foo'length) else '0';
```

### Combinational Logic

***Use `process(all)` for combinational blocks. Use concurrent signal
assignments for simple logic.***

Use `process(all)` for combinational processes in VHDL-2008. This eliminates
the need for manually maintained sensitivity lists, which are a common source
of simulation/synthesis mismatches in VHDL-93/2002.

**VHDL-2008 improvement:** `process(all)` is the VHDL-2008 equivalent of
SystemVerilog's `always_comb`. It automatically infers the correct
sensitivity list.

❌ (VHDL-93/2002 style — avoid in new code):
```vhdl
-- Bad: manual sensitivity list is error-prone.
process(a, b, sel) is
begin
  if (sel = '1') then
    result <= a;
  else
    result <= b;
  end if;
end process;
```

✅ (VHDL-2008 preferred):
```vhdl
-- Good: process(all) auto-infers sensitivity list.
p_mux : process(all) is
begin
  if (sel = '1') then
    result <= a;
  else
    result <= b;
  end if;
end process p_mux;
```

Prefer concurrent signal assignments (`<=`) wherever practical for simple
expressions:

✅
```vhdl
final_value <= value_a when (xyz = '1') else value_b;
```

**VHDL-2008 conditional and selected signal assignments** can replace many
`process` blocks:

✅ Conditional assignment (replaces a simple if/else process):
```vhdl
out_signal <= value_a when (condition_a = '1') else
              value_b when (condition_b = '1') else
              value_default;
```

✅ Selected signal assignment (replaces a simple case process):
```vhdl
with select_sig select
  out_signal <= value_a when SEL_A,
                value_b when SEL_B,
                value_c when SEL_C,
                (others => '0') when others;
```

Do not use three-state logic (`'Z'` state) to accomplish on-chip logic such
as multiplexing. Three-state logic is only appropriate for physical I/O pads.

Do not infer a latch inside a function, as this may cause a
simulation/synthesis mismatch.

### Case Statements

***Always define a `when others` alternative. Use `case?` for wildcard
matching in VHDL-2008.***

Every `case` statement must include a `when others =>` alternative, even if
all enumerated values are covered. This prevents simulation/synthesis
mismatches: a case expression that evaluates to an out-of-range value at
simulation time will fall through to `when others` rather than producing
undefined behavior.

Here is an example of a style-compliant full case statement:

```vhdl
p_comb : process(all) is
begin
  case select is
    when "000" => operand <= accum0;
    when "001" => operand <= accum0(6 downto 0) & '0';
    when "010" => operand <= accum1;
    when "011" => operand <= accum1(6 downto 0) & '0';
    when others => operand <= (others => '0');
  end case;
end process p_comb;
```

A frequently used variant places default assignments before the `case` block,
allowing individual `when` alternatives to omit common assignments. This is
the recommended pattern for FSM next-state decode:

```vhdl
p_state_comb : process(all) is
begin
  -- Common defaults
  state_d <= state_q;
  outa    <= '0';
  outb    <= '0';
  outc    <= '0';

  case state_q is
    when StIdle =>
      state_d <= StWork;
      outa    <= in0;
    when StWork =>
      state_d <= StWait;
      outb    <= in1;
    when StWait =>
      state_d <= StIdle;
      outc    <= in2;
    -- when others always included; null is permissible due to defaults above
    when others =>
      null;
  end case;
end process p_state_comb;
```

**Wildcards in case items:**

-   Use `case` if wildcard behavior is not needed.
-   Use `case?` (VHDL-2008 matching case) if wildcard matching against
    `'-'` (don't-care) values is needed for `std_ulogic` or
    `std_ulogic_vector` signals. This is the VHDL-2008 equivalent of
    `casez` with `?` wildcards.

**VHDL-2008 `case?` example:**

✅
```vhdl
-- VHDL-2008 matching case: '-' in when alternatives acts as a wildcard.
p_priority : process(all) is
begin
  case? select_slv is
    when "1--" => operand <= accum0;   -- top bit set: use accum0
    when "01-" => operand <= accum1;   -- bit 1 set: use accum1
    when "001" => operand <= accum2;
    when others => operand <= (others => '0');
  end case?;
end process p_priority;
```

Do not use `'X'` or `'U'` as wildcard values in case items; use `'-'` in
`case?` matching statements only.

### Generate Constructs

***Always label your generate regions.***

When using a generate construct, always explicitly label each region using
the `gen_` prefix. Name each possible outcome of an `if generate` statement,
and name the iterated block of a `for generate` statement. This ensures that
generated hierarchical signal names are consistent across different tools.

Generate labels should use `lower_snake_case` with the `gen_` prefix. A
space should be placed between the label and the colon.

Example of a conditional generate construct:

✅
```vhdl
gen_posedge : if TypeIsPosedge generate
  p_reg : process(clk_i) is
  begin
    if rising_edge(clk_i) then
      foo <= bar;
    end if;
  end process p_reg;
else generate  -- gen_negedge (VHDL-2008 allows else/elsif in if generate)
  p_reg : process(clk_i) is
  begin
    if falling_edge(clk_i) then
      foo <= bar;
    end if;
  end process p_reg;
end generate gen_posedge;
```

**VHDL-2008 improvement:** `if generate` now supports `elsif` and `else`
branches, eliminating the need for paired complementary `if generate`
statements.

Example of a loop generate construct:

✅
```vhdl
gen_buses : for ii in 0 to NUMBER_OF_BUSES_C - 1 generate
  u_my_bus : entity work.my_bus(rtl)
    generic map (Index => ii)
    port map (
      foo_i => foo_i,
      bar_o => bar_o(ii)
    );
end generate gen_buses;
```

### Signed and Unsigned Arithmetic

***Use `ieee.numeric_std` with `unsigned` and `signed` types wherever
arithmetic is used.***

Do not use the non-standard packages `std_logic_arith`, `std_logic_unsigned`,
or `std_logic_signed`. These packages are not part of any IEEE standard and
their behavior is inconsistent across tools.

When it is necessary to convert between types, use the explicit conversion
functions from `ieee.numeric_std`:

-   `unsigned(slv)` to treat a `std_ulogic_vector` as unsigned.
-   `signed(slv)` to treat a `std_ulogic_vector` as signed.
-   `std_ulogic_vector(u)` or `std_logic_vector(u)` to convert back.
-   `to_integer(u)` to convert `unsigned` or `signed` to `integer`.
-   `to_unsigned(int, width)` to convert `integer` to `unsigned`.
-   `to_signed(int, width)` to convert `integer` to `signed`.
-   `resize(u, new_width)` to change the width of `unsigned` or `signed`,
    sign-extending for `signed`.

Example of implicit signed-to-unsigned promotion hazard:

```vhdl
signal a    : signed(7 downto 0);
signal incr : std_ulogic;
signal sum1 : signed(15 downto 0);
signal sum2 : signed(15 downto 0);

-- VHDL does not implicitly mix signed/unsigned: this is a compile error.
-- sum1 := a + incr;  -- type mismatch

-- Correct: explicit conversion before arithmetic.
sum2 <= resize(a, 16) + resize(signed('0' & incr), 16);  -- sign-extended add
```

If any operand in a calculation is `unsigned`, ensure all operands are
explicitly cast to maintain the intended signedness. Avoid relying on
implicit type promotions.

### Number Formatting

***Prefer hex or binary literals with underscores for clarity. Always
specify the base explicitly.***

When assigning constant values, use `std_ulogic_vector` string literals in
the appropriate base:

-   Hexadecimal: `x"AB"` or `16#AB#`
-   Binary: `"1010_1111"` (use `_` grouping for values longer than 8 bits)
-   Decimal (for integer/natural/positive types only): plain decimal

For `report` statements in test benches and assertions, make the base of a
printed number clear. Use descriptive format specifiers:

✅
```vhdl
report "Value: 0x" & to_hstring(some_slv);   -- hex output
report "Value: 0b" & to_bstring(some_slv);   -- binary output (VHDL-2008)
report "Count: "  & integer'image(count);    -- decimal output
```

**VHDL-2008 improvement:** The functions `to_hstring`, `to_ostring`, and
`to_bstring` are defined in `ieee.std_logic_1164` (VHDL-2008) and provide
base-prefixed string conversion without manual formatting.

When assigning constant values, use underscore notation for hex or binary
values longer than 8 bits:

✅
```vhdl
signal val0  : std_ulogic_vector(15 downto 0);
signal addr1 : std_ulogic_vector(39 downto 0);

val0  <= x"0000";
val0  <= "0010_0011_0000_1101";   -- binary with grouping underscores
addr1 <= x"00_1FC0_0000";         -- 40-bit hex with grouping
```

### Functions and Procedures

The following section applies to synthesizable RTL only.

***In synthesizable RTL, the use of functions is recommended. Procedures
may be used with care, but should not infer state.***

Functions and procedures must be declared in either a package or within an
architecture's declarative region. A package is appropriate where the
subprogram relates to other definitions in that package and could be useful
to multiple architectures. An architecture declarative region is appropriate
where the subprogram specifically relates to the internals of that entity.

Functions should aim to represent reusable blocks of combinational logic.

The types of all parameters and the return type must be explicitly declared.
All types used in synthesizable subprograms must be `std_ulogic`,
`std_ulogic_vector`, `unsigned`, `signed`, or types derived from these.

Do not use `out` or `inout` on function parameters. All functions should
consume inputs and produce exactly one output via the `return` statement.
Use procedures (with `out` parameters) only for simulation utilities.

❌
```vhdl
-- Bad: uses out parameter in function, implicit types.
function foo(a : std_ulogic_vector; b : out std_ulogic_vector)
    return std_ulogic_vector is
begin
  b := a;
  return a xor b;
end function foo;
```

✅
```vhdl
function foo(
  a : std_ulogic_vector(2 downto 0);
  b : std_ulogic_vector(2 downto 0)
) return std_ulogic_vector is
begin
  return a xor b;
end function foo;
```

✅ Using a named result variable for clarity:

```vhdl
function foo(
  a : std_ulogic_vector(2 downto 0);
  b : std_ulogic_vector(2 downto 0)
) return std_ulogic_vector is
  variable result : std_ulogic_vector(2 downto 0);
begin
  if (a = "010") then
    result := b;
  else
    result := a xor b;
  end if;
  return result;
end function foo;
```

All local variables must be assigned in all code paths, either through an
initial assignment or through the use of `else` and `when others` for `if`
and `case` statements:

✅
```vhdl
function foo(
  a : std_ulogic_vector(2 downto 0);
  b : std_ulogic_vector(2 downto 0)
) return std_ulogic_vector is
  variable local_var_1 : std_ulogic_vector(2 downto 0);
  variable local_var_2 : std_ulogic_vector(2 downto 0);
begin
  local_var_1 := (others => '0');  -- initial default

  if (a = "000") then
    local_var_1 := "010";
  end if;

  case b is
    when "000"  => local_var_2 := "001";
    when "001"  => local_var_2 := "011";
    when others => local_var_2 := (others => '0');
  end case;

  return local_var_1 xor local_var_2;
end function foo;
```

❌
```vhdl
function foo(
  a : std_ulogic_vector(2 downto 0);
  b : std_ulogic_vector(2 downto 0)
) return std_ulogic_vector is
  variable local_var_1 : std_ulogic_vector(2 downto 0);
  variable local_var_2 : std_ulogic_vector(2 downto 0);
begin
  -- Bad: local_var_1 not assigned if a /= "000".
  if (a = "000") then
    local_var_1 := "010";
  end if;

  -- Bad: no when others: local_var_2 may be uninitialized.
  case b is
    when "000" => local_var_2 := "001";
    when "001" => local_var_2 := "011";
  end case;

  return local_var_1 xor local_var_2;
end function foo;
```

Functions must not reference any non-local signals or variables outside their
scope. Avoiding non-local references improves readability and prevents
simulation/synthesis mismatches. Accessing non-local constants and generics
is allowed.

❌
```vhdl
-- Bad: mem and in_i are not local to get_mem().
architecture rtl of mymod is
  signal mem  : std_ulogic_vector_array_t(0 to 255)(7 downto 0);

  function get_mem return std_ulogic_vector is
  begin
    return mem(to_integer(unsigned(in_i)));  -- non-local reference: bad
  end function get_mem;
begin
  out_o <= get_mem;
end architecture rtl;
```

✅
```vhdl
-- Good: constants are allowed; in_i passed as argument.
architecture rtl of mymod is
  constant MAGIC_VALUE_C : std_ulogic_vector(7 downto 0) := x"01";

  function is_magic(v : std_ulogic_vector(7 downto 0)) return boolean is
  begin
    return (v = MAGIC_VALUE_C) or (v = my_pkg.OTHER_MAGIC_VALUE_C);
  end function is_magic;
begin
  out_o <= '1' when is_magic(in_i) else '0';
end architecture rtl;
```

### Problematic Language Features and Constructs

These language features are considered problematic and their use is
discouraged unless otherwise noted:

-   `shared variable` without `protected` type (use `protected` type or
    avoid shared variables entirely).
-   Unconstrained arrays as signals or ports without explicit constraints at
    the point of use.
-   `transport` delay models in synthesizable code.
-   VHDL-2008 external names in synthesizable code (simulation use only).

#### Shared Variables

VHDL shared variables (declared without `protected`) have undefined behavior
when accessed concurrently from multiple processes. Their use in RTL is
prohibited.

**VHDL-2008 improvement:** If a shared mutable state is truly necessary in a
simulation context (not synthesizable RTL), use a `protected` type, which
provides defined, mutex-like access semantics:

```vhdl
-- For simulation/test bench use only, not for synthesizable RTL.
type shared_counter_t is protected
  procedure increment;
  impure function get_value return natural;
end protected shared_counter_t;

type shared_counter_t is protected body
  variable count : natural := 0;
  procedure increment is
  begin
    count := count + 1;
  end procedure increment;
  impure function get_value return natural is
  begin
    return count;
  end function get_value;
end protected body shared_counter_t;
```

#### Hierarchical References via External Names

VHDL-2008 introduces **external names** (e.g., `<< signal .tb.dut.internal_sig : std_ulogic >>`)
which allow direct access to internal signals from outside a design hierarchy.
The use of external names in synthesizable RTL code is prohibited. External
names may only be used in simulation test benches, and even there they should
be used sparingly: they create tight coupling between the test bench and the
design hierarchy, making refactoring difficult.

❌
```vhdl
-- Bad: external name in synthesizable RTL is prohibited.
architecture rtl of mymod is
  alias int_sig is << signal .top.mymod_int.int : std_ulogic >>;
begin
  out_o <= int_sig;  -- hierarchical reference via external name: prohibited
end architecture rtl;
```

---

## Design Conventions

### Summary

The key ideas in this section include:

*   Declare all signals explicitly: `signal foo : std_ulogic;`
*   Use `std_ulogic` for internal signals, `std_logic` only for resolved
    signals at bidirectional ports.
*   Vectors are declared with `downto` (little-endian bit ordering).
*   Arrays of records or vectors use `0 to N-1` (big-endian element ordering).
*   Prefer to register module outputs.
*   Declare FSMs consistently using a two-process style.

### Declare All Signals

***Do not rely on implicit signal types.***

All signals must be explicitly declared before use, with an explicit type.
VHDL requires signal declarations in the architecture declarative region; there
are no implicit net declarations as in Verilog. A correct design has no
implicit or untyped signals.

### Use std_logic for Synthesis

***Use `std_ulogic` for internal signals. Use `std_logic` only at resolved
(multi-driver) boundaries.***

All signals in synthesizable RTL must use `std_ulogic` or `std_ulogic_vector`
from `ieee.std_logic_1164`. This ensures that each signal has exactly one
driver, which is verified by the simulator. Using the resolved type `std_logic`
allows multiple drivers and suppresses the multi-driver error — masking design
bugs.

Use `std_logic` (resolved) only where multiple drivers are legitimately
required, specifically at `inout` bidirectional ports that interface to
tri-state bus structures on physical pins.

**VHDL-2008 note:** `std_ulogic` and `std_logic` are both nine-valued types
(`'U'`, `'X'`, `'0'`, `'1'`, `'Z'`, `'W'`, `'L'`, `'H'`, `'-'`). The
difference is resolution: `std_logic` is resolved (allows multiple drivers,
applies a resolution function) and `std_ulogic` is unresolved (single driver
only, generates a multiple-driver error).

✅
```vhdl
signal x_velocity : signed(31 downto 0);     -- 32-bit signed integer
subtype byte_t is std_ulogic_vector(7 downto 0);
```

❌
```vhdl
-- Bad: resolved type used for internal signals.
signal foo : std_logic;         -- use std_ulogic for internal signals
signal bar : std_logic_vector(7 downto 0);  -- use std_ulogic_vector
```

**Exception:** Port signals of type `std_logic` or `std_logic_vector` are
acceptable when interfacing with third-party IP or vendor primitives that
declare their ports using those resolved types. Such exceptions must be
justified with a comment.

### Logical vs. Bitwise Operators

***Prefer logical operators for boolean conditions; use bitwise operators
for data manipulation.***

In VHDL, the same keywords (`and`, `or`, `not`, `xor`, etc.) serve as both
logical and bitwise operators depending on context (scalar vs. vector
operands). Nevertheless, the intent should be made clear:

*   Use `and`, `or`, `not`, `xor` in boolean/conditional contexts for scalar
    `std_ulogic` signals.
*   Use `and`, `or`, `not`, `xor` in data contexts for `std_ulogic_vector`
    signals, but ensure the operands are clearly vectors and not scalars to
    avoid accidental reductions.
*   Use explicit comparison (`= '1'`, `= '0'`) rather than treating a scalar
    `std_ulogic` as a boolean.

✅
```vhdl
-- Sequential process: logical context.
p_reg : process(clk_i, rst_n_i) is
begin
  if (rst_n_i = '0') then
    reg_q <= (others => '0');
  elsif rising_edge(clk_i) then
    reg_q <= reg_d;
  end if;
end process p_reg;

-- Combinational: logical conditions.
p_comb : process(all) is
begin
  if (bool_a = '1') or ((bool_b = '1') and (bool_c = '0')) then
    x <= '1';
  else
    x <= '0';
  end if;
end process p_comb;

-- Bitwise data operation.
y <= (a and (not b)) or c;
```

❌
```vhdl
-- Bad: checking reset with 'not' applied to a std_ulogic is incorrect syntax
-- in VHDL (not is not a unary logical operator in a condition here).
if not rst_n_i then  -- illegal in VHDL; must compare to '0'
  ...
end if;
```

✅ Allowed: logical assignment for boolean test

```vhdl
-- Compute a boolean result from data signals.
request_valid <= '1' when (fifo_empty = '0') and (data_available = '1')
                     else '0';
```

### Array Ordering

***Bit vectors must be declared with `downto` (little-endian bit ordering).
Arrays of elements use `0 to N-1` (ascending element ordering).***

When declaring `std_ulogic_vector`, `unsigned`, or `signed` signals, use
`downto` so that the most-significant bit is on the left (index `N-1`) and
the least-significant bit is on the right (index `0`). This is consistent
with conventional bus notation.

```vhdl
subtype u8_t  is std_ulogic_vector(7 downto 0);
signal u32_word : std_ulogic_vector(31 downto 0);
```

For arrays of elements (records, vectors, etc.), use ascending index order
(`0 to N-1`) to match the conventional memory addressing direction:

```vhdl
type word_array_t is array (0 to 3) of std_ulogic_vector(15 downto 0);
signal word_array : word_array_t;
```

Do not declare arrays in descending element order (`N-1 downto 0`) unless
required by a specific interface convention, and never mix ordering styles
within a project without clear justification.

### Finite State Machines

***State machines use an enumerated type to define states and are implemented
with two process blocks: a combinational block and a clocked block.***

Every state machine description has three parts:

1.  A `type` declaration that defines the enumerated state type.
2.  A combinational process block that decodes state to produce next state
    and combinational outputs.
3.  A clocked process block that updates state from next state.

*Enumerating States*

The `type` declaration for the state machine must list each state. Comments
describing each state should be deferred to the `case` statement in the
combinational process block.

States should be named in `UpperCamelCase` with a `St` prefix, like other
[enumeration value names](#enumerations), or in `ALL_CAPS` for projects
that prefer that convention. Choose one style and apply it consistently.

The initial idle state of the state machine should be named `StIdle`.
Alternate names are acceptable if they improve clarity.

Each module should ideally contain only one state machine. If a module needs
more than one, add a unique prefix to the states: for example, a "reader"
machine and a "writer" machine might have `StRdIdle` and `StWrIdle`.

*Combinational Decode of State*

The combinational process block must contain:

-   Default assignments for all outputs and the next-state variable, before
    the `case` statement.
-   A `case` statement that decodes state to produce next state and
    combinational outputs.
-   The default value for next-state must be the current state.
-   Each `when` alternative should be preceded by a comment describing that
    state's function.

*The State Register*

No logic except for reset should be performed in this process. The state
register simply latches the next-state value.

*Example*

✅
```vhdl
-- Define the states.
type alcor_state_t is (
  StIdle, StFrameStart, StDynInstrRead, StBandCorr, StAccStoreWrite, StBandEnd
);

signal alcor_state_d : alcor_state_t;
signal alcor_state_q : alcor_state_t;

-- Combinational decode of the state.
p_alcor_comb : process(all) is
begin
  alcor_state_d <= alcor_state_q;
  foo <= '0';
  bar <= '0';
  bum <= '0';

  case alcor_state_q is
    -- StIdle: waiting for frame_start.
    when StIdle =>
      if (frame_start = '1') then
        foo           <= '1';
        alcor_state_d <= StFrameStart;
      end if;
    -- StFrameStart: reset accumulators.
    when StFrameStart =>
      -- ... etc ...
    -- Catch any parasitic or tool-inserted states.
    when others =>
      alcor_state_d <= StIdle;
  end case;
end process p_alcor_comb;

-- Register the state.
p_alcor_reg : process(clk_i, rst_n_i) is
begin
  if (rst_n_i = '0') then
    alcor_state_q <= StIdle;
  elsif rising_edge(clk_i) then
    alcor_state_q <= alcor_state_d;
  end if;
end process p_alcor_reg;
```

*FSM Encoding*

VHDL enumerations are encoded by the synthesis tool by default. To control
encoding (one-hot, Gray code, safe encoding), use synthesis tool-specific
attributes. Consult your tool's documentation. Example using a Xilinx-style
attribute:

```vhdl
type alcor_state_t is (StIdle, StFrameStart, StDynInstrRead);
attribute fsm_encoding : string;
attribute fsm_encoding of alcor_state_q : signal is "one_hot";
```

### Active-Low Signals

***The `_n` suffix indicates an active-low signal.***

If active-low signals are used, they must carry the `_n` suffix in their
name. Otherwise, all signals are assumed to be active-high.

Active-low resets must be compared explicitly to `'0'` to test for assertion:

```vhdl
if (rst_n_i = '0') then  -- active-low reset is asserted
  ...
end if;
```

### Differential Pairs

***Use the `_p` and `_n` suffixes to indicate a differential pair.***

For example, `in_p_i` and `in_n_i` comprise a differential pair on input ports.
For output ports: `out_p_o` and `out_n_o`.

### Delays

***Signals delayed by a single clock cycle should end in a `_q` suffix.***

If one signal is only a delayed version of another signal, the `_q` suffix
should be used to indicate this relationship. If another signal is then
delayed by another clock cycle, that signal should be suffixed `_q2`, then
`_q3`, and so on.

```vhdl
p_delay : process(clk_i) is
begin
  if rising_edge(clk_i) then
    data_valid_q  <= data_valid_d;
    data_valid_q2 <= data_valid_q;
    data_valid_q3 <= data_valid_q2;
  end if;
end process p_delay;
```

### Library and Package Use Clauses

***Use explicit `use` clauses. Wildcard `use ... all` is allowed only for
packages that are part of the same IP as the using entity.***

VHDL `use` clauses with `.all` make all public declarations from a package
visible. This is the VHDL equivalent of SystemVerilog wildcard package import.

The following rules apply:

*   `use ieee.std_logic_1164.all;` and `use ieee.numeric_std.all;` are
    universally permitted, as these are the standard packages.
*   `use work.<package_name>.all;` is permitted when the package is part of
    the same IP as the entity that uses it.
*   For packages from other IP blocks or external libraries, prefer qualified
    references (`my_pkg.MY_CONSTANT_C`) over wildcard `use` clauses to
    prevent namespace pollution and to make the origin of each identifier
    clear to the reader.

✅
```vhdl
-- mod_a_pkg.vhd and mod_a.vhd are in the same IP.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.mod_a_pkg.all;  -- same-IP package: wildcard is allowed

entity mod_a is
  port (
    a_req_i : in mod_a_pkg.a_req_t;  -- or just 'a_req_t' with use clause
    ...
  );
end entity mod_a;
```

❌
```vhdl
-- Bad: wildcard use of a package from a different IP.
use work.mod_b_pkg.all;  -- mod_b is a different IP block

entity mod_a is
  ...
end entity mod_a;
```

**VHDL-2008 `context` clauses** provide an alternative to repeating the same
set of `library` and `use` statements in every file. Declare a context in a
dedicated file and reference it from other files:

```vhdl
-- my_project_context.vhd
context my_project_ctx is
  library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  library work;
  use work.my_project_pkg.all;
end context my_project_ctx;

-- Usage:
context work.my_project_ctx;

entity foo is
  ...
end entity foo;
```

### Assertion Statements

***It is encouraged to use VHDL `assert` statements throughout the design
to check functional correctness and flag invalid conditions.***

VHDL provides built-in assertion syntax. In synthesizable RTL, use
concurrent assertions (placed in the architecture body alongside other
concurrent statements) for functional assertions, and immediate assertions
(inside processes) for local checks.

The standard assertion severities in VHDL are `note`, `warning`, `error`,
and `failure`. For RTL assertions:

*   `severity note` — informational, no action required.
*   `severity warning` — unexpected but non-fatal condition.
*   `severity error` — assertion failure; simulation should stop or the
    designer should investigate.
*   `severity failure` — fatal condition; simulation must stop.

Recommended assertion patterns:

```vhdl
-- Concurrent assertion: checks a condition every simulation delta cycle.
-- Equivalent to a continuous SVA.
assert_no_special_without_wr : assert
    not (special_reg_en = '1' and reg_wr_en = '0')
    report "special_reg_en asserted without reg_wr_en"
    severity error;

-- Immediate assertion inside a clocked process (checks on each clock edge).
p_reg : process(clk_i, rst_n_i) is
begin
  if (rst_n_i = '0') then
    state_q <= StIdle;
  elsif rising_edge(clk_i) then
    state_q <= state_d;
    -- Immediate assertion: checks at the time of this simulation event.
    assert (state_d /= ILLEGAL_STATE_C)
      report "FSM entered illegal state"
      severity error;
  end if;
end process p_reg;

-- Static/elaboration-time assertion: checks generic values at startup.
-- Placed in the architecture body.
assert_width_valid : assert (Width > 0 and Width <= 64)
    report "Width generic must be in range 1..64"
    severity failure;
```

Assertion labels must follow the `lower_snake_case` naming convention with
a descriptive name suffixed with `_a` or `_assert`:

```vhdl
assert_no_overflow_a : assert (cnt_q < MAX_COUNT_C)
    report "Counter overflow detected"
    severity error;
```

For design verification (test bench) environments, use `report` statements
for debug output and `assert` with `severity failure` to indicate test
failures:

```vhdl
-- In a test bench:
assert (dut_output = expected_output)
    report "Test failed: got 0x" & to_hstring(dut_output) &
           ", expected 0x" & to_hstring(expected_output)
    severity failure;
```

#### A Note on Security-Critical Applications

For security-critical applications, assertions that guard case statements and
conditional assignments against invalid input combinations must be clearly
labeled. Adopt a naming convention that marks security-critical assertions
(e.g., suffix `_sec_a`) to enable post-processing identification:

```vhdl
-- Security-critical assertion: input must be in a known valid encoding.
assert_sel_valid_sec_a : assert (sel_i = SEL_A_C or sel_i = SEL_B_C)
    report "sel_i is outside the valid set in a security-critical mux"
    severity error;
```

More security assertion and coding style guidance should be given in a
separate security-focused document.

---

## Appendix - Condensed Style Guide

This is a short summary of the preferred VHDL-2008 style. Refer to the main
text body for explanations, examples, and exceptions.

### Basic Style Elements

*   Use VHDL-2008 conventions; files named as `<entity_name>.vhd`, one
    entity/architecture pair per file.
*   Only ASCII; **100** characters per line maximum; **no** tabs; **two**
    spaces per indentation level for all paired keywords.
*   VHDL `--` single-line comments only.
*   For multiple items on a line, **one** space must separate the comma and
    the next character.
*   Include **whitespace** around keywords and binary operators.
*   **No** space between case item `when` and `=>`, between function name and
    opening parenthesis.
*   Line wraps should indent by **four** spaces.
*   Paired keyword closers (`end process`, `end if`, `end case`, `end entity`,
    etc.) must each start a new line.
*   Always repeat the label/name after closing paired keywords for top-level
    structures and any nested block exceeding 20 lines.

### Construct Naming

*   Use **lower\_snake\_case** for entity names, architecture names, signal
    names, variable names, process labels (with `p_` prefix), generate labels
    (with `gen_` prefix), instance labels (with `u_` prefix), type names
    (with `_t` suffix), and subprogram names.
*   Use **UpperCamelCase** for generic names and enumeration value names.
*   Use **ALL\_CAPS\_C** for constants (with `_C` suffix).
*   Main clock port is named `clk_i`. All clock signals must start with `clk`.
*   Reset signals are **active-low** and **asynchronous** by default; default
    port name is `rst_n_i`.
*   Signal names should be descriptive and consistent throughout the hierarchy.

### Suffixes for Signals and Types

*   Add `_i` to entity port inputs, `_o` to outputs, `_io` to bidirectionals.
*   The combinational next-state (next value) of a registered signal uses
    `_d`; the registered output uses `_q`.
*   Pipelined versions of signals: `_q2`, `_q3`, etc.
*   Active-low signals use `_n`. Differential pair signals use `_p` (positive)
    and `_n` (negative).
*   All user-defined type names use `_t` suffix.
*   All constants use `_C` suffix.
*   Multiple suffixes combine without extra `_`: `_n` before direction
    (`_ni`, `_no`).

### Language Features

*   Use **full port declaration style** for entities; clock and reset declared
    first.
*   Use **named association** for all generic maps and port maps; all declared
    ports must be present; no positional association.
*   Use **direct entity instantiation** (`entity work.foo(rtl)`) in preference
    to component instantiation.
*   Use **symbolically named constants** instead of raw numbers.
*   Global constants declared in packages; local constants in architecture
    declarative regions.
*   `std_ulogic` / `std_ulogic_vector` are preferred over `std_logic` /
    `std_logic_vector` for internal signals.
*   `process(all)` (VHDL-2008) is required for combinational processes.
*   Sequential and combinational logic must not be mixed in the same process.
*   Use of latches is discouraged; use flip-flops when possible.
*   The use of `'X'` assignments in RTL is strongly discouraged; make
    extensive use of VHDL `assert` statements to check invalid behavior.
*   Prefer concurrent signal assignments (`<= ... when ... else ...` and
    `with ... select ...`) wherever practical.
*   Every `case` statement must include `when others`.
*   Use `ieee.numeric_std` with `unsigned`/`signed` for arithmetic;
    do **not** use `std_logic_arith`, `std_logic_unsigned`, or
    `std_logic_signed`.
*   When printing/reporting, use `to_hstring`, `to_bstring` for hex/binary.
    Use `_` underscores in long binary and hex literals for readability.
*   FSMs: **no logic except for reset** should be in the state register
    process.
*   A combinational process should first define **default values** for all
    outputs before any conditional logic.
*   The default value for the next-state variable must be the current state.
*   Bit vectors use `downto`; element arrays use `0 to N-1`.
*   `shared variable` without `protected` type is prohibited in RTL.
*   VHDL-2008 external names are permitted in test benches only.
