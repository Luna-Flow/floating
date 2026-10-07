# `cli/gda_expr_cli` Design

## Responsibility

Filesystem and rendering adapter for GDA `.decTest` execution.

## Data Flow

It expands inputs, reads each source once, delegates parsing/execution to `frontend/gda_expr`, then renders text or schema-versioned JSON.

## Algorithms And Invariants

Filtering and sharding are deterministic; strict mode fails on unsupported rows, while diagnostics stay classified separately.

## Failure And Effects

File reads, argument handling, JSON rendering, and exit status are effects isolated from the pure frontend.

## Implementation Trade-offs

Keeping transport separate makes parser tests deterministic, at the cost of a small adapter API used only by the main CLI.

## Stability

The package is maintained as repository infrastructure. Generated declarations may change with the runners and do not promise downstream compatibility.
