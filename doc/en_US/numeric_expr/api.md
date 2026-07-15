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

## Complete Public Interface

The following snapshot is the complete generated package interface for `0.7.0`. Public declarations are authoritative; prose above groups them by behavior.

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/numeric_expr"

import {
  "moonbitlang/core/debug",
}

// Values
pub fn[V, E] evaluate(Expr, (Literal) -> Result[V, E], (Operation, Array[V]) -> Result[V, E]) -> Result[V, EvalError[E]]

// Errors

// Types and methods
pub(all) enum EvalError[E] {
  LiteralFailure(Literal, E)
  OperationFailure(Operation, E)
  UnsupportedExpression(SourceSpan)
}

pub struct Expr {
  // private fields
}
pub fn Expr::invoke(Operation, Array[Self]) -> Self
pub fn Expr::literal(Literal) -> Self

pub struct Literal {
  // private fields
} derive(Eq, @debug.Debug)
pub fn Literal::new(String, span? : SourceSpan) -> Self
pub fn Literal::raw(Self) -> String
pub fn Literal::span(Self) -> SourceSpan

pub struct Operation {
  // private fields
} derive(Eq, @debug.Debug)
pub fn Operation::name(Self) -> String
pub fn Operation::new(String, span? : SourceSpan) -> Self
pub fn Operation::span(Self) -> SourceSpan

pub struct SourceSpan {
  // private fields
} derive(Eq, @debug.Debug)
pub fn SourceSpan::column(Self) -> Int
pub fn SourceSpan::line(Self) -> Int
pub fn SourceSpan::new(String, line? : Int, column? : Int) -> Self
pub fn SourceSpan::source(Self) -> String

// Type aliases

// Traits
```
<!-- generated-api-end -->
