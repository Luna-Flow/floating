# @decimal.Decimal

## Stability

`Decimal`, `DecimalContext`, `DecimalFlags`, and decimal interchange are
supported `0.7.0` application APIs. Internal `DecCoeff` layout is not public;
the pinned legal GDA corpus is fully conformant, with only `#` placeholder/
non-scalar invalid rows excluded.

This page tracks the `0.7.0` IEEE API and separate GDA representation.

## Representation

## Before You Start

Use `Decimal` for decimal meaning, not for a promise that every operation is exact. Keep `DecimalContext` explicit whenever flags or exponent bounds matter.

## Semantic Reminders

Numeric equality, quantum equality, and total order observe different aspects of a Decimal value.

Finite values are stored as:

`(-1)^negative * magnitude * 10^exponent10`

with an attached working `precision`.

The public `coefficient()` and `magnitude()` observers return the non-negative
coefficient as `BigInt`. Use `is_negative()` when the sign must be inspected
separately. This matters for GDA-style values such as `-0`, where the
mathematical coefficient is zero but the representation still carries a
negative sign.

## Constructors and Parsing

- `Decimal::make`
- `Decimal::zero`
- `Decimal::negative_zero`
- `Decimal::one`
- `Decimal::inf`
- `Decimal::nan`
- `Decimal::quiet_nan`
- `Decimal::signaling_nan`
- `Decimal::from_int`
- `Decimal::from_bigint`
- `Decimal::from_float`
- `Decimal::from_double`
- `Decimal::from_string`
- `Decimal::from_interchange_hex`
- `Decimal::from_bin_float`
- `DecimalInterchange::from_hex`
- `DecimalInterchange::from_decimal`

Notes:

- Numeric constructors such as `make`, `from_int`, and `from_bigint` normalize
  by removing removable powers of `10`.
- `from_string` accepts plain decimal, scientific notation, and
  `Infinity`/`NaN`/`sNaN` spellings with optional sign and decimal payload. It
  preserves the parsed exponent/quantum when the coefficient fits the
  requested precision.
- `from_string("-0")` preserves negative zero.
- Invalid strings return `None`.
- `from_interchange_hex` decodes decimal32/64/128 interchange hex strings into
  scalar `Decimal` values using the requested format context.
- `DecimalInterchange` is the public wrapper for raw decimal32/64/128
  interchange bit patterns when callers need to preserve, inspect, or
  canonicalize non-canonical encodings instead of collapsing immediately to a
  scalar decimal value.

## Access, Normalization, and Comparison

- `classify`
- `class_name`
- `precision`
- `sign`
- `coefficient`
- `magnitude`
- `exponent10`
- `is_negative`
- `is_signed`
- `is_finite`
- `is_infinite`
- `is_nan`
- `is_canonical`
- `is_zero`
- `is_negative_zero`
- `is_normal`
- `is_subnormal`
- `is_quiet_nan`
- `is_qnan`
- `is_signaling_nan`
- `is_snan`
- `nan_payload`
- `normalized`
- `with_precision`
- `compare`
- `compare_ctx`
- `compare_signal_ctx`
- `compare_total`
- `compare_total_magnitude`
- `min`
- `max`
- `min_ctx`
- `max_ctx`
- `min_mag_ctx`
- `max_mag_ctx`
- `clamp`
- `clamp_checked`

Notes:

- `compare` aborts on `NaN`.
- `compare_ctx(lhs, rhs, ctx)` returns a decimal `-1`, `0`, `1`, or quiet `NaN`
  plus flags. Quiet NaNs produce quiet `NaN` without invalid-operation status;
  signaling NaNs set `invalid_operation`.
- `compare_signal_ctx(lhs, rhs, ctx)` has the same numeric result shape as
  `compare_ctx`, but any NaN operand sets `invalid_operation`.
- `clamp` aborts if the bounds are unordered or `NaN`.
- `clamp_checked` returns a structured domain error for those invalid bounds.
- The shared `Sign` observer still returns `Zero` for finite zero values,
  including negative zero. Use `is_negative_zero()` when the sign of zero is
  semantically relevant.
- `class_name(ctx)` returns the GDA-style class string for the value under the
  supplied exponent context, including normal/subnormal distinctions.
- `is_canonical()` currently returns `true` because this package has no
  alternate decimal interchange encodings yet.
- `is_qnan()` and `is_snan()` are GDA-name aliases for the existing quiet and
  signaling NaN predicates.
