# `internal/conformance` Design

This package centralizes source locations, validated shard specifications, case
dispositions, and summary folding. Sharding is deterministic modulo case index;
summary merge adds disjoint counts and concatenates results. `success` means no
executable failure, not that every selected case was supported.

It is an internal data model with no parser, arithmetic, filesystem access, or
parallel scheduler. Frontends may wrap its types to keep their public vocabulary
domain-specific.
