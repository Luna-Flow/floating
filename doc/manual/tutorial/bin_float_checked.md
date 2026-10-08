# `bin_float_checked` tutorial

This tutorial shows how to write a binary floating-point computation in which
every step that can fail is checked, without unwrapping a `Result` after each
step: you wrap the inputs in `BinFloatResult`, chain operations and operators,
add your own validation with `bind`, and inspect the first error once at the
end. The wrapper delegates all arithmetic to [`bin_float`](bin_float.md). The
formal model is in the [design page](../design/bin_float_checked.md); every
method is listed in the [API reference](../api/bin_float_checked.md).

## Quick start

```sh
moon add Luna-Flow/floating@0.8.0
```

```text
import {
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/bin_float_checked",
}
```

Compute $\sqrt{81} / 3$ at 48 bits and read the result:

```moonbit
///|
test "quick start: a checked pipeline" {
  let value = @bin_float_checked.BinFloatResult::from_int(81, precision=48)
    .sqrt()
    .div(@bin_float_checked.BinFloatResult::from_int(3, precision=48))
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
fn show(r : @bin_float_checked.BinFloatResult) -> String {
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
  a : @bin_float_checked.BinFloatResult,
  b : @bin_float_checked.BinFloatResult,
) -> @bin_float_checked.BinFloatResult {
  let one = @bin_float_checked.BinFloatResult::from_int(1)
  let two = @bin_float_checked.BinFloatResult::from_int(2)
  two / (one / a + one / b)
}

///|
test "harmonic mean with a checked division" {
  let r = fn(n : Int) { @bin_float_checked.BinFloatResult::from_int(n) }
  inspect(show(harmonic_mean(r(2), r(6))), content="3p0")
  inspect(show(harmonic_mean(r(2), r(0))), content="error: division by zero")
}
```

On plain `BinFloat` values the second call would silently produce a number
($1/0 = \infty$ and $2/\infty = 0$); the wrapper reports where the
computation left the real numbers.

### Add your own checks with `bind`

`map` applies a function that cannot fail; `bind` applies one that returns a
`BinFloatResult` and may fail. Use `bind` to put an application rule into the
pipeline:

```moonbit
///|
fn require_probability(x : @bin_float.BinFloat) -> @bin_float_checked.BinFloatResult {
  let in_range = x.compare(@bin_float.BinFloat::zero()) >= 0 &&
    x.compare(@bin_float.BinFloat::from_int(1)) <= 0
  if in_range {
    @bin_float_checked.BinFloatResult::ok(x)
  } else {
    @bin_float_checked.BinFloatResult::err(
      @lf_arith.ArithmeticError::domain_error("not a probability"),
    )
  }
}

///|
test "entropy term with a domain check" {
  let term = fn(p : Double) {
    let x = @bin_float_checked.BinFloatResult::from_double(p).bind(require_probability)
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
  let two = @bin_float_checked.BinFloatResult::from_int(2)
  inspect(show(two.ln()), content="6243314768165359p-53")
  let single = @bin_float.BinaryContext::binary32()
  inspect(show(two.ln_ctx(single)), content="1453635p-21")
  let down = @bin_float.BinaryContext::unbounded(
    24,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
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
fn classify_error(r : @bin_float_checked.BinFloatResult) -> String {
  match r.result() {
    Ok(_) => "ok"
    Err(e) if e.is_domain_error() => "domain"
    Err(e) if e.is_certification_failure() => "certification"
    Err(e) if e.is_division_by_zero() => "division by zero"
    Err(_) => "other"
  }
}

///|
test "error kinds" {
  let r = fn(n : Int) { @bin_float_checked.BinFloatResult::from_int(n) }
  inspect(classify_error(r(-1).sqrt()), content="domain")
  inspect(classify_error(r(3).exp_ln()), content="certification")
  inspect(classify_error(r(1) / r(0)), content="division by zero")
  inspect(classify_error(r(2).sqrt()), content="ok")
}
```

`exp_ln` (the fused $\ln(\exp x)$) is certified only for $|x| \le 1/8$, so it
fails for $3$; this is a certification limit, not a mathematical domain.

## Going further

### Generic code over Luna-Flow/arithmetic traits

`BinFloat` implements the checked traits of Luna-Flow/arithmetic
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
  let r = @bin_float_checked.BinFloatResult::from_result(
    ratio_root(@bin_float.BinFloat::from_int(18), @bin_float.BinFloat::from_int(2), ctx),
  )
  inspect(show(r + @bin_float_checked.BinFloatResult::from_int(1)), content="1p2")
  let bad = @bin_float_checked.BinFloatResult::from_result(
    ratio_root(@bin_float.BinFloat::from_int(1), @bin_float.BinFloat::zero(), ctx),
  )
  inspect(show(bad), content="error: division by zero")
}
```

### Keep IEEE flags when they matter

The wrapper stores a value or an error, nothing else. When the inexact,
overflow or underflow flags are part of your contract, call the
`BinFloat::*_ctx` operations, which return `(value, BinaryFlags)`, and combine
the flags yourself:

```moonbit
///|
test "carry flags next to the wrapper" {
  let ctx = @bin_float.BinaryContext::binary64()
  let (third, f1) = @bin_float.BinFloat::from_int(1).div_ctx(
    @bin_float.BinFloat::from_int(3),
    ctx,
  )
  let (sum, f2) = third.add_ctx(third, ctx)
  let flags = f1.combine(f2)
  inspect(flags.inexact(), content="true")
  inspect(show(@bin_float_checked.BinFloatResult::ok(sum)), content="6004799503160661p-53")
}
```

## Common pitfalls

- **NaN is a success.** `BinFloatResult` reports what `bin_float` reports as an
  error. Operations that IEEE defines with a NaN or infinite result
  ($\infty - \infty$, `sqrt_ctx` of a negative number, `div_ctx` by zero) are
  successful values. Test `@def.is_nan` on the final value if that matters.
- **`div` and `div_ctx` differ.** `div` (and `/`) fails on a zero divisor;
  `div_ctx` returns an infinity. The same holds for `pow_int` versus
  `pow_int_ctx` and `sqrt` versus `sqrt_ctx`.
- **Only the first error survives.** In `a + b` with both operands failing,
  the error of `a` is reported. Errors are not collected.
- **The `_ctx` methods drop flags.** Use `bin_float` directly for flags.
- **Precision of mixed operands.** Binary operations use the larger operand
  precision; `from_float` defaults to 24 bits, so mixing it with
  `from_double` values gives 53-bit results.
- **`flat_map` is deprecated.** Use `bind`.

## Next steps

- [`bin_float_checked` design](../design/bin_float_checked.md): the error monad,
  its laws and the first-error theorem.
- [`bin_float_checked` API](../api/bin_float_checked.md): every method.
- [`bin_float` tutorial](bin_float.md): contexts, flags and interchange formats.
- [`ball_float_checked` tutorial](ball_float_checked.md): the same pipeline for
  enclosures.
