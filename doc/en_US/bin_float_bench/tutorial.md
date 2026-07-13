# `bin_float_bench` Tutorial

## Quick Start

Benchmark-only package for representative `BinCoeff` operations.

## Workflow

Run the package through the repository wrapper so dependency and target handling match CI:

```sh
sh tools/run_moon_clean_exec.sh test src/bin_float_bench --target native
```

Read failures as repository-maintenance signals; this package is not a standalone end-user product.

## Failure And Scope

Skipped benchmark tests allocate and observe time locally; they perform no application IO. Do not import this package as a substitute for the numeric packages it supports.

## Next Reading

Read [API](./api.md) for the complete generated surface and [Design](./design.md) for ownership and trade-offs.
