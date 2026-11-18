# decimal_gda performance

<!-- historical-performance-baseline: 0.7.1 -->

## Measurement boundary

`just bench decimal-gda --target native` runs the current Maremark suite in
`src/bench/decimal_gda` and writes `.tmp/bench/decimal-gda.jsonl` plus its
analysis file. The independent quick fixture can be run with
`python3 tools/run_gda_benchmark.py`; it writes `.tmp/bench/gda-quick-native.json`
and uses three native runs per cell. Neither artifact is a universal speed
claim or a substitute for the conformance gate.

## Workload

The Maremark suite measures add, subtract, multiply, divide, FMA, and parse at
1, 9, 18, 34, and 128 decimal digits. It compares the core `GdaContext` path
with the full checked path and validates both against the core result before
reporting layer overhead.

Contexts may use the adopted decNumber maximum precision `999,999,999`, but
operations at that boundary can be expensive. In debug-native measurements, `1 / 4` in
`decimal_gda` did not finish within 40 seconds. Use a smaller precision for
interactive work and reserve the maximum for compatibility or conformance
checks.

## Reading results

`MAREMARK_JSONL` is the raw event stream and `MAREMARK_HOTSPOT` reports paired
core-versus-checked overhead. The quick fixture additionally records per-
operation medians and dispersion. Interpret these measurements only for the
recorded target, toolchain, fixture, and workload; they do not establish a
cross-target threshold or a fixed latency bound.

## Reproduction

```bash
just bench decimal-gda --target native
python3 tools/run_gda_benchmark.py
just bench all --target native
```

Use the same target and toolchain when comparing artifacts. Normal benchmark
tests compile their plans but skip timing, so an explicit benchmark command is
required for measurement.

## Small-coefficient fast paths and the exponential

`add`, `subtract`, `multiply` and `divide` on operands whose coefficients are single-limb values (below 10^18) in an extended context of at most 18 digits (17 for `divide`) compute the exact sum, product or guarded quotient on `UInt64` pairs, round once to the precision with the context's rounding mode, and build the result and its flags directly, instead of going through the operand preparation, the normalization chain and the finalizer. The functions decline (and the general path answers) a NaN, an infinity, a zero, a wider coefficient or precision, a non-extended context, `ZeroFiveUp`, an exact zero sum, an exact quotient (whose preferred exponent the general path settles), exponents more than 19 places apart or near the implementation limits, and any result that would be clamped, subnormal, or beyond the exponent range of the context; the value, the flags and the next context are those of the general path. White-box tests compare 60,000 random operand pairs per operation over twelve precisions from 1 to 34, all eight rounding modes, narrow and wide exponent ranges, clamping, extended and basic contexts, all-nines and tie coefficients, cancelling sums and power-of-two and power-of-five divisors with the general path. Paired native runs at 16 digits: `add` 4.6 times, `multiply` 4.0 and `divide` 8.2 times faster; Wasm-GC 9.3, 10.2 and 7.8 times.

The certified exponential of an argument below 1000 in magnitude, in a context that holds every result (extended, not clamped, `e_min` at most -999,999 and `e_max` at least 999,999), starts from the binary enclosure alone: its midpoint, converted to decimal and padded to `precision + 8` digits, picks the rounding cell, and the enclosure at about 3.33 bits per digit plus 12 guard bits and 4 per decade of the argument certifies it. Previously only arguments in [1, 10) took this attempt, and every other argument evaluated the Taylor series in decimal arithmetic at four bits per digit plus 64, which dominated the cost. A hard case (an enclosure that straddles a cell boundary) falls back to the conservative precision and the decimal series, as before. White-box tests compare the result with that of the former procedure for 400 random arguments of 1 to 40 digits and adjusted exponents from -40 to 3 and for 150 arguments chosen so that the exponential lies within 10^-60 of a rounding midpoint (6,000 and 2,000 in a one-off run): the value, flags and cohort are the same. Paired native runs of `exp`: 3.9 times faster at 16 digits, 8.2 at 34, 22 at 100 and 305 at 1,000 digits.

## Semantic gate

The timing path is accepted only alongside the independent GDA state model and
the pinned legal scalar corpus: 64,986/64,986 current rows and 16,124/16,124
legacy rows pass in the 0.7.1 audit. See [Conformance](../conformance/decimal_gda.md),
[Design](../design/decimal_gda.md), and the [0.7.1 performance and semantic
audit](../performance_audit.md).
