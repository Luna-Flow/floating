# `cli/gda_expr_cli`

Filesystem and output adapter for `.decTest` execution.

## Contract

It delegates parsing and arithmetic to `frontend/gda_expr` and is not a general GDA library.

## Maintainer Quick Start

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- --backend gda --help
```

## Detailed Documentation

The synchronized English, Simplified Chinese, and Japanese references live under
`doc/*/cli/gda_expr_cli`. Read `api.md` for the generated surface, `tutorial.md` for the
shortest workflow, and `design.md` for invariants and trade-offs.
