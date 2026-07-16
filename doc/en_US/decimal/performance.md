# `decimal` Performance

## Measurement Boundary

`just bench decimal --target native` runs the current Maremark suite in
`src/bench/decimal` and writes `.tmp/bench/decimal.jsonl` plus its analysis
file. This is a reproducible measurement artifact, not an immutable release
gate. There is no checked-in decimal performance manifest or threshold workflow
in 0.7.1; current instructions use the Maremark suite below.

## Workload

The suite measures add, multiply, and divide at 9, 34, 128, and 512 decimal
digits. Each cell compares the coefficient kernel, the core `Decimal` path,
and the full checked path against an exact `BigInt` reference. Input creation
and expected-value construction stay outside the timed payload.

## Reading Results

`MAREMARK_JSONL` is the raw versioned event stream and `MAREMARK_HOTSPOT` is
the paired layer-overhead analysis. Results describe this tree, toolchain, and
target. They are useful for finding a hotspot, but they do not establish a
universal crossover or a release-wide latency bound.

## Reproduction

```sh
just bench decimal --target native
just bench all --target native
```

The all-suite run also covers binary, GDA, and interval kernels. It is safe to
compare artifacts only when the target, toolchain, workload, and benchmark
protocol are held constant.

## Semantic Gate

Benchmark equivalence checks are necessary but not sufficient. Optimized
decimal routes must also pass coefficient differential tests and the pinned
IEEE decimal and GDA conformance gates before they are accepted. See
[Conformance](./conformance.md), [Design](./design.md), and the [0.7.1
performance and semantic audit](../performance_audit.md).
