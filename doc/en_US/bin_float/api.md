# @bin_float.BinFloat

This page tracks the current repository implementation and is written as the
`0.1.0` API baseline.

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

## Constants and Transcendental API

Direct exported helpers:

- `pi_for_precision`
- `tau_for_precision`
- `half_pi_for_precision`
- `quarter_pi_for_precision`
- `ln2_for_precision`
- `e_for_precision`
- `sqrt_bounds_for_precision`
- `sqrt_for_precision`
- `cbrt_for_precision`
- `exp_for_precision`
- `exp2_for_precision`
- `ln_for_precision`
- `log2_for_precision`
- `log10_for_precision`
- `sin_for_precision`
- `cos_for_precision`
- `tan_for_precision`
- `atan_for_precision`
- `atan2_for_precision`
- `asin_for_precision`
- `acos_for_precision`
- `sinh_for_precision`
- `cosh_for_precision`
- `tanh_for_precision`
- `asinh_for_precision`
- `acosh_for_precision`
- `atanh_for_precision`
- `pow_for_precision`
- `bin_floor_integer`
- `bin_ceil_integer`
- `bin_nearest_integer`

Domain notes:

- `sqrt_bounds_for_precision` and `sqrt_for_precision` require non-negative finite inputs.
- `ln*` require positive finite inputs.
- `asin` and `acos` require inputs inside `[-1, 1]`.
- `atanh` requires inputs inside `(-1, 1)`.
- `acosh` requires inputs `>= 1`.
- `pow_for_precision` aborts for non-integer exponents on non-positive bases.
- `tan_for_precision` aborts when the computed cosine vanishes at an odd multiple of `pi/2`.

## Trait Surface

`BinFloat` currently implements:

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
