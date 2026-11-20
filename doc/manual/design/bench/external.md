# bench/external design

## Design goal

Put a number on how far `floating` is from the established C libraries, on the
same machine, the same operands and the same measurement protocol, so that a
statement such as "N times slower than MPFR at 512 bits" can be checked and
tracked from release to release. Benchmarks that compare `floating` with its
own earlier versions cannot say that.

## Mathematical background

Let $t_F$ and $t_R$ be the time per operation of `floating` and of the
reference library for one case (operation and precision). The number the
project is judged by is the ratio of the *net* times, which are the times of the
operation without the cost of the benchmark loop around it. The method is fixed
in advance and versioned (`net-ratio-v1`); a change of any number below is a
new method version.

**Pairs.** Each side is timed in pairs of blocks, in one process: a block of the
case, $x_{r,j}$, and a block of its null, $y_{r,j}$ (the same loop without the
library call, see below), both in ns per operation, each with its own
calibrated batch of about 20 ms, run back to back with the order inside the
pair alternating. Here $r$ is the round and $j$ the confirmatory pair of the
round ($R = 7$ rounds of $B = 12$ pairs, after 3 exploratory pairs per round
that are discarded by position). The difference of a pair is

$$
d_{r,j} = x_{r,j} - y_{r,j}.
$$

The two blocks of a pair are 40 ms apart, so a drift of the machine that is
slower than that cancels in $d$; it does not cancel in $x$ or $y$ alone.

**Net time and its interval.** The net time of a side is the median of all its
differences,

$$
\nu = \operatorname{med}_{r,j}\, d_{r,j}.
$$

Blocks of one round come from one process and share memory layout, frequency
state and system noise, so they are not independent. The interval of $\nu$ is
a two-level percentile bootstrap that keeps the pairs intact: a replicate draws
$R$ rounds with replacement, then draws the $B$ pairs of each chosen round with
replacement, and $\nu^*$ is the median of the $RB$ drawn differences; the 2.5%
and 97.5% quantiles of 2000 seeded replicates are the interval.

**Ratio.** $\hat\rho = \nu_F / \nu_R$. The two sides run in different
processes and share no structure, so their replicates are drawn independently,
$\rho^*_b = \nu^*_{F,b} / \nu^*_{R,b}$ (with $\rho^*_b = +\infty$ when
$\nu^*_{R,b} \le 0$). Replicate $b$ of one side is divided by replicate $b$ of
the other only to form the distribution of the ratio; it is not a pairing. The
seed of every draw is derived from the run seed, the case, the side and the
purpose, so two sides never share a stream, even when their data are identical.
The interval $[\rho_{lo}, \rho_{hi}]$ is the 2.5% and
97.5% quantiles of the $\rho^*_b$. The raw ratio of the 0.11.0 method, the
median of the case blocks over the median of the case blocks, is kept beside
it, with its interval from a bootstrap that pairs the rounds of the two sides.

**Criterion.** A case meets the target when $\rho_{hi} \le 3$. This is a
one-sided 97.5% statement made from a two-sided 95% interval, so it is
conservative. A resolved case that does not meet it is marked borderline when
$\rho_{lo} \le 3 < \rho_{hi}$.

**Unresolved.** A case is reported as unresolved, and never as met, when
(1) the 2.5% quantile of $\nu^*_R$ is at most zero, or $\nu_R \le 0$ (the
reference net is not distinguishable from zero), (2) $\nu_F \le 0$, or (3)
$\rho_{hi} / \rho_{lo} > 1.25$ (the interval is too wide; in the 0.11.0 summary
the raw interval has $\rho_{hi}/\rho_{lo}$ of 1.02 at the median case and 1.07 at
the worst). The raw ratio decides such a case and is printed as "met (raw)" or
"not met (raw)"; it is never counted among the met cases.

**Flags.** The null loop scales with the clock, so the null blocks are a
thermometer. With $n_r$ the median of the null blocks of round $r$, a side is
flagged `d` (drift) when $\max_r |n_r / \operatorname{med}_r n_r - 1|$ exceeds
5%. A case is flagged `o` (order) when the mean of $d$ over the pairs where the
null ran first differs from the mean over the pairs where it ran second by more
than 5% of $\nu$. Flags are reported; they remove no data and change no
verdict by themselves (a drift between rounds widens the interval, and an
interval above the width bound makes the case unresolved).

