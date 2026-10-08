# internal/conformance design

## Design goal

Four corpus frontends report results for very different data (decimal rows,
interval statements, MPFR rows, TestFloat vectors), and the Python tooling
aggregates them across processes. They must agree on what a "case", a
"pass", a "skip" and a "shard" are, or published totals become incomparable.
`internal/conformance` fixes that vocabulary once: a disposition per case,
counters with fixed identities, and one shard rule.

## Mathematical background

### Results and counters

A result is a tuple $(\mathit{id}, \delta, \pi, m)$ with disposition
$\delta \in \{\mathsf{E}, \mathsf{D}, \mathsf{L}, \mathsf{U}\}$ (executable,
diagnostic, legacy, unsupported), pass bit $\pi$ and message $m$. For a list
$R$ of results define the counter vector

$$
c(R) = \sum_{r \in R} \begin{cases}
e_{\text{exec}} + e_{\text{pass}} & \delta = \mathsf{E},\ \pi,\\
e_{\text{exec}} + e_{\text{fail}} & \delta = \mathsf{E},\ \neg\pi,\\
e_{\text{skip}} + e_{\delta} & \delta \in \{\mathsf{D}, \mathsf{L}, \mathsf{U}\},
\end{cases}
\qquad \text{selected}(R) = |R| ,
$$

where the $e$ are unit vectors in $\mathbb{N}^{7}$. `RunSummary::from_results`
computes exactly $c(R)$ and $|R|$ and stores the caller's total $T$.

### Shards

For $n \ge 1$ and $0 \le i < n$, shard $(n, i)$ selects the ordinals
$S_i = \{ k \in \mathbb{N} : k \bmod n = i \}$.

## Design decisions

### Four dispositions, one failure notion

Only executable results can fail. Distinguishing diagnostic, legacy and
unsupported skips lets a report say *why* rows were not run: a diagnostic row
is not a test (no claim is lost), an unsupported row is a missing feature (a
claim is lost), a legacy row follows retired conventions. `success()` means
"no executable case failed"; stricter verdicts are layered on top by the
caller (the ITL frontend also fails on diagnostics, the CLIs optionally on
unsupported rows).

### Round-robin shards

Assigning ordinal $k$ to shard $k \bmod n$ needs no knowledge of the total,
can be decided while streaming, and spreads neighbouring (often similar-cost)
cases across shards. Validation is separated (`try_new`) from use, so
`selects` is a single comparison.

### `total` is supplied, `merge` takes the maximum

The number of cases before sharding is known to the caller, not to a shard's
result list. Every shard of a run reports the same total $T$, so the maximum
in `merge` returns $T$ whatever the number of parts, while the sum would
count it $n$ times.

### One-based locations

`SourceLocation` clamps line and column to at least 1, so formatted
diagnostics (`file:line:column: message`) are always valid editor positions,
even for callers that pass 0 for "unknown".

## Correctness / invariants

**Counter identities.** For every summary,
$\text{selected} = \text{executable} + \text{skipped}$,
$\text{executable} = \text{passed} + \text{failed}$ and
$\text{skipped} = \text{diagnostic} + \text{legacy} + \text{unsupported}$.
Each summand of $c(R)$ adds 1 to exactly one side of each identity, so they
hold for `from_results`; `merge` adds counters componentwise, which preserves
linear identities.

**Shards partition the ordinals.** Every $k$ has exactly one residue modulo
$n$, so the $S_i$ are disjoint and cover $\mathbb{N}$. Among the first $N$
ordinals, shard $i$ receives

$$
|S_i \cap \{0, \dots, N-1\}| = \left\lceil \frac{N - i}{n} \right\rceil ,
$$

so shard sizes differ by at most one.

**Merging shards gives the serial counters.** $c$ is a monoid homomorphism
from lists under concatenation to $(\mathbb{N}^7, +)$:
$c(R \mathbin{+\!\!+} R') = c(R) + c(R')$, and likewise
$|R \mathbin{+\!\!+} R'| = |R| + |R'|$. If the results of the shards are the
results of the serial run restricted to $S_0, \dots, S_{n-1}$ (true whenever a
case's result does not depend on the other cases), then

$$
\operatorname{merge}\bigl(\mathrm{fr}(T, R|_{S_0}), \dots,
\mathrm{fr}(T, R|_{S_{n-1}})\bigr)
\text{ and } \mathrm{fr}(T, R)
$$

have equal counters and equal totals; only the order of the result list
differs (grouped by shard).

**Immutability.** Summaries copy result arrays on construction and on
`results()`, so callers cannot change a summary after the fact.

## Alternatives rejected

- **A single "skipped" counter.** It would hide the difference between
  non-tests and missing features, which is exactly what conformance claims
  must state.
- **Contiguous shards.** They need the total in advance and concentrate
  expensive files in one shard.
- **Public frontend use of these types.** Frontends wrap them instead, so this
  package can evolve without breaking published APIs.

## Boundaries

- No parsing of corpora, no execution, no IO, no JSON: those belong to the
  frontends and [internal/runner_cli](runner_cli.md).
- No timing or performance data.
- No check that a result's `passed` bit agrees with its disposition.
- Internal: not importable outside `Luna-Flow/floating`, no stability promise.
