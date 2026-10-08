# frontend/testfloat_expr API

## Purpose

`frontend/testfloat_expr` parses Berkeley TestFloat test vectors and executes
them against `bin_float` in the binary16, binary32, binary64 and binary128
interchange formats. A `TestFloatSpec` describes the function, rounding mode,
tininess rule and exactness that produced a vector file; `parse_testfloat`
reads the vectors and `execute_document` runs them. The package does no IO;
the runner is [`cli/testfloat_expr_cli`](../cli/testfloat_expr_cli.md). The
[tutorial](../../tutorial/frontend/testfloat_expr.md) shows the workflow and
the [design page](../../design/frontend/testfloat_expr.md) specifies the pass
rule.

## Importing

Add the package to the `import` block of your `moon.pkg`; import `bin_float`
as well when you compare the format or rounding mode of a specification:

```moonbit nocheck
import {
  "Luna-Flow/floating/frontend/testfloat_expr",
  "Luna-Flow/floating/bin_float",
}
```

The examples use the aliases `@testfloat_expr` and `@bin_float`.

## Function specification

### `TestFloatOperation`

`TestFloatOperation` lists the TestFloat functions the executor supports.

```mbti
pub(all) enum TestFloatOperation {
  Add
  Subtract
  Multiply
  Divide
  SquareRoot
  MulAdd
  Remainder
  RoundToInt
  ToInt32
  ToInt64
  ToUInt32
  ToUInt64
  Equal
  LessEqual
  Less
  EqualSignaling
  LessEqualQuiet
  LessQuiet
} derive(Eq, @debug.Debug)
```

| Constructor | TestFloat name | Operands | `bin_float` method |
| --- | --- | --- | --- |
| `Add`, `Subtract`, `Multiply`, `Divide` | `add`, `sub`, `mul`, `div` | 2 | `add_ctx`, `sub_ctx`, `mul_ctx`, `div_ctx` |
| `SquareRoot` | `sqrt` | 1 | `sqrt_ctx` |
| `MulAdd` | `mulAdd` | 3 | `fma_ctx` |
| `Remainder` | `rem` | 2 | `remainder_ctx` |
| `RoundToInt` | `roundToInt` | 1 | `to_integral_exact_ctx` if exact, else `to_integral_value_ctx` |
| `ToInt32`, `ToInt64`, `ToUInt32`, `ToUInt64` | `to_i32`, `to_i64`, `to_ui32`, `to_ui64` | 1 | `to_int_ctx`, `to_int64_ctx`, `to_uint_ctx`, `to_uint64_ctx` with `exact~` |
| `Equal`, `LessEqual`, `Less` | `eq`, `le`, `lt` | 2 | `equal_quiet`, `less_equal_signaling`, `less_signaling` |
| `EqualSignaling`, `LessEqualQuiet`, `LessQuiet` | `eq_signaling`, `le_quiet`, `lt_quiet` | 2 | `equal_signaling`, `less_equal_quiet`, `less_quiet` |

### `TestFloatSpec`

`TestFloatSpec` is the configuration of one TestFloat run.

```mbti
pub struct TestFloatSpec {
  // private fields
} derive(Eq, @debug.Debug)
```

### `TestFloatSpec::parse`

`TestFloatSpec::parse(function_name, rounding, tininess?, exact?)` builds a
specification from TestFloat names.

```mbti
pub fn TestFloatSpec::parse(String, String, tininess? : String, exact? : Bool) -> Result[Self, String]
```

`function_name` is `FORMAT_OPERATION`: the part before the first `_` is the
format (`f16`, `f32`, `f64`, `f128`) and the rest is the operation
(`add`, `mulAdd`, `to_ui64`, `le_quiet`, …). Names are matched
case-insensitively with `-`, `_` and spaces removed. TestFloat functions
outside the eighteen operations, such as `f64_to_f32`, `i32_to_f64` or
`f64_to_i32_r_minMag`, are rejected. `rounding` is one of
`rnear_even`, `rnear_maxMag`, `rminMag`, `rmin`, `rmax` (also accepted without
the leading `r`, or as the IEEE names `roundTiesToEven`, `roundTiesToAway`,
`roundTowardZero`, `roundTowardNegative`, `roundTowardPositive`).
`tininess` is `"after"` (default) or `"before"` (also `tininessAfter`,
`tininessBefore`). `exact` (default `false`) selects TestFloat's `-exact`
variants of `roundToInt` and the integer conversions. Errors are
`"unsupported TestFloat function name …"`, `"… format …"`,
`"… operation …"`, `"… rounding mode …"` and `"… tininess mode …"`.

