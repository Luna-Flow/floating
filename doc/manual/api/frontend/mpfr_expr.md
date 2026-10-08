# frontend/mpfr_expr API

## Purpose

`frontend/mpfr_expr` parses reference data produced with GNU MPFR and executes
it against `bin_float`. Three formats are supported: MPFR's square-root
`data_check` files, integer-power rows, and an elementary-function matrix with
exception flags. The package does no IO; the runner is
[`cli/mpfr_expr_cli`](../cli/mpfr_expr_cli.md). See the
[tutorial](../../tutorial/frontend/mpfr_expr.md) for the workflow and the
[design page](../../design/frontend/mpfr_expr.md) for the pass rules.

## Importing

Add the package to the `import` block of your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/frontend/mpfr_expr",
}
```

The examples call it through the alias `@mpfr_expr`; rows are written as
text, so `bin_float` does not need to be imported.

## Common row syntax

All three parsers split the text at `\n`, trim each line, and skip empty lines
and lines starting with `#`. Fields are separated by spaces, tabs or carriage
returns. Line numbers start at 1. A rounding field is one of

| Field | `BinaryRoundingMode` |
| --- | --- |
| `n` | `RoundTiesToEven` |
| `na` | `RoundTiesToAway` |
| `z` | `RoundTowardZero` |
| `u` | `RoundTowardPositive` |
| `d` | `RoundTowardNegative` |
| `a` | `RoundAwayFromZero` |

and a number is read by `@bin_float.BinFloat::from_hex` (`0x…p…` with an
integer hexadecimal significand and no point, `inf`, `-inf`, `nan`) at the
precision named for that field; a significand with more bits than that
precision is rounded to nearest-even. Each parser returns `Ok(document)` when every line is valid and
otherwise `Err` with one `ParseDiagnostic` per invalid line.

## Square-root data

### `parse_sqrt_data`

`parse_sqrt_data(source, text)` parses rows of five fields:
`input_precision output_precision rounding input expected`.

```mbti
pub fn parse_sqrt_data(String, String) -> Result[MpfrDocument, Array[ParseDiagnostic]]
```

The input is read at `input_precision` bits and the expected value at
`output_precision` bits. Row ids are `sqrt:LINE`.

### `execute_sqrt_data`

`execute_sqrt_data(document)` computes `input.sqrt_ctx(ctx)` for every row,
where `ctx` is `BinaryContext::unbounded(output_precision, rounding~)`.

```mbti
pub fn execute_sqrt_data(MpfrDocument) -> RunSummary
```

A row passes when the result is equal (`==`) to the expected `BinFloat`.
Flags are not compared.

### `MpfrDocument`, `MpfrCase`

`MpfrDocument` is a parsed square-root file; `MpfrCase` is one of its rows and
has no public methods.

```mbti
pub struct MpfrDocument {
  // private fields
}

pub struct MpfrCase {
  // private fields
}
```

### `MpfrDocument::source`, `MpfrDocument::case_count`

`source` returns the name given to the parser and `case_count` the number of
rows.

```mbti
pub fn MpfrDocument::source(Self) -> String
pub fn MpfrDocument::case_count(Self) -> Int
```

## Integer powers

### `parse_pow_data`

`parse_pow_data(source, text)` parses rows of ten fields.

```mbti
pub fn parse_pow_data(String, String) -> Result[MpfrPowDocument, Array[ParseDiagnostic]]
```

The fields are `precision rounding input_coefficient_hex input_exponent2
input_negative exponent expected_coefficient_hex expected_exponent2
expected_negative inexact`, where the two numbers are
$(-1)^{\text{negative}} \cdot \text{coefficient} \cdot 2^{\text{exponent2}}$,
the signs and `inexact` are `0` or `1`, and `exponent` is the integer power.
The input is read at 512 bits and the expected value at `precision` bits. Row
ids are `pow:LINE`. The coefficient fields are bare hexadecimal digits; the
parser builds `0xCOEFFpEXP` from them.

### `execute_pow_data`

`execute_pow_data(document)` computes `input.pow_int_ctx(exponent, ctx)` with
`ctx = BinaryContext::unbounded(precision, rounding~)`.

```mbti
pub fn execute_pow_data(MpfrPowDocument) -> RunSummary
```

A row passes when the result is equal (`==`) to the expected value, the
inexact flag equals the row's flag, and no underflow, overflow, division by
zero or invalid flag is raised.

