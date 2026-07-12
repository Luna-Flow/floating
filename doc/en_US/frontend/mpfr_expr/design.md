# `frontend/mpfr_expr` Design

The package parses two pinned MPFR text formats: upstream hexadecimal sqrt
`data_check` rows and repository-generated integer-power witnesses. It converts
hexadecimal coefficients to `BinCoeff`, executes `sqrt_ctx` or `pow_int_ctx`,
and compares value plus inexact status using the rounding mode encoded by each
row.

It is an oracle adapter, not an MPFR binding. It supports only those two corpus
grammars and operations, performs no C FFI or file IO, and makes no claim about
other MPFR functions or rounding modes absent from the corpus.
