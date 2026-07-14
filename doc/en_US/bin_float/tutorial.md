# `bin_float` Tutorial

This page tracks the `0.6.1` implementation. Read
[Conformance](./conformance.md) before treating a contextual result as an IEEE
interchange operation.

## Creating Dyadic Values

`BinFloat` is the best fit when the value you want is naturally expressed in binary form.

```moonbit
let x = @bin_float.BinFloat::make(
  @bin_float.BinCoeff::from_uint64(3UL),
  -1,
  32,
) // 3 * 2^-1 = 1.5
let y = @bin_float.BinFloat::make(
  @bin_float.BinCoeff::from_uint64(5UL),
  -1,
  32,
) // 2.5
let sum = x + y
inspect(sum.to_string(), content="1p2")
```

The displayed `1p2` form means `1 * 2^2`.

## Understanding Normalization

Finite values are normalized automatically. For example:

```moonbit
let raw = @bin_float.BinFloat::make(
  @bin_float.BinCoeff::from_uint64(12UL),
  0,
  32,
)
inspect(raw.coefficient().to_string(), content="3")
inspect(raw.exponent2().to_string(), content="2")
```

The stored value is canonicalized from `12 * 2^0` into `3 * 2^2`.

## Contextual IEEE Arithmetic

Use a `BinaryContext` when format bounds and status flags matter. Decode
interchange bits rather than routing binary16/32/64/128 through host floats.

```moonbit
let format = @bin_float.BinaryInterchangeFormat::Binary16
let context = @bin_float.BinaryContext::binary16(
  rounding=@bin_float.BinaryRoundingMode::RoundTiesToEven,
  tininess=@bin_float.TininessDetection::AfterRounding,
)
let x = @bin_float.BinaryInterchange::from_hex("3C00", format).unwrap().to_bin_float()
let y = @bin_float.BinaryInterchange::from_hex("4000", format).unwrap().to_bin_float()
let (sum, flags) = x.add_ctx(y, context)
let (bits, encoding_flags) = sum.to_interchange(format)
inspect(bits.to_hex(), content="4200")
inspect(flags.combine(encoding_flags).to_testfloat_bits(), content="0")
```

`add_ctx`, `sub_ctx`, `mul_ctx`, `div_ctx`, and `sqrt_ctx` round the exact real
operation once under the supplied context and return IEEE status flags.

## Retuning Precision

Each value stores a working precision.

```moonbit
let x = @bin_float.BinFloat::make(
  @bin_float.BinCoeff::from_uint64(7UL),
  -2,
  32,
)
let short = x.with_precision(4, @def.RoundingMode::ToNearestEven)
```

Use `with_precision` when you want an explicitly rounded representation.

## Measuring Spacing with `ulp`

`ulp()` gives a spacing-style value for the current finite representation.

```moonbit
let x = @bin_float.BinFloat::from_int(8, precision=16)
let step = x.ulp()
```

This is useful when reasoning about representational granularity rather than exact-real error bounds.

## Signed Zero And NaNs

`negative_zero`, `quiet_nan`, and `signaling_nan` are explicit constructors.
Use `is_negative_zero`, `is_quiet_nan`, `is_signaling_nan`, and `nan_payload`
when the representation state is observable. Do not use ordinary comparison to
order NaNs.

## Comparison and Special Values

Finite values can be compared with `compare`. Do not call `compare` on `nan`.

```moonbit
let a = @bin_float.BinFloat::from_int(3, precision=16)
let b = @bin_float.BinFloat::from_int(5, precision=16)
inspect(a.compare(b).to_string(), content="-1")
```

Use `classify()` when special values may be present.

## Context Status

When flags are part of the result, keep the `(value, BinaryFlags)` pair through the operation boundary.
