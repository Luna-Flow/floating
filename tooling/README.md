# floating-tools

[![Maintainer](https://img.shields.io/badge/Maintainer-KCN--judu-violet)](https://github.com/KCN-judu)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue)](./LICENSE)
![State](https://img.shields.io/badge/State-active-success)

`Luna-Flow/floating-tools` holds the developer tools of
[`Luna-Flow/floating`](https://github.com/Luna-Flow/floating/blob/main/library/README.md):
the benchmarks, the corpus frontends and command-line programs that run the
conformance suites (IEEE 754 binary and decimal, General Decimal Arithmetic,
IEEE 1788 intervals), the seeded random differential harness against MPFR and
libmpdec, a small numeric-expression syntax, and the documentation examples that
keep the manual compiling. The module has the version of the library and imports
the library of that version.

## Install

The module is built in the workspace of the repository, where it resolves the library
as a member:

```bash
git clone https://github.com/Luna-Flow/floating
cd floating
just pr 8
```

It is versioned with the library (`0.11.0` imports `Luna-Flow/floating@0.11.0`);
once it is published to the registry, `moon add Luna-Flow/floating-tools@0.11.0`
adds it to a module. It needs the MoonBit toolchain with `moonc` 0.10.22 or later (the `differential` executable uses `async fn main` without importing `moonbitlang/async`),
and the dependencies `Luna-Flow/arithmetic`, `Luna-Flow/luna-generic`, `Luna-Flow/mare_mark`,
`Luna-Flow/type_theory`, `moonbitlang/async` and `moonbitlang/x`.

## Quick start

Run the committed smoke fixtures through the frontends and the differential
harness:

```bash
just conformance smoke binary          # TestFloat vectors through frontend/testfloat_expr
just conformance smoke interval        # ITF1788 rows through frontend/itl_expr
just random-diff smoke                 # seeded rows against MPFR and libmpdec
just bench external quick              # the floating side of the external baseline
```

Use a frontend from MoonBit code (a test of your own package in this workspace):

```moonbit nocheck
import {
  "Luna-Flow/floating-tools/frontend/gda_expr",
}

///|
test "parse two decTest rows and execute them" {
  let source =
    #|precision: 9
    #|rounding: half_even
    #|add001 add 1.20 2 -> 3.20
    #|div001 divide 1 3 -> 0.333333333 Inexact Rounded
    #|
  let document = @gda_expr.parse_dectest("quick.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  inspect(summary.passed_cases(), content="2")
  inspect(summary.success(), content="true")
}
```


## Packages

| Package | Purpose |
| --- | --- |
| [`numeric_expr`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/numeric_expr.md) | host-independent numeric expression syntax and evaluation |
| [`frontend/gda_expr`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/frontend/gda_expr.md), [`itl_expr`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/frontend/itl_expr.md), [`mpfr_expr`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/frontend/mpfr_expr.md), [`testfloat_expr`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/frontend/testfloat_expr.md) | parse and execute GDA decTest files, ITF1788 interval rows, MPFR witnesses and Berkeley TestFloat vectors |
| [`cli`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/cli.md), [`cli/dispatch`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/cli/dispatch.md) and the four `cli/*_expr_cli` runners | the `floating-conformance` executable and its libraries |
| [`differential`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/differential.md), [`differential/harness`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/differential/harness.md) | the seeded random differential campaign and its library |
| [`bench`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/bench.md) and `bench/*` | Maremark benchmark infrastructure, per-package suites and the timing against MPFR and libmpdec |
| [`consistency`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/consistency.md) | cross-package laws and API audits of the library (white-box tests, no public items) |
| `internal/conformance`, `internal/runner_cli` | summaries, shards, options and JSON shared by the runners |
| [`doc_examples`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/doc_examples.md) | the documentation examples run by `just docs` |

The [package map](https://github.com/Luna-Flow/floating/blob/main/doc/manual/index.md)
lists every package with its tutorial, API and design page.

## Documentation

The manual covers both modules and is published at <https://lunaflow.cn/en/floating/>
in English, Chinese and Japanese; its English source is in
[`doc/manual`](https://github.com/Luna-Flow/floating/tree/main/doc/manual).
Start with the [architecture](https://github.com/Luna-Flow/floating/blob/main/doc/manual/architecture.md)
and [verification](https://github.com/Luna-Flow/floating/blob/main/doc/manual/verification.md)
pages. Every package of this module has an API reference, a tutorial and a design
page; `tools/doc_quality.py` checks that they have the sections the standard asks for.

## Development

The task runner, the gates and the layout of the repository are described in the
[repository README](https://github.com/Luna-Flow/floating#readme) and
[CONTRIBUTING](https://github.com/Luna-Flow/floating/blob/main/CONTRIBUTING.md). Tests
run in the module directory `tooling/`: paths to the corpora in `testdata/` start
with `../`.

## Contributing

An entry that changes only this module goes to [CHANGELOG](./CHANGELOG.md); an entry
that changes the library goes to the changelog of the library.

## License

Apache-2.0. See [LICENSE](./LICENSE).
