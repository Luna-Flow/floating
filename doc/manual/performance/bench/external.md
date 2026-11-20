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

The ratio of a cell is the *net* time of `floating` divided by the net time of
the reference library; above 1 means `floating` is slower. A net time is the
time of the operation without the loop around it: every block of a case is
paired with a block of its null (the same loop without the library call), and
the net time is the median of the differences of the pairs. The bracketed
interval is a 95% bootstrap interval over rounds and pairs, and the interval of
the ratio resamples the two sides independently; the method, with its formulas
and its fixed rules, is on the [design page](../../design/bench/external.md).
A case meets the target of the baseline, a ratio of at most 3, when the upper end
of that interval is at most 3. A case whose reference net time cannot be told
from zero, whose floating net time is not above zero, or whose interval is wider
than a stated bound is reported as unresolved, is never counted as met, and is
judged on the raw ratio (the median of the case blocks over the median of the
case blocks, the number of 0.11.0), which is printed beside the net ratio. The
measurements are native, release builds only.

The method makes the number honest; it does not move the target. Computed from
the 0.11.0 medians, with the floating floor then measured (9.21 ns per
operation) and any reference floor between 0.4 and 1.1 ns, 43 of the 59 cases
are above 3 on the raw ratio and 42 on the net ratio; only `decimal_gda`
multiplication at 100 digits (3.03) changes side.

## Machine and toolchain

The table describes the run of 0.11.0; every summary records its own machine and
toolchain in `meta`, and the sections of the new measurements state theirs.

| Item | Value |
| --- | --- |
| CPU | Apple M4, 10 logical cores (4 performance, 6 efficiency), 16 GiB |
| OS | Darwin 27.2.1 (Darwin kernel 27.2.0) |
| Power | AC power at start and end of the run; no frequency pinning, no core pinning |
| Other load | the runner waits for the other processes to use under 150% CPU (1.5 cores) before each timed side; at the start of each side they used 8% to 34% (122% once, before the floating side of one round) |
| MoonBit | moon 0.1.20261119 (738607b 2026-11-19), v0.10.22+124d61d05 (2026-11-19) |
| `floating` build | `moon test --release --target native`; moon compiles the generated C with `/usr/bin/cc -fwrapv -fno-strict-aliasing -ffp-contract=off -Wno-unused-value -O2 -DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC` (reference-counted memory management, mimalloc allocator) |
| C compiler of the harness | Apple clang 21.0.0 (Xcode command line tools), flags `-O2` |
| MPFR | 4.2.2 (Homebrew bottle, thread-local storage on, no shared cache) |
| GMP | 6.3.0 (Homebrew bottle, built with `clang -O2 -pedantic -march=armv8-a`) |
| mpdecimal | 4.0.1 (Homebrew bottle) |
| Library revision | `4a052ed42f18`, clean working tree |
| Run | 2026-11-20T07:43:31Z, `just bench external run` with the `standard` preset |
| Operand and reference files | SHA-256 `e05e3284482dab5f` and `7ee258b310849477` (seed 20261118) |

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
  the immutable result value. The loop around the call, and for `floating`
  Maremark's per-iteration bookkeeping, are in the raw time and are removed in
  the net time by the null of the case (see the
  [design page](../../design/bench/external.md#the-null-of-a-case-the-same-loop-without-the-library-call)
  for what the null contains and what it cannot remove).
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
pass of eight operations), 3 exploratory pairs that are discarded and 12
confirmatory pairs. A pair is a block of the case and a block of its null, each
with its own calibrated batch, back to back, the order alternating. The two
sides alternate over 7 rounds in seeded AB/BA order, each round with its own
shuffled case order, so every cell has 84 confirmatory pairs per side from 7
separate processes. The rules of the verdict (84 pairs, the width bound of 1.25
on the ratio interval, the 5% drift and order thresholds, the target of 3) are
fixed in the method and written into the `protocol` block of every summary. Before each side
starts, the runner waits until other processes use under 150% CPU. The slowest cells
(elementary functions at 8192 bits and 1000 digits) take seconds per pass, so
their batch is a single pass.

## Configurations and results

The floating side is measured in two configurations of the native build, each
published as its own summary and shown in its own section: `native`, with the
native limb primitives where the build has them, and `portable`, with the
portable path forced. The target has to be reached by the portable path too.
The configuration is chosen when the run starts (`--configuration NAME`,
`--moon-env KEY=VALUE`) and recorded in the summary. The tables of a configuration are generated by
`just bench external publish` between the marker comments below and copied
without editing.

### Configuration `native`

<!-- external-baseline:native:start -->

Not measured yet with the net-ratio method. The first measurement with it is
published with the next release; until then the results below are those of
0.11.0, measured with the raw method.

<!-- external-baseline:native:end -->

### Configuration `portable`

