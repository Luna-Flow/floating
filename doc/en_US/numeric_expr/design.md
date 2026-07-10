# `numeric_expr` Design

## Responsibility Boundary

The package owns syntax construction, source locations, traversal, and generic
evaluation order. It does not own parsing files, resolving operation names, or
choosing a concrete numeric type.

## Private Representation

`Expr` hides its internal type-theory-backed term representation. Callers depend
on `literal`, `invoke`, and `evaluate`, leaving room for future syntax forms
without exposing the underlying term encoding.
