# itl_expr_cli tutorial

This tutorial shows how to run ITF1788 `.itl` files with the interval runner,
select operations, and read its JSON report. The runner is reached as
`floating-conformance --backend itl`; below, `itl` abbreviates that command.

## Quick start

```sh
just conformance build interval
_build/conformance/itl/native/release/build/itl-conformance.exe --backend itl
```

With no path the runner executes `testdata/interval/smoke.itl` and prints one
JSON object such as

```text
{"schemaVersion":1,"runner":"itl-expression-interpreter","totalCases":…,"executableCases":…,"passedCases":…,"failedCases":0,…}
```

## Everyday tasks

### Run files

```sh
itl .tmp/interval/itf1788/libieeep1788_tests_set.itl
itl a.itl b.itl
```

Paths must be files; they are read in the given order.

### Select operations

```sh
itl --operation add --operation sub libieeep1788_tests_elem.itl
```

Only cases whose operation is one of the listed names are executed and
counted.

### Make unsupported operations fail

```sh
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
- **All parse diagnostics are printed** as `PATH: MESSAGE`, and the run stops.

## Next steps

- [itl_expr_cli API](../../api/cli/itl_expr_cli.md)
- [itl_expr_cli design](../../design/cli/itl_expr_cli.md)
