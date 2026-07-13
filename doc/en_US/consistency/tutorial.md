# `consistency` Tutorial

## Quick Start

White-box package for cross-package laws and public-surface audits.

## Workflow

Run the package through the repository wrapper so dependency and target handling match CI:

```sh
sh tools/run_moon_clean_exec.sh test -p Luna-Flow/floating/consistency --target native
```

Read failures as repository-maintenance signals; this package is not a standalone end-user product.

## Failure And Scope

The package has no runtime API or IO. Failures are test assertions identifying a contract mismatch. Do not import this package as a substitute for the numeric packages it supports.

## Next Reading

Read [API](./api.md) for the complete generated surface and [Design](./design.md) for ownership and trade-offs.
