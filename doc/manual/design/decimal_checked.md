# `decimal_checked` Design

## State Model

`DecimalChecked` is an immutable product of value, IEEE context, latest flags,
and accumulated flags. Construction forces `DecimalContext::ieee754()` so a
GDA-profile context cannot leak into this package.

## Transitions

Each method runs one contextual operation. The returned value becomes the next
value, returned flags become `raised`, and `combine` adds them to `flags`.
Exceptional IEEE results remain defined values. `with_context` explicitly
reapplies the current value under a new IEEE context and records that step.

## Composition Boundary

Binary methods accept plain `Decimal` operands. Accepting another
`DecimalChecked` would require an arbitrary rule for merging contexts and flag
histories. Operators are intentionally not implemented for the same reason.
The wrapper adds constant state-copy and flag-combine work around the delegated
numeric operation.
