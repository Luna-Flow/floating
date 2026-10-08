# frontend/testfloat_expr tutorial

This tutorial shows how to run Berkeley TestFloat vectors against `bin_float`.
A TestFloat vector file is produced by `testfloat_gen` for one function, such
as `f64_mulAdd`, under one rounding mode; every line holds the operands, the
expected result and the expected exception flags in hexadecimal. You describe
the function with a `TestFloatSpec`, parse the lines, execute them, and read
the summary. The command-line runner is
[`cli/testfloat_expr_cli`](../cli/testfloat_expr_cli.md).

| I want to | Use |
| --- | --- |
| describe how a vector file was generated | [`TestFloatSpec::parse`](#quick-start) |
| run vectors from a string | [`parse_testfloat`, `execute_document`](#quick-start) |
| see why a vector failed | [`CaseResult::message`](#values-and-flags-are-both-checked) |
| check operations that return NaN | [any quiet NaN matches](#nan-results) |
| check integer conversions and `-exact` runs | [`TestFloatSpec::parse(…, exact=true)`](#conversions-to-integers-and-the-exact-variants) |
| check the comparison predicates | [`f64_le`, `f64_le_quiet`, …](#comparisons) |
| split a file over processes | [`RunOptions::new`](#shards) |

## Quick start

Add the library to your module and import the package in `moon.pkg`:

```bash
moon add Luna-Flow/floating@0.8.0
```

```moonbit nocheck
import {
  "Luna-Flow/floating/frontend/testfloat_expr",
}
```

Check $1.5 \times 2 = 3$ in binary64:

```moonbit
///|
test "quick start" {
  let spec = @testfloat_expr.TestFloatSpec::parse("f64_mul", "rnear_even").unwrap()
  let vectors =
    #|3FF8000000000000 4000000000000000 4008000000000000 00
    #|
  let document = @testfloat_expr.parse_testfloat("mul.tv", vectors, spec).unwrap()
  let summary = @testfloat_expr.execute_document(document)
  inspect(summary.passed_cases(), content="1")
  inspect(summary.success(), content="true")
}
```

The last field is the SoftFloat flag mask: `01` inexact, `02` underflow, `04`
overflow, `08` division by zero (infinite), `10` invalid.

## Everyday tasks

### Values and flags are both checked

A vector fails if either the encoded result or the flag mask differs:

```moonbit
///|
test "flag mismatch" {
  let spec = @testfloat_expr.TestFloatSpec::parse("f16_add", "rnear_even").unwrap()
  // 1 + 2^-11 is a tie in binary16 and rounds to 1, inexact
  let vectors =
    #|3C00 1000 3C00 01
    #|3C00 1000 3C00 00
    #|
  let summary = @testfloat_expr.execute_document(
    @testfloat_expr.parse_testfloat("add.tv", vectors, spec).unwrap(),
  )
  let messages = summary.results().map(r => r.id() + " " + r.message())
  inspect(
    messages.join("; "),
    content="f16_add:1 ; f16_add:2 flags mismatch: expected 0, actual 1",
  )
}
```

Ids are the function name and the line number.

### NaN results

When the expected result is a NaN, any quiet NaN is accepted, because IEEE 754
does not fix the payload or sign of a generated NaN. The flags must still
match:

```moonbit
///|
test "nan results" {
  let spec = @testfloat_expr.TestFloatSpec::parse("f32_mul", "rnear_even").unwrap()
  // inf * 0 is invalid; SoftFloat's default NaN is FFC00000
  let vectors =
    #|7F800000 00000000 FFC00000 10
    #|
  let summary = @testfloat_expr.execute_document(
    @testfloat_expr.parse_testfloat("nan.tv", vectors, spec).unwrap(),
  )
  inspect(summary.passed_cases(), content="1")
}
```

### Conversions to integers and the exact variants

For `to_i32`, `to_i64`, `to_ui32` and `to_ui64` the result field is the
integer in hexadecimal. With `exact=true` (TestFloat's `-exact`) an inexact
conversion also raises the inexact flag. An invalid conversion is checked by
its flags only:

```moonbit
///|
test "integer conversions" {
  let plain = @testfloat_expr.TestFloatSpec::parse("f64_to_i32", "rnear_even").unwrap()
  let exact = @testfloat_expr.TestFloatSpec::parse(
    "f64_to_i32",
    "rnear_even",
    exact=true,
  ).unwrap()
  // 1.5 -> 2; NaN -> invalid (the value field is SoftFloat's sentinel)
  let plain_rows =
    #|3FF8000000000000 00000002 00
    #|7FF8000000000000 7FFFFFFF 10
    #|
  let exact_rows =
    #|3FF8000000000000 00000002 01
    #|
  let a = @testfloat_expr.execute_document(
    @testfloat_expr.parse_testfloat("plain.tv", plain_rows, plain).unwrap(),
  )
  let b = @testfloat_expr.execute_document(
    @testfloat_expr.parse_testfloat("exact.tv", exact_rows, exact).unwrap(),
  )
  inspect(a.passed_cases(), content="2")
  inspect(b.passed_cases(), content="1")
}
```

### Comparisons

The comparison functions expect `0` or `1`. The signaling predicates
(`eq_signaling`, `le`, `lt`) raise invalid for any NaN operand; the quiet ones
(`eq`, `le_quiet`, `lt_quiet`) only for signaling NaNs:

```moonbit
///|
test "comparisons" {
  let le = @testfloat_expr.TestFloatSpec::parse("f64_le", "rnear_even").unwrap()
  let le_quiet = @testfloat_expr.TestFloatSpec::parse("f64_le_quiet", "rnear_even").unwrap()
  let row =
    #|7FF8000000000000 3FF0000000000000 0 10
    #|
  let quiet_row =
    #|7FF8000000000000 3FF0000000000000 0 00
    #|
  let signaling = @testfloat_expr.execute_document(
    @testfloat_expr.parse_testfloat("le.tv", row, le).unwrap(),
  )
  let quiet = @testfloat_expr.execute_document(
    @testfloat_expr.parse_testfloat("le_quiet.tv", quiet_row, le_quiet).unwrap(),
  )
  inspect(signaling.passed_cases(), content="1")
  inspect(quiet.passed_cases(), content="1")
}
```

### Shards

`RunOptions` runs every `n`-th vector, starting at index `i`, so `n` processes
can share one file:

```moonbit
///|
test "shards" {
  let spec = @testfloat_expr.TestFloatSpec::parse("f16_add", "rnear_even").unwrap()
  let vectors =
    #|3C00 3C00 4000 00
    #|0001 0001 0002 00
    #|7C00 FC00 7E00 10
    #|8000 0000 0000 00
    #|3C00 BC00 0000 00
    #|
  let document = @testfloat_expr.parse_testfloat("add.tv", vectors, spec).unwrap()
  let second = @testfloat_expr.execute_document(
    document,
    options=@testfloat_expr.RunOptions::new(shard_count=2, shard_index=1),
  )
  inspect(second.total_cases(), content="5")
  inspect(second.selected_cases(), content="2")
  inspect(second.passed_cases(), content="2")
}
```

## Going further

- **Generating vectors.** `just conformance fetch binary` downloads the
  pinned SoftFloat and TestFloat sources, and `just conformance run binary
  --level 1` builds `testfloat_gen`, then generates and executes the matrix of
  all formats, operations and rounding modes. Tininess defaults to after
  rounding; add `--tininess after --tininess before` to run both modes for
  the operations that can underflow. See
  [verification](../../verification.md).
- **Tininess.** Pass `tininess="before"` to `TestFloatSpec::parse` to match
  vectors generated with `-tininessbefore`; the default is after rounding.
- **Function names.** The spec accepts TestFloat names: `f16_`, `f32_`, `f64_`
  or `f128_` followed by `add`, `sub`, `mul`, `div`, `sqrt`, `mulAdd`, `rem`,
  `roundToInt`, `to_i32`, `to_i64`, `to_ui32`, `to_ui64`, `eq`, `le`, `lt`,
  `eq_signaling`, `le_quiet` or `lt_quiet`.

## Common pitfalls

- **One function per document.** The spec applies to every line; split mixed
  files.
- **The rounding argument is not optional.** `rem` and the comparisons ignore
  it, but `TestFloatSpec::parse` still needs a valid name such as
  `rnear_even`.
- **`rodd` is not supported.** Only the five IEEE directions are accepted.
- **`exact` matters.** Vectors from `-exact` runs contain the inexact flag for
  `roundToInt` and integer conversions; parse them with `exact=true`.

## Next steps

- [frontend/testfloat_expr API](../../api/frontend/testfloat_expr.md) for
  every item.
- [frontend/testfloat_expr design](../../design/frontend/testfloat_expr.md)
  for the exact pass rule.
- [cli/testfloat_expr_cli tutorial](../cli/testfloat_expr_cli.md) for
  running vector files from the command line.
- [bin_float conformance](../../conformance/bin_float.md) for the published
  TestFloat claim.
