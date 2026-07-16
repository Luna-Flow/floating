# 0.7.1 Performance And Semantic Audit

<!-- historical-performance-baseline: 0.6.1 -->
<!-- historical-performance-baseline: 0.7.0 -->

This page is the English structural source for the 0.7.1 optimization audit.
It records the four optimization commits after 0.7.0, the working-tree
semantic repairs found during release review, and the evidence boundary for
performance claims.

## Scope

The audit covers commits `69084bc`, `7904016`, `23005ed`, and `4fd41ad`, plus
the pending GDA coefficient helper and the interval regression repair in this
release tree. The audit treats observed behavior, normative expectations,
implementation choices, and acceptance evidence as separate facts.

## Issue Matrix

| Row | Class | Observed | Expected | Change | Acceptance evidence |
| --- | --- | --- | --- | --- | --- |
| GDA coefficient kernels | implementation gap | GDA fast paths added small representations, remainder-only division, and half-power comparison | coefficient identities, cohorts, flags, traps, and sticky status remain unchanged | use canonical `GdaCoeff` operations and preserve the shared GDA finalizer | 93 package tests, 8 frontend tests, 64,986/64,986 `official`, 16,124/16,124 `official0` |
| IEEE decimal paths | semantic-risk optimization | exact and bounded division paths bypass repeated generic work | exact decimal results, rounding, quantum, flags, and exceptional values match IEEE behavior | guard fast paths with finite-domain, factor, bound, and finalization predicates; fall back otherwise | 94 package tests and 15,763/15,763 four-target IEEE cases |
| Binary IEEE paths | semantic-risk optimization | exact-top ordering, split round/sticky extraction, and coefficient dispatch replace wider work | contextual value, rounding, flags, signed zero, and interchange bits remain identical | retain exact coefficient construction and route all results through contextual rounding | 68 package tests and 7,464,503/7,464,503 binary cases |
| Interval endpoint dispatch | semantic deviation found and fixed | optimized `pown` reused endpoint directions across sign regions; negative intervals could produce `lo > hi` or lose one ulp | every returned interval is ordered and contains the mathematical image | select endpoints from monotonicity and round each candidate outward; add negative-half-axis coverage | 42 package tests, integer-power 174/174, strict ITF1788 4,656/4,656 |
| Release documentation | documentation gap | 0.7.0 remained the current baseline in module, manifests, and localized prose | all current references identify 0.7.1 while historical notes remain historical | update current metadata and add synchronized audit pages | `python3 tools/doc_quality.py` |

## Optimization Proofs

### Exact coefficient paths

For a non-negative coefficient `a` and positive divisor `d`, the remainder
operation returns `r = a - floor(a / d) * d` with `0 <= r < d`. Replacing a
quotient/remainder call with a remainder-only kernel therefore preserves every
observable remainder and every Euclidean-algorithm step. The GDA half-power
predicate compares `a` with `5 * 10^(digits(a) - 1)` by its leading decimal
digit and its non-zero tail, so it is exact rather than a floating estimate.

The IEEE decimal exact-division path first removes the coefficient GCD. It is
eligible only when the reduced denominator contains no prime factors other
than 2 and 5. The path constructs the exact decimal coefficient/exponent and
then invokes the existing finalizer; an unmet factor, bound, or special-value
precondition returns to the generic algorithm. Thus the optimization changes
the route to the exact value, not the IEEE rounding or flag rule.

### Binary contextual paths

For a finite dyadic value `c * 2^e`, `binary_exact_top(c, e)` identifies the
highest occupied exact bit. Comparing these tops is equivalent to comparing
the magnitudes before alignment, including coefficients with different
trailing powers of two. When a far addend is discarded, the split operation
retains the first discarded bit and the OR of all later bits; these are exactly
the round and sticky predicates consumed by the contextual rounding function.
The fast path therefore preserves the same exact rounding inputs while avoiding
materialization of an enormous aligned coefficient.

### Directed interval paths

An interval operation must preserve the set inclusion invariant
`image(X) subset [lo, hi]` and the storage invariant `lo <= hi`. For an exact
endpoint candidate `y`, `RoundTowardNegative(y)` is a lower certificate and
`RoundTowardPositive(y)` is an upper certificate. The `pown` branches use the
following monotonicity table:

| Domain | Positive odd power | Positive even power | Negative odd power | Negative even power |
| --- | --- | --- | --- | --- |
| negative half-axis | increasing | decreasing | decreasing | increasing |
| positive half-axis | increasing | increasing | decreasing | decreasing |
| interval containing zero | endpoint order or zero/extreme split | zero to the outward-rounded maximum | pole/whole-real split | pole/whole-real split |

The implementation now selects the mathematical endpoint first and applies
the direction required by its role. Across zero, both finite extremum
candidates use upward rounding for the upper bound. `quantize_interval` then
rounds once more outward. The proof is local to the declared operation and
precision contract; it does not claim unsupported reverse operations.

## Performance Evidence

| Area | Measurement | Interpretation |
| --- | --- | --- |
| Binary, decimal, GDA, and interval kernels | `just bench all --target native` | all four Maremark suites produced valid artifacts under the current tree |
| Binary square policy | `just bench auto-tune --target native` | a target-specific policy artifact is produced; raw observations can be non-monotonic and are not a universal threshold claim |
| IEEE/GDA fast paths | benchmark package tests plus conformance gates | performance routes are admissible only when the semantic oracle remains green |
| Interval endpoint dispatch | `src/bench/ball_float` and strict ITF1788 | lower cost is acceptable only with ordered, outward-rounded enclosures |

The generated artifacts live under `.tmp/bench/` and are intentionally not
published as API data. Re-run the commands on the target hardware before
promoting a crossover. The benchmark workload is evidence about this tree and
does not prove a release-wide speedup, cross-target equivalence, or a universal
latency bound.

## Acceptance Matrix

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
| `python3 tools/doc_quality.py` | passed after version, audit-page, and design-proof changes |

## Reviewer Self-Review

- Contribution: pass — the release records concrete optimization boundaries
  and a repaired semantic failure instead of claiming an unexplained speedup.
- Writing clarity: pass — each proof section separates representation,
  monotonicity, rounding direction, and evidence.
- Experimental strength: needs replication — native artifacts are valid, but
  noisy auto-tune observations should be repeated before threshold promotion.
- Evaluation completeness: pass for the declared pinned corpora; it does not
  imply every standard operation or arbitrary real input.
- Method soundness: pass for the covered branches after the negative-half-axis
  regression and full 1788 gate.

## Claim-Evidence Map

| Claim | Evidence | Status |
| --- | --- | --- |
| Fast coefficient routes preserve the declared numerical results | exact-kernel identities, package tests, IEEE/GDA conformance | supported within the declared APIs and preconditions |
| Interval `pown` preserves ordered outward enclosures | monotonicity table, negative-half-axis regression, 4,656 strict ITF1788 cases | supported for the declared forward interval surface |
| The release is performance-audited | native Maremark `all` and `auto-tune` artifacts | supported as measurement evidence, not as a universal speed claim |
| Every future target and operation has equivalent performance | no cross-target paired artifact in this audit | needs evidence; intentionally not claimed |

## Limits

The semantic claims are bounded by the pinned corpora, the public operation
surface, target-specific precision rules, and the explicit fallback contracts.
The `0.6.1` elementary manifest remains a historical comparison baseline;
`0.7.1` is its current candidate release. No public API, rounding rule, error
signal, or enclosure contract is changed merely to improve a benchmark.
