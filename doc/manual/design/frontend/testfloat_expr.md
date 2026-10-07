# `frontend/testfloat_expr` Design

The package parses TestFloat function metadata and fixed-width hexadecimal
vectors, decodes operands through `BinaryInterchange`, constructs a
`BinaryContext`, executes add/sub/mul/div/sqrt, and compares encoded result and
all five IEEE flags. Sharding is stable by row index.

Accepted formats are binary16/32/64/128 and accepted operation, rounding, and
tininess modes are exactly those parsed by `TestFloatSpec`. The package does not
generate vectors, invoke SoftFloat, read files, or extend coverage beyond that
matrix.
