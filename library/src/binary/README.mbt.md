# `binary`

`binary` is the stable scalar binary surface for `0.12.0`. Public types are
`Binary`, non-negative `BinCoeff`, `BinaryContext`/`BinaryFlags`, and
`BinaryInterchange`. Use ordinary methods for arbitrary-precision values and
`*_ctx` methods when IEEE rounding, exponent limits, tininess, or flags matter.

The verified matrix is binary16/32/64/128 add, subtract, multiply, divide, and
sqrt across five rounding directions and both tininess modes. Integer powers,
hex interchange, signed zero, infinities, NaNs, payloads, and checked traits are
also public, as are the certified elementary functions (`exp_ctx`, `ln_ctx`,
`atan2_ctx`, `hypot_ctx` and the rest of the IEEE 754-2019 9.2 family), which
the MPFR fixture of the conformance page checks. This is not a claim of every
IEEE 754 operation or every real input.

`BinCoeff` is the application boundary; do not depend on limb layout, dispatch
thresholds, NTT primes, or host bigint implementation details.
