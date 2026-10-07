# `bench/ball_float` Design

## Responsibility

Isolate binary-kernel, interval-core, and checked-wrapper costs.

## Data Flow

Exact singleton intervals make add, multiply, and divide comparable to their `BinFloat` reference results.

## Invariants

Core and checked outputs must remain singleton intervals centered on the reference value.

## Effects

Maremark owns calibration and timing; the Python runner owns process and artifact IO.

