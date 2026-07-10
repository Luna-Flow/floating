# `numeric_expr` API

`numeric_expr` supplies a host-independent numeric expression core. Expression
storage is private.

## Syntax Types

- `SourceSpan::new(source, line?, column?)` records location metadata; access it
  with `source`, `line`, and `column`.
- `Literal::new(raw, span?)` stores source text and exposes `raw` and `span`.
- `Operation::new(name, span?)` stores an operation name and source span.
- `Expr::literal` and `Expr::invoke` build literal and primitive-application nodes.

## Evaluation

`evaluate(expr, literal_callback, operation_callback)` evaluates children before
calling the operation callback. It returns `Result[V, EvalError[E]]`.
`EvalError` distinguishes literal failure, operation failure, and an expression
shape unsupported by the current evaluator.
