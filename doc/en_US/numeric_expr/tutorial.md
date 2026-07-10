# `numeric_expr` Tutorial

## Separate Syntax From Numeric Semantics

Build expressions from `Literal` and `Operation`, then provide two callbacks to
`evaluate`: one parses literal text into the backend value, and one dispatches
an operation name over evaluated arguments.

This split lets the same expression tree target `Decimal`, `BinFloat`, semantic
values, or a test double. Preserve `SourceSpan` in frontend diagnostics instead
of embedding filesystem behavior into the expression package.
