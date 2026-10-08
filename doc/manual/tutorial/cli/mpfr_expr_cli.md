# mpfr_expr_cli tutorial

This tutorial shows how to check `bin_float` against an MPFR data file from
the command line. The runner is reached as
`floating-conformance --backend mpfr`; below, `mpfr` abbreviates that command.

## Quick start

```sh
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

## Everyday tasks

### Run each format

The runner reads exactly one file and picks the format from its content:

```sh
mpfr testdata/bin_float/mpfr-4.2.2-elementary.txt   # contains "mpfr-elementary-v1"
mpfr pow_si.txt                                     # header contains "input_coefficient_hex"
mpfr path/to/mpfr/tests/data/sqrt                   # anything else: sqrt data_check
```

### JSON for scripts

```sh
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
- **Format detection is textual.** A square-root file that happens to contain
  `input_coefficient_hex` in a comment is parsed as power data.

## Next steps

- [mpfr_expr_cli API](../../api/cli/mpfr_expr_cli.md)
- [mpfr_expr_cli design](../../design/cli/mpfr_expr_cli.md)
