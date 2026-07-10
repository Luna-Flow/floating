# `ball_float` Design Notes

This page tracks the current repository implementation and is written as the `0.4.0` design baseline.

## Representation

`BallFloat` stores:

- `center_ : BinFloat`
- `radius_ : BinFloat`
- `precision_ : Int`

and interprets the value as:

`[center - radius, center + radius]`

## Radius Invariant

The constructor validates that the radius is:

- finite
- not NaN
- non-negative

This is the core representation invariant for the package.

When a stored center is rounded to a lower precision, the constructor and precision-retuning path widen the radius by the induced center displacement. That keeps the represented interval from shrinking during quantization.

## Sign Semantics

`BallFloat::sign` is not the sign of the center alone.

- if the radius is zero, it matches the exact embedded center
- if the entire ball is strictly positive, it returns `Positive`
- if the entire ball is strictly negative, it returns `Negative`
- otherwise it returns `Zero`

That makes `Sign::Zero` partly a "crosses zero" signal for this package.

## Arithmetic Model

The arithmetic formulas are enclosure-oriented:

- addition and subtraction widen by adding radii
- multiplication uses a radius propagation formula based on center magnitude and error terms
- division rejects denominator balls that contain zero
- every arithmetic result also widens for the displacement introduced when the output center is quantized back to the requested precision

This package therefore behaves differently from exact scalar representations even when it shares some method names.

## Why There Is No Total Order

`BallFloat` provides:

- overlap checks
- separation checks
- definitely-less / definitely-greater relations

It does not provide a total scalar order because uncertainty intervals do not generally admit one without collapsing their semantics.
