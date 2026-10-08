# numeric_expr API

## Purpose

`numeric_expr` is a small expression language for numeric test corpora and
tools. On the current branch the GDA frontend `frontend/gda_expr` lowers its
`.decTest` rows to it; the other frontends execute their rows directly. An `Expr` is a tree whose leaves are literals (raw source text) and whose
inner nodes apply a named operation to argument expressions. The package does
not know any number type: `evaluate` folds the tree with two callbacks supplied
by the caller, one that decodes a literal and one that executes an operation.
Every node carries a `SourceSpan` so that a failure can be reported at its
source line. The [tutorial](../tutorial/numeric_expr.md) builds and evaluates
expressions step by step, and the [design page](../design/numeric_expr.md)
states the evaluation semantics and proves its invariants.

## Importing

Add the package to your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/numeric_expr",
}
```

The examples call the package as `@numeric_expr.`; they evaluate over `Int`
with `String` errors, so no number package is needed.
## Source locations

### `SourceSpan`

`SourceSpan` records where a syntax node came from: a source name (usually a
file path), a line and a column.

```mbti
pub struct SourceSpan {
  // private fields
} derive(Eq, @debug.Debug)
```

The fields are private and immutable. Two spans are equal when the source,
line and column are all equal.

### `SourceSpan::new`

`SourceSpan::new(source, line?, column?)` creates a span.

```mbti
pub fn SourceSpan::new(String, line? : Int, column? : Int) -> Self
```

`line` and `column` default to `0`, which means "unknown". The values are
stored as given; no range check is made.

### `SourceSpan::source`, `SourceSpan::line`, `SourceSpan::column`

These accessors return the three components of a span.

```mbti
pub fn SourceSpan::source(Self) -> String
pub fn SourceSpan::line(Self) -> Int
pub fn SourceSpan::column(Self) -> Int
```

```moonbit
///|
test "source span accessors" {
  let span = @numeric_expr.SourceSpan::new("add.decTest", line=12, column=1)
  inspect(span.source(), content="add.decTest")
  inspect(span.line(), content="12")
  let unknown = @numeric_expr.SourceSpan::new("")
  inspect(unknown.line(), content="0")
  inspect(unknown.column(), content="0")
}
```

## Syntax nodes

### `Literal`

`Literal` is a leaf of an expression: the raw text of an operand, such as
`"1.20"`, `"-Inf"` or `"#7C00016E"`, together with its span.

```mbti
pub struct Literal {
  // private fields
} derive(Eq, @debug.Debug)
```

The text is not parsed when the literal is built. Its meaning is decided by the
`decode` callback of `evaluate`, so the same tree can be read as a binary,
decimal or interval value.

### `Literal::new`, `Literal::raw`, `Literal::span`

`Literal::new(raw, span?)` builds a literal; `raw` and `span` read it back.

```mbti
pub fn Literal::new(String, span? : SourceSpan) -> Self
pub fn Literal::raw(Self) -> String
pub fn Literal::span(Self) -> SourceSpan
```

The default span is `SourceSpan::new("")`.

### `Operation`

`Operation` names the operation of an inner node, for example `"add"` or
`"squareroot"`, together with its span.

```mbti
pub struct Operation {
  // private fields
} derive(Eq, @debug.Debug)
```

The package attaches no meaning to the name and does not record an arity. The
`invoke` callback of `evaluate` decides which names exist and how many
arguments each one takes.

### `Operation::new`, `Operation::name`, `Operation::span`

`Operation::new(name, span?)` builds an operation; `name` and `span` read it
back.

```mbti
pub fn Operation::new(String, span? : SourceSpan) -> Self
pub fn Operation::name(Self) -> String
pub fn Operation::span(Self) -> SourceSpan
```

The default span is `SourceSpan::new("")`.

## Expressions

### `Expr`

`Expr` is an immutable expression tree.

```mbti
pub struct Expr {
  // private fields
}
```

The representation is private. Only the two constructors below create
expressions, so every `Expr` has the shape

$$
e \;::=\; \mathsf{lit}(\ell) \;\mid\; \mathsf{op}(o)(e_1, \dots, e_n), \qquad n \ge 0 .
$$

`Expr` has no equality, `Debug` or `Show` implementation; inspect an
expression by evaluating it.

### `Expr::literal`

`Expr::literal(literal)` is the leaf expression for one literal.

```mbti
pub fn Expr::literal(Literal) -> Self
```

### `Expr::invoke`

`Expr::invoke(operation, arguments)` applies `operation` to the argument
expressions, in order.

```mbti
pub fn Expr::invoke(Operation, Array[Self]) -> Self
```

The array is copied into the tree, so later changes to `arguments` do not
change the expression. An empty array is allowed and gives a nullary
operation.

```moonbit
///|
test "build a nested expression" {
  // (2 + 3) * 4
  let sum = @numeric_expr.Expr::invoke(@numeric_expr.Operation::new("add"), [
    @numeric_expr.Expr::literal(@numeric_expr.Literal::new("2")),
    @numeric_expr.Expr::literal(@numeric_expr.Literal::new("3")),
  ])
  let product = @numeric_expr.Expr::invoke(
    @numeric_expr.Operation::new("mul"),
    [sum, @numeric_expr.Expr::literal(@numeric_expr.Literal::new("4"))],
  )
  let result : Result[Int, @numeric_expr.EvalError[String]] = @numeric_expr.evaluate(
    product,
    literal => {
      match literal.raw() {
        "2" => Ok(2)
        "3" => Ok(3)
        "4" => Ok(4)
        _ => Err("bad literal")
      }
    },
    (operation, arguments) => {
      match (operation.name(), arguments) {
        ("add", [a, b]) => Ok(a + b)
        ("mul", [a, b]) => Ok(a * b)
        _ => Err("unknown operation")
      }
    },
  )
  inspect(result is Ok(20), content="true")
}
```

## Evaluation

### `evaluate`

`evaluate(expression, decode, invoke)` computes the value of `expression`
bottom-up with the two callbacks.

```mbti
pub fn[V, E] evaluate(Expr, (Literal) -> Result[V, E], (Operation, Array[V]) -> Result[V, E]) -> Result[V, EvalError[E]]
```

`V` is the value type and `E` the error type of the callbacks. The rules are:

- a literal $\ell$ evaluates to `decode(ℓ)`; an `Err(e)` becomes
  `Err(LiteralFailure(ℓ, e))`;
- an invocation $o(e_1, \dots, e_n)$ first evaluates $e_1, \dots, e_n$ from
  left to right. The first argument that fails ends the evaluation and its
  error is returned unchanged. When all arguments succeed with values
  $v_1, \dots, v_n$, the result is `invoke(o, [v1, ..., vn])`, and an `Err(e)`
  becomes `Err(OperationFailure(o, e))`.

Consequently the callbacks are called in post-order (children left to right,
then the parent), each node at most once, and evaluation stops at the first
failure. On success `decode` runs once per literal leaf and `invoke` once per
invocation node. The package performs no other effect. The recursion depth
equals the height of the tree. The [design page](../design/numeric_expr.md)
proves these properties.

`evaluate` never aborts on its own; any abort comes from the callbacks, or
from stack exhaustion on a very deep tree, since the evaluation is
recursive.

### `EvalError`

`EvalError[E]` tells which node failed and carries the callback's error.

```mbti
pub(all) enum EvalError[E] {
  LiteralFailure(Literal, E)
  OperationFailure(Operation, E)
  UnsupportedExpression(SourceSpan)
}
```

- `LiteralFailure(literal, error)`: `decode(literal)` returned `Err(error)`.
  `literal.span()` locates the operand.
- `OperationFailure(operation, error)`: `invoke` returned `Err(error)` for
  `operation`, after all its arguments evaluated successfully.
- `UnsupportedExpression(span)`: the tree contains a form the evaluator does
  not handle. Trees built with `Expr::literal` and `Expr::invoke` never
  produce it; the constructor is reserved for forms the private
  representation can hold but the public constructors cannot yet build, such
  as variables and binders.

```moonbit
///|
test "evaluation reports the failing node" {
  let span = @numeric_expr.SourceSpan::new("row.txt", line=3, column=7)
  let expression = @numeric_expr.Expr::invoke(
    @numeric_expr.Operation::new("div", span~),
    [
      @numeric_expr.Expr::literal(@numeric_expr.Literal::new("1", span~)),
      @numeric_expr.Expr::literal(@numeric_expr.Literal::new("0", span~)),
    ],
  )
  let result : Result[Int, @numeric_expr.EvalError[String]] = @numeric_expr.evaluate(
    expression,
    literal => if literal.raw() == "1" { Ok(1) } else { Ok(0) },
    (_, arguments) => {
      if arguments[1] == 0 {
        Err("division by zero")
      } else {
        Ok(arguments[0] / arguments[1])
      }
    },
  )
  match result {
    Err(@numeric_expr.OperationFailure(operation, message)) => {
      inspect(operation.name(), content="div")
      inspect(operation.span().line(), content="3")
      inspect(message, content="division by zero")
    }
    _ => fail("expected an operation failure")
  }
}
```

## Trait implementations

### `Literal::equal`, `Literal::not_equal`, `Operation::equal`, `Operation::not_equal`, `SourceSpan::equal`, `SourceSpan::not_equal`

These methods compare all stored components (text or name and span). Use `==`
and `!=` in new code.

```mbti
pub fn Literal::equal(Self, Self) -> Bool
pub fn Literal::not_equal(Self, Self) -> Bool
pub fn Operation::equal(Self, Self) -> Bool
pub fn Operation::not_equal(Self, Self) -> Bool
pub fn SourceSpan::equal(Self, Self) -> Bool
pub fn SourceSpan::not_equal(Self, Self) -> Bool
```

Two literals with the same text but different spans are different.

### `Literal::to_repr`, `Operation::to_repr`, `SourceSpan::to_repr`

These methods render a value for `debug_inspect` and other `Debug` consumers.

```mbti
pub fn Literal::to_repr(Self) -> @debug.Repr
pub fn Operation::to_repr(Self) -> @debug.Repr
pub fn SourceSpan::to_repr(Self) -> @debug.Repr
```

```moonbit
///|
test "syntax nodes compare by text and span" {
  let a = @numeric_expr.Literal::new("1.0")
  let b = @numeric_expr.Literal::new(
    "1.0",
    span=@numeric_expr.SourceSpan::new("x", line=1),
  )
  inspect(a == @numeric_expr.Literal::new("1.0"), content="true")
  inspect(a != b, content="true")
}
```

## Complete public interface

This snapshot is the generated `pkg.generated.mbti` of the package. It is the authority when prose and interface disagree.

<!-- generated-api-start -->
```mbti
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
pub fn Literal::equal(Self, Self) -> Bool
pub fn Literal::new(String, span? : SourceSpan) -> Self
pub fn Literal::not_equal(Self, Self) -> Bool
pub fn Literal::raw(Self) -> String
pub fn Literal::span(Self) -> SourceSpan
pub fn Literal::to_repr(Self) -> @debug.Repr

pub struct Operation {
  // private fields
} derive(Eq, @debug.Debug)
pub fn Operation::equal(Self, Self) -> Bool
pub fn Operation::name(Self) -> String
pub fn Operation::new(String, span? : SourceSpan) -> Self
pub fn Operation::not_equal(Self, Self) -> Bool
pub fn Operation::span(Self) -> SourceSpan
pub fn Operation::to_repr(Self) -> @debug.Repr

pub struct SourceSpan {
  // private fields
} derive(Eq, @debug.Debug)
pub fn SourceSpan::column(Self) -> Int
pub fn SourceSpan::equal(Self, Self) -> Bool
pub fn SourceSpan::line(Self) -> Int
pub fn SourceSpan::new(String, line? : Int, column? : Int) -> Self
pub fn SourceSpan::not_equal(Self, Self) -> Bool
pub fn SourceSpan::source(Self) -> String
pub fn SourceSpan::to_repr(Self) -> @debug.Repr

// Type aliases

// Traits
```
<!-- generated-api-end -->
