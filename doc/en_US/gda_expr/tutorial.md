# `gda_expr` Tutorial

## Repository Workflow

Use `just smoke` for the checked-in fixture, a focused `just pr phase=... --cases
...` command while fixing Decimal semantics, and plain `just pr` for the full
pre-PR gate. The complete command reference is in
[Decimal Conformance Data](../../../testdata/decimal/README.md).

## Direct CLI Use

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/gda_expr_cli -- \
  --cases quax1010..quax1015 --json \
  testdata/decimal/official/quantize.decTest
```

Direct CLI runs skip `moon check` and `moon info`. Use the standard gate before
publishing. Non-strict execution counts diagnostic, legacy, and unsupported rows
without treating them as semantic mismatches.
