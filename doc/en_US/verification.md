# Verification

The repository separates fast development checks from finite, reproducible
conformance claims. Passing a corpus proves only the declared formats,
operations, rounding modes, targets, and fixture revisions.

## Verification Layers

| Layer | Command | Purpose |
| --- | --- | --- |
| Documentation | `just docs` | Locale/file/heading/link checks plus executable documentation examples |
| Formatting | `just fmt` | MoonBit formatter |
| Pull request | `just pr [jobs]` | Generated interfaces, all-target checks, native tests, Python tests, smoke corpora |
| IEEE decimal | `just decimal-ci [jobs]` or `just ieee-ci` | Checked-in decimal32/64/128 DPD/BID vectors across supported targets |
| GDA decimal | `just decimal-gda-ci [jobs]` | Pinned `official` and `official0` `.decTest` legal scalar rows |
| Binary | `just bin-ci [jobs]` | Pinned TestFloat level-1 matrix and MPFR data |
| Interval | `just interval-ci [jobs]` | Pinned ITF1788 strict supported phases |
| Complete | `just ci [jobs]` | All generated-interface, target, unit, and conformance gates |

Run the narrowest relevant check first, then broaden before release.

## Shared Conformance Runner

All suites use one dispatcher:

```sh
python3 tools/conformance.py <build|run|smoke|plan|fetch> \
  --backend <decimal|decimal_gda|binary|interval> [options]
```

`decimal` means the independent IEEE decimal corpus; `decimal_gda` means GDA
`.decTest`. `binary` combines TestFloat and MPFR sources. `interval` uses ITL.

`smoke` runs committed fixtures without downloading external corpora. `plan`
shows deterministic tasks. `fetch` verifies pinned provenance before installing
ignored data below `.tmp/`. `run` executes the chosen suite. Backend-specific
filters, phases, targets, strict mode, sharding, and JSON output are documented
under `testdata/*/README.md`.

## Published Claims

- **GDA:** all 64,986 legal executable scalar rows in the 144-file `official`
  corpus pass; all 16,124 legal rows in `official0` pass. The 141 `#`
  placeholder/non-scalar invalid rows are diagnostic exclusions, not
  unsupported legal behavior.
- **Binary:** 7,461,360 TestFloat vectors cover binary16/32/64/128 add,
  subtract, multiply, divide, and square root, five rounding directions, and
  both tininess modes. The pinned MPFR square-root dataset adds 1,055 rows.
- **IEEE decimal:** committed decimal32/64/128 DPD and BID fixtures cover
  encoding, special values, flags, core arithmetic, and all 1,024 DPD declets on
  native, Wasm, Wasm-GC, and JavaScript. LLVM is excluded from this gate.
- **Interval:** the strict ITF1788 phases cover declared set, relation,
  observation, arithmetic, cancellation, elementary, power, trigonometric,
  FMA, integer-power, and extrema operations. Reverse operations remain
  unsupported.

These are finite claims. They do not imply every IEEE 754 or IEEE 1788
operation, arbitrary resource sizes, every NaN payload policy, or unpinned
future corpus revisions.

## Reproducibility

External artifacts are revision- and SHA-256-pinned in corpus manifests. Builds
use backend-named outputs and isolated target directories so parallel jobs do
not overwrite one another. Shards select deterministic case indices, and
merged summaries retain exact totals and failed IDs.

The MoonBit frontend parses and executes numeric rows. Python orchestrates
downloads, task planning, subprocesses, target selection, and aggregation. An
optional oracle is never silently replaced by a weaker implementation; missing
requirements must be reported explicitly.

Performance evidence is separate from semantic conformance. Benchmark manifests
pin baseline source, dependencies, toolchain, target, schedule, sample count,
and dispersion limits. A performance threshold never changes correctness.

## Failure Triage

1. Re-run the failing backend with the smallest case, ID filter, phase, or
   shard that reproduces it.
2. Distinguish parse diagnostics, unsupported cases, legacy classifications,
   executable mismatches, and infrastructure failures.
3. Record expected value, actual value, flags, context, target, corpus revision,
   and command.
4. Run the matching white-box package test to decide whether the defect is in
   parsing, arithmetic, interchange, or aggregation.
5. After a fix, run the focused case, committed smoke fixture, backend gate, and
   finally `just pr` or `just ci` as appropriate.

Do not weaken strict support, discard flags, or change the denominator to make
a failing gate pass.

## Release Gate

Before publishing:

1. align `moon.mod`, root README, localized indexes, standards, and changelog;
2. run `just docs` and inspect generated interface differences;
3. run `just pr` during iteration;
4. run `just ci` for the release candidate;
5. publish through the repository GitHub Actions workflow.

Local `moon publish` is not the Luna-Flow release path because organization
credentials are supplied by the workflow.

