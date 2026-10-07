# `def` Design

## Responsibility

`def` is the shared numeric vocabulary. It reexports arithmetic context/error,
rounding, classification, and `BigInt` types; defines `Sign` and
`PartialOrder`; and provides the deliberately small open `Floating` trait.

## Selection And Boundary

`Floating` contains only representation-independent observation and retuning:
`classify`, `sign`, `precision`, `with_precision`, and `normalized`. Arithmetic,
ordering, parsing, context flags, and interval relations stay in narrower
capability traits or concrete packages because their laws differ by domain.
The helper predicates are direct pure projections over `classify`; this package
contains no numerical algorithm, storage, IO, or global state.

Implementing `Floating` does not imply a field, total order, IEEE format, exact
arithmetic, or checked error behavior. Downstream generic code must request the
additional capabilities it actually uses.
