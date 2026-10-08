# internal/conformance API

## Purpose

`internal/conformance` is the shared result model of the conformance
frontends: source locations, per-case results with a disposition, run
summaries with fixed counting rules, and deterministic shard selection.
`frontend/gda_expr`, `frontend/itl_expr`, `frontend/mpfr_expr`,
`frontend/testfloat_expr` and `internal/runner_cli` build on it and wrap its
types in their own public types. It is an internal package: code outside
the `Luna-Flow/floating` module cannot import it, and its interface may change
without notice. See the [tutorial](../../tutorial/internal/conformance.md) and
the [design page](../../design/internal/conformance.md).

## Importing

Inside the module, add the package to `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/internal/conformance",
}
```

The examples call the package as `@conformance.`. The manual's example checker
has no alias for internal subpackages, so they are marked `nocheck`; each one
is a copy of behaviour checked by the package's own tests or verified by hand
against the source.

## Source locations

### `SourceLocation`

`SourceLocation` is a position in a named source.

```mbti
pub struct SourceLocation {
  // private fields
} derive(Eq, @debug.Debug)
```

### `SourceLocation::new`

`SourceLocation::new(source, line, column?)` creates a location.

```mbti
pub fn SourceLocation::new(String, Int, column? : Int) -> Self
```

`column` defaults to `1`. Line and column are clamped to at least `1`, so a
location always points at a real character position.

### `SourceLocation::source`, `SourceLocation::line`, `SourceLocation::column`

These accessors return the components.

```mbti
pub fn SourceLocation::source(Self) -> String
pub fn SourceLocation::line(Self) -> Int
pub fn SourceLocation::column(Self) -> Int
```

```moonbit nocheck
///|
test "locations are one-based" {
  let location = @conformance.SourceLocation::new("a.txt", 0, column=-3)
  inspect(location.line(), content="1")
  inspect(location.column(), content="1")
}
```

## Case results

### `CaseDisposition`

`CaseDisposition` classifies a selected case.

```mbti
pub(all) enum CaseDisposition {
  Executable
  Diagnostic(String)
  Legacy(String)
  Unsupported(String)
} derive(Eq, @debug.Debug)
```

- `Executable`: the case was run; its `passed` flag is meaningful.
- `Diagnostic(reason)`: the case is not a valid test of this kind (for
  example a placeholder row).
- `Legacy(reason)`: the case belongs to an older version of the corpus format.
- `Unsupported(reason)`: the case is valid but the implementation does not
  provide the feature.

### `CaseResult`

`CaseResult` is the outcome of one case.

```mbti
pub struct CaseResult {
  // private fields
} derive(Eq, @debug.Debug)
```

### `CaseResult::new`, `CaseResult::executable`

`CaseResult::new(id, disposition, passed, message?)` builds a result;
`CaseResult::executable(id, passed, message?)` is `new` with `Executable`.

```mbti
pub fn CaseResult::new(String, CaseDisposition, Bool, message? : String) -> Self
pub fn CaseResult::executable(String, Bool, message? : String) -> Self
```

`message` defaults to `""`. No consistency check is made between
`disposition` and `passed`; summaries only read `passed` for executable
results.

### `CaseResult::id`, `CaseResult::disposition`, `CaseResult::passed`, `CaseResult::message`

These accessors return the stored fields.

```mbti
pub fn CaseResult::id(Self) -> String
pub fn CaseResult::disposition(Self) -> CaseDisposition
pub fn CaseResult::passed(Self) -> Bool
pub fn CaseResult::message(Self) -> String
```

## Sharding

### `ShardSpec`

`ShardSpec` is a validated pair (shard count, shard index).

```mbti
pub struct ShardSpec {
  // private fields
} derive(Eq, @debug.Debug)
```

### `ShardSpec::try_new`, `ShardSpec::new`

`ShardSpec::try_new(count, index)` validates and builds a shard;
`ShardSpec::new` aborts with the same message instead of returning `Err`.

```mbti
pub fn ShardSpec::try_new(Int, Int) -> Result[Self, String]
pub fn ShardSpec::new(Int, Int) -> Self
```

Errors: `"shard count must be positive"` when `count <= 0`, and
`"shard index must be within shard count"` unless `0 <= index < count`.

### `ShardSpec::count`, `ShardSpec::index`

These accessors return the count $n$ and the index $i$.

```mbti
pub fn ShardSpec::count(Self) -> Int
pub fn ShardSpec::index(Self) -> Int
```

### `ShardSpec::selects`

`shard.selects(k)` is true when the case with ordinal `k` belongs to this
shard, that is when $k \bmod n = i$.

```mbti
pub fn ShardSpec::selects(Self, Int) -> Bool
```

Ordinals are expected to be non-negative. MoonBit's `%` keeps the sign of
the dividend, so a negative ordinal $k$ is selected by shard 0 when $n$
divides $k$ and by no shard otherwise (`ShardSpec::new(3, 0).selects(-3)` is
`true`, `selects(-1)` is false for every index).

