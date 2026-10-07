# `cli` Design

## Responsibility

Native executable dispatcher for the repository conformance backends.

## Data Flow

It consumes `--backend`, forwards remaining arguments unchanged, invokes one backend adapter, and converts its return code into process exit status.

## Algorithms And Invariants

Backend names are explicit and dispatch is single-shot; the package owns no corpus grammar or numerical semantics.

## Failure And Effects

Argument parsing and process exit are effects. Parsing, arithmetic, sharding, and summaries remain in imported packages.

## Implementation Trade-offs

One executable keeps operator usage uniform, while deliberately exposing only repository verification workflows.

## Stability

The package is maintained as repository infrastructure. Generated declarations may change with the runners and do not promise downstream compatibility.
