# frontend/gda_expr API

`frontend/gda_expr` reads General Decimal Arithmetic test files (the
`.decTest` format of Cowlishaw's decimal specification) and executes their rows
against `decimal_gda`. Parsing turns every row into a `GdaCase` with its
context and a [`numeric_expr`](../numeric_expr.md) expression; execution
evaluates the expression and compares the result and the status flags with the
row. The package does no file or process IO; the command-line runner is
[`cli/gda_expr_cli`](../cli/gda_expr_cli.md). The
[tutorial](../../tutorial/frontend/gda_expr.md) shows the workflow and the
[design page](../../design/frontend/gda_expr.md) specifies the row mapping and
the pass rule.

Import the package in `moon.pkg`:

```text
import {
  "Luna-Flow/floating/frontend/gda_expr",
}
```

## Parsing

### `parse_dectest`

`parse_dectest(source, text)` parses a whole `.decTest` document.

```mbti
pub fn parse_dectest(String, String) -> Result[GdaDocument, Array[ParseDiagnostic]]
```

`source` is a name used in spans (normally the file path) and `text` is the
file content. The text is split at `\n`; line numbers start at 1. Each line is
handled as follows:

1. `--` outside quotes starts a comment; the rest of the line is dropped.
   Leading and trailing white space is trimmed and empty lines are skipped.
2. A line without `->` outside quotes is a directive `name: value`. The name
   is compared case-insensitively with `-`, `_`, spaces and tabs removed:
   `precision`, `rounding`, `minexponent`, `maxexponent`, `clamp`, `extended`
   and `dectest` update the context; `version` and unknown names are ignored.
   `precision`, `minExponent` and `maxExponent` must be integers, otherwise
   the line is a diagnostic. `clamp` is on only for the value `1`;
   `extended` is off only for the value `0`. A line without `:` is a
   diagnostic.
3. A line with `->` is a test row. The left side is tokenized into
   `id operation operand…` (at least two tokens), the right side into
   `expected condition…` (at least one token). Tokens are separated by spaces,
   tabs or line breaks; a token enclosed in `'…'` or `"…"` may contain spaces
   and loses its quotes. An unterminated quote after `->` is the diagnostic
   `unterminated quoted token`; a quote opened before `->` hides the arrow,
   so the line is reported as `expected directive or testcase row`. Fewer
   tokens than required give `malformed testcase row`.

The result is `Ok(document)` when no diagnostic was produced, and otherwise
`Err` with every diagnostic of the document in line order.

## Documents and rows

### `GdaDocument`

`GdaDocument` is a parsed file: its source name and its rows in file order.

```mbti
pub struct GdaDocument {
  // private fields
}
```

### `GdaDocument::source`, `GdaDocument::cases`, `GdaDocument::case_count`

These methods return the source name, a copy of the rows and the number of
rows.

```mbti
pub fn GdaDocument::source(Self) -> String
pub fn GdaDocument::cases(Self) -> Array[GdaCase]
pub fn GdaDocument::case_count(Self) -> Int
```

### `GdaCase`

`GdaCase` is one test row together with the context in force on its line.

```mbti
pub struct GdaCase {
  // private fields
}
```

### `GdaCase::id`, `GdaCase::operation`, `GdaCase::normalized_operation`

These methods return the row id, the operation as written, and the operation
name used for dispatch: lower case, with `-`, `_`, spaces and tabs removed.

```mbti
pub fn GdaCase::id(Self) -> String
pub fn GdaCase::operation(Self) -> String
pub fn GdaCase::normalized_operation(Self) -> String
```

### `GdaCase::operands`, `GdaCase::expected`, `GdaCase::conditions`

These methods return the operand tokens, the expected-result token and the
condition tokens, unquoted and otherwise exactly as written.

```mbti
pub fn GdaCase::operands(Self) -> Array[String]
pub fn GdaCase::expected(Self) -> String
pub fn GdaCase::conditions(Self) -> Array[String]
```

The arrays are copies.

### `GdaCase::context`, `GdaCase::span`, `GdaCase::expression`

These methods return the directive context of the row, its span (source,
line, column 1), and the row as an expression.

```mbti
pub fn GdaCase::context(Self) -> GdaContext
pub fn GdaCase::span(Self) -> @numeric_expr.SourceSpan
pub fn GdaCase::expression(Self) -> @numeric_expr.Expr
```

The expression is `Expr::invoke(Operation::new(normalized_operation), …)`
applied to one `Expr::literal` per operand, all carrying the row's span.

### `GdaContext`

`GdaContext` is the directive state of a document at a given row.

```mbti
pub struct GdaContext {
  // private fields
} derive(Eq, @debug.Debug)
```

It is a record of the directive values as written, not a
`@decimal_gda.GdaContext`; execution converts it.

### `GdaContext::default`

`GdaContext::default()` is the context before the first directive.

```mbti
pub fn GdaContext::default() -> Self
```

Precision 34, rounding `"half_even"`, `min_exponent` $-999999999$,
`max_exponent` $999999999$, `clamp` off, `extended` on, `dectest` empty.

### `GdaContext::precision`, `rounding`, `min_exponent`, `max_exponent`, `clamp`, `extended`, `dectest`

These accessors return the directive values.

```mbti
pub fn GdaContext::precision(Self) -> Int
pub fn GdaContext::rounding(Self) -> String
pub fn GdaContext::min_exponent(Self) -> Int
pub fn GdaContext::max_exponent(Self) -> Int
pub fn GdaContext::clamp(Self) -> Bool
pub fn GdaContext::extended(Self) -> Bool
pub fn GdaContext::dectest(Self) -> String
```

`rounding` is the directive text as written (for example `"half_up"` or
`"05up"`); it is only interpreted at execution time.

### `ParseDiagnostic`

`ParseDiagnostic` is one parse error with its location.

```mbti
pub struct ParseDiagnostic {
  // private fields
} derive(Eq, @debug.Debug)
```

### `ParseDiagnostic::span`, `ParseDiagnostic::message`

These methods return the location (source, line, column 1) and the message,
for example `"unterminated quoted token"`, `"malformed testcase row"`,
`"expected directive or testcase row"` or `"invalid precision directive"`.

```mbti
pub fn ParseDiagnostic::span(Self) -> @numeric_expr.SourceSpan
pub fn ParseDiagnostic::message(Self) -> String
```

```moonbit
///|
test "parse diagnostics" {
  let text =
    #|precision: nine
    #|t1 add 1 1 -> 2
    #|t2 add 1 1 -> '2
    #|t3 add 1 1
    #|
  match @gda_expr.parse_dectest("bad.decTest", text) {
    Err(diagnostics) => {
      let lines = diagnostics.map(d => {
        d.span().line().to_string() + " " + d.message()
      })
      inspect(
        lines.join("; "),
        content="1 invalid precision directive; 3 unterminated quoted token; 4 expected directive or testcase row",
      )
    }
    Ok(_) => fail("expected diagnostics")
  }
}
```

## Execution

### `execute_documents`

`execute_documents(documents, options?)` executes the selected rows of the
documents, in order, and summarizes the results.

```mbti
pub fn execute_documents(Array[GdaDocument], options? : RunOptions) -> RunSummary
```

Rows are visited document by document in file order. A row whose id does not
match `options.case_filter()` is ignored entirely; the remaining rows are
numbered $0, 1, 2, \dots$ and row $k$ is executed when
$k \bmod n = i$ for shard count $n$ and shard index $i$. Each executed row
first gets a disposition:

- `Diagnostic` if the context is invalid (precision not positive, or
  `minexponent` above `maxexponent`), an operand is exactly `#` or `?`, or the
  expected result is exactly `#`;
- `Unsupported` if a condition is not one of the thirteen GDA conditions,
  the operation is not implemented, or the rounding directive is not
  recognized;
- `Executable` otherwise.

Only `Executable` rows are evaluated. The row passes when the result matches
the expected token and the raised conditions are exactly the listed ones; the
[design page](../../design/frontend/gda_expr.md#the-pass-rule) gives the full
rule. Non-executable rows get `passed() == false` and the message
`"skipped"`, and are counted as skipped, not failed. The function never
aborts on row content.

### `RunOptions`

`RunOptions` selects which rows `execute_documents` runs.

```mbti
pub struct RunOptions {
  // private fields
} derive(Eq, @debug.Debug)
```

### `RunOptions::new`

`RunOptions::new(shard_count?, shard_index?, strict_supported?, case_filter?)`
builds the options.

```mbti
pub fn RunOptions::new(shard_count? : Int, shard_index? : Int, strict_supported? : Bool, case_filter? : String) -> Self
```

Defaults: one shard, index 0, `strict_supported` off, empty filter (all
rows). Aborts unless `shard_count > 0` and `0 <= shard_index < shard_count`.

`case_filter` is a comma-separated list of selectors, each trimmed. A selector
`id` matches that id exactly. A selector `first..last` matches every id that
has the same length as `first` and `last` and lies between them in string
order, so `add001..add099` selects a numbered block.

`strict_supported` is stored for callers; `execute_documents` itself does not
read it. The CLI uses it to turn unsupported rows into a failing exit code.

### `RunOptions::shard_count`, `shard_index`, `strict_supported`, `case_filter`

These accessors return the option values.

```mbti
pub fn RunOptions::shard_count(Self) -> Int
pub fn RunOptions::shard_index(Self) -> Int
pub fn RunOptions::strict_supported(Self) -> Bool
pub fn RunOptions::case_filter(Self) -> String
```

## Results

### `CaseDisposition`

`CaseDisposition` says whether a row was executed and, if not, why.

```mbti
pub(all) enum CaseDisposition {
  Executable
  Diagnostic(String)
  Legacy(String)
  Unsupported(String)
}
```

The string is a short reason such as
`"diagnostic interchange/non-scalar row"` or
`"unsupported operation frobnicate"`. `Legacy` exists for the shared result
model; the current executor never assigns it.

### `CaseResult`

`CaseResult` is the outcome of one selected row.

```mbti
pub struct CaseResult {
  // private fields
}
```

### `CaseResult::id`, `disposition`, `passed`, `message`

These methods return the row id, its disposition, whether it passed, and a
message: empty for a pass, `"skipped"` for a non-executable row,
`"evaluation failed"` when an operand could not be decoded or the operation
rejected its operands, and otherwise a
`"result mismatch: expected …, actual …"` or
`"status flags mismatch: expected …, actual …"` text.

```mbti
pub fn CaseResult::id(Self) -> String
pub fn CaseResult::disposition(Self) -> CaseDisposition
pub fn CaseResult::passed(Self) -> Bool
pub fn CaseResult::message(Self) -> String
```

### `RunSummary`

`RunSummary` aggregates the results of a run.

```mbti
pub struct RunSummary {
  // private fields
}
```

### `RunSummary` counters

These methods return the counts of a run.

```mbti
pub fn RunSummary::total_cases(Self) -> Int
pub fn RunSummary::selected_cases(Self) -> Int
pub fn RunSummary::executable_cases(Self) -> Int
pub fn RunSummary::passed_cases(Self) -> Int
pub fn RunSummary::failed_cases(Self) -> Int
pub fn RunSummary::skipped_cases(Self) -> Int
pub fn RunSummary::diagnostic_cases(Self) -> Int
pub fn RunSummary::legacy_cases(Self) -> Int
pub fn RunSummary::unsupported_cases(Self) -> Int
```

`total_cases` counts the rows that match the filter (in all shards);
`selected_cases` the rows executed by this shard. They satisfy

$$
\begin{aligned}
\text{selected} &= \text{executable} + \text{skipped}, &
\text{executable} &= \text{passed} + \text{failed}, \\
\text{skipped} &= \text{diagnostic} + \text{legacy} + \text{unsupported}. &&
\end{aligned}
$$

### `RunSummary::results`, `RunSummary::success`

`results` returns a copy of the per-row results in execution order; `success`
is true when no executable row failed.

```mbti
pub fn RunSummary::results(Self) -> Array[CaseResult]
pub fn RunSummary::success(Self) -> Bool
```

Skipped rows do not affect `success`.

### `RunSummary::merge`

`RunSummary::merge(parts)` combines the summaries of the shards of one run.

```mbti
pub fn RunSummary::merge(Array[Self]) -> Self
```

All counters except `total_cases` are added; `total_cases` is the maximum of
the parts (every shard reports the same total). Results are concatenated in
the order of `parts`. Merging the $n$ shards of a run gives the same counters
as an unsharded run.

```moonbit
///|
test "merge shards" {
  let text =
    #|s1 add 1 1 -> 2
    #|s2 add 1 2 -> 3
    #|s3 add 1 3 -> 5
    #|
  let document = @gda_expr.parse_dectest("s.decTest", text).unwrap()
  let parts = [0, 1].map(i => {
    @gda_expr.execute_documents(
      [document],
      options=@gda_expr.RunOptions::new(shard_count=2, shard_index=i),
    )
  })
  let merged = @gda_expr.RunSummary::merge(parts)
  inspect(merged.total_cases(), content="3")
  inspect(merged.passed_cases(), content="2")
  inspect(merged.failed_cases(), content="1")
}
```

## Trait implementations

### `GdaContext`, `ParseDiagnostic` and `RunOptions` equality and `Debug`

These methods compare all fields and render the value for `Debug`. Use `==`,
`!=` and `debug_inspect` in new code.

```mbti
pub fn GdaContext::equal(Self, Self) -> Bool
pub fn GdaContext::not_equal(Self, Self) -> Bool
pub fn GdaContext::to_repr(Self) -> @debug.Repr
pub fn ParseDiagnostic::equal(Self, Self) -> Bool
pub fn ParseDiagnostic::not_equal(Self, Self) -> Bool
pub fn ParseDiagnostic::to_repr(Self) -> @debug.Repr
pub fn RunOptions::equal(Self, Self) -> Bool
pub fn RunOptions::not_equal(Self, Self) -> Bool
pub fn RunOptions::to_repr(Self) -> @debug.Repr
```

## Complete public interface

This snapshot is the generated `pkg.generated.mbti` of the package. It is the authority when prose and interface disagree.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/frontend/gda_expr"

import {
  "Luna-Flow/floating/numeric_expr",
  "moonbitlang/core/debug",
}

// Values
pub fn execute_documents(Array[GdaDocument], options? : RunOptions) -> RunSummary

pub fn parse_dectest(String, String) -> Result[GdaDocument, Array[ParseDiagnostic]]

// Errors

// Types and methods
pub(all) enum CaseDisposition {
  Executable
  Diagnostic(String)
  Legacy(String)
  Unsupported(String)
}

pub struct CaseResult {
  // private fields
}
pub fn CaseResult::disposition(Self) -> CaseDisposition
pub fn CaseResult::id(Self) -> String
pub fn CaseResult::message(Self) -> String
pub fn CaseResult::passed(Self) -> Bool

pub struct GdaCase {
  // private fields
}
pub fn GdaCase::conditions(Self) -> Array[String]
pub fn GdaCase::context(Self) -> GdaContext
pub fn GdaCase::expected(Self) -> String
pub fn GdaCase::expression(Self) -> @numeric_expr.Expr
pub fn GdaCase::id(Self) -> String
pub fn GdaCase::normalized_operation(Self) -> String
pub fn GdaCase::operands(Self) -> Array[String]
pub fn GdaCase::operation(Self) -> String
pub fn GdaCase::span(Self) -> @numeric_expr.SourceSpan

pub struct GdaContext {
  // private fields
} derive(Eq, @debug.Debug)
pub fn GdaContext::clamp(Self) -> Bool
pub fn GdaContext::dectest(Self) -> String
pub fn GdaContext::default() -> Self
pub fn GdaContext::equal(Self, Self) -> Bool
pub fn GdaContext::extended(Self) -> Bool
pub fn GdaContext::max_exponent(Self) -> Int
pub fn GdaContext::min_exponent(Self) -> Int
pub fn GdaContext::not_equal(Self, Self) -> Bool
pub fn GdaContext::precision(Self) -> Int
pub fn GdaContext::rounding(Self) -> String
pub fn GdaContext::to_repr(Self) -> @debug.Repr

pub struct GdaDocument {
  // private fields
}
pub fn GdaDocument::case_count(Self) -> Int
pub fn GdaDocument::cases(Self) -> Array[GdaCase]
pub fn GdaDocument::source(Self) -> String

pub struct ParseDiagnostic {
  // private fields
} derive(Eq, @debug.Debug)
pub fn ParseDiagnostic::equal(Self, Self) -> Bool
pub fn ParseDiagnostic::message(Self) -> String
pub fn ParseDiagnostic::not_equal(Self, Self) -> Bool
pub fn ParseDiagnostic::span(Self) -> @numeric_expr.SourceSpan
pub fn ParseDiagnostic::to_repr(Self) -> @debug.Repr

pub struct RunOptions {
  // private fields
} derive(Eq, @debug.Debug)
pub fn RunOptions::case_filter(Self) -> String
pub fn RunOptions::equal(Self, Self) -> Bool
pub fn RunOptions::new(shard_count? : Int, shard_index? : Int, strict_supported? : Bool, case_filter? : String) -> Self
pub fn RunOptions::not_equal(Self, Self) -> Bool
pub fn RunOptions::shard_count(Self) -> Int
pub fn RunOptions::shard_index(Self) -> Int
pub fn RunOptions::strict_supported(Self) -> Bool
pub fn RunOptions::to_repr(Self) -> @debug.Repr

pub struct RunSummary {
  // private fields
}
pub fn RunSummary::diagnostic_cases(Self) -> Int
pub fn RunSummary::executable_cases(Self) -> Int
pub fn RunSummary::failed_cases(Self) -> Int
pub fn RunSummary::legacy_cases(Self) -> Int
pub fn RunSummary::merge(Array[Self]) -> Self
pub fn RunSummary::passed_cases(Self) -> Int
pub fn RunSummary::results(Self) -> Array[CaseResult]
pub fn RunSummary::selected_cases(Self) -> Int
pub fn RunSummary::skipped_cases(Self) -> Int
pub fn RunSummary::success(Self) -> Bool
pub fn RunSummary::total_cases(Self) -> Int
pub fn RunSummary::unsupported_cases(Self) -> Int

// Type aliases

// Traits
```
<!-- generated-api-end -->
