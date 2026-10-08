# internal/conformance tutorial

The goal of this page is to help maintainers who add or change a conformance
frontend: it shows how a frontend records per-case results, summarizes a run,
splits it into shards and merges the shards back, using the shared model of
`internal/conformance`. The package is internal to `Luna-Flow/floating`, so
the examples are written for code inside the module and are not compiled by
the manual checker.

| I want to | Use |
| --- | --- |
| record the outcome of one case | [`CaseResult::executable`, `CaseResult::new`](#quick-start) |
| say why a case was not run | [`CaseDisposition`](#pick-a-disposition) |
| count a run | [`RunSummary::from_results`](#quick-start) |
| run one shard of a corpus | [`ShardSpec::selects`](#shard-a-run) |
| combine shard summaries | [`RunSummary::merge`](#shard-a-run) |
| turn user shard options into a usage error | [`ShardSpec::try_new`](#validate-user-input) |
| keep the frontend API stable | [wrapper types](#wrap-the-model-in-a-frontend-type) |

## Quick start

There is nothing to install: the package ships inside `Luna-Flow/floating`.
Run its tests from the repository:

```bash
sh tools/run_moon_clean_exec.sh test src/internal/conformance --target native
```

In a frontend package of the module, import it in `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/internal/conformance",
}
```

Record one result per case and summarize:

```moonbit nocheck
///|
test "summarize a run" {
  let results = [
    @conformance.CaseResult::executable("add001", true),
    @conformance.CaseResult::executable("add002", false, message="expected 3, got 2"),
    @conformance.CaseResult::new("add003", @conformance.Diagnostic("placeholder"), false),
  ]
  let summary = @conformance.RunSummary::from_results(3, results)
  inspect(summary.executable_cases(), content="2")
  inspect(summary.failed_cases(), content="1")
  inspect(summary.skipped_cases(), content="1")
  inspect(summary.success(), content="false")
}
```

## Everyday tasks

### Pick a disposition

Give every selected case exactly one disposition:

- `Executable` when the case was run, with `passed` telling the outcome;
- `Diagnostic(reason)` when the corpus row is not a test of this kind;
- `Unsupported(reason)` when the row is valid but the feature is missing;
- `Legacy(reason)` when the row follows an older convention that is not
  claimed.

Skipped results never fail `success()`, so choose `Unsupported` honestly:
runners with a strict mode turn unsupported rows into a failing exit code.

### Shard a run

Number the cases that pass your filters $0, 1, 2, \dots$ and keep those the
shard selects. Pass the number of filtered cases as `total`:

```moonbit nocheck
///|
fn run_shard(ids : Array[String], shard : @conformance.ShardSpec) -> @conformance.RunSummary {
  let results = []
  for ordinal, id in ids {
    if shard.selects(ordinal) {
      results.push(@conformance.CaseResult::executable(id, true))
    }
  }
  @conformance.RunSummary::from_results(ids.length(), results)
}

///|
test "shards merge to the serial run" {
  let ids = ["a", "b", "c", "d", "e"]
  let parts = [0, 1].map(i => run_shard(ids, @conformance.ShardSpec::new(2, i)))
  let merged = @conformance.RunSummary::merge(parts)
  inspect(merged.total_cases(), content="5")
  inspect(merged.selected_cases(), content="5")
}
```

### Validate user input

Command-line shard options come from users. Use `ShardSpec::try_new` and turn
the `Err` into a usage error; `ShardSpec::new` aborts.

### Wrap the model in a frontend type

Public frontends do not expose these types directly: `gda_expr`,
`mpfr_expr` and `testfloat_expr` wrap `CaseResult` and `RunSummary` in their
own structs and forward the accessors they want to publish. Follow the same
pattern so the internal model can change without breaking the frontend API.

## Going further

- Run the package tests from a workspace that contains the module:
  `moon test -p Luna-Flow/floating/internal/conformance`.
- [internal/runner_cli](runner_cli.md) parses the shared command-line options
  (`--json`, `--shard-count`, `--shard-index`) into a `ShardSpec`.

## Common pitfalls

- **Wrong total.** `total_cases` should count the cases *after* filtering and
  *before* sharding, the same number in every shard; `merge` keeps the
  maximum.
- **Negative ordinals.** `selects` uses `%`, which keeps the sign of the
  ordinal: a negative multiple of the count goes to shard 0 and every other
  negative ordinal to no shard. Always count from 0.
- **`passed` on skipped results.** It is ignored by the counters; set it to
  `false` for clarity.

## Next steps

- [internal/conformance API](../../api/internal/conformance.md)
- [internal/conformance design](../../design/internal/conformance.md)
- [gda_expr tutorial](../frontend/gda_expr.md) for a frontend built on this
  model.
