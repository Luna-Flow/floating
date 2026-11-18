# `internal/decimal_kernel`

Status-free integer arithmetic on decimal coefficients, shared by `decimal` (IEEE 754) and `decimal_gda` (General Decimal Arithmetic).

## Contract

It computes exact integer results: it raises no condition, knows no rounding mode, context or flag, and imports neither decimal package (`tools/check_imports.py` checks this). Finalization, overflow, underflow, clamping and the status model stay in each decimal package.

## Maintainer Quick Start

```sh
just decimal-kernel-ci
```

## Detailed Documentation

The synchronized English, Simplified Chinese, and Japanese references live under
`doc/*/internal/decimal_kernel`. Read `api.md` for the generated surface, `tutorial.md` for the
shortest workflow, and `design.md` for invariants and trade-offs.
