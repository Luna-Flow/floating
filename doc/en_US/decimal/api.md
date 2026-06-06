# @decimal.Decimal

This page tracks the current repository implementation and is written as the
`0.1.0` API baseline.

## Representation

Finite values are stored as:

`coefficient * 10^exponent10`

with an attached working `precision`.

## Constructors and Parsing

- `Decimal::make`
- `Decimal::zero`
- `Decimal::one`
- `Decimal::inf`
- `Decimal::nan`
- `Decimal::from_int`
- `Decimal::from_bigint`
- `Decimal::from_float`
- `Decimal::from_double`
- `Decimal::from_string`
- `Decimal::from_bin_float`

Notes:

- Finite public constructors normalize by removing removable powers of `10`.
- `from_string` accepts plain decimal and scientific notation.
- Invalid strings return `None`.

## Access, Normalization, and Comparison

- `classify`
- `precision`
- `sign`
- `coefficient`
- `exponent10`
- `is_zero`
- `normalized`
- `with_precision`
- `compare`
- `min`
- `max`
- `clamp`

Notes:

- `compare` aborts on `NaN`.
- `clamp` aborts if the bounds are unordered or `NaN`.

## Arithmetic and Conversion

- `neg`
- `abs`
- `add`
- `sub`
- `mul`
- `div`
- `to_bin_float`

Supported operators:

- `+`
- `-`
- `*`
- `/`
- unary `-`

Conversion notes:

- Decimal-to-binary conversion may be approximate for non-dyadic values.
- Binary-to-decimal conversion is exact for the currently stored finite `BinFloat` value.

## Trait Surface

`Decimal` currently implements:

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

Behavior note:

- The transcendental and constant traits are exposed through the shared arithmetic interfaces; their implementations route through the package's precision-aware decimal/binary bridge rather than through a separate decimal-only kernel.
