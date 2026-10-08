# bench/ball_float design

## Design goal

Measure the cost of each layer of the interval stack separately, on
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
median of the differences is not the difference of the medians in general
($\operatorname{med}(c - k) \ne \operatorname{med}(c) - \operatorname{med}(k)$),
so `core_pct` is not $100\,(\operatorname{med} c / \operatorname{med} k - 1)$;
it is the quantity whose uncertainty the paired bootstrap describes. The
estimators, the pairing and the bootstrap interval are derived in the
[bench design](../bench.md).

## Design decisions

### Workloads

| Case | Datasets | Implementations | Protocol |
| --- | --- | --- | --- |
| `ball-float/add`, `ball-float/mul`, `ball-float/div` | 53, 128, 512, 2048 bits | `kernel/bin-float` (`BinFloat`), `core/ball-float` (`BallFloat`), `full/checked` (`BallFloatResult`) | `Development` |

Inputs are exact singleton intervals built from fixed bit patterns; the precision is the sum of the operand bit lengths plus 4 and the `div` dividend is the product of the patterns, so every result is exact and every interval result must stay a singleton.

### Correctness oracle

The reference is the `BinFloat` kernel result itself, which is exact for these inputs; kernel outputs must equal it, and interval outputs must be singletons whose center equals it. An output that disagrees with the oracle is counted as a
failure and the performance test asserts that there is none, so a comparison
is never between paths that compute different things.

### Exact inputs

Exact results make the arithmetic work identical across paths: no path can
win by rounding earlier, and the measured difference is the cost of
representation, context handling and checking.

## Correctness and invariants

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
