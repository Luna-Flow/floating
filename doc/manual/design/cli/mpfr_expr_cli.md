# `cli/mpfr_expr_cli` Design

## Responsibility

Command adapter for the two pinned MPFR witness grammars.

## Data Flow

It identifies sqrt versus integer-power input, delegates parsing and execution, and renders one-file summaries.

## Algorithms And Invariants

Grammar selection is transport metadata, not a numerical heuristic; unsupported files fail before execution.

## Failure And Effects

File reads and rendering are effects. MPFR-format parsing and binary comparison remain in `frontend/mpfr_expr`.

## Implementation Trade-offs

Automatic grammar selection keeps commands short but is intentionally limited to repository-pinned formats.

## Stability

The package is maintained as repository infrastructure. Generated declarations may change with the runners and do not promise downstream compatibility.
