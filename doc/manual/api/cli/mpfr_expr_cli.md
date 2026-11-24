# cli/mpfr_expr_cli API

## Purpose

`cli/mpfr_expr_cli` is the command-line runner for MPFR reference data. It
reads one file, detects its format, parses and executes it with
[`frontend/mpfr_expr`](../frontend/mpfr_expr.md) and prints a summary. It is
normally reached as `floating-conformance --backend mpfr …`. See the
[tutorial](../../tutorial/cli/mpfr_expr_cli.md) and the
[design page](../../design/cli/mpfr_expr_cli.md).

## Importing

The runner is a library, so it can be called from MoonBit code as well as
through the dispatcher. Add it to the `import` block of your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating-tools/cli/mpfr_expr_cli",
}
```

The examples use the alias `@mpfr_expr_cli`. `run` reads files through
`moonbitlang/x/fs`; the repository builds and tests the runners on the native
target.

## `run`

`run(arguments)` executes one invocation and returns the exit code.

```mbti
pub fn run(Array[String]) -> Int
```

`arguments[0]` is the program name and is ignored. The runner accepts
`--json` and exactly one path. After `--json` is removed, any other number of
arguments (none, or two or more, including shard options, which are disabled
for this runner) prints
`usage: mpfr-expr [--json] <MPFR sqrt, pow, elementary, strtofr, or decimal output corpus>`. A single
remaining argument is always taken as the path, even when it starts with `-`:
`--help` or a mistyped option is reported as `cannot read file: --help`. Both
cases return `2`.

The format is chosen from the file content:

| Content contains | Format | Parser and executor | JSON `corpus` |
| --- | --- | --- | --- |
| `mpfr-decimal-random-v2` | seeded random decimal differential rows | `parse_decimal_random_data`, `execute_decimal_random_data` | `mpfr-4.2.2-decimal-random` |
| `mpfr-random-v1` | seeded random differential rows | `parse_random_data`, `execute_random_data` | `mpfr-4.2.2-random` |
| `mpfr-strtofr-v1` (and not the above) | decimal text to binary conversion | `parse_strtofr_data`, `execute_strtofr_data` | `mpfr-4.2.2-strtofr` |
| `mpfr-decimal-output-v1` (and not the above) | binary to decimal digits conversion | `parse_decimal_output_data`, `execute_decimal_output_data` | `mpfr-4.2.2-decimal-output` |
| `mpfr-elementary-v1` | elementary matrix | `parse_elementary_data`, `execute_elementary_data` | `mpfr-4.2.2-elementary` |
| `input_coefficient_hex` (and not the above) | integer powers | `parse_pow_data`, `execute_pow_data` | `mpfr-4.2.2-pow-si` |
| none of these | square-root `data_check` | `parse_sqrt_data`, `execute_sqrt_data` | `mpfr-4.2.2-sqrt` |

On a parse error the first diagnostic is printed as `source:line:1: message`.
Text output prints a title, `cases`, `passed cases`, `failed cases` and one
`failed ID: MESSAGE` line per failure. JSON output has the keys `corpus`,
`frontend` (always `mpfr`), `totalCases`, `passedCases`, `failedCases` and `failedIds`.

Return value: `2` for usage, file or parse errors (including an elementary
`pow`, `hypot` or `atan2` row whose second operand is `-`, see
[`frontend/mpfr_expr`](../frontend/mpfr_expr.md#parse_elementary_data)); `1`
when a row failed; `0` otherwise.

```moonbit
///|
test "mpfr runner usage errors" {
  inspect(@mpfr_expr_cli.run(["mpfr"]), content="2")
  inspect(@mpfr_expr_cli.run(["mpfr", "--shard-count=2", "data.txt"]), content="2")
  inspect(@mpfr_expr_cli.run(["mpfr", "--help"]), content="2")
}
```

## Complete public interface

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating-tools/cli/mpfr_expr_cli"

// Values
pub fn run(Array[String]) -> Int32

// Errors

// Types and methods

// Type aliases

// Traits
```
<!-- generated-api-end -->