### `MpfrPowDocument`, `MpfrPowCase`

`MpfrPowDocument` is a parsed power file; `MpfrPowCase` is one row and has no
public methods.

```mbti
pub struct MpfrPowDocument {
  // private fields
}

pub struct MpfrPowCase {
  // private fields
}
```

### `MpfrPowDocument::source`, `MpfrPowDocument::case_count`

These methods return the name given to the parser and the number of rows.

```mbti
pub fn MpfrPowDocument::source(Self) -> String
pub fn MpfrPowDocument::case_count(Self) -> Int
```

## Elementary functions

### `parse_elementary_data`

`parse_elementary_data(source, text)` parses rows of ten fields:
`op precision rounding x y n expected inexact invalid divbyzero`.

```mbti
pub fn parse_elementary_data(String, String) -> Result[MpfrElementaryDocument, Array[ParseDiagnostic]]
```

`op` is one of `exp`, `exp2`, `exp10`, `expm1`, `ln`, `log2`, `log10`,
`log1p`, `sqrt`, `rootn`, `pown`, `pow`, `hypot`, `sin`, `cos`, `tan`,
`sinpi`, `cospi`, `tanpi`, `asin`, `acos`, `atan`, `atan2`, `sinh`, `cosh`,
`tanh`, `asinh`, `acosh`, `atanh`. `x` and `y` are operands read at 512 bits
(`y` is `-` when unused), `n` is the integer argument of `rootn` and `pown`,
`expected` is read at `precision` bits, and the last three fields are `0` or
`1`. Row ids are `op:LINE`.

> [!WARNING]
> The parser does not check that `y` is present for the two-operand functions
> `pow`, `hypot` and `atan2`, and the executor unwraps it: executing such a
> row with `y = -` aborts the whole run instead of failing the row.

### `execute_elementary_data`

`execute_elementary_data(document)` evaluates every row with the checked
`try_*_ctx` method of `BinFloat` for its operation (`sqrt_ctx` and `pown_ctx`
for `sqrt` and `pown`) in `BinaryContext::unbounded(precision, rounding~)`.

```mbti
pub fn execute_elementary_data(MpfrElementaryDocument) -> RunSummary
```

A row passes when the result compares equal to the expected value
(`compare == 0`: $+0 = -0$ and every NaN equals every NaN), the inexact,
invalid and division-by-zero flags equal the row's flags, and neither
underflow nor overflow is raised. If a `try_*_ctx` method returns `Err` (for
example a certification failure) the row fails with the message
`"certification failure for MPFR differential case"`.

### `MpfrElementaryDocument`

`MpfrElementaryDocument` is a parsed elementary file.

```mbti
pub struct MpfrElementaryDocument {
  // private fields
}
```

### `MpfrElementaryDocument::source`, `MpfrElementaryDocument::case_count`

These methods return the name given to the parser and the number of rows.

```mbti
pub fn MpfrElementaryDocument::source(Self) -> String
pub fn MpfrElementaryDocument::case_count(Self) -> Int
```

## Diagnostics and results

### `ParseDiagnostic`

`ParseDiagnostic` is one invalid line.

```mbti
pub struct ParseDiagnostic {
  // private fields
} derive(Eq, @debug.Debug)
```

### `ParseDiagnostic::source`, `ParseDiagnostic::line`, `ParseDiagnostic::message`

These methods return the name given to the parser, the 1-based line number
and the message.

```mbti
pub fn ParseDiagnostic::source(Self) -> String
pub fn ParseDiagnostic::line(Self) -> Int
pub fn ParseDiagnostic::message(Self) -> String
```

Messages name the problem, for example `"MPFR pow row must contain ten
fields"`, `"invalid MPFR pow field"` or `"invalid MPFR elementary expected
value"`.

### `CaseResult`

`CaseResult` is the outcome of one row.

```mbti
pub struct CaseResult {
  // private fields
}
```

### `CaseResult::id`, `CaseResult::passed`, `CaseResult::message`

These methods return the row id, whether the row passed, and a message.

```mbti
pub fn CaseResult::id(Self) -> String
pub fn CaseResult::passed(Self) -> Bool
pub fn CaseResult::message(Self) -> String
```

The message is empty for a pass and otherwise shows expected and actual values
in hexadecimal (and the compared flags for power and elementary rows).

### `RunSummary`

`RunSummary` aggregates the rows of one document.

