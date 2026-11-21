# binary_checked tutorial

This tutorial shows how to write a binary floating-point computation in which
every step that can fail is checked, without unwrapping a `Result` after each
step: you wrap the inputs in `BinaryChecked`, chain operations and operators,
add your own validation with `bind`, and inspect the first error once at the
end. The wrapper delegates all arithmetic to [`binary`](binary.md). The
formal model is in the [design page](../design/binary_checked.md); every
method is listed in the [API reference](../api/binary_checked.md).

| I want to | Use |
| --- | --- |
| start a checked computation from a number | [`BinaryChecked::from_int`, `from_double`, `ok`](#quick-start) |
| write a formula with `+`, `-`, `*`, `/` | [operators on wrappers](#write-formulas-with-operators) |
| add my own validation step | [`BinaryChecked::bind`](#add-your-own-checks-with-bind) |
| round to a given precision or IEEE format | [the `_ctx` methods](#control-precision-and-rounding-with-a-context) |
| tell a domain error from a certification failure | [`ArithmeticError` predicates](#tell-domain-errors-from-certification-failures) |
| feed a generic checked function into a pipeline | [`BinaryChecked::from_result`](#generic-code-over-luna-flowarithmetic-traits) |
| keep the IEEE flags as well | [the `binary` `*_ctx` operations](#keep-ieee-flags-when-they-matter) |

## Quick start

Add the module:

```bash
moon add Luna-Flow/floating@0.11.0
```

Import the wrapper and `binary` in your `moon.pkg` (the examples also use
`Luna-Flow/arithmetic` as `@lf_arith`):

```moonbit nocheck
import {
  "Luna-Flow/floating/binary",
  "Luna-Flow/floating/binary_checked",
  "Luna-Flow/arithmetic" @lf_arith,
}
```

Compute $\sqrt{81} / 3$ at 48 bits and read the result:

```moonbit
///|
test "quick start: a checked pipeline" {
  let value = @binary_checked.BinaryChecked::from_int(81, precision=48)
    .sqrt()
    .div(@binary_checked.BinaryChecked::from_int(3, precision=48))
  match value.result() {
    Ok(x) => inspect(x.to_string(), content="3p0")
    Err(e) => fail(e.message)
  }
}
```

`to_string` prints the exact binary value: `3p0` is $3 \cdot 2^0$.

## Everyday tasks

The remaining examples print results with this helper:

```moonbit
///|
fn show(r : @binary_checked.BinaryChecked) -> String {
  match r.result() {
    Ok(v) => v.to_string()
    Err(e) => "error: " + e.message
  }
}
```

### Write formulas with operators

`+`, `-`, `*`, `/` and unary `-` work on wrappers. The first failing step
decides the result; later steps do not run on an error:

```moonbit
///|
fn harmonic_mean(
  a : @binary_checked.BinaryChecked,
  b : @binary_checked.BinaryChecked,
) -> @binary_checked.BinaryChecked {
  let one = @binary_checked.BinaryChecked::from_int(1)
  let two = @binary_checked.BinaryChecked::from_int(2)
  two / (one / a + one / b)
}

///|
test "harmonic mean with a checked division" {
  let r = fn(n : Int) { @binary_checked.BinaryChecked::from_int(n) }
  inspect(show(harmonic_mean(r(2), r(6))), content="3p0")
  inspect(show(harmonic_mean(r(2), r(0))), content="error: div: division by zero")
}
```

On plain `Binary` values the second call would silently produce a number
($1/0 = \infty$ and $2/\infty = 0$); the wrapper reports where the
computation left the real numbers.

### Add your own checks with `bind`

`map` applies a function that cannot fail; `bind` applies one that returns a
`BinaryChecked` and may fail. Use `bind` to put an application rule into the
pipeline:

```moonbit
///|
fn require_probability(x : @binary.Binary) -> @binary_checked.BinaryChecked {
  let in_range = x.compare(@binary.Binary::zero()) >= 0 &&
    x.compare(@binary.Binary::from_int(1)) <= 0
  if in_range {
    @binary_checked.BinaryChecked::ok(x)
  } else {
    @binary_checked.BinaryChecked::err(
      @lf_arith.ArithmeticError::domain_error("not a probability"),
    )
  }
}

///|
test "entropy term with a domain check" {
  let term = fn(p : Double) {
    let x = @binary_checked.BinaryChecked::from_double(p).bind(require_probability)
    -(x * x.log2())
  }
  inspect(show(term(0.5)), content="1p-1")
  inspect(show(term(1.5)), content="error: not a probability")
}
```

### Control precision and rounding with a context

Every elementary function has a `_ctx` form that takes a `BinaryContext`. The
plain form rounds to nearest at the operand's own precision; the context form
rounds to the context:

```moonbit
///|
test "the same logarithm at two precisions" {
  let two = @binary_checked.BinaryChecked::from_int(2)
  inspect(show(two.ln()), content="6243314768165359p-53")
  let single = @binary.BinaryContext::binary32()
  inspect(show(two.ln_ctx(single)), content="1453635p-21")
  let down = @binary.BinaryContext::new(
    precision=24,
    rounding=@binary.BinaryRoundingMode::RoundTowardNegative,
  )
  inspect(show(two.ln_ctx(down)), content="11629079p-24")
}
```

### Tell domain errors from certification failures

Errors are `ArithmeticError` values from Luna-Flow/arithmetic. Their kind says
whether the input was outside the function's domain or the library could not
certify a correctly rounded result:

```moonbit
///|
fn classify_error(r : @binary_checked.BinaryChecked) -> String {
  match r.result() {
    Ok(_) => "ok"
    Err(e) if e.is_domain_error() => "domain"
    Err(e) if e.is_division_by_zero() => "division by zero"
    Err(_) => "other"
  }
}

///|
test "error kinds" {
  let r = fn(n : Int) { @binary_checked.BinaryChecked::from_int(n) }
  inspect(classify_error(r(-1).sqrt()), content="domain")
  inspect(classify_error(r(1) / r(0)), content="division by zero")
  inspect(classify_error(r(2).sqrt()), content="ok")
}
```

## Going further

### Generic code over Luna-Flow/arithmetic traits

`Binary` implements the checked traits of Luna-Flow/arithmetic
(`SqrtChecked`, `DivChecked`, `PowIntChecked`, `PowNatChecked`). A function
written against those traits returns `Result[T, ArithmeticError]`, and
`from_result` brings it into a pipeline:

```moonbit
///|
fn[T : @lf_arith.SqrtChecked + @lf_arith.DivChecked] ratio_root(
  a : T,
  b : T,
  ctx : @lf_arith.ArithmeticContext,
) -> Result[T, @lf_arith.ArithmeticError] {
  match @lf_arith.DivChecked::div_checked(a, b, ctx) {
    Ok(q) => @lf_arith.SqrtChecked::sqrt_checked(q, ctx)
    Err(e) => Err(e)
  }
}

///|
test "a generic checked function feeds the pipeline" {
  let ctx = @lf_arith.ArithmeticContext::new(53)
  let r = @binary_checked.BinaryChecked::from_result(
    ratio_root(@binary.Binary::from_int(18), @binary.Binary::from_int(2), ctx),
  )
  inspect(show(r + @binary_checked.BinaryChecked::from_int(1)), content="1p2")
  let bad = @binary_checked.BinaryChecked::from_result(
    ratio_root(@binary.Binary::from_int(1), @binary.Binary::zero(), ctx),
  )
  inspect(show(bad), content="error: division by zero")
}
```

### Keep IEEE flags when they matter

The wrapper stores a value or an error, nothing else. When the inexact,
overflow or underflow flags are part of your contract, call the
`Binary::*_ctx` operations, which return `(value, BinaryFlags)`, and combine
the flags yourself:

```moonbit
///|
test "carry flags next to the wrapper" {
  let ctx = @binary.BinaryContext::binary64()
  let (third, f1) = @binary.Binary::from_int(1).div_ctx(
    @binary.Binary::from_int(3),
    ctx,
  )
  let (sum, f2) = third.add_ctx(third, ctx)
  let flags = f1.combine(f2)
  inspect(flags.inexact(), content="true")
  inspect(show(@binary_checked.BinaryChecked::ok(sum)), content="6004799503160661p-53")
}
```

## Common pitfalls

- **A quiet NaN is a success.** `BinaryChecked` reports an invalid operation
  ($\infty - \infty$, `sqrt_ctx` of a negative number, a signaling NaN) as
  `DomainError` and a division by zero as `DivisionByZero`, with or without a
  context. A quiet NaN operand is not an exception and stays a successful NaN;
  test `@def.is_nan` on the final value if that matters.
- **`x` and `x_ctx` have one error contract.** `x_ctx` is `x` with an explicit
  context; `div_ctx` by zero fails like `div`. Overflow, underflow and inexact
  are not errors in either form.
- **Only the first error survives.** In `a + b` with both operands failing,
  the error of `a` is reported. Errors are not collected.
- **The `_ctx` methods drop the range flags.** Overflow, underflow and inexact
  are dropped; use `binary` directly for flags and for the raw default
  result of an invalid operation or a division by zero.
- **Precision of mixed operands.** Binary operations use the larger operand
  precision; `from_float` defaults to 24 bits, so mixing it with
  `from_double` values gives 53-bit results.
- **Operands are always evaluated.** The wrapper skips the *operation* after
  an error, but MoonBit evaluates every argument first, so in `a + f(b)` the
  call `f(b)` runs even when `a` is an error. Put expensive steps behind
  `bind` when they should be skipped.

## Next steps

- [`binary_checked` design](../design/binary_checked.md): the error monad,
  its laws and the first-error theorem.
- [`binary_checked` API](../api/binary_checked.md): every method.
- [`binary` tutorial](binary.md): contexts, flags and interchange formats.
- [`interval_checked` tutorial](interval_checked.md): the same pipeline for
  enclosures.
