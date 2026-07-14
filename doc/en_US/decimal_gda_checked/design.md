# `decimal_gda_checked` Design

## State Model

`GdaDecimalChecked` contains exactly one `GdaOutcome[Decimal]`. The outcome owns
the current defined value, next sticky context, flags raised by the latest
operation, and optional trapped signal.

## Transitions

An operation on `Completed` uses its value and next context, then stores the new
outcome. An operation on `Trapped` is the identity transition. This makes trap
short-circuiting explicit and prevents accidental calculation past a configured
control boundary.

## Recovery Boundary

`resume_defined` is the only implicit-control escape hatch. It retains the
defined value and sticky context, clears the current-step `raised` observation,
and returns a completed pipeline. Binary methods accept plain GDA values so two
independent sticky contexts are never merged. Traps are never converted to
`ArithmeticError`.
