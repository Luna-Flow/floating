# `bin_float` Design Notes

This page tracks the current repository implementation and is written as the `0.1.0` design baseline.

## Representation

Finite values are stored as:

- `significand : BigInt`
- `exponent2 : Int`
- `precision_ : Int`

The intended meaning is:

`significand * 2^exponent2`

along with an explicit floating classification.

## Normalization Invariant

Finite non-zero values are normalized by stripping all removable powers of `2` from the significand and compensating them into `exponent2`.

That gives the package:

- unique zero representation
- canonical finite forms
- stable formatting and comparison behavior

## Precision Control

When a finite value has more significant binary bits than the requested precision, the implementation:

1. computes the excess bit count
2. rounds by a shift operation
3. rebuilds a normalized finite value

This keeps constructor and `with_precision` behavior aligned.

## Comparison Strategy

Finite comparison works by aligning exponents to a common target and comparing the expanded significands. The package refuses to define order for `nan`.

## Why `ulp` Exists

`ulp` is included because a binary representation often needs a representation-local notion of spacing, even before any higher-level numerical analysis layer exists.
