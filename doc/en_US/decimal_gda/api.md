# `decimal_gda` API

`decimal_gda` is the General Decimal Arithmetic Specification 1.70 surface for
`0.7.1`. Its value, context, flags, traps, signals, and outcomes are distinct
from the IEEE-oriented types in `decimal`.

The implementation is also independent: `Decimal` owns a persistent
`Small(UInt64) | Limbs(base-10^9)` coefficient, `GdaContext` stores its policy
and state directly, and concrete decimal32/64/128 interchange is DPD-only.
Neither this package nor its production frontend imports `decimal`.

## Value Type

`Decimal` is opaque and supports:

- `from_string(source, precision?) -> Decimal?` for context-free construction;
- `zero`, `one`, `quiet_nan`, and `signaling_nan` constructors;
- `is_finite`, `is_infinite`, `is_nan`, `is_qnan`, `is_snan`, `is_zero`, and
  `is_negative` classification;
- `nan_payload` observation and `Show` formatting.

Use package function `parse(source, context)` when conversion syntax, rounding,
exponent limits, sticky status, or traps must be observed. `Decimal` is not an
alias for `@decimal.Decimal`; cross the IEEE/GDA boundary through text or a
declared interchange format rather than depending on private representation.

## Contexts And Rounding

`GdaContext::new` accepts positive `precision`, `GdaRoundingMode`, `e_min`,
`e_max`, `clamp`, `extended`, and `GdaTrapSet`. It aborts for non-positive
precision. `try_new` reports invalid precision or reversed exponent bounds as
`ArithmeticError` instead.

Rounding modes are `HalfEven`, `HalfUp`, `HalfDown`, `Down`, `Ceiling`,
`Floor`, `Up`, and `ZeroFiveUp`.

GDA package operations `sqrt`, `exp`, `ln`, and `log10` finalize with the
specification-mandated half-even mathematical-function rule regardless of the
context's general rounding setting. `power` and ordinary arithmetic remain
sensitive to `GdaContext::rounding` as shown by official decTest vectors.

Context constructors and accessors include:

| API | Meaning |
| --- | --- |
| `basic`, `default` | precision 9, half-up, non-extended; Clamped, DivisionByZero, InvalidOperation, Overflow, and Underflow traps enabled |
| `decimal32`, `decimal64`, `decimal128` | standard precision/exponent presets with clamp |
| package `context` | convenience wrapper around `GdaContext::new` |
| package `decimal*_context` | convenience wrappers around standard presets |
| `radix` | always 10 |
| `precision`, `rounding`, `e_min`, `e_max`, `clamp`, `extended` | immutable arithmetic policy |
| `status`, `traps` | current sticky status and enabled trap set |
| `with_traps`, `trap` | return a context with changed traps |
| `clear_status` | clear sticky status and keep traps |
| `reset` | clear both sticky status and traps |

## Signals, Flags, And Traps

`GdaSignal` includes `ConversionSyntax`, `DivisionByZero`,
`DivisionImpossible`, `DivisionUndefined`, `InvalidContext`,
`InvalidOperation`, `Overflow`, `Underflow`, `Subnormal`, `Inexact`, `Rounded`,
`Clamped`, and `LostDigits`.

`GdaFlags::none`, `contains`, and `combine` create, query, and union condition
sets. `GdaTrapSet::none`, `with_signal`, and `contains` configure traps without
mutation.

The 1.70 standard signals are Clamped, DivisionByZero, InvalidOperation,
Overflow, Underflow, Subnormal, Inexact, and Rounded. `ConversionSyntax`,
`DivisionImpossible`, `DivisionUndefined`, and `InvalidContext` are retained as
detailed condition diagnostics and all signal `InvalidOperation`; `LostDigits`
is retained for legacy non-extended arithmetic. Consequently, an
`InvalidOperation` trap catches every one of those invalid conditions.

When several enabled signals are raised by one operation, trap selection uses
this precedence: invalid operation, division by zero, division undefined,
division impossible, invalid context, conversion syntax, overflow, underflow,
subnormal, inexact, rounded, clamped, then lost digits.

## Outcomes And State Threading

Every context operation returns `GdaOutcome[T]`:

```moonbit nocheck
enum GdaOutcome[T] {
  Completed(T, GdaContext, GdaFlags)
  Trapped(GdaSignal, T, GdaContext, GdaFlags)
}
```

Both variants contain the defined result, the next context with sticky status,
and flags raised by this operation. `value`, `next_context`, and `raised` expose
those common fields without matching the variant.