```moonbit nocheck
///|
test "round-robin selection" {
  let shard = @conformance.ShardSpec::new(3, 1)
  let picked = [0, 1, 2, 3, 4, 5, 6].filter(k => shard.selects(k))
  debug_inspect(picked, content="[1, 4]")
  inspect(@conformance.ShardSpec::try_new(0, 0) is Err(_), content="true")
}
```

## Run summaries

### `RunSummary`

`RunSummary` counts the results of one run or shard.

```mbti
pub struct RunSummary {
  // private fields
} derive(Eq, @debug.Debug)
```

### `RunSummary::from_results`

`RunSummary::from_results(total, results)` counts `results` and records
`total` as the number of cases before shard selection.

```mbti
pub fn RunSummary::from_results(Int, Array[CaseResult]) -> Self
```

Each result is counted once: an `Executable` result as passed or failed
according to `passed()`, any other result as skipped and in its own
disposition counter. The results are copied.

### `RunSummary::merge`

`RunSummary::merge(parts)` combines shard summaries.

```mbti
pub fn RunSummary::merge(Array[Self]) -> Self
```

All counters are summed except `total_cases`, which is the maximum over the
parts; results are concatenated in the order of `parts`. An empty array gives
an empty summary.

### `RunSummary::total_cases`, `RunSummary::selected_cases`, `RunSummary::executable_cases`, `RunSummary::passed_cases`, `RunSummary::failed_cases`

These accessors return the run-level counters.

```mbti
pub fn RunSummary::total_cases(Self) -> Int
pub fn RunSummary::selected_cases(Self) -> Int
pub fn RunSummary::executable_cases(Self) -> Int
pub fn RunSummary::passed_cases(Self) -> Int
pub fn RunSummary::failed_cases(Self) -> Int
```

`total_cases` is the caller's total (the maximum over merged parts);
`selected_cases` is the number of results.

### `RunSummary::skipped_cases`, `RunSummary::diagnostic_cases`, `RunSummary::legacy_cases`, `RunSummary::unsupported_cases`

These accessors return the skip counters, in total and per disposition.

```mbti
pub fn RunSummary::skipped_cases(Self) -> Int
pub fn RunSummary::diagnostic_cases(Self) -> Int
pub fn RunSummary::legacy_cases(Self) -> Int
pub fn RunSummary::unsupported_cases(Self) -> Int
```

### `RunSummary::results`, `RunSummary::success`

`results()` returns a copy of the results in counting order; `success()` is the
verdict.

```mbti
pub fn RunSummary::results(Self) -> Array[CaseResult]
pub fn RunSummary::success(Self) -> Bool
```

The identities

$$
\begin{aligned}
\text{selected} &= \text{executable} + \text{skipped}, \\
\text{executable} &= \text{passed} + \text{failed}, \\
\text{skipped} &= \text{diagnostic} + \text{legacy} + \text{unsupported}
\end{aligned}
$$

hold for every summary built by `from_results` or `merge`. `success()` is
`failed_cases() == 0`; skipped cases never make it false, and a summary with
no executable case (including `merge([])`) is a success. Frontends that need
a stricter verdict (`itl_expr` also fails on diagnostics) add their own rule.

```moonbit nocheck
///|
test "summary counting" {
  let summary = @conformance.RunSummary::from_results(10, [
    @conformance.CaseResult::executable("a", true),
    @conformance.CaseResult::executable("b", false, message="mismatch"),
    @conformance.CaseResult::new("c", @conformance.Unsupported("op"), false),
  ])
  inspect(summary.total_cases(), content="10")
  inspect(summary.selected_cases(), content="3")
  inspect(summary.skipped_cases(), content="1")
  inspect(summary.success(), content="false")
}
```

## Trait implementations

All five types derive `Eq` and `Debug`; the promoted methods below compare all
fields and render values. Use `==`, `!=` and `debug_inspect` in new code.

### `SourceLocation::equal`, `SourceLocation::not_equal`, `SourceLocation::to_repr`

```mbti
pub fn SourceLocation::equal(Self, Self) -> Bool
pub fn SourceLocation::not_equal(Self, Self) -> Bool
pub fn SourceLocation::to_repr(Self) -> @debug.Repr
```

### `CaseDisposition::equal`, `CaseDisposition::not_equal`, `CaseDisposition::to_repr`

```mbti
pub fn CaseDisposition::equal(Self, Self) -> Bool
pub fn CaseDisposition::not_equal(Self, Self) -> Bool
pub fn CaseDisposition::to_repr(Self) -> @debug.Repr
```

Two dispositions with the same constructor and different reasons are
different.

### `CaseResult::equal`, `CaseResult::not_equal`, `CaseResult::to_repr`