```moonbit
///|
test "spec parse" {
  let spec = @testfloat_expr.TestFloatSpec::parse(
    "f128_mulAdd",
    "rminMag",
    tininess="before",
  ).unwrap()
  inspect(spec.operation() == @testfloat_expr.MulAdd, content="true")
  inspect(spec.format() == @bin_float.Binary128, content="true")
  inspect(spec.rounding() == @bin_float.RoundTowardZero, content="true")
  inspect(
    @testfloat_expr.TestFloatSpec::parse("f64_mul", "rodd") is Err(_),
    content="true",
  )
}
```

### `TestFloatSpec::function_name`, `TestFloatSpec::format`, `TestFloatSpec::operation`, `TestFloatSpec::rounding`, `TestFloatSpec::tininess`, `TestFloatSpec::exact`

These accessors return the parsed configuration.

```mbti
pub fn TestFloatSpec::function_name(Self) -> String
pub fn TestFloatSpec::format(Self) -> @bin_float.BinaryInterchangeFormat
pub fn TestFloatSpec::operation(Self) -> TestFloatOperation
pub fn TestFloatSpec::rounding(Self) -> @bin_float.BinaryRoundingMode
pub fn TestFloatSpec::tininess(Self) -> @bin_float.TininessDetection
pub fn TestFloatSpec::exact(Self) -> Bool
```

`function_name` is the name as given. `exact` is stored for every operation
but only changes the result of `roundToInt` and the four integer
conversions.

## Parsing

### `parse_testfloat`

`parse_testfloat(source, text, spec)` parses the vectors of one function.

```mbti
pub fn parse_testfloat(String, String, TestFloatSpec) -> Result[TestFloatDocument, Array[ParseDiagnostic]]
```

Lines are trimmed; empty lines and lines starting with `#` are skipped. A
vector has $k + 2$ white-space separated fields, where $k$ is the operand count
of the operation: $k$ operand encodings, the expected result and a two-digit
hexadecimal flag mask. Operand encodings are hexadecimal bit patterns of
`spec.format()`. The expected result is an encoding for arithmetic
operations, a hexadecimal integer of at most 16 digits for conversions, and
`0` or `1` for comparisons. A wrong field count gives
`"unexpected TestFloat field count"`, an unreadable field
`"invalid TestFloat hexadecimal field"`. The result is `Ok` only when no line
is invalid.

### `TestFloatDocument`

`TestFloatDocument` is a parsed vector file.

```mbti
pub struct TestFloatDocument {
  // private fields
}
```

### `TestFloatDocument::source`, `TestFloatDocument::spec`, `TestFloatDocument::cases`, `TestFloatDocument::case_count`

These methods return the name given to the parser, the specification, a copy
of the vectors in file order, and their number.

```mbti
pub fn TestFloatDocument::source(Self) -> String
pub fn TestFloatDocument::spec(Self) -> TestFloatSpec
pub fn TestFloatDocument::cases(Self) -> Array[TestFloatCase]
pub fn TestFloatDocument::case_count(Self) -> Int
```

### `TestFloatCase`

`TestFloatCase` is one vector.

```mbti
pub struct TestFloatCase {
  // private fields
}
```

### `TestFloatCase::id`, `TestFloatCase::line`

These methods return the id `FUNCTION:LINE`, for example `f64_mulAdd:17`, and
the 1-based line number of the vector in the parsed text.

```mbti
pub fn TestFloatCase::id(Self) -> String
pub fn TestFloatCase::line(Self) -> Int
```

```moonbit
///|
test "vector ids" {
  let spec = @testfloat_expr.TestFloatSpec::parse("f16_mul", "rnear_even").unwrap()
  let text =
    #|# a comment line
    #|3C00 4000 4000 00
    #|
  let document = @testfloat_expr.parse_testfloat("mul.tv", text, spec).unwrap()
  inspect(document.case_count(), content="1")
  inspect(document.cases()[0].id(), content="f16_mul:2")
  inspect(document.spec().function_name(), content="f16_mul")
}
```

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

## Execution

### `execute_document`

`execute_document(document, options?)` executes the selected vectors.

```mbti
pub fn execute_document(TestFloatDocument, options? : RunOptions) -> RunSummary
```

Vector $k$ (counting from 0 in file order) is executed when
$k \bmod n = i$ for shard count $n$ and index $i$. Operands are decoded to
`BinFloat` and the operation runs in `spec.format().context(rounding~,
tininess~)`. The vector passes when:

