# bench/external design

## Design goal

Put a number on how far `floating` is from the established C libraries, on the
same machine, the same operands and the same measurement protocol, so that a
statement such as "N times slower than MPFR at 512 bits" can be checked and
tracked from release to release. Benchmarks that compare `floating` with its
own earlier versions cannot say that.

## Mathematical background

Let $t_F$ and $t_R$ be the time per operation of `floating` and of the
reference library for one case (operation and precision). Each side yields
blocks of per-operation times, $x_{r,j}$ in round $r$ and block $j$. The
reported quantities are the pooled medians
$\tilde t_F = \operatorname{med}_{r,j} x^F_{r,j}$ and
$\tilde t_R = \operatorname{med}_{r,j} x^R_{r,j}$ and the ratio

$$
\rho = \frac{\tilde t_F}{\tilde t_R}.
$$

Blocks of one round come from one process and share memory layout, frequency
state and system noise, so they are not independent. The interval is therefore
a two-level percentile bootstrap: a replicate draws $R$ rounds with
replacement, once for both sides, and then draws the blocks of each chosen
round with replacement on each side; the ratio of the two replicate medians is
one replicate of $\rho$, and the 2.5% and 97.5% quantiles of 2000 replicates
(seeded) are the interval. Drawing the rounds once for both sides pairs them,
so a slow drift of the machine between rounds cancels in the ratio. The
interval of a single median is obtained the same way from one side.

A cell is flagged as noisy when the half-width of its median interval exceeds
5% of the median or when the medians of the rounds spread (maximum minus
minimum) by more than 10% of the pooled median, on either side.

## Design decisions

### One operand file, read by both sides

A seeded generator (Python's `random.Random` seeded by a string, stable across
versions) writes `operands-per-case = 8` operand sets for every case. Binary
operands are exact `±0x<mantissa>p<exponent>` values with exactly the case
precision in mantissa bits and the leading bit set; decimal operands are exact
`±<coefficient>E<exponent>` values with exactly the case digit count. Parsing
is therefore exact on both sides and needs no rounding mode, and both sides
time the same values. Magnitudes are chosen so that no operation takes a
special-case shortcut: the leading-bit exponent of `add`, `mul`, `div` and
`sqrt` operands lies in $[-8, 8]$, `exp` and `sin` arguments have
$|x| \in [0.25, 4)$, `ln` arguments lie in $[2^{-3}, 2^4)$; for decimal the
magnitudes are $[10^{-2}, 10^{3})$ for arithmetic, $[0.1, 10)$ for `exp` and
$[0.1, 10^3)$ for `ln` and `sqrt`. Every operand is a different random
mantissa, so no result repeats and nothing can be answered from a cache of
results.

### Oracle: the reference result of the same operands

The C harness prints the correctly rounded MPFR (round to nearest even) and
libmpdec (`HalfEven`, `allcr = 1`) results for every operand to a reference
file. The `floating` benchmark reads that file as its oracle, so Maremark
validates every `floating` output against the reference library before it is
timed. A mismatch is reported (it would be a correctness finding) and the case
is still timed, so the table never silently compares different results. The
elementary functions of both libraries are correctly rounded, so for them,
too, equal precision implies equal results.

### Same protocol on both sides

The C harness implements the Maremark protocol literally: warm-up passes until
both a count and a time are reached, the calibration rule that grows the batch
towards a target batch time, then exploratory and confirmatory blocks of a
fixed number of passes. The numbers (warm-up, batch target, block counts) are
passed to both sides from one place. Only confirmatory blocks enter the
statistics.

### Alternating sides, shuffled cases

Each round runs the C harness and the `floating` test as two processes, the
first side alternating from round to round (seeded AB/BA), with one shuffled
case order per round shared by both sides, so a case occupies different times
of the run in different rounds. Seven rounds give each case seven process-level
measurements per side to bootstrap over; between-process variation (core
placement, allocator layout, other load) is larger than the variation between
blocks of one process, and the two-level bootstrap accounts for it. Before each
side starts the runner waits until other processes use under 150% CPU and
records the load it saw.

### What is not in the timed region

Operand parsing, context and `mpfr_t` / `mpd_t` initialisation, result
buffers (MPFR and libmpdec write into preallocated results; `floating` writes
into a preallocated array of results), and printing are outside. What stays
inside is the cost of the library's own API: for MPFR and libmpdec the call
and any internal temporaries, for `floating` the construction of an immutable
result value, which is how the library is used. That difference is inherent in
the two designs and is part of what the ratio reports.

### The harness overhead is measured, not assumed

`external/*/null` cases run `floating`'s timed loop with the arithmetic
removed. Its time per operation bounds what the harness adds to every
`floating` number and is reported next to the results; it is not subtracted.

## Correctness and invariants

- The operand file and the reference file are checksummed in `machine.json`.
- A `floating` result that differs from the reference is counted in the
  Maremark validation tally and listed in `results.json`.
- The ratio uses only rounds in which both sides produced confirmatory blocks.
- Seeds are recorded, so the round order and the bootstrap are reproducible
  from the raw JSONL; the timings themselves are not.

## Alternatives rejected

- **A binding from MoonBit to MPFR.** It would put FFI marshalling inside the
  timed region of one side only.
- **Comparing against mpmath or gmpy2.** Their overhead is the Python
  interpreter, not the library.
- **Timing one operand repeatedly.** A single fixed operand lets branch
  predictors and caches memorise the data path; eight different operands per
  pass avoid it at a cost of eight times the batch duration.

## Boundaries

- Native target only; no claims for JavaScript or WebAssembly.
- One machine, one operating system, one compiler per run; see the performance
  page for the machine.
- Elementary functions are measured on a few well-conditioned argument ranges;
  huge arguments and arguments near singularities are not measured.
- The library caches of MPFR (for $\pi$ and $\log 2$) and the corresponding
  caches of `floating` are warm during timing; cold-start cost is not measured.
- Only a single thread is used; memory use is not measured.
