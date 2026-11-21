# `interval_checked`

`IntervalResult` is the stable checked wrapper for interval construction and
scalar composition. Invalid bounds and checked arithmetic failures are errors;
Entire and other conservative enclosures are valid successful values. The
wrapper does not store decorations or `IntervalFlags`; those remain explicit
`interval` concerns.
