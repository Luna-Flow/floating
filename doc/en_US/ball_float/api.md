# @ball_float.BallFloat

This page tracks the current repository implementation and is written as the `0.1.0` API baseline.

---

## `pub struct BallFloat`

```moonbit
struct BallFloat {
  center_ : @bin_float.BinFloat
  radius_ : @bin_float.BinFloat
  precision_ : Int
} derive(Eq)
```

- **Description**
  Represents a ball arithmetic value with the meaning `center +/- radius`.

### Semantic Notes

- `radius` is always required to be finite and non-negative.
- `center` is required to be finite.
- `BallFloat` uses enclosure semantics rather than exact-real value semantics.
- The current implementation stores both center and radius as `BinFloat`.

## Construction

- **`fn BallFloat::new(center : @bin_float.BinFloat, radius : @bin_float.BinFloat, precision? : Int = Int::max(center.precision(), radius.precision())) -> BallFloat`**
  Validates and stores a ball value.

- **`fn BallFloat::exact(x : @bin_float.BinFloat, precision? : Int = x.precision()) -> BallFloat`**
  Embeds a binary float as a zero-radius ball.

- **`fn BallFloat::from_decimal(x : @decimal.Decimal, precision? : Int = x.precision()) -> BallFloat`**
  Converts a decimal value into an enclosure-oriented ball.

### Notes

- `new` aborts if the center is non-finite, or if the radius is negative or non-finite.
- Center quantization widens the stored radius by the induced center displacement so the enclosure does not shrink during precision reduction.
- Radius quantization is rounded outward.
- `from_decimal` is not an "exact decimal object wrapper"; it builds a `BinFloat`-based enclosure around the decimal value.

## Accessors and Shared Floating Operations

- **`fn center(self : BallFloat) -> @bin_float.BinFloat`**
- **`fn radius(self : BallFloat) -> @bin_float.BinFloat`**
- **`fn precision(self : BallFloat) -> Int`**
- **`fn classify(self : BallFloat) -> FpClass`**
- **`fn sign(self : BallFloat) -> Sign`**
- **`fn normalized(self : BallFloat) -> BallFloat`**
- **`fn with_precision(self : BallFloat, precision : Int, mode : RoundingMode) -> BallFloat`**

### Sign Notes

- If the radius is zero, `sign()` matches the center sign.
- If the enclosure spans negative and positive values, the current implementation returns `Sign::Zero`.
- `with_precision` preserves containment of the original stored enclosure by widening the radius when center retuning moves the center.

## Enclosure Relations

- **`fn contains(self : BallFloat, x : @bin_float.BinFloat) -> Bool`**
- **`fn overlaps(self : BallFloat, other : BallFloat) -> Bool`**
- **`fn separated_from(self : BallFloat, other : BallFloat) -> Bool`**
- **`fn definitely_lt(self : BallFloat, other : BallFloat) -> Bool`**
- **`fn definitely_gt(self : BallFloat, other : BallFloat) -> Bool`**
- **`fn maybe_overlap(self : BallFloat, other : BallFloat) -> Bool`**

## Arithmetic

- **`fn add(self : BallFloat, other : BallFloat) -> BallFloat`**
- **`fn sub(self : BallFloat, other : BallFloat) -> BallFloat`**
- **`fn mul(self : BallFloat, other : BallFloat) -> BallFloat`**
- **`fn div(self : BallFloat, other : BallFloat) -> BallFloat`**

### Operator Support

- `+`
- `-`
- `*`
- `/`

### Division Note

- Division aborts if the denominator ball contains zero.
- Arithmetic widens for both analytic error propagation and output-center rounding displacement.

## Trait Implementations

- `Eq`
- `Add`
- `Sub`
- `Mul`
- `Div`
- `Show`
- `@def.Floating`
