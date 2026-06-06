# @ball_float.BallFloat

This page tracks the current repository implementation and is written as the
`0.1.0` API baseline.

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
- `BallFloat::from_decimal`

Constraints:

- The center must be finite.
- The radius must be finite and non-negative.
- `exact`, `from_float`, `from_double`, and `from_decimal` abort on non-finite source values.

Notes:

- Center retuning widens the stored radius by the induced center displacement so the enclosure never shrinks.
- Radius quantization always rounds outward.
- `from_decimal` constructs a `BinFloat`-based enclosure; it is not an exact decimal wrapper.

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
- `maybe_overlap`
- `separated_from`
- `definitely_lt`
- `definitely_gt`
- `compare`
- `min`
- `max`
- `clamp`

Notes:

- `compare` aborts on overlapping or otherwise incomparable intervals.
- `clamp` aborts if `min` and `max` are not themselves ordered.

## Arithmetic and Transcendental Behavior

- `add`
- `sub`
- `mul`
- `div`
- `pow`

Supported operators:

- `+`
- `-`
- `*`
- `/`
- unary `-`

Domain notes:

- Division aborts if the denominator enclosure contains zero.
- `pow` aborts if the exponent enclosure is not exact.
- `pow` with a non-integer exponent aborts unless the base interval is strictly positive.
- `sqrt`, `ln`, `log2`, `log10`, `asin`, `acos`, `acosh`, and `atanh` abort outside their documented domains.
- `atan2` now widens to the full principal-angle enclosure `[-pi, pi]` when the input rectangle crosses the negative-axis branch cut or contains the origin, because enclosure correctness takes priority over a narrower but unsound result.

## Trait Surface

`BallFloat` currently implements:

- `@def.Floating`
- `@arithmetic.Constants`
- `@arithmetic.Sqrt`
- `@arithmetic.Cbrt`
- `@arithmetic.Radical`
- `@arithmetic.Exponential`
- `@arithmetic.Logarithmic`
- `@arithmetic.Power`
- `@arithmetic.Trigonometric`
- `@arithmetic.InverseTrigonometric`
- `@arithmetic.Hyperbolic`
- `@arithmetic.InverseHyperbolic`
- `@luna-generic.Zero`
- `@luna-generic.One`
- `@luna-generic.Num`
- `@luna-generic.Semiring`
- `@luna-generic.Ring`
- `@luna-generic.Field`
- `Eq`, `Add`, `Sub`, `Mul`, `Div`, `Neg`, `Show`
