# `internal/conformance` Tutorial

## Quick Start

Pure shared model for conformance locations, dispositions, shards, and summaries.

## Workflow

Run the package through the repository wrapper so dependency and target handling match CI:

```sh
sh tools/run_moon_clean_exec.sh test -p Luna-Flow/floating/internal/conformance --target native
```

Read failures as repository-maintenance signals; this package is not a standalone end-user product.

## Failure And Scope

The package performs no parsing, arithmetic, IO, or scheduling effects. Do not import this package as a substitute for the numeric packages it supports.

## Next Reading

Read [API](./api.md) for the complete generated surface and [Design](./design.md) for ownership and trade-offs.
