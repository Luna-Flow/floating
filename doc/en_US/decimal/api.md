# @decimal.Decimal

This page tracks the current repository implementation and is written as the
`0.4.0` API baseline plus the first GDA-representation migration.

## Representation

Finite values are stored as:

`(-1)^negative * magnitude * 10^exponent10`

with an attached working `precision`.

The public `coefficient()` observer returns the signed coefficient for
compatibility with the existing scalar semantics. Use `magnitude()` and
`is_negative()` when the sign must be inspected separately. This matters for
GDA-style values such as `-0`, where the mathematical coefficient is zero but
the representation still carries a negative sign.

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

Notes:

- `compare` aborts on `NaN`.
- `compare_ctx(lhs, rhs, ctx)` returns a decimal `-1`, `0`, `1`, or quiet `NaN`
  plus flags. Quiet NaNs produce quiet `NaN` without invalid-operation status;
  signaling NaNs set `invalid_operation`.
- `compare_signal_ctx(lhs, rhs, ctx)` has the same numeric result shape as
  `compare_ctx`, but any NaN operand sets `invalid_operation`.
- `clamp` aborts if the bounds are unordered or `NaN`.
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
- `ln_ctx`
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
- `to_integral_exact`
- `to_integral_value`
- `logical_and`
- `logical_or`
- `logical_xor`
- `logical_invert`
- `to_interchange_hex`
- `to_bin_float`

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
- `DecimalContext::exact`
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

The exponent-bound implementation is a GDA baseline rather than full
conformance. Results above `e_max` currently produce an infinity and set
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
official math-function `Invalid_context` restriction rows. The remaining
conformance gap is diagnostic interchange/non-scalar coverage rather than a
non-diagnostic scalar `power` subset.

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

`DecCoeff` provides `from_bigint`, `to_bigint`, `digits10`, `is_zero`, and
`to_string`. Additional public entry points that must remain visible in the
generated interface are `Decimal::{from_string_ctx,parse,apply_ctx,div_checked,compare_checked,compare_total_ctx,compare_total_magnitude_ctx}`
and `DecimalInterchange::to_decimal_ctx`.
