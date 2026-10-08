# itl_expr tutorial

This tutorial shows how to run IEEE 1788 interval test cases written in the
ITL format of the ITF1788 suite against `ball_float`. You parse ITL text into
cases, execute each case, and summarize the results. The command-line runner
for whole files is [`itl_expr_cli`](../cli/itl_expr_cli.md).

## Quick start

Add the package to `moon.pkg`:

```text
import {
  "Luna-Flow/floating/frontend/itl_expr",
}
```

Parse a test case block and run it:

```moonbit
///|
test "quick start" {
  let source =
    #|testcase demo {
    #|  add [1.0,2.0] [3.0,4.0] = [4.0,6.0];
    #|  intersection [1.0,3.0] [2.0,4.0] = [2.0,3.0];
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  let summary = @itl_expr.summarize_results(
    cases.map(case => @itl_expr.execute_case(case)),
  )
  inspect(summary.passed_cases(), content="2")
  inspect(summary.success(), content="true")
}
```

Each statement `operation operand… = expected;` becomes one `ItlCase` with
the id `testcase:index`.

## Everyday tasks

### Inspect parsed cases

```moonbit
///|
test "parsed cases" {
  let source =
    #|testcase bounds {
    #|  inf [-0x1.8p1,2.5] = -3.0;
    #|  mul [1.0,2.0]
    #|      [entire] = [entire];
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  inspect(cases.map(c => c.id()).join(" "), content="bounds:1 bounds:2")
  inspect(cases[1].operation(), content="mul")
  inspect(cases[1].operands().join(" "), content="[1.0,2.0] [entire]")
  inspect(cases[1].expected(), content="[entire]")
}
```

A statement may span several lines; it ends at `;`. Bounds can be decimal or
hexadecimal (`0x1.8p1`) text, and the literals `[empty]`, `[entire]` and
`[nai]` are understood.

### Check decorations

A decoration suffix (`_com`, `_dac`, `_def`, `_trv`, `_ill`) on the expected
value makes the decoration part of the test. Without a suffix only the set is
compared. Failure messages print intervals in midpoint-radius form:

```moonbit
///|
test "decorations" {
  let source =
    #|testcase deco {
    #|  add [1.0,2.0]_com [3.0,4.0]_com = [4.0,6.0]_com;
    #|  add [1.0,2.0]_com [3.0,4.0]_com = [4.0,6.0]_def;
    #|  add [1.0,2.0]_com [3.0,4.0]_com = [4.0,6.0];
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  let passed = cases.map(c => @itl_expr.execute_case(c).passed().to_string())
  inspect(passed.join(" "), content="true false true")
  inspect(
    @itl_expr.execute_case(cases[1]).message(),
    content="expected 5p0 +/- 1p0_def, got 5p0 +/- 1p0_com",
  )
}
```

### Numbers, booleans and overlap states

Besides interval results, ITL cases can expect a number (`inf`, `sup`, `mid`,
`rad`, `wid`, `mag`, `mig`), a boolean (`isEmpty`, `subset`, `isMember`, …)
or an overlap state name:

```moonbit
///|
test "other result kinds" {
  let source =
    #|testcase kinds {
    #|  wid [1.0,3.5] = 2.5;
    #|  subset [1.0,2.0] [0.0,3.0] = true;
    #|  isMember 4.0 [1.0,3.0] = false;
    #|  overlap [1.0,2.0] [2.0,3.0] = meets;
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  let summary = @itl_expr.summarize_results(
    cases.map(c => @itl_expr.execute_case(c)),
  )
  inspect(summary.passed_cases(), content="4")
}
```

### Unsupported and malformed cases

A case the executor does not implement is `Unsupported`; a case whose operands
cannot be read is a `Diagnostic`. Neither counts as a failure, but a
diagnostic makes `success()` false:

```moonbit
///|
test "dispositions" {
  let source =
    #|testcase odd {
    #|  mulRevToPair [1.0,2.0] [3.0,4.0] = [1.0,2.0];
    #|  sqrt [one,two] = [1.0,2.0];
    #|}
  let results = @itl_expr.parse_itl(source)
    .unwrap()
    .map(c => @itl_expr.execute_case(c))
  let summary = @itl_expr.summarize_results(results)
  inspect(summary.unsupported_cases(), content="1")
  inspect(summary.diagnostic_cases(), content="1")
  inspect(summary.success(), content="false")
}
```

## Going further

- **Corpus runs.** `just conformance run interval` fetches the pinned ITF1788
  corpus, builds the native runner and runs the strict phases listed in
  `testdata/interval/interpreter_stages.json`; see
  [verification](../../verification.md).
- **Filtering by operation.** The CLI's `--operation NAME` option keeps only
  cases of that operation; in code, filter `cases` by `operation()` before
  executing.
- **Precision.** `execute_case(case, precision=p)` parses bounds at `p` bits;
  the interval operations themselves are rounded to binary64, so keep the
  default `53` for ITF1788 data.

## Common pitfalls

- **Decimal bounds are rounded to nearest.** A bound such as `0.1` is read as
  the nearest binary64 number, not rounded outward, so `[0.1,0.1]` is the
  singleton of that binary64 number.
- **Signals are not checked.** ITL annotations such as `signal …` after the
  expected value make the expected value unreadable; such cases become
  unsupported or diagnostic rather than passing.
- **Parse errors reject the input.** `parse_itl` returns only diagnostics if
  any statement lacks `=` or an operation, or if the text ends inside a
  statement.

## Next steps

- [itl_expr API](../../api/frontend/itl_expr.md) for every item and the list
  of executed operations.
- [itl_expr design](../../design/frontend/itl_expr.md) for the pass rule.
- [ball_float tutorial](../ball_float.md) for the interval arithmetic being
  tested.