- **arithmetic:** the result, re-encoded in the format with the same rounding
  and tininess, has exactly the expected bit pattern, or the expected result
  is any NaN and the actual result is a quiet NaN; and the SoftFloat mask of
  the operation's flags combined with the encoding flags equals the expected
  mask;
- **integer conversion:** if the expected mask has the invalid bit `10`, the
  conversion must report invalid (`None`) and its value field is ignored;
  otherwise the conversion must return the expected integer (signed results
  compared as two's-complement bit patterns); in both cases the flag masks
  must be equal;
- **comparison:** the boolean and the flag mask are equal.

Every selected vector is executable; there are no skipped vectors.

### `RunOptions`

`RunOptions` selects a shard.

```mbti
pub struct RunOptions {
  // private fields
}
```

### `RunOptions::new`

`RunOptions::new(shard_count?, shard_index?)` builds the options.

```mbti
pub fn RunOptions::new(shard_count? : Int, shard_index? : Int) -> Self
```

Defaults: one shard, index 0. `RunOptions::new` aborts unless
`shard_count > 0` and `0 <= shard_index < shard_count`.

### `RunOptions::shard_count`, `RunOptions::shard_index`

These accessors return the shard count and index.

```mbti
pub fn RunOptions::shard_count(Self) -> Int
pub fn RunOptions::shard_index(Self) -> Int
```

## Results

### `CaseResult`

`CaseResult` is the outcome of one vector.

```mbti
pub struct CaseResult {
  // private fields
}
```

### `CaseResult::id`, `CaseResult::passed`, `CaseResult::message`

These methods return the vector id, whether it passed, and a message.

```mbti
pub fn CaseResult::id(Self) -> String
pub fn CaseResult::passed(Self) -> Bool
pub fn CaseResult::message(Self) -> String
```

Messages: empty for a pass; `"value mismatch: expected HEX, actual HEX"`,
`"integer mismatch: …"`, `"comparison mismatch: …"`, or
`"flags mismatch: expected M, actual M"` (masks in decimal).

### `RunSummary`

`RunSummary` aggregates a run.

```mbti
pub struct RunSummary {
  // private fields
}
```

### `RunSummary::total_cases`, `RunSummary::selected_cases`, `RunSummary::passed_cases`, `RunSummary::failed_cases`

These methods return the number of vectors in the document, the number this
shard executed, and how many of those passed and failed.

```mbti
pub fn RunSummary::total_cases(Self) -> Int
pub fn RunSummary::selected_cases(Self) -> Int
pub fn RunSummary::passed_cases(Self) -> Int
pub fn RunSummary::failed_cases(Self) -> Int
```

### `RunSummary::results`, `RunSummary::success`

`results` returns a copy of the results in vector order; `success` is the
verdict.

```mbti
pub fn RunSummary::results(Self) -> Array[CaseResult]
pub fn RunSummary::success(Self) -> Bool
```

`total_cases` is the number of vectors in the document,
`selected_cases = passed_cases + failed_cases` the number executed by this
shard, and `success` is true when none failed.

## Trait implementations

These methods come from `derive(Eq, @debug.Debug)`. Use `==`, `!=` and
`debug_inspect` in new code.

### `TestFloatOperation::equal`, `TestFloatOperation::not_equal`, `TestFloatOperation::to_repr`

`equal` compares constructors; `to_repr` renders the constructor name.

```mbti
pub fn TestFloatOperation::equal(Self, Self) -> Bool
pub fn TestFloatOperation::not_equal(Self, Self) -> Bool
pub fn TestFloatOperation::to_repr(Self) -> @debug.Repr
```

### `TestFloatSpec::equal`, `TestFloatSpec::not_equal`, `TestFloatSpec::to_repr`

`equal` compares all six fields, including `function_name` as written, so
`f64_mul` and `F64_MUL` give unequal specifications with the same behaviour.

```mbti
pub fn TestFloatSpec::equal(Self, Self) -> Bool
pub fn TestFloatSpec::not_equal(Self, Self) -> Bool
pub fn TestFloatSpec::to_repr(Self) -> @debug.Repr
```

### `ParseDiagnostic::equal`, `ParseDiagnostic::not_equal`, `ParseDiagnostic::to_repr`

`equal` compares location and message; `to_repr` renders both.

```mbti
pub fn ParseDiagnostic::equal(Self, Self) -> Bool
pub fn ParseDiagnostic::not_equal(Self, Self) -> Bool
pub fn ParseDiagnostic::to_repr(Self) -> @debug.Repr
```

```moonbit
///|
test "spec equality" {
  let a = @testfloat_expr.TestFloatSpec::parse("f64_mul", "rnear_even").unwrap()
  let b = @testfloat_expr.TestFloatSpec::parse("F64_MUL", "rnear_even").unwrap()
  inspect(a.operation() == b.operation(), content="true")
  inspect(a == b, content="false")
}
```

## Complete public interface

This snapshot is the generated `pkg.generated.mbti` of the package. It is the authority when prose and interface disagree.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/frontend/testfloat_expr"

import {
  "Luna-Flow/floating/bin_float",
  "moonbitlang/core/debug",
}

// Values
pub fn execute_document(TestFloatDocument, options? : RunOptions) -> RunSummary

pub fn parse_testfloat(String, String, TestFloatSpec) -> Result[TestFloatDocument, Array[ParseDiagnostic]]

// Errors

// Types and methods
pub struct CaseResult {
  // private fields
}
pub fn CaseResult::id(Self) -> String
pub fn CaseResult::message(Self) -> String
pub fn CaseResult::passed(Self) -> Bool

pub struct ParseDiagnostic {
  // private fields
} derive(Eq, @debug.Debug)
pub fn ParseDiagnostic::equal(Self, Self) -> Bool
pub fn ParseDiagnostic::line(Self) -> Int
pub fn ParseDiagnostic::message(Self) -> String
pub fn ParseDiagnostic::not_equal(Self, Self) -> Bool
pub fn ParseDiagnostic::source(Self) -> String
pub fn ParseDiagnostic::to_repr(Self) -> @debug.Repr

pub struct RunOptions {
  // private fields
}
pub fn RunOptions::new(shard_count? : Int, shard_index? : Int) -> Self
pub fn RunOptions::shard_count(Self) -> Int
pub fn RunOptions::shard_index(Self) -> Int

pub struct RunSummary {
  // private fields
}
pub fn RunSummary::failed_cases(Self) -> Int
pub fn RunSummary::passed_cases(Self) -> Int
pub fn RunSummary::results(Self) -> Array[CaseResult]
pub fn RunSummary::selected_cases(Self) -> Int
pub fn RunSummary::success(Self) -> Bool
pub fn RunSummary::total_cases(Self) -> Int

pub struct TestFloatCase {
  // private fields
}
pub fn TestFloatCase::id(Self) -> String
pub fn TestFloatCase::line(Self) -> Int

pub struct TestFloatDocument {
  // private fields
}
pub fn TestFloatDocument::case_count(Self) -> Int
pub fn TestFloatDocument::cases(Self) -> Array[TestFloatCase]
pub fn TestFloatDocument::source(Self) -> String
pub fn TestFloatDocument::spec(Self) -> TestFloatSpec

pub(all) enum TestFloatOperation {
  Add
  Subtract
  Multiply
  Divide
  SquareRoot
  MulAdd
  Remainder
  RoundToInt
  ToInt32
  ToInt64
  ToUInt32
  ToUInt64
  Equal
  LessEqual
  Less
  EqualSignaling
  LessEqualQuiet
  LessQuiet
} derive(Eq, @debug.Debug)
pub fn TestFloatOperation::equal(Self, Self) -> Bool
pub fn TestFloatOperation::not_equal(Self, Self) -> Bool
pub fn TestFloatOperation::to_repr(Self) -> @debug.Repr

pub struct TestFloatSpec {
  // private fields
} derive(Eq, @debug.Debug)
pub fn TestFloatSpec::equal(Self, Self) -> Bool
pub fn TestFloatSpec::exact(Self) -> Bool
pub fn TestFloatSpec::format(Self) -> @bin_float.BinaryInterchangeFormat
pub fn TestFloatSpec::function_name(Self) -> String
pub fn TestFloatSpec::not_equal(Self, Self) -> Bool
pub fn TestFloatSpec::operation(Self) -> TestFloatOperation
pub fn TestFloatSpec::parse(String, String, tininess? : String, exact? : Bool) -> Result[Self, String]
pub fn TestFloatSpec::rounding(Self) -> @bin_float.BinaryRoundingMode
pub fn TestFloatSpec::tininess(Self) -> @bin_float.TininessDetection
pub fn TestFloatSpec::to_repr(Self) -> @debug.Repr

// Type aliases

// Traits
```
<!-- generated-api-end -->
