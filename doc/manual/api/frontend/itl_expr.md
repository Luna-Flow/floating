# frontend/itl_expr API

## Purpose

`frontend/itl_expr` parses interval test cases in the ITL format of the
ITF1788 suite (test data for the IEEE 1788-2015 interval standard) and executes
them against `ball_float`. It is a pure library: the command-line runner is
[`cli/itl_expr_cli`](../cli/itl_expr_cli.md). The
[tutorial](../../tutorial/frontend/itl_expr.md) walks through the workflow and
the [design page](../../design/frontend/itl_expr.md) gives the pass rule.

## Importing

Add the package to the `import` block of your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/frontend/itl_expr",
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

- lines starting with `//` and empty lines are skipped; a line starting with
  `/*` starts a block comment that ends on the first later line containing
  `*/` (or on the same line);
- `testcase NAME …` starts a new block; `NAME` is the word after `testcase`
  and must be followed by a space, otherwise the diagnostic
  `"invalid testcase declaration"` is recorded; the statement counter
  restarts at 0;
- a line equal to `}` is skipped;
- every other line is appended (with a space) to the current statement, and a
  line ending in `;` completes it.

Comments are recognized only at the start of a line. A `//` comment after a
statement's `;` keeps the line from ending in `;`, so the statement silently
absorbs the following lines up to the next line that ends in `;`: the text
`add [1.0,2.0] [3.0,4.0] = [4.0,6.0]; // c` followed by a `sub` statement
yields one case whose expected text is
`[4.0,6.0]; // c sub [1.0,2.0] [3.0,4.0] = [-3.0,-1.0]`. Tracked in
[#76](https://github.com/Luna-Flow/floating/issues/76); a fix is proposed in [#82](https://github.com/Luna-Flow/floating/pull/82).

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
pub fn execute_case(ItlCase, precision? : Int) -> ItlResult
```

`precision` (default `53`) is the bit precision used to read bounds.
Interval results are rounded with `@ball_float.BallContext::binary64()`
regardless of `precision`, so the default is the meaningful value for ITF1788
data (tracked in [#62](https://github.com/Luna-Flow/floating/issues/62); no fix yet).

Operands and expected values are read as follows. An interval literal is
`[lo,hi]`, `[empty]`, `[entire]` or `[nai]`, optionally followed by
`_dec` with `dec` one of `com`, `dac`, `def`, `trv`, `ill` (default `com`).
A bound is `inf`/`infinity` with an optional sign, a hexadecimal float
`0x…p…`, or decimal text. Decimal and hexadecimal bounds are rounded to
nearest-even at `precision` bits, the lower bound as well as the upper one, so
an inexact decimal literal does not give an enclosing interval (tracked in
[#62](https://github.com/Luna-Flow/floating/issues/62); no fix yet). A decimal
bound is first read as a decimal of $2p + 16$ significant digits; a literal
with more digits is rounded twice.

The case is dispatched on its operation and expected value:

| Case | Operations | Expected | Comparison |
| --- | --- | --- | --- |
| boolean | `isEmpty`, `isEntire`, `isNaI`, `isCommonInterval`, `isSingleton`, `equal`, `subset`, `interior`, `disjoint`, `precedes`, `strictPrecedes`, `less`, `strictLess`, `isMember` | `true` or `false` | equal booleans |
| overlap | `overlap` | an overlap state name (`before`, `meets`, `overlaps`, `starts`, `containedBy`, `finishes`, `equals`, `after`, `metBy`, `overlappedBy`, `startedBy`, `contains`, `finishedBy`, `bothEmpty`, `firstEmpty`, `secondEmpty`, `undefined`) | equal names |
| numeric | `inf`, `sup`, `mid`, `rad`, `wid`, `mag`, `mig` | a bound | equal numbers |
| unary | `pos`, `neg`, `abs`, `recip`, `sqr`, `sqrt`, `exp`, `exp2`, `exp10`, `log`, `log2`, `log10`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh` | interval | equal sets |
| ternary | `fma` | interval | equal sets |
| integer power | `pown` (second operand an integer) | interval | equal sets |
| binary | `add`, `sub`, `mul`, `div`, `pow`, `atan2`, `min`, `max`, `intersection`, `convexHull`, `cancelPlus`, `cancelMinus` | interval | equal sets |

"Equal sets" means: both NaI, or both empty, or equal lower bounds and equal
upper bounds (compared numerically, so $-0 = +0$). When the expected text
contains `_`, the decorations must also be equal. The boolean dispatch is
chosen whenever the expected text is `true` or `false`.

Dispositions:

- `Executable` when the case was run; `passed()` tells the outcome;
- `Unsupported(reason)` for an unknown operation whose operands are all
  interval literals, a binary-dispatch case whose expected value is not an
  interval (for example one followed by a `signal` annotation), a
  binary-dispatch case with other than two operands, or a boolean predicate
  other than the five unary ones whose second operand is missing or
  unreadable;
- `Diagnostic(reason)` when the first operand of a boolean case, an operand of
  `isMember`, or an operand or the expected value of the overlap, numeric,
  unary, ternary or integer-power dispatch, cannot be read, or an operand of
  the binary dispatch is not an interval literal.

The binary dispatch reads the operands before it looks at the operation, so
an operation the executor does not know is a `Diagnostic`, not `Unsupported`,
when one of its operands is not an interval literal: `nums2interval 1.0 2.0`
and `rootn [1.0,8.0] 3` are diagnostics, while `sqrRev [0.0,1.0] [-1.0,1.0]`
is unsupported. Because a diagnostic makes `RunSummary::success` false, run
such operations only through an operation filter. Tracked in [#75](https://github.com/Luna-Flow/floating/issues/75); a fix
is proposed in [#82](https://github.com/Luna-Flow/floating/pull/82).

`execute_case` does not abort on case content.

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
printed by `BallFloatDecorated::to_string`), and a short reason or the
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
pub fn RunSummary::total_cases(Self) -> Int
pub fn RunSummary::executable_cases(Self) -> Int
pub fn RunSummary::passed_cases(Self) -> Int
pub fn RunSummary::failed_cases(Self) -> Int
```

### `RunSummary::unsupported_cases`, `RunSummary::diagnostic_cases`

These methods return the number of cases that were not executed, by
disposition.

```mbti
pub fn RunSummary::unsupported_cases(Self) -> Int
pub fn RunSummary::diagnostic_cases(Self) -> Int
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
package "Luna-Flow/floating/frontend/itl_expr"

import {
  "moonbitlang/core/debug",
}

// Values
pub fn execute_case(ItlCase, precision? : Int) -> ItlResult

pub fn parse_itl(String) -> Result[Array[ItlCase], Array[String]]

pub fn summarize_results(Array[ItlResult]) -> RunSummary

// Errors

// Types and methods
pub struct ItlCase {
  // private fields
} derive(Eq, @debug.Debug)
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
pub fn RunSummary::diagnostic_cases(Self) -> Int
pub fn RunSummary::executable_cases(Self) -> Int
pub fn RunSummary::failed_cases(Self) -> Int
pub fn RunSummary::passed_cases(Self) -> Int
pub fn RunSummary::results(Self) -> Array[ItlResult]
pub fn RunSummary::success(Self) -> Bool
pub fn RunSummary::total_cases(Self) -> Int
pub fn RunSummary::unsupported_cases(Self) -> Int

// Type aliases

// Traits
```
<!-- generated-api-end -->
