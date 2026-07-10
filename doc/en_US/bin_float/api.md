# @bin_float.BinFloat

This page tracks the current repository implementation and is written as the
`0.4.0` API baseline.

## Representation

Finite values are stored as:

`significand * 2^exponent2`

with an attached working `precision`.

## Constructors and Stored Form

- `BinFloat::make`
- `BinFloat::zero`
- `BinFloat::one`
- `BinFloat::inf`
- `BinFloat::nan`
- `BinFloat::from_int`
- `BinFloat::from_bigint`
- `BinFloat::from_float`
- `BinFloat::from_double`

Notes:

- Public finite constructors normalize the stored representation.
- `compare` aborts on `NaN`.
- `sign()` currently returns `Sign::Zero` for `NaN`.

## Access, Normalization, and Comparison

- `classify`
- `precision`
- `sign`
- `significand`
- `exponent2`
- `is_zero`
- `normalized`
- `with_precision`
- `ulp`
- `compare`
- `min`
- `max`
- `clamp`

Notes:

- `clamp` aborts if the bounds are unordered or `NaN`.
- `ulp()` returns `NaN` on non-finite inputs.

## Arithmetic and Conversion

- `neg`
- `abs`
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

Special-value notes:

- `NaN` generally propagates.
- `inf - inf` with opposite signs becomes `NaN`.
- Division by zero produces `inf` or `NaN` depending on the numerator class.

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
