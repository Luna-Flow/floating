# differential tutorial

This tutorial runs a randomized differential campaign: it generates seeded
rows with MPFR (binary) and libmpdec (decimal), validates `floating` against
them through the mare_mark runner, reads the JSONL record, and replays and
minimizes a failure.

| I want to | Use |
| --- | --- |
| check the committed fixtures | [`just random-diff smoke`](#quick-start) |
| run a campaign | [`just random-diff run …`](#run-a-campaign) |
| read the record | [the JSONL events](#read-the-record) |
| reproduce one case | [`just random-diff replay <id>`](#replay-a-case) |
| shrink a failing case | [`just random-diff minimize <id>`](#minimize-a-failure) |
| run another backend | [`--target wasm`, `js`, `wasm-gc`](#other-backends) |

## Quick start

The committed fixtures need no oracle: their expected values are in the rows.

```bash
just random-diff smoke
```

```text
binary: 500/500 passed (testdata/bin_float/mpfr-4.2.2-random.txt)
binary-regression: 5/5 passed (testdata/bin_float/random-regressions.txt)
decimal: 650/650 passed (testdata/decimal/random/libmpdec-random.decTest)
decimal-regression: 0/10 passed, 10 known failures (xfail) (testdata/decimal/random/random-regressions.decTest)
```

`smoke` builds the synchronous `floating-conformance` executable for the
native target and runs the four fixture files through it. A known failure
recorded in a regression fixture is annotated `xfail` with its issue number; the
smoke run requires exactly those rows to fail, so a fix shows up as an
unexpected pass.

## Everyday tasks

### Run a campaign

A campaign needs the oracles: a C compiler with MPFR and GMP (Homebrew puts
them in `/opt/homebrew`; pass `--mpfr-prefix` elsewhere) for the binary
families, and Python 3 with the `decimal` module for the decimal families.

```bash
just random-diff run --family add --family dec-add --count 100000 --target native
```

```text
2 shards, 100000 cases per family, seed 20261118, targets native
[1/2] native add            0+100000  ok    4.3s
[2/2] native dec-add        0+100000  ok   46.6s
native: 200,000 cases
    add               100,000
    dec-add           100,000
batches validated 200, invalid 0
records and summary: .tmp/random-diff/run-20261118-120000
```

`--family` is repeatable and defaults to every family. The binary families
are `add sub mul div sqrt fma strtofr getstr shortest elem`; the decimal
ones are `dec-add dec-subtract dec-multiply dec-divide dec-squareroot dec-fma
dec-apply dec-tosci dec-toeng dec-exp dec-ln dec-log10 dec-power`. The
`dec-*wide` families sample the contexts on which the elementary functions
refuse by design and are opt-in. `--count` is per family, `--shard` bounds the
rows generated per file, `--batch` the cases validated together, `--jobs` the
parallel shards.

The run directory holds `records-<target>.jsonl` (append-only, one file per
backend) and `summary.json` with the exact number of cases per backend, family
and operation. The command exits with `1` when a batch disagreed.

### Read the record

```bash
python3 -c "
import json
for line in open('.tmp/random-diff/run-20261118-120000/records-native.jsonl'):
    event = json.loads(line)
    if event['type'] != 'validation': continue
    print(event['status'], event['operands'], event['scale'][:60])
" | head -3
```

```text
valid ['20261118.add.0', '20261118.add.999', '1000'] # mpfr-random-v1 mpfr=4.2.2 gmp=6.3.0 fam
valid ['20261118.add.1000', '20261118.add.1999', '1000'] # mpfr-random-v1 mpfr=4.2.2 gmp=6.3.0 fam
valid ['20261118.add.2000', '20261118.add.2999', '1000'] # mpfr-random-v1 mpfr=4.2.2 gmp=6.3.0 fam
```

Each `validation` names the batch by its first and last case id and its size.
An `invalid` one is followed by a `validation_failure` that carries the
minimized case.

### Replay a case

```bash
just random-diff replay 20261118.add.1234
just random-diff replay 20261118.add.1000..20261118.add.1999 --target wasm
just random-diff replay d20261118.divide.77
```

The generators are pure functions of seed, family and index, so the id is the
whole reproduction. The output is the frontend's summary; a failing row is
printed with the expected and the actual value and flags.

### Minimize a failure

```bash
just random-diff minimize d20261118.add.7352 --output testdata/decimal/random/random-regressions.decTest
```

The minimizer tries simpler variants (smaller precision, plain rounding, no
clamp, narrower exponent range, shorter operands, operands rewritten as `1E+k`),
asks the oracle for the correct answer of each variant, and keeps a variant when
the library still disagrees. The result is a row the oracle produced itself, so
it is a consistent regression case, not an edited one.

### Sweep the range limits

The random rows rarely land on an underflow or overflow threshold. For the
binary elementary functions, `tools/range_boundary_rows.py` writes rows on the
thresholds themselves, for every precision in a range, with the oracle columns
left as `?`:

```bash
python3 tools/range_boundary_rows.py --p-min 2 --p-max 300 --out .tmp/boundary.in
(head -n 1 .tmp/boundary.in; .tmp/random-diff/bin/generate_mpfr_random_oracle eval < .tmp/boundary.in) > .tmp/boundary.rows
moon run src/cli --target native --release -- --backend mpfr .tmp/boundary.rows
```

The generator binary is built by any `just random-diff run`. A failing row is
named with its expected and actual value and flags, so it can be pasted into a
regression fixture.

### Other backends

`--target` selects the backend of the harness: `native`, `wasm`, `js` or `llvm`
(the mare_mark runner has no Wasm-GC runtime). For Wasm-GC, run the same
fixtures through the synchronous runner:

```bash
just random-diff smoke --target wasm-gc
just random-diff replay 20261118.add.1234 --target wasm-gc
```

## Going further

- [API](../api/differential.md): the command line and the record.
- [Design](../design/differential.md): the oracle reductions and the batch
  validation.
- [Binary test data](../../../testdata/bin_float/README.md) and
  [decimal test data](../../../testdata/decimal/README.md): row formats,
  coverage, the intentional differences and the regression fixtures.
- [Verification](../verification.md): what has been run, with exact counts.

## Common pitfalls

- **A stale `moon` earlier on `PATH`.** The build runs `moon`; make sure the
  one you meant comes first.
- **No MPFR headers.** The generator build fails with `mpfr.h not found`; set
  `MPFR_PREFIX` or pass `--mpfr-prefix`.
- **Seeds above 2^31.** The harness takes the seed as a 32-bit integer and the
  tool reduces it; the case ids keep the full seed.
- **Treating a disagreement as a bug.** The oracles are implementations. Read
  the clause first.

## Next steps

Run a longer campaign on every backend, then read
[verification](../verification.md) for how the published counts were produced.
