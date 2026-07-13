# `decimal` Design

## Responsibility And Representation

`decimal` owns arbitrary-precision decimal values, General Decimal Arithmetic
contexts and flags, and decimal32/64/128 interchange. Finite values have an
independent sign, coefficient, base-10 exponent, cohort, and working
precision. Signed zero, infinities, qNaN/sNaN, and payloads remain observable.

The coefficient kernel is private. It uses canonical little-endian base-1e9
`UInt` limbs with `UInt64` intermediates. A one-limb coefficient is stored in
an inline representation; larger values use a limb-backed array. Zero has one
canonical form, limb arrays have no leading zero, and decimal digit counts are
exact. Public APIs do not expose this layout. BigInt is retained only at public
conversion/serialization boundaries and for tests oracles; Decimal hot paths
operate directly on the private coefficient value.

Parsing and quantum-sensitive operations may preserve trailing coefficient
zeros and the exponent cohort. `normalized()`/`reduce_ctx()` remove removable
powers of ten without changing the mathematical value. Numeric equality and
`compare_total` are therefore different relations.

## Coefficient And Rounding Algorithms

Small operations use inline arithmetic, checked add/subtract, Comba/schoolbook
multiplication, a dedicated square path, single-limb division, exact powers,
GCD, integer square root/remainder, and exponentiation by squaring. Sparse
operands use compressed non-zero products; strongly unbalanced operands are
split into balanced blocks once the short side is large enough, with a single
normalized accumulator retained for smaller shapes.

Balanced multiplication is selected by operand length, density, balance ratio,
square shape, and target-specific thresholds. The production ladder is
schoolbook, Karatsuba, Toom-3, and dual-modulus NTT convolution. Karatsuba and
Toom-3 use bounded recursion and scratch storage; Toom-3 keeps signed
intermediates private and checks exact division during interpolation. NTT uses
smaller decimal working digits, CRT reconstruction, and explicit length and
coefficient bounds, falling back when its preconditions are not met.

Division selects word division, normalized Knuth Algorithm D, Burnikel-Ziegler
block recursion, or Newton reciprocal division. Every path checks quotient and
remainder invariants and may fall back to a safer algorithm. Scratch arenas
reuse temporary limb buffers without allowing a rewound buffer to escape.

Context operations classify special values, compute the finite
coefficient/exponent result, round according to one of the eight decimal modes,
then finalize exponent, subnormal, clamp, and status behavior. FMA keeps the
product exact until the addition. Square root and transcendental operations
use coefficient-native guard digits and iterative/series refinement before one
context finalization. Quantize fixes the target exponent and reports
`invalid_operation` when the resulting coefficient cannot fit the context.

## Context And Interchange Boundary

`DecimalContext` is immutable input; `*_ctx` functions are pure transformations
returning `(Decimal, DecimalFlags)`. Flags are explicit accumulated data, not
ambient mutable state. `DecimalInterchange` provides a shared Decimal semantic
layer for DPD and BID decimal32/64/128 encoding, including canonicalization,
non-canonical finite encodings, NaN payloads, infinities, and signed zero.
Encoding selection does not duplicate arithmetic or rounding semantics.

## Capability And Conformance Boundary

The public surface includes arithmetic, FMA, integer division/remainders,
quantize/rescale, total comparison, logical digits, adjacent values,
classification, formatting, interchange, and elementary functions. The GDA
claim is tracked separately from the IEEE gate: pinned `official` and
`official0` corpora cover legal scalar behavior, while independent IEEE
decimal32/64/128 vectors cover operations, flags, special values, total order,
format conversion, and DPD/BID bit patterns. Both gates require zero failed or
unsupported cases on supported targets.

The oracle matrix is layered. Mandatory decimal operations use the DPD-to-BID
conversion path around Intel RDFP when installed; nearest-even `exp`/`ln`/
`log10` use libmpdec allcr=1 with Arb as a secondary check; square root uses
RDFP with libmpdec fallback; integer powers use exact integer/rational
arithmetic; and the remaining elementary families use adaptive Arb intervals
with MPFR as a secondary implementation. Result values/bits and IEEE flags are
separate records. A fixed-seed generator targets at least 100,000 cases per
family and rotates format, rounding, tininess, boundary class, coefficient
scale, and operand shape. Optional external tools are never silently replaced
by a weaker oracle.

## Complexity And References

For `n` base-1e9 limbs, addition, comparison, shifts, normalization, and
single-limb division are `O(n)`. Schoolbook and Knuth division are `O(n²)`;
Karatsuba, Toom-3, NTT, Burnikel-Ziegler, and Newton are selected only where
their measured crossover justifies the additional setup cost. Canonicalization
and exact carry checks are part of every algorithm boundary, so optimization
cannot change Decimal rounding or cohort semantics.

Algorithm and semantic references are Knuth, *The Art of Computer
Programming*, Vol. 2 (Algorithm D); Karatsuba multiplication; Bodrato's
Toom-Cook interpolation; Burnikel-Ziegler, *Fast Recursive Division*;
Brent-Zimmermann, *Modern Computer Arithmetic*; Cowlishaw's General Decimal
Arithmetic specification and decNumber; and IEEE 754-2019 / ISO 60559.

## Evidence Map

[IEEE conformance](./conformance.md), [`decimal_gda` conformance](../decimal_gda/conformance.md), and [performance](./performance.md) are separate evidence ledgers. This separation prevents GDA status, IEEE flags, and benchmark thresholds from being conflated.
