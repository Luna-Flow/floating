# @ball_float.BallFloat

This page tracks the current repository implementation and is written as the
`0.2.0` API baseline.

## Semantics

`BallFloat` represents the enclosure:

`center +/- radius`

The implementation stores that enclosure as lower and upper `BinFloat` bounds
and prefers correctness of containment over returning the narrowest possible
interval.

## Construction

- `BallFloat::new`
- `BallFloat::exact`
- `BallFloat::from_int`
- `BallFloat::from_bigint`
- `BallFloat::from_float`
- `BallFloat::from_double`

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

- `add`
- `sub`
- `mul`
- `div`

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
- This pass does not expose non-integer power, transcendental functions, calculus, matrices, complex balls, or special functions.

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
