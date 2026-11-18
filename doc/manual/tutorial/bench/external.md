# bench/external tutorial

This page shows how to run the external baseline, `floating` against MPFR and
libmpdec, and how to read what it writes. The measured ratios and the method
are on the [performance page](../../performance/bench/external.md); the
toolkit and the statistics are in the [bench tutorial](../bench.md).

| I want to | Use |
| --- | --- |
| run the baseline | [`just bench external run`](#quick-start) |
| try it quickly before a real run | [`just bench external run --preset quick`](#quick-start) |
| restrict the matrix | [`--ops`, `--binary-precisions`, `--decimal-digits`](#restrict-the-matrix) |
| re-reduce raw rounds without measuring | [`just bench external report`](#re-reduce-and-publish) |
| keep a summary in the repository | [`just bench external publish`](#re-reduce-and-publish) |
| see how the ratios moved since a release | [`just bench external compare OLD NEW`](#compare-two-releases) |
| understand what is timed | [performance page](../../performance/bench/external.md#what-is-timed) |

## Quick start

The baseline needs a C compiler and the headers and libraries of MPFR, GMP and
mpdecimal. The runner looks for them under `/opt/homebrew`; set `--prefix` or
`EXTBENCH_PREFIX` for another location. From the repository root:

```bash
just bench external run
```

The run builds `tools/external_baseline.c`, writes the operand file, asks the
C harness for the reference results, checks `floating` against them while it is
timed, and alternates the two sides over seven rounds, waiting before each side until
the machine is quiet (under 150% CPU used by other processes; `--no-gate`
turns this off). It takes about 40 minutes on the machine of the reported run,
because the slowest cases (elementary functions at 8192 bits and 1000 digits)
run for hundreds of milliseconds per operation. Run it on AC power and close
other heavy work: the load of other processes is the main source of noise. The
files land in `.tmp/external`:

| File | Content |
| --- | --- |
| `inputs.txt` | the operands both sides read |
| `reference.txt` | MPFR and libmpdec results for those operands |
| `machine.json` | CPU, OS, compiler, library, `moon` and `moonc` versions, revision, checksums of the two files above |
| `round-N/reference.jsonl`, `round-N/floating.jsonl`, `round-N/floating.log` | raw observations of each round |
| `results.json`, `results.md` | medians, intervals, ratios |

## Everyday tasks

### Restrict the matrix

```bash
just bench external run --ops add mul --binary-precisions 53 512 --decimal-digits 34 --out .tmp/external-small
```

A restricted run writes its own directory, so it never mixes with a full run.

### Try a run quickly

```bash
just bench external run --preset quick --ops add sqrt
```

The `quick` preset uses short batches and two rounds, and is far noisier than the `standard` one. It exercises every path
but is not a measurement to publish.

### Re-reduce and publish

```bash
just bench external report
just bench external publish
```

`report` reduces the raw rounds in `.tmp/external` again, for example after a
change of the statistics, without measuring. `publish` copies the compact
summary into `testdata/external_baseline` as `summary-VERSION.json`, one file
per release, and refreshes `summary.md`; the raw JSONL stays out of the
repository.

### Compare two releases

```bash
just bench external compare testdata/external_baseline/summary-0.10.2.json .tmp/external/results.json
```

prints the ratio of every case in both files, the change in percent, and a
verdict: `slower` when the interval of the new ratio lies entirely above the
old one, `faster` when it lies entirely below, `same` otherwise. Ratios, not
absolute times, are compared, so a faster machine does not hide a regression;
the two runs should still come from the same machine class.

### Read a ratio

A cell such as `37.5 [36.9, 38.2]` is the median time of `floating` divided by
the median time of the reference library, with a 95% bootstrap interval. Above
1 means `floating` is slower. An asterisk marks a cell whose measurements
spread more than the dispersion thresholds on the performance page.

## Common pitfalls

- Compare runs only when `machine.json` agrees on CPU, compilers and library
  versions.
- A validation failure is reported but does not stop the timing: look for
  `WARNING` lines and `validation_failed_cases` in `results.json`.
- Do not run other heavy work during a measurement; the load average is
  recorded at the start only.

## Next steps

- [bench/external API](../../api/bench/external.md)
- [bench/external design](../../design/bench/external.md)
- [External baseline results](../../performance/bench/external.md)
