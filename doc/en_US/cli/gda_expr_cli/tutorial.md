# `cli/gda_expr_cli` Tutorial

## Quick Start

Filesystem and rendering adapter for GDA `.decTest` execution.

## Workflow

Run the package through the repository wrapper so dependency and target handling match CI:

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- --backend gda --help
```

Read failures as repository-maintenance signals; this package is not a standalone end-user product.

## Failure And Scope

File reads, argument handling, JSON rendering, and exit status are effects isolated from the pure frontend. Do not import this package as a substitute for the numeric packages it supports.

## Next Reading

Read [API](./api.md) for the complete generated surface and [Design](./design.md) for ownership and trade-offs.