<!-- external-baseline:portable:start -->

Not measured yet with the net-ratio method.

<!-- external-baseline:portable:end -->

## Results of 0.11.0 (raw method)

These are the tables of the release 0.11.0, measured before the net-ratio method
existed: the ratio is the median of the case blocks of `floating` over that of
the reference, without a null, and the single floor known then was the 9.21 ns of
the floating loop. They are kept as the record of that release
(`testdata/external_baseline/summary-0.11.0.json`, schema v1) and are replaced
by the sections above as the new measurements are published. The tables are the
output of `just bench external publish` for that run, copied without editing.

### Binary: floating `bin_float` against MPFR

Ratio floating / MPFR (median time, 95% bootstrap interval; above 1 means floating is slower)

| op | 53 bits | 128 bits | 512 bits | 2048 bits | 8192 bits |
| --- | ---: | ---: | ---: | ---: | ---: |
| add | 8.74 [8.66, 8.84] | 6.41 [6.32, 6.59] | 6.96 [6.90, 7.04] | 6.34 [6.23, 6.51] | 5.15 [5.11, 5.18] |
| mul | 7.58 [7.51, 7.65] | 3.98 [3.93, 4.07] | 3.79\* [3.72, 3.82] | 3.93 [3.90, 3.96] | 3.92 [3.92, 3.93] |
| div | 7.94 [7.92, 8.06] | 5.88 [5.83, 5.93] | 3.19 [3.17, 3.24] | 3.70 [3.66, 3.73] | 4.76 [4.75, 4.77] |
| sqrt | 10.12 [9.99, 10.22] | 1.90 [1.90, 1.92] | 4.60 [4.56, 4.68] | 4.12 [4.06, 4.18] | 4.28 [4.24, 4.37] |
| exp | 3.09 [3.06, 3.13] | 2.52 [2.51, 2.54] | 2.50 [2.48, 2.52] | 5.23 [5.17, 5.29] | 2.99 [2.96, 3.02] |
| ln | 6.92 [6.89, 7.09] | 4.60 [4.55, 4.64] | 6.20 [6.16, 6.23] | 10.87 [10.80, 10.94] | 9.54 [9.45, 9.58] |
| sin | 8.84 [8.76, 8.93] | 7.70 [7.61, 7.76] | 7.26 [7.23, 7.31] | 10.13 [10.08, 10.22] | 5.24 [5.18, 5.26] |

Median ns per operation, MPFR

| op | 53 bits | 128 bits | 512 bits | 2048 bits | 8192 bits |
| --- | ---: | ---: | ---: | ---: | ---: |
| add | 4.59 ns | 6 ns | 12.4 ns | 21.7 ns | 85.6 ns |
| mul | 5 ns | 10.1 ns | 32 ns | 231 ns | 2.13 us |
| div | 5.38 ns | 26.3 ns | 106 ns | 498 ns | 4 us |
| sqrt | 5.64 ns | 62.3 ns | 162 ns | 509 ns | 2.83 us |
| exp | 557 ns | 846 ns | 2.35 us | 16.8 us | 208 us |
| ln | 388 ns | 1.09 us | 3.41 us | 14.9 us | 116 us |
| sin | 496 ns | 792 ns | 2.22 us | 14.1 us | 197 us |

Median ns per operation, floating

| op | 53 bits | 128 bits | 512 bits | 2048 bits | 8192 bits |
| --- | ---: | ---: | ---: | ---: | ---: |
| add | 40.1 ns | 38.5 ns | 86.2 ns | 138 ns | 441 ns |
| mul | 37.9 ns | 40 ns | 121 ns | 910 ns | 8.34 us |
| div | 42.8 ns | 154 ns | 340 ns | 1.84 us | 19 us |
| sqrt | 57.1 ns | 119 ns | 745 ns | 2.1 us | 12.1 us |
| exp | 1.72 us | 2.13 us | 5.89 us | 87.7 us | 619 us |
| ln | 2.69 us | 4.99 us | 21.2 us | 162 us | 1.11 ms |
| sin | 4.38 us | 6.1 us | 16.1 us | 143 us | 1.03 ms |

### Decimal GDA: floating `decimal_gda` against libmpdec

Ratio floating / libmpdec (median time, 95% bootstrap interval; above 1 means floating is slower)

