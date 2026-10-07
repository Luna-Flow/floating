# `cli/testfloat_expr_cli` Design

## Responsibility

Command adapter for Berkeley TestFloat vector files.

## Data Flow

It validates function, rounding, tininess, and shard options, then delegates parsing and execution to `frontend/testfloat_expr`.

## Algorithms And Invariants

Metadata is explicit and never inferred from filenames; JSON fields and exit status remain stable for tooling.

## Failure And Effects

File access, option parsing, rendering, and exit status are effects isolated at this edge.

## Implementation Trade-offs

Explicit metadata is more verbose but prevents a wrong format or rounding policy from silently selecting another oracle contract.

## Stability

The package is maintained as repository infrastructure. Generated declarations may change with the runners and do not promise downstream compatibility.
