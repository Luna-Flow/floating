# differential API

## Purpose

`differential` is the executable of the seeded random differential campaign
(`random-diff`). It reads a generated corpus of MPFR (binary) or libmpdec
(decimal) rows, validates them against `floating` in batches through the
[mare_mark](https://lunaflow.cn/en/mare_mark/) runner and prints the
append-only JSONL record of the run on standard output. The package has no
public MoonBit items; this page documents its command line and its record. The
[tutorial](../tutorial/differential.md) shows a campaign end to end and the
[design page](../design/differential.md) explains why the harness validates
batches and how a failing batch is minimized. The row formats and the oracle
programs are described in
[`testdata/bin_float/README.md`](../../../testdata/bin_float/README.md) and
[`testdata/decimal/README.md`](../../../testdata/decimal/README.md).

## Importing

`differential` is an executable package (`pkgtype(kind: "executable")`) and
cannot be imported. It builds for native, JavaScript, Wasm and LLVM; it is
excluded from Wasm-GC because the mare_mark runner uses `moonbitlang/async`,
which has no Wasm-GC runtime. Its `moon.pkg` imports the two frontends, the
mare_mark packages and the shared benchmark toolkit:

```moonbit nocheck
import {
  "Luna-Flow/floating/bench" @benchkit,
  "Luna-Flow/floating/frontend/gda_expr",
  "Luna-Flow/floating/frontend/mpfr_expr",
  "Luna-Flow/mare_mark/runner",
}
```

## Command line

```text
random-diff --rows <corpus> [--batch N] [--seed N] [--run-id ID]
            [--target native|js|wasm|wasm-gc|llvm]
            [--replay-command CMD [--replay-argument ARG ...]]
```

| Option | Meaning |
| --- | --- |
| `--rows FILE` | the corpus: `mpfr-random-v1` rows, `mpfr-decimal-random-v1` rows or a `.decTest` file whose header says `libmpdec-random-v1`; the format is detected from the text |
| `--batch N` | cases validated together; default 1000 |
| `--seed N` | the mare_mark run seed, below 2^31; it seeds the balanced block order and is recorded in every failure |
| `--run-id ID` | provenance id written into the environment snapshot and the summary |
| `--target T` | the backend name recorded in the environment snapshot (it does not select the backend: the binary you run does) |
| `--replay-command CMD` | the command stored in each `validation_failure` for `mare-mark replay`; default `python3` |
| `--replay-argument ARG` | a leading argument of that command, repeatable; the harness appends `--target T` and the failing case id or `first..last` range |

Arguments before the first `--option` are ignored, because a Node.js or Wasm
host puts the program or script path first. Every option takes one value.

Exit status: `0` when every batch agreed with its oracle; `1` when a batch
failed or a case was not executable; `2` for a usage error, an unreadable file
or a file that is not a random differential corpus.

## The record

The harness writes mare_mark JSONL (`mmka_1`) to standard output, one event per
line, nothing else:

| `type` | When | Content |
| --- | --- | --- |
| `validation` | once per batch | `status` (`valid`, `invalid` with a `reason`, `infrastructure_failure`), `operands` = `[first id, last id, case count]`, `scale` = the corpus header line (family, seed, range, oracle version), `dataset_id` = the batch number |
| `validation_failure` | once per invalid batch | the same fields plus `seed`, the `shrink_path` (each step of the delta debugging, as an id range), `minimal_input` (the failing case, as its row) and the `replay_command` with its arguments |
| `calibration`, `observation` | once per batch | the timing of the batch; one iteration per block |
| `summary` | last | `validation_count`, `passed_count`, `failed_count`, the protocol and the environment |

The protocol is fixed: `MultipleDatasetsSingleMeasurement`, no warm-up, one
iteration per batch, `EveryDataset` validation, balanced blocks seeded by
`--seed`. Timing is a by-product; correctness is the verdict.

A case is identified by its id, `<seed>.<family>.<index>` for MPFR rows and
`d<seed>.<family>.<index>` for libmpdec rows. The id is all that
`tools/random_differential.py replay` needs, because both generators are pure
functions of seed, family and index.

## Replaying a failure

The `validation_failure` event carries the replay command, so the record can be
replayed by the mare_mark command line:

```bash
# in a mare_mark checkout
moon run src/cli --target native -- replay records.jsonl --dry-run
```

The command it prints is
`python3 tools/random_differential.py replay --target native <id or range>`,
which regenerates the rows and runs them through the frontends. Without
mare_mark, run that command directly or `just random-diff replay <id>`.

## Complete public interface

The package exports no MoonBit items.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/differential"

// Values

// Errors

// Types and methods

// Type aliases

// Traits
```
<!-- generated-api-end -->
