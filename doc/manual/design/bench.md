# bench design

## Design goal

Performance claims in `floating` must be reproducible and must not be
confused with noise. `bench` turns the Maremark framework into a small,
repository-specific toolkit: benchmarks are immutable specifications with a
correctness oracle, every run records its environment and protocol, and
timings are reduced with robust, paired statistics whose uncertainty is
reported as a bootstrap confidence interval. Measurement (timing, streaming
JSONL) happens in the per-core test packages and `tools/benchmark.py`; this
package only describes experiments and reduces their data.

## Mathematical background

### What one observation measures

Maremark first *calibrates* a batch size for each implementation and dataset:
starting from the protocol's minimum $n_0$ iterations, it times a batch and,
while the batch is shorter than the target batch time $T$ (5 ms in the
`Development` preset, 10 ms in `RegressionGate`) and the iteration cap is not
reached, retries with

$$
n_{k+1} = \min\Bigl(n_{\max},\ \max\bigl(n_k + 1,\ \lceil n_k T / t_k \rceil\bigr)\Bigr),
$$

where $t_k$ is the measured batch time. An observation is then one timed
batch of $n$ calls, recorded as the mean per-call time
$x = t_{\text{batch}} / n$ in microseconds. Averaging inside a batch removes
clock granularity; the batch-to-batch variation that remains is what the
statistics below handle.

### Blocks and pairing

The confirmatory phase consists of $m$ blocks ($m = 10$ for `Development`,
$20$ for `RegressionGate`). In block $j$ every implementation is measured
once, in the cyclic order $(j + o) \bmod K$ of the $K$ implementations, with an
offset $o$ derived from the seed, so each implementation runs first equally
often over $K$ consecutive blocks. For a baseline $B$ and a candidate $C$ the
observations are sorted by block and paired:

$$
d_j = c_j - b_j, \qquad j = 1, \dots, m .
$$

Slow drifts (frequency scaling, thermal state, background load) affect $b_j$
and $c_j$ of the same block similarly and cancel in $d_j$.

### Point estimates

With $\operatorname{med}$ the sample median,

$$
\Delta_{\%} = 100 \cdot \frac{\operatorname{med}(d)}{\operatorname{med}(b)},
\qquad
\text{speedup} = \frac{\operatorname{med}(b)}{\operatorname{med}(b) + \operatorname{med}(d)} .
$$

The median has a breakdown point of 50 %: up to half of the blocks can be
arbitrarily disturbed (a preempted batch, a page-fault storm) without moving
the estimate arbitrarily. This is the outlier handling of the `bench`
reductions: no observation is discarded. Maremark's protocols also name an
outlier policy (`ReportOnly` for `Development`, `TukeyFence` for
`RegressionGate`); it is part of the recorded protocol identity, but the
observations are emitted unfiltered and the reductions in this package do not
apply a filter.

The decision compares $\Delta_{\%}$ with a practical threshold $\delta$:
`Faster` if $\Delta_{\%} \le -\delta$, `Slower` if $\Delta_{\%} \ge \delta$,
`Equivalent` otherwise. A difference smaller than $\delta$ is treated as
irrelevant however precisely it is measured.

### Sample quantiles

Maremark uses the linear-interpolation quantile (type 7 of Hyndman and
Fan[^hf]): for sorted values $s_0 \le \dots \le s_{N-1}$ and
$f \in [0, 1]$, with $h = f (N - 1)$,

$$
Q(f) = s_{\lfloor h \rfloor} + \bigl(h - \lfloor h \rfloor\bigr)
\bigl(s_{\lceil h \rceil} - s_{\lfloor h \rfloor}\bigr),
$$

so $Q(1/2)$ is the usual median (the mean of the two middle values for even
$N$).

[^hf]: R. J. Hyndman, Y. Fan, "Sample quantiles in statistical packages",
    *The American Statistician* 50(4), 1996.

### The bootstrap confidence interval

The uncertainty of $\operatorname{med}(d)$ is estimated with the percentile
bootstrap[^efron]. For $r = 1, \dots, R$:

1. draw $m$ indices $i_1, \dots, i_m$ uniformly with replacement from
   $\{1, \dots, m\}$;
2. compute the resampled median $\theta^{*}_r = \operatorname{med}(d_{i_1},
   \dots, d_{i_m})$.

Sort $\theta^{*}_{(1)} \le \dots \le \theta^{*}_{(R)}$. For a confidence level
$c$ (in percent) let $\alpha = (100 - c) / 200$. The interval is

