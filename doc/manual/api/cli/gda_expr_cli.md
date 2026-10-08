# cli/gda_expr_cli API

`cli/gda_expr_cli` is the command-line runner for General Decimal Arithmetic
`.decTest` corpora. It reads files, parses them with
[`frontend/gda_expr`](../frontend/gda_expr.md), executes them against
`decimal_gda` and prints a text or JSON summary. It is normally reached
through the [`cli`](../cli.md) dispatcher as
`floating-conformance --backend gda …`. See the
[tutorial](../../tutorial/cli/gda_expr_cli.md) and the
[design page](../../design/cli/gda_expr_cli.md).

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
| `PATH …` | `.decTest` files or directories (direct entries ending in `.decTest`); default `testdata/decimal/smoke.decTest` |

Any other argument starting with `-` is an error `unknown option: …`. Files
are sorted, parsed in order (the first parse diagnostic of a file is printed as
`source:line:1: message` and ends the run), and executed together, so row
ordinals and shards span all files.

Text output lists the counts (`cases`, `selected cases`, `executable cases`,
`passed cases`, `failed cases`, `skipped cases`), the shard, and one
`failed ID: MESSAGE` line per failing row. JSON output has the keys
`totalCases`, `supportedCases` (executable rows), `diagnosticCases`,
`legacyConditionCases`, `unsupportedCases` and an `execution` object with
`executableCases`, `passedCases`, `failedCases`, `skippedCases`, `failedIds`,
`shardCount`, `shardIndex`.

Return value: `2` for usage, file or parse errors; `1` when a row failed, or
with `--strict-supported` when any legacy or unsupported row was selected;
`0` otherwise.

```moonbit
///|
test "gda runner usage errors" {
  inspect(@gda_expr_cli.run(["gda", "--frobnicate"]), content="2")
  inspect(@gda_expr_cli.run(["gda", "--shard-count", "0"]), content="2")
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
