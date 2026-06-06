# `def` Design Notes

This page tracks the current repository implementation and is written as the `0.1.0` design baseline.

## Purpose

`@def` is the protocol layer for the repository. It exists to describe the shared semantic surface of the current floating packages without committing the library to one representation strategy.

## Why `Floating` Is Intentionally Small

The current `Floating` trait only covers:

- classification
- sign
- precision inspection
- precision retuning
- normalization

It does **not** include:

- arithmetic operators
- total ordering
- parsing
- formatting
- static constructors such as `from_int`

This is deliberate.

## Why Arithmetic Is Not In the Trait

MoonBit already has operator traits such as `Add`, `Sub`, `Mul`, `Div`, and `Neg`. Repeating those requirements inside `Floating` would blur the difference between:

- a semantic floating capability boundary
- a concrete arithmetic capability set

The current code keeps those concerns separate.

## Why Comparison Is Not in the Trait

`bin_float` supports a finite-value comparison method. `decimal` has exact decimal semantics. `ball_float`, however, is enclosure-based and does not model a total order in the same sense.

If `Floating` required total comparison, the trait would either:

- misrepresent `ball_float`, or
- force an artificial comparison contract

The repository therefore keeps comparison outside the shared trait.

## Shared Semantic Vocabulary

`@def` establishes the repository-wide vocabulary for:

- `Sign`
- `FpClass`
- `RoundingMode`
- the meaning of `precision`
- the meaning of `normalized`

That lets `bin_float`, `decimal`, and `ball_float` align names even when their internal representations differ.

## Role in Future Layering

In the current repository, `@def` is already the correct place for minimal protocol-style abstractions. Higher-level mathematical capability traits, if introduced later, should build on this layer rather than replacing it.
