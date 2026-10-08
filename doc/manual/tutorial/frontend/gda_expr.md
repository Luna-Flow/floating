# frontend/gda_expr tutorial

This tutorial shows how to run General Decimal Arithmetic test rows
(`.decTest` files) against `decimal_gda` from MoonBit code: parse a document,
execute it, read the summary, and find out why a row failed. It also shows how
to select rows and split a run into shards. To run whole corpora from the
command line, use the [`cli/gda_expr_cli`](../cli/gda_expr_cli.md) runner
instead.

| I want to | Use |
| --- | --- |
| run a few rows from a string | [`parse_dectest`, `execute_documents`](#quick-start) |
| see why a row failed | [`CaseResult::message`](#read-why-a-row-failed) |
| know why a row was not run | [`CaseResult::disposition`](#skipped-rows-and-dispositions) |
| run only some row ids | [`RunOptions::new(case_filter=…)`](#select-rows-and-split-work-into-shards) |
| split a run over processes | [`RunOptions::new(shard_count=…, shard_index=…)`, `RunSummary::merge`](#select-rows-and-split-work-into-shards) |
| inspect rows without running them | [`GdaDocument::cases`, `GdaCase`](#look-at-the-parsed-rows) |
| evaluate rows with my own library | [`GdaCase::expression`](#going-further) |

## Quick start

Add the library to your module and import the package in `moon.pkg`:

```bash
moon add Luna-Flow/floating@0.8.0
```

```moonbit nocheck
import {
  "Luna-Flow/floating/frontend/gda_expr",
}
```

Parse two rows and execute them:

```moonbit
///|
test "quick start" {
  let source =
    #|precision: 9
    #|rounding: half_even
    #|add001 add 1.20 2 -> 3.20
    #|div001 divide 1 3 -> 0.333333333 Inexact Rounded
    #|
  let document = @gda_expr.parse_dectest("quick.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  inspect(summary.passed_cases(), content="2")
  inspect(summary.success(), content="true")
}
```

A row has the form `id operation operand… -> expected condition…`. The
directives above the rows (`precision:`, `rounding:`, …) set the context that
every following row uses.

## Everyday tasks

### Read why a row failed

A row passes only if both the result and the exact set of conditions (status
flags) match. Each `CaseResult` carries a message for a failure:

```moonbit
///|
test "inspect failures" {
  let source =
    #|precision: 9
    #|ok1 multiply 3 4 -> 12
    #|bad1 add 1 1 -> 3
    #|bad2 divide 1 3 -> 0.333333333
    #|
  let document = @gda_expr.parse_dectest("failures.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  inspect(summary.failed_cases(), content="2")
  let messages = summary
    .results()
    .filter(r => !r.passed())
    .map(r => r.message())
  inspect(messages[0], content="result mismatch: expected 3, actual 2")
  inspect(
    messages[1],
    content="status flags mismatch: expected , actual Inexact Rounded",
  )
}
```

`bad2` has the right digits but omits `Inexact Rounded`; an extra flag is a
failure just like a missing one.

### Results are compared with their exponent

The expected result is compared as a decimal *representation*, not only as a
number: `2.0` and `2.00` have the same value but different exponents, and only
the one with the right exponent passes. Signed zeros and NaN payloads are
compared the same way.

```moonbit
///|
test "exponent matters" {
  let source =
    #|precision: 9
    #|q1 add 1.00 1.0 -> 2.00
    #|q2 add 1.00 1.0 -> 2.0
    #|z1 multiply -1 0 -> -0
    #|z2 multiply -1 0 -> 0
    #|
  let document = @gda_expr.parse_dectest("cohorts.decTest", source).unwrap()
  let passed = @gda_expr.execute_documents([document])
    .results()
    .map(r => r.id() + "=" + r.passed().to_string())
  inspect(passed.join(" "), content="q1=true q2=false z1=true z2=false")
}
```

### Skipped rows and dispositions

Some rows are not executed. Each result has a `CaseDisposition`:
`Executable` rows are run; `Diagnostic` rows (a `#` placeholder operand or
result, or a `?` operand) and `Unsupported` rows (an unknown operation,
condition or rounding mode) are counted as skipped and never fail the run.

```moonbit
///|
test "dispositions" {
  let source =
    #|precision: 9
    #|r1 add 1 1 -> 2
    #|r2 add # 1 -> #
    #|r3 frobnicate 1 -> 1
    #|rounding: banker
    #|r4 add 1 1 -> 2
    #|
  let document = @gda_expr.parse_dectest("mixed.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  inspect(summary.executable_cases(), content="1")
  inspect(summary.diagnostic_cases(), content="1")
  inspect(summary.unsupported_cases(), content="2")
  inspect(summary.skipped_cases(), content="3")
  inspect(summary.success(), content="true")
  let reasons = summary
    .results()
    .filter_map(r => {
      match r.disposition() {
        @gda_expr.Unsupported(reason) => Some(r.id() + ": " + reason)
        _ => None
      }
    })
  inspect(
    reasons.join("; "),
    content="r3: unsupported operation frobnicate; r4: unsupported rounding banker",
  )
}
```

`success()` only says that no executable row failed. A strict runner also
requires that nothing was unsupported; the CLI does this with
`--strict-supported`.

### Select rows and split work into shards

`RunOptions` filters rows by id and selects one shard of the remaining rows.
A filter is a comma-separated list of ids or ranges `first..last`, where a
range matches ids of the same length that sort between the bounds:

```moonbit
///|
test "filter and shard" {
  let source =
    #|precision: 9
    #|add001 add 1 1 -> 2
    #|add002 add 2 2 -> 4
    #|add003 add 3 3 -> 6
    #|add004 add 4 4 -> 8
    #|mul001 multiply 2 3 -> 6
    #|
  let document = @gda_expr.parse_dectest("select.decTest", source).unwrap()
  let filtered = @gda_expr.execute_documents(
    [document],
    options=@gda_expr.RunOptions::new(case_filter="add002..add004,mul001"),
  )
  inspect(filtered.total_cases(), content="4")
  let shards = [0, 1, 2].map(index => {
    @gda_expr.execute_documents(
      [document],
      options=@gda_expr.RunOptions::new(shard_count=3, shard_index=index),
    )
  })
  inspect(shards.map(s => s.selected_cases().to_string()).join(" "), content="2 2 1")
  let merged = @gda_expr.RunSummary::merge(shards)
  inspect(merged.selected_cases(), content="5")
  inspect(merged.passed_cases(), content="5")
}
```

Shard `i` of `n` takes the rows whose position among the filtered rows is
congruent to `i` modulo `n`, so the shards are disjoint and together cover
every row. `RunSummary::merge` adds the counts back up.

### Look at the parsed rows

`parse_dectest` keeps each row's text and the context in force for it, so you
can inspect a corpus without executing it:

```moonbit
///|
test "parsed rows" {
  let source =
    #|precision: 16
    #|rounding: ceiling
    #|maxExponent: 384
    #|minExponent: -383
    #|c1 add '1.5' "2" -> 3.5 -- quotes are optional
    #|
  let document = @gda_expr.parse_dectest("context.decTest", source).unwrap()
  let row = document.cases()[0]
  inspect(row.operation(), content="add")
  inspect(row.operands().join(" "), content="1.5 2")
  inspect(row.context().precision(), content="16")
  inspect(row.context().rounding(), content="ceiling")
  inspect(row.context().max_exponent(), content="384")
  inspect(row.span().line(), content="5")
}
```

## Going further

- **Interchange rows.** In a context whose precision and exponent limits are
  exactly those of decimal32, decimal64 or decimal128, operands and results
  written as `#` followed by hexadecimal digits are IEEE 754 interchange
  encodings, and the result is compared bit for bit. Operands prefixed
  `32#`, `64#` or `128#` are read in that format.
- **Expected `?`.** A result of `?` means "any value": only the conditions are
  compared.
- **Your own executor.** Every `GdaCase` exposes `expression()`, a
  [`numeric_expr`](../numeric_expr.md) tree, so you can evaluate the same rows
  with your own callbacks, for example against another decimal library.
- **Whole corpora.** `just conformance run decimal_gda` downloads the pinned
  official corpus, builds the native runner and executes all phases; see
  [verification](../../verification.md).

## Common pitfalls

- **Parse errors reject the whole document.** `parse_dectest` returns all
  diagnostics and no document if any line is malformed; fix the line or drop
  it.
- **The default context is not a decTest default.** Before any directive the
  context is precision 34, `half_even`, exponents $\pm 999999999$,
  `extended: 1`, `clamp: 0`. Real files set their own directives.
- **`success()` ignores skipped rows.** Check `unsupported_cases()` (or use
  the CLI's `--strict-supported`) if unsupported rows must fail the run.
- **Doubled quotes.** Inside a quoted token, the delimiting quote written
  twice is one literal quote (`'1''2'` is the operand `1'2`), so a quoted
  token ends only at a single matching quote.
- **Invalid contexts are skipped.** A non-positive precision directive (or
  `minexponent` above `maxexponent`) is accepted by the parser, and the rows
  under it are `Diagnostic`: they are counted in `diagnostic_cases()`, not
  executed.

## Next steps

- [frontend/gda_expr API](../../api/frontend/gda_expr.md) for every item.
- [frontend/gda_expr design](../../design/frontend/gda_expr.md) for the exact
  pass rule and the row-to-operation mapping.
- [cli/gda_expr_cli tutorial](../cli/gda_expr_cli.md) for running corpora from
  the command line.
- [decimal_gda tutorial](../decimal_gda.md) for the arithmetic being tested.
