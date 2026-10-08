# cli/mpfr_expr_cli tutorial

This tutorial shows how to check `bin_float` against an MPFR data file from
the command line. The runner is reached as
`floating-conformance --backend mpfr`; below, `mpfr` abbreviates that command.

| I want to | Use |
| --- | --- |
| run the committed elementary matrix | [`mpfr FILE`](#quick-start) |
| run square-root or power data | [the same command; the format is detected](#run-each-format) |
| get machine-readable output | [`--json`](#json-for-scripts) |
| call the runner from MoonBit | [`@mpfr_expr_cli.run`](#from-moonbit-code) |
| run all binary corpora | [`just conformance run binary`](#going-further) |

## Quick start

The executable is built from a checkout of the repository:

```bash
just conformance build binary
_build/conformance/mpfr/native/release/build/mpfr-conformance.exe \
  --backend mpfr testdata/bin_float/mpfr-4.2.2-elementary.txt
```

```text
MPFR elementary summary
cases: …
passed cases: …
failed cases: 0
```

### From MoonBit code

After `moon add Luna-Flow/floating@0.8.0`, import
`"Luna-Flow/floating/cli/mpfr_expr_cli"` in `moon.pkg` and call `run`:

```moonbit nocheck
let status = @mpfr_expr_cli.run(["mpfr", "--json", "data/sqrt"])
```

## Everyday tasks

### Run each format

The runner reads exactly one file and picks the format from its content:

```bash
mpfr testdata/bin_float/mpfr-4.2.2-elementary.txt   # contains "mpfr-elementary-v1"
mpfr pow_si.txt                                     # header contains "input_coefficient_hex"
mpfr path/to/mpfr/tests/data/sqrt                   # anything else: sqrt data_check
```

### JSON for scripts

```bash
mpfr --json testdata/bin_float/mpfr-4.2.2-elementary.txt
```

prints one object with `corpus`, `totalCases`, `passedCases`, `failedCases`
and `failedIds`.

## Going further

- `just conformance run binary` runs the pinned MPFR square-root data and the
  elementary matrix together with the TestFloat matrix.
- New elementary data is produced by `tools/generate_mpfr_elementary_oracle.c`;
  keep the `mpfr-elementary-v1` marker line so the runner detects the format.
- [mpfr_expr tutorial](../frontend/mpfr_expr.md) explains the row formats and
  pass rules.

## Common pitfalls

- **One file per invocation.** Extra paths, missing paths, and the shard
  options all print the usage line and exit with `2`.
- **A lone option is read as a path.** `mpfr --help` reports
  `cannot read file: --help`, not the usage line.
- **Format detection is textual.** A square-root file that happens to contain
  `input_coefficient_hex` in a comment is parsed as power data.

## Next steps

- [cli/mpfr_expr_cli API](../../api/cli/mpfr_expr_cli.md)
- [cli/mpfr_expr_cli design](../../design/cli/mpfr_expr_cli.md)
- [frontend/mpfr_expr tutorial](../frontend/mpfr_expr.md) for the row
  formats.
