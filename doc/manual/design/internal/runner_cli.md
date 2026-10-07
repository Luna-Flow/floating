# `internal/runner_cli` Design

## Responsibility

Effect boundary shared by native conformance command adapters.

## Data Flow

It parses common options, collects and reads files, formats diagnostics, and builds JSON values for backend CLIs.

## Algorithms And Invariants

File ordering and JSON encoding are deterministic; shard parameters are validated before frontend execution.

## Failure And Effects

Filesystem reads and rendering are intentionally contained here; the conformance model and numeric frontends stay pure.

## Implementation Trade-offs

Sharing effect helpers removes duplicated CLI behavior without creating a general-purpose command framework.

## Stability

The package is maintained as repository infrastructure. Generated declarations may change with the runners and do not promise downstream compatibility.
