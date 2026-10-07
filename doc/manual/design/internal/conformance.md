# `internal/conformance` Design

## Responsibility

Pure shared model for conformance locations, dispositions, shards, and summaries.

## Data Flow

Frontends construct immutable case results; summary folding counts categories, merge combines disjoint shards, and success depends on executable failures.

## Algorithms And Invariants

Shard selection is deterministic by case index, and unsupported or diagnostic rows never masquerade as passed executable rows.

## Failure And Effects

The package performs no parsing, arithmetic, IO, or scheduling effects.

## Implementation Trade-offs

One shared model prevents count drift across runners, while frontend wrappers retain domain-specific public names.

## Stability

The package is maintained as repository infrastructure. Generated declarations may change with the runners and do not promise downstream compatibility.
