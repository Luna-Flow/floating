# `decimal` Design Notes

This page tracks the current repository implementation and is written as the
`0.4.0` design baseline plus the first GDA-representation migration.

## Representation

Finite values are stored as:

- `negative : Bool`
- `coefficient : BigInt`
- `exponent10 : Int`
- `precision_ : Int`

with the intended meaning:

`(-1)^negative * magnitude * 10^exponent10`

The stored coefficient is a non-negative magnitude. This is a deliberate move
toward General Decimal Arithmetic style representation, because `BigInt` cannot
represent `-0` by itself. A separate sign bit lets the package preserve
negative zero and signed NaN payloads.

The public `coefficient()` observer still returns the signed coefficient for
the existing scalar interpretation. `magnitude()` exposes the stored
non-negative coefficient.

## Normalization Invariant

Numeric constructors canonicalize finite non-zero values by stripping all
removable powers of `10` from the coefficient and compensating them into
`exponent10`.

That gives:

- stable string formatting
- distinct `+0` and `-0` representation
- consistent decimal semantics

Zero is canonicalized to exponent `0`, but the sign is preserved.

GDA-style APIs may intentionally preserve a finite value's exponent/quantum.
For example, parsing `1.20` or quantizing a value to `0.01` can store
coefficient `120` with exponent `-2`. Use `normalized()` to request the
canonical cohort.

## Decimal Parsing

`Decimal::from_string` delegates its preprocessing to `@internal.split_decimal_string`, which:

- parses sign
- removes the decimal point into a digit string
- folds scientific notation into an exponent adjustment

When the parsed coefficient fits the requested precision, the package preserves
that parsed exponent instead of canonicalizing away trailing zeros. Signed zero
is preserved when the parsed digits are all zero. If the parsed coefficient
exceeds the requested precision, the value is rounded through the normal
precision path.

## Precision and Rounding

When a coefficient has more decimal digits than the requested precision, the implementation divides by the appropriate power of `10` and applies the selected rounding mode.

`DecimalContext` is the first decimal-native context layer. It carries
precision, shared Luna-Flow rounding, decimal-native rounding, exponent bounds,
and clamp mode. `precision = 0` means exact/no precision limit at the context
layer; internally this is represented by choosing enough stored precision for
the produced finite coefficient because the `Decimal` value itself still stores
a positive working precision.

The context keeps both rounding layers deliberately:

- `rounding : RoundingMode` is the generic Luna-Flow bridge used by
  `ArithmeticContext` and checked trait adapters.
- `decimal_rounding : DecimalRoundingMode` is the GDA-facing mode used by
  context-aware Decimal operations.

`DecimalRoundingMode` covers `HalfEven`, `HalfUp`, `HalfDown`, `Down`,
`Ceiling`, `Floor`, `Up`, and `ZeroFiveUp`. Modes that have no representation
in the shared Luna-Flow enum return `None` from `to_arithmetic()`, which keeps
the generic ecosystem honest while still allowing official GDA rounding
directives to execute through Decimal-native APIs.

`DecimalFlags` is the first decimal-native status layer. Context-aware
arithmetic currently reports:

- `rounded`
- `inexact`
- `lost_digits`
- `invalid_operation`
- `division_by_zero`
- `division_undefined`
- `overflow`
- `underflow`
- `subnormal`
- `clamped`

Subset operand rounding follows GDA `decRoundOperand`: an inexact operand
reduction sets `lost_digits` in addition to `rounded` and `inexact`.

The full flag structure also reserves `conversion_syntax`,
`division_impossible`, and `invalid_context` for later GDA features without
changing the public status type.

Finite context-aware results are finalized against the context exponent
bounds. Results whose adjusted exponent exceeds `e_max` become infinities and
set `overflow`, `rounded`, and `inexact`. Results below `e_min` set
`subnormal`; `underflow` is set when that subnormal result is also inexact.
When `clamp` is enabled, finite results with an exponent above the clamped top
exponent can be padded with trailing coefficient zeros and a lower exponent
without changing their numeric value.

Context-aware finite operations preserve GDA-style preferred exponents where
the current operation defines one and the result fits the context. Addition and
subtraction use the smaller operand exponent, multiplication uses the sum of
operand exponents, and `quantize` uses the quantum operand exponent. Precision
reduction may still raise the exponent by discarding trailing zeros before any
inexact rounding is needed.

`quantize` is the first fixed-quantum operation. It returns a value with the
same exponent as the quantum operand, raises `rounded` when digits are
discarded, raises `inexact` when discarded digits are non-zero, and raises
`invalid_operation` when the resulting coefficient would exceed the context
precision. `rescale` currently aliases `quantize`.

`to_integral_exact` quantizes to exponent `0` and preserves rounded/inexact
flags. `to_integral_value` returns the same value but suppresses those two
informational flags.

The first non-arithmetic-operator GDA operations are also present:

- `fma_ctx` performs an exact multiplication and rounds only after adding the
  third operand.
- `divide_integer` returns the integer part of division and reports
  `division_impossible` instead of rounding an over-precision quotient into
  shape.
- `remainder` is based on the integer quotient relation.
- `remainder_near` is based on the nearest integer quotient and resolves exact
  half-way cases toward the even quotient.
