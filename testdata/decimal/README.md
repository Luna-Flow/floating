# Decimal Conformance Data

The repository uses the native MoonBit `gda_expr` interpreter for all General
Decimal Arithmetic conformance execution. Generated MoonBit test packages and
the former JavaScript executor are no longer supported.

The authoritative testcase sources are:

- <https://speleotrove.com/decimal/dectest.html>
- <https://speleotrove.com/decimal/dectest.zip>

The official corpora are not vendored. Their URLs, checksums, destinations,
and expected file counts are pinned in `corpora.json`.

## Which Command To Use

```sh
just smoke
just fetch
just fetch official0
just plan jobs=8
just pr jobs=8
just pr jobs=8 phase=arithmetic
just pr jobs=8 --strict-supported --json
just ci
```

- `just smoke` runs the checked-in `smoke.decTest` fixture directly.
- `just fetch` installs the current official corpus.
- `just plan` prints the staged file assignment without executing cases.
- `just pr` runs `moon check --target all`, refreshes interfaces with
  `moon info`, then executes the selected corpus through the native interpreter.
- `just ci` is intentionally separate and runs only a focused white-box test
  file for pull-request automation.

Use `just smoke` while changing parser or interpreter wiring. Use a targeted
`just pr` command while fixing Decimal semantics. Run plain `just pr` before
opening or updating a pull request. Do not treat `just ci` as full validation;
it is deliberately a small and fast CI gate.

## Recommended Workflow

### 1. Run the checked-in smoke fixture

```sh
just smoke
```

This does not download anything. It executes all cases in `smoke.decTest` in a
single interpreter process and is the fastest end-to-end parser/backend check.

To run one smoke case or a small smoke range:

```sh
just smoke --cases lfquant001
just smoke --cases lfnextp001,lfnextm001
just smoke --cases lfnextp001..lfnextp002 --json
```

### 2. Inspect or install the official corpus

```sh
just fetch
just plan jobs=8
```

`just fetch` verifies the pinned SHA-256 digest and expected file count. The
runner also fetches a missing corpus automatically, but explicit fetching makes
network and corpus failures easier to distinguish from semantic failures.

Use the legacy corpus only when investigating old subset behavior:

```sh
just fetch official0
just plan corpus=official0 jobs=4
```

### 3. Run a focused official case

Case selectors are passed with `--cases`:

```sh
# One exact case ID
just pr phase=arithmetic --cases quax1010

# Several exact IDs, separated by commas
just pr phase=arithmetic --cases quax1010,quax1013,quax1015

# Inclusive ID range
just pr phase=arithmetic --cases quax1010..quax1015

# Legacy corpus case
just pr corpus=official0 phase=arithmetic --cases add011
```

Selectors may be combined in one comma-separated expression, for example
`--cases quax1010..quax1015,quax1020`. Whitespace around comma-separated
selectors is ignored. A range is inclusive and only matches IDs whose length
equals both endpoints. Matching is lexicographic, so keep the same ID prefix
and zero-padding on both sides.

Case IDs are normally unique in the corpus. Add `phase=...` to avoid scanning
unrelated phases and to make the intended operation family explicit.

### 4. Run one phase

```sh
just pr phase=arithmetic jobs=8
just pr phase=elementary jobs=4
just pr phase=interchange jobs=4
just pr phase=remaining jobs=8
```

The configured phases are:

- `arithmetic`: add, subtract, multiply, divide, FMA, remainder, quantize,
  rescale, and related integer operations.
- `elementary`: exp, ln, log10, power, and square root.
- `interchange`: decimal32, decimal64, and decimal128 `ds`/`dd`/`dq` files.
- `remaining`: every file not claimed by an earlier phase.

Pass `phase=...` more than once only when invoking the Python runner directly;
the short `phase=name` form is intended for one phase per `just` invocation.

### 5. Run the full pre-PR gate

```sh
just pr jobs=8
```

The command stops at the first failed stage:

1. `moon check --target all`
2. `moon info`
3. native interpreter build
4. staged official-corpus execution

Use `--strict-supported` when unsupported or legacy rows must also fail the run:

```sh
just pr jobs=8 --strict-supported
```

Without strict mode, semantic mismatches fail the run, while diagnostic,
legacy-condition, and unsupported rows are counted and skipped.

## Run One `.decTest` File Directly

Use the interpreter CLI when file isolation matters more than the standard
pre-PR checks:

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/gda_expr_cli -- \
  testdata/decimal/official/quantize.decTest

sh tools/run_moon_clean_exec.sh run --release --target native src/gda_expr_cli -- \
  --cases quax1010..quax1015 --json \
  testdata/decimal/official/quantize.decTest
```

The CLI accepts multiple files or directories after its options. Direct CLI
runs do not execute `moon check` or `moon info`; use `just pr` for the final gate.

## Run White-Box Tests

CI intentionally runs only:

```sh
just ci
```

That command executes `src/decimal/coeff_kernel_wbtest.mbt`. To reproduce one
MoonBit white-box test by name:

```sh
sh tools/run_moon_clean_exec.sh test \
  src/decimal/coeff_kernel_wbtest.mbt \
  --filter 'decimal coefficient exact power-of-ten division uses unit shifts' \
  --no-parallelize
```

Use Moon's `--filter` glob syntax when selecting several named tests. These
white-box tests complement the interpreter corpus; they do not replace it.

## Execution Model

`interpreter_stages.json` assigns every corpus file to one sequential phase.
Within a phase, the runner starts deterministic native interpreter shards in
parallel. Per-shard JSON and the aggregate `summary.json` are written under
`.tmp/dectest-interpreter/`.

The runner accepts regular options such as `--jobs`, `--corpus`, `--phase`,
`--cases`, `--strict-supported`, and `--json`. For short `just` invocations,
`jobs=8`, `corpus=official0`, and `phase=arithmetic` are also accepted.

`--jobs` controls deterministic interpreter shards inside each phase. Start
with `jobs=1` when reproducing a failure and increase it for full runs. Use
`--no-build` only after the native interpreter has already been built and no
relevant MoonBit source has changed.

## Results And Failure Triage

The staged runner writes:

- `.tmp/dectest-interpreter/summary.json`: aggregate run result.
- `.tmp/dectest-interpreter/<phase>/shard-NNN.json`: per-shard result and timing.
- `failedIds`: case IDs that produced semantic mismatches.
- counts for executable, passed, failed, skipped, diagnostic, legacy, and
  unsupported cases.

Use JSON output when another tool needs to consume the result:

```sh
just pr phase=arithmetic --cases quax1010..quax1015 --json
```

Interpret failures in this order:

1. A failure during `moon check` or `moon info` is a compile/interface problem;
   no conformance case ran.
2. Runner exit code `2` indicates setup, corpus, build, process, or JSON failure.
3. Runner exit code `1` with `failedIds` indicates semantic case mismatches.
4. Strict mode also returns `1` when legacy or unsupported cases remain.
5. Re-run failed IDs with `jobs=1`, one phase, and `--json` before changing code.

Example focused rerun:

```sh
just pr jobs=1 phase=arithmetic --cases quax1010,quax1013 --json
```
