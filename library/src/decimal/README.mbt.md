# `decimal`

`decimal` is the IEEE 754 arbitrary-precision decimal surface. `Decimal` keeps
sign, coefficient, exponent, precision, special values, and quantum-sensitive
cohort information. `DecimalContext` and `DecimalFlags` make rounding,
exponent bounds, clamp, subnormal status, and IEEE status explicit. Contexts
created by `DecimalContext::new` use IEEE NaN propagation by default. The
separate `decimal_gda` package exposes GDA contexts, sticky status, and
traps through `GdaOutcome`.

The public operation family includes arithmetic/FMA, integer division and
remainder, quantize/rescale, total comparison, logical digits, adjacent values,
formatting, decimal32/64/128 interchange, and elementary functions. Prefer
`*_ctx` for status-sensitive code; operators intentionally omit flags.

IEEE 754-2019 minimum/maximum and magnitude variants are distinct from the
legacy GDA-compatible `min`/`max` methods. `quantum` and NaN payload accessors
keep cohort and diagnostic state observable without changing finite values.

The pinned official and official0 GDA rows remain fully conformant through the
compatibility profile. The coefficient kernel uses canonical little-endian
base-1e9 limbs with inline arithmetic, Karatsuba, Toom-3, NTT, Knuth,
Burnikel-Ziegler, and Newton dispatch. Its thresholds and rationale are
documented in `doc/*/decimal/design.md`.
