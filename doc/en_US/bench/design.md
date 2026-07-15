# `bench` Design

## Responsibility

Build immutable Maremark plans and reduce versioned observations without coupling numeric packages to benchmark code.

## Data Flow

Datatype fixtures produce inputs, Maremark validates reference equivalence, balanced timed blocks emit observations, and pure reducers calculate paired hotspots or tuning winners.

## Invariants

Setup stays outside timed payloads; comparisons use matching dataset and block identifiers; auto-tune candidates must be semantically equivalent.

## Effects

The shared package is pure except for its explicit async runner boundary. JSONL printing and filesystem writes remain in tests and `tools/benchmark.py`.

