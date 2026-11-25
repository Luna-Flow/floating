# frontend/itl_expr API

## Purpose

`frontend/itl_expr` parses interval test cases in the ITL format of the
ITF1788 suite (test data for the IEEE 1788-2015 interval standard) and executes
them against `interval`. It is a pure library: the command-line runner is
[`cli/itl_expr_cli`](../cli/itl_expr_cli.md). The
[tutorial](../../tutorial/frontend/itl_expr.md) walks through the workflow and
the [design page](../../design/frontend/itl_expr.md) gives the pass rule.

## Importing

Add the package to the `import` block of your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating-tools/frontend/itl_expr",
}
```

The examples call it through the alias `@itl_expr`; cases are written as ITL
text, so no interval package needs to be imported.

## Parsing

### `parse_itl`

`parse_itl(source)` parses ITL text into cases.

```mbti
pub fn parse_itl(String) -> Result[Array[ItlCase], Array[String]]
```

The text is read line by line, each line trimmed:

- `//` starts a comment that runs to the end of the line, so a statement may
  end in `; // note`; empty lines (also after removing the comment) are
  skipped; a line starting with `/*` starts a block comment that ends on the first later line containing
  `*/` (or on the same line);
- `testcase NAME …` starts a new block; `NAME` is the word after `testcase`
  and must be followed by a space, otherwise the diagnostic
  `"invalid testcase declaration"` is recorded; the statement counter
  restarts at 0;
- a line equal to `}` is skipped;
- every other line is appended (with a space) to the current statement, and a
  line ending in `;` completes it.

A completed statement `left = expected` is split at the first `=`. The left
side is split into words at spaces and tabs outside square brackets; the
first word is the operation and the rest are operands. The case id is
`NAME:k`, where `k` counts statements in the block from 1 (statements before
the first `testcase` use the name `anonymous`). A statement without `=` or
without an operation is a diagnostic `"NAME:k: missing '='"` or
`"NAME:k: missing operation"`; text left after the last `;` gives
`"unterminated ITL statement"`. The result is `Ok(cases)` when there is no
diagnostic and `Err(diagnostics)` otherwise.

### `ItlCase`

`ItlCase` is one parsed statement.

```mbti
pub struct ItlCase {
  // private fields
} derive(Eq, @debug.Debug)
```

### `ItlCase::id`, `ItlCase::operation`, `ItlCase::operands`, `ItlCase::expected`

These methods return the id `NAME:k`, the operation word, a copy of the
operand words and the expected text (trimmed, including any decoration
suffix).

```mbti
pub fn ItlCase::id(Self) -> String
pub fn ItlCase::operation(Self) -> String
pub fn ItlCase::operands(Self) -> Array[String]
pub fn ItlCase::expected(Self) -> String
```

## Execution

### `execute_case`

`execute_case(case, precision?)` executes one case and returns its result.

```mbti
pub fn execute_case(ItlCase, precision? : Int32) -> ItlResult
```

`precision` (default `53`, must be within `1` and `268435456`) is the significand precision of
the interval format the case runs in: bounds are read at `precision` bits and
interval results (except those of `intersection`, `convexHull`, `pow` and
`atan2`) and `mid` are rounded with
`@interval.IntervalContext::new(precision=precision, e_max=1023)`, which has the
binary64 exponent range. The default `53` is `IntervalContext::binary64()`, the format of the
ITF1788 data.

Operands and expected values are read as follows. An interval literal is
`[lo,hi]`, `[empty]`, `[entire]` or `[nai]`, optionally followed by
`_dec` with `dec` one of `com`, `dac`, `def`, `trv`, `ill` (default `com`).
A bound is `inf`/`infinity` or `nan` with an optional sign, a hexadecimal float
`0x…p…`, or decimal text. The reader accepts `nan`, but a `nan` bound inside `[lo,hi]` is not an
interval and gives a `Diagnostic`, so `nan` is usable only as a numeric expected
value or as the candidate of `isMember`. Decimal and hexadecimal bounds are rounded to
nearest-even at `precision` bits, the lower bound as well as the upper one.
This is the ITF1788 convention: its generator passes `[lo,hi]` to the inf-sup
constructor of the target type as two floating constants, so a bound is the
nearest number of the format, not the outward rounding that IEEE 1788
`textToInterval` applies to an interval literal string; the corpus relies on
it (`isSingleton [17.1, 17.1] = true`). A decimal bound is read once, by
`Binary::from_string_ctx`, and a hexadecimal one by `Binary::from_hex_ctx`, so
a literal of any length is rounded once.

The case is dispatched on its operation and expected value:

