# `decimal` Design Notes

This page tracks the current repository implementation and is written as the `0.1.0` design baseline.

## Representation

Finite values are stored as:

- `coefficient : BigInt`
- `exponent10 : Int`
- `precision_ : Int`

with the intended meaning:

`coefficient * 10^exponent10`

## Normalization Invariant

Finite non-zero values are canonicalized by stripping all removable powers of `10` from the coefficient and compensating them into `exponent10`.

That gives:

- stable string formatting
- unique zero representation
- consistent decimal semantics

## Decimal Parsing

`Decimal::from_string` delegates its preprocessing to `@internal.split_decimal_string`, which:

- parses sign
- removes the decimal point into a digit string
- folds scientific notation into an exponent adjustment

The package then builds a normalized decimal value from that parsed form.

## Precision and Rounding

When a coefficient has more decimal digits than the requested precision, the implementation divides by the appropriate power of `10` and applies the selected rounding mode.

## Relationship to `bin_float`

`Decimal` is the repository’s decimal-first package, while `BinFloat` is the binary-first package.

- binary to decimal preserves the exact finite binary representation currently stored
- decimal to binary may approximate non-dyadic values

That distinction should be made explicit whenever conversion behavior is documented.
