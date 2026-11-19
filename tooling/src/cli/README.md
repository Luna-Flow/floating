# `cli`

The entry point of the `floating-conformance` executable: it passes the program
arguments to `cli/dispatch` and exits with the code it returns. The dispatcher,
its contract and its tests live in `cli/dispatch`; the manual pages are
`doc/manual/{api,tutorial,design}/cli.md`.

This package has no `README.mbt.md` on purpose: a main package that holds `.mbt.md`
test inputs is deprecated by the toolchain.

## Maintainer Quick Start

```sh
sh tools/run_moon_clean_exec.sh run --release --target native tooling/src/cli -- --help
```
