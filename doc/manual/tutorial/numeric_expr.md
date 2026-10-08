# numeric_expr tutorial

The goal of this tutorial is to describe a computation once as a
`numeric_expr` tree and run it against any number type by supplying two
callbacks: one that reads a literal and one that executes an operation. By the
end you can evaluate expressions over `Int`, over `BinFloat` with IEEE flags,
and report failures at their source line. This is the mechanism the GDA
conformance frontend `frontend/gda_expr` uses to run `.decTest` corpora.

| I want to | Use |
| --- | --- |
| build an expression tree | [`Expr::literal`, `Expr::invoke`](#quick-start) |
| give operations a meaning | [the `invoke` callback](#write-a-small-interpreter) |
| evaluate over a floating-point type with flags | [a pair value type](#evaluate-over-binfloat-and-collect-ieee-flags) |
| report a failure at its source line | [`SourceSpan`, `EvalError`](#report-errors-at-their-source) |
| know which callbacks run, and in which order | [post-order evaluation](#see-the-evaluation-order) |
| keep domain errors as values | [checked value types](#going-further) |

## Quick start

```bash
moon add Luna-Flow/floating@0.8.0
```

Add the package to `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/numeric_expr",
}
```

Build `1 + 2` and evaluate it over `Int`:

```moonbit
///|
test "quick start" {
  let one_plus_two = @numeric_expr.Expr::invoke(
    @numeric_expr.Operation::new("add"),
    [
      @numeric_expr.Expr::literal(@numeric_expr.Literal::new("1")),
      @numeric_expr.Expr::literal(@numeric_expr.Literal::new("2")),
    ],
  )
  let result : Result[Int, @numeric_expr.EvalError[String]] = @numeric_expr.evaluate(
    one_plus_two,
    literal => if literal.raw() == "1" { Ok(1) } else { Ok(2) },
    (_, arguments) => Ok(arguments[0] + arguments[1]),
  )
  inspect(result is Ok(3), content="true")
}
```

`evaluate` decodes both literals, then calls the operation callback with the
decoded arguments `[1, 2]`.

## Everyday tasks

### Write a small interpreter

Most callers match on the operation name and the argument array. Matching the
array pattern also checks the arity, which `numeric_expr` itself does not do:

```moonbit
///|
fn int_literal(literal : @numeric_expr.Literal) -> Result[Int, String] {
  match literal.raw() {
    "0" => Ok(0)
    "1" => Ok(1)
    "2" => Ok(2)
    "3" => Ok(3)
    "10" => Ok(10)
    other => Err("not a small integer: " + other)
  }
}

///|
fn int_operation(
  operation : @numeric_expr.Operation,
  arguments : Array[Int],
) -> Result[Int, String] {
  match (operation.name(), arguments) {
    ("add", [a, b]) => Ok(a + b)
    ("mul", [a, b]) => Ok(a * b)
    ("neg", [a]) => Ok(-a)
    ("sum", values) => Ok(values.fold(init=0, (acc, x) => acc + x))
    (name, values) =>
      Err(name + " does not take " + values.length().to_string() + " arguments")
  }
}

///|
fn lit(raw : String) -> @numeric_expr.Expr {
  @numeric_expr.Expr::literal(@numeric_expr.Literal::new(raw))
}

///|
fn call(name : String, arguments : Array[@numeric_expr.Expr]) -> @numeric_expr.Expr {
  @numeric_expr.Expr::invoke(@numeric_expr.Operation::new(name), arguments)
}

///|
test "small interpreter" {
  // -(2 * 3) + sum(1, 2, 3, 10)
  let expression = call("add", [
    call("neg", [call("mul", [lit("2"), lit("3")])]),
    call("sum", [lit("1"), lit("2"), lit("3"), lit("10")]),
  ])
  let result = @numeric_expr.evaluate(expression, int_literal, int_operation)
  inspect(result is Ok(10), content="true")
}
```

`sum` shows that an operation may take any number of arguments; the callback
decides.

### Evaluate over `BinFloat` and collect IEEE flags

The value type `V` can carry more than a number. Here every value is a
`BinFloat` together with the IEEE flags raised so far, and each operation merges
the flags of its arguments with its own:

```moonbit
///|
fn binary_literal(
  literal : @numeric_expr.Literal,
) -> Result[(@bin_float.BinFloat, @bin_float.BinaryFlags), String] {
  match
    @bin_float.BinFloat::from_string_ctx(
      literal.raw(),
      @bin_float.BinaryContext::binary64(),
    ) {
    Ok(pair) => Ok(pair)
    Err(_) => Err("not a number: " + literal.raw())
  }
}

///|
fn binary_operation(
  operation : @numeric_expr.Operation,
  arguments : Array[(@bin_float.BinFloat, @bin_float.BinaryFlags)],
) -> Result[(@bin_float.BinFloat, @bin_float.BinaryFlags), String] {
  let context = @bin_float.BinaryContext::binary64()
  match (operation.name(), arguments) {
    ("add", [(a, fa), (b, fb)]) => {
      let (value, flags) = a.add_ctx(b, context)
      Ok((value, fa.combine(fb).combine(flags)))
    }
    ("div", [(a, fa), (b, fb)]) => {
      let (value, flags) = a.div_ctx(b, context)
      Ok((value, fa.combine(fb).combine(flags)))
    }
    _ => Err("unsupported " + operation.name())
  }
}

///|
test "binary64 evaluation with flags" {
  // 1/3 + 1/3 in binary64
  let third = call("div", [lit("1"), lit("3")])
  let result = @numeric_expr.evaluate(
    call("add", [third, third]),
    binary_literal,
    binary_operation,
  )
  match result {
    Ok((value, flags)) => {
      inspect(value.to_hex(), content="0x15555555555555p-53")
      inspect(flags.inexact(), content="true")
    }
    Err(_) => fail("expected a value")
  }
}
```

The same tree could be evaluated over `@decimal_gda.Decimal` by swapping the two
callbacks; nothing in the expression depends on the number type.

### Report errors at their source

Give every node the span of the text it came from. When a callback fails, the
`EvalError` returns the failing node, so the span locates the error:

```moonbit
///|
test "locate a bad operand" {
  let span = @numeric_expr.SourceSpan::new("rows.txt", line=42, column=9)
  let expression = @numeric_expr.Expr::invoke(
    @numeric_expr.Operation::new("add", span~),
    [
      @numeric_expr.Expr::literal(@numeric_expr.Literal::new("2", span~)),
      @numeric_expr.Expr::literal(@numeric_expr.Literal::new("two", span~)),
    ],
  )
  let message = match
    @numeric_expr.evaluate(expression, int_literal, int_operation) {
    Ok(_) => "ok"
    Err(@numeric_expr.LiteralFailure(literal, error)) =>
      literal.span().source() +
      ":" +
      literal.span().line().to_string() +
      ": " +
      error
    Err(@numeric_expr.OperationFailure(operation, error)) =>
      operation.name() + ": " + error
    Err(@numeric_expr.UnsupportedExpression(_)) => "unsupported"
  }
  inspect(message, content="rows.txt:42: not a small integer: two")
}
```

### See the evaluation order

The callbacks run in post-order, left to right, and evaluation stops at the
first failure. A trace makes this visible:

```moonbit
///|
test "post-order with early stop" {
  let trace : Array[String] = []
  let expression = call("add", [
    call("mul", [lit("2"), lit("3")]),
    call("add", [lit("bad"), lit("1")]),
  ])
  let _ = @numeric_expr.evaluate(
    expression,
    literal => {
      trace.push(literal.raw())
      int_literal(literal)
    },
    (operation, arguments) => {
      trace.push(operation.name())
      int_operation(operation, arguments)
    },
  )
  inspect(trace.join(" "), content="2 3 mul bad")
}
```

The literal `1` and both `add` nodes are never visited, because `bad` fails
first.

## Going further

- **Corpus frontends.** `frontend/gda_expr` lowers each `.decTest` row
  `id operation operands -> expected conditions` into
  `Expr::invoke(Operation::new(op), operands.map(Expr::literal))` and evaluates
  it with callbacks over `@decimal_gda`. Read
  [gda_expr](frontend/gda_expr.md) for a complete example of the pattern.
- **Richer values.** `V` can be an enum when operations return different kinds
  of results (numbers, booleans, strings), as `gda_expr` does for `compare`,
  `class` and `isnan`.
- **Typed errors.** `E` can be your own enum instead of `String`; `EvalError[E]`
  keeps it unchanged.
- **Checked pipelines.** If you want domain errors to stay values instead of
  stopping the evaluation, make `V` a checked type such as
  `@bin_float_checked.BinFloatResult` and let the callbacks always return `Ok`.

## Common pitfalls

- **No arity check.** `Expr::invoke` accepts any number of arguments. Check the
  arity in `invoke` (an array pattern does it) and return `Err` on a mismatch.
- **Early stop.** After the first failure no further callback runs. Do not rely
  on side effects of callbacks for nodes to the right of a failing node.
- **Deep trees.** Evaluation is recursive; the stack depth equals the tree
  height. Very deep left-leaning trees (for example a sum of a million terms
  built as nested `add`) can exhaust the stack; build a flat `sum` node instead.
- **Default spans.** Without an explicit span a node reports
  `SourceSpan::new("")`, whose line and column are `0`.
- **No literal parsing here.** A `Literal` stores raw text. Rounding, precision
  and flags of the conversion are decided entirely by your `decode` callback.

## Next steps

- [numeric_expr API](../api/numeric_expr.md) lists every item.
- [numeric_expr design](../design/numeric_expr.md) states the evaluation
  semantics and its invariants.
- [gda_expr tutorial](frontend/gda_expr.md) runs real decimal test
  rows through this package.
