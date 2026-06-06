# @bin_float.BinFloat

This page tracks the current repository implementation and is written as the `0.1.0` API baseline.

---

## `pub struct BinFloat`

```moonbit
struct BinFloat {
  class : FpClass
  significand : BigInt
  exponent2 : Int
  precision_ : Int
} derive(Eq)
```

- **Description**
  Represents an arbitrary-precision binary floating-point value.

### Semantic Notes

- Finite values are represented as `significand * 2^exponent2`.
- Public constructors normalize finite values to a canonical form.
- Precision is stored on each value and used when retuning or constructing rounded results.
- `nan` is unordered and rejected by `compare`.

## Constructors and Special Values

- **`fn BinFloat::make(significand : BigInt, exponent2 : Int, precision : Int, mode? : RoundingMode = ToNearestEven) -> BinFloat`**
  Creates and normalizes a finite binary float.

- **`fn BinFloat::zero(precision? : Int = 53) -> BinFloat`**
  Creates normalized zero.

- **`fn BinFloat::one(precision? : Int = 53) -> BinFloat`**
  Creates normalized one.

- **`fn BinFloat::inf(sign : Sign, precision? : Int = 53) -> BinFloat`**
  Creates signed infinity.

- **`fn BinFloat::nan(precision? : Int = 53) -> BinFloat`**
  Creates a NaN sentinel value.

- **`fn BinFloat::from_int(n : Int, precision? : Int = 53) -> BinFloat`**
  Embeds an `Int`.

- **`fn BinFloat::from_bigint(n : BigInt, precision? : Int = 53) -> BinFloat`**
  Embeds a `BigInt`.

## Classification and Accessors

- **`fn classify(self : BinFloat) -> FpClass`**
- **`fn precision(self : BinFloat) -> Int`**
- **`fn sign(self : BinFloat) -> Sign`**
- **`fn significand(self : BinFloat) -> BigInt`**
- **`fn exponent2(self : BinFloat) -> Int`**
- **`fn is_zero(self : BinFloat) -> Bool`**

### Notes

- `significand()` and `exponent2()` expose the stored normalized representation.
- `sign()` returns `Sign::Zero` for `nan` in the current implementation.

## Normalization and Precision Control

- **`fn normalized(self : BinFloat) -> BinFloat`**
  Re-runs canonical normalization on the current value.

- **`fn with_precision(self : BinFloat, precision : Int, mode : RoundingMode) -> BinFloat`**
  Retunes the value to the requested working precision.

- **`fn ulp(self : BinFloat) -> BinFloat`**
  Returns the unit-in-the-last-place style spacing value for the current finite value.

## Arithmetic and Unary Operations

- **`fn neg(self : BinFloat) -> BinFloat`**
- **`fn abs(self : BinFloat) -> BinFloat`**
- **`fn add(self : BinFloat, other : BinFloat) -> BinFloat`**
- **`fn sub(self : BinFloat, other : BinFloat) -> BinFloat`**
- **`fn mul(self : BinFloat, other : BinFloat) -> BinFloat`**
- **`fn div(self : BinFloat, other : BinFloat) -> BinFloat`**

### Operator Support

- `+`
- `-`
- `*`
- `/`
- unary `-`

### Special-Value Behavior

- `nan` generally propagates through arithmetic.
- `inf - inf` with opposite signs produces `nan`.
- division by zero produces `inf` or `nan` depending on the numerator class.

## Comparison

- **`fn compare(self : BinFloat, other : BinFloat) -> Int`**
  Compares two values when both are ordered.

### Notes

- `compare` aborts when either side is `nan`.
- Finite comparison aligns exponents and compares the expanded significands.

## Trait Implementations

- `Eq`
- `Add`
- `Sub`
- `Mul`
- `Div`
- `Neg`
- `Show`
- `@def.Floating`
