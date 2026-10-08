# gda_expr_cli tutorial

This tutorial shows how to run `.decTest` files with the GDA runner: select
files and rows, shard a run, get JSON output and make unsupported rows fail
the run. The runner is reached as `floating-conformance --backend gda`; below,
`gda` abbreviates that command.

## Quick start

Build the executable and run the committed smoke file:

```sh
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

## Everyday tasks

### Run files and directories

```sh
gda path/to/add.decTest path/to/multiply.decTest
gda .tmp/decimal/official          # every *.decTest directly in the directory
```

Files are sorted by path and executed as one run.

### Select rows

```sh
gda --cases add001 add.decTest
gda --cases add001..add099,addx1001 add.decTest
```

A range matches ids of the same length that sort between its bounds.

### Shard a run

```sh
gda --json --shard-count 4 --shard-index 0 .tmp/decimal/official
gda --json --shard-count 4 --shard-index 1 .tmp/decimal/official
```

Shard `i` runs the rows whose position (after the `--cases` filter, across all
files) is `i` modulo the shard count. Adding the JSON counters of all shards
gives the counters of the unsharded run.

### Fail on unsupported rows

```sh
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

## Next steps

- [gda_expr_cli API](../../api/cli/gda_expr_cli.md) for options, output keys
  and exit codes.
- [gda_expr_cli design](../../design/cli/gda_expr_cli.md).
