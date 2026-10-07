# `bench/decimal` Design

## Responsibility

Separate coefficient cost from contextual `Decimal` and `DecimalChecked` overhead.

## Data Flow

Deterministic decimal coefficients are materialized before timing and evaluated at 9, 34, 128, and 512 digits.

## Invariants

Precision is large enough for exact arithmetic, so every layer is checked against the same integer reference.

## Effects

Only explicitly included skipped tests measure time and emit artifacts.