| op | 16 digits | 34 digits | 100 digits | 1000 digits |
| --- | ---: | ---: | ---: | ---: |
| add | 3.63 [3.60, 3.67] | 11.39 [11.23, 11.55] | 8.71 [8.61, 8.83] | 6.01 [5.89, 6.13] |
| mul | 4.25 [4.20, 4.30] | 5.41 [5.27, 5.63] | 3.03 [3.00, 3.06] | 1.74 [1.72, 1.77] |
| div | 2.95 [2.90, 2.98] | 6.15 [6.09, 6.25] | 4.33 [4.28, 4.37] | 3.09 [3.07, 3.11] |
| sqrt | 5.31 [5.28, 5.35] | 4.27 [4.24, 4.31] | 2.77 [2.75, 2.78] | 2.12 [2.10, 2.13] |
| exp | 2.92 [2.88, 2.95] | 1.53 [1.52, 1.55] | 1.39 [1.38, 1.41] | 0.11 [0.11, 0.11] |
| ln | 1.28 [1.27, 1.29] | 0.96 [0.96, 0.98] | 1.17 [1.16, 1.18] | 0.28 [0.27, 0.28] |

Median ns per operation, libmpdec

| op | 16 digits | 34 digits | 100 digits | 1000 digits |
| --- | ---: | ---: | ---: | ---: |
| add | 20 ns | 21.9 ns | 35.1 ns | 171 ns |
| mul | 19.4 ns | 48.7 ns | 136 ns | 9.05 us |
| div | 31.6 ns | 122 ns | 328 ns | 14.5 us |
| sqrt | 307 ns | 1.07 us | 4.03 us | 213 us |
| exp | 2.97 us | 7.97 us | 17.5 us | 4.69 ms |
| ln | 9.94 us | 18 us | 43.2 us | 5.24 ms |

Median ns per operation, floating

| op | 16 digits | 34 digits | 100 digits | 1000 digits |
| --- | ---: | ---: | ---: | ---: |
| add | 72.5 ns | 249 ns | 306 ns | 1.03 us |
| mul | 82.6 ns | 264 ns | 413 ns | 15.7 us |
| div | 93.3 ns | 750 ns | 1.42 us | 44.8 us |
| sqrt | 1.63 us | 4.55 us | 11.2 us | 451 us |
| exp | 8.67 us | 12.2 us | 24.3 us | 523 us |
| ln | 12.7 us | 17.4 us | 50.4 us | 1.45 ms |

### Harness overhead of the floating side

| case | ns per operation (loop and result store only) |
| --- | ---: |
| `binary/null/53` | 9.21 ns [9.15 ns, 9.26 ns] |
| `decimal_gda/null/16` | 9.21 ns [9.14 ns, 9.32 ns] |

Cells marked with an asterisk exceeded a dispersion threshold (CI half-width over 5% of the median, or round medians spread by over 10%): `binary/mul/512`.

## What the numbers say

Everything below is read from the tables above; ratios are rounded and the
intervals are in the tables.

**`floating` is slower than the reference in 56 of the 59 cells and faster in
three, all `decimal_gda`.** Excluding those, the smallest ratio is 1.28
(`decimal_gda` `ln` at 16 digits) and the largest 11.4 (`decimal_gda` addition
at 34 digits). Four cells are above 10: binary `sqrt` at 53 bits (10.1), binary
`ln` and `sin` at 2048 bits (10.9 and 10.1), and `decimal_gda` addition at 34
digits (11.4). Where `floating` is faster, it is `exp` at 1000 digits (0.11,
that is 9 times faster: 523 us against 4.69 ms), `ln` at 1000 digits (0.28,
3.6 times faster: 1.45 ms against 5.24 ms) and `ln` at 34 digits (0.96, a
difference of 4%, with the interval [0.96, 0.98] below 1).

**Basic binary arithmetic: roughly 3 to 9 times slower.** Addition costs 5.2
to 8.7 times MPFR's time at every precision, multiplication 3.8 to 7.6, division
3.2 to 7.9. The gap is widest at 53 bits, where MPFR needs 4.6 ns for an
addition and `floating` 40.1 ns; about 9.2 ns of that is the harness (see the
`null` row), the rest is allocation and normalisation of an immutable result. At
128 bits and above multiplication stays at 3.8 to 4.0 times (8192 bits: 8.34 us
against 2.13 us).

**Square root is not smooth in precision.** The ratio is 10.1 at 53 bits, 1.9
at 128 bits, 4.6 at 512 bits and 4.1 to 4.3 at 2048 and 8192 bits. From 128 to
512 bits, 4 times the width, the time of `floating` grows from 119 ns to 745
ns (6.3 times) and MPFR's from 62.3 ns to 162 ns (2.6 times).

**Elementary functions: 2.5 to 11 times slower than MPFR in binary.** `exp` is
2.5 to 5.2 times slower at every precision (3.1 at 53 bits, 5.2 at 2048 bits,
3.0 at 8192 bits), `ln` 4.6 to 10.9 times and `sin` 5.2 to 10.1 times. These
three have their largest ratios at 2048 bits (5.2, 10.9, 10.1), not at 8192 bits
(3.0, 9.5, 5.2); the cost is not a smooth function of the precision. Both
libraries are correctly rounded, so the work is equal in specification but not
in method. The slowest binary operations measured are `ln` and `sin` at 8192
bits (1.11 ms and 1.03 ms against 116 us and 197 us in MPFR).

