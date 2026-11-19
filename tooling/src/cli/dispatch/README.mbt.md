# `cli/dispatch`

The dispatcher of the `cli` executable: native dispatcher for the GDA, TestFloat, MPFR, and ITL conformance backends.

## Contract

It owns argument dispatch and returns the exit code; the `cli` entry point exits the process; parsing and numerical semantics live in frontend packages.

## Maintainer Quick Start

```sh
sh tools/run_moon_clean_exec.sh run --release --target native tooling/src/cli -- --help
```

## Detailed Documentation

The synchronized English, Simplified Chinese, and Japanese references live under
`doc/*/cli/dispatch`. Read `api.md` for the generated surface, `tutorial.md` for the
shortest workflow, and `design.md` for invariants and trade-offs.
