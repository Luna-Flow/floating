# Performance and semantic audit

<!-- historical-performance-baseline: 0.6.1 -->
<!-- historical-performance-baseline: 0.7.0 -->
<!-- historical-performance-baseline: 0.7.1 -->

This guide records the audit of the optimizations that form the repository's
performance baseline, release 0.7.1. It lists the optimized paths, the
semantic repair found during review, the proofs that each fast path returns
exactly what the general path returns, and the evidence boundary of the
performance claims. Later work, including the current branch, adds no new
performance measurement, so this audit remains the reference for the optimized
paths.

## Scope

The audit covers commits `69084bc`, `7904016`, `23005ed` and `4fd41ad`, which
followed release 0.7.0, plus the GDA coefficient helper and the interval
regression repair made during the 0.7.1 release review. It treats observed
behaviour, normative expectation, implementation choice and acceptance
evidence as separate facts.

## Issue matrix

| Row | Class | Observed | Expected | Change | Acceptance evidence |
| --- | --- | --- | --- | --- | --- |
| GDA coefficient kernels | implementation gap | GDA fast paths added small representations, remainder-only division and half-power comparison | coefficient identities, cohorts, flags, traps and sticky status unchanged | use canonical `GdaCoeff` operations and keep the shared GDA finalizer | 93 package tests, 8 frontend tests, 64,986/64,986 `official`, 16,124/16,124 `official0` |
| IEEE decimal paths | semantic-risk optimization | exact and bounded division paths skip repeated generic work | exact decimal results, rounding, quantum, flags and exceptional values match IEEE behaviour | guard fast paths with finite-domain, factor, bound and finalization predicates; fall back otherwise | 94 package tests and 15,763/15,763 four-target IEEE cases |
| Binary IEEE paths | semantic-risk optimization | exact-top ordering, split round/sticky extraction and coefficient dispatch replace wider work | contextual value, rounding, flags, signed zero and interchange bits identical | keep exact coefficient construction and route every result through contextual rounding | 68 package tests and 7,464,503/7,464,503 binary cases |
| Interval endpoint dispatch | semantic deviation, fixed | optimized `pown` reused endpoint directions across sign regions; negative intervals could give $\underline{y} > \overline{y}$ or lose one ulp | every returned interval is ordered and contains the exact image | select endpoints from monotonicity and round each candidate outward; add negative-half-axis tests | 42 package tests, integer power 174/174, strict ITF1788 4,656/4,656 |
| Release documentation | documentation gap | 0.7.0 was still named as the current baseline | current references name the new baseline; history stays in the changelog | update metadata and add this audit | `python3 tools/doc_quality.py` |

## Optimization proofs

### Exact coefficient paths

For a coefficient $a \ge 0$ and a divisor $d > 0$ the remainder is

$$
r = a - \left\lfloor \frac{a}{d} \right\rfloor d, \qquad 0 \le r < d .
$$

A remainder-only kernel returns the same $r$ as a quotient-and-remainder
kernel, so it preserves every observable remainder and every step of the
Euclidean algorithm. The GDA half-power predicate compares $a$ with
$5 \cdot 10^{\,\operatorname{digits}(a) - 1}$ by its leading decimal digit and
whether its tail is non-zero; it is exact, not a floating estimate.

The IEEE decimal exact-division path first divides out
$g = \gcd(c_x, c_y)$. A quotient $c_x / c_y$ has a finite decimal expansion
exactly when the reduced denominator $c_y / g$ has no prime factor other than 2
and 5:

$$
\frac{c_x}{c_y} = \frac{c_x / g}{2^{i} 5^{j}}
= \frac{(c_x / g) \cdot 2^{k-i} 5^{k-j}}{10^{k}}, \qquad k = \max(i, j).
$$

The path is taken only then. It builds the exact coefficient and exponent and
calls the existing finalizer; any unmet factor, bound or special-value
precondition returns to the generic algorithm. The optimization changes the
route to the exact value, not the IEEE rounding or flag rule.

### Binary contextual paths

For a finite dyadic value $c \cdot 2^{e}$, `binary_exact_top(c, e)` is the
exponent of the highest set bit, $e + \operatorname{bitlen}(c) - 1$. Comparing
these tops is equivalent to comparing magnitudes before alignment, including
coefficients with different trailing powers of two. When a far addend is
discarded, the split keeps the first discarded bit (the round bit) and the OR
of all later bits (the sticky bit). These are exactly the inputs of the
rounding decision: for the truncated magnitude $t$ and the discarded fraction
$f \in [0, 1)$ of one ulp,

$$
\text{round bit} = [f \ge \tfrac{1}{2}], \qquad
\text{sticky bit} = [f \notin \{0, \tfrac{1}{2}\}],
$$

and every IEEE rounding direction is a function of $t$'s last bit, the sign,
and these two bits. The fast path therefore feeds the same rounding inputs
while never materializing an enormous aligned coefficient.

