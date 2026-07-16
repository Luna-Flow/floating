# `bin_float`

`bin_float` is the stable scalar binary surface for `0.7.1`. Public types are
`BinFloat`, non-negative `BinCoeff`, `BinaryContext`/`BinaryFlags`, and
`BinaryInterchange`. Use ordinary methods for arbitrary-precision values and
`*_ctx` methods when IEEE rounding, exponent limits, tininess, or flags matter.

The verified matrix is binary16/32/64/128 add, subtract, multiply, divide, and
sqrt across five rounding directions and both tininess modes. Integer powers,
hex interchange, signed zero, infinities, NaNs, payloads, and checked traits are
also public. This is not a claim of every IEEE 754 operation or transcendental.

`BinCoeff` is the application boundary; do not depend on limb layout, dispatch
thresholds, NTT primes, or host bigint implementation details.
