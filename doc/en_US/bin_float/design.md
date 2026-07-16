# `bin_float` Design

`bin_float` is the binary numerical core of `floating` 0.7.1. Its design has
two simultaneous goals: preserve exact integer/dyadic semantics at arbitrary
precision, and reproduce the declared IEEE 754-2019 behavior when a bounded
`BinaryContext` is supplied. Public names are fixed by
`src/bin_float/pkg.generated.mbti`; coefficient layouts, dispatch thresholds,
and scratch storage remain implementation details.

## Design Contract

The package separates three concerns that are often mixed in a floating-point
implementation:

1. `BinCoeff` performs exact non-negative integer arithmetic.
2. `BinFloat` represents a dyadic value or an explicit special state.
3. `BinaryContext` applies a target precision, exponent range, rounding mode,
   tininess policy, and status flags to one operation.

This separation is the main correctness device. Kernel algorithms may change
the cost of producing an exact coefficient, but only contextual finalization
may change the represented floating-point result.

## Representation And Invariants

A finite value denotes

```text
(-1)^negative × coefficient × 2^exponent2
```

with an explicit working precision. A nonzero finite coefficient is odd because
normalization removes powers of two and moves them into `exponent2`. The sign is
stored independently, so positive and negative zero remain distinguishable.
Infinity, quiet NaN, signaling NaN, and NaN payloads bypass the finite model and
remain observable.

On non-JS targets, `BinCoeff` selects an inline 64/128-bit representation or a
little-endian array of 32-bit limbs. The JavaScript target uses host `bigint`
behind the same public contract. No caller can observe which storage form or
coefficient algorithm was selected.

## Standard Alignment

The IEEE-facing path follows a fixed operation pipeline:

```text
operands + immutable BinaryContext
  -> classify NaN, infinity, zero, and invalid combinations
  -> compute an exact dyadic/rational result or certified enclosure
  -> round once in the requested direction
  -> apply exponent bounds and before/after-rounding tininess
  -> return value + BinaryFlags
```

`BinaryInterchange` is the only fixed-width encoding boundary. It decodes and
encodes binary16, binary32, binary64, and binary128 without routing through a
host `Float` or `Double`. Context arithmetic and interchange therefore share
one value model while keeping format width explicit.

The conformance claim is deliberately narrower than the implementation. The
pinned TestFloat matrix covers add, subtract, multiply, divide, and square root
for the four interchange formats, five rounding directions, and both tininess
policies. Pinned MPFR 4.2.2 data covers the documented square-root, integer-
power, and elementary-function boundary. Passing these finite matrices does not
claim every IEEE 754 operation or every real input.

## Coefficient Algorithm Selection

Dispatch depends on operand size, shape, target, and algorithm preconditions;
it is not a single size cutoff. For multiplication, `n` is the shorter operand
length in 32-bit limbs and `m` is the longer length.

| Decision | Condition | Selected path | Reason |
| --- | --- | --- | --- |
| Inline/schoolbook | `n < 96` | fixed-width or schoolbook | setup and allocation dominate at small sizes |
| Transform | `n` reaches the target NTT threshold and CRT bounds fit | two-prime Montgomery NTT + CRT | asymptotically lower work for large dense products |
| Oversized transform | a full transform does not fit but overlap is legal | overlap-add NTT | retain transform scaling without violating length bounds |
| Unbalanced | `m > 2n` after transform checks | block the longer operand | avoid padding a highly rectangular product |
| Large balanced | `n` reaches the target Toom-3 threshold | Toom-3 | reduce recursive multiplication count |
| Medium balanced | otherwise | scratch-backed Karatsuba | lower asymptotic cost without transform setup |

Squaring has its own schoolbook kernel and thresholds because cross terms are
symmetric. The current crossover parameters are:

| Target | Karatsuba | Toom-3 / NTT multiply | NTT square | recursive-square entry |
| --- | ---: | ---: | ---: | ---: |
| native | 96 | 2,048 | 768 | 512 |
| LLVM | 96 | 2,048 | 768 | 768 |
| Wasm / Wasm-GC | 96 | 4,096 | 3,072 | 768 |

