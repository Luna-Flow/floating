# `ball_float` Performance

## Measurement Boundary

`just bench ball-float --target native` runs the current Maremark suite in
`src/bench/ball_float` and writes `.tmp/bench/ball-float.jsonl` plus its
analysis file. The artifact measures layer cost on the current target; it is
not an IEEE 1788 completeness claim or a release-wide latency guarantee.

## Workload

The suite measures add, multiply, and divide at 53, 128, 512, and 2,048 bits.
Each cell compares the binary kernel, core `BallFloat`, and full checked path.
The expected value is an exact binary result, and the ball and checked outputs
must match it as singleton enclosures before timing observations are accepted.

## Reading Results

`MAREMARK_JSONL` is the raw event stream and `MAREMARK_HOTSPOT` reports paired
kernel-to-core and core-to-checked overhead. A lower layer cost does not imply a
tighter enclosure: directed rounding, decorations, poles, and conservative
fallbacks remain semantic responsibilities of the core path.

## Reproduction

```sh
just bench ball-float --target native
just bench all --target native
```

Compare artifacts only with the same target, toolchain, workload, and benchmark
protocol. Normal benchmark tests compile plans but skip timing.

## Semantic Gate

Performance evidence is subordinate to enclosure correctness. The 0.7.1
interval gate passes 4,656/4,656 selected strict ITF1788 cases, including the
integer-power regression boundary. See [Conformance](./conformance.md),
[Design](./design.md), and the [0.7.1 performance and semantic
audit](../performance_audit.md).