- `Eq` is numeric equality for generic Luna-Flow use: `+0 == -0`, and NaN
  values compare equal to each other at the `Eq` layer. Use the explicit NaN
  observers when representation-level distinction matters.

## Arithmetic and Conversion

## When To Use Context APIs

Prefer `*_ctx` for IEEE Decimal workflows that must observe rounding and
`DecimalFlags`; convenience operators intentionally discard those flags. Use
`decimal_gda` when sticky GDA status or traps are required.

- `neg`
- `abs`
- `copy`
- `copy_abs`
- `copy_negate`
- `copy_sign`
- `add`
- `add_ctx`
- `plus_ctx`
- `minus_ctx`
- `abs_ctx`
- `sub`
- `sub_ctx`
- `mul`
- `mul_ctx`
- `div`
- `div_ctx`
- `sqrt`
- `sqrt_ctx`
- `fma_ctx`
- `divide_integer`
- `remainder`
- `remainder_near`
- `next_plus`
- `next_minus`
- `next_toward`
- `exp_ctx`
- `exp2_ctx`, `exp10_ctx`, `expm1_ctx`
- `ln_ctx`
- `log2_ctx`, `log10_ctx`, `log1p_ctx`
- `power_ctx`, `pown_ctx`, `rootn_ctx`, `hypot_ctx`
- `sin_ctx`, `cos_ctx`, `tan_ctx`
- `sinpi_ctx`, `cospi_ctx`, `tanpi_ctx`
- `asin_ctx`, `acos_ctx`, `atan_ctx`, `atan2_ctx`
- `sinh_ctx`, `cosh_ctx`, `tanh_ctx`
- `asinh_ctx`, `acosh_ctx`, `atanh_ctx`
- `logb_ctx`
- `scaleb_ctx`
- `to_sci_string`
- `to_eng_string`
- `shift_ctx`
- `rotate_ctx`
- `quantize`
- `rescale`
- `reduce_ctx`
- `normalize_ctx`
- `same_quantum`
- `quantum`
- `get_payload`
- `set_payload`
- `set_payload_signaling`
- `to_integral_exact`
- `to_integral_value`
- `logical_and`
- `logical_or`
- `logical_xor`
- `logical_invert`
- `to_interchange_hex`
- `to_bin_float`

Every elementary `*_ctx` entry has an additive `try_*_ctx` mirror that returns
`ArithmeticError::CertificationFailure` when the enclosure cannot prove a
unique target value and flags. The GDA-standard surface remains limited to
`exp`, `ln`, `log10`, `power`, and `sqrt`; the other families above are IEEE
Decimal extensions and are not exported by `decimal_gda`.

## Interchange Encoding

- `DecimalInterchangeFormat::context`
- `Decimal::to_interchange_hex`
- `DecimalInterchange::format`
- `DecimalInterchange::to_hex`
- `DecimalInterchange::to_decimal`
- `DecimalInterchange::canonical`
- `DecimalInterchange::is_canonical`
- `DecimalInterchange::copy`
- `DecimalInterchange::copy_abs`
- `DecimalInterchange::copy_negate`
- `DecimalInterchange::copy_sign`

Supported operators:

- `+`
- `-`
- `*`
- `/`
- unary `-`

Conversion notes:

- Decimal-to-binary conversion may be approximate for non-dyadic values.
- Binary-to-decimal conversion is exact for the currently stored finite `BinFloat` value.
- `to_sci_string(src, ctx)` and `to_eng_string(src, ctx)` implement the GDA
  string-conversion operations used by `toSci` and `toEng` decTests. They parse
  finite numbers, infinities, qNaNs, and sNaNs from text under the active
  decimal context, then return canonical GDA scientific or engineering text
  together with conversion status flags. The conversion path handles syntax
  diagnostics, payload bounds, discarded-zero `rounded` status, directed
  overflow to infinity or maximum finite value, Etiny underflow, clamped
  zero exponents, and canonical special-value spellings such as `Infinity`,
  `NaN7`, and `sNaN`.
- `logb_ctx` returns the adjusted exponent as a Decimal integer under the active
  context. Finite zero returns `-Infinity` with `division_by_zero`; infinities
  return `+Infinity`; NaNs propagate through the context quieting/payload rules.
  When the adjusted exponent needs context rounding, discarded zero digits set
  `rounded` without `inexact`, matching GDA integer-result semantics.
