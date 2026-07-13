# `internal/runner_cli` Tutorial

## Quick Start

Effect boundary shared by native conformance command adapters.

## Workflow

Run the package through the repository wrapper so dependency and target handling match CI:

```sh
sh tools/run_moon_clean_exec.sh test -p Luna-Flow/floating/internal/runner_cli --target native
```

Read failures as repository-maintenance signals; this package is not a standalone end-user product.

## Failure And Scope

Filesystem reads and rendering are intentionally contained here; the conformance model and numeric frontends stay pure. Do not import this package as a substitute for the numeric packages it supports.

## Next Reading

Read [API](./api.md) for the complete generated surface and [Design](./design.md) for ownership and trade-offs.
