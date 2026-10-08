# cli/itl_expr_cli API

`cli/itl_expr_cli` is the command-line runner for ITF1788 `.itl` interval
test files. It parses them with [`frontend/itl_expr`](../frontend/itl_expr.md),
executes every case against `ball_float` and prints a JSON report. It is
normally reached as `floating-conformance --backend itl …`. See the
[tutorial](../../tutorial/cli/itl_expr_cli.md) and the
[design page](../../design/cli/itl_expr_cli.md).

## `run`

`run(arguments)` executes one invocation and returns the exit code.

```mbti
pub fn run(Array[String]) -> Int
```

`arguments[0]` is the program name and is ignored. Options:

| Option | Meaning |
| --- | --- |
| `--strict-supported` | also fail when any case is unsupported |
| `--operation NAME` | keep only cases of this operation; repeatable (cases of any listed operation are kept) |
| `PATH …` | `.itl` files, read in the given order; default `testdata/interval/smoke.itl` |

Any other argument starting with `-` (including `--json` and the shard
options, which this runner does not have) is an error `unknown option: …`.
Paths are files; directories are not expanded. If a file does not parse, every
diagnostic is printed as `PATH: MESSAGE` and the run ends.

The output is always one JSON object with the keys `schemaVersion` (`1`),
`runner` (`"itl-expression-interpreter"`), `totalCases`, `executableCases`,
`passedCases`, `failedCases`, `unsupportedCases`, `diagnosticCases`,
`failedIds`, `failedMessages` (`ID: MESSAGE`), `unsupportedIds` and
`diagnosticIds`.

Return value: `2` for usage, file or parse errors; `1` when a case failed, a
case was a diagnostic, or with `--strict-supported` a case was unsupported;
`0` otherwise. Cases are executed with the default precision 53.

```moonbit
///|
test "itl runner usage errors" {
  inspect(@itl_expr_cli.run(["itl", "--json"]), content="2")
  inspect(@itl_expr_cli.run(["itl", "--operation"]), content="2")
}
```

## Complete public interface

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/cli/itl_expr_cli"

// Values
pub fn run(Array[String]) -> Int

// Errors

// Types and methods

// Type aliases

// Traits
```
<!-- generated-api-end -->
