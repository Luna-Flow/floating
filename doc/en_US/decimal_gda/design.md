# `decimal_gda` Design

`decimal_gda` is the standalone General Decimal Arithmetic (GDA)
Specification 1.70 engine in `floating` 0.7.0. It is validated against the
pinned General Decimal Arithmetic testcase suite 2.62 and intentionally does
not depend on the IEEE-oriented `decimal` package. Its `Decimal`, coefficient,
context, flags, interchange, and finalization code are package-owned so an IEEE
state model cannot silently enter a GDA calculation.

## Design Objective

GDA arithmetic specifies more than a numerical value: each operation also
produces conditions, updates sticky status, and may transfer control through a
configured trap while retaining a defined result. The package therefore models
an operation as a pure state transition:

```text
(operands, GdaContext)
  -> exact operation + GDA finalization
  -> (defined result, raised flags, next sticky context)
  -> fixed-precedence trap selection
  -> Completed(...) or Trapped(...)
```

The returned `GdaOutcome` is the complete result. A trap is not an exception
that erases the value, and sticky status is not ambient mutable state.

## Value And Coefficient Representation

An opaque finite `Decimal` stores classification, sign, a package-owned
`GdaCoeff`, decimal exponent, precision, signaling-NaN state, and payload.
`GdaCoeff` has two canonical persistent forms:

- `Small(UInt64)` represents zero through `10^18 - 1` without allocation;
- `Limbs(Array[UInt], digits)` stores larger magnitudes as little-endian
  base-`10^9` limbs with an exact digit count.

Published values never share mutable scratch storage. Inputs may be reused by
the caller after an operation because algorithms build a new canonical
coefficient instead of mutating operand limbs.

The finite value model preserves cohorts. Sign, coefficient, and exponent are
separate, so signed zero and trailing-zero quantum remain observable. Quiet and
signaling NaNs retain sign and payload. These representation states are needed
by GDA copy, class, total-order, same-quantum, formatting, and interchange
operations and cannot be reduced to mathematical equality alone.

## Context, Status, And Trap Alignment

`GdaContext` directly stores precision, all eight GDA rounding modes, exponent
bounds, clamp, extended mode, sticky status, and the enabled trap set. Standard
decimal32/64/128 presets are immutable cached values.

Each operation computes per-operation `raised` flags, combines them into the
next context status, and chooses at most one enabled signal using the package's
fixed GDA precedence. Both `Completed` and `Trapped` retain the defined value,
next context, and raised flags. Threading `next_context()` accumulates status;
reusing the original context deliberately starts from the old status.

This explicit transition provides three guarantees:

1. deterministic trap precedence when several conditions are raised;
2. reproducible calculations without thread-local rounding or status; and
3. lossless inspection/recovery because the defined result survives a trap.

## Arithmetic And Finalization

Finite arithmetic first constructs an exact signed coefficient and preferred
exponent. One shared GDA finalizer then decides precision reduction, rounding,
cohort selection, clamp, subnormal classification, underflow, overflow, signed
zero, and conditions. FMA preserves the exact product through aligned addition
and rounds once.

The order is important: special-value/domain rules precede finite arithmetic,
and no coefficient algorithm is allowed to set GDA flags directly. This keeps
the standard-facing state machine independent from kernel selection.

Exact 1-18 digit parse, add, subtract, multiply, and FMA cases use a proved
wrapper fast path. It is selected only if the result is finite, remains in
`Small`, fits precision and exponent bounds, requires no clamp, and raises no
flag. Any failed predicate routes to the generic finalizer. Differential
white-box tests compare the value, raised flags, sticky context, trap state, and
boundary fallback against the generic path.

## Coefficient Algorithm Selection

The local coefficient engine includes schoolbook/Comba, Karatsuba, Toom-3,
dual-modulus NTT, normalized Knuth D, Burnikel-Ziegler, and reciprocal Newton
algorithms. Selection considers size, density, operand balance, square shape,
transform length, and target.

