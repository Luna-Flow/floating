# `numeric_expr` Design

## Responsibility And Algorithm

`numeric_expr` is a syntax-only expression IR containing literals, named
operations, source spans, and invocation trees. `evaluate` performs a strict
depth-first post-order traversal: literal and operation semantics are supplied
as callbacks, child failures are wrapped with the originating syntax node, and
unsupported internal forms produce `UnsupportedExpression`.

## Boundary

The representation of `Expr` is private so frontends cannot depend on tree
layout. The package does not tokenize text, choose numeric types, define
operation arity, round values, perform IO, or schedule parallel work. It is a
pure orchestration layer; each frontend owns source policy and each backend
owns numerical semantics.