### Directed interval paths

An interval operation must keep the inclusion invariant
$f(X) \subseteq [\underline{y}, \overline{y}]$ and the storage invariant
$\underline{y} \le \overline{y}$. For an exact endpoint candidate $y$,
$\operatorname{RD}(y)$ is a valid lower certificate and $\operatorname{RU}(y)$
a valid upper certificate. The `pown` branches use this monotonicity table for
$x \mapsto x^{n}$:

| Domain | $n > 0$ odd | $n > 0$ even | $n < 0$ odd | $n < 0$ even |
| --- | --- | --- | --- | --- |
| negative half-axis | increasing | decreasing | decreasing | increasing |
| positive half-axis | increasing | increasing | decreasing | decreasing |
| interval containing zero | endpoint order | $0$ up to the outward-rounded maximum | pole: Entire if $0$ is interior, a half-line if $0$ is an endpoint | pole: $[\min(\underline{x}^{n}, \overline{x}^{n}), +\infty)$ with $0^{n} = +\infty$, lower bound rounded down |

The implementation selects the mathematical endpoint first and then applies
the direction its role requires. For an interval across zero with even
$n > 0$, both finite extremum candidates are rounded upward for the upper
bound. `quantize_interval` then rounds once more outward. The proof is local to
the declared operation and precision contract and makes no claim about the
unsupported reverse operations.

## Performance evidence

| Area | Measurement | Interpretation |
| --- | --- | --- |
| binary, decimal, GDA and interval kernels | `just bench all --target native` | all four Maremark suites produced valid artifacts |
| binary square policy | `just bench auto-tune --target native` | a target-specific policy artifact; raw observations can be non-monotonic and are not a universal threshold |
| IEEE and GDA fast paths | benchmark package tests plus the conformance gates | a fast route is admissible only while the semantic oracle stays green |
| interval endpoint dispatch | `src/bench/ball_float` and strict ITF1788 | lower cost is acceptable only with ordered, outward-rounded enclosures |

Generated artifacts live under `.tmp/bench/` and are not published as API data.
Re-run the commands on the target hardware before promoting a crossover. The
workload is evidence about the audited tree; it does not prove a speedup for
every release, equivalence across targets, or a latency bound.

## Acceptance matrix

| Check | Result |
| --- | --- |
| `sh tools/run_moon_clean_exec.sh test src/decimal_gda --target native --deny-warn --frozen --no-parallelize` | 93/93 passed |
| `sh tools/run_moon_clean_exec.sh test src/decimal --target native --deny-warn --frozen --no-parallelize` | 94/94 passed |
| `sh tools/run_moon_clean_exec.sh test src/bin_float --target native --deny-warn --frozen --no-parallelize` | 68/68 passed |
| `sh tools/run_moon_clean_exec.sh test src/ball_float --target native --deny-warn --frozen --no-parallelize` | 42/42 passed |
| `just gate binary 8` | 7,464,503/7,464,503 passed |
| `just gate decimal 8` | 15,763/15,763 passed |
| `just gate decimal_gda 8` | 64,986/64,986 and 16,124/16,124 passed |
| `just gate interval 8` | 4,656/4,656 passed |
| `python3 tools/doc_quality.py` | passed |

These counts describe the audited tree. The gates have grown since (the binary
gate now runs the full IEEE operation matrix); [verification](./verification.md)
lists the current claims.

## Reviewer self-review

- Contribution: pass. The audit records concrete optimization boundaries and a
  repaired semantic failure instead of an unexplained speedup.
- Clarity: pass. Each proof separates representation, monotonicity, rounding
  direction and evidence.
- Experimental strength: needs replication. The native artifacts are valid,
  but noisy auto-tune observations should be repeated before a threshold is
  promoted.
- Completeness: pass for the declared pinned corpora; it does not cover every
  standard operation or every real input.
- Soundness: pass for the covered branches after the negative-half-axis
  regression fix and the full IEEE 1788 gate.

## Claim–evidence map

| Claim | Evidence | Status |
| --- | --- | --- |
| fast coefficient routes preserve the declared numerical results | exact-kernel identities, package tests, IEEE and GDA conformance | supported within the declared APIs and preconditions |
| interval `pown` keeps ordered outward enclosures | monotonicity table, negative-half-axis regression, 4,656 strict ITF1788 cases | supported for the declared forward interval operations |
| the optimized paths are performance-audited | native Maremark `all` and `auto-tune` artifacts | supported as measurement evidence, not a universal speed claim |
| every target and operation has equivalent performance | no paired cross-target artifact | not claimed |

## Limits

The semantic claims are bounded by the pinned corpora, the public operations,
target-specific precision rules and the explicit fallback contracts. The 0.6.1
elementary manifest remains the comparison baseline of the elementary
performance gate, with 0.7.1 as its candidate. No public API, rounding rule,
error signal or enclosure contract is changed merely to improve a benchmark.
