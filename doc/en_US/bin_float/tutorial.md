# `bin_float` Tutorial

This page tracks the current repository implementation and is written as the `0.1.0` tutorial baseline.

## Creating Dyadic Values

`BinFloat` is the best fit when the value you want is naturally expressed in binary form.

```moonbit
let x = @bin_float.BinFloat::make(3N, -1, 32) // 3 * 2^-1 = 1.5
let y = @bin_float.BinFloat::make(5N, -1, 32) // 2.5
let sum = x + y
inspect(sum.to_string(), content="1p2")
```

The displayed `1p2` form means `1 * 2^2`.

## Understanding Normalization

Finite values are normalized automatically. For example:

```moonbit
let raw = @bin_float.BinFloat::make(12N, 0, 32)
inspect(raw.significand().to_string(), content="3")
inspect(raw.exponent2().to_string(), content="2")
```

The stored value is canonicalized from `12 * 2^0` into `3 * 2^2`.

## Retuning Precision

Each value stores a working precision.

```moonbit
let x = @bin_float.BinFloat::make(7N, -2, 32)
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

## Comparison and Special Values

Finite values can be compared with `compare`. Do not call `compare` on `nan`.

```moonbit
let a = @bin_float.BinFloat::from_int(3, precision=16)
let b = @bin_float.BinFloat::from_int(5, precision=16)
inspect(a.compare(b).to_string(), content="-1")
```

Use `classify()` when special values may be present.
