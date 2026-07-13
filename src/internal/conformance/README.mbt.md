# `internal/conformance`

Pure shared model for source locations, deterministic shards, case dispositions, and summaries.

## Contract

It performs no parsing, arithmetic, filesystem access, or scheduling.

## Maintainer Quick Start

```sh
sh tools/run_moon_clean_exec.sh test -p Luna-Flow/floating/internal/conformance --target native
```

## Detailed Documentation

The synchronized English, Simplified Chinese, and Japanese references live under
`doc/*/internal/conformance`. Read `api.md` for the generated surface, `tutorial.md` for the
shortest workflow, and `design.md` for invariants and trade-offs.
