# @bin_float.BinFloat

## Stability

`BinFloat`, `BinCoeff`, binary contexts/flags, and binary16/32/64/128
interchange are supported `0.7.0` application APIs. Limb layout, algorithm
thresholds, and complete IEEE 754 coverage are not promised.

This page tracks the `0.7.0` API baseline. The semantic and test scope
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

## Complete Public Interface

The following snapshot is the complete generated package interface for `0.7.0`. Public declarations are authoritative; prose above groups them by behavior.

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/bin_float"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/def",
  "moonbitlang/core/debug",
}

// Values
pub fn sqrt_bounds_for_precision(BinFloat, Int) -> Result[(BinFloat, BinFloat), @arithmetic.ArithmeticError]

pub fn sqrt_for_precision(BinFloat, Int) -> Result[BinFloat, @arithmetic.ArithmeticError]

// Errors

// Types and methods
pub struct BinCoeff {
  // private fields
} derive(@debug.Debug)
pub fn BinCoeff::add(Self, Self) -> Self
pub fn BinCoeff::bit_and(Self, Self) -> Self
pub fn BinCoeff::bit_length(Self) -> Int
pub fn BinCoeff::bit_or(Self, Self) -> Self
pub fn BinCoeff::bit_xor(Self, Self) -> Self
pub fn BinCoeff::compare(Self, Self) -> Int
pub fn BinCoeff::ctz(Self) -> Int
pub fn BinCoeff::div_rem_checked(Self, Self) -> Result[(Self, Self), String]
pub fn BinCoeff::from_bytes_be(BytesView) -> Self
pub fn BinCoeff::from_uint64(UInt64) -> Self
pub fn BinCoeff::gcd(Self, Self) -> Self
pub fn BinCoeff::is_zero(Self) -> Bool
pub fn BinCoeff::mul(Self, Self) -> Self
pub fn BinCoeff::one() -> Self
pub fn BinCoeff::parse(String, radix? : Int) -> Result[Self, String]
pub fn BinCoeff::pow_nat(Self, UInt) -> Self
pub fn BinCoeff::shift_left(Self, Int) -> Self
pub fn BinCoeff::shift_right(Self, Int) -> Self
pub fn BinCoeff::square(Self) -> Self
pub fn BinCoeff::sub_checked(Self, Self) -> Result[Self, String]
pub fn BinCoeff::test_bit(Self, Int) -> Bool
pub fn BinCoeff::to_bytes_be(Self) -> Bytes
pub fn BinCoeff::to_string(Self, radix? : Int) -> String
pub fn BinCoeff::to_uint64(Self) -> UInt64?
pub fn BinCoeff::zero() -> Self
pub impl Add for BinCoeff
pub impl Compare for BinCoeff
pub impl Eq for BinCoeff
pub impl Mul for BinCoeff
pub impl Shl for BinCoeff
pub impl Show for BinCoeff
pub impl Shr for BinCoeff

