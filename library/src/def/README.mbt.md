# `def`

`def` is the smallest shared vocabulary: `Sign`, `PartialOrder`, `FpClass`,
rounding/context/error aliases, helper predicates, and the `Floating` trait (implemented by
the types of this library only). Its public contract is observational (`classify`, `sign`, `precision`,
`with_precision`, `normalized`); it does not promise arithmetic or total order.

Use concrete packages for arithmetic and request narrower capability traits when
writing generic code. This package is stable vocabulary, not a numerical kernel.
