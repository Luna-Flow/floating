# `consistency` Design

## Responsibility

White-box package for cross-package laws and public-surface audits.

## Data Flow

Tests compare aliases, capability traits, checked wrappers, semantic projections, and migration invariants across numeric packages.

## Algorithms And Invariants

Every witness is small and deterministic; external corpus completeness belongs to conformance runners.

## Failure And Effects

The package has no runtime API or IO. Failures are test assertions identifying a contract mismatch.

## Implementation Trade-offs

Centralizing cross-package laws catches drift, while package-local algorithm details remain in their owning white-box tests.

## Stability

The package is maintained as repository infrastructure. Generated declarations may change with the runners and do not promise downstream compatibility.
