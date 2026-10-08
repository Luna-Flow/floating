# cli/gda_expr_cli tutorial

This tutorial shows how to run `.decTest` files with the GDA runner: select
files and rows, shard a run, get JSON output and make unsupported rows fail
the run. The runner is reached as `floating-conformance --backend gda`; below,
`gda` abbreviates that command.

| I want to | Use |
| --- | --- |
| run the committed smoke file | [`gda` with no path](#quick-start) |
| run some files or a directory | [`gda PATH …`](#run-files-and-directories) |
| run only some row ids | [`--cases`](#select-rows) |
| split a corpus over processes | [`--shard-count`, `--shard-index`](#shard-a-run) |
| fail on rows that were not executed | [`--strict-supported`](#fail-on-unsupported-rows) |
| call the runner from MoonBit | [`@gda_expr_cli.run`](#from-moonbit-code) |

## Quick start

The executable is built from a checkout of the repository. Build it and run
the committed smoke file:

```bash
just conformance build decimal_gda
_build/conformance/gda/native/release/build/gda-conformance.exe --backend gda
```

```text
GDA expression execution summary
cases: …
selected cases: …
executable cases: …
passed cases: …
failed cases: 0
skipped cases: …
shard: 0/1
```

The exit status is `0` when no executable row failed.

### From MoonBit code

The runner is also a library. After `moon add Luna-Flow/floating@0.8.0`,
import it and pass the argument vector, program name first:

```moonbit nocheck
import {
  "Luna-Flow/floating/cli/gda_expr_cli",
}
```

```moonbit nocheck
let status = @gda_expr_cli.run(["gda", "--json", "path/to/add.decTest"])
```

`run` prints the same output as the executable and returns the exit status
instead of exiting.

## Everyday tasks

### Run files and directories

```bash
gda path/to/add.decTest path/to/multiply.decTest
gda .tmp/decimal/official          # every *.decTest directly in the directory
```

Files are sorted by path and executed as one run.

### Select rows

```bash
gda --cases add001 add.decTest
gda --cases add001..add099,addx1001 add.decTest
```

A range matches ids of the same length that sort between its bounds.

### Shard a run

```bash
gda --json --shard-count 4 --shard-index 0 .tmp/decimal/official
gda --json --shard-count 4 --shard-index 1 .tmp/decimal/official
```

Shard `i` runs the rows whose position (after the `--cases` filter, across all
files) is `i` modulo the shard count. Adding the JSON counters of all shards
gives the counters of the unsharded run, except `totalCases`, which every
shard already reports for the whole run.

### Fail on unsupported rows

```bash
gda --strict-supported add.decTest
```

With `--strict-supported` the exit status is `1` if any selected row is
unsupported or legacy, even when all executed rows pass.

## Going further

- `just conformance run decimal_gda` fetches the pinned official corpora,
  splits them into the phases of `testdata/decimal/interpreter_stages.json`
  and runs the shards in parallel with this runner.
- [gda_expr tutorial](../frontend/gda_expr.md) explains the row semantics and
  the pass rule.

## Common pitfalls

- **`--help` returns `2`.** The runner prints its usage as an error; through
  the dispatcher, `--help` shows the dispatcher usage instead.
- **First parse error only.** A malformed line stops the run with one
  `file:line:1: message`; fix it and rerun to see the next.
- **Non-recursive directories.** Subdirectories are not searched.
- **Other suffixes are dropped silently.** A path such as `add.dectest` or
  `add.txt` is skipped without a message; if nothing is left the run reports
  zero cases and exits with `0`.

## Next steps

- [cli/gda_expr_cli API](../../api/cli/gda_expr_cli.md) for options, output
  keys and exit codes.
- [cli/gda_expr_cli design](../../design/cli/gda_expr_cli.md).
- [frontend/gda_expr tutorial](../frontend/gda_expr.md) for the row
  semantics.