$$
\bigl[\, L, U \,\bigr] = \bigl[\, Q^{*}(\alpha),\ Q^{*}(1 - \alpha) \,\bigr],
$$

with $Q^{*}$ the type-7 quantile of the sorted bootstrap medians. With
$c = 95$ and $R = 10\,000$ this is
$[Q^{*}(0.025), Q^{*}(0.975)]$, i.e. linear interpolation at positions
$249.975$ and $9749.025$ of the sorted resamples (0-based). The interval is
on $\operatorname{med}(d)$ in microseconds (not in percent).

The random indices come from a xorshift64\* generator[^vigna] seeded with the
caller's seed (a zero seed is replaced by a fixed constant), and an index is
the state modulo $m$; the modulo bias is at most $m / 2^{64}$. With a fixed
seed the interval is a deterministic function of the data, so reruns of an
analysis reproduce it exactly.

[^efron]: B. Efron, R. J. Tibshirani, *An Introduction to the Bootstrap*,
    Chapman & Hall, 1993, chapter 13.

[^vigna]: S. Vigna, "An experimental exploration of Marsaglia's xorshift
    generators, scrambled", *ACM TOMS* 42(4), 2016.

### The regression verdict

`is_significant_regression` requires both

$$
\Delta_{\%} \ge \delta \quad\text{and}\quad L > 0 :
$$

the median slowdown must be practically relevant *and* the 95 % interval of
the median paired difference must exclude zero on the slow side. The first
condition guards against flagging tiny but precisely measured changes, the
second against flagging large but noisy ones.

## Design decisions

### Paired medians instead of means

Timing distributions are right-skewed with occasional large outliers. The
mean of differences and a $t$ interval would be dominated by those outliers;
the median of block-paired differences is robust and needs no normality
assumption, and the bootstrap gives its interval without a variance formula
for the median.

### Fixed parameters per use

`confirmatory_regression` fixes $\delta = 3\,\%$, $R = 10\,000$ and
$c = 95\,\%$, so a regression gate cannot be weakened by a caller.
`paired_hotspot` takes $\delta$ and the seed from the caller and uses
$R = 2000$ and $c = 95\,\%$ for exploratory hotspot reports.

### Auto-tuning by minimum median

`tune_dataset` scores each candidate by the median of its valid confirmatory
samples and returns the one with the smallest median, breaking exact ties by
candidate id. The score is passed to `@tune.select_best` as both primary and
secondary criterion, so among the candidates within $\delta$ of the fastest
the smallest secondary, which is again the fastest, wins; the practical
threshold therefore has no effect on the choice. The crossover between two
candidates across scales is computed by Maremark from the per-dataset labels.

### Immutable fixtures with an oracle

`immutable_bench` generates each input once per scale and checks every
output against an independent reference. A faster implementation that
computes the wrong result fails the run instead of winning a comparison.

### Environment as data

`environment` records the target, profile and a data-type label with every
run, and marks what only the outer tool knows (machine, frequency policy,
commit) as `external-metadata`. A reader of two artifacts can then tell
whether their numbers are comparable; the package itself does not compare
runs across environments.

## Correctness / invariants

- **Determinism of the reduction.** For fixed observations and seed,
  `paired_hotspot`, `confirmatory_regression` and `tune_dataset` return the
  same values on every run (sorting by block id, seeded generator,
  deterministic tie-breaking).
- **Pairing.** Samples are paired by block order. Unequal sample counts are an
  error (`MismatchedPairs`), never a silent truncation.
- **Interval ordering.** $L \le U$, because $Q^{*}$ is monotone in its
  argument and $\alpha < 1 - \alpha$ for $c > 0$.
- **Scale invariance.** Multiplying all samples by a constant $\lambda > 0$
  multiplies $\operatorname{med}(d)$, $L$ and $U$ by $\lambda$ and leaves
  $\Delta_{\%}$, the decision and the verdict unchanged, so the unit of time
  does not matter.

## Alternatives rejected

- **Discarding outliers before averaging.** Any fence needs a tuning constant
  and silently changes the sample; the median makes it unnecessary.
- **Unpaired comparison of two sample sets.** Drift between the measurement of
  $B$ and $C$ would enter the difference directly.
- **Normal-theory intervals.** They assume symmetric errors that timing data
  does not have.

## Boundaries

- No timing, process control or file output: Maremark's runner and
  `tools/benchmark.py` do that.
- No absolute performance targets; thresholds apply to relative differences.
- Performance results never change correctness claims, and the benchmarks run
  only on the native target.
