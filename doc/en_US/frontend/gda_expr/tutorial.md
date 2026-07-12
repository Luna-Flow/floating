# `frontend/gda_expr` Tutorial

## Repository Workflow

Use `just smoke` for the checked-in fixture, `just conformance run decimal
--phase ... --cases ...` while fixing Decimal semantics, `just pr` for the fast
pre-PR gate, and `just ci` for the complete repository gate. The command reference is in
[Decimal Conformance Data](../../../../testdata/decimal/README.md).

## Direct CLI Use

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- \
  --backend gda --cases quax1010..quax1015 --json \
  testdata/decimal/official/quantize.decTest
```

Direct CLI runs skip `moon check` and `moon info`. Use the standard gate before
publishing. The official corpus's diagnostic rows are only `#` placeholder or
non-scalar invalid inputs; legal GDA rows are executed and must pass. Any
legacy/unsupported classification is a regression signal.
