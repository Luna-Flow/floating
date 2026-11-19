# External baseline: floating against MPFR and libmpdec

## Contract

This page records how much slower or faster `floating` is than the established
C libraries on the same machine, with the same operands and the same
measurement protocol: `bin_float` against MPFR for binary arithmetic and
`decimal_gda` against libmpdec for GDA decimal arithmetic. It makes no API promise,
and the numbers are evidence about one machine, one toolchain and one operand
distribution, not a speed claim for every environment. Where `floating` is
slower, the tables say so as measured; nothing here is tuned for the
comparison, and no library code was changed for it.

The ratio of a cell is the median time of `floating` divided by the median time
of the reference library; above 1 means `floating` is slower. The bracketed
interval is a 95% two-level bootstrap interval over rounds and blocks (see the
[design page](../../design/bench/external.md)). The measurements are native,
release builds only.

## Machine and toolchain

| Item | Value |
| --- | --- |
| CPU | Apple M4, 10 logical cores (4 performance, 6 efficiency), 16 GiB |
| OS | Darwin 27.2.1 (Darwin kernel 27.2.0) |
| Power | AC power at start and end of the run; no frequency pinning, no core pinning |
| Other load | the runner waits for the other processes to use under 150% CPU (1.5 cores) before each timed side; at the start of each side they used 30% to 91%, mostly the window server and desktop applications |
| MoonBit | moon 0.1.20261117 (eb64713 2026-11-17), v0.10.21+06da1ed44 (2026-11-16) |
| `floating` build | `moon test --release --target native`; moon compiles the generated C with `/usr/bin/cc -fwrapv -fno-strict-aliasing -ffp-contract=off -Wno-unused-value -O2 -DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC` (reference-counted memory management, mimalloc allocator) |
| C compiler of the harness | Apple clang 21.0.0 (Xcode command line tools), flags `-O2` |
| MPFR | 4.2.2 (Homebrew bottle, thread-local storage on, no shared cache) |
| GMP | 6.3.0 (Homebrew bottle, built with `clang -O2 -pedantic -march=armv8-a`) |
| mpdecimal | 4.0.1 (Homebrew bottle) |
| Library revision | `2938f6ce6ab6` plus documentation-only edits; no library source differs from the commit |
| Run | 2026-11-18T12:03:10Z, `just bench external run` with the `standard` preset |
| Operand and reference files | SHA-256 `4be4d4ca88128cad` and `f5ee544a4698cfac` (seed 20261118) |

## What is timed

Each case is one operation at one precision with eight different operand sets
read from the same file by both sides (`inputs.txt`, written by one seeded
generator; checksums are in `machine.json`). One timed iteration is one pass
over the eight sets, so a time per operation is the batch time divided by the
iterations and by eight.

- **Binary.** Operands and results have the case precision in bits. MPFR:
  `mpfr_add`, `mpfr_mul`, `mpfr_div`, `mpfr_sqrt`, `mpfr_exp`, `mpfr_log`,
  `mpfr_sin` with `MPFR_RNDN`. `floating`: the `BinFloat` methods `add`, `mul`,
  `div`, `sqrt`, `exp`, `ln`, `sin` on operands of that precision (round to
  nearest even, unbounded exponent range).
- **`decimal_gda`.** Operands and results have the case digit count, rounding half
  even, exponent range ±999999. libmpdec: `mpd_qadd`, `mpd_qmul`, `mpd_qdiv`,
  `mpd_qsqrt`, `mpd_qexp`, `mpd_qln` with `allcr = 1`. `floating`:
  `decimal_gda` `add`, `multiply`, `divide`, `sqrt`, `exp`, `ln` in a context of
  that precision. libmpdec has no `sin`, so `decimal_gda` has six operations.
- **Included in the time.** The library call itself, with whatever temporary
  storage it allocates internally. For `floating` this includes constructing
  the immutable result value and the Maremark per-iteration bookkeeping; the
  `null` rows below measure the latter.
