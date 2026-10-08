# cli tutorial

This tutorial shows how to build the `floating-conformance` executable and
run the four conformance runners through it, either directly or through the
`just conformance` tooling that downloads and plans whole corpora.

| I want to | Use |
| --- | --- |
| build the executable and see its usage | [`run … src/cli -- --help`](#quick-start) |
| run decTest, ITL, MPFR or TestFloat data | [`--backend gda`, `itl`, `mpfr`, `testfloat`](#choose-a-backend) |
| run whole pinned corpora in parallel | [`just conformance …`](#use-the-tooling-instead-of-raw-invocations) |
| use the result in a script | [the exit code and `--json`](#read-the-exit-code) |
| see the options of one runner | [the runner tutorials](#going-further) |

## Quick start

The executable is native-only and is built from a checkout of the
repository, not installed with `moon add`. From the repository root, build it
and print the usage line:

```bash
sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- --help
```

```text
usage: floating-conformance --backend <gda|testfloat|mpfr|itl> [backend options]
```

Run the committed GDA smoke file (the default path of the `gda` runner):

```bash
sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- --backend gda
```

The runner prints a summary and the process exits with `0` when every
executable row passed.

## Everyday tasks

### Choose a backend

Everything after the dispatcher's own options goes to the runner:

```bash
floating-conformance --backend gda --json testdata/decimal/smoke.decTest
floating-conformance --backend itl testdata/interval/smoke.itl
floating-conformance --backend mpfr --json testdata/bin_float/mpfr-4.2.2-elementary.txt
floating-conformance --backend testfloat --function f64_mul --rounding rnear_even vectors.tv
```

(`floating-conformance` stands for the built executable, for example
`_build/conformance/gda/native/release/build/gda-conformance.exe`.)

### Use the tooling instead of raw invocations

For full corpora, let `tools/conformance.py` build the executable, fetch the
pinned data, plan the phases and run the shards in parallel:

```bash
just conformance build decimal_gda
just conformance smoke binary
just conformance run interval
just gate decimal_gda 8
```

### Read the exit code

`0` means success, `1` means failing cases (for `itl` also diagnostic cases;
in strict mode also unsupported cases), `2` means a usage, file or parse
error. Scripts should check the code
and, with `--json`, parse the single JSON object on standard output.

## Going further

- Each runner has its own options; see the tutorials for
  [gda_expr_cli](cli/gda_expr_cli.md), [itl_expr_cli](cli/itl_expr_cli.md),
  [mpfr_expr_cli](cli/mpfr_expr_cli.md) and
  [testfloat_expr_cli](cli/testfloat_expr_cli.md).
- To execute corpora in MoonBit code without a process, call the frontends
  directly, for example [gda_expr](frontend/gda_expr.md).

## Common pitfalls

- **`--help` is the dispatcher's.** `--backend gda --help` prints the
  dispatcher usage and exits with `0`; it does not show the runner's options.
- **Relative default paths.** Runners default to files under `testdata/`;
  run them from the repository root.
- **One backend per invocation.** `--backend` may be given only once.
- **An empty directory is not an error.** The `gda` runner rejects a named
  file without the `.decTest` suffix (`not a .decTest file: PATH`, exit `2`),
  but a directory contributes only its direct `.decTest` files, so a
  directory without any gives an empty run that exits with `0`.

## Next steps

- [cli API](../api/cli.md) for the exact options and exit codes.
- [internal/runner_cli](internal/runner_cli.md) for the shared option
  parser.
- [cli design](../design/cli.md) for the layering.
- [verification](../verification.md) for the published corpus claims.
