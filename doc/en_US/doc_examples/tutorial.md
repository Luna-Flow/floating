# `doc_examples` Tutorial

## Quick Start

Executable home for examples shared by localized documentation.

## Workflow

Run the package through the repository wrapper so dependency and target handling match CI:

```sh
just docs
```

Read failures as repository-maintenance signals; this package is not a standalone end-user product.

## Failure And Scope

The package runs only under tests and performs no filesystem or process effects. Do not import this package as a substitute for the numeric packages it supports.

## Next Reading

Read [API](./api.md) for the complete generated surface and [Design](./design.md) for ownership and trade-offs.