Pass `outcome.next_context()` into the next operation to accumulate status.
Reusing the old input context intentionally starts the next operation from its
old status. A trap does not discard the result.

## Arithmetic Operations

All functions take operands followed by `GdaContext` and return
`GdaOutcome[...]`.

| Family | Functions |
| --- | --- |
| Context application/unary | `apply`, `plus`, `minus`, `abs` |
| Basic arithmetic | `add`, `subtract`, `multiply`, `divide`, `fma` |
| Quotient/remainder | `divide_integer`, `remainder`, `remainder_near` |
| Exponent/quantum | `quantize`, `rescale`, `scaleb`, `reduce` |
| Integral conversion | `to_integral_exact`, `to_integral_value` |
| Elementary | `sqrt`, `exp`, `ln`, `log10`, `power` |
| Adjacent values | `next_plus`, `next_minus`, `next_toward` |
| Logical digits | `logical_and`, `logical_or`, `logical_xor`, `logical_invert` |
| Digit movement | `shift`, `rotate` |
| Comparison | `compare`, `compare_signal`, `compare_total`, `compare_total_magnitude` |

`compare` and `compare_signal` return a GDA decimal comparison value.
`compare_total` and `compare_total_magnitude` return `Int` inside the outcome.
Total comparison is representation-aware and differs from ordinary numeric
comparison.

## Boundary And Guarantees

The package is intended for GDA integrations and `.decTest` behavior. New IEEE
754 code should normally use `decimal`, where operations return
`(Decimal, DecimalFlags)` and contexts do not carry sticky status or traps.
Trigonometric, inverse-trigonometric, `atan2`, hyperbolic, `hypot`, and
pi-scaled functions are not GDA operations and are intentionally unavailable
from this package.

The pinned `official` corpus passes all 64,986 legal executable scalar rows and
`official0` passes all 16,124 legal rows. This does not turn diagnostic `#`
placeholder/non-scalar rows into values and does not promise compatibility with
unbounded future directives or resource sizes.

## Complete Public Interface

The following snapshot is the complete generated package interface for `0.7.1`. Public declarations are authoritative; prose above groups them by behavior.

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/decimal_gda"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/def",
  "Luna-Flow/luna-generic",
  "moonbitlang/core/bigint",
  "moonbitlang/core/debug",
}

