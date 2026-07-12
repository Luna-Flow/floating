# `numeric_expr`

This package documentation describes the current **`0.5.0`** baseline.

`numeric_expr` is a host-language-independent numeric expression core. It
represents literals and primitive applications today while keeping its syntax
representation private so variables, bindings, and lambda evaluation can be
added without breaking callers.

The internal syntax uses `Luna-Flow/type_theory`; filesystem access, concrete
numeric values, and operation semantics belong to frontend and backend
packages.

Public construction uses `SourceSpan`, `Literal`, `Operation`, `Expr::literal`,
and `Expr::invoke`. `evaluate` delegates literal parsing and operation dispatch
to caller-provided callbacks and reports `EvalError` with the failing syntax
node. See the multilingual package docs under `doc/*/numeric_expr` for the API,
tutorial, and design boundaries.

## Stability And Complexity

The construction and callback interfaces are provisional integration APIs; the
tree representation is private. Evaluation is a pure post-order traversal:
`O(nodes)` callback invocations and `O(depth)` traversal stack, excluding the
caller-supplied numeric operations. Keeping parsing and arithmetic outside this
package avoids coupling the IR to a particular decimal, binary, or interval
representation.
