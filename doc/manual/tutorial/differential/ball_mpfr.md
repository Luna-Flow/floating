# differential/ball_mpfr tutorial

This page shows how to run the differential stage of `BallFloat` against MPFR and how to read its output. The stage does not time anything: it asks whether the interval operations return the tightest result at the ends of the exponent range and in the subnormal band, where the other tests have no oracle of their own.

| I want to | Use |
| --- | --- |
| run the whole stage | [`python3 tools/ball_diff.py run`](#quick-start) |
| write the rows only | [`ball_diff.py gen`](#everyday-tasks) |
| run one class of rows | [`--classes` and `--ops`](#everyday-tasks) |
| read a failing row | [`BALLDIFF_FAIL` lines](#read-the-output) |

## Quick start

From the repository root, with MPFR and GMP installed under `/opt/homebrew` (`--prefix` selects another prefix):

```bash
python3 tools/ball_diff.py run
```

The script writes the rows, builds `tools/ball_mpfr_oracle.c`, computes the oracle, cross-checks it with a second oracle in Python integers, runs the test of this package on native in release mode and prints the verdict. The exit status is 0 when no row differs from MPFR except the rows listed in `tools/ball_diff_known.txt`, and 1 otherwise.

## Everyday tasks

### Run a part of the rows

```bash
python3 tools/ball_diff.py run --classes OV SUB --ops fma mul --precisions 53 512 --per-cell 40
```

A cell keeps its seeded stream when other cells are selected, so a row id means the same operands in every run.

### Read the output

The first table counts, per class, operation and precision, the rows and how many reached an overflow, a subnormal result, a subnormal operand or an underflow to zero according to the oracle's flags. `BALLDIFF_FAIL id op size class expected LO HI got LO HI` is a row whose bounds differ; the texts are canonical (`0b<odd integer>p<exponent>`, `inf`, `-inf`, `0`). Take the id to `inputs.txt` in the output directory (`.tmp/ball_diff`) for the operands.

### A row that differs today

File an issue, then add `<row id> #<issue>` to `tools/ball_diff_known.txt`. The run reports it as known; when the library is fixed the row agrees, the run reports it as stale and fails until the line is removed.

## Going further

- Add a class in `tools/ball_diff.py` (`CLASSES`, a generator in `GENERATORS`); give it the oracle flag it must reach, so that a class that misses its band fails the run.
- The header `tools/mpfr_ours.h` is shared by every C program that needs MPFR in the range of `bin_float`.

## Common pitfalls

- The test needs the two environment variables; started by plain `moon test` it does nothing.
- A row marked undecided is one where MPFR's `mpfr_sqrt` failed an exact check; it is not compared.
- The stage needs the MPFR headers, so it is not part of `just pr`.

## Next steps

- [differential/ball_mpfr API](../../api/differential/ball_mpfr.md)
- [differential/ball_mpfr design](../../design/differential/ball_mpfr.md)
- [Verification](../../verification.md#interval-differential-stage-against-mpfr)
