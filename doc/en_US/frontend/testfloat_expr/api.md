# `frontend/testfloat_expr` API

`TestFloatSpec::parse(function, rounding, tininess?)` validates format,
operation, rounding, and tininess. `parse_testfloat(source, text, spec)` returns
a typed document; `execute_document(document, options?)` executes stable shards
and returns result/count accessors.

Supported operations are `Add`, `Subtract`, `Multiply`, `Divide`, and
`SquareRoot` over binary16/32/64/128. A successful summary means selected rows
matched values and flags; it does not expand the supported matrix.
