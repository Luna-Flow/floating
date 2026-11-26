# decimal performance

<!-- historical-performance-baseline: 0.7.1 -->

## Method and scope

The command `just bench decimal --target native` runs the current Maremark suite
in `tooling/src/bench/decimal` and writes `.tmp/bench/decimal.jsonl` plus its
analysis file. This is a reproducible measurement artifact, not an immutable
release gate. The current branch has no checked-in decimal performance manifest
or threshold workflow; measurements use the Maremark suite.

## Workload

The suite measures add, multiply, and divide at 9, 34, 128, and 512 decimal
digits. Each cell validates every output against an exact `BigInt` reference.
Input creation and expected-value construction stay outside the timed payload.

Each cell compares three paths:

| Path label | Implementation |
| --- | --- |
| `kernel/coefficient` | `BigInt` coefficient baseline |
| `core/decimal` | contextual `Decimal` path (`*_ctx` operations) |
| `full/checked` | full `DecimalChecked` path |

The reference exponent and precision implementation limits admit contexts up to
`999,999,999`. Such contexts are valid, though they can require very large
coefficient work: debug-native probes at the `999,999,999` limit took more
than 25 seconds for some `plus`, `min`, and `quantize` cases (method not
recorded). Choose a smaller precision for interactive work and treat the large
limit as a compatibility limit.

## Reading results

In the output, `MAREMARK_JSONL` is the raw versioned event stream and
`MAREMARK_HOTSPOT` is the paired layer-overhead analysis. Results describe this
tree, toolchain, and target. They are useful for finding a hotspot, but they do
not establish a universal crossover or a release-wide latency bound.

## Reproduction

```bash
just bench decimal --target native
just bench all --target native
```

The all-suite run also covers binary, GDA, and interval kernels. It is safe to
compare artifacts only when the target, toolchain, workload, and benchmark
protocol are held constant.

## Semantic gate

Benchmark equivalence checks are necessary but not sufficient. Optimized decimal
routes must also pass coefficient differential tests and the pinned IEEE decimal
and GDA conformance gates before they are accepted. See
[Conformance](../conformance/decimal.md), [Design](../design/decimal.md), and
the [0.7.1 performance and semantic audit](../performance_audit.md).
