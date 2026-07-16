# Numeric Semantics

This page defines the vocabulary shared across the `0.7.1` documentation. It
distinguishes mathematical value from stored representation, rounding status,
checked failure, and interval enclosure.

## Value And Representation

A finite binary value is a signed non-negative coefficient multiplied by a
power of two. A finite decimal value is a signed non-negative coefficient
multiplied by a power of ten. Different representations can denote the same
mathematical value.

For decimal values, `12.3400`, `12.340`, and `12.34` are one numeric value but
different cohorts. Their stored exponent is the quantum. Parsing preserves that
quantum; `normalized()` or `reduce_ctx()` may remove trailing coefficient zeros
and adjust the exponent without changing the mathematical value.

Precision is representation metadata and a rounding bound, not a proof that
every stored digit is significant. `with_precision` may round. It does not
change the radix or convert between binary and decimal.

## Rounding And Contexts

The shared binary-style rounding vocabulary contains nearest-even,
toward-zero, toward-positive, toward-negative, and away-from-zero. Decimal adds
GDA modes such as half-up, half-down, and zero-five-up.

`BinaryContext`, `DecimalContext`, and `BallContext` make bounded-format policy
explicit. Depending on the domain, a context carries precision, exponent
bounds, clamp, rounding, and tininess detection. Presets such as `binary64`,
`decimal64`, and the corresponding ball context supply standard bounds.

Use a context API when any of the following is observable:

- exact rounding direction;
- overflow, underflow, subnormal, inexact, or rounded status;
- before- versus after-rounding tininess;
- decimal clamp or exponent cohort rules;
- a fixed interchange format.

## Flags, Status, Traps, And Errors

An operation flag reports a condition raised while producing a defined result.
Flags are not automatically exceptions. Combine explicit IEEE flags across
steps when accumulated status is required.

GDA distinguishes three related values:

- `raised`: conditions produced by the current operation;
- `status`: sticky union of conditions from all threaded operations;
- `traps`: enabled conditions that change `Completed` into `Trapped`.

A trapped `GdaOutcome` still contains the GDA-defined result, next context, and
raised flags. Trap selection follows a fixed precedence when multiple enabled
signals are raised.

`ArithmeticError` is different: it describes a checked operation that cannot
produce the requested scalar result under the checked capability contract.
Binary and interval result wrappers short-circuit that error. Decimal
composition instead preserves its native state: `DecimalChecked` accumulates
IEEE flags around defined results, while `GdaDecimalChecked` threads sticky
status and short-circuits traps without erasing their defined results.

## Special Scalar Values

Binary and decimal scalars expose signed zero, positive/negative infinity,
quiet NaN, and signaling NaN where supported. NaN payload and signaling state
are representation data; arithmetic may quiet a signaling NaN and raise an
invalid condition.

Numeric equality and ordering do not imply representation equality:

- signed zeros compare numerically equal but retain different signs;
- decimal cohort members compare numerically equal but may fail `same_quantum`;
- NaN is unordered under ordinary comparison;
- total comparison operations deliberately order representations, including
  NaNs and cohorts, for sorting and protocol use.

Use classification and explicit total-order APIs instead of inferring behavior
from formatted text.

## Interval Semantics

`BallFloat` denotes a set of reals bounded by binary endpoints. Arithmetic must
contain every mathematical result of choosing one value from each input set.
Outward rounding protects this inclusion invariant.

The important states are:

- **Empty**: no real value;
- **Entire**: all real values;
- **non-empty bounded or unbounded interval**: values between endpoints;
- **NaI**: decorated invalid interval state, distinct from Empty.

Containment, subset, overlap, disjointness, and definite comparison replace
scalar total ordering. Division by an interval containing zero can validly
produce Entire. A conservative enclosure is a successful value even when it is
not tight.

Decorations record how strongly the result satisfies continuity/domain
conditions. They are not scalar flags and are not stored by
`BallFloatResult`.

## Conversion And Projection

Binary-to-decimal and decimal-to-binary conversion may require rounding because
finite values in one radix are not always finite in the other. Choose precision
and rounding explicitly when the conversion result is part of a contract.

Interchange conversion is narrower than arbitrary-precision conversion:
binary16/32/64/128 and decimal32/64/128 enforce fixed field widths, exponent
bounds, special encodings, and status behavior.

`semantic` projection is exact for the mathematical value it retains, but it is
intentionally lossy for representation metadata. Use it for cross-package
comparison and diagnostics, never to round-trip quantum, payloads, signed zero,
decorations, or flags.

## Decision Checklist

Before choosing an API, answer:

1. Is the required result a scalar value, a representation, or a real set?
2. Must radix, precision, exponent bounds, or quantum remain observable?
3. Does the caller need per-operation flags, sticky GDA status, or checked
   short-circuit errors?
4. Can NaN, infinity, signed zero, Empty, Entire, or NaI occur?
5. Is ordinary partial comparison sufficient, or is total order/set relation
   required?
6. Is conversion arbitrary precision or fixed interchange?
7. Which finite conformance matrix supports the claimed behavior?
