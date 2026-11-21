# `differential/ball_mpfr`

The untimed differential stage of `BallFloat` against MPFR (`tools/ball_diff.py`,
`tools/ball_mpfr_oracle.c`): the operands of a row file are read, the operation is
run, and the two bounds of the result are compared as canonical text with the
bounds MPFR gives directly (directed roundings, the exponent range and the
gradual underflow of `bin_float`). The test runs only when `BALLDIFF_INPUTS` and
`BALLDIFF_ORACLE` name the files; `just` does not call it, `ball_diff.py run` does.