- **Excluded.** Parsing operands, creating contexts, `mpfr_t` and `mpd_t`
  initialisation and result buffers (MPFR and libmpdec write into results
  allocated before timing), reading files, and printing. Process start-up and
  the first warm-up passes are outside the measured blocks.
- **Correctness.** Before it is timed, every `floating` output is compared with
  the MPFR or libmpdec result for the same operand (all 427 comparisons, 61 cases in 7 rounds, were equal). Both
  libraries round every result correctly (MPFR always; libmpdec with
  `allcr = 1`; `floating` by certified refinement), so at equal precision the
  results are identical and the ratio compares equal work.
- **Not trivially cached.** The operands are 8 distinct random sets per case,
  every result is overwritten on the next pass, and neither library keeps a
  result cache. Both keep internal caches of constants such as $\pi$ and
  $\ln 2$ per precision; these are warm during timing on both sides (the
  warm-up passes fill them), so the numbers are steady-state rates, not
  cold-start costs.

## Protocol

Both sides run the Maremark protocol with the same numbers: 3 warm-up passes
and at least 5 ms of warm-up, batches calibrated to about 20 ms (at least one
pass of eight operations), 3 exploratory blocks that are discarded and 12
confirmatory blocks. The two sides alternate over 7 rounds in seeded AB/BA
order, each round with its own shuffled case order, so every cell has
84 confirmatory blocks per side from 7 separate processes. Before each side
starts, the runner waits until other processes use under 150% CPU. The slowest cells
(elementary functions at 8192 bits and 1000 digits) take seconds per pass, so
their batch is a single pass.

## Results

### Binary: floating `bin_float` against MPFR

Ratio floating / MPFR (median time, 95% bootstrap interval; above 1 means floating is slower)

| op | 53 bits | 128 bits | 512 bits | 2048 bits | 8192 bits |
| --- | ---: | ---: | ---: | ---: | ---: |
| add | 22.13 [22.02, 22.24] | 21.22 [20.97, 21.49] | 18.06 [17.90, 18.45] | 16.36 [16.24, 16.49] | 15.59 [15.56, 15.61] |
| mul | 20.02 [19.85, 20.15] | 13.27 [13.22, 13.33] | 10.66 [10.60, 10.75] | 10.93 [10.89, 10.96] | 12.76 [12.73, 12.80] |
| div | 33.35 [33.17, 33.47] | 8.94 [8.87, 9.00] | 6.20 [6.15, 6.29] | 8.59 [8.56, 8.63] | 13.80 [13.76, 13.84] |
| sqrt | 39.53 [39.30, 39.80] | 7.84 [7.78, 7.86] | 49.87 [49.49, 50.31] | 27.81 [27.70, 27.96] | 27.87 [27.72, 28.03] |
| exp | 65.06 [64.66, 65.49] | 77.14 [76.66, 77.79] | 102 [102, 103] | 187 [186, 187] | 411 [410, 412] |
| ln | 141 [141, 142] | 107 [107, 108] | 155 [155, 156] | 561 [559, 563] | 2472 [2460, 2475] |
| sin | 435 [433, 436] | 433 [431, 435] | 577 [575, 582] | 1214 [1210, 1217] | 2554 [2548, 2561] |

Median ns per operation, MPFR

| op | 53 bits | 128 bits | 512 bits | 2048 bits | 8192 bits |
| --- | ---: | ---: | ---: | ---: | ---: |
| add | 4.57 ns | 6 ns | 12.4 ns | 21.8 ns | 85.9 ns |
| mul | 5.01 ns | 10.1 ns | 32 ns | 232 ns | 2.14 us |
| div | 5.4 ns | 26.4 ns | 108 ns | 514 ns | 4.07 us |
| sqrt | 5.65 ns | 62.9 ns | 166 ns | 522 ns | 2.97 us |
| exp | 559 ns | 851 ns | 2.38 us | 17 us | 213 us |
| ln | 388 ns | 1.1 us | 3.45 us | 15.1 us | 116 us |
| sin | 503 ns | 803 ns | 2.23 us | 14.2 us | 198 us |

