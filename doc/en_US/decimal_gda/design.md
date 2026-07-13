# `decimal_gda` Design

`decimal_gda` isolates General Decimal Arithmetic state and control semantics
from the IEEE-oriented `decimal` API while reusing the same proven decimal
kernel internally.

## Responsibility And Representation

The public `Decimal` wrapper is opaque. `GdaContext` contains an internal decimal
context plus GDA rounding, sticky status, and trap configuration. The package
owns GDA naming, signal mapping, trap precedence, and state threading; it does
not duplicate coefficient arithmetic, transcendental algorithms, or
decimal32/64/128 encoding.

The separation prevents one context type from having two incompatible meanings.
IEEE code observes per-operation flags. GDA code threads status and traps. Text
or interchange formats form the explicit boundary between the public value
types.

## Outcome State Machine

For each operation:

1. execute the corresponding internal decimal context operation;
2. map `DecimalFlags` to `GdaFlags` raised by this step;
3. combine raised flags into the input context's sticky status;
4. scan enabled traps in fixed precedence order;
5. return `Completed` or `Trapped`, always retaining value, next context, and
   raised flags.

This flow is deterministic and pure. The context is immutable data; “updating”
status means returning a new context. Callers decide whether to thread, clear,
or discard it.

## Context Invariants

Public precision is strictly positive and `e_min <= e_max`. `try_new` is the
checked constructor; `new` enforces the positive-precision invariant directly.
The radix is fixed at 10. Standard presets use GDA decimal32/64/128 precision,
exponent, and clamp values.

`clear_status` preserves traps. `reset` clears both status and traps. Trap-set
operations return new values and never mutate a context shared by another
calculation.

## Capability Boundary

The operation inventory follows the implemented scalar GDA families: arithmetic,
FMA, integer division and remainders, quantize/rescale, integral conversion,
elementary functions, adjacent values, logical digits, shifts/rotations, and
numeric/total comparison.

Filesystem access, `.decTest` parsing, case filters, sharding, JSON, and process
exit status belong to `frontend/gda_expr`, `internal/runner_cli`, CLI packages,
and Python tooling. Keeping these effects outside the numerical package allows
operations and state transitions to be tested as ordinary values.

## Conformance Boundary

The compatibility claim is defined by the pinned legal scalar rows, not by the
existence of a parser token. `frontend/gda_expr` classifies `#` placeholder or
non-scalar rows as diagnostics and reports unknown future operations or
conditions separately. Strict runners fail supported-case gaps rather than
silently weakening the denominator.

IEEE decimal conformance is a separate gate with independent DPD/BID fixtures.
Passing GDA decTest does not by itself prove every IEEE interchange property,
and passing the IEEE fixture does not supply GDA sticky status or traps.

## Complexity And Extension

Wrapping a decimal operation adds constant state-combination work plus a scan of
the fixed 13-signal precedence list. Numeric complexity and allocation remain
those of the delegated decimal operation.

When adding a signal or operation, update the public enum/interface, flag and
trap mapping, precedence policy, operation adapter, `.decTest` frontend support,
tests, generated interface, and all localized docs together. Do not expose the
internal decimal value merely to avoid writing an explicit boundary conversion.

