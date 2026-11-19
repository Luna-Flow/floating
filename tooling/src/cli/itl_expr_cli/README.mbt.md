# `cli/itl_expr_cli`

Filesystem and JSON adapter for ITL interval cases.

## Contract

It delegates interval semantics to `frontend/itl_expr`; strict mode affects gate success only.

## Maintainer Quick Start

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- --backend itl --help
```

## Detailed Documentation

The synchronized English, Simplified Chinese, and Japanese references live under
`doc/*/cli/itl_expr_cli`. Read `api.md` for the generated surface, `tutorial.md` for the
shortest workflow, and `design.md` for invariants and trade-offs.
