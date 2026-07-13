# `cli/itl_expr_cli` Design

## Responsibility

Filesystem and JSON adapter for ITL interval cases.

## Data Flow

It reads ITL files, applies optional operation filters, delegates cases to `frontend/itl_expr`, and renders stable summaries.

## Algorithms And Invariants

Unsupported cases remain explicit; strict mode changes gate success, not the underlying case disposition.

## Failure And Effects

Filesystem access and output are effects; interval parsing and arithmetic remain pure package calls.

## Implementation Trade-offs

The adapter avoids duplicating interval semantics but intentionally leaves phase planning to Python tooling.

## Stability

The package is maintained as repository infrastructure. Generated declarations may change with the runners and do not promise downstream compatibility.
