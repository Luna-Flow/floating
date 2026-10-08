# frontend/mpfr_expr tutorial

This tutorial shows how to check `bin_float` against reference results
computed with GNU MPFR. Three line-oriented formats are supported: MPFR's own
square-root test data, integer powers, and an elementary-function matrix. You
parse a file into a document, execute it, and read the summary. The
command-line runner is [`cli/mpfr_expr_cli`](../cli/mpfr_expr_cli.md).

| I want to | Use |
| --- | --- |
| check square roots from MPFR's `tests/data/sqrt` | [`parse_sqrt_data`, `execute_sqrt_data`](#quick-start) |
| check elementary functions and their flags | [`parse_elementary_data`, `execute_elementary_data`](#elementary-functions-with-flags) |
| check integer powers | [`parse_pow_data`, `execute_pow_data`](#integer-powers) |
| see why a row failed | [`CaseResult::message`](#read-a-failure) |
| find malformed lines | [`ParseDiagnostic::line`, `ParseDiagnostic::message`](#parse-errors) |
| run the pinned corpora | [`just conformance run binary`](#going-further) |

## Quick start

Add the library to your module and import the package in `moon.pkg`:

```bash
moon add Luna-Flow/floating@0.8.0
```

```moonbit nocheck
import {
  "Luna-Flow/floating/frontend/mpfr_expr",
}
```

Check one square root: $\sqrt{2^{-1074} \cdot 2^{52}} = 2^{-511}$ at 53 bits,
rounding to nearest:

```moonbit
///|
test "quick start" {
  let rows =
    #|# input_precision output_precision rounding input expected
    #|53 53 n 0x10000000000000p-1074 0x10000000000000p-563
    #|
  let document = @mpfr_expr.parse_sqrt_data("sqrt.txt", rows).unwrap()
  let summary = @mpfr_expr.execute_sqrt_data(document)
  inspect(summary.passed_cases(), content="1")
  inspect(summary.success(), content="true")
}
```

Numbers are written as hexadecimal significand and binary exponent:
`0x10000000000000p-1074` is $2^{52} \cdot 2^{-1074}$.

## Everyday tasks

### Elementary functions with flags

An elementary row names the function, the output precision and rounding, the
operands, the expected result and three exception flags (inexact, invalid,
division by zero). Unused operands are written `-` (second operand) and `0`
(integer operand):

```moonbit
///|
test "elementary rows" {
  let rows =
    #|# mpfr-elementary-v1
    #|# op prec rnd x y n expected inexact invalid divbyzero
    #|exp 24 n 0x0p0 - 0 0x1p0 0 0 0
    #|ln 53 n 0x0p0 - 0 -inf 0 0 1
    #|sqrt 53 z -0x1p0 - 0 nan 0 1 0
    #|rootn 53 n 0x1bp0 - 3 0x3p0 0 0 0
    #|hypot 53 d 0x3p0 0x4p0 0 0x5p0 0 0 0
    #|
  let document = @mpfr_expr.parse_elementary_data("elem.txt", rows).unwrap()
  let summary = @mpfr_expr.execute_elementary_data(document)
  inspect(summary.total_cases(), content="5")
  inspect(summary.passed_cases(), content="5")
}
```

`ln(0) = -inf` raises division by zero and `sqrt(-1)` is an invalid operation
returning NaN; both flags are part of the check.

### Integer powers

A `pow` row splits each number into coefficient, binary exponent and sign:

```moonbit
///|
test "integer power rows" {
  // (3 * 2^-1)^3 = 27/8 at 11 bits, exact
  let rows =
    #|11 n 3 -1 0 3 6c0 -9 0 0
    #|
  let document = @mpfr_expr.parse_pow_data("pow.txt", rows).unwrap()
  let summary = @mpfr_expr.execute_pow_data(document)
  inspect(summary.passed_cases(), content="1")
}
```

The fields are: precision, rounding, input coefficient (hex digits), input
exponent, input sign (`1` negative), integer exponent, expected coefficient,
expected exponent, expected sign, inexact flag. Here `0x6c0p-9` is
$1728/512 = 27/8$.

### Read a failure

```moonbit
///|
test "a failing row" {
  let rows =
    #|# mpfr-elementary-v1
    #|exp 24 n 0x0p0 - 0 0x2p0 0 0 0
    #|
  let summary = @mpfr_expr.execute_elementary_data(
    @mpfr_expr.parse_elementary_data("bad.txt", rows).unwrap(),
  )
  let result = summary.results()[0]
  inspect(result.id(), content="exp:2")
  inspect(
    result.message(),
    content="elementary mismatch: expected 0x1p1 flags=false/false/false, actual 0x1p0 flags=false/false/false",
  )
}
```

The id is the operation (or `sqrt`/`pow`) and the line number.

### Parse errors

Every malformed line is reported with its line number, and no document is
returned:

```moonbit
///|
test "parse errors" {
  match @mpfr_expr.parse_sqrt_data("bad.sqrt", "53 53 x 0x1p0 0x1p0\n53 53\n") {
    Err(diagnostics) =>
      inspect(
        diagnostics.map(d => d.line().to_string() + ": " + d.message()).join("; "),
        content="1: invalid or unsupported MPFR data_check directive; 2: MPFR data_check row must contain five fields",
      )
    Ok(_) => fail("expected diagnostics")
  }
}
```

## Going further

- **Corpora.** `just conformance run binary` executes the pinned MPFR
  `tests/data/sqrt` file and the committed elementary matrix
  `testdata/bin_float/mpfr-4.2.2-elementary.txt` together with TestFloat; see
  [verification](../../verification.md). The generators for the elementary
  and power data are `tools/generate_mpfr_elementary_oracle.c` and
  `tools/generate_mpfr_pow_oracle.c`.
- **Which parser?** The CLI chooses the elementary format when the file
  contains `mpfr-elementary-v1`, the power format when it contains
  `input_coefficient_hex`, and the square-root format otherwise. Put the
  marker in a comment line.

## Common pitfalls

- **Elementary rows compare numbers, not encodings.** `+0` and `-0` compare
  equal there, and any NaN matches an expected `nan`. Square-root and power
  rows compare the whole `BinFloat`, including the sign of zero.
- **Square-root flags are not checked.** `sqrt` data rows compare only the
  value.
- **No exponent range.** Rows are executed in an unbounded context: there is
  no overflow, underflow or subnormal range, and an elementary or power row
  that reports overflow or underflow fails.
- **Binary operations need a second operand.** An elementary `pow`, `hypot`
  or `atan2` row with `-` as second operand is accepted by the parser but
  aborts the whole run when executed.
- **Inputs are read at 512 bits.** Elementary and power operands with longer
  significands are rounded before the function is evaluated.

## Next steps

- [frontend/mpfr_expr API](../../api/frontend/mpfr_expr.md) for every item
  and the exact field layouts.
- [frontend/mpfr_expr design](../../design/frontend/mpfr_expr.md) for the
  pass rules.
- [cli/mpfr_expr_cli tutorial](../cli/mpfr_expr_cli.md) for running a file
  from the command line.
- [bin_float tutorial](../bin_float.md) for the functions being tested.
