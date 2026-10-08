# cli/testfloat_expr_cli API

## Purpose

`cli/testfloat_expr_cli` is the command-line runner for Berkeley TestFloat
vector files. It builds a `TestFloatSpec` from its options, parses one vector
file with [`frontend/testfloat_expr`](../frontend/testfloat_expr.md),
executes it against `bin_float` and prints a summary. It is normally reached as
`floating-conformance --backend testfloat …`. See the
[tutorial](../../tutorial/cli/testfloat_expr_cli.md) and the
[design page](../../design/cli/testfloat_expr_cli.md).

## Importing

The runner is a library, so it can be called from MoonBit code as well as
through the dispatcher. Add it to the `import` block of your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/cli/testfloat_expr_cli",
}
```

The examples use the alias `@testfloat_expr_cli`. `run` reads files through
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
| `--function NAME` | TestFloat function, for example `f64_mulAdd` (required) |
| `--rounding NAME` | rounding mode, default `rnear_even` |
| `--tininess NAME` | `after` (default) or `before` |
| `--exact` | the `-exact` variant of `roundToInt` and integer conversions |
| `--json` | print one JSON object instead of text |
| `--shard-count N`, `--shard-index I` (also `=` forms) | run shard `I` of `N` |
| `PATH` | exactly one vector file (required) |

The names are interpreted by `TestFloatSpec::parse`. A value option given
twice keeps the last value. `--help` is not an option of this runner and is
reported as `unknown option: --help`. Errors such as
`--function is required`, `a TestFloat vector path is required`,
`only one TestFloat vector file is accepted per invocation`, `unknown option:
…` or an unsupported name are printed and return `2`; so is the first parse
diagnostic of the file (`source:line:1: message`).

Text output prints the function, rounding, tininess, the counts `cases`,
`selected cases`, `passed cases`, `failed cases` and one `failed ID: MESSAGE`
line per failure. JSON output has the keys `function`, `rounding`,
`tininess`, `exact`, `totalCases`, `selectedCases`, `passedCases`,
`failedCases` and `failedIds`.

Return value: `2` for usage, specification, file or parse errors; `1` when a
vector failed; `0` otherwise.

```moonbit
///|
test "testfloat runner usage errors" {
  inspect(@testfloat_expr_cli.run(["testfloat", "vectors.tv"]), content="2")
  inspect(
    @testfloat_expr_cli.run(["testfloat", "--function", "f64_mul", "--rounding", "rodd", "v.tv"]),
    content="2",
  )
}
```

## Complete public interface

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/cli/testfloat_expr_cli"

// Values
pub fn run(Array[String]) -> Int

// Errors

// Types and methods

// Type aliases

// Traits
```
<!-- generated-api-end -->
