# @decimal.Decimal

This page tracks the current repository implementation and is written as the
`0.2.0` API baseline.

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
- `@arithmetic.ParseChecked`
- `@arithmetic.SqrtChecked`
- `@arithmetic.DivChecked`
- `@arithmetic.CompareChecked`
- `@arithmetic.PowNatChecked`
- `@arithmetic.PowIntChecked`
- `Eq`, `Add`, `Sub`, `Mul`, `Div`, `Neg`, `Show`

Behavior note:

- This pass does not expose transcendental or constant traits from `Decimal`.
- Checked arithmetic is the intended integration surface with `Luna-Flow/arithmetic`.