Median ns per operation, floating

| op | 53 bits | 128 bits | 512 bits | 2048 bits | 8192 bits |
| --- | ---: | ---: | ---: | ---: | ---: |
| add | 101 ns | 127 ns | 225 ns | 357 ns | 1.34 us |
| mul | 100 ns | 134 ns | 341 ns | 2.54 us | 27.3 us |
| div | 180 ns | 236 ns | 668 ns | 4.42 us | 56.2 us |
| sqrt | 223 ns | 493 ns | 8.26 us | 14.5 us | 82.7 us |
| exp | 36.4 us | 65.7 us | 244 us | 3.18 ms | 87.4 ms |
| ln | 54.7 us | 118 us | 536 us | 8.47 ms | 286 ms |
| sin | 218 us | 348 us | 1.29 ms | 17.3 ms | 507 ms |

### Decimal GDA: floating `decimal_gda` against libmpdec

Ratio floating / libmpdec (median time, 95% bootstrap interval; above 1 means floating is slower)

| op | 16 digits | 34 digits | 100 digits | 1000 digits |
| --- | ---: | ---: | ---: | ---: |
| add | 16.01 [15.87, 16.23] | 11.57 [11.44, 11.70] | 8.58 [8.33, 8.68] | 6.67 [6.62, 6.72] |
| mul | 16.04 [15.87, 16.14] | 6.37 [6.11, 6.47] | 3.13 [3.08, 3.18] | 1.77 [1.74, 1.81] |
| div | 22.11 [21.84, 22.27] | 8.02 [7.91, 8.14] | 4.73 [4.68, 4.83] | 3.14 [3.04, 3.20] |
| sqrt | 5.95 [5.81, 6.02] | 4.34 [4.32, 4.39] | 2.77 [2.73, 2.82] | 2.11 [2.03, 2.15] |
| exp | 86.94 [86.35, 87.29] | 36.54\* [36.29, 36.79] | 95.74 [95.46, 96.24] | 65.62 [64.19, 67.00] |
| ln | 22.42 [22.31, 22.54] | 22.36 [22.24, 22.65] | 24.46 [24.33, 24.70] | 15.02 [14.68, 15.24] |

Median ns per operation, libmpdec

| op | 16 digits | 34 digits | 100 digits | 1000 digits |
| --- | ---: | ---: | ---: | ---: |
| add | 19.2 ns | 23.5 ns | 43.2 ns | 160 ns |
| mul | 18.4 ns | 47.5 ns | 142 ns | 9.68 us |
| div | 30.1 ns | 119 ns | 343 ns | 15.3 us |
| sqrt | 289 ns | 1.09 us | 4.13 us | 211 us |
| exp | 2.85 us | 8.01 us | 17.6 us | 4.98 ms |
| ln | 9.87 us | 15.8 us | 40.7 us | 5.95 ms |

Median ns per operation, floating

| op | 16 digits | 34 digits | 100 digits | 1000 digits |
| --- | ---: | ---: | ---: | ---: |
| add | 307 ns | 273 ns | 371 ns | 1.07 us |
| mul | 296 ns | 303 ns | 446 ns | 17.2 us |
| div | 666 ns | 955 ns | 1.62 us | 47.9 us |
| sqrt | 1.72 us | 4.71 us | 11.4 us | 445 us |
| exp | 248 us | 293 us | 1.69 ms | 327 ms |
| ln | 221 us | 353 us | 996 us | 89.4 ms |

### Harness overhead of the floating side

| case | ns per operation (loop and result store only) |
| --- | ---: |
| `binary/null/53` | 9.28 ns [9.23 ns, 9.4 ns] |
| `decimal_gda/null/16` | 9.36 ns [9.28 ns, 9.48 ns] |

Cells marked with an asterisk exceeded a dispersion threshold (CI half-width over 5% of the median, or round medians spread by over 10%): `decimal_gda/exp/34`.

## What the numbers say

Everything below is read from the tables above; ratios are rounded and the
intervals are in the tables.

