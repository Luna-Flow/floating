# `cli/testfloat_expr_cli` Tutorial

## Quick Start

Command adapter for Berkeley TestFloat vector files.

## Workflow

Run the package through the repository wrapper so dependency and target handling match CI:

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- --backend testfloat --help
```

Read failures as repository-maintenance signals; this package is not a standalone end-user product.

## Failure And Scope

File access, option parsing, rendering, and exit status are effects isolated at this edge. Do not import this package as a substitute for the numeric packages it supports.

## Next Reading

Read [API](./api.md) for the complete generated surface and [Design](./design.md) for ownership and trade-offs.
