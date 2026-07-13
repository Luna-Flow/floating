# `ball_float` Tutorial

This page tracks the `0.6.0` behavior.

## Exact Embedding

The simplest way to create a ball is to embed a `BinFloat` exactly.

```moonbit
let x = @bin_float.BinFloat::make(
  @bin_float.BinCoeff::from_uint64(3UL),
  -1,
  32,
)
let ball = @ball_float.BallFloat::exact(x)
inspect(ball.to_string(), content="3p-1 +/- 0")
```

This creates a zero-radius enclosure.

If you request a lower precision than the source value can represent exactly, `exact` widens the radius instead of silently dropping containment.

## Approximate Decimal Embedding

```moonbit
let d = @decimal.Decimal::from_string("12.34", precision=32).unwrap()
let ball = @ball_float.BallFloat::exact(d.to_bin_float(precision=32))
```

This path converts through `BinFloat` and preserves the decimal value as an enclosure rather than pretending the binary center is exact.

## Reading Relations

```moonbit
let a = @ball_float.BallFloat::new(
  @bin_float.BinFloat::from_int(10, precision=16),
  @bin_float.BinFloat::from_int(1, precision=16),
)
let b = @ball_float.BallFloat::new(
  @bin_float.BinFloat::from_int(15, precision=16),
  @bin_float.BinFloat::from_int(1, precision=16),
)
inspect(a.separated_from(b).to_string(), content="true")
inspect(a.definitely_lt(b).to_string(), content="true")
```

Use:

- `contains` for point inclusion
- `overlaps` for enclosure overlap
- `definitely_lt` / `definitely_gt` for order statements that are actually provable

## Ball Arithmetic

```moonbit
let c = a + b
let p = a * b
```

The returned balls are intended to enclose the result rather than to behave like exact scalar arithmetic with a hidden uncertainty tag.

That includes the rounding performed on the returned center: any center displacement introduced by precision reduction is folded back into the radius.
