# `ball_float` API

## Stability

Bare/decorated interval construction, relations, forward arithmetic, contexts,
and flags are supported `0.7.0` APIs. Reverse operations and guaranteed
tightness are outside the contract.

This page tracks the current repository implementation and is written as the
`0.7.0` API baseline. It covers `@ball_float.BallFloat`,
`@ball_float.Decoration`, and `@ball_float.BallFloatDecorated`.

## Semantics

`BallFloat` represents the enclosure:

`center +/- radius`

The implementation stores that enclosure as lower and upper `BinFloat` bounds
and prefers correctness of containment over returning the narrowest possible
interval.

## Construction

- `BallFloat::new`
- `BallFloat::exact`
- `BallFloat::from_bounds`
- `BallFloat::from_coefficient`
- `BallFloat::from_int`
- `BallFloat::from_float`
- `BallFloat::from_double`

`from_coefficient` accepts a non-negative `@bin_float.BinCoeff` and an
independent `negative?` flag. The binary stack no longer exposes a `BigInt`
constructor; Decimal's `BigInt` API is unchanged.

Constraints:

- The center must be finite.
- The radius must be finite and non-negative.
- `exact`, `from_float`, and `from_double` abort on non-finite source values.

Notes:

- Center retuning widens the stored radius by the induced center displacement so the enclosure never shrinks.
- Radius quantization always rounds outward.

## Accessors and Interval Shape

- `lower_bound`
- `upper_bound`
- `center`
- `radius`
- `precision`
- `classify`
- `sign`
- `is_bounded`
- `is_entire`
- `contains_zero`
- `normalized`
- `with_precision`

Notes:

- `center()` and `radius()` abort on unbounded intervals.
- If the enclosure spans both negative and positive values, `sign()` returns `Sign::Zero`.
- `classify()` reports `Infinity` for unbounded intervals.

## Relations and Comparison

- `contains`
- `overlaps`
- `separated_from`
- `definitely_lt`
- `definitely_le`
- `definitely_gt`
- `maybe_eq`

Notes:

- Relations are enclosure-oriented and intentionally do not pretend to be a scalar total order.

## Arithmetic and Checked Capability Behavior

## Context And Status

`BallContext` applies directed endpoint rounding and `BallFlags` reports inexact, overflow, and underflow without changing set semantics.

- `add`
- `sub`
- `mul`
- `div`
- `abs`
- `neg`
- `pow_interval`
- `sin_interval`
- `cos_interval`
- `tan_interval`

Supported operators:

- `+`
- `-`
- `*`
- `/`
- unary `-`

Checked-behavior notes:

- Checked division may widen to the whole-real enclosure when the divisor contains zero.
- Checked integer power preserves enclosure correctness and uses the same whole-real fallback for zero-containing inverse cases.
- `BallFloat` does not implement scalar `CompareChecked`.
- General power uses the IEEE 1788 nonnegative-base domain; negative-base integer powers remain the responsibility of `pown`.
- The package does not yet expose hyperbolic or inverse trigonometric functions, calculus, matrices, complex balls, or special functions.

`BallContext::new` is a convenience constructor with positive-precision and
ordered-exponent preconditions. Use `BallContext::try_new` for external
parameters. `BallFlags` exposes `inexact`, `overflow`, `underflow`, and
`combine` accessors; callers should use these methods instead of depending on
field layout.

## Decorated Intervals

`BallFloatDecorated` intentionally lives in the same `ball_float` package as
`BallFloat`. Consumers import only `Luna-Flow/floating/ball_float`; there is no
separate `Luna-Flow/floating/decorated_ball_float` package. Bare intervals,
decorated intervals, contexts, and IEEE 1788 set semantics therefore share one
package boundary.

`Decoration` is ordered from weakest to strongest as `Ill`, `Trv`, `Def`,
`Dac`, and `Com`. `BallFloatDecorated` stores an underlying `BallFloat`, a
decoration, and an independent NaI state:

