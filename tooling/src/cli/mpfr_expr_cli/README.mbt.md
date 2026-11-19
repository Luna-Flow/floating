# `cli/mpfr_expr_cli`

Command adapter for the pinned MPFR sqrt and integer-power witness formats.

## Contract

It performs transport and rendering, not MPFR arithmetic or FFI.

## Maintainer Quick Start

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- --backend mpfr --help
```

## Detailed Documentation

The synchronized English, Simplified Chinese, and Japanese references live under
`doc/*/cli/mpfr_expr_cli`. Read `api.md` for the generated surface, `tutorial.md` for the
shortest workflow, and `design.md` for invariants and trade-offs.
