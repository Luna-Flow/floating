# Verification

The repository separates fast development checks from finite, reproducible
conformance claims. Passing a corpus proves only the declared formats,
operations, rounding modes, targets and fixture revisions. This guide lists the
gates, what each published claim covers, and how to reproduce and triage a
result.

## Verification layers

| Layer | Command | Purpose |
| --- | --- | --- |
| Documentation | `just docs` | `tools/doc_quality.py` (page coverage, API snapshots, links and anchors, version and GDA claims, package `README.mbt.md` files), then `tools/check_doc_examples.py` (every runnable example of the manual), then the `src/doc_examples` tests |
| Formatting | `just fmt` | the MoonBit formatter |
| Pull request | `just pr [jobs]` | format check, docs, native check and tests with `--deny-warn`, Python tool tests, and the four committed smoke corpora |
| IEEE decimal | `just gate decimal [jobs]` | committed decimal32/64/128 DPD and BID vectors on native, Wasm, Wasm-GC and JavaScript |
| GDA decimal | `just gate decimal_gda [jobs]` | package and frontend tests, then the pinned `official` and `official0` `.decTest` corpora |
| Binary | `just gate binary [jobs]` | the pinned TestFloat level-1 matrix and the MPFR witnesses |
| Interval | `just gate interval [jobs]` | every strict ITF1788 phase |
| Complete | `just ci [jobs]` | format, docs, `--deny-warn` checks and tests on all four targets, generated interfaces, and every conformance gate |

Run the narrowest relevant check first, then broaden before a release.
Translation catalogs are checked separately by `lunadoc check`, which the
`Docs` workflow runs on every change under `doc/`.

## Continuous integration

- `ci.yml` runs `just pr` on every pull request and every push to `main`.
- `nightly.yml` runs `just gate` for `quick`, `decimal`, `decimal_gda`,
  `binary` and `interval` as parallel jobs every night and on demand. It
  caches the SHA-256-pinned upstream corpora by manifest hash (the hashes are
  still verified after download) and uploads each `summary.json` as an
  artifact, so the published results are reproduced outside maintainers'
  machines.
- `docs.yml` runs the organization's `lunadoc check` workflow.
- `publish.yml` builds, runs the documentation gate, the format check, an
  all-target `--deny-warn` check and the tests, then publishes to mooncakes.

## Shared conformance runner

All suites use one dispatcher:

```bash
just conformance <build|run|smoke|plan|fetch> \
  <decimal|decimal_gda|binary|interval> [options]
```

`decimal` is the independent IEEE decimal corpus; `decimal_gda` is the GDA
`.decTest` corpus; `binary` combines TestFloat and MPFR sources; `interval`
uses ITF1788.

`smoke` runs committed fixtures without downloading anything. `plan` prints
the deterministic task list. `fetch` verifies pinned provenance before
installing ignored data below `.tmp/`. `run` executes the chosen suite.
Backend-specific filters, phases, targets, strict mode, sharding and JSON output
are documented in `testdata/bin_float/README.md`, `testdata/decimal/README.md`
and `testdata/interval/README.md`.

## Published claims

- **GDA.** All 64,986 legal executable scalar rows of the 144-file `official`
  corpus pass, and all 16,124 legal rows of `official0`. The 141 `#`
  placeholder or non-scalar rows are diagnostic exclusions, not unsupported
  legal behaviour.
- **Binary.** The TestFloat level-1 matrix (seed 1) has 254,227,872 vectors in
  468 tasks over binary16/32/64/128: 7,461,360 for add, subtract, multiply,
  divide and square root, and 246,766,512 for the IEEE operations mulAdd
  (245,329,920 of them), rem, roundToInt, the conversions to 32- and 64-bit
  signed and unsigned integers, and the comparisons eq, le, lt,
  eq_signaling, le_quiet and lt_quiet. It runs five rounding directions
  where the operation uses one, both tininess modes for the arithmetic
  operations and mulAdd, and both exact and inexact variants for roundToInt and
  the conversions. Invalid integer conversions are compared by flags only,
  because SoftFloat returns platform-specific sentinel values where the API
  returns `None`. The MPFR part adds the 1,055 executable rows of the pinned
  square-root data and 2,088 hash-pinned witnesses covering 29 elementary
  operations at binary32/64/128 precision under all six `BinaryRoundingMode`
  values.
- **IEEE decimal.** Committed decimal32/64/128 DPD and BID fixtures cover
  encoding, special values, flags, core arithmetic and all 1,024 DPD declets on
  native, Wasm, Wasm-GC and JavaScript; LLVM is outside this gate. A committed
  elementary oracle adds 2,784 rows computed from 768-bit MPFR enclosures under
  all eight decimal rounding modes.
- **Interval.** The strict ITF1788 phases pass 4,656/4,656 selected cases:
  sets, relations, numeric observations, cancellation, arithmetic,
  elementary-core, exponentials and logarithms, general power, trigonometric,
  hyperbolic, inverse trigonometric, `atan2`, FMA, integer power and extrema.
  Reverse operations remain unsupported.

The committed smoke fixtures that `just pr` runs are subsets of these: the
binary smoke, for example, has 2,451 rows (240 TestFloat vectors, 3
square-root witnesses, 120 integer-power witnesses and 2,088 elementary
witnesses).

These are finite claims. They do not imply every IEEE 754 or IEEE 1788
operation, arbitrary resource sizes, every NaN payload policy, or future
corpus revisions. The per-package [binary](./conformance/bin_float.md),
[IEEE decimal](./conformance/decimal.md), [GDA](./conformance/decimal_gda.md)
and [interval](./conformance/ball_float.md) conformance pages state the exact
matrix and its exclusions.

## Reproducibility

External artifacts are pinned by revision and SHA-256 in each corpus manifest
(`testdata/*/corpora.json`). Builds use backend-named outputs and isolated
target directories so that parallel jobs do not overwrite each other. Shards
select deterministic case indices, and merged summaries keep exact totals and
failed IDs. Large generated fixtures are split across files (the IEEE decimal
public-API fixture is written 400 tests per file) so that every toolchain
compiles them.

The MoonBit frontends parse and execute numeric rows. Python orchestrates
downloads, task planning, subprocesses, target selection and aggregation. An
optional oracle is never silently replaced by a weaker one; a missing
requirement is reported explicitly.

Performance evidence is separate from semantic conformance. Benchmark
manifests pin the baseline source, dependencies, toolchain, target, schedule,
sample count and dispersion limits, and a performance threshold never changes
correctness. See [performance audit](./performance_audit.md) and the
per-package performance pages.

## Failure triage

1. Re-run the failing backend with the smallest case, ID filter, phase or
   shard that reproduces it.
2. Distinguish parse diagnostics, unsupported cases, legacy classifications,
   executable mismatches and infrastructure failures.
3. Record the expected value, actual value, flags, context, target, corpus
   revision and command.
4. Run the matching white-box package test to decide whether the defect is in
   parsing, arithmetic, interchange or aggregation.
5. After a fix, run the focused case, the committed smoke fixture, the backend
   gate, and finally `just pr` or `just ci`.

Do not weaken strict support, discard flags, or change the denominator to make
a failing gate pass.

## Release gate

Before publishing:

1. align `moon.mod`, `README.md`, the manual and `CHANGELOG.md`;
2. run `just docs`, `lunadoc check`, and inspect generated interface
   differences;
3. run `just pr` while iterating;
4. run `just ci` on the release candidate;
5. publish through the repository's `publish.yml` GitHub Actions workflow.

Local `moon publish` is not the Luna-Flow release path, because the
organization's credentials are supplied by the workflow.