- `BallFloatDecorated::new` wraps a bare interval.
- `BallFloatDecorated::nai` constructs NaI; NaI uses `Ill` but is not Empty.
- `interval`, `decoration`, and `is_nai` expose the three observations.
- Empty canonicalizes to `Trv`; a non-common interval cannot retain `Com` and
  canonicalizes to `Dac`.
- Operations take the weakest input/operation decoration, so a grade never
  improves during evaluation.
- Partial domains, possible division by zero, and trigonometric poles lower the
  operation grade to `Trv`.
- Numeric operations propagate NaI; Boolean relations return `false` for NaI,
  while `overlap_state` returns `Undefined`.

The decorated type mirrors the supported set, relation, arithmetic,
cancellation, elementary-function, FMA, integer-power, extrema, and context
operations and implements `+`, `-`, `*`, `/`, and `Show`.

## Trait Surface

`BallFloat` currently implements:

- `@def.Floating`
- `@arithmetic.Contains`
- `@arithmetic.Overlaps`
- `@arithmetic.DefinitelyLt`
- `@arithmetic.DefinitelyLe`
- `@arithmetic.MaybeEq`
- `@arithmetic.DivChecked`
- `@arithmetic.PowNatChecked`
- `@arithmetic.PowIntChecked`
- `Eq`, `Add`, `Sub`, `Mul`, `Div`, `Neg`, `Show`

## Complete Public Interface

The following snapshot is the complete generated package interface for `0.7.0`. Public declarations are authoritative; prose above groups them by behavior.

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/ball_float"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/def",
  "moonbitlang/core/debug",
}

// Values

// Errors

// Types and methods
pub struct BallContext {
  // private fields
}
pub fn BallContext::binary32() -> Self
pub fn BallContext::binary64() -> Self
pub fn BallContext::e_max(Self) -> Int
pub fn BallContext::e_min(Self) -> Int
pub fn BallContext::new(precision? : Int, e_min? : Int, e_max? : Int) -> Self
pub fn BallContext::precision(Self) -> Int
pub fn BallContext::try_new(precision? : Int, e_min? : Int, e_max? : Int) -> Result[Self, @arithmetic.ArithmeticError]

pub struct BallFlags {
  inexact : Bool
  overflow : Bool
  underflow : Bool
} derive(Eq)
pub fn BallFlags::combine(Self, Self) -> Self
pub fn BallFlags::inexact(Self) -> Bool
pub fn BallFlags::new() -> Self
pub fn BallFlags::overflow(Self) -> Bool
pub fn BallFlags::underflow(Self) -> Bool

