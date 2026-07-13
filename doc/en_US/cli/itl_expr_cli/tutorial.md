# `cli/itl_expr_cli` Tutorial

## Quick Start

Filesystem and JSON adapter for ITL interval cases.

## Workflow

Run the package through the repository wrapper so dependency and target handling match CI:

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- --backend itl --help
```

Read failures as repository-maintenance signals; this package is not a standalone end-user product.

## Failure And Scope

Filesystem access and output are effects; interval parsing and arithmetic remain pure package calls. Do not import this package as a substitute for the numeric packages it supports.

## Next Reading

Read [API](./api.md) for the complete generated surface and [Design](./design.md) for ownership and trade-offs.
