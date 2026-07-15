# `bin_float_checked` Tutorial

`BinFloatResult` keeps `Result[BinFloat, ArithmeticError]` inside a fluent
pipeline. Use it when the first checked construction or arithmetic failure
should stop every later step. It is not an IEEE flag accumulator.

## Build A Pipeline

```moonbit check
///|
test "checked binary pipeline" {
  let value =
    @bin_float_checked.BinFloatResult::from_int(81, precision=48)
    .sqrt()
    .div(@bin_float_checked.BinFloatResult::from_int(3, precision=48))
  inspect(value.result().unwrap().to_string(), content="3p0")
}
```

Keep the wrapper until the application boundary. Call `result()` once the
caller is ready to handle `ArithmeticError`; use `is_ok`, `is_err`, or
`error()` for branch decisions without extracting the value.

## Understand First-Error Short-Circuiting

Every transformation on an error is the identity. In a binary method, the left
error wins before the right is evaluated as a numerical operand. This makes the
pipeline deterministic but intentionally does not collect multiple errors.

Use `map` for an infallible `BinFloat -> BinFloat` transformation. Use `bind`
when the callback may return another `BinFloatResult`. `flat_map` is a
deprecated alias; new code should use `bind`.

```moonbit nocheck
let normalized = checked.map(value => value.normalized())
let validated = normalized.bind(value => {
  if value.is_finite() {
    @bin_float_checked.BinFloatResult::ok(value)
  } else {
    @bin_float_checked.BinFloatResult::err(application_error)
  }
})
```

## Contextual Operations Do Not Retain Flags

Methods such as `add_ctx` and `exp_ctx` retain certification/arithmetic failure
in the wrapper, but `BinFloatResult` stores only the resulting value or error.
If IEEE `BinaryFlags` are part of the contract, call the underlying
`BinFloat::*_ctx` API and carry `(value, flags)` explicitly.

## Recommended Practice

1. Use the wrapper for first-error pipelines, not for status accumulation.
2. Keep all operands wrapped when using binary combinators.
3. Extract once at an application boundary rather than repeatedly unwrapping.
4. Use raw `bin_float` context APIs when rounding flags or interchange bits are
   required.

See [Design](./design.md) for the state model and
[`bin_float` tutorial](../bin_float/tutorial.md) for contexts and flags.
