# `decimal` Design

`decimal` is the IEEE-oriented arbitrary-precision decimal core of `floating`
0.7.0. It combines a quantum-preserving decimal value, explicit contextual
rounding and flags, decimal32/64/128 interchange, and certified elementary
functions. The separate [`decimal_gda`](../decimal_gda/design.md) package owns
sticky General Decimal Arithmetic status and traps; the two value types are
intentionally not aliases.

## Design Contract

The implementation is organized around one semantic rule: coefficient kernels
compute exact integer facts, while a shared finalization step alone decides the
bounded decimal result. This gives the following pipeline:

```text
Decimal operands + immutable DecimalContext
  -> classify special values and operation domain
  -> form exact sign/coefficient/preferred exponent
  -> round once to the requested precision and mode
  -> apply exponent, subnormal, tininess, and clamp policy
  -> return Decimal + DecimalFlags
```

Consequently, a faster multiplication or division algorithm cannot alter
rounding, quantum, signed zero, NaN payloads, or flags. These observable states
are owned by the decimal layer, not by the coefficient representation.

## Representation And Cohorts

A finite `Decimal` stores an independent sign, non-negative coefficient,
base-10 exponent, precision, and special-value state. Its mathematical value is

```text
(-1)^negative × coefficient × 10^exponent10.
```

The same number may have several cohort representations. For example,
`1.2300` has quantum `-4`, whereas `1.23` has quantum `-2`. Parsing preserves
the input exponent when it fits the requested precision; `normalized()` or
`reduce_ctx()` removes removable powers of ten only when the caller explicitly
requests canonical cohort form. Numeric comparison and `compare_total` are
therefore different relations.

The private `DecCoeff` uses an inline representation for small magnitudes and
canonical little-endian base-`10^9` `UInt` limbs for larger values. Limb arrays
have no leading zero and carry an exact decimal digit count. `BigInt` remains at
public conversion/serialization boundaries and in test oracles, but decimal hot
paths operate on `DecCoeff`.

## IEEE 754 Alignment

`DecimalContext::ieee754()` and decimal32/64/128 presets make precision,
rounding, exponent limits, clamp, and before/after-rounding tininess explicit.
Context operations return `(Decimal, DecimalFlags)`; there is no ambient
rounding mode or process-global flag register. FMA preserves the exact product
through aligned addition and performs one final rounding.

`DecimalInterchange` implements both DPD and BID encodings for decimal32,
decimal64, and decimal128. Decode and encode preserve signed zero, infinity,
quiet/signaling NaN, and payload state. Non-canonical finite encodings are
handled at this encoding boundary rather than leaking bit-layout rules into
ordinary arithmetic.

The checked IEEE matrix covers the operation/encoding rows declared in
`testdata/decimal/ieee/conformance_matrix.json`. GDA-compatible operations that
remain on `Decimal` are compatibility surface, not evidence that this package
threads GDA traps. Applications requiring sticky status, fixed trap precedence,
or `.decTest` behavior must use `decimal_gda`.

## Coefficient Algorithm Selection

The selector considers limb count, density, balance ratio, square shape,
transform length, and target. Sparse coefficients use compressed nonzero
products; strongly unbalanced coefficients are divided into balanced blocks.
Dense balanced multiplication follows schoolbook/Comba, Karatsuba, Toom-3, and
dual-modulus NTT stages.

| Target | Karatsuba mul / square | Toom-3 mul | first NTT mul / square | BZ division | Newton division |
| --- | ---: | ---: | ---: | ---: | ---: |
| native | 96 / 48 | 1,152 | 1,728 / 640 | adaptive from 2,816 | disabled |
| LLVM | 96 / 96 | 2,048 | 4,096 / 2,048 | 2,048 | 4,096 |
| Wasm / Wasm-GC / JS | 96 / 96 | 4,096 | 8,192 / 4,096 | 2,048 | 4,096 |

The native NTT boundary is further adjusted by transform size: multiplication
uses 1,728, 2,816, 4,608, 7,680, then 8,192 limbs as the transform grows;
squaring uses 640, 1,040, 1,824, 3,648, 7,296, then 8,192. Native
Burnikel-Ziegler entry likewise moves from 2,816 to 5,120 and 10,240 limbs for
larger block lengths. These piecewise boundaries encode measured non-monotonic
costs that a single global cutoff would hide.

Algorithm-specific preconditions remain mandatory:

- Karatsuba and Toom-3 stop at bounded recursion depth and use scratch arenas.
- Toom-3 keeps signed interpolation values private and checks every exact
  small division.
- NTT converts to smaller working digits, checks transform and coefficient
  bounds, reconstructs with two-prime CRT, and falls back if exact
  reconstruction cannot be proved.
- Division checks `n = qd + r` and `0 <= r < d`; Newton/Burnikel-Ziegler may
  fall back to normalized Knuth Algorithm D.
- Scratch buffers are rewound only after all returned values have detached from
  temporary storage.

The native Newton selector is intentionally disabled in 0.7.0 even though the
algorithm is implemented and tested: current native measurements do not justify
its production crossover. LLVM, Wasm-family, and JS retain it from 4,096 limbs,
where the target cost model differs.

## Rounding, Exponents, And Quantum

Context finalization receives a signed exact coefficient and preferred exponent.
It computes guard/sticky information, applies one of the supported decimal
rounding modes, then decides overflow, underflow, subnormal, rounded, inexact,
and clamped status. `quantize` fixes the target exponent and reports
`invalid_operation` when the coefficient cannot fit the context; it never
silently changes the requested quantum.

Parsing follows the same model. `Decimal::parse`/`from_string` preserve an
input quantum that fits the chosen precision; a longer coefficient is rounded
once. `from_string_ctx` additionally returns conversion/rounding flags and
applies context exponent policy. This distinction is important for accounting,
protocol, and test-vector data where trailing zeros are meaningful.

## Certified Elementary Functions

Decimal elementary functions use a proof-producing bridge rather than a host
floating-point approximation. Each decimal input is converted twice to a
dyadic interval: once toward negative infinity and once toward positive
infinity. `ball_float` evaluates that enclosure, and both exact dyadic endpoints
are converted back through integer arithmetic. The result is accepted only when
both endpoints produce the same target `Decimal` and identical `DecimalFlags`.

The initial working precision is at least 128 bits and otherwise scales from
the input digits and target precision. A shared 12-step refinement budget grows
precision by `max(32, work / 2)`. `try_*_ctx` returns a structured certification
failure when no unique target rounding cell can be proved; convenience methods
use the same certified path and do not substitute an unchecked approximation.

The committed MPFR 4.2.2 oracle independently forms 768-bit directed bounds and
contains 2,784 rows across 29 operations, decimal32/64/128, and all eight
`DecimalRoundingMode` values. libmpdec `allcr=1` separately checks the
GDA-compatible `exp`, `ln`, and `log10` subset. These are finite evidence sets,
not a claim over all real inputs.

## Optimization And Boundary Tuning

Maremark measurements separate dense, sparse, balanced, unbalanced, square,
kernel-only, and full contextual paths. Candidate and baseline order is rotated
to limit warmup/order bias, and threshold tests exercise the exact limb below,
at, and above every selected boundary. A candidate path enters production only
after exact differential tests and a measured practical advantage both hold.

This produces two classes of boundary:

- **semantic boundaries**, such as precision, exponent, rounding, and quantum,
  which are public and must remain stable; and
- **dispatch boundaries**, such as 1,152 or 1,728 limbs, which are private,
  target-specific, and may be retuned without changing any result.

## Complexity And Trade-offs

For `n` base-`10^9` limbs, comparison, addition, normalization, shifts, and
single-limb division are `O(n)`. Schoolbook multiplication and Knuth division
are quadratic; Karatsuba, Toom-3, NTT, Burnikel-Ziegler, and Newton reduce large
asymptotic cost at the price of setup, temporary storage, and more restrictive
preconditions. The selector prefers the simplest proven algorithm until the
measured crossover pays for that complexity.

The algorithmic basis follows Knuth Algorithm D, Karatsuba multiplication,
Bodrato-style Toom-Cook interpolation, Burnikel-Ziegler division,
Brent-Zimmermann multiple-precision methods, Cowlishaw's decimal arithmetic
model, and IEEE 754-2019 / ISO 60559 semantics. Repository conformance data and
current code determine the exact 0.7.0 claim.

## Evidence Map

- [API reference](./api.md) inventories the public surface.
- [Tutorial](./tutorial.md) demonstrates quantum, contexts, interchange, and
  certified operations.
- [IEEE conformance](./conformance.md) defines the finite IEEE evidence claim.
- [Performance](./performance.md) records the dispatch and benchmark protocol.
- [`decimal_gda` conformance](../decimal_gda/conformance.md) records the
  separate GDA claim and prevents the two state models from being conflated.