| Case | Operations | Expected | Comparison |
| --- | --- | --- | --- |
| boolean | `isEmpty`, `isEntire`, `isNaI`, `isCommonInterval`, `isSingleton`, `equal`, `subset`, `interior`, `disjoint`, `precedes`, `strictPrecedes`, `less`, `strictLess`, `isMember` | `true` or `false` | equal booleans |
| overlap | `overlap` | an overlap state name (`before`, `meets`, `overlaps`, `starts`, `containedBy`, `finishes`, `equals`, `after`, `metBy`, `overlappedBy`, `startedBy`, `contains`, `finishedBy`, `bothEmpty`, `firstEmpty`, `secondEmpty`, `undefined`) | equal names |
| numeric | `inf`, `sup`, `mid`, `rad`, `wid`, `mag`, `mig` | a bound | equal numbers |
| unary | `pos`, `neg`, `abs`, `recip`, `sqr`, `sqrt`, `sign`, `ceil`, `floor`, `trunc`, `roundTiesToEven`, `roundTiesToAway`, `exp`, `exp2`, `exp10`, `log`, `log2`, `log10`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh` | interval | equal sets |
| ternary | `fma` | interval | equal sets |
| integer power | `pown` (second operand an integer) | interval | equal sets |
| reverse | `sqrRev`, `absRev`, `coshRev`, `pownRev`, `sinRev`, `cosRev`, `tanRev`, each also as `…Bin` (the prior interval comes before the integer power of `pownRev`) | interval | equal sets |
| reverse (`mulRev` and `mulRevToPair` two operands, the others three) or two results (`mulRevToPair`) | `mulRev`, `mulRevTen`, `mulRevToPair`, `powRev1`, `powRev2`, `atan2Rev1`, `atan2Rev2` | interval (two for `mulRevToPair`) | equal sets |
| binary | `add`, `sub`, `mul`, `div`, `pow`, `atan2`, `min`, `max`, `intersection`, `convexHull`, `cancelPlus`, `cancelMinus` | interval | equal sets |

"Equal sets" means: both NaI, or both empty, or equal lower bounds and equal
upper bounds (compared numerically, so $-0 = +0$). When the expected text
contains `_`, the decorations must also be equal. The bounds of the actual
interval must also carry the labels that the representation requires: a bound
has the precision of the interval exactly when it is a number of that format. The boolean dispatch is
chosen whenever the expected text is `true` or `false`.

Dispositions:

- `Executable` when the case was run; `passed()` tells the outcome;
- `Unsupported(reason)` for an unknown operation, whatever its operands and
  expected value, a binary-dispatch case whose expected value is not an
  interval (for example one followed by a `signal` annotation), a
  binary-dispatch case with other than two operands, or a boolean predicate
  other than the five unary ones that does not have exactly two operands
  or whose second operand is unreadable, or a boolean case whose operation is not a boolean predicate
  (`unsupported boolean operation`);
- `Diagnostic(reason)` when the first operand of a boolean case, an operand of
  `isMember`, or an operand of the overlap dispatch, or an operand or the expected value of the numeric,
  unary, ternary, integer-power or reverse dispatch, cannot be read or is missing, or an operand of
  the binary dispatch is not an interval literal; the fma, unary, numeric,
  integer-power, overlap and reverse dispatches also report a wrong number of
  operands as a `Diagnostic`.

Support is decided from the operation name before any operand is read, so
`nums2interval 1.0 2.0`, `rootn [1.0,8.0] 3` and `rsqrt [1.0,4.0]` are
unsupported and do not count against `RunSummary::success`.

An interval literal that is not an interval (a lower bound above the upper
bound, a `nan` bound, a lower bound of `+inf` or an upper bound of `-inf`, the
literal `[1e400,1e400]` included, which reads as `[inf,inf]`) is reported as a
`Diagnostic` like any other unreadable literal.

### `summarize_results`

`summarize_results(results)` counts a list of results.

```mbti
pub fn summarize_results(Array[ItlResult]) -> RunSummary
```

`total_cases` is the length of the list.

## Results

### `ItlDisposition`

`ItlDisposition` says whether a case was executed.

```mbti
pub(all) enum ItlDisposition {
  Executable
  Unsupported(String)
  Diagnostic(String)
}
```

### `ItlResult`

`ItlResult` is the outcome of one case.

```mbti
pub struct ItlResult {
  // private fields
}
```

### `ItlResult::id`, `ItlResult::disposition`, `ItlResult::passed`, `ItlResult::message`

These methods return the case id, the disposition, whether the case passed,
and a message: empty on success, `"expected E, got A"` on a mismatch (intervals
printed by `DecoratedInterval::to_string`; `"output N: expected E, got A; "` for each wrong result of `mulRev`, `mulRevTen`, `mulRevToPair`, `powRev1`, `powRev2`, `atan2Rev1`, `atan2Rev2`), and a short reason or the
offending text otherwise.

```mbti
pub fn ItlResult::id(Self) -> String
pub fn ItlResult::disposition(Self) -> ItlDisposition
pub fn ItlResult::passed(Self) -> Bool
pub fn ItlResult::message(Self) -> String
```

### `RunSummary`

`RunSummary` aggregates a list of results.

```mbti
pub struct RunSummary {
  // private fields
}
```

### `RunSummary::total_cases`, `RunSummary::executable_cases`, `RunSummary::passed_cases`, `RunSummary::failed_cases`

These methods return the number of results, the number of executed cases, and
how many of those passed and failed.

```mbti
pub fn RunSummary::total_cases(Self) -> Int32
pub fn RunSummary::executable_cases(Self) -> Int32
pub fn RunSummary::passed_cases(Self) -> Int32
pub fn RunSummary::failed_cases(Self) -> Int32
```

### `RunSummary::unsupported_cases`, `RunSummary::diagnostic_cases`

These methods return the number of cases that were not executed, by
disposition.

```mbti
pub fn RunSummary::unsupported_cases(Self) -> Int32
pub fn RunSummary::diagnostic_cases(Self) -> Int32
```

### `RunSummary::results`, `RunSummary::success`

`results` returns a copy of the results in the order they were given;
`success` is the overall verdict.

```mbti
pub fn RunSummary::results(Self) -> Array[ItlResult]
pub fn RunSummary::success(Self) -> Bool
```

$\text{total} = \text{executable} + \text{unsupported} + \text{diagnostic}$ and
$\text{executable} = \text{passed} + \text{failed}$. `success()` is true when
no executable case failed **and** there is no diagnostic case; unsupported
cases do not affect it.

```moonbit
///|
test "itl summary" {
  let source =
    #|testcase s {
    #|  sub [1.0,2.0] [3.0,4.0] = [-3.0,-1.0];
    #|  sqr [-2.0,1.0] = [0.0,4.0];
    #|  mid [1.0,2.0] = 1.5;
    #|  isEmpty [empty] = true;
    #|}
  let summary = @itl_expr.summarize_results(
    @itl_expr.parse_itl(source).unwrap().map(c => @itl_expr.execute_case(c)),
  )
  inspect(summary.total_cases(), content="4")
  inspect(summary.passed_cases(), content="4")
}
```

## Trait implementations

### `ItlCase::equal`, `ItlCase::not_equal`, `ItlCase::to_repr`

These methods compare all fields of two cases and render a case for `Debug`.
Use `==`, `!=` and `debug_inspect` in new code.

```mbti
pub fn ItlCase::equal(Self, Self) -> Bool
pub fn ItlCase::not_equal(Self, Self) -> Bool
pub fn ItlCase::to_repr(Self) -> @debug.Repr
```

## Complete public interface

This snapshot is the generated `pkg.generated.mbti` of the package. It is the authority when prose and interface disagree.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating-tools/frontend/itl_expr"

import {
  "moonbitlang/core/debug",
}

// Values
pub fn execute_case(ItlCase, precision? : Int32) -> ItlResult

pub fn parse_itl(String) -> Result[Array[ItlCase], Array[String]]

pub fn summarize_results(Array[ItlResult]) -> RunSummary

// Errors

// Types and methods
#derive(Eq, @debug.Debug)
pub struct ItlCase {
  // private fields
}
pub fn ItlCase::equal(Self, Self) -> Bool
pub fn ItlCase::expected(Self) -> String
pub fn ItlCase::id(Self) -> String
pub fn ItlCase::not_equal(Self, Self) -> Bool
pub fn ItlCase::operands(Self) -> Array[String]
pub fn ItlCase::operation(Self) -> String
pub fn ItlCase::to_repr(Self) -> @debug.Repr

pub(all) enum ItlDisposition {
  Executable
  Unsupported(String)
  Diagnostic(String)
}

pub struct ItlResult {
  // private fields
}
pub fn ItlResult::disposition(Self) -> ItlDisposition
pub fn ItlResult::id(Self) -> String
pub fn ItlResult::message(Self) -> String
pub fn ItlResult::passed(Self) -> Bool

pub struct RunSummary {
  // private fields
}
pub fn RunSummary::diagnostic_cases(Self) -> Int32
pub fn RunSummary::executable_cases(Self) -> Int32
pub fn RunSummary::failed_cases(Self) -> Int32
pub fn RunSummary::passed_cases(Self) -> Int32
pub fn RunSummary::results(Self) -> Array[ItlResult]
pub fn RunSummary::success(Self) -> Bool
pub fn RunSummary::total_cases(Self) -> Int32
pub fn RunSummary::unsupported_cases(Self) -> Int32

// Type aliases

// Traits
```
<!-- generated-api-end -->