pub struct BallFloat {
  // private fields
} derive(Eq, @debug.Debug)
pub fn BallFloat::abs(Self) -> Self
pub fn BallFloat::acos_interval(Self) -> Self
pub fn BallFloat::acosh_interval(Self) -> Self
pub fn BallFloat::add(Self, Self) -> Self
pub fn BallFloat::add_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::apply_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::asin_interval(Self) -> Self
pub fn BallFloat::asinh_interval(Self) -> Self
pub fn BallFloat::atan2_interval(Self, Self) -> Self
pub fn BallFloat::atan_interval(Self) -> Self
pub fn BallFloat::atanh_interval(Self) -> Self
pub fn BallFloat::cancel_minus(Self, Self) -> Self
pub fn BallFloat::cancel_plus(Self, Self) -> Self
pub fn BallFloat::center(Self) -> @bin_float.BinFloat
pub fn BallFloat::classify(Self) -> @arithmetic.FpClass
pub fn BallFloat::contains(Self, @bin_float.BinFloat) -> Bool
pub fn BallFloat::contains_zero(Self) -> Bool
pub fn BallFloat::convex_hull(Self, Self) -> Self
pub fn BallFloat::cos_interval(Self) -> Self
pub fn BallFloat::cosh_interval(Self) -> Self
pub fn BallFloat::cospi_interval(Self) -> Self
pub fn BallFloat::definitely_gt(Self, Self) -> Bool
pub fn BallFloat::definitely_le(Self, Self) -> Bool
pub fn BallFloat::definitely_lt(Self, Self) -> Bool
pub fn BallFloat::disjoint(Self, Self) -> Bool
pub fn BallFloat::div(Self, Self) -> Self
pub fn BallFloat::div_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::empty(precision? : Int) -> Self
pub fn BallFloat::exact(@bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloat::exp10_interval(Self) -> Self
pub fn BallFloat::exp2_interval(Self) -> Self
pub fn BallFloat::exp_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::exp_interval(Self) -> Self
pub fn BallFloat::expm1_interval(Self) -> Self
pub fn BallFloat::fma(Self, Self, Self) -> Self
pub fn BallFloat::from_bounds(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloat::from_coefficient(@bin_float.BinCoeff, precision? : Int, negative? : Bool) -> Self
pub fn BallFloat::from_double(Double, precision? : Int) -> Self
pub fn BallFloat::from_float(Float, precision? : Int) -> Self
pub fn BallFloat::from_int(Int, precision? : Int) -> Self
pub fn BallFloat::hypot(Self, Self) -> Self
pub fn BallFloat::interior(Self, Self) -> Bool
pub fn BallFloat::intersection(Self, Self) -> Self
pub fn BallFloat::is_bounded(Self) -> Bool
pub fn BallFloat::is_common_interval(Self) -> Bool
pub fn BallFloat::is_empty(Self) -> Bool
pub fn BallFloat::is_entire(Self) -> Bool
pub fn BallFloat::is_singleton(Self) -> Bool
pub fn BallFloat::less(Self, Self) -> Bool
pub fn BallFloat::ln_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::ln_interval(Self) -> Self
pub fn BallFloat::log10_interval(Self) -> Self
pub fn BallFloat::log1p_interval(Self) -> Self
pub fn BallFloat::log2_interval(Self) -> Self
pub fn BallFloat::lower_bound(Self) -> @bin_float.BinFloat
pub fn BallFloat::magnitude(Self) -> @bin_float.BinFloat
pub fn BallFloat::maximum(Self, Self) -> Self
pub fn BallFloat::maybe_eq(Self, Self) -> Bool
pub fn BallFloat::midpoint(Self) -> @bin_float.BinFloat
pub fn BallFloat::midpoint_ctx(Self, BallContext) -> (@bin_float.BinFloat, BallFlags)
pub fn BallFloat::mignitude(Self) -> @bin_float.BinFloat
pub fn BallFloat::minimum(Self, Self) -> Self
pub fn BallFloat::mul(Self, Self) -> Self
pub fn BallFloat::mul_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::neg(Self) -> Self
pub fn BallFloat::new(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloat::normalized(Self) -> Self
pub fn BallFloat::overlap_state(Self, Self) -> OverlapState
pub fn BallFloat::overlaps(Self, Self) -> Bool
pub fn BallFloat::pow_interval(Self, Self) -> Self
pub fn BallFloat::pown(Self, Int) -> Self
pub fn BallFloat::precedes(Self, Self) -> Bool
pub fn BallFloat::precision(Self) -> Int
pub fn BallFloat::radius(Self) -> @bin_float.BinFloat
pub fn BallFloat::radius_extended(Self) -> @bin_float.BinFloat
pub fn BallFloat::reciprocal(Self) -> Self
pub fn BallFloat::rootn(Self, Int) -> Self
pub fn BallFloat::separated_from(Self, Self) -> Bool
pub fn BallFloat::set_equal(Self, Self) -> Bool
pub fn BallFloat::sign(Self) -> @def.Sign
pub fn BallFloat::sin_interval(Self) -> Self
pub fn BallFloat::sinh_interval(Self) -> Self
pub fn BallFloat::sinpi_interval(Self) -> Self
pub fn BallFloat::sqrt_interval(Self) -> Self
pub fn BallFloat::square(Self) -> Self
pub fn BallFloat::strictly_less(Self, Self) -> Bool
pub fn BallFloat::strictly_precedes(Self, Self) -> Bool
pub fn BallFloat::sub(Self, Self) -> Self
pub fn BallFloat::sub_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::subset(Self, Self) -> Bool
pub fn BallFloat::tan_interval(Self) -> Self
pub fn BallFloat::tanh_interval(Self) -> Self
pub fn BallFloat::tanpi_interval(Self) -> Self
pub fn BallFloat::try_acos_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_acosh_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_asin_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_asinh_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_atan2_interval(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_atan_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_atanh_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_cos_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_cosh_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_cospi_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_exact(@bin_float.BinFloat, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_exp10_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_exp2_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_exp_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_expm1_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_from_bounds(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_from_double(Double, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_from_float(Float, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_hypot(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_ln_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_log10_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_log1p_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_log2_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_pow_interval(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_rootn(Self, Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_sin_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_sinh_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_sinpi_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_tan_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_tanh_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_tanpi_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::upper_bound(Self) -> @bin_float.BinFloat
pub fn BallFloat::whole(precision? : Int) -> Self
pub fn BallFloat::width(Self) -> @bin_float.BinFloat
pub fn BallFloat::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub impl @arithmetic.Contains for BallFloat
pub impl @arithmetic.DefinitelyLe for BallFloat
pub impl @arithmetic.DefinitelyLt for BallFloat
pub impl @arithmetic.DivChecked for BallFloat
pub impl @arithmetic.MaybeEq for BallFloat
pub impl @arithmetic.Overlaps for BallFloat
pub impl @arithmetic.PowIntChecked for BallFloat
pub impl @arithmetic.PowNatChecked for BallFloat
pub impl @def.Floating for BallFloat
pub impl Add for BallFloat
pub impl Div for BallFloat
pub impl Mul for BallFloat
pub impl Neg for BallFloat
pub impl Show for BallFloat
pub impl Sub for BallFloat

pub struct BallFloatDecorated {
  // private fields
} derive(Eq)
pub fn BallFloatDecorated::abs(Self) -> Self
pub fn BallFloatDecorated::acos_interval(Self) -> Self
pub fn BallFloatDecorated::acosh_interval(Self) -> Self
pub fn BallFloatDecorated::add(Self, Self) -> Self
pub fn BallFloatDecorated::apply_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloatDecorated::asin_interval(Self) -> Self
pub fn BallFloatDecorated::asinh_interval(Self) -> Self
pub fn BallFloatDecorated::atan2_interval(Self, Self) -> Self
pub fn BallFloatDecorated::atan_interval(Self) -> Self
pub fn BallFloatDecorated::atanh_interval(Self) -> Self
pub fn BallFloatDecorated::cancel_minus(Self, Self) -> Self
pub fn BallFloatDecorated::cancel_plus(Self, Self) -> Self
pub fn BallFloatDecorated::contains(Self, @bin_float.BinFloat) -> Bool
pub fn BallFloatDecorated::convex_hull(Self, Self) -> Self
pub fn BallFloatDecorated::cos_interval(Self) -> Self
pub fn BallFloatDecorated::cosh_interval(Self) -> Self
pub fn BallFloatDecorated::cospi_interval(Self) -> Self
pub fn BallFloatDecorated::decoration(Self) -> Decoration
pub fn BallFloatDecorated::disjoint(Self, Self) -> Bool
pub fn BallFloatDecorated::div(Self, Self) -> Self
pub fn BallFloatDecorated::exp10_interval(Self) -> Self
pub fn BallFloatDecorated::exp2_interval(Self) -> Self
pub fn BallFloatDecorated::exp_interval(Self) -> Self
pub fn BallFloatDecorated::expm1_interval(Self) -> Self
pub fn BallFloatDecorated::fma(Self, Self, Self) -> Self
pub fn BallFloatDecorated::hypot(Self, Self) -> Self
pub fn BallFloatDecorated::interior(Self, Self) -> Bool
pub fn BallFloatDecorated::intersection(Self, Self) -> Self
pub fn BallFloatDecorated::interval(Self) -> BallFloat
pub fn BallFloatDecorated::is_common_interval(Self) -> Bool
pub fn BallFloatDecorated::is_empty(Self) -> Bool
pub fn BallFloatDecorated::is_entire(Self) -> Bool
pub fn BallFloatDecorated::is_nai(Self) -> Bool
pub fn BallFloatDecorated::is_singleton(Self) -> Bool
pub fn BallFloatDecorated::less(Self, Self) -> Bool
pub fn BallFloatDecorated::ln_interval(Self) -> Self
pub fn BallFloatDecorated::log10_interval(Self) -> Self
pub fn BallFloatDecorated::log1p_interval(Self) -> Self
pub fn BallFloatDecorated::log2_interval(Self) -> Self
pub fn BallFloatDecorated::maximum(Self, Self) -> Self
pub fn BallFloatDecorated::minimum(Self, Self) -> Self
pub fn BallFloatDecorated::mul(Self, Self) -> Self
pub fn BallFloatDecorated::nai(precision? : Int) -> Self
pub fn BallFloatDecorated::neg(Self) -> Self
pub fn BallFloatDecorated::new(BallFloat, decoration? : Decoration) -> Self
pub fn BallFloatDecorated::overlap_state(Self, Self) -> OverlapState
pub fn BallFloatDecorated::pos(Self) -> Self
pub fn BallFloatDecorated::pow_interval(Self, Self) -> Self
pub fn BallFloatDecorated::pown(Self, Int) -> Self
pub fn BallFloatDecorated::precedes(Self, Self) -> Bool
pub fn BallFloatDecorated::reciprocal(Self) -> Self
pub fn BallFloatDecorated::rootn(Self, Int) -> Self
pub fn BallFloatDecorated::set_equal(Self, Self) -> Bool
pub fn BallFloatDecorated::sin_interval(Self) -> Self
pub fn BallFloatDecorated::sinh_interval(Self) -> Self
pub fn BallFloatDecorated::sinpi_interval(Self) -> Self
pub fn BallFloatDecorated::sqrt_interval(Self) -> Self
pub fn BallFloatDecorated::square(Self) -> Self
pub fn BallFloatDecorated::strictly_less(Self, Self) -> Bool
pub fn BallFloatDecorated::strictly_precedes(Self, Self) -> Bool
pub fn BallFloatDecorated::sub(Self, Self) -> Self
pub fn BallFloatDecorated::subset(Self, Self) -> Bool
pub fn BallFloatDecorated::tan_interval(Self) -> Self
pub fn BallFloatDecorated::tanh_interval(Self) -> Self
pub fn BallFloatDecorated::tanpi_interval(Self) -> Self
pub impl Add for BallFloatDecorated
pub impl Div for BallFloatDecorated
pub impl Mul for BallFloatDecorated
pub impl Show for BallFloatDecorated
pub impl Sub for BallFloatDecorated

pub(all) enum Decoration {
  Ill
  Trv
  Def
  Dac
  Com
} derive(Eq, @debug.Debug)
pub impl Show for Decoration

pub(all) enum OverlapState {
  Undefined
  BothEmpty
  FirstEmpty
  SecondEmpty
  Before
  Meets
  OverlapsState
  Starts
  ContainedBy
  Finishes
  EqualIntervals
  After
  MetBy
  OverlappedBy
  StartedBy
  ContainsInterval
  FinishedBy
} derive(Eq, @debug.Debug)

// Type aliases

// Traits
```
<!-- generated-api-end -->
