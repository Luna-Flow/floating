# `cli` Tutorial

## Quick Start

Native executable dispatcher for the repository conformance backends.

## Workflow

Run the package through the repository wrapper so dependency and target handling match CI:

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- --help
```

Read failures as repository-maintenance signals; this package is not a standalone end-user product.

## Failure And Scope

Argument parsing and process exit are effects. Parsing, arithmetic, sharding, and summaries remain in imported packages. Do not import this package as a substitute for the numeric packages it supports.

## Next Reading

Read [API](./api.md) for the complete generated surface and [Design](./design.md) for ownership and trade-offs.
