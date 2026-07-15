# Decimal Conformance Data

The public evidence summaries are split between
[`decimal` IEEE conformance](../../doc/en_US/decimal/conformance.md) and
[`decimal_gda` conformance](../../doc/en_US/decimal_gda/conformance.md). This
page owns corpus manifests, execution options, and failure triage.

The repository uses the native MoonBit `gda_expr` interpreter for all General
Decimal Arithmetic conformance execution. Generated MoonBit test packages and
the former JavaScript executor are no longer supported.

The authoritative testcase sources are:

- <https://speleotrove.com/decimal/dectest.html>
- <https://speleotrove.com/decimal/dectest.zip>

The official corpora are not vendored. Their URLs, checksums, destinations,
and expected file counts are pinned in `corpora.json`.

## IEEE 754 decimal32/64/128 corpus

The independent IEEE gate lives in `testdata/decimal/ieee`. It is separate
from the GDA `decTest` corpus and contains fixed-width DPD and BID witnesses,
arithmetic/flag rows, and a compact exhaustive 1,024-code DPD declet fixture.
`manifest.json` records the IEEE encoding and exact-arithmetic fixture schema;
no implementation-specific source archive is downloaded during a test run.

IEEE permits either tininess policy. The public context defaults to
after-rounding and exposes an explicit before-rounding option; GDA always uses
before-rounding. NaN payload and sign selection follow the public API contract.

The checked-in runner validates all 1,024 DPD declets and the fixed-width BID
and DPD cases directly from the IEEE formulas, then executes the same public
MoonBit API tests on every supported target.

The runner also executes a 42-row excerpt from the pinned `dd*` and `dq*`
concrete-format files in `dectest.zip`. Those rows are useful boundary and
rounding witnesses, but decTest is a General Decimal Arithmetic corpus and its
own notice says that it is beta, non-exhaustive, and not proof of IEEE
compliance. They are never used to override the clause-derived oracle.

`vector_plan.json` defines the next fixed-seed expansion: every oracle family
targets at least 100,000 rows across decimal32/64/128, five IEEE rounding
directions, both tininess policies, 14 boundary classes, nine coefficient-size
classes, and balanced/sparse/dense/unbalanced shapes. Generate a stream without
committing a multi-gigabyte artifact with:

```sh
just ieee-vectors mandatory-decimal 100000 .tmp/mandatory.jsonl
```

The committed elementary oracle adds 2,784 executable rows. MPFR 4.2.2
computes 768-bit directed dyadic enclosures; exact integer conversion rounds
both endpoints to decimal32/64/128 under all eight Decimal rounding modes and
rejects non-unique value/flag witnesses. RDFP and Arb routes remain optional
secondary evidence and are never counted when unavailable. The larger
100,000-per-family plan remains an optional generated stress matrix rather
than a multi-gigabyte committed artifact.

Run the IEEE runner through the shared conformance entry point:

```sh
just conformance plan decimal
just conformance run decimal --run-target native
just conformance run decimal --run-target native --run-target wasm --run-target wasm-gc --run-target js --json
```

The Python runner remains available for internal debugging. Run the implementation
gate on native, Wasm, Wasm-GC, and JavaScript (LLVM is intentionally not part
of this gate) with `just gate decimal`. The `decimal_gda` backend and
`just gate decimal_gda` remain the separate GDA suite.

## Which Command To Use

```sh
just conformance smoke decimal_gda
just conformance fetch decimal_gda official
just conformance fetch decimal_gda official0
just conformance plan decimal_gda --jobs 8
just gate decimal_gda 8
just conformance run decimal_gda --jobs 8 --phase arithmetic
just conformance run decimal_gda --jobs 8 --strict-supported --json
just decimal-kernel-ci
```

- `just conformance smoke decimal_gda` runs the checked-in `smoke.decTest` fixture directly.
- `just conformance fetch decimal_gda` installs the selected official corpus.
- `just conformance plan decimal_gda` prints the staged file assignment without executing cases.
- `just gate decimal_gda` executes both pinned GDA corpora through the native interpreter.
- `just pr` runs the complete repository gate; `just decimal-kernel-ci` runs the
  focused Decimal white-box test file.

Use `just conformance smoke decimal_gda` while changing parser or interpreter wiring. Use a targeted
`just conformance run decimal_gda` command while fixing GDA semantics. Run plain `just pr` before
opening or updating a pull request. Do not treat `just decimal-kernel-ci` as full validation;
it is deliberately a small and fast CI gate.

## Recommended Workflow

### 1. Run the checked-in smoke fixture

```sh
just conformance smoke decimal_gda
```

This does not download anything. It executes all cases in `smoke.decTest` in a
single interpreter process and is the fastest end-to-end parser/backend check.

To run one smoke case or a small smoke range:

```sh
just conformance smoke decimal_gda --cases lfquant001
just conformance smoke decimal_gda --cases lfnextp001,lfnextm001
just conformance smoke decimal_gda --cases lfnextp001..lfnextp002 --json
```

