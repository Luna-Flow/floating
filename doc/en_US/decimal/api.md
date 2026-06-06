# @decimal.Decimal

This page tracks the current repository implementation and is written as the `0.1.0` API baseline.

---

## `pub struct Decimal`

```moonbit
struct Decimal {
  class : FpClass
  coefficient : BigInt
  exponent10 : Int
  precision_ : Int
} derive(Eq)
```

- **Description**
  Represents an arbitrary-precision decimal floating-point value.

### Semantic Notes

- Finite values are represented as `coefficient * 10^exponent10`.
- Public constructors normalize finite values by stripping removable powers of `10`.
- String parsing and string display are first-class package concerns.

## Constructors and Special Values

- **`fn Decimal::make(coefficient : BigInt, exponent10 : Int, precision : Int, mode? : RoundingMode = ToNearestEven) -> Decimal`**
- **`fn Decimal::zero(precision? : Int = 34) -> Decimal`**
- **`fn Decimal::one(precision? : Int = 34) -> Decimal`**
- **`fn Decimal::inf(sign : Sign, precision? : Int = 34) -> Decimal`**
- **`fn Decimal::nan(precision? : Int = 34) -> Decimal`**
- **`fn Decimal::from_int(n : Int, precision? : Int = 34) -> Decimal`**
- **`fn Decimal::from_bigint(n : BigInt, precision? : Int = 34) -> Decimal`**
- **`fn Decimal::from_string(src : String, precision? : Int = 34) -> Decimal?`**

### Notes

- `from_string` accepts plain decimal and scientific notation in the current implementation.
- Invalid strings return `None`.

## Classification and Accessors

- **`fn classify(self : Decimal) -> FpClass`**
- **`fn precision(self : Decimal) -> Int`**
- **`fn sign(self : Decimal) -> Sign`**
- **`fn coefficient(self : Decimal) -> BigInt`**
- **`fn exponent10(self : Decimal) -> Int`**
- **`fn is_zero(self : Decimal) -> Bool`**

## Normalization and Precision Control

- **`fn normalized(self : Decimal) -> Decimal`**
- **`fn with_precision(self : Decimal, precision : Int, mode : RoundingMode) -> Decimal`**

## Arithmetic and Unary Operations

- **`fn neg(self : Decimal) -> Decimal`**
- **`fn abs(self : Decimal) -> Decimal`**
- **`fn add(self : Decimal, other : Decimal) -> Decimal`**
- **`fn sub(self : Decimal, other : Decimal) -> Decimal`**
- **`fn mul(self : Decimal, other : Decimal) -> Decimal`**
- **`fn div(self : Decimal, other : Decimal) -> Decimal`**

### Operator Support

- `+`
- `-`
- `*`
- `/`
- unary `-`

## Conversion

- **`fn to_bin_float(self : Decimal, precision? : Int = self.precision_, mode? : RoundingMode = ToNearestEven) -> @bin_float.BinFloat`**
- **`fn Decimal::from_bin_float(x : @bin_float.BinFloat, precision? : Int = x.precision()) -> Decimal`**

### Notes

- Conversion from decimal to binary may be approximate when the decimal value is not dyadic.
- Conversion from binary to decimal is exact for the finite representation currently stored in `BinFloat`.

## Trait Implementations

- `Eq`
- `Add`
- `Sub`
- `Mul`
- `Div`
- `Neg`
- `Show`
- `@def.Floating`