- `scaleb_ctx` returns `self * 10^other` under the active context. The scale
  operand must be a finite exponent-zero integer within the GDA context range;
  invalid scale operands return quiet `NaN` with `invalid_operation`. Finite
  results preserve coefficient cohorts where possible, then apply exponent-bound
  finalization, including Etiny subnormal rounding, clamped zero, and directed
  overflow flags.
- `shift_ctx` and `rotate_ctx` implement GDA coefficient digit movement using
  the active context precision as the digit width. Count operands must be finite
  integers in range; invalid counts return quiet `NaN` with `invalid_operation`.
  Quiet NaNs propagate their sign and payload, and signaling NaNs are quieted
  with payload truncation governed by the context precision.
- `to_interchange_hex(format)` encodes a `Decimal` into decimal32/64/128
  interchange hex text after applying the target format context to finite
  values. `from_interchange_hex(src, format)` performs the inverse decode and
  accepts canonical and non-canonical interchange payloads, optional leading
  `#`, either hex case, and surrounding ASCII whitespace.
- `DecimalInterchange::to_hex()` emits canonical wrapper text with an uppercase
  hex body and the fixed digit width required by the stored decimal32/64/128
  format.
- `DecimalInterchangeFormat::context()` returns the matching decimal32,
  decimal64, or decimal128 preset context used by the interchange encode/decode
  helpers.
- `DecimalInterchange::from_decimal(value, format)` is the wrapper-form encode
  entry point: it returns the same representation and status flags as
  `value.to_interchange_hex(format)`, but packages the resulting bits as a
  `DecimalInterchange` for further representation-level operations.
- `DecimalInterchange` preserves raw interchange bits for callers that need
  representation-level operations such as canonicalization or sign-copy without
  first collapsing to a scalar Decimal cohort.
- `DecimalInterchange::canonical()` preserves the current interchange format,
  canonicalizes the raw bits once, and is idempotent when applied repeatedly.
- `DecimalInterchange::is_canonical()` is the representation-level predicate
  paired with `canonical()`: it reports whether the current raw bits are already
  in canonical interchange form, including for special-value encodings.
- `DecimalInterchange::to_decimal()` decodes the wrapper using its stored
  interchange format, preserving special-value sign, qNaN/sNaN kind, and
  payload semantics represented by the raw bits.
- `DecimalInterchange::copy()` is a representation-preserving wrapper copy: it
  keeps the original raw bits and format unchanged, including non-canonical
  encodings.
- `DecimalInterchange::copy_sign` requires both operands to use the same
  interchange format; mixed-format sign-copy is rejected instead of silently
  reinterpreting bits across decimal32/64/128 layouts.
- `DecimalInterchange::copy_abs`, `copy_negate`, and `copy_sign` operate on the
  raw sign bit only; they preserve payload/coefficient continuation bits for
  NaNs, infinities, and finite encodings.

## Context And Flags

- `DecimalContext::new`
- `DecimalContext::try_new`
- `DecimalContext::decimal32`
- `DecimalContext::decimal64`
- `DecimalContext::decimal128`
- `DecimalContext::from_arithmetic_context`
- `DecimalRoundingMode::from_arithmetic`
- `DecimalRoundingMode::to_arithmetic`
- `DecimalFlags::new`
- `DecimalFlags::combine`
- `DecimalFlags::has_error`

`*_ctx` methods return `(Decimal, DecimalFlags)`. The current context layer
reports `lost_digits` when non-extended GDA arithmetic reduces an oversized
operand inexactly before applying the operation.
tracks rounded and inexact finite results, signaling-NaN invalid operations,
division by zero, undefined division, finite-result exponent bounds, clamp
padding, overflow, subnormal, and underflow status. The decimal32/64/128
constructors store the expected precision and exponent bounds, and finite
context-aware results are finalized against those bounds.

`DecimalContext` stores both the shared Luna-Flow `rounding` mode and a
decimal-native `decimal_rounding` mode. The shared field is the bridge for
`ArithmeticContext` and generic checked traits. The decimal-native field covers
the full GDA rounding baseline used by context-aware Decimal operations:
`HalfEven`, `HalfUp`, `HalfDown`, `Down`, `Ceiling`, `Floor`, `Up`, and
`ZeroFiveUp`. GDA-only modes such as `HalfUp`, `HalfDown`, and `ZeroFiveUp`
return `None` from `DecimalRoundingMode::to_arithmetic()` because the shared
Luna-Flow rounding enum intentionally does not claim those modes.

