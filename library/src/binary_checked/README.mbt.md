# `binary_checked`

`BinaryChecked` is the stable short-circuit composition wrapper around
`Result[Binary, ArithmeticError]`. Constructors validate at the boundary;
`map` preserves success, `bind` may introduce an error, and binary operations
retain the first error from left to right.

It adds no IEEE context, flags, interchange, or recovery policy. Use
`binary` directly for those concerns and use `BinaryChecked` for pipelines
whose failure channel must remain explicit.

Every `_ctx` method is its plain method with an explicit context and the same
error map: an invalid operation is a `DomainError`, a division by zero a
`DivisionByZero`, and overflow, underflow and inexact are dropped.