| Target | Karatsuba mul / square | Toom-3 mul | first NTT mul / square | BZ division | Newton division |
| --- | ---: | ---: | ---: | ---: | ---: |
| native | 96 / 48 | 1,152 | 1,728 / 640 | adaptive from 2,816 | disabled |
| LLVM | 96 / 96 | 2,048 | 4,096 / 2,048 | 2,048 | 4,096 |
| Wasm / Wasm-GC / JS | 96 / 96 | 4,096 | 8,192 / 4,096 | 2,048 | 4,096 |

Native NTT and Burnikel-Ziegler boundaries are piecewise functions of transform
or block length, reaching 8,192 and 10,240 limbs respectively. This is a
measured target policy, not a standard rule. NTT length/coefficient bounds, CRT
reconstruction, Toom interpolation divisions, and quotient/remainder identities
are checked; an unmet precondition selects an exact fallback.

Although the current thresholds numerically match the IEEE decimal engine,
the code and tests are independent. Sharing a number is not sharing a semantic
or dependency boundary. This duplication is deliberate: it prevents a future
IEEE kernel/context change from entering the GDA conformance surface
accidentally.

## Certified Elementary Functions

Square root uses the local integer-square-root and refinement machinery.
Integer power uses exact or bounded exponentiation by squaring. Non-integer
power, `exp`, `ln`, and `log10` convert the exact decimal input into directed
binary enclosures, evaluate a certified interval, convert both dyadic endpoints
back exactly, and accept a result only if both endpoints occupy the same GDA
rounding cell with identical flags.

Ordinary bounded inputs may begin with a lower-cost working precision, but an
inconclusive witness returns to the conservative refinement budget. A bounded
single-entry `ln(10)` interval cache accelerates repeated logarithms; the cached
object is immutable. No approximate candidate bypasses GDA finalization.

The mathematical-function boundary is standard-specific. `exp`, `ln`, and
`log10` retain the GDA fixed HalfEven rule where required; `power` follows the
context rule represented by the current API. Trigonometric, hyperbolic,
inverse, `atan2`, `hypot`, and pi-scaled functions are intentionally absent
because they are not part of this GDA operation adapter.

## Non-Arithmetic And Interchange Operations

The package implements the legal scalar inventory used by the pinned suite:
quiet/signaling comparisons, total order, extrema, `logB`, same-quantum,
adjacent values, copy/class/predicate families, logical digits, shift/rotate,
integral conversions, and scientific/engineering formatting.

Concrete decimal32/64/128 interchange is package-owned DPD. Decode, encode,
canonicalization, and copy operations do not call the IEEE interchange code.
BID remains an IEEE-package feature and is intentionally absent here.

## Optimization And Switching Boundaries

Optimization follows a two-level rule. First, every candidate must be
observationally identical at the GDA boundary: value, cohort, flags, next sticky
context, and trap must agree. Second, target-specific benchmark evidence must
justify the added setup and storage. Boundaries are tested below, at, and above
the selected limb counts, including sparse, square, and unbalanced shapes.

The small-value fast path is a semantic predicate rather than a size-only
cutoff. The large coefficient selector is a performance policy rather than a
semantic predicate. Keeping these roles distinct allows aggressive kernel
tuning without weakening GDA behavior.

## Effects And Verification Boundary

`.decTest` parsing, directive snapshots, sharding, JSON, filesystem access, and
process exit status live in `frontend/gda_expr`, CLI packages, and Python
tooling. `decimal_gda` itself is a deterministic value/context transformation.
The frontend invokes its public `GdaContext`/`GdaOutcome` API directly and may
memoize only immutable parsed contexts.

The 0.7.0 acceptance boundary combines package/property tests, all-target
checks, dependency scans, IEEE-isolation tests, and both pinned corpora. The
`official` corpus passes 64,986/64,986 legal executable scalar rows and
`official0` passes 16,124/16,124; the remaining 141 `#` placeholder/non-scalar
rows are diagnostics outside the legal denominator. This finite result does not
claim future directives, invalid placeholders, or unbounded input strings.

## Evidence Map

- [API reference](./api.md) inventories the GDA value/context/outcome surface.
- [Tutorial](./tutorial.md) demonstrates correct context threading, traps, and
  recovery choices.
- [Conformance](./conformance.md) defines the pinned corpus, exclusions, and
  isolation checks.
- [`decimal` design](../decimal/design.md) explains the separate IEEE state
  model and interchange boundary.