### 2. Inspect or install the official corpus

```sh
just conformance fetch decimal_gda official
just conformance plan decimal_gda --jobs 8
```

`just conformance fetch decimal_gda` verifies the pinned SHA-256 digest and expected file count. The
runner also fetches a missing corpus automatically, but explicit fetching makes
network and corpus failures easier to distinguish from semantic failures.

Use the legacy corpus only when investigating old subset behavior:

```sh
just conformance fetch decimal_gda official0
just conformance plan decimal_gda --corpus official0 --jobs 4
```

### 3. Run a focused official case

Case selectors are passed with `--cases`:

```sh
# One exact case ID
just conformance run decimal_gda --phase arithmetic --cases quax1010

# Several exact IDs, separated by commas
just conformance run decimal_gda --phase arithmetic --cases quax1010,quax1013,quax1015

# Inclusive ID range
just conformance run decimal_gda --phase arithmetic --cases quax1010..quax1015

# Legacy corpus case
just conformance run decimal_gda --corpus official0 --phase arithmetic --cases add011
```

Selectors may be combined in one comma-separated expression, for example
`--cases quax1010..quax1015,quax1020`. Whitespace around comma-separated
selectors is ignored. A range is inclusive and only matches IDs whose length
equals both endpoints. Matching is lexicographic, so keep the same ID prefix
and zero-padding on both sides.

Case IDs are normally unique in the corpus. Add `--phase ...` to avoid scanning
unrelated phases and to make the intended operation family explicit.

### 4. Run one phase

```sh
just conformance run decimal_gda --phase arithmetic --jobs 8
just conformance run decimal_gda --phase elementary --jobs 4
just conformance run decimal_gda --phase interchange --jobs 4
just conformance run decimal_gda --phase remaining --jobs 8
```

The configured phases are:

- `arithmetic`: add, subtract, multiply, divide, FMA, remainder, quantize,
  rescale, and related integer operations.
- `elementary`: exp, ln, log10, power, and square root.
- `interchange`: decimal32, decimal64, and decimal128 `ds`/`dd`/`dq` files.
- `remaining`: every file not claimed by an earlier phase.

Pass `--phase ...` more than once to select multiple phases explicitly.

### 5. Run the full pre-PR gate

```sh
just gate decimal_gda 8
```

The command stops at the first failed stage:

1. `decimal_gda` package tests;
2. GDA frontend tests;
3. staged `official` corpus execution;
4. staged `official0` corpus execution.

Use `--strict-supported` as a guard against accidentally adding unsupported or
legacy classifications; the pinned legal GDA corpus has none:

```sh
just conformance run decimal_gda --jobs 8 --strict-supported
```

The only intentionally non-executable rows in the official corpus are `#`
placeholder/non-scalar invalid inputs. They are classified as diagnostics and
excluded from the legal GDA conformance denominator; every legal executable row
must pass.

## Run One `.decTest` File Directly

Use the interpreter CLI when file isolation matters more than the standard
pre-PR checks:

```sh
sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- \
  --backend gda \
  testdata/decimal/official/quantize.decTest

sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- \
  --backend gda --cases quax1010..quax1015 --json \
  testdata/decimal/official/quantize.decTest
```

The CLI accepts multiple files or directories after its options. Direct CLI
runs do not execute `moon check` or `moon info`; use `just pr` for the final gate.

## Run White-Box Tests

CI intentionally runs only:

```sh
just decimal-kernel-ci
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
`--cases`, `--strict-supported`, and `--json`.

`--jobs` controls deterministic interpreter shards inside each phase. Start
with `--jobs 1` when reproducing a failure and increase it for full runs. Use
`--no-build` only after the native interpreter has already been built and no
relevant MoonBit source has changed.

## Results And Failure Triage

The staged runner writes:

- `.tmp/dectest-interpreter/summary.json`: aggregate run result.
- `.tmp/dectest-interpreter/<phase>/shard-NNN.json`: per-shard result and timing.
- `failedIds`: case IDs that produced semantic mismatches.
- counts for executable, passed, failed, skipped, diagnostic, legacy, and
  unsupported cases. In the pinned corpus, diagnostic rows are only `#`
  placeholders; legacy and unsupported counts are zero.

Use JSON output when another tool needs to consume the result:

```sh
just conformance run decimal_gda --phase arithmetic --cases quax1010..quax1015 --json
```

Interpret failures in this order:

1. A failure during `moon check` or `moon info` is a compile/interface problem;
   no conformance case ran.
2. Runner exit code `2` indicates setup, corpus, build, process, or JSON failure.
3. Runner exit code `1` with `failedIds` indicates semantic case mismatches.
4. Strict mode returns `1` if a future change introduces legacy or unsupported
   classifications; it does not turn invalid `#` placeholders into arithmetic
   cases.
5. Re-run failed IDs with `--jobs 1`, one phase, and `--json` before changing code.

Example focused rerun:

```sh
just conformance run decimal_gda --jobs 1 --phase arithmetic --cases quax1010,quax1013 --json
```