The `extended` named argument of `DecimalContext::new` selects the GDA
arithmetic mode and defaults to `true`. Most callers therefore get extended
arithmetic without extra configuration. Use
`DecimalContext::new(precision=17, extended=false)` when classic decNumber
subset behavior is required, including operand reduction, `lost_digits`, zero
and cohort cleanup, and classic transcendental rounding.

The exponent-bound implementation follows the GDA baseline rules and is
covered by the legal-row conformance run. Results above `e_max` produce an infinity and set
`overflow`, `rounded`, and `inexact`. Exact results below `e_min` set
`subnormal`; inexact subnormal results also set `underflow`. Clamp mode can pad
the coefficient with trailing zeros and lower the exponent while preserving the
numeric value, setting `clamped`.

Context-aware finite addition, subtraction, multiplication, and quantize-style
operations preserve the operation's preferred exponent when the result fits the
context. For example, exact decimal-scale results such as `1.20 + 3.40` can
remain in the `4.60` cohort instead of being canonicalized to `4.6`.

`fma_ctx` computes the multiplication exactly and applies context rounding only
after adding the third operand. `divide_integer` returns the integer part of
division with exponent `0` and reports `division_impossible` when the integer
quotient cannot fit the context precision. `remainder` uses that integer
quotient so the implemented finite cases follow `x - divide_integer(x, y) * y`.
`remainder_near` uses the nearest integer quotient, with ties resolved toward
the even quotient.

`power_ctx` is the context-aware GDA power entry point for the current
executable scalar `power.decTest` surface. It covers exact finite integer
exponents, rounded large integer exponents including million-scale cases,
terminating and non-terminating reciprocal results that finalize honestly
through the active context, exact `+1` and `-1` identities, NaN priority
propagation, infinite-base non-integer sign/domain cases, infinite-exponent
limit cases, finite positive non-integer powers, finite non-integer
operand-range invalid rows, and finite power-of-ten bases whose large integer
exponents force overflow or half-even underflow to zero. It also reports the
official math-function `Invalid_context` restriction rows. The only excluded
corpus rows are diagnostic `#` interchange/non-scalar placeholders; there is no
non-diagnostic scalar `power` gap.

`log10_ctx` is the context-aware GDA base-10 logarithm entry point. It uses the
fixed-point logarithm baseline, preserves NaN sign/payload quieting, maps
signed zero to `-Infinity`, maps positive infinity to `Infinity`, rejects
negative finite values and negative infinity with `invalid_operation`, and
rounds positive finite logarithms through the active context. It also reports
the official math-function `Invalid_context` restriction rows.

`exp_ctx` and `ln_ctx` are context-aware GDA mathematical-function entry
points. `exp_ctx` uses fixed-point exponential evaluation with decimal range
reduction and handles NaNs, infinities, finite signed zeros (`exp(0) = 1`),
general finite values, overflow/underflow boundaries, and official
math-function `Invalid_context` restriction rows. `ln_ctx` uses the fixed-point
logarithm baseline and handles NaNs, infinities, signed zeros, negative finite
invalid-operation cases, finite values exactly equal to one (`ln(1) = 0`), and
general positive finite values.

`next_plus`, `next_minus`, and `next_toward` return adjacent representable
decimals in the active context. They use `Etiny = e_min - precision + 1` for the
subnormal lattice, preserve quiet NaN sign/payload, quiet signaling NaNs with
`invalid_operation`, and handle powers of ten by stepping across the lower
cohort boundary rather than using the larger upper-side quantum. `next_toward`
chooses the direction from the second operand, preserves the left-hand
representation for equal finite values except for zero sign-copying, and reports
GDA overflow/underflow/subnormal/rounded/inexact/clamped status for directed
steps.

`sqrt_ctx` is the context-aware GDA square-root entry point used by decTest
execution. Exact finite roots are detected with integer decimal semantics and
then finalized through the context. Non-exact finite roots return a rounded
approximation and set `rounded` plus `inexact`; negative finite non-zero inputs
return quiet `NaN` with `invalid_operation`. `sqrt` is the checked convenience
wrapper.

`plus_ctx`, `minus_ctx`, and `abs_ctx` are the context-aware unary operations
used by GDA testcase execution. `copy` is the quiet no-context identity
operation: it preserves finite exponent/quantum and NaN sign, payload, and
qNaN/sNaN state. `copy_abs`, `copy_negate`, and `copy_sign` are
representation-level sign-copy operations and do not use a context.

