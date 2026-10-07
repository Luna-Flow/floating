# `bench/bin_float` Design

## Responsibility

Measure coefficient kernels, `BinFloat`, checked wrappers, the elementary matrix, and square crossover candidates.

## Data Flow

Exact generated coefficients feed coefficient, core, and checked implementations under one validated Maremark case.

## Invariants

Arithmetic layers must return the same exact value; elementary core and checked paths must agree before timing; tuning compares only `mul(x, x)` with `square(x)`.

## Effects

Skipped tests stream `mmka_1` JSONL and hotspot/tuning lines only when the unified runner includes them.