// Values
pub fn abs(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn add(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn apply(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn class_name(Decimal, GdaContext) -> GdaOutcome[String]

pub fn compare(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn compare_signal(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn compare_total(Decimal, Decimal, GdaContext) -> GdaOutcome[Int]

pub fn compare_total_magnitude(Decimal, Decimal, GdaContext) -> GdaOutcome[Int]

pub fn context(precision? : Int, rounding? : GdaRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool) -> GdaContext

pub fn decimal128_context() -> GdaContext

pub fn decimal32_context() -> GdaContext

pub fn decimal64_context() -> GdaContext

pub fn divide(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn divide_integer(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn exp(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn fma(Decimal, Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn is_normal(Decimal, GdaContext) -> GdaOutcome[Bool]

pub fn is_subnormal(Decimal, GdaContext) -> GdaOutcome[Bool]

pub fn ln(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn log10(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logb(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_and(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_invert(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_or(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_xor(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn max(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn max_mag(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn min(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn min_mag(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn minus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn multiply(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn next_minus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn next_plus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn next_toward(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn parse(String, GdaContext) -> GdaOutcome[Decimal]

pub fn plus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn power(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn quantize(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn reduce(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn remainder(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn remainder_near(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn rescale(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn rotate(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn same_quantum(Decimal, Decimal, GdaContext) -> GdaOutcome[Bool]

pub fn scaleb(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn shift(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn sqrt(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn subtract(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn to_integral_exact(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn to_integral_value(Decimal, GdaContext) -> GdaOutcome[Decimal]

// Errors

// Types and methods
pub struct Decimal {
  // private fields
} derive(@debug.Debug)
pub fn Decimal::abs(Self) -> Self
pub fn Decimal::abs_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::add(Self, Self) -> Self
pub fn Decimal::add_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::apply_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn Decimal::clamp_checked(Self, min~ : Self, max~ : Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::class_name(Self, DecimalContext) -> String
pub fn Decimal::classify(Self) -> @arithmetic.FpClass
pub fn Decimal::coefficient(Self) -> @bigint.BigInt
pub fn Decimal::compare(Self, Self) -> Int
pub fn Decimal::compare_checked(Self, Self) -> Result[Int, @arithmetic.ArithmeticError]
pub fn Decimal::compare_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::compare_signal_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::compare_total(Self, Self) -> Int
pub fn Decimal::compare_total_ctx(Self, Self, DecimalContext) -> (Int, DecimalFlags)
pub fn Decimal::compare_total_magnitude(Self, Self) -> Int
pub fn Decimal::compare_total_magnitude_ctx(Self, Self, DecimalContext) -> (Int, DecimalFlags)
pub fn Decimal::copy(Self) -> Self
pub fn Decimal::copy_abs(Self) -> Self
pub fn Decimal::copy_negate(Self) -> Self
pub fn Decimal::copy_sign(Self, Self) -> Self
pub fn Decimal::div(Self, Self) -> Self
pub fn Decimal::div_checked(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::div_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::divide_integer(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exp_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exponent10(Self) -> Int
pub fn Decimal::fma_ctx(Self, Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::from_bigint(@bigint.BigInt, precision? : Int) -> Self
pub fn Decimal::from_bin_float(@bin_float.BinFloat, precision? : Int) -> Self
pub fn Decimal::from_double(Double, precision? : Int) -> Self
pub fn Decimal::from_float(Float, precision? : Int) -> Self
pub fn Decimal::from_int(Int, precision? : Int) -> Self
pub fn Decimal::from_interchange_hex(String, GdaInterchangeFormat) -> Self?
pub fn Decimal::from_string(String, precision? : Int) -> Self?
pub fn Decimal::from_string_ctx(String, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::get_payload(Self) -> @bigint.BigInt
pub fn Decimal::inf(@def.Sign, precision? : Int) -> Self
pub fn Decimal::is_canonical(Self) -> Bool
pub fn Decimal::is_finite(Self) -> Bool
pub fn Decimal::is_infinite(Self) -> Bool
pub fn Decimal::is_nan(Self) -> Bool
pub fn Decimal::is_negative(Self) -> Bool
pub fn Decimal::is_negative_zero(Self) -> Bool
pub fn Decimal::is_normal(Self, DecimalContext) -> Bool
pub fn Decimal::is_qnan(Self) -> Bool
pub fn Decimal::is_quiet_nan(Self) -> Bool
pub fn Decimal::is_signaling_nan(Self) -> Bool
pub fn Decimal::is_signed(Self) -> Bool
pub fn Decimal::is_snan(Self) -> Bool
pub fn Decimal::is_subnormal(Self, DecimalContext) -> Bool
pub fn Decimal::is_zero(Self) -> Bool
pub fn Decimal::ln_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log10_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logb_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_and(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_invert(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_or(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_xor(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::magnitude(Self) -> @bigint.BigInt
pub fn Decimal::make(@bigint.BigInt, Int, Int, mode? : @arithmetic.RoundingMode) -> Self
pub fn Decimal::max(Self, Self) -> Self
pub fn Decimal::max_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::max_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::min(Self, Self) -> Self
pub fn Decimal::min_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::min_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minus_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::mul(Self, Self) -> Self
pub fn Decimal::mul_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::nan(precision? : Int) -> Self
pub fn Decimal::nan_payload(Self) -> @bigint.BigInt
pub fn Decimal::neg(Self) -> Self
pub fn Decimal::negative_zero(precision? : Int) -> Self
pub fn Decimal::next_minus(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_plus(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_toward(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::normalize_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::normalized(Self) -> Self
pub fn Decimal::one(precision? : Int) -> Self
pub fn Decimal::parse(String, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::plus_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::power_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::precision(Self) -> Int
pub fn Decimal::quantize(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::quantum(Self) -> Int
pub fn Decimal::quiet_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::reduce_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder_near(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rescale(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rotate_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::same_quantum(Self, Self) -> Bool
pub fn Decimal::scaleb_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::set_payload(Self, @bigint.BigInt) -> Self
pub fn Decimal::set_payload_signaling(Self, @bigint.BigInt) -> Self
pub fn Decimal::shift_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sign(Self) -> @def.Sign
pub fn Decimal::signaling_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::sqrt(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sub(Self, Self) -> Self
pub fn Decimal::sub_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_bin_float(Self, precision? : Int, mode? : @arithmetic.RoundingMode) -> @bin_float.BinFloat
pub fn Decimal::to_eng_string(String, DecimalContext) -> (String, DecimalFlags)
pub fn Decimal::to_integral_exact(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_integral_value(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_interchange_hex(Self, GdaInterchangeFormat) -> (String, DecimalFlags)
pub fn Decimal::to_sci_string(String, DecimalContext) -> (String, DecimalFlags)
pub fn Decimal::trim(Self) -> Self
pub fn Decimal::try_exp_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_ln_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log10_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_power_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub fn Decimal::zero(precision? : Int) -> Self
pub impl @arithmetic.AbsContextual for Decimal
pub impl @arithmetic.AddContextual for Decimal
pub impl @arithmetic.CompareChecked for Decimal
pub impl @arithmetic.DivChecked for Decimal
pub impl @arithmetic.DivContextual for Decimal
pub impl @arithmetic.ExpContextual for Decimal
pub impl @arithmetic.MulContextual for Decimal
pub impl @arithmetic.NumericFormatContextual for Decimal
pub impl @arithmetic.ParseChecked for Decimal
pub impl @arithmetic.PowIntChecked for Decimal
pub impl @arithmetic.PowNatChecked for Decimal
pub impl @arithmetic.SqrtChecked for Decimal
pub impl @arithmetic.SqrtContextual for Decimal
pub impl @arithmetic.SubContextual for Decimal
pub impl @def.Floating for Decimal
pub impl @luna-generic.AddGroup for Decimal
pub impl @luna-generic.AddMonoid for Decimal
pub impl @luna-generic.IntegralHomomorphism for Decimal
pub impl @luna-generic.MulMonoid for Decimal
pub impl @luna-generic.NatHomomorphism for Decimal
pub impl @luna-generic.One for Decimal
pub impl @luna-generic.Ring for Decimal
pub impl @luna-generic.Semiring for Decimal
pub impl @luna-generic.Zero for Decimal
pub impl Add for Decimal
pub impl Compare for Decimal
pub impl Div for Decimal
pub impl Eq for Decimal
pub impl Mul for Decimal
pub impl Neg for Decimal
pub impl Show for Decimal
pub impl Sub for Decimal

pub struct DecimalContext {
  // private fields
} derive(Eq)
pub fn DecimalContext::clamp(Self) -> Bool
pub fn DecimalContext::decimal128() -> Self
pub fn DecimalContext::decimal32() -> Self
pub fn DecimalContext::decimal64() -> Self
pub fn DecimalContext::decimal_rounding(Self) -> DecimalRoundingMode
pub fn DecimalContext::e_max(Self) -> Int
pub fn DecimalContext::e_min(Self) -> Int
pub fn DecimalContext::exact() -> Self
pub fn DecimalContext::extended(Self) -> Bool
pub fn DecimalContext::from_arithmetic_context(@arithmetic.ArithmeticContext) -> Self
pub fn DecimalContext::new(precision? : Int, rounding? : @arithmetic.RoundingMode, decimal_rounding? : DecimalRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, tininess? : DecimalTininessDetection) -> Self
pub fn DecimalContext::precision(Self) -> Int
pub fn DecimalContext::rounding(Self) -> @arithmetic.RoundingMode
pub fn DecimalContext::tininess(Self) -> DecimalTininessDetection
pub fn DecimalContext::try_new(precision? : Int, rounding? : @arithmetic.RoundingMode, decimal_rounding? : DecimalRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, tininess? : DecimalTininessDetection) -> Result[Self, @arithmetic.ArithmeticError]
pub fn DecimalContext::with_rounding(Self, @arithmetic.RoundingMode) -> Self
pub fn DecimalContext::with_tininess(Self, DecimalTininessDetection) -> Self

pub struct DecimalFlags {
  inexact : Bool
  rounded : Bool
  lost_digits : Bool
  invalid_operation : Bool
  division_by_zero : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  clamped : Bool
  conversion_syntax : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
} derive(Eq)
pub fn DecimalFlags::combine(Self, Self) -> Self
pub fn DecimalFlags::contains(Self, DecimalSignal) -> Bool
pub fn DecimalFlags::has_error(Self) -> Bool
pub fn DecimalFlags::new() -> Self

pub(all) enum DecimalRoundingMode {
  HalfEven
  HalfUp
  HalfDown
  Down
  Ceiling
  Floor
  Up
  ZeroFiveUp
} derive(Eq)
pub fn DecimalRoundingMode::from_arithmetic(@arithmetic.RoundingMode) -> Self
pub fn DecimalRoundingMode::to_arithmetic(Self) -> @arithmetic.RoundingMode?

pub(all) enum DecimalSignal {
  ConversionSyntax
  DivisionByZero
  DivisionImpossible
  DivisionUndefined
  InvalidContext
  InvalidOperation
  Overflow
  Underflow
  Subnormal
  Inexact
  Rounded
  Clamped
  LostDigits
} derive(Eq)

pub(all) enum DecimalTininessDetection {
  BeforeRounding
  AfterRounding
} derive(Eq)

pub struct GdaContext {
  // private fields
}
pub fn GdaContext::basic() -> Self
pub fn GdaContext::clamp(Self) -> Bool
pub fn GdaContext::clear_status(Self) -> Self
pub fn GdaContext::decimal128() -> Self
pub fn GdaContext::decimal32() -> Self
pub fn GdaContext::decimal64() -> Self
pub fn GdaContext::default() -> Self
pub fn GdaContext::e_max(Self) -> Int
pub fn GdaContext::e_min(Self) -> Int
pub fn GdaContext::extended(Self) -> Bool
pub fn GdaContext::new(precision? : Int, rounding? : GdaRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, traps? : GdaTrapSet) -> Self
pub fn GdaContext::precision(Self) -> Int
pub fn GdaContext::radix(Self) -> Int
pub fn GdaContext::reset(Self) -> Self
pub fn GdaContext::rounding(Self) -> GdaRoundingMode
pub fn GdaContext::status(Self) -> GdaFlags
pub fn GdaContext::trap(Self, GdaSignal, enabled? : Bool) -> Self
pub fn GdaContext::traps(Self) -> GdaTrapSet
pub fn GdaContext::try_new(precision? : Int, rounding? : GdaRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, traps? : GdaTrapSet) -> Result[Self, @arithmetic.ArithmeticError]
pub fn GdaContext::with_traps(Self, GdaTrapSet) -> Self

pub struct GdaFlags {
  conversion_syntax : Bool
  division_by_zero : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
  invalid_operation : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  inexact : Bool
  rounded : Bool
  clamped : Bool
  lost_digits : Bool
} derive(Eq)
pub fn GdaFlags::combine(Self, Self) -> Self
pub fn GdaFlags::contains(Self, GdaSignal) -> Bool
pub fn GdaFlags::none() -> Self

pub struct GdaInterchange {
  // private fields
}
pub fn GdaInterchange::canonical(Self) -> Self
pub fn GdaInterchange::copy(Self) -> Self
pub fn GdaInterchange::copy_abs(Self) -> Self
pub fn GdaInterchange::copy_negate(Self) -> Self
pub fn GdaInterchange::copy_sign(Self, Self) -> Self
pub fn GdaInterchange::format(Self) -> GdaInterchangeFormat
pub fn GdaInterchange::from_decimal(Decimal, GdaInterchangeFormat) -> (Self, DecimalFlags)
pub fn GdaInterchange::from_hex(String, GdaInterchangeFormat) -> Self?
pub fn GdaInterchange::is_canonical(Self) -> Bool
pub fn GdaInterchange::to_decimal(Self) -> Decimal
pub fn GdaInterchange::to_decimal_ctx(Self) -> (Decimal, DecimalFlags)
pub fn GdaInterchange::to_hex(Self) -> String

pub(all) enum GdaInterchangeFormat {
  Decimal32
  Decimal64
  Decimal128
} derive(Eq)
pub fn GdaInterchangeFormat::context(Self) -> DecimalContext

pub(all) enum GdaOutcome[T] {
  Completed(T, GdaContext, GdaFlags)
  Trapped(GdaSignal, T, GdaContext, GdaFlags)
}
pub fn[T] GdaOutcome::next_context(Self[T]) -> GdaContext
pub fn[T] GdaOutcome::raised(Self[T]) -> GdaFlags
pub fn[T] GdaOutcome::value(Self[T]) -> T

pub(all) enum GdaRoundingMode {
  HalfEven
  HalfUp
  HalfDown
  Down
  Ceiling
  Floor
  Up
  ZeroFiveUp
} derive(Eq)

pub(all) enum GdaSignal {
  ConversionSyntax
  DivisionByZero
  DivisionImpossible
  DivisionUndefined
  InvalidContext
  InvalidOperation
  Overflow
  Underflow
  Subnormal
  Inexact
  Rounded
  Clamped
  LostDigits
} derive(Eq)

pub struct GdaTrapSet {
  conversion_syntax : Bool
  division_by_zero : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
  invalid_operation : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  inexact : Bool
  rounded : Bool
  clamped : Bool
  lost_digits : Bool
} derive(Eq)
pub fn GdaTrapSet::contains(Self, GdaSignal) -> Bool
pub fn GdaTrapSet::none() -> Self
pub fn GdaTrapSet::with_signal(Self, GdaSignal, enabled? : Bool) -> Self

// Type aliases

// Traits
```
<!-- generated-api-end -->
