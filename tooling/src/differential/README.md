# `differential`

The entry point of the seeded random differential executable: it calls `run` of
`differential/harness` with the program arguments. The harness, its contract
and its tests live in `differential/harness`; the manual pages are
`doc/manual/{api,tutorial,design}/differential.md`.

This package has no `README.mbt.md` on purpose: a main package that holds `.mbt.md`
test inputs is deprecated by the toolchain.

## Maintainer Quick Start

```sh
just random-diff smoke
just random-diff run --family add --family decimal_gda-add --count 20000 --target native
```
