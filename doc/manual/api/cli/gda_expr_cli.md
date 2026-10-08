# cli/gda_expr_cli API

## Purpose

`cli/gda_expr_cli` is the command-line runner for General Decimal Arithmetic
`.decTest` corpora. It reads files, parses them with
[`frontend/gda_expr`](../frontend/gda_expr.md), executes them against
`decimal_gda` and prints a text or JSON summary. It is normally reached
through the [`cli`](../cli.md) dispatcher as
`floating-conformance --backend gda …`. See the
[tutorial](../../tutorial/cli/gda_expr_cli.md) and the
[design page](../../design/cli/gda_expr_cli.md).

## Importing

The runner is a library, so it can be called from MoonBit code as well as
through the dispatcher. Add it to the `import` block of your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/cli/gda_expr_cli",
}
```

The examples use the alias `@gda_expr_cli`. `run` reads files through
`moonbitlang/x/fs`; the repository builds and tests the runners on the native
target.

## `run`

`run(arguments)` executes one invocation and returns the exit code.

```mbti
pub fn run(Array[String]) -> Int
```

`arguments[0]` is the program name and is ignored. Options:

| Option | Meaning |
| --- | --- |
| `--json` | print one JSON object instead of text |
| `--shard-count N`, `--shard-index I` (also `=` forms) | run shard `I` of `N` (default `1`, `0`) |
| `--strict-supported` | also fail when a selected row is unsupported or legacy |
| `--cases SPEC`, `--cases=SPEC` | row filter: comma-separated ids or `first..last` ranges (see `RunOptions::new`) |
| `--help`, `-h` | print the usage line and return `2` |
| `PATH …` | `.decTest` files or directories (direct file entries ending in `.decTest`); default `testdata/decimal/smoke.decTest` |

Any other argument starting with `-` is an error `unknown option: …`. A
directory contributes its direct file entries whose names end in `.decTest`
(a directory without any adds no file); a named file without that suffix is
the error `not a .decTest file: PATH`, and a path that does not exist is the
error `path does not exist: PATH`, both with exit status 2. Files are sorted,
each file is run once even if named twice, parsed in order (the first parse diagnostic of a file is printed as
`source:line:1: message` and ends the run), and executed together, so row
ordinals and shards span all files.

Text output lists the counts (`cases`, `selected cases`, `executable cases`,
`passed cases`, `failed cases`, `skipped cases`), the shard, and one
`failed ID: MESSAGE` line per failing row. JSON output has the keys
`totalCases`, `supportedCases` (executable rows), `diagnosticCases`,
`legacyConditionCases`, `unsupportedCases` and an `execution` object with
`executableCases`, `passedCases`, `failedCases`, `skippedCases`, `failedIds`,
`shardCount`, `shardIndex`. `totalCases` counts the rows that match
`--cases` in all shards; every other counter, including the top-level
`supportedCases`, `diagnosticCases`, `legacyConditionCases` and
`unsupportedCases`, counts only the rows of this shard. `legacyConditionCases`
is always 0 with the current frontend.

Return value: `2` for usage, file or parse errors; `1` when a row failed, or
with `--strict-supported` when any legacy or unsupported row was selected;
`0` otherwise. Diagnostic rows (`#` and `?` placeholders) never change the
exit status, even with `--strict-supported`.

```moonbit
///|
test "gda runner usage errors" {
  inspect(@gda_expr_cli.run(["gda", "--frobnicate"]), content="2")
  inspect(@gda_expr_cli.run(["gda", "--shard-count", "0"]), content="2")
  inspect(@gda_expr_cli.run(["gda", "--help"]), content="2")
}
```

## Complete public interface

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/cli/gda_expr_cli"

// Values
pub fn run(Array[String]) -> Int

// Errors

// Types and methods

// Type aliases

// Traits
```
<!-- generated-api-end -->
