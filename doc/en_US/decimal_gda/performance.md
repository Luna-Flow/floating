# `decimal_gda` Performance

## Measurement Boundary

`just bench decimal-gda --target native` runs the current Maremark suite in
`src/bench/decimal_gda` and writes `.tmp/bench/decimal-gda.jsonl` plus its
analysis file. The independent quick fixture can be run with
`python3 tools/run_gda_benchmark.py`; it writes `.tmp/bench/gda-quick-native.json`
and uses three native runs per cell. Neither artifact is a universal speed
claim or a substitute for the conformance gate.

## Workload

The Maremark suite measures add, subtract, multiply, divide, FMA, and parse at
1, 9, 18, 34, and 128 decimal digits. It compares the core `GdaContext` path
with the full checked path and validates both against the core result before
reporting layer overhead.

## Reading Results

`MAREMARK_JSONL` is the raw event stream and `MAREMARK_HOTSPOT` reports paired
core-versus-checked overhead. The quick fixture additionally records per-
operation medians and dispersion. Interpret these measurements only for the
recorded target, toolchain, fixture, and workload; they do not establish a
cross-target threshold or a fixed latency bound.

## Reproduction

```sh
just bench decimal-gda --target native
python3 tools/run_gda_benchmark.py
just bench all --target native
```

Use the same target and toolchain when comparing artifacts. Normal benchmark
tests compile their plans but skip timing, so an explicit benchmark command is
required for measurement.

## Semantic Gate

The timing path is accepted only alongside the independent GDA state model and
the pinned legal scalar corpus: 64,986/64,986 current rows and 16,124/16,124
legacy rows pass in the 0.7.1 audit. See [Conformance](./conformance.md),
[Design](./design.md), and the [0.7.1 performance and semantic
audit](../performance_audit.md).
