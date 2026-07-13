# `cli`

Native dispatcher for the GDA, TestFloat, MPFR, and ITL conformance backends.

## Contract

It owns argument dispatch and process exit only; parsing and numerical semantics live in frontend packages.

## Maintainer Quick Start

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- --help
```

## Detailed Documentation

The synchronized English, Simplified Chinese, and Japanese references live under
`doc/*/cli`. Read `api.md` for the generated surface, `tutorial.md` for the
shortest workflow, and `design.md` for invariants and trade-offs.
