# `internal` Design Notes

This page tracks the current repository implementation and is written as the `0.2.0` design baseline.

## Purpose

`@internal` exists to keep low-level numeric machinery out of the public representation packages.

It centralizes:

- small `BigInt` utility constructors
- sign extraction
- base-2 and base-10 normalization helpers
- precision-reduction rounding helpers
- decimal string preprocessing

## Why It Is a Separate Package

Without `@internal`, the repository would duplicate the same logic in:

- `bin_float`
- `decimal`
- `ball_float` support paths

That would make it harder to keep rounding and normalization semantics aligned.

## What It Guarantees Today

The package provides the building blocks for:

- unique zero normalization
- factor stripping for canonical finite values
- power generation for base conversion
- precision trimming with explicit rounding modes
- decimal parsing shared by `Decimal::from_string`

## Stability Boundary

`@internal` is documented, but it is not intended to be a long-term stable external package contract. It should be treated as implementation support for the repository’s current numeric packages.
