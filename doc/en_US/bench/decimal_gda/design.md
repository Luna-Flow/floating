# `bench/decimal_gda` Design

## Responsibility

Measure GDA core operations and sticky-context checked composition.

## Data Flow

Exact non-trapping inputs cover add, multiply, divide, fused multiply-add, and parse across representative digit counts.

## Invariants

Core and checked values must be equal before their observations enter hotspot analysis.

## Effects

Context creation, input parsing, JSONL streaming, and reporting stay outside timed payloads.