- `next_plus`, `next_minus`, and `next_toward` construct adjacent representable
  decimals in the active context, using `Etiny = e_min - precision + 1` for
  subnormal spacing and the lower-side cohort quantum when stepping toward zero
  across an exact power of ten. `next_toward` selects direction from the second
  operand and reports the GDA status flags for directed overflow and underflow
  steps.
- `shift_ctx` and `rotate_ctx` move coefficient digits in the active context
  width. They preserve finite signs and exponents, reject non-integral or
  out-of-range count operands with `invalid_operation`, and use the same
  quieting/payload truncation rules as the rest of the context operation layer.
- `logb_ctx` returns the adjusted exponent as a context-rounded Decimal integer.
  Zero maps to `-Infinity` with `division_by_zero`, infinities map to
  `+Infinity`, and NaNs use the usual context quieting/payload rules. Its
  integer-result rounding deliberately distinguishes discarded zero digits
  (`rounded`) from discarded non-zero digits (`rounded` plus `inexact`).
- `scaleb_ctx` shifts a finite operand by a power of ten without changing its
  coefficient digits first. It validates the scale operand as a finite
  exponent-zero integer within the GDA context range, handles huge exponent moves
  without machine-integer overflow, and finalizes finite results through the
  context's overflow, Etiny subnormal rounding, underflow, and clamped-zero
  rules.
- `compare_total` and `compare_total_magnitude` order decimal representations,
  including NaNs and different cohorts of the same numeric value, without
  replacing numeric `Compare`.
- `compare_ctx` and `compare_signal_ctx` return decimal comparison results with
  status flags; the signaling form reports `invalid_operation` for quiet NaNs as
  well as signaling NaNs.
- `logical_and`, `logical_or`, `logical_xor`, and `logical_invert` implement the
  GDA logical digit operations for finite exponent-zero operands whose digits are
  only `0` or `1`.
- `plus_ctx`, `minus_ctx`, and `abs_ctx` provide context-aware unary operation
  entry points for standard testcase execution.
- `reduce_ctx` applies context rounding and then canonicalizes the finite result
  cohort by stripping trailing decimal zeros; `normalize_ctx` is the GDA alias.
- `copy` exposes the GDA quiet identity operation, preserving finite
  exponent/quantum and NaN sign, payload, and qNaN/sNaN state; `trim` strips
  finite trailing zeros without applying context rounding.
- `copy_abs`, `copy_negate`, and `copy_sign` expose GDA representation-level
  sign-copy operations without using the context.
- `class_name` and predicate helpers expose the first GDA classification layer,
  including context-dependent normal/subnormal checks and representation-level
  signedness.
- `min_ctx`, `max_ctx`, `min_mag_ctx`, and `max_mag_ctx` provide GDA-style
  min/max operation baselines with NaN handling and total-order tie breaking.

## Current GDA Boundary

The package now has the representation hooks needed for GDA-style values:

- negative zero
- quiet NaN constructor
- signaling NaN constructor
- NaN payload observation
- separate sign and magnitude observations
- context-aware add, subtract, multiply, and divide entry points
- fused multiply-add, integer division, remainder, and total/signaling comparison
  baselines
- nearest-remainder baseline
- unary context and sign-copy operation baselines
- reduce/normalize cohort canonicalization
- logical digit operation baselines
- classification and predicate operation baselines
- context-aware minimum/maximum and magnitude-minimum/maximum baselines
- decimal status flags for rounded/inexact, core exceptional division cases,
  and the first exponent-bound/clamp cases
- quantize/rescale and same-quantum operations
- integral rounding operations
- a small decTest-style consistency runner that checks result cohorts and flags
  through shared case helpers

It is not a full GDA implementation yet. Missing or incomplete pieces include:

- full Etiny/minimum-exponent behavior
- overflow result selection for every rounding mode
- full clamped interchange-format behavior
- decimal32, decimal64, and decimal128 interchange formats
- official `.decTest` corpus semantic execution and full conformance reporting
- full NaN/sNaN semantics for the official `compare` / `comparesig` testcase
  surface, including sign/payload propagation and signaling behavior
- proof-driven optimization boundaries for `quantize` / `rescale`; official GDA
  rows such as `quax1010..quax1015` show that seemingly simple coarse-target
  shortcutting can silently violate required `Invalid_operation` results

Those should be added on top of the current representation rather than by
returning to signed-coefficient storage.

## Luna-Flow Generic Integration

`Decimal` implements Luna-Flow generic algebra traits up to `Ring`:

- `Zero`
- `One`
- `AddMonoid`
- `MulMonoid`
- `AddGroup`
- `Semiring`
- `Ring`

It intentionally does not claim `Field`. Decimal division is context-sensitive
and has special-value behavior around zero, infinities, and NaNs, so the field
contract would be too strong at this stage.

`Eq` is intentionally numeric rather than representation-level. `+0` and `-0`
are equal for generic algorithms, while `is_negative_zero()` preserves the
representation distinction. NaN values are equal to each other at the `Eq`
layer so the trait remains reflexive; decimal-native comparison/status APIs
should carry the future GDA signaling behavior.

## Relationship to `bin_float`

`Decimal` is the repository’s decimal-first package, while `BinFloat` is the binary-first package.

- binary to decimal preserves the exact finite binary representation currently stored
- decimal to binary may approximate non-dyadic values

That distinction should be made explicit whenever conversion behavior is documented.
