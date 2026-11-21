<!-- historical-performance-baseline: 0.11.0 -->
# bench/external tutorial

This page shows how to run the external baseline, `floating` against MPFR and
libmpdec, and how to read what it writes. The measured ratios and the method
are on the [performance page](../../performance/bench/external.md); the
toolkit and the statistics are in the [bench tutorial](../bench.md).

| I want to | Use |
| --- | --- |
| run the baseline | [`just bench external run`](#quick-start) |
| try it quickly before a real run | [`just bench external run --preset quick`](#quick-start) |
| see the gaps without the C side, a few rounds | [`just bench external quick`](#check-the-gaps-quickly) |
| restrict the matrix | [`--ops`, `--binary-precisions`, `--decimal-gda-digits`](#restrict-the-matrix) |
| re-reduce raw rounds without measuring | [`just bench external report`](#re-reduce-and-publish) |
| keep a summary in the repository | [`just bench external publish`](#re-reduce-and-publish) |
| measure a build configuration of the floating side | [`--configuration`, `--moon-env`](#choose-a-configuration) |
| check a summary against its samples | [`just bench external recompute`](#recompute-a-summary) |
| measure the floating side on wasm or js | [`--target wasm`, `--target js`](#choose-a-configuration) |
| fix the warm-up of a runtime | [`just bench external warmup`](#calibrate-the-warm-up-of-a-runtime) |
| see how the ratios moved since a release | [`just bench external compare OLD NEW`](#compare-two-releases) |
| a table of a run beside an earlier release, as Markdown and CSV | [`just bench external table OLD NEW...`](#table-of-a-run-beside-a-release) |
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
turns this off). Every block is a pair of the case and its null, so a run takes
about twice as long as it did before the net-ratio method (about 40 minutes
then), because the slowest cases (elementary functions at 8192 bits and 1000
digits) run for hundreds of milliseconds per operation. Run it on AC power and close
other heavy work: the load of other processes is the main source of noise. The
files land in `.tmp/external`:

| File | Content |
| --- | --- |
| `inputs.txt` | the operands both sides read |
| `reference.txt` | MPFR and libmpdec results for those operands |
| `machine.json` | CPU, OS, compiler, library, `moon` and `moonc` versions, revision, checksums of the two files above |
| `round-N/reference.jsonl`, `round-N/floating.jsonl`, `round-N/floating.log` | raw observations of each round |
| `results.json`, `results.md` | raw and net times, null times, intervals, ratios, verdicts (schema `external-baseline-v2`) |
| `samples.json` | the pairs of case and null blocks of every case, per side and round: everything `results.json` is computed from |

## Everyday tasks

### Restrict the matrix

```bash
just bench external run --ops add mul --binary-precisions 53 512 --decimal-gda-digits 34 --out .tmp/external-small
```

A restricted run writes its own directory, so it never mixes with a full run.

### Try a run quickly

```bash
just bench external run --preset quick --ops add sqrt
```

The `quick` preset uses short batches and two rounds, and is far noisier than the `standard` one. It exercises every path
but is not a measurement to publish.

### Check the gaps quickly

```bash
just bench external quick --ops exp ln --binary-precisions 53 512
```

`quick` times only `floating`, in two rounds with short batches, and divides by
the MPFR and libmpdec medians stored in `testdata/external_baseline/summary-0.11.0.json`
(`--stored` names another summary). Those reference timings do not change, so
the C side is not built or run, and the runner does not wait for a quiet
machine. The table shows the time of `floating`, the stored reference time, the
ratio, the ratio of the stored run and a flag for ratios above `--flag-above`
(10 by default). The machine state of the stored run differs from today's, so
read a single absolute ratio as a guide and decide a change by timing the old
and the new build alternately on the same machine. The floating results are
checked against an untimed pass of the same function, not against the C library;
only `run` validates against MPFR and libmpdec.

### Re-reduce and publish

```bash
just bench external report
just bench external publish
```

`report` reduces the raw rounds in `.tmp/external` again, for example after a
change of the statistics, without measuring (the rounds must come from a harness
that writes null blocks). `publish` copies the compact summary into
`testdata/external_baseline` as `summary-VERSION-CONFIGURATION.json`, one file per
release and configuration, the samples as `samples-VERSION-CONFIGURATION.json.gz`,
the tables as `summary-CONFIGURATION.md`, and regenerates the tables of that
configuration in the [performance page](../../performance/bench/external.md);
the raw JSONL stays out of the repository. The summaries of earlier releases
(schema v1) keep their names.

### Choose a configuration

```bash
just bench external run --configuration native-portable --moon-env KEY=VALUE
just bench external run --target wasm
just bench external run --target js
```

`--target` chooses the `moon` target the floating side is built and run for
(`native`, `wasm` under `moonrun`, `js` under node; the reference side stays the
native C process), `--warmup-us` overrides the warm-up time, and `--configuration`
names the build configuration of the floating side (lower-case letters, digits and
hyphens; `native` for the native target and the target's name otherwise) and is
recorded in the summary and in the names of the published files. `--moon-env` passes an environment
variable to the `moon` process that builds and runs the floating side and can be
repeated; how a configuration is selected, for example how the portable path is
forced, is defined by the kernel work, not by the benchmark.

### Calibrate the warm-up of a runtime

```bash
just bench external warmup --target js
```

runs the calibration experiment of the [design page](../../design/bench/external.md#the-calibration-experiment-of-the-warm-up)
on the floating side only (nothing is published): the warm-up drift of every case,
warm-up time and repeat, and the smallest warm-up within the limit. It writes
`warmup-<target>.json` under `--out`. It is run once per runtime, before any cell
is measured, in the same bench window as the measurement.

### Recompute a summary

```bash
just bench external recompute testdata/external_baseline/summary-VERSION-native.json testdata/external_baseline/samples-VERSION-native.json.gz
```

recomputes every case from the samples and the protocol of the summary and says
how many cases agree with the stored numbers (the exit status is 1 when one
differs).

### Compare two releases

```bash
just bench external compare testdata/external_baseline/summary-0.11.0.json .tmp/external/results.json
```

prints the ratio of every case in both files, the change in percent, a verdict:
`slower` when the interval of the new ratio lies entirely above the old one,
`faster` when it lies entirely below, `same` otherwise, and which ratio was
compared: the net ratios when both summaries are resolved v2 results of the case,
the raw ratios otherwise (a v1 summary has only raw ratios). A line says when the
two summaries are of different configurations. Ratios, not absolute times, are
compared, so a faster machine does not hide a regression; the two runs should
still come from the same machine class.

### Table of a run beside a release

```bash
just bench external table testdata/external_baseline/summary-0.11.0.json \
  .tmp/ext-native/results.json .tmp/ext-portable/results.json \
  --markdown .tmp/table.md --csv .tmp/table.csv
```

writes one table per new summary, that is per configuration, with a heading that
names the bounds of the criterion and a line of counts (met, tolerated, not met,
unresolved). A row has the case, the time of the reference and of `floating` (the
net times of the new summary), the ratio of the old summary, the net ratio of the
new one with its 95% interval, the verdict against the bounds recorded in the new
summary, the quotient new over old (below 1 is faster) and the quotient of the raw
ratios, new raw over old raw. The rows are sorted by
package (`binary`, then `decimal_gda`), precision and operation. Without
`--markdown` the Markdown goes to standard output; the CSV has the same rows for
all configurations in one file, with a `configuration` column and plain numbers
(nanoseconds and ratios), meant for a chart.

The old summary may be of schema v1 (the 0.11.0 baseline) or v2. A v1 ratio is a
ratio of medians (marked `(raw)`): the loop floor of the timing harness is in both
of its times. The new net ratio has the floor subtracted on both sides, so the two
are not the same quantity and the quotient new over old is indicative, above all for
the small cases whose time is mostly floor. The column `raw new / old` divides the raw
ratio of the new summary (every v2 case has one) by the raw ratio of the old one: the
same quantity on both sides, medians with the floor in both times, so it is the
like-for-like change since the old release; it is empty when either raw ratio is
missing. The verdict is made on the net ratio, not on this quotient. An unresolved case shows its raw ratio, marked
`(raw)`, and the verdict `unresolved (raw met)` or the like. The same old summary is
used for every configuration; the heading of each section names the configuration of
the new summary.

The three states of the native limb primitives are three runs with their own
output directory, each with an explicit configuration name and environment, so that
their summaries sit side by side in one table (a name outside the table of criteria
is judged like its target, here `native`, bound 3):

```bash
just bench external run --out .tmp/ext-native                                            # default state, configuration native
just bench external run --out .tmp/ext-native-c --configuration native-c --moon-env LUNA_FLOATING_LIMBS=c
just bench external run --out .tmp/ext-portable --configuration native-portable --moon-env LUNA_FLOATING_PORTABLE=1
just bench external table testdata/external_baseline/summary-0.11.0.json \
  .tmp/ext-native/results.json .tmp/ext-native-c/results.json .tmp/ext-portable/results.json
```

The configuration name is recorded in the summary and is the heading of its section;
`native-c` is a name of this example, any lower-case name with letters, digits and
hyphens is accepted. Use the same `--seed` and preset for all of them.

### Read a ratio

A cell of the net table such as `2.80 [2.71, 2.93] met` is the net time of
`floating` divided by the net time of the reference library, with a 95%
bootstrap interval; above 1 means `floating` is slower. `met` says the upper end
is at most 3. `unresolved, raw 3.77 not met` says the net ratio could not be
resolved (the reason is listed under the tables) and the raw ratio, shown in its
own table, decides. `d` and `o` after a cell flag a drift of the null time
between rounds and an order effect; an asterisk after a net ratio says the
interval contains the target, after a raw ratio that the cell spread more than
the dispersion thresholds on the performance page.

## Going further

- Add a case: extend the matrix constants of `tools/external_baseline.py` (for
  example `BINARY_PRECISIONS`) and the matching benchmark of
  `tooling/src/bench/external`; the operand file is read by both sides, so the
  new case is measured on the same inputs.
- Understand the protocol: [bench/external design](../../design/bench/external.md)
  states why the sides alternate and defines the net ratio, the null and the
  rules of the verdict.
- Read the numbers: [external baseline](../../performance/bench/external.md)
  records the machine, the method and the ratios of the latest published
  release.

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