```mbti
pub struct RunSummary {
  // private fields
}
```

### `RunSummary::total_cases`, `RunSummary::passed_cases`, `RunSummary::failed_cases`

These methods return the number of rows, and how many passed and failed.

```mbti
pub fn RunSummary::total_cases(Self) -> Int
pub fn RunSummary::passed_cases(Self) -> Int
pub fn RunSummary::failed_cases(Self) -> Int
```

### `RunSummary::results`, `RunSummary::success`

`results` returns a copy of the per-row results; `success` is the verdict.

```mbti
pub fn RunSummary::results(Self) -> Array[CaseResult]
pub fn RunSummary::success(Self) -> Bool
```

Every row is executed, so $\text{total} = \text{passed} + \text{failed}$;
`success` is true when no row failed. `results` returns the results in row
order.

```moonbit
///|
test "mpfr summary" {
  let rows =
    #|53 53 n 0x0p0 0x0p0
    #|53 53 u 0x3p0 0x1bb67ae8584cabp-52
    #|
  let summary = @mpfr_expr.execute_sqrt_data(
    @mpfr_expr.parse_sqrt_data("s", rows).unwrap(),
  )
  inspect(summary.total_cases(), content="2")
  inspect(summary.passed_cases(), content="2")
}
```

## Trait implementations

### `ParseDiagnostic::equal`, `ParseDiagnostic::not_equal`, `ParseDiagnostic::to_repr`

These methods compare location and message and render a diagnostic for
`Debug`. Use `==`, `!=` and `debug_inspect` in new code.

```mbti
pub fn ParseDiagnostic::equal(Self, Self) -> Bool
pub fn ParseDiagnostic::not_equal(Self, Self) -> Bool
pub fn ParseDiagnostic::to_repr(Self) -> @debug.Repr
```

## Complete public interface

This snapshot is the generated `pkg.generated.mbti` of the package. It is the authority when prose and interface disagree.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/frontend/mpfr_expr"

import {
  "moonbitlang/core/debug",
}

// Values
pub fn execute_elementary_data(MpfrElementaryDocument) -> RunSummary

pub fn execute_pow_data(MpfrPowDocument) -> RunSummary

pub fn execute_sqrt_data(MpfrDocument) -> RunSummary

pub fn parse_elementary_data(String, String) -> Result[MpfrElementaryDocument, Array[ParseDiagnostic]]

pub fn parse_pow_data(String, String) -> Result[MpfrPowDocument, Array[ParseDiagnostic]]

pub fn parse_sqrt_data(String, String) -> Result[MpfrDocument, Array[ParseDiagnostic]]

// Errors

// Types and methods
pub struct CaseResult {
  // private fields
}
pub fn CaseResult::id(Self) -> String
pub fn CaseResult::message(Self) -> String
pub fn CaseResult::passed(Self) -> Bool

pub struct MpfrCase {
  // private fields
}

pub struct MpfrDocument {
  // private fields
}
pub fn MpfrDocument::case_count(Self) -> Int
pub fn MpfrDocument::source(Self) -> String

pub struct MpfrElementaryDocument {
  // private fields
}
pub fn MpfrElementaryDocument::case_count(Self) -> Int
pub fn MpfrElementaryDocument::source(Self) -> String

pub struct MpfrPowCase {
  // private fields
}

pub struct MpfrPowDocument {
  // private fields
}
pub fn MpfrPowDocument::case_count(Self) -> Int
pub fn MpfrPowDocument::source(Self) -> String

pub struct ParseDiagnostic {
  // private fields
} derive(Eq, @debug.Debug)
pub fn ParseDiagnostic::equal(Self, Self) -> Bool
pub fn ParseDiagnostic::line(Self) -> Int
pub fn ParseDiagnostic::message(Self) -> String
pub fn ParseDiagnostic::not_equal(Self, Self) -> Bool
pub fn ParseDiagnostic::source(Self) -> String
pub fn ParseDiagnostic::to_repr(Self) -> @debug.Repr

pub struct RunSummary {
  // private fields
}
pub fn RunSummary::failed_cases(Self) -> Int
pub fn RunSummary::passed_cases(Self) -> Int
pub fn RunSummary::results(Self) -> Array[CaseResult]
pub fn RunSummary::success(Self) -> Bool
pub fn RunSummary::total_cases(Self) -> Int

// Type aliases

// Traits
```
<!-- generated-api-end -->
