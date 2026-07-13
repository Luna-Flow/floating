# `decimal_gda` API

`decimal_gda` is the General Decimal Arithmetic surface for `0.6.0`. Its value,
context, flags, traps, signals, and outcomes are distinct from the IEEE-oriented
types in `decimal`.

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

Context constructors and accessors include:

| API | Meaning |
| --- | --- |
| `basic`, `default` | precision 9, half-even, non-extended GDA context |
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

The pinned `official` corpus passes all 64,986 legal executable scalar rows and
`official0` passes all 16,124 legal rows. This does not turn diagnostic `#`
placeholder/non-scalar rows into values and does not promise compatibility with
unbounded future directives or resource sizes.

## Complete Public Interface

The following snapshot is the complete generated package interface for `0.6.0`. Public declarations are authoritative; prose above groups them by behavior.

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/decimal_gda"

import {
  "Luna-Flow/arithmetic",
  "moonbitlang/core/bigint",
}

// Values
pub fn abs(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn add(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn apply(Decimal, GdaContext) -> GdaOutcome[Decimal]

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

pub fn ln(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn log10(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_and(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_invert(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_or(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_xor(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

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
} derive(Eq)
pub fn Decimal::from_string(String, precision? : Int) -> Self?
pub fn Decimal::is_finite(Self) -> Bool
pub fn Decimal::is_infinite(Self) -> Bool
pub fn Decimal::is_nan(Self) -> Bool
pub fn Decimal::is_negative(Self) -> Bool
pub fn Decimal::is_qnan(Self) -> Bool
pub fn Decimal::is_snan(Self) -> Bool
pub fn Decimal::is_zero(Self) -> Bool
pub fn Decimal::nan_payload(Self) -> @bigint.BigInt
pub fn Decimal::one(precision? : Int) -> Self
pub fn Decimal::quiet_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::signaling_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::zero(precision? : Int) -> Self
pub impl Show for Decimal

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
