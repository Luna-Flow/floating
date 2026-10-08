# cli/itl_expr_cli tutorial

This tutorial shows how to run ITF1788 `.itl` files with the interval runner,
select operations, and read its JSON report. The runner is reached as
`floating-conformance --backend itl`; below, `itl` abbreviates that command.

| I want to | Use |
| --- | --- |
| run the committed smoke file | [`itl` with no path](#quick-start) |
| run one or more `.itl` files | [`itl PATH …`](#run-files) |
| run only some operations | [`--operation NAME`](#select-operations) |
| fail on operations that are not implemented | [`--strict-supported`](#make-unsupported-operations-fail) |
| call the runner from MoonBit | [`@itl_expr_cli.run`](#from-moonbit-code) |

## Quick start

The executable is built from a checkout of the repository:

```bash
just conformance build interval
_build/conformance/itl/native/release/build/itl-conformance.exe --backend itl
```

With no path the runner executes `testdata/interval/smoke.itl` and prints one
JSON object such as

```text
{"schemaVersion":1,"runner":"itl-expression-interpreter","totalCases":…,"executableCases":…,"passedCases":…,"failedCases":0,…}
```

### From MoonBit code

After `moon add Luna-Flow/floating@0.8.0`, import
`"Luna-Flow/floating/cli/itl_expr_cli"` in `moon.pkg` and call `run` with the
argument vector, program name first:

```moonbit nocheck
let status = @itl_expr_cli.run(["itl", "--operation", "add", "cases.itl"])
```

## Everyday tasks

### Run files

```bash
itl .tmp/interval/itf1788/libieeep1788_tests_set.itl
itl a.itl b.itl
```

Paths must be files; they are read in the given order.

### Select operations

```bash
itl --operation add --operation sub libieeep1788_tests_elem.itl
```

Only cases whose operation is one of the listed names are executed and
counted.

### Make unsupported operations fail

```bash
itl --strict-supported --operation sqrt libieeep1788_tests_elem.itl
```

Without the flag, unsupported cases are reported in `unsupportedIds` but do
not change the exit status; diagnostic cases always do.

## Going further

- `just conformance run interval` runs the phases listed in
  `testdata/interval/interpreter_stages.json` (files and operations per
  phase); add `--strict-supported` to forward strict mode to every phase.
- [itl_expr tutorial](../frontend/itl_expr.md) explains the cases and the
  pass rule.

## Common pitfalls

- **No `--json` option.** The output is always JSON; passing `--json` is an
  unknown option (exit `2`).
- **No sharding.** ITL files are small; the tooling parallelizes by phase.
- **All parse diagnostics are printed** as `PATH: MESSAGE`, and the run stops,
  even when the bad statement belongs to an operation you did not select.
- **Unknown operations with non-interval operands fail the run.** Without
  `--operation`, cases such as `nums2interval 1.0 2.0 = …` are diagnostics,
  and any diagnostic makes the exit status `1`. Tracked in [#75](https://github.com/Luna-Flow/floating/issues/75); a fix is
  proposed in [#82](https://github.com/Luna-Flow/floating/pull/82).

## Next steps

- [cli/itl_expr_cli API](../../api/cli/itl_expr_cli.md)
- [cli/itl_expr_cli design](../../design/cli/itl_expr_cli.md)
- [frontend/itl_expr tutorial](../frontend/itl_expr.md) for the cases and
  the pass rule.
