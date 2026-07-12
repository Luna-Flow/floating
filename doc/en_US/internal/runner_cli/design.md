# `internal/runner_cli` Design

This package isolates runner effects and transport helpers: common option
parsing, deterministic file collection, source reads, diagnostic formatting,
and JSON construction. It deliberately contains no corpus-specific parser or
numeric operation. Filesystem and JSON details stay here so frontend packages
remain pure and directly testable.
