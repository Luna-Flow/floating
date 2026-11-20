# floating

[![Maintainer](https://img.shields.io/badge/Maintainer-KCN--judu-violet)](https://github.com/KCN-judu)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue)](./LICENSE)

Arbitrary-precision binary, decimal, General Decimal Arithmetic and interval
arithmetic for MoonBit, with explicit numeric semantics. This repository is a
`moon.work` workspace of two modules, the manual that covers both, the pinned
conformance corpora and the scripts of the gates.

| Directory | What it holds |
| --- | --- |
| [`library/`](./library/README.md) | the published module `Luna-Flow/floating` (`moon add Luna-Flow/floating`): the numeric packages, its README, LICENSE and CHANGELOG |
| [`tooling/`](./tooling/moon.mod) | the unpublished module `Luna-Flow/floating-tools`: benchmarks, command-line programs, the differential harness, corpus frontends and the documentation examples |
| [`doc/manual`](./doc/manual/index.md) | one manual for both modules (English source; Chinese and Japanese catalogs in `doc/locale`), also published at <https://lunaflow.cn/en/floating/> |
| [`testdata/`](./testdata/) | pinned corpora and expected values, documented per directory |
| [`tools/`](./tools/) | the Python and shell scripts of the gates, generators and checks |
| [`.github/`](./.github/workflows) | CI, nightly, docs and publish workflows |

Start with the [library README](./library/README.md) to use the package, with the
[manual](./doc/manual/index.md) to learn it and with [CONTRIBUTING](./CONTRIBUTING.md)
to work on it. Release history is in [library/CHANGELOG.md](./library/CHANGELOG.md).

## Development

The repository uses [`just`](https://github.com/casey/just) as its task runner.
Every `moon` command run at the root acts on both modules; `-p <package>` or a
path such as `library/src/bin_float` narrows it.

```bash
just pr 8                    # pull-request gate
just fmt                     # format MoonBit sources
just docs                    # manual checks and documentation examples
just gate binary 8           # TestFloat and MPFR
just gate decimal 8          # IEEE decimal vectors
just gate decimal_gda 8      # GDA decTest corpora
just gate interval 8         # strict ITF1788
just ci 8                    # everything, before a release
```

Smoke fixtures, plans, pinned corpora, targets and phases go through one entry
point:

```bash
just conformance smoke binary
just conformance run decimal --run-target native --run-target wasm
just conformance run interval --phase trigonometric --strict-supported
```

Corpus provenance and options are described in
[`testdata/bin_float`](./testdata/bin_float/README.md),
[`testdata/decimal`](./testdata/decimal/README.md) (IEEE 754),
[`testdata/decimal_gda`](./testdata/decimal_gda/README.md) (GDA) and
[`testdata/interval`](./testdata/interval/README.md).

## License

Apache-2.0. See [LICENSE](./LICENSE).
