# Executable documentation examples

This test-only package is the canonical executable source for the public
numeric workflows shown in the localized tutorials.

```moonbit check
///|
test "binary context and interchange" {
  let value = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(3UL),
    -1,
    53,
  )
  let context = @bin_float.BinaryContext::binary64()
  let (rounded, flags) = value.add_ctx(value, context)
  inspect(rounded.to_hex(), content="0x3p0")
  inspect(flags.inexact(), content="false")
  let (encoded, _) = rounded.to_interchange(@bin_float.Binary64)
  inspect(encoded.to_hex(), content="4008000000000000")
}
```

```moonbit check
///|
test "decimal context preserves explicit status" {
  let context = @decimal.DecimalContext::decimal64()
  let (value, parse_flags) = @decimal.Decimal::from_string_ctx(
    "12.3400", context,
  )
  let (result, arithmetic_flags) = value.div_ctx(
    @decimal.Decimal::from_int(2),
    context,
  )
  inspect(parse_flags.has_error(), content="false")
  inspect(arithmetic_flags.has_error(), content="false")
  inspect(result.to_string(), content="6.1700")
}
```

```moonbit check
///|
test "interval and decorated semantics" {
  let interval = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(1),
    @bin_float.BinFloat::from_int(2),
  )
  inspect(interval.contains(@bin_float.BinFloat::from_int(1)), content="true")
  let decorated = @ball_float.BallFloatDecorated::new(interval)
  inspect(decorated.is_nai(), content="false")
}
```

```moonbit check
///|
test "checked pipelines preserve the first error" {
  let binary = @bin_float_checked.BinFloatResult::from_int(9).sqrt()
  inspect(binary.result().unwrap().to_string(), content="3p0")
  let decimal = @decimal_checked.DecimalResult::parse("9").sqrt()
  inspect(decimal.result().unwrap().to_string(), content="3")
  let interval = @ball_float_checked.BallFloatResult::from_int(4).pow_int(-1)
  inspect(interval.result() is Ok(_), content="true")
}
```
