# `bin_float_bench` Design

## Responsibility

Benchmark-only package for representative `BinCoeff` operations.

## Data Flow

The test harness constructs fixed operand shapes, runs MoonBit bench cells, and reports measurements without affecting production dispatch.

## Algorithms And Invariants

Benchmarks must retain results and keep setup outside timed loops; measurements are evidence, never correctness contracts.

## Failure And Effects

Skipped benchmark tests allocate and observe time locally; they perform no application IO.

## Implementation Trade-offs

A separate package prevents benchmark-only imports from entering `bin_float`, at the cost of white-box threshold benches remaining in the core package.

## Stability

The package is maintained as repository infrastructure. Generated declarations may change with the runners and do not promise downstream compatibility.