```mbti
pub fn CaseResult::equal(Self, Self) -> Bool
pub fn CaseResult::not_equal(Self, Self) -> Bool
pub fn CaseResult::to_repr(Self) -> @debug.Repr
```

### `ShardSpec::equal`, `ShardSpec::not_equal`, `ShardSpec::to_repr`

```mbti
pub fn ShardSpec::equal(Self, Self) -> Bool
pub fn ShardSpec::not_equal(Self, Self) -> Bool
pub fn ShardSpec::to_repr(Self) -> @debug.Repr
```

### `RunSummary::equal`, `RunSummary::not_equal`, `RunSummary::to_repr`

```mbti
pub fn RunSummary::equal(Self, Self) -> Bool
pub fn RunSummary::not_equal(Self, Self) -> Bool
pub fn RunSummary::to_repr(Self) -> @debug.Repr
```

Summary equality includes the order of the result list, so a merged summary
equals the serial summary only in its counters, not as a value (see the
[design page](../../design/internal/conformance.md)).

```moonbit nocheck
///|
test "debug rendering" {
  debug_inspect(
    @conformance.SourceLocation::new("a", 0),
    content="{ source: \"a\", line: 1, column: 1 }",
  )
  debug_inspect(@conformance.CaseDisposition::Legacy("x"), content="Legacy(\"x\")")
}
```

## Complete public interface

This snapshot is the generated `pkg.generated.mbti` of the package. It is the authority when prose and interface disagree.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/internal/conformance"

import {
  "moonbitlang/core/debug",
}

// Values

// Errors

// Types and methods
pub(all) enum CaseDisposition {
  Executable
  Diagnostic(String)
  Legacy(String)
  Unsupported(String)
} derive(Eq, @debug.Debug)
pub fn CaseDisposition::equal(Self, Self) -> Bool
pub fn CaseDisposition::not_equal(Self, Self) -> Bool
pub fn CaseDisposition::to_repr(Self) -> @debug.Repr

pub struct CaseResult {
  // private fields
} derive(Eq, @debug.Debug)
pub fn CaseResult::disposition(Self) -> CaseDisposition
pub fn CaseResult::equal(Self, Self) -> Bool
pub fn CaseResult::executable(String, Bool, message? : String) -> Self
pub fn CaseResult::id(Self) -> String
pub fn CaseResult::message(Self) -> String
pub fn CaseResult::new(String, CaseDisposition, Bool, message? : String) -> Self
pub fn CaseResult::not_equal(Self, Self) -> Bool
pub fn CaseResult::passed(Self) -> Bool
pub fn CaseResult::to_repr(Self) -> @debug.Repr

pub struct RunSummary {
  // private fields
} derive(Eq, @debug.Debug)
pub fn RunSummary::diagnostic_cases(Self) -> Int
pub fn RunSummary::equal(Self, Self) -> Bool
pub fn RunSummary::executable_cases(Self) -> Int
pub fn RunSummary::failed_cases(Self) -> Int
pub fn RunSummary::from_results(Int, Array[CaseResult]) -> Self
pub fn RunSummary::legacy_cases(Self) -> Int
pub fn RunSummary::merge(Array[Self]) -> Self
pub fn RunSummary::not_equal(Self, Self) -> Bool
pub fn RunSummary::passed_cases(Self) -> Int
pub fn RunSummary::results(Self) -> Array[CaseResult]
pub fn RunSummary::selected_cases(Self) -> Int
pub fn RunSummary::skipped_cases(Self) -> Int
pub fn RunSummary::success(Self) -> Bool
pub fn RunSummary::to_repr(Self) -> @debug.Repr
pub fn RunSummary::total_cases(Self) -> Int
pub fn RunSummary::unsupported_cases(Self) -> Int

pub struct ShardSpec {
  // private fields
} derive(Eq, @debug.Debug)
pub fn ShardSpec::count(Self) -> Int
pub fn ShardSpec::equal(Self, Self) -> Bool
pub fn ShardSpec::index(Self) -> Int
pub fn ShardSpec::new(Int, Int) -> Self
pub fn ShardSpec::not_equal(Self, Self) -> Bool
pub fn ShardSpec::selects(Self, Int) -> Bool
pub fn ShardSpec::to_repr(Self) -> @debug.Repr
pub fn ShardSpec::try_new(Int, Int) -> Result[Self, String]

pub struct SourceLocation {
  // private fields
} derive(Eq, @debug.Debug)
pub fn SourceLocation::column(Self) -> Int
pub fn SourceLocation::equal(Self, Self) -> Bool
pub fn SourceLocation::line(Self) -> Int
pub fn SourceLocation::new(String, Int, column? : Int) -> Self
pub fn SourceLocation::not_equal(Self, Self) -> Bool
pub fn SourceLocation::source(Self) -> String
pub fn SourceLocation::to_repr(Self) -> @debug.Repr

// Type aliases

// Traits
```
<!-- generated-api-end -->
