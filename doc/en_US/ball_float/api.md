# `ball_float` API

## Stability

Bare/decorated interval construction, relations, forward arithmetic, contexts,
and flags are supported `0.5.0` APIs. Reverse operations and guaranteed
tightness are outside the contract.

This page tracks the current repository implementation and is written as the
`0.5.0` API baseline. It covers `@ball_float.BallFloat`,
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