`min_ctx`, `max_ctx`, `min_mag_ctx`, and `max_mag_ctx` are the GDA-style
context-aware minimum/maximum operations. They handle quiet/signaling NaNs,
use total-order tie breaking for equal numeric values, and return status flags.

The IEEE 754-2019 extrema family is separate from those compatibility methods:
`minimum_ctx`, `minimum_number_ctx`, `maximum_ctx`,
`maximum_number_ctx`, and the four `*_magnitude_ctx` variants preserve the
standard distinction between NaN-propagating and number-selecting behavior.
`quantum` exposes the stored decimal exponent; payload accessors replace or
quiet/signaling-mark NaN payloads without changing finite operands.

`logical_and`, `logical_or`, `logical_xor`, and `logical_invert` operate on GDA
logical operands: finite non-negative values with exponent `0` and coefficient
digits restricted to `0` and `1`. Invalid logical operands return quiet `NaN`
and set `invalid_operation`. `logical_invert` uses the active context precision
as the number of logical digits to invert.

`quantize` returns a value with the same exponent as the quantum operand.
`rescale` is currently an alias for `quantize`. `trim` strips insignificant
finite trailing zeros without first applying context rounding and leaves
special values unchanged. `reduce_ctx` first applies the
context-aware unary plus operation, then canonicalizes the resulting finite
cohort by removing trailing decimal zeros; zero is reduced to exponent `0` while
preserving its sign. `normalize_ctx` is an alias for `reduce_ctx`.
`to_integral_exact` quantizes to exponent `0` and reports rounded/inexact flags;
`to_integral_value` returns the same rounded value but suppresses those two
informational flags.

## Trait Surface

## Documentation Boundary

The public inventory is generated from the package interface; implementation kernels and benchmark thresholds remain private.

`Decimal` currently implements:

- `@def.Floating`
- `@arithmetic.ParseChecked`
- `@arithmetic.SqrtChecked`
- `@arithmetic.DivChecked`
- `@arithmetic.CompareChecked`
- `@arithmetic.PowNatChecked`
- `@arithmetic.PowIntChecked`
- `@luna-generic.Zero`
- `@luna-generic.One`
- `@luna-generic.AddMonoid`
- `@luna-generic.MulMonoid`
- `@luna-generic.AddGroup`
- `@luna-generic.Semiring`
- `@luna-generic.Ring`
- `Eq`, `Add`, `Sub`, `Mul`, `Div`, `Neg`, `Show`

Behavior note:

- `Decimal` does not implement separate transcendental or constant traits; its elementary functions are explicit context methods.
- Checked arithmetic is the intended integration surface with `Luna-Flow/arithmetic`.
- The package now exposes decimal32/64/128 interchange encode/decode APIs, but
  conformance status is reported by the current `gda_expr` run rather than by a
  blanket claim of support for every diagnostic row.

## Public Inventory Addendum

`DecCoeff` is package-private; the public representation boundary is `BigInt`.
Additional public entry points that must remain visible in the generated
interface are `Decimal::{from_string_ctx,parse,apply_ctx,div_checked,compare_checked,compare_total_ctx,compare_total_magnitude_ctx}`
and `DecimalInterchange::to_decimal_ctx`.

## Complete Public Interface

The following snapshot is the complete generated package interface for `0.7.0`. Public declarations are authoritative; prose above groups them by behavior.

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/decimal"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/def",
  "Luna-Flow/luna-generic",
  "moonbitlang/core/bigint",
  "moonbitlang/core/debug",
}

// Values

// Errors

