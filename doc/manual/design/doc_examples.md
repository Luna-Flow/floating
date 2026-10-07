# `doc_examples` Design

## Responsibility

Executable home for examples shared by localized documentation.

## Data Flow

MoonBit `check` blocks exercise supported binary, decimal, GDA, interval, checked, semantic, expression, and frontend workflows.

## Algorithms And Invariants

Examples are compact contract witnesses; large matrices and performance measurements do not belong here.

## Failure And Effects

The package runs only under tests and performs no filesystem or process effects.

## Implementation Trade-offs

Central examples prevent translation drift, while localized prose remains free to explain the same behavior naturally.

## Stability

The package is maintained as repository infrastructure. Generated declarations may change with the runners and do not promise downstream compatibility.
