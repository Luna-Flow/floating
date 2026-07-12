# @bin_float.BinFloat

## Stability

`BinFloat`, `BinCoeff`, binary contexts/flags, and binary16/32/64/128
interchange are supported `0.5.0` application APIs. Limb layout, algorithm
thresholds, and complete IEEE 754 coverage are not promised.

This page tracks the `0.5.0` API baseline. The semantic and test scope
is in [Conformance](./conformance.md).

## Representation

Finite values are stored as a non-negative `BinCoeff`, an independent sign,
and an exponent:

`(-1)^negative * coefficient * 2^exponent2`

with an attached working `precision`.

## Context, Flags, And Interchange

- `BinaryRoundingMode`: nearest-even, nearest-away, toward-zero,
  toward-positive, toward-negative, and away-from-zero.
- `TininessDetection`: before or after rounding.
- `BinaryContext::new`, `try_new`, `unbounded`, `binary16`, `binary32`, `binary64`,
  `binary128`.
- `BinaryFlags`: `inexact`, `underflow`, `overflow`, `division_by_zero`,
  `invalid_operation`, `combine`, and `to_testfloat_bits`.
- `BinaryInterchangeFormat`: binary16, binary32, binary64, binary128 and their
  precision/exponent metadata.
- `BinaryInterchange::from_hex`, `to_hex`, `to_bin_float`, and
  `from_bin_float`; `BinFloat::to_interchange`.

`BinaryInterchange::from_bin_float` and `to_interchange` return both encoded
bits and status flags.

## Constructors and Observable State

- `BinFloat::make`
- `BinFloat::zero`
- `BinFloat::negative_zero`
- `BinFloat::one`
- `BinFloat::inf`
- `BinFloat::nan`
- `BinFloat::quiet_nan`
- `BinFloat::signaling_nan`
- `BinFloat::from_int`
- `BinFloat::from_coefficient`
- `BinFloat::from_float`
- `BinFloat::from_double`

`BinCoeff` is the public non-negative coefficient type. Construct one with
`BinCoeff::from_uint64`, `BinCoeff::parse`, or `BinCoeff::from_bytes_be`, then
pass it to `BinFloat::from_coefficient` or `BinFloat::make`. The sign is the
separate `negative?` argument; there is no binary-stack `BigInt` boundary.

`BinCoeff` exposes `zero`, `one`, `from_uint64`, `parse`, `from_bytes_be`,
`to_uint64`, `to_string`, and `to_bytes_be`; queries include `compare`,
`bit_length`, `ctz`, and `test_bit`. Arithmetic includes `add`, `sub_checked`,
`mul`, `square`, `div_rem_checked`, `gcd`, `pow_nat`, shifts, and bitwise
operations. Subtraction and division are checked because the type cannot
represent negative values or division by zero.

## Migration From The 0.4 Binary API

| 0.4 API | Current API |
| --- | --- |
| `BinFloat::from_bigint(n)` | `BinFloat::from_coefficient(c, negative=...)` |
| `BinFloat::make(n, e, p)` | `BinFloat::make(c, e, p, negative=...)` |
| `value.significand()` | `value.coefficient()` |
| `BinaryInterchange::from_bits(n, format)` / `bits() -> BigInt` | `from_bits(c, format)` / `bits() -> BinCoeff` |
| `BallFloat::from_bigint(n)` | `BallFloat::from_coefficient(c, negative=...)` |
| checked `from_bigint(n)` | checked `from_coefficient(c, negative=...)` |
| `NatHomomorphism` / `IntegralHomomorphism` | removed from binary types; use explicit constructors |

The change is intentionally limited to the binary and ball stacks. Decimal
and Semantic continue to expose their documented `BigInt` boundaries.

Notes:

- Public finite constructors normalize the stored representation.
- `compare` aborts on `NaN`.
- `is_negative`, `is_negative_zero`, `is_quiet_nan`, `is_signaling_nan`, and
  `nan_payload` expose special-value state.

## Access, Normalization, and Comparison

- `classify`
- `precision`
- `sign`
- `coefficient`
- `exponent2`
- `is_zero`
- `normalized`
- `with_precision`
- `ulp`
- `compare`
- `min`
- `max`
- `clamp`
- `clamp_checked`

Notes:

- `clamp` aborts if the bounds are unordered or `NaN`.
- `clamp_checked` returns a structured domain error for those invalid bounds.
- `ulp()` returns `NaN` on non-finite inputs.

## Arithmetic and Conversion

- `neg`
- `abs`
- `add`
- `sub`
- `mul`
- `div`

Contextual operations:

- `round_ctx`
- `add_ctx`, `sub_ctx`, `mul_ctx`, `div_ctx`
- `sqrt_ctx`
- `pow_int_ctx`

Supported operators:

- `+`
- `-`
- `*`
- `/`
- unary `-`

Special-value notes:

- `NaN` generally propagates.
- `inf - inf` with opposite signs becomes `NaN`.
- Division by zero produces `inf` or `NaN` depending on the numerator class.
- Operators use an unbounded nearest-even context and do not expose flags;
  use `*_ctx` for IEEE format semantics.

## Checked Arithmetic API

Direct exported helpers:

- `sqrt_bounds_for_precision`
- `sqrt_for_precision`
- `compare_checked`
- `div_checked`
- `sqrt`
- `pow_int`

Checked-behavior notes:

- `sqrt_bounds_for_precision` and `sqrt_for_precision` require non-negative finite inputs.
- `compare_checked` returns a structured unordered-comparison error on `NaN`.
- `div_checked` returns a structured division-by-zero error.
- `pow_int` returns a structured division-by-zero error for negative powers of zero.

## Trait Surface

`BinFloat` currently implements:

- `@def.Floating`
- `@arithmetic.SqrtChecked`
- `@arithmetic.DivChecked`
- `@arithmetic.CompareChecked`
- `@arithmetic.PowNatChecked`
- `@arithmetic.PowIntChecked`
- `Eq`, `Add`, `Sub`, `Mul`, `Div`, `Neg`, `Show`