A raw cell is flagged as noisy when the half-width of its median interval
exceeds 5% of the median or when the medians of the rounds spread (maximum
minus minimum) by more than 10% of the pooled median, on either side.

Nothing is removed from the data after it is measured: not by hand, not by a
rule that looks at the result.

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

### The null of a case: the same loop without the library call

The null removes everything the library needs to do and nothing else, so that
the net time is what the library call costs.

- **`floating`.** A second implementation of the same case, run by Maremark
  next to the operation (the blocks of the implementations are interleaved, each
  implementation has its own calibration). Its closure has the shape of the
  operation closures, an indirect call with the same arguments returning its
  first one, and it loads from `expected` instead of the operands so that its
  output validates against the reference. It keeps the closure call, the array
  loads, the reference-counted store of a result and Maremark's per-pass work. It
  removes the library call and the allocation, construction and release of a
  result. The operation of a case is a closure chosen at run time by the
  operation name, and the generated C calls it through the closure object
  (`f->code(f, a, b)`, checked on the release build). A top-level function with a
  known body would be called directly and could be inlined, which would make the
  null cheaper than the harness part of the case and the net larger, so the null
  closure is held in a `Ref` and is called through the closure object the same
  way (checked in the generated C as well).
- **MPFR and libmpdec.** `pass_null` runs the loop of the case with the same
  operand and result accesses (the three operand pointers of every row, and the
  context and the status of the decimal calls) handed to an empty `asm` statement,
  so the compiler can neither drop the accesses nor fuse the loop. For binary
  the null computes the three row addresses (`a[i]`, `b[i]` and `r[i]` are
  addresses into arrays of `mpfr_t`); for decimal it loads three pointers from
  the pointer arrays, and takes the address of the context and of the status.
  That is exactly what `pass` does before the call.

What the null cannot remove, and what the net therefore still contains:

1. The call itself: argument set-up and return of `mpfr_add` are in the net of
   the reference; the direct call into the library is in the net of `floating`,
   while the closure that reaches it is in the null. The closure belongs to the
   harness, the library call to the library.
2. Cache, branch-predictor and allocator state differ between a loop with and a
   loop without the call, so the net is an approximation of "the operation
   alone", not an identity. Its error is of the order of the variation of the
   null and is the same for every build of the library, so comparisons between
   builds are not affected.
3. Per-pass and per-block costs (the pair of clock reads, `Bench::keep`) are in
   both blocks and cancel in the difference; they are not removed from the
   individual times.
4. The release of the previous result happens in the next call: in the null
   `out[i]` holds a shared value, in the case it frees an allocation. That cost
   is caused by the operation and stays in the net.

A regression of the time on the number of operations per block was considered
and not adopted: it removes per-pass costs but not the per-operation cost of the
harness (the closure call, the array traffic, the reference loop), which is the
largest part of the floor, so a null would still be needed.

### Two configurations of the floating side

The floating side is built and published in named configurations, recorded as
`floating_configuration` in the protocol block of the summary and in the names of
the published files: `native` (the native limb primitives where the build has
them) and `portable` (the portable path forced). The target of the baseline has
to be reached by the portable path as well. The runner passes the name and the
environment variables that select a configuration (`--configuration`,
`--moon-env KEY=VALUE`); how a configuration is selected is defined by the kernel
work, not by the benchmark. One summary, one samples file and one section of the
manual page exist per configuration.

## Correctness and invariants

- The operand file and the reference file are checksummed in `machine.json`.
- A `floating` result that differs from the reference is counted in the
  Maremark validation tally and listed in `results.json`.
- A summary is a function of its samples file (the pairs of every case, per side and round) and of its protocol block; `just bench external recompute` recomputes it and says whether every stored number agrees.
- A pair is used only when both of its blocks were measured; exploratory pairs are never used.
- Seeds are recorded, so the round order and the bootstrap are reproducible
  from the samples; the timings themselves are not.

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
- The correction for the loop floor moves few verdicts. Computed from the 0.11.0 medians with the floating floor then measured (9.21 ns) and a reference floor between 0.4 and 1.1 ns, 43 of 59 cases are above 3 on the raw ratio and 42 on the net ratio: only `decimal_gda` multiplication at 100 digits (3.03) changes side. The method makes the number honest; it does not move the target.
