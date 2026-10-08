# bench/decimal_gda design

## Design goal

Measure the cost of each layer of the GDA decimal stack separately, on
inputs where all layers must produce the same result, so that a change in one
layer shows up as a change in one reported percentage.

## Mathematical background

For one dataset let $k_j$, $c_j$ and $f_j$ be the per-call times of the
kernel, core and checked paths in block $j$ (a case without a kernel path
reports only the second quantity). The reported quantities are

$$
\text{core\_pct} = 100\,\frac{\operatorname{med}_j (c_j - k_j)}{\operatorname{med}_j k_j},
\qquad
\text{full\_pct} = 100\,\frac{\operatorname{med}_j (f_j - c_j)}{\operatorname{med}_j c_j},
$$

the relative median paired overheads of one layer over the layer below. The
estimators, the pairing and the bootstrap interval are derived in the
[bench design](../bench.md).

## Design decisions

### Workloads

| Case | Datasets | Implementations | Protocol |
| --- | --- | --- | --- |
| `decimal-gda/add`, `sub`, `mul`, `div`, `fma`, `parse` | 1, 9, 18, 34, 128 digits | `core/gda` (`@decimal_gda.add` and the other functions with an explicit `GdaContext`), `full/checked` (`GdaDecimalChecked`, which threads the sticky context) | `Development` |

The left operand is a fixed digit pattern of the dataset length, the right operand 2 and the addend 3; the context has precision $\max(9, 2d + 4)$ for $d$ digits and exponent limits $\pm 999999$, so no operation rounds or traps. `parse` reads the pattern text.

### Correctness oracle

Outputs are checked against the core result with structural equality, so the checked path must return the identical decimal, exponent included. An output that disagrees with the oracle is counted as a
failure and the performance test asserts that there is none, so a comparison
is never between paths that compute different things.

### Exact inputs

Exact results make the arithmetic work identical across paths: no path can
win by rounding earlier, and the measured difference is the cost of
representation, context handling and checking.

## Correctness / invariants

- Plan tests compile every specification in ordinary test runs, so the
  benchmarks cannot rot unnoticed.
- Performance tests assert `failed_count == 0`: every output matched its
  oracle.
- Seeds are fixed (`20260715`), so the measurement order and the bootstrap
  resamples are reproducible.

## Alternatives rejected

- **Random inputs per sample.** They would mix input variance into timing
  variance; fixed patterns per dataset isolate the cost of the code.
- **Only end-to-end timings.** A single number cannot tell whether a
  regression is in the kernel, the core or the checked wrapper.

## Boundaries

- Native target only; no claims for other targets.
- No public API; the package exists for `tools/benchmark.py`.
- Measurements are evidence for the performance pages, never for correctness.