These values are empirical policy, not semantic constants. Exact reconstruction
bounds are checked before NTT selection; failure selects an exact integer
fallback rather than accepting a transform result outside its proof range.

Division uses a similarly staged selector:

- inline or one-limb division for the smallest denominator;
- normalized Knuth division below 48 denominator limbs;
- Burnikel-Ziegler block division from 48 limbs;
- reciprocal Newton division from 1,024 limbs;
- a bounded high-product search for short near-equal quotients where applicable.

Every path returns quotient and remainder satisfying `n = qd + r` and
`0 <= r < d`. Square root uses fixed-width kernels through 512 bits and a
divide-and-conquer path above that boundary. GCD uses Euclid on small inputs and
Lehmer batching once leading-limb quotient prediction can amortize divisions.

## Certified Elementary Functions

Elementary functions do not accept a repeated approximate value as evidence of
correct rounding. A `try_*_ctx` function constructs directed lower and upper
enclosures at a working precision, rounds both endpoints under the target
context, and accepts the result only when both the value and flags agree.

Refinement begins with target precision plus guard bits, permits at most 12
attempts, and grows the working precision by `max(32, work / 2)`. Failure to
certify range reduction or the target rounding cell returns a structured
`ArithmeticError::CertificationFailure`. The non-`try` convenience methods
unwrap the same proof-producing path; they do not switch to an unchecked host
transcendental function.

## Optimization And Boundary Tuning

The switch boundaries are chosen by the unified Maremark benchmark hierarchy,
not by asymptotic complexity alone. Measurements distinguish balanced,
unbalanced, sparse, dense, and square shapes; target-specific policies are kept
because allocation, integer lowering, and transform constants differ across
native, LLVM, Wasm, Wasm-GC, and JavaScript.

An optimization is accepted only if it satisfies two independent conditions:

1. exact differential/property tests agree across the algorithms on and around
   every crossover; and
2. confirmatory measurements show a practical benefit under the repository's
   paired benchmark protocol.

This rule explains why the dispatcher retains simple algorithms below their
measured crossover and why every advanced path has an exact fallback. A tuning
decision may move a boundary, but it cannot move the numerical contract.

## Complexity And Trade-offs

For balanced `n`-limb operands, schoolbook multiplication is `O(n^2)`,
Karatsuba is `O(n^log2(3))`, Toom-3 is `O(n^log3(5))`, and NTT convolution is
approximately `O(n log n)` with larger constants and temporary storage.
Burnikel-Ziegler and Newton division approach the multiplication cost at large
sizes. Shape-aware dispatch and scratch arenas reduce allocation on hot paths,
while immutable public values prevent temporary storage from escaping.

The implementation therefore optimizes expected cost subject to exactness,
not exactness subject to speed. Thresholds, NTT primes, limb layout, and arena
capacity may change in a patch release; normalized values, contextual rounding,
flags, and interchange behavior may not change without an API/semantic change.

## 0.7.1 Semantic Preservation Proof

The optimization boundary is the exact coefficient or exact discarded-bit
calculation. It does not cross the contextual finalizer. For far-exponent
addition, `binary_exact_top(c, e)` orders exact magnitudes before alignment,
and the split operation preserves the first discarded bit plus the sticky OR of
all later bits. Those are precisely the inputs consumed by the existing
rounding rule, so the fast path has the same rounded value and flags as the
fully aligned path. Every advanced coefficient path retains an exact fallback
when its proof precondition fails.

The semantic acceptance condition is observational equivalence at the
`BinFloat` boundary: equal class, sign, coefficient/exponent, precision,
rounding result, flags, and interchange bits. TestFloat, MPFR, boundary tests,
and differential tests establish this condition for the declared matrices;
Maremark only decides whether the private route is worth its setup cost.

## Evidence Map

- [API reference](./api.md) defines the callable 0.7.1 surface.
- [Tutorial](./tutorial.md) gives recommended construction and context flows.
- [Conformance](./conformance.md) states the pinned TestFloat/MPFR claim and its
  exclusions.
- [Performance](./performance.md) records target-specific dispatch evidence and
  the immutable release comparison baseline.
