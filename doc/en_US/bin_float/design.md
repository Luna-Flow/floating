# `bin_float` Design

This page describes the current development implementation. Public names are
defined by `src/bin_float/pkg.generated.mbti`; benchmark thresholds are
implementation details, not API guarantees.

## Responsibility And Representation

`bin_float` owns arbitrary-precision binary scalars, IEEE-style contexts and
interchange, and the non-negative `BinCoeff` kernel shared by the binary and
interval stacks. A finite value is sign × coefficient × `2^exponent2`, with a
working precision. Powers of two are stripped from nonzero coefficients;
signed zero, infinities, qNaN/sNaN, and NaN payloads remain observable.

Non-JS targets store `BinCoeff` as inline 64/128-bit values or little-endian
32-bit limbs. JS uses host `bigint` behind the same API. No representation is
promised to callers, and `Decimal`/`Semantic` intentionally retain `BigInt`.

## Coefficient Algorithms

Multiplication dispatches by shorter operand length and shape:

- schoolbook below 96 limbs;
- Karatsuba from 96 limbs;
- unbalanced block multiplication when the longer operand exceeds twice the
  shorter operand;
- Toom-3 for large balanced inputs when NTT is not selected;
- a two-prime Montgomery NTT plus CRT when the transform and coefficient bound
  fit, with overlap-add for oversized unbalanced inputs.

Native/LLVM select Toom-3 and NTT multiplication at 2,048 limbs and NTT square
at 768 limbs. Wasm/Wasm-GC use 4,096 and 3,072 respectively. These values are
benchmark-tuned and may change. Squaring has a dedicated schoolbook path.

Division uses a word path for one limb, Knuth division below 48 divisor limbs,
Burnikel–Ziegler from 48 limbs, and reciprocal Newton iteration from 1,024
limbs. Short near-equal divisions first try a bounded high-product search.
Square root uses fixed-width kernels through 512 bits and a recursive
divide-and-conquer algorithm above that. GCD uses Euclid for small inputs and
Lehmer batching for large inputs.

## Floating-Point Algorithms

Context arithmetic resolves special values, forms an exact dyadic or rational
result, rounds once from quotient/remainder plus guard/sticky information, then
applies exponent bounds and the selected before/after tininess rule. Integer
power first attempts bounded approximations and an exact can-round decision;
the exact coefficient-power route is the permanent correctness fallback.

`BinaryInterchange` encodes and decodes binary16/32/64/128. The arbitrary-
precision scalar is not itself limited to those formats.

## Complexity And Trade-offs

For `n` limbs, schoolbook multiplication is `O(n²)`, Karatsuba is
`O(n^log2(3))`, Toom-3 is `O(n^log3(5))`, and the NTT path is approximately
`O(n log n)` with larger constants and temporary buffers. The dispatcher uses
the simpler method for small operands, shape-aware blocking for unbalanced
operands, and transforms only after measured crossover points. This keeps the
common path allocation-light while scaling large coefficients.

Knuth division is `O(nm)` in the operand dimensions; Burnikel–Ziegler and
reciprocal Newton move large division toward the multiplication cost `M(n)`.
The fixed-width square-root kernel avoids setup overhead through 512 bits, while
divide-and-conquer is selected only above that boundary. Every fast path has an
exact integer fallback, so dispatch cannot change public results.

## Capability Boundary

The verified IEEE matrix is add/sub/mul/div/sqrt over binary16/32/64/128, five
rounding directions, and both tininess modes, plus the documented MPFR sqrt and
integer-power witnesses. This is not a claim of complete IEEE 754 coverage.
NaNs do not participate in ordinary ordered comparison. Algorithm thresholds,
limb layout, NTT primes, scratch arenas, and exact fallback selection are not
stable API. See [Conformance](./conformance.md) for the exact evidence boundary.

## Mathematical Model

All finite values reduce to a signed coefficient and a power of two; special values are dispatched before this model is used.

## Evidence Map

[Conformance](./conformance.md) records the pinned TestFloat/MPFR claim. [Performance](./performance.md) records target-specific dispatch evidence. Neither page expands the public API beyond the generated interface.