**`floating` is slower than both C libraries in every one of the 59 cells.**
The smallest ratio is 1.77 (`decimal_gda` multiplication at 1000 digits) and the
largest 2554 (binary `sin` at 8192 bits).

**Basic binary arithmetic: roughly 6 to 40 times slower.** Addition costs
15.6 to 22 times MPFR's time at every precision, and multiplication 10.7 to 20
times. The gap is widest at 53 bits, where MPFR needs 4.6 ns for an addition
and `floating` 101 ns; about 9 ns of that is the harness (see the `null`
row), the rest is allocation and normalisation of an immutable result.
Division is 6.2 times slower at 512 bits but 33 times at 53 bits and 13.8 times
at 8192 bits. At 8192 bits multiplication takes 27.3 us against 2.14 us
(12.8 times); 8192 bits is 256 limbs of 32 bits, in the Karatsuba range,
against GMP's 64-bit limbs with assembly kernels.

**Square root is not smooth in precision.** The ratio is 7.8 at 128 bits, 49.9
at 512 bits and 27.8 at 2048 and 8192 bits. At 512 bits `floating` takes 8.26
us, 17 times its time at 128 bits for 4 times the width, where MPFR's time grows
2.6 times. The change of algorithm at 512 bits (fixed-width kernels below,
divide and conquer above) is the likely cause; see the follow-up list.

**Elementary functions: 65 to 2554 times slower, and the gap grows with
precision.** `exp` is 65 times slower at 53 bits and 411 times at 8192 bits;
`ln` 141 and 2472 times; `sin` 435 and 2554 times. At 53 bits a `sin` takes
218 us in `floating` and 0.5 us in MPFR. Both are correctly rounded, so the
work is equal in specification but not in method: `floating` certifies each
result by interval arithmetic and a Ziv refinement loop, and the cost grows
faster than MPFR's with the precision. `exp` at 8192 bits (87 ms against
213 us) and `ln` and `sin` at 8192 bits (286 ms and 507 ms) are among the
slowest operations measured.

**`decimal_gda`: closer, but still slower everywhere.** Against libmpdec, addition is
6.7 to 16 times slower, multiplication 1.8 to 16, division 3.1 to 22 and square
root 2.1 to 6.0. The gap narrows with the digit count for these four
operations: at 1000 digits multiplication is 1.8 times, square root 2.1 and
division 3.1 times libmpdec. `ln` is 15 to 24 times slower and `exp` 37 to 96
times. The `exp` ratio is not monotone in the digit count: `floating` takes
about 250 to 290 us at 16 and 34 digits, a floor that does not shrink with
fewer digits, while libmpdec's time grows from 2.9 us to 8.0 us.

**Harness overhead.** The `null` rows show that the timed loop of the
`floating` side costs 9.3 ns per operation with the arithmetic removed. That
is 9% of the 101 ns of a 53-bit addition and under 1% of anything above 1 us;
it is not subtracted. The C side's loop overhead is below the clock
resolution.

**Dispersion.** Within a process the 20 ms batches vary by under 3% (largest
median absolute deviation 1.9% for `floating` and 2.9% for the references). Between the seven rounds the medians of one
cell spread by at most 8.7% for the references and 10.4% for `floating`; the
bootstrap intervals therefore cover whole-process variation, and their
half-widths are at most 1.9% of the median. One cell exceeds a dispersion
threshold (marked in the table): `decimal_gda/exp/34`, whose round medians for
`floating` spread by 10.4%.

**Measurement history.** A first five-round run was discarded, not selected
against: the machine switched from battery to AC power during it and another
session on the same machine kept about six processes at full CPU, and round medians of
one cell differed by up to a factor of two, so every cell was marked noisy.
Its ratios differ from this run's by 21% in the median cell and by up to 49%
(`decimal_gda/ln/16`), and its intervals are 7 to 250 times wider (median 62 times). The reported run added the
quiet-machine gate, the power-source check, and a larger number of shorter
rounds.

## Follow-ups (not fixed here)

