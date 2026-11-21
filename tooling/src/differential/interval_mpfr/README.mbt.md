# `differential/interval_mpfr`

The untimed differential stage of `Interval` against MPFR (`tools/interval_diff.py`,
`tools/interval_mpfr_oracle.c`): the operands of a row file are read, the operation is
run, and the two bounds of the result are compared as canonical text with the
bounds MPFR gives directly (directed roundings, the exponent range and the
gradual underflow of `binary`). The test runs only when `INTERVALDIFF_INPUTS` and
`INTERVALDIFF_ORACLE` name the files; `just` does not call it, `interval_diff.py run` does.
