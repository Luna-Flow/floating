# `internal/bin_kernel`

Exact integer arithmetic on the coefficients of `BinFloat`: one non-negative integer type, `Coeff`, with its multiplication, division, square root, GCD and radix-conversion algorithms and their per-target thresholds.

## Contract

It computes exact integer results: it raises no condition, knows no rounding mode, context or flag, and imports no other package of this module (`tools/check_imports.py` checks this). Rounding, exponents, classes and flags stay in `bin_float`. The package is internal: only code inside `Luna-Flow/floating` can import it, and the public coefficient type `BinCoeff` of `bin_float` is a newtype over `Coeff` whose public methods (construction, conversion, comparison, queries) forward to it; the arithmetic is available only here.

## Maintainer Quick Start

```sh
just bin-kernel-ci
```

## Detailed Documentation

The synchronized English, Simplified Chinese, and Japanese references live under
`doc/*/internal/bin_kernel`. Read `api.md` for the generated surface, `tutorial.md` for the
shortest workflow, and `design.md` for invariants and trade-offs.