A short `sample` profile of the `floating` test binary (4 seconds on
`binary/sqrt/512` and on `binary/sin/128`; indicative, not a rigorous
profile) shows the following. No library code was changed for this baseline.

- **Allocation and reference counting dominate the small cases.** The top
  frames are `moonbit_drop_object`, `mi_malloc`, `moonbit_make_int32_array`
  and, for the elementary functions, `scan_regular_object` (the cycle scan of
  the reference counter) and thread-local lookups of the allocator. Every
  `BinCoeff` intermediate is a heap array of 32-bit limbs. Fewer intermediate
  `BinCoeff` values in the contextual rounding path (`binary_round_rational`,
  `normalize_finite`, `add_heap`) would help add, mul and div at 53 to 512
  bits, where `floating` is 10 to 33 times slower.
- **`sqrt` at 512 bits.** The profile is led by `compare`, `shift_left` and
  `test_bit` inside `bin_coeff_sqrt_rem_divide_conquer`: bit-level work on
  heap coefficients. The jump from 493 ns at 128 bits to 8.26 us at 512 bits
  suggests the divide-and-conquer threshold is too low, or its base case too
  slow, at this size.
- **Elementary functions.** The start precision of the certification loop is
  at least 128 bits (`max(128, 4D + 64)` for `decimal_gda`), which puts a floor of
  roughly 220 to 350 us on `decimal_gda` `exp` and `ln` at 16 and 34 digits and 36 to 55 us
  on binary `exp` and `ln` at 53 bits, where MPFR needs 0.4 to 0.6 us. A
  cheaper first attempt at the target precision plus a few guard bits, falling
  back to the existing loop, would address the low-precision end. The growth
  towards 8192 bits needs a different algorithm (argument reduction and
  series evaluation on `BinCoeff` with bit-burst or binary splitting) and is a
  larger piece of work.
- **Multiplication at 8192 bits.** 27.3 us against 2.14 us; 8192 bits is 256
  limbs of 32 bits, below the native Toom-3 and transform thresholds (2048
  limbs), so the Karatsuba range and its allocations are where the time goes.
  This is an inference from the thresholds, not a measurement.

## What is not measured

- **Other targets.** JavaScript, WebAssembly and LLVM builds are not measured;
  the C libraries have no counterpart there.
- **Other machines and compilers.** One Apple M4 laptop on AC power, with no frequency or core
  pinning and some background desktop load; absolute
  times will differ on other hardware, and ratios shift with the memory
  system and the CPU's multiplier and SIMD units.
- **Tuned library builds.** The MPFR and GMP in use are Homebrew bottles built
  with `-O2 -march=armv8-a`; a GMP configured for the exact CPU, or a
  libmpdec with other build options, can be faster.
- **Large and special arguments.** Elementary functions are timed on
  well-conditioned arguments of modest magnitude; argument reduction of huge
  arguments, arguments near zeros and singularities, subnormal results,
  overflow, and exceptional values are not timed.
- **Cold start.** Warm caches only; the cost of the first call at a precision is
  excluded.
- **Other operations.** `fma`, `pow`, `hypot`, `cos`, `tan`, the hyperbolic and
  inverse functions, remainders, conversions, and parsing and printing are not
  compared. Interval (`ball_float`) arithmetic has no counterpart in MPFR and
  is not compared (MPFI is not part of this baseline).
- **Memory and threads.** Peak memory and multi-threaded behaviour are not
  measured.
- **Other rounding modes.** Only round to nearest even.

## Reproduce

```bash
just bench external run
just bench external publish
```

`run` writes the inputs, the reference results, the raw rounds and the
summary under `.tmp/external`; `publish` copies the compact summary to
`testdata/external_baseline/summary-VERSION.json`. The raw JSONL of the run
reported here (about 12 MB, 2.4 MB compressed) is not committed; its checksums and the
checksums of the operand and reference files are in the published summary.
`just bench external compare OLD NEW` compares two summaries; see the
[tutorial](../../tutorial/bench/external.md) for the commands and the
[API page](../../api/bench/external.md) for the benchmark cases.