**`decimal_gda`: slower for the four basic operations, at par or faster for
`exp` and `ln` from about 34 digits.** Against libmpdec, addition is 3.6 to 11.4
times slower, multiplication 1.7 to 5.4, division 3.0 to 6.2 and square root
2.1 to 5.3. Multiplication, division and square root narrow towards the large
size: at 1000 digits they are 1.7, 3.1 and 2.1 times libmpdec. `exp` is 2.9, 1.5
and 1.4 times slower at 16, 34 and 100 digits and 0.11 at 1000 digits; `ln` is
1.28, 0.96, 1.17 and 0.28. This comes from libmpdec's side: from 100 to 1000
digits its `exp` time grows 268 times (17.5 us to 4.69 ms) and its `ln` time
121 times (43.2 us to 5.24 ms), against 21.5 times (24.3 us to 523 us) and 29
times (50.4 us to 1.45 ms) for `floating`. These are the measured times; the
cause in libmpdec was not investigated here. For scale, against MPFR at binary
sizes near 1000 decimal digits (2048 and 8192 bits), the binary `floating`
`exp` is 5.2 and 3.0 times slower and `ln` 10.9 and 9.5 times slower, so the
`floating` advantage over libmpdec at 1000 digits is not an advantage over a
binary library of the same size class.

**Harness overhead.** The `null` rows show that the timed loop of the
`floating` side costs 9.2 ns per operation with the arithmetic removed. That
is 23% of the 40.1 ns of a 53-bit addition and 16% of the 57.1 ns of a 53-bit
square root, about 1% of 1 us and less above it; it is not subtracted in these
tables. The loop of the C side was not measured in that run.

**Dispersion.** Within a process the 20 ms batches vary by under 3.1% (largest
median absolute deviation 1.5% for `floating` and 3.1% for the references).
Between the seven rounds the medians of one cell spread by at most 6.0% for
`floating` and 25.3% for the references (the reference side of `binary/mul/512`,
the one cell marked in the table); the bootstrap intervals therefore cover
whole-process variation, and the half-widths of the medians are at most 1.7%
for `floating` and 3.1% for the references, and at most 3.3% for a ratio.

**Repeatability.** The run was repeated once on the same commit `4a052ed` with a
different round-order seed. The run published here is the first one, with the
quieter machine: the other processes used 8% to 34% of the CPU before the timed
sides (once 122%), against 26% to 110% in the second run. Over the 59 cases the
medians of `floating` moved by 0.43% in the median and 2.1% at most, and the
ratios by 0.72% in the median. Two ratios moved by more than 3%:
`binary/mul/8192` (3.92 to 3.41, entirely on the MPFR side, which was 15% slower
in the second run) and `decimal_gda/mul/34` (5.41 to 5.59). Neither run had a
validation failure. The second run is not published.

## Follow-ups (not fixed here)

No profile was taken for this run, so the list is read from the ratios only and
names where the largest gaps are, not their cause.

- **Small binary cases.** At 53 bits `floating` takes 38 to 57 ns for add, mul, div
  and `sqrt`, 7.6 to 10.1 times MPFR, with 9.2 ns of the
  harness included; `sqrt` at 53 bits (10.1) stands out against 1.9 at 128 bits.
- **`ln` and `sin` at 2048 bits and 8192 bits.** Ratios of 10.9 and 10.1 at
  2048 bits and 9.5 at 8192 bits for `ln`, the largest elementary ratios; `exp`
  is at 2.5 to 5.2 at all sizes.
- **`sqrt` at 512 bits.** 4.6 times MPFR against 1.9 at 128 bits.
- **`decimal_gda` addition at 34 and 100 digits.** 11.4 and 8.7 times, against
  3.6 at 16 digits; the largest basic-operation ratios of the decimal side.

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
just bench external run --configuration native
just bench external publish
```

`run` writes the inputs, the reference results, the raw rounds, the summary and
the samples under `.tmp/external`; `publish` copies the compact summary to
`testdata/external_baseline/summary-VERSION-CONFIGURATION.json`, the samples
(the pairs of every case) to `samples-VERSION-CONFIGURATION.json.gz`, the tables
to `summary-CONFIGURATION.md`, and regenerates the tables of that configuration
on this page. The raw JSONL (about 12 MB) is not committed; its checksums and the
checksums of the operand and reference files are in the published summary.
`just bench external recompute SUMMARY SAMPLES` recomputes a summary from its
samples; `just bench external compare OLD NEW` compares two summaries (net
ratios when both are resolved, raw ratios otherwise); see the
[tutorial](../../tutorial/bench/external.md) for the commands and the
[API page](../../api/bench/external.md) for the benchmark cases.
