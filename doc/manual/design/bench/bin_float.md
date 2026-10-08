# bench/bin_float design

## Design goal

Measure the cost of each layer of the binary stack separately, on
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
| `bin-float/add`, `bin-float/mul`, `bin-float/div` | 53, 128, 512, 2048 bits | `kernel/coefficient` (`BinCoeff`), `core/bin-float` (`BinFloat` operators), `full/checked` (`BinFloatResult`) | `Development` |
| `bin-float/elementary/OP` for 28 functions (`exp`, `exp2`, `exp10`, `expm1`, `ln`, `log2`, `log10`, `log1p`, `sqrt`, `rootn`, `pow`, `hypot`, `sin`, `cos`, `tan`, `sinpi`, `cospi`, `tanpi`, `asin`, `acos`, `atan`, `atan2`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh`) | 53, 128, 512 bits of precision | `core/bin-float` (aborting methods), `full/checked` (`BinFloatResult`) | `Development` |
| `bin-float/autotune/square` | 4, 8, 16, …, 1024 limbs of 32 bits | `mul-self` (`x.mul(x)`), `square` (`x.square()`) on `BinCoeff` | `RegressionGate` |

Arithmetic inputs are fixed bit patterns with the top and bottom bits set; the precision is the sum of the operand bit lengths plus 4, and for `div` the dividend is the product of the two patterns, so every result is exact and every path computes the same number. Elementary inputs are 1.25, 0.5 and 0.25 at the dataset precision, each inside the domain of the functions it is used with. The square inputs are patterns of the given limb count; the experiment picks the faster of two equivalent algorithms per size and reports the crossover size.

### Correctness oracle

Arithmetic outputs are checked against the exact `BinCoeff` result, elementary outputs against the core result (so the checked path must agree with the core), and square outputs against `x.square()`. An output that disagrees with the oracle is counted as a
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