pub struct BinFloat {
  // private fields
} derive(Eq, @debug.Debug)
pub fn BinFloat::abs(Self) -> Self
pub fn BinFloat::acos(Self) -> Self
pub fn BinFloat::acos_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::acosh(Self) -> Self
pub fn BinFloat::acosh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::add(Self, Self) -> Self
pub fn BinFloat::add_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::asin(Self) -> Self
pub fn BinFloat::asin_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::asinh(Self) -> Self
pub fn BinFloat::asinh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::atan(Self) -> Self
pub fn BinFloat::atan2(Self, Self) -> Self
pub fn BinFloat::atan2_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::atan_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::atanh(Self) -> Self
pub fn BinFloat::atanh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn BinFloat::clamp_checked(Self, min~ : Self, max~ : Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::classify(Self) -> @arithmetic.FpClass
pub fn BinFloat::coefficient(Self) -> BinCoeff
pub fn BinFloat::compare(Self, Self) -> Int
pub fn BinFloat::compare_checked(Self, Self) -> Result[Int, @arithmetic.ArithmeticError]
pub fn BinFloat::cos(Self) -> Self
pub fn BinFloat::cos_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::cosh(Self) -> Self
pub fn BinFloat::cosh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::cospi(Self) -> Self
pub fn BinFloat::cospi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::div(Self, Self) -> Self
pub fn BinFloat::div_checked(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::div_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::exp(Self) -> Self
pub fn BinFloat::exp10(Self) -> Self
pub fn BinFloat::exp10_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::exp2(Self) -> Self
pub fn BinFloat::exp2_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::exp_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::exp_ln(Self) -> Self
pub fn BinFloat::exp_ln_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::expm1(Self) -> Self
pub fn BinFloat::expm1_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::exponent2(Self) -> Int
pub fn BinFloat::from_coefficient(BinCoeff, precision? : Int, negative? : Bool) -> Self
pub fn BinFloat::from_double(Double, precision? : Int) -> Self
pub fn BinFloat::from_float(Float, precision? : Int) -> Self
pub fn BinFloat::from_hex(String, Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::from_int(Int, precision? : Int) -> Self
pub fn BinFloat::hypot(Self, Self) -> Self
pub fn BinFloat::hypot_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::inf(@def.Sign, precision? : Int) -> Self
pub fn BinFloat::is_negative(Self) -> Bool
pub fn BinFloat::is_negative_zero(Self) -> Bool
pub fn BinFloat::is_quiet_nan(Self) -> Bool
pub fn BinFloat::is_signaling_nan(Self) -> Bool
pub fn BinFloat::is_zero(Self) -> Bool
pub fn BinFloat::ln(Self) -> Self
pub fn BinFloat::ln_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::log10(Self) -> Self
pub fn BinFloat::log10_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::log1p(Self) -> Self
pub fn BinFloat::log1p_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::log2(Self) -> Self
pub fn BinFloat::log2_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::make(BinCoeff, Int, Int, negative? : Bool, mode? : @arithmetic.RoundingMode) -> Self
pub fn BinFloat::max(Self, Self) -> Self
pub fn BinFloat::min(Self, Self) -> Self
pub fn BinFloat::mul(Self, Self) -> Self
pub fn BinFloat::mul_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::nan(precision? : Int) -> Self
pub fn BinFloat::nan_payload(Self) -> BinCoeff
pub fn BinFloat::neg(Self) -> Self
pub fn BinFloat::negative_zero(precision? : Int) -> Self
pub fn BinFloat::normalized(Self) -> Self
pub fn BinFloat::one(precision? : Int) -> Self
pub fn BinFloat::pow(Self, Self) -> Self
pub fn BinFloat::pow_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::pow_int(Self, Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::pow_int_ctx(Self, Int, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::pown(Self, Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::pown_ctx(Self, Int, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::precision(Self) -> Int
pub fn BinFloat::quiet_nan(payload? : BinCoeff, negative? : Bool, precision? : Int) -> Self
pub fn BinFloat::rootn(Self, Int) -> Self
pub fn BinFloat::rootn_ctx(Self, Int, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::round_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::sign(Self) -> @def.Sign
pub fn BinFloat::signaling_nan(payload? : BinCoeff, negative? : Bool, precision? : Int) -> Self
pub fn BinFloat::sin(Self) -> Self
pub fn BinFloat::sin_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::sinh(Self) -> Self
pub fn BinFloat::sinh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::sinpi(Self) -> Self
pub fn BinFloat::sinpi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::sqrt(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::sqrt_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::sub(Self, Self) -> Self
pub fn BinFloat::sub_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::tan(Self) -> Self
pub fn BinFloat::tan_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::tanh(Self) -> Self
pub fn BinFloat::tanh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::tanpi(Self) -> Self
pub fn BinFloat::tanpi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::to_hex(Self) -> String
pub fn BinFloat::to_interchange(Self, BinaryInterchangeFormat, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> (BinaryInterchange, BinaryFlags)
pub fn BinFloat::try_acos_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_acosh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_asin_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_asinh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_atan2_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_atan_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_atanh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_cos_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_cosh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_cospi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_exp10_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_exp2_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_exp_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_exp_ln_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_expm1_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_hypot_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_ln_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_log10_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_log1p_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_log2_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_pow_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_rootn_ctx(Self, Int, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_sin_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_sinh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_sinpi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_tan_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_tanh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_tanpi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::ulp(Self) -> Self
pub fn BinFloat::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub fn BinFloat::zero(precision? : Int) -> Self
pub impl @arithmetic.CompareChecked for BinFloat
pub impl @arithmetic.DivChecked for BinFloat
pub impl @arithmetic.PowIntChecked for BinFloat
pub impl @arithmetic.PowNatChecked for BinFloat
pub impl @arithmetic.SqrtChecked for BinFloat
pub impl @def.Floating for BinFloat
pub impl Add for BinFloat
pub impl Compare for BinFloat
pub impl Div for BinFloat
pub impl Mul for BinFloat
pub impl Neg for BinFloat
pub impl Show for BinFloat
pub impl Sub for BinFloat

pub struct BinaryContext {
  // private fields
} derive(Eq, @debug.Debug)
pub fn BinaryContext::binary128(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::binary16(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::binary32(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::binary64(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::e_max(Self) -> Int?
pub fn BinaryContext::e_min(Self) -> Int?
pub fn BinaryContext::from_arithmetic_context(@arithmetic.ArithmeticContext) -> Self
pub fn BinaryContext::new(Int, rounding? : BinaryRoundingMode, e_min? : Int, e_max? : Int, tininess? : TininessDetection) -> Self
pub fn BinaryContext::precision(Self) -> Int
pub fn BinaryContext::rounding(Self) -> BinaryRoundingMode
pub fn BinaryContext::tininess(Self) -> TininessDetection
pub fn BinaryContext::try_new(Int, rounding? : BinaryRoundingMode, e_min? : Int, e_max? : Int, tininess? : TininessDetection) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinaryContext::unbounded(Int, rounding? : BinaryRoundingMode) -> Self

pub struct BinaryFlags {
  // private fields
} derive(Eq, @debug.Debug)
pub fn BinaryFlags::combine(Self, Self) -> Self
pub fn BinaryFlags::division_by_zero(Self) -> Bool
pub fn BinaryFlags::inexact(Self) -> Bool
pub fn BinaryFlags::invalid_operation(Self) -> Bool
pub fn BinaryFlags::new() -> Self
pub fn BinaryFlags::overflow(Self) -> Bool
pub fn BinaryFlags::to_testfloat_bits(Self) -> Int
pub fn BinaryFlags::underflow(Self) -> Bool

pub struct BinaryInterchange {
  // private fields
} derive(Eq)
pub fn BinaryInterchange::bits(Self) -> BinCoeff
pub fn BinaryInterchange::format(Self) -> BinaryInterchangeFormat
pub fn BinaryInterchange::from_bin_float(BinFloat, BinaryInterchangeFormat, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> (Self, BinaryFlags)
pub fn BinaryInterchange::from_bits(BinCoeff, BinaryInterchangeFormat) -> Self
pub fn BinaryInterchange::from_hex(String, BinaryInterchangeFormat) -> Self?
pub fn BinaryInterchange::to_bin_float(Self) -> BinFloat
pub fn BinaryInterchange::to_hex(Self) -> String

pub(all) enum BinaryInterchangeFormat {
  Binary16
  Binary32
  Binary64
  Binary128
} derive(Eq, @debug.Debug)
pub fn BinaryInterchangeFormat::bias(Self) -> Int
pub fn BinaryInterchangeFormat::context(Self, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> BinaryContext
pub fn BinaryInterchangeFormat::e_max(Self) -> Int
pub fn BinaryInterchangeFormat::e_min(Self) -> Int
pub fn BinaryInterchangeFormat::exponent_bits(Self) -> Int
pub fn BinaryInterchangeFormat::fraction_bits(Self) -> Int
pub fn BinaryInterchangeFormat::precision(Self) -> Int
pub fn BinaryInterchangeFormat::total_bits(Self) -> Int

pub(all) enum BinaryRoundingMode {
  RoundTiesToEven
  RoundTiesToAway
  RoundTowardZero
  RoundTowardPositive
  RoundTowardNegative
  RoundAwayFromZero
} derive(Eq, @debug.Debug)
pub fn BinaryRoundingMode::from_arithmetic(@arithmetic.RoundingMode) -> Self
pub fn BinaryRoundingMode::to_arithmetic(Self) -> @arithmetic.RoundingMode?

pub(all) enum TininessDetection {
  BeforeRounding
  AfterRounding
} derive(Eq, @debug.Debug)

// Type aliases

// Traits
```
<!-- generated-api-end -->
