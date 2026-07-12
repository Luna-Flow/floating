# `decimal` Design

## Responsibility And Representation

`decimal` owns arbitrary-precision decimal values, General Decimal Arithmetic
contexts and flags, and decimal32/64/128 interchange. Finite values store an
independent sign, non-negative `BigInt` coefficient, base-10 exponent, and
working precision. Signed zero, infinities, qNaN/sNaN, and payloads are part of
the observable representation.

Parsing and quantum-sensitive operations may preserve trailing coefficient
zeros and the exponent cohort. `normalized()`/`reduce_ctx()` remove removable
powers of ten without changing the mathematical value. Numeric equality and
`compare_total` are therefore different relations.

## Coefficient And Rounding Algorithms

The package-local `DecCoeff` is a little-endian base-1000 array. It implements
digit shifts, add/subtract, schoolbook multiplication, long division, exact
powers, and rounding helpers without exposing the storage type. Public
coefficients remain `BigInt`; crossing that boundary is intentional and unlike
the binary stack's `BinCoeff` migration.

Context operations first classify special values, compute the finite
coefficient/exponent result, round according to one of the eight decimal modes,
then finalize exponent, subnormal, clamp, and status behavior. FMA keeps the
product exact until the addition. Square root and transcendental operations use
guard digits and iterative/series refinement before a single context
finalization. Quantize fixes the target exponent and fails with
`invalid_operation` when the resulting coefficient cannot fit the context.

## Context And Effect Boundary

`DecimalContext` is immutable input; `*_ctx` functions are pure transformations
returning `(Decimal, DecimalFlags)`. Flags are explicit accumulated data, not
ambient mutable state. Convenience operators omit flags and therefore are not a
replacement when GDA status is relevant. `DecimalInterchange` owns hexadecimal
decimal32/64/128 encoding and reports conversion flags.

## Capability Boundary

The public surface includes arithmetic, FMA, integer division/remainders,
quantize/rescale, total comparison, logical digits, adjacent values,
classification, formatting, interchange, and elementary functions. The GDA
claim covers every legal executable scalar row in the pinned `official` and
`official0` corpora: 0 failures, 0 unsupported, and 0 legacy-condition rows.
The only excluded rows are `#` placeholder/non-scalar invalid inputs. This is a
complete claim for the represented legal corpus, not for arbitrary resource
sizes or directives outside that corpus. The base-1000 kernel is correctness-
oriented and does not currently select Karatsuba/Toom/FFT multiplication.

## Complexity And Why This Kernel

With `n` base-1000 limbs, addition, comparison, shifts, and normalization are
`O(n)`. Schoolbook multiplication and long division are `O(n²)`. Base-1000
digits keep carry handling, decimal parsing, and GDA rounding easy to audit,
while the public boundary remains `BigInt` and does not expose storage layout.

The implementation deliberately does not yet pay the complexity and tuning cost
of Karatsuba, Toom, or FFT: current Decimal workloads are bounded by context
precision and flag/cohort semantics. This is a performance trade-off, not a
semantic limitation; a future kernel can add dispatch without changing the
`Decimal` or `DecimalContext` contract.

## Responsibility And Representation

The value model, cohort rules, and special-value states are part of the concrete Decimal contract rather than the coefficient kernel.

## Context And Effect Boundary

`DecimalContext` is explicit input and `DecimalFlags` is explicit output; no ambient rounding state is used.