// Types and methods
pub struct Decimal {
  // private fields
} derive(@debug.Debug)
pub fn Decimal::abs(Self) -> Self
pub fn Decimal::abs_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::acos_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::acosh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::add(Self, Self) -> Self
pub fn Decimal::add_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::apply_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::asin_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::asinh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::atan2_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::atan_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::atanh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
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
pub fn Decimal::cos_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::cosh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::cospi_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::div(Self, Self) -> Self
pub fn Decimal::div_checked(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::div_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::divide_integer(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exp10_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exp2_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exp_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::expm1_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exponent10(Self) -> Int
pub fn Decimal::fma_ctx(Self, Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::from_bigint(@bigint.BigInt, precision? : Int) -> Self
pub fn Decimal::from_bin_float(@bin_float.BinFloat, precision? : Int) -> Self
pub fn Decimal::from_double(Double, precision? : Int) -> Self
pub fn Decimal::from_float(Float, precision? : Int) -> Self
pub fn Decimal::from_int(Int, precision? : Int) -> Self
pub fn Decimal::from_interchange_hex(String, DecimalInterchangeFormat) -> Self?
pub fn Decimal::from_interchange_hex_with_encoding(String, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> Self?
pub fn Decimal::from_string(String, precision? : Int) -> Self?
pub fn Decimal::from_string_ctx(String, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::get_payload(Self) -> @bigint.BigInt
pub fn Decimal::hypot_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
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
pub fn Decimal::log1p_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log2_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
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
pub fn Decimal::pown_ctx(Self, Int, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::precision(Self) -> Int
pub fn Decimal::quantize(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::quantum(Self) -> Int
pub fn Decimal::quiet_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::reduce_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder_near(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rescale(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rootn_ctx(Self, Int, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rotate_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::same_quantum(Self, Self) -> Bool
pub fn Decimal::scaleb_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::set_payload(Self, @bigint.BigInt) -> Self
pub fn Decimal::set_payload_signaling(Self, @bigint.BigInt) -> Self
pub fn Decimal::shift_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sign(Self) -> @def.Sign
pub fn Decimal::signaling_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::sin_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sinh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sinpi_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sqrt(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sub(Self, Self) -> Self
pub fn Decimal::sub_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::tan_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::tanh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::tanpi_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_bin_float(Self, precision? : Int, mode? : @arithmetic.RoundingMode) -> @bin_float.BinFloat
pub fn Decimal::to_eng_string(String, DecimalContext) -> (String, DecimalFlags)
pub fn Decimal::to_integral_exact(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_integral_value(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_interchange_hex(Self, DecimalInterchangeFormat) -> (String, DecimalFlags)
pub fn Decimal::to_interchange_hex_with_encoding(Self, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> (String, DecimalFlags)
pub fn Decimal::to_sci_string(String, DecimalContext) -> (String, DecimalFlags)
pub fn Decimal::trim(Self) -> Self
pub fn Decimal::try_acos_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_acosh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_asin_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_asinh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_atan2_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_atan_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_atanh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_cos_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_cosh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_cospi_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_exp10_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_exp2_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_exp_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_expm1_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_hypot_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_ln_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log10_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log1p_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log2_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_power_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_pown_ctx(Self, Int, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_rootn_ctx(Self, Int, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_sin_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_sinh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_sinpi_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_tan_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_tanh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_tanpi_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
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
pub fn DecimalContext::ieee754(Self) -> Self
pub fn DecimalContext::is754version2019(Self) -> Bool
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

pub struct DecimalInterchange {
  // private fields
}
pub fn DecimalInterchange::canonical(Self) -> Self
pub fn DecimalInterchange::copy(Self) -> Self
pub fn DecimalInterchange::copy_abs(Self) -> Self
pub fn DecimalInterchange::copy_negate(Self) -> Self
pub fn DecimalInterchange::copy_sign(Self, Self) -> Self
pub fn DecimalInterchange::encoding(Self) -> DecimalInterchangeEncoding
pub fn DecimalInterchange::format(Self) -> DecimalInterchangeFormat
pub fn DecimalInterchange::from_decimal(Decimal, DecimalInterchangeFormat) -> (Self, DecimalFlags)
pub fn DecimalInterchange::from_decimal_with_encoding(Decimal, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> (Self, DecimalFlags)
pub fn DecimalInterchange::from_hex(String, DecimalInterchangeFormat) -> Self?
pub fn DecimalInterchange::from_hex_with_encoding(String, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> Self?
pub fn DecimalInterchange::is_canonical(Self) -> Bool
pub fn DecimalInterchange::to_decimal(Self) -> Decimal
pub fn DecimalInterchange::to_decimal_ctx(Self) -> (Decimal, DecimalFlags)
pub fn DecimalInterchange::to_hex(Self) -> String

pub(all) enum DecimalInterchangeEncoding {
  DPD
  BID
} derive(Eq)

pub(all) enum DecimalInterchangeFormat {
  Decimal32
  Decimal64
  Decimal128
} derive(Eq)
pub fn DecimalInterchangeFormat::context(Self) -> DecimalContext

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

// Type aliases

// Traits

```
<!-- generated-api-end -->
