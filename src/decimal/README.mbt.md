# `decimal`

`decimal` is the stable arbitrary-precision decimal surface. `Decimal` keeps
sign, coefficient, exponent, precision, special values, and quantum-sensitive
cohort information. `DecimalContext` and `DecimalFlags` make rounding,
exponent bounds, clamp, subnormal status, and GDA conditions explicit.

The public operation family includes arithmetic/FMA, integer division and
remainder, quantize/rescale, total comparison, logical digits, adjacent values,
formatting, decimal32/64/128 interchange, and elementary functions. Prefer
`*_ctx` for status-sensitive code; operators intentionally omit flags.

The pinned official and official0 legal executable rows are fully conformant;
only `#` placeholder/non-scalar invalid inputs are excluded. The coefficient
kernel is correctness-oriented base-1000 schoolbook code; its
complexity and rationale are documented in `doc/*/decimal/design.md`.
