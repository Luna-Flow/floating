# `frontend/mpfr_expr` Design

The package parses three pinned MPFR text formats: upstream hexadecimal sqrt
`data_check` rows, repository-generated integer-power witnesses, and the
29-operation elementary matrix. It converts hexadecimal coefficients to
`BinCoeff`, executes the matching contextual operation, and compares the value
plus inexact/invalid/division-by-zero status under the row's rounding mode.

It is an oracle adapter, not an MPFR binding. It performs no runtime C FFI or
file IO. The development-only generator uses MPFR 4.2.2 and its mandatory
nearest-away wrapper; released packages do not link MPFR or GMP.
