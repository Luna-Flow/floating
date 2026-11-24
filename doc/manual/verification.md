# Verification

The repository separates fast development checks from finite, reproducible
conformance claims. Passing a corpus proves only the declared formats,
operations, rounding modes, targets and fixture revisions. This guide lists the
gates, what each published claim covers, and how to reproduce and triage a
result.

## Verification layers

| Layer | Command | Purpose |
| --- | --- | --- |
| Documentation | `just docs` | `tools/doc_quality.py` (page coverage, API snapshots, links and anchors, version and GDA claims, package `README.mbt.md` files), then `tools/check_doc_examples.py` (every runnable example of the manual), then the `tooling/src/doc_examples` tests |
| Formatting | `just fmt` | the MoonBit formatter |
| Pull request | `just pr [jobs]` | format check, docs, native check and tests with `--deny-warn`, Python tool tests, and the four committed smoke corpora |
| IEEE decimal | `just gate decimal [jobs]` | committed decimal32/64/128 DPD and BID vectors on native, Wasm, Wasm-GC and JavaScript, and the full 9,691-row π-inverse table, read at run time by the release-built conformance CLI on each target |
| GDA decimal | `just gate decimal_gda [jobs]` | package and frontend tests, then the pinned `official` and `official0` `.decTest` corpora |
| Binary | `just gate binary [jobs]` | the pinned TestFloat level-1 matrix and the MPFR witnesses |
| Binary, incremental | `just verify binary [jobs]` | the same gate with the TestFloat tasks and MPFR files whose code, input and toolchain are unchanged reused from the ledger (see Incremental verification) |
| Interval | `just gate interval [jobs]` | every strict ITF1788 phase |
| Random differential | `just random-diff run …` | seeded random cases against MPFR (binary and IEEE `decimal`) and libmpdec (`decimal_gda`), recorded through mare_mark; `just random-diff smoke` runs the committed sample in `just pr` |
| Complete | `just ci [jobs]` | format, docs, `--deny-warn` checks and tests on all four targets, generated interfaces, and every conformance gate |

Run the narrowest relevant check first, then broaden before a release.
Translation catalogs are checked separately by `lunadoc check`, which the
`Docs` workflow runs on every change under `doc/`.

## Continuous integration

- `ci.yml` runs `just pr` on every pull request and every push to `main`. It restores
  the newest verification ledger first and only a push to `main` saves one: GitHub
  scopes a cache to the ref that created it, so what a pull-request run would save
  can be restored by neither `main` nor another pull request. The native tests of
  the pull-request gate run as incremental units (`tools/native_units.py`).
- `nightly.yml` runs `just gate` for `quick`, `decimal`, `decimal_gda`,
  `binary` and `interval` as parallel jobs every night and on demand. It
  caches the SHA-256-pinned upstream corpora by manifest hash (the hashes are
  still verified after download) and uploads each `summary.json` as an
  artifact, so the published results are reproduced outside maintainers'
  machines. It runs the gates with `--no-reuse` and restores no ledger. It also runs the
  unit tests of the whole workspace on `native`, without reuse (the audit of the
  native units of the pull-request gate), `js`, `wasm`
  and `wasm-gc` (the pull-request gate tests native and only type-checks these;
  `QUICK_TEST_TARGETS` in `tools/run_ci.py` is the one line that adds a target to
  it),
  and, on an arm64 macOS runner, the tests of `internal/binary_kernel` and
  `binary` on native with the row primitives portable
  (`LUNA_FLOATING_PORTABLE=1`), forced to the C tier (`LUNA_FLOATING_LIMBS=c`) and
  in the default state; `tools/check_limbs_tier.py` fails the job when the runner
  is not arm64, a state reports another tier than expected, or the switch
  did not take (`enabled=false` in the portable state, `enabled=true` in the others). The Linux runner is
  x86-64, so nothing else executes the arm64 code. `wasm-gc` runs the whole
  workspace except what needs `moonbitlang/async`, which has no wasm-gc
  runtime (its module initialiser is rejected by the runtime at validation); the
  workflow states the reason next to the job.
- `docs.yml` runs the organization's `lunadoc check` workflow.
- `publish.yml` builds, runs the documentation gate, the format check, an
  all-target `--deny-warn` check and the tests, then publishes to mooncakes.

## Quick-gate table of the π-inverse rows

The rows of `asinpi`, `acospi`, `atanpi` and `atan2pi` are the largest table
of the repository. The quick gate (`just pr`, the native test stage of CI)
compiles all 9,691 of them into `library/src/decimal/elementary_pi_inverse_rows_wbtest.mbt`
(2.2 MB of source), and the same rows are data
(`testdata/decimal/ieee/rows/pi_inverse.txt`, `mpfr-decimal-random-v2` rows, see
`tooling/src/frontend/mpfr_expr`) that `just gate decimal` and the nightly run feed to the
release-built conformance CLI on native, Wasm, Wasm-GC and JavaScript. Both compare
value, cohort (`total_order_compare`) and all flags exactly.

This was not always so. While about 50 `atan2pi` rows with an operand of
`1E-1999996` cost 90 % of a 466 s debug run, the quick gate compiled only a
deterministic sample. After the `atan2pi` path for tiny operands was fixed the
full table runs in 2.4 s of a debug native build (4,416 sampled rows: 0.5 s) and
adds about 1.4 s to the build, under the 5 s the quick gate allows it, so the
sample was dropped. The mechanism stays in the generator
(`tools/generate_decimal_pi_inverse_rows.py`) as an option:
`--sample-step N` compiles every row that is not the rounding of an MPFR
enclosure (the exact Niven values and the other cases decided by exact rational
arithmetic) and, of the MPFR rows stratified by (operation, rounding mode), one
row in N, taken equidistantly in generation order (a stratum shorter than N keeps
its middle row). The data file is always the full table.

| Operation | Exact rows | MPFR rows | Total |
| --- | ---: | ---: | ---: |
| `asinpi` | 148 | 1,125 | 1,273 |
| `acospi` | 148 | 950 | 1,098 |
| `atanpi` | 148 | 1,440 | 1,588 |
| `atan2pi` | 1,248 | 4,484 | 5,732 |
| Total | 1,692 | 7,999 | 9,691 |

`python3 tools/generate_decimal_pi_inverse_rows.py --check` fails if either
table is stale or if the compiled table is not a subset of the full table, and
`--strata` prints the counts of every stratum. Go back to a sample (start with
`--sample-step 8` and set `SAMPLE_STEP` in the generator) when the debug native run
of the `pi inverse generated rows` test exceeds about 5 s again: measure it with
`python3 tools/native_test_timing.py --package library/src/decimal`, not by assumption.

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
are documented in `testdata/binary/README.md`, `testdata/decimal/README.md` (IEEE `decimal`),
`testdata/decimal_gda/README.md` and `testdata/interval/README.md`.

## Published claims

- **GDA.** All 64,986 legal executable scalar rows of the 144-file `official`
  corpus pass, and all 16,124 legal rows of `official0`. The 141 `#`
  placeholder or non-scalar rows are diagnostic exclusions, not unsupported
  legal behaviour.
- **Binary.** The TestFloat level-1 matrix (seed 1) has 254,280,504 vectors in
  534 tasks over binary16/32/64/128: 7,461,360 for add, subtract, multiply,
  divide and square root, 52,632 for the format conversions (each of the four
  formats to each of the other three, 66 tasks), and 246,766,512 for the IEEE
  operations mulAdd (245,329,920 of them), rem, roundToInt, the conversions to
  32- and 64-bit signed and unsigned integers, and the comparisons eq, le, lt,
  eq_signaling, le_quiet and lt_quiet. It runs five rounding directions
  where the operation uses one, both tininess modes for the arithmetic
  operations, mulAdd and the narrowing format conversions, and both exact and inexact variants for roundToInt and
  the conversions. Invalid integer conversions are compared by flags only,
  because SoftFloat returns platform-specific sentinel values where the API
  returns `None`. The gate judges the operation, not the operation followed by a rounding
  of the harness: the result is packed into the bit fields of its format by the
  front end itself and a result that is not a number of the format fails the
  vector; the flags compared are the operation's own. The MPFR part adds the 1,055 executable rows of the pinned
  square-root data, 1,740 hash-pinned witnesses covering 29 elementary
  operations at binary32/64/128 precision under the five `BinaryRoundingMode`
  values, and the decimal character conversions of IEEE 754-2019 §5.12:
  3,699 `mpfr_strtofr` witnesses (decimal text to binary at 11 to 200 bits,
  including exact halfway points and the exponent limits) and 2,688
  `mpfr_get_str` witnesses (fixed digit counts, exact ties and the shortest
  round-trip digit count).
- **IEEE decimal.** Committed decimal32/64/128 DPD and BID fixtures cover
  encoding, special values, flags, core arithmetic and all 1,024 DPD declets on
  native, Wasm, Wasm-GC and JavaScript; LLVM is outside this gate. A committed
  elementary oracle adds 3,060 rows computed from 768-bit MPFR enclosures under
  the five IEEE decimal rounding-direction attributes.
- **Interval.** The strict ITF1788 phases pass 6,632/6,632 selected cases:
  sets, relations, numeric observations, cancellation, arithmetic,
  elementary-core, exponentials and logarithms, general power, trigonometric,
  hyperbolic, inverse trigonometric, `atan2`, FMA, integer power, extrema, the
  integer functions, reverse multiplication and the algebraic and
  trigonometric reverse functions, `powRev1` and `powRev2`. `atan2Rev1` and `atan2Rev2` have no ITF1788 cases; the gate runs 16,260 generated cases of ours (`testdata/interval/generated`, written and validated by `tools/itl_atan2_reverse_oracle.py`) as the separate `atan2-reverse` phase.

The committed smoke fixtures that `just pr` runs are subsets of these: the
binary smoke, for example, has 8,514 rows (288 TestFloat vectors, 3
square-root witnesses, 96 integer-power witnesses, 1,740 elementary witnesses,
3,699 `strtofr` witnesses and 2,688 decimal output witnesses). These counts
are read from the manifests (`testdata/binary/corpora.json` and
`testdata/binary/smoke/manifest.json`) by `tools/check_manual_counts.py`,
which runs with the unit tests of `just pr` and fails when a page and a
manifest disagree.

These are finite claims. They do not imply every IEEE 754 or IEEE 1788
operation, arbitrary resource sizes, every NaN payload policy, or future
corpus revisions. The per-package [binary](./conformance/binary.md),
[IEEE decimal](./conformance/decimal.md), [GDA](./conformance/decimal_gda.md)
and [interval](./conformance/interval.md) conformance pages state the exact
matrix and its exclusions.

## External performance baseline

`just bench external run` times `floating` against MPFR and libmpdec on the same
operands and records the ratios; every `floating` result is first compared with
the result of the reference library for the same operand. The method, machine
and results are on the [external baseline page](./performance/bench/external.md).
It is evidence about speed, not a conformance gate, and is not part of `just pr`.

## Interval differential stage against MPFR

`python3 tools/interval_diff.py run` checks `Interval` against MPFR with no timing.
A seeded generator writes rows of operand intervals for `add`, `sub`, `mul`,
`div`, `sqr`, `sqrt`, `fma`, `exp` and `ln`; `tools/interval_mpfr_oracle.c` computes the tightest
result of every row with MPFR directly (one directed rounding per bound, in the
exponent range and with the gradual underflow of `binary`, defined once in
`tools/mpfr_ours.h`); the test of `tooling/src/differential/interval_mpfr` runs the
rows on `Interval` and compares both bounds as canonical text. IEEE 1788-2015
12.10.2 makes the first seven operations tightest, so the bounds must be equal;
`exp` and `ln` are only required to be valid, so their result must enclose the
tightest one and must not be wider than 1,024 units of the last place (the
standard says "should be accurate"), with `exp` rows at the overflow and
underflow thresholds and `ln` rows at the ends of the range. The
classes of operands are ordinary values, results one unit from the overflow
threshold on both sides, results and operands in the subnormal band, operands
whose exponents differ by far more than the precision, operands with fewer bits
than the precision, bounds with more bits than the precision (the interval rounds
them outward), and intervals with a zero bound. A class that does not reach its
band is an error of the generator, decided from the oracle's own flags. The stage is
part of `just gate interval`. An oracle in Python integers, which shares nothing
with MPFR, decides every arithmetic row with nothing but CPython and is the
required one; MPFR decides all rows, `exp` and `ln` included, when its headers
are found, and the two must agree on every arithmetic row. The report says which
oracles ran and how many rows each decided, and on a machine without MPFR it
lists the rows only MPFR decides as not checked. For `exp` and `ln` it also
reports the excess over the tightest bound in units of the last place. A row that differs from MPFR today is listed
with its issue in `tools/interval_diff_known.txt`; a new difference, or a listed row
that agrees again, fails the run.

## Randomized differential testing

The fixed corpora above check rows someone chose. The randomized campaign
(`just random-diff`, [tutorial](./tutorial/differential.md),
[design](./design/differential.md)) generates seeded cases and compares the
library with two independent implementations: GNU MPFR 4.2.2 (GMP 6.3.0) for
`binary` and libmpdec 4.0.0 (Python 3.13 `decimal`) for `decimal_gda`
(the IEEE `decimal` package is checked against MPFR, below). Both are oracles, not
specifications: every disagreement was read against IEEE 754-2019 or the
General Decimal Arithmetic 1.70 text before it was called a bug.

**What is varied.** Binary: output precisions 2 to 10,000 (a mix of small,
format-sized, log-uniform and large), operand widths independent of the output
precision, all five MPFR directions plus the nearest-away wrapper, unbounded
contexts and bounded ones (binary16/32/64/128 ranges and random ranges) with
both tininess rules, operand exponents at the overflow threshold, the smallest
normal number and in the subnormal range, exact halfway and near-halfway results
(precision one bit below the exact result), cancellation, alignment gaps around
the precision, zeros, infinities and NaNs, decimal text in both directions
(`strtofr` with exact halfway literals, `getstr` with 1 to 1,200 digits, the
shortest round-trip form) and 28 elementary functions (including `pow`, `pown`,
`rootn`, `hypot` and `atan2`). Decimal:
decimal32/64/128 contexts and random GDA contexts (precision up to 5,000,
Emax up to 999,999,999, all eight rounding modes, clamp on and off), the same
structured operands, string conversion (`apply`, `tosci`, `toeng`) and `exp`,
`ln`, `log10`, `power`. Every value and every flag (inexact, overflow,
underflow, invalid, division by zero; the GDA conditions for decimal) is
compared.

**Reproducibility.** Case `I` of family `F` under seed `S` is a pure function of
`(S, F, I)`; the seed of every run below is 20261118. Each run is recorded as
mare_mark JSONL (validations per batch of 1,000 cases, delta-debugged failures,
replay commands) and summarized in `summary.json` next to it. The record of a
backend stays in `.tmp/random-diff/<run>/records-<backend>.jsonl`.

**Cases run, per operation and backend.** Native: 26,900,000 cases (28,900,000
executed, counting 2,000,000 `sqrt` cases made before the MPFR defect filter);
Wasm, JavaScript and Wasm-GC: 2,730,000 each. Wasm-GC has no mare_mark runtime
(the runner needs `moonbitlang/async`), so it ran the same corpora through the
synchronous `floating-conformance` runner without the JSONL record. The three
other backends ran the first 200,000 (binary) or 100,000 (`decimal_gda`) cases of each
family of the native run, so their failing batches can be compared with it:
Wasm and JavaScript fail on exactly the same batches as native within that
range.

**MPFR (binary)**

| Operation | native | Wasm | JavaScript | Wasm-GC |
| --- | ---: | ---: | ---: | ---: |
| `acos (elementary)` | 35,445 | 3,625 | 3,625 | 3,625 |
| `acosh (elementary)` | 35,602 | 3,507 | 3,507 | 3,507 |
| `add` | 2,000,000 | 200,000 | 200,000 | 200,000 |
| `asin (elementary)` | 35,524 | 3,431 | 3,431 | 3,431 |
| `asinh (elementary)` | 35,946 | 3,618 | 3,618 | 3,618 |
| `atan (elementary)` | 35,763 | 3,499 | 3,499 | 3,499 |
| `atan2 (elementary)` | 35,765 | 3,645 | 3,645 | 3,645 |
| `atanh (elementary)` | 35,595 | 3,565 | 3,565 | 3,565 |
| `cos (elementary)` | 35,396 | 3,493 | 3,493 | 3,493 |
| `cosh (elementary)` | 35,695 | 3,686 | 3,686 | 3,686 |
| `cospi (elementary)` | 35,627 | 3,491 | 3,491 | 3,491 |
| `div` | 2,000,000 | 200,000 | 200,000 | 200,000 |
| `exp (elementary)` | 35,748 | 3,590 | 3,590 | 3,590 |
| `exp10 (elementary)` | 35,668 | 3,579 | 3,579 | 3,579 |
| `exp2 (elementary)` | 35,751 | 3,648 | 3,648 | 3,648 |
| `expm1 (elementary)` | 35,992 | 3,691 | 3,691 | 3,691 |
| `fma` | 2,000,000 | 200,000 | 200,000 | 200,000 |
| `getstr` | 2,000,000 | 200,000 | 200,000 | 200,000 |
| `hypot (elementary)` | 35,805 | 3,655 | 3,655 | 3,655 |
| `ln (elementary)` | 36,144 | 3,517 | 3,517 | 3,517 |
| `log10 (elementary)` | 36,002 | 3,575 | 3,575 | 3,575 |
| `log1p (elementary)` | 35,554 | 3,566 | 3,566 | 3,566 |
| `log2 (elementary)` | 35,473 | 3,546 | 3,546 | 3,546 |
| `mul` | 2,000,000 | 200,000 | 200,000 | 200,000 |
| `pow (elementary)` | 35,594 | 3,595 | 3,595 | 3,595 |
| `pown (elementary)` | 35,598 | 3,573 | 3,573 | 3,573 |
| `rootn (elementary)` | 35,779 | 3,482 | 3,482 | 3,482 |
| `shortest` | 500,000 | 50,000 | 50,000 | 50,000 |
| `sin (elementary)` | 35,681 | 3,643 | 3,643 | 3,643 |
| `sinh (elementary)` | 35,669 | 3,530 | 3,530 | 3,530 |
| `sinpi (elementary)` | 35,631 | 3,513 | 3,513 | 3,513 |
| `sqrt` | 2,000,000 | 200,000 | 200,000 | 200,000 |
| `strtofr` | 2,000,000 | 200,000 | 200,000 | 200,000 |
| `sub` | 2,000,000 | 200,000 | 200,000 | 200,000 |
| `tan (elementary)` | 35,727 | 3,531 | 3,531 | 3,531 |
| `tanh (elementary)` | 35,796 | 3,659 | 3,659 | 3,659 |
| `tanpi (elementary)` | 36,030 | 3,547 | 3,547 | 3,547 |
| **total** | **17,500,000** | **1,750,000** | **1,750,000** | **1,750,000** |

**libmpdec (`decimal_gda`)**

| Operation | native | Wasm | JavaScript | Wasm-GC |
| --- | ---: | ---: | ---: | ---: |
| `add` | 1,000,000 | 100,000 | 100,000 | 100,000 |
| `apply` | 1,000,000 | 100,000 | 100,000 | 100,000 |
| `divide` | 1,000,000 | 100,000 | 100,000 | 100,000 |
| `exp` | 100,000 | 20,000 | 20,000 | 20,000 |
| `fma` | 1,000,000 | 100,000 | 100,000 | 100,000 |
| `ln` | 100,000 | 20,000 | 20,000 | 20,000 |
| `log10` | 100,000 | 20,000 | 20,000 | 20,000 |
| `multiply` | 1,000,000 | 100,000 | 100,000 | 100,000 |
| `power` | 100,000 | 20,000 | 20,000 | 20,000 |
| `squareroot` | 1,000,000 | 100,000 | 100,000 | 100,000 |
| `subtract` | 1,000,000 | 100,000 | 100,000 | 100,000 |
| `toeng` | 1,000,000 | 100,000 | 100,000 | 100,000 |
| `tosci` | 1,000,000 | 100,000 | 100,000 | 100,000 |
| **total** | **9,400,000** | **980,000** | **980,000** | **980,000** |

(`sqrt` on native: the table counts the 2,000,000 cases of the final run; the first run of 2,000,000 `sqrt` cases, made before the MPFR defect filter, is not counted: 2,000,000.)

**Names.** The family prefixes `dec-` (`decimal_gda` against libmpdec) and
`decm-` (IEEE `decimal` against MPFR), and the option `--decm`, are now
`decimal_gda-`, `decimal-` and `--decimal`; the old spellings are deprecated
aliases. The run logs below quote the commands as they were run.

**MPFR enclosures (decimal elementary functions)**, a third corpus
(`mpfr-decimal-random-v2`, `just random-diff run --decimal`). The IEEE `decimal`
package's elementary functions are checked against MPFR through certified
enclosures, not single results: 2048-bit directed operand bounds, 768-bit
directed results on every corner, one ulp of slack, both endpoints rounded to
the context with Python `decimal`; a row exists only if the endpoints agree and
the rounded value lies outside the enclosure (so exact results are not sampled
here). Contexts are decimal32/64/128 and random ones (precision 1 to 120,
exponent range up to ±20,000; since 0.12 only legal contexts: the five rounding directions of IEEE 754-2019 4.3, `e_min = 1 - e_max`, clamp, tininess before rounding; the campaign counts below are those of the runs before that change); operands are drawn so that results reach overflow, underflow
and the subnormal range. Native: 559,979 cases, 20,000 for each of 28 functions
(`exp exp2 exp10 expm1 sinh cosh ln log2 log10 log1p sin cos tan sinpi cospi
tanpi atan tanh asinh asin acos atanh acosh pow hypot atan2 rootn pown`; `cospi`
and `tanh` have a few candidates that never certify within eight attempts);
Wasm, JavaScript and Wasm-GC: 55,996 each (the first 2,000 of every function).

**Outcome.**

- *Binary arithmetic, string conversion and `shortest`*: no disagreement in
  16,500,000 native cases (plus 1,650,000 on each of the other three
  backends) apart from the MPFR defect below. Every one of the 5 rounding directions, both
  tininess rules, the exponent limits and the subnormal range were exercised;
  a mutation check (swapping the two tininess rules, or nearest-even with
  nearest-away, in the executor) fails 0.15% to 2.8% of the rows, so the rows
  that decide those cases are present.
- *Decimal elementary functions against MPFR*: 26 of the 28 functions agree
  with MPFR in value, cohort and flags in every one of their 20,000
  native cases, and the same rows pass on Wasm, JavaScript and Wasm-GC. Two
  disagreements, with the identical failing ids on all four backends: `atan2`
  returns the zero of an underflowed result with exponent 0 instead of the
  least exponent `e_min - p + 1` (54 of 20,000 rows, e.g. `atan2(1E-500, 9)` in
  decimal64 gives `0`, not `0E-398`; IEEE 754-2019 §5.2: an inexact result uses
  the cohort member of least possible exponent), and `exp` raises no
  Underflow and Subnormal for a result that underflows to the smallest
  subnormal when `precision = 1`, the non-standard `AfterRounding` tininess
  option is selected and the direction is `Up`, `Ceiling` or `ZeroFiveUp` (22
  of 20,000 rows; the smallest subnormal equals the smallest normal number
  then, and the library's own after-rounding rule says the result is tiny; the
  standard rule for decimal formats, tininess before rounding, was correct).
  Both are reported separately and become regression rows when fixed.
- *Decimal `exp2m1`, `exp10m1`, `log2p1` and `log10p1`*
  ([#236](https://github.com/Luna-Flow/floating/issues/236)): families
  `decm-exp2m1`, `decm-exp10m1`, `decm-log2p1` and `decm-log10p1`, seed
  20261118, 250,000 native cases each (1,000,000 in all) agree with MPFR in
  value, cohort and all eight flags, and so do 100,000 cases each on Wasm,
  Wasm-GC and JavaScript (400,000 per target, 1,200,000 in all, 804 validated
  batches, run on 2026-11-19 with `just random-diff run --family decm-exp2m1
  --family decm-exp10m1 --family decm-log2p1 --family decm-log10p1 --count
  100000 --seed 20261118 --target wasm --target wasm-gc --target js`). On the
  final code the native 1,000,000 cases of seed 20261118 were run again
  (1,000 validated batches) and a second seed, 20261202, with 100,000 cases
  per function on native, Wasm, Wasm-GC and JavaScript (400,000 per target,
  1,600,000 in all, 1,204 validated batches), both on 2026-11-19 and both
  without a disagreement. Exact results are not sampled here; they,
  the clusters near the integers and near -1, the tiny arguments and the
  tininess and clamp boundaries are the 7,175 rows of
  `library/src/decimal/elementary_pm1_rows_wbtest.mbt` (exact rational arithmetic and
  certified MPFR enclosures, `tools/generate_decimal_pm1_rows.py`), which pass
  on native, Wasm, Wasm-GC and JavaScript.
- *Decimal `rsqrt`, `compound` and `powr`*
  ([#236](https://github.com/Luna-Flow/floating/issues/236)): families
  `decm-rsqrt`, `decm-compound` and `decm-powr`; `compound` rows are
  certified from exact arithmetic (the rational $(1+x)^n$, an exact decimal
  $1 + nx \pm 2(nx)^2$ for $|x| < 10^{-150}$, or libmpdec $\exp(n\ln(1+x))$
  with a proven slack), never from `mpfr_compound_si`, which MPFR 4.2.2 rounds
  wrongly for $n < 0$ in the directed modes. Seed 20261118: 250,000 native
  cases per function (750,000) and 100,000 per function on each of Wasm,
  Wasm-GC and JavaScript (900,000); seed 20261202: 100,000 per function on
  native, Wasm, Wasm-GC and JavaScript (1,200,000); all on 2026-11-19 and all
  in agreement in value, cohort and flags. The 8,459 rows of
  `library/src/decimal/elementary_rcp_rows_wbtest.mbt`
  (`tools/generate_decimal_rcp_rows.py`) add the exact cases, the preferred
  exponents, the `Int32` minimum of `compound`, operands down to
  $10^{-1\,999\,997}$ and the range limits, on all four targets.
- *Decimal `exp`, `exp2` and `exp10` at the range limits*
  ([#363](https://github.com/Luna-Flow/floating/issues/363)): families
  `decimal-exp`, `decimal-exp2` and `decimal-exp10`, 100,000 native cases per
  function for seed 334 and for seed 20261120 (600,000) and 20,000 per
  function on each of Wasm, Wasm-GC and JavaScript for seed 334 (180,000), run
  on 2026-11-20, in agreement with MPFR in value, cohort and flags. The
  generator reaches the failing arguments only rarely (case `m334.exp2.30728`
  is one of them), so the boundaries are covered by deterministic rows:
  `library/src/decimal/exp_range_rows_wbtest.mbt` (`tools/generate_decimal_exp_range_rows.py`,
  Python `decimal` at 400 digits, a cross-check only) holds 8,305 rows for
  the context of the issue, decimal32, decimal64, decimal128 and a wide
  context, the five rounding directions, at results just inside and outside
  the range and at the thresholds of the decision; they also cover `expm1`,
  `exp2m1`, `exp10m1`, `sinh`, `cosh`, `pow`, `powr`, `pown`, `compound` and
  `rsqrt`, none of which failed before the change.
- *Decimal `asinPi`, `acosPi`, `atanPi` and `atan2Pi`*
  ([#236](https://github.com/Luna-Flow/floating/issues/236)): families
  `decimal-asinpi`, `decimal-acospi`, `decimal-atanpi` and `decimal-atan2pi`, certified
  by `mpfr_asinpi`, `mpfr_acospi`, `mpfr_atanpi` and `mpfr_atan2pi`. Seed
  20261118: 100,000 native cases per function (400,000) and 20,000 per
  function on each of Wasm, Wasm-GC and JavaScript (240,000), 564 validated
  batches, run on 2026-11-19 with `just random-diff run --family decimal-asinpi
  --family decimal-acospi --family decimal-atanpi --family decimal-atan2pi --count
  100000 --seed 20261118 --target native` and the same with `--count 20000
  --target wasm --target wasm-gc --target js`, in agreement with MPFR in
  value, cohort and all eight flags. The 9,691 rows of
  `testdata/decimal/ieee/rows/pi_inverse.txt`
  (`tools/generate_decimal_pi_inverse_rows.py`) add the exact Niven values at
  the preferred exponent 0, the clusters next to $\pm\tfrac12$ and $\pm 1$ in
  the five rounding directions on both sides, operands down to
  $10^{-1\,999\,996}$ and the range limits of decimal32/64/128. They run in the full gate and the nightly run on all four
  targets, and all of them run in the quick gate (see
  [Quick-gate table of the π-inverse rows](#quick-gate-table-of-the-π-inverse-rows)).
- *Binary elementary functions*: one finding in 1,000,000 native cases (and
  300,000 on the other backends): `exp2` of exactly −2^30 returned +0 with no
  flags where the result 2^−1073741824 is an exact subnormal (13 cases,
  [#271](https://github.com/Luna-Flow/floating/issues/271)). It is fixed, and
  its rows are regression rows of `testdata/binary/random-regressions.txt`.
  After the fix two seeds (20261118 and 20261201) agree with MPFR in 1,000,000
  native `elem` cases each. The random sample reaches the range limits rarely,
  so `tools/range_boundary_rows.py` generates the thresholds directly: for
  every precision from 2 to 300, six contexts (unbounded, the binary16, 32, 64
  and 128 ranges, `e_min = -6`) and the thresholds log2(result) in
  {q − 1, q, e_min, e_max, e_max + 1}, the arguments of `exp`, `exp2`, `exp10`,
  `expm1`, `pow`, `pown` and `rootn` are placed on each threshold and at
  relative offsets of 2^−20 to 2^−64, rounding direction and tininess rule
  cycling (1,269,554 rows). That sweep found four more disagreements, all
  fixed with regression rows or tests: `pow` of an exact power of two below
  2^e_min ([#272](https://github.com/Luna-Flow/floating/issues/272)), the
  underflow flag of `pown` under after-rounding tininess near the
  implementation limit
  ([#273](https://github.com/Luna-Flow/floating/issues/273)), `expm1` just
  past its overflow threshold
  ([#274](https://github.com/Luna-Flow/floating/issues/274)) and `pown` of a
  value between half and the whole smallest subnormal, rounded to the wrong
  neighbour ([#278](https://github.com/Luna-Flow/floating/issues/278)); after
  the fixes it agrees with MPFR in all 1,269,554 rows. A probe of the neighbouring
  `hypot` found that operands with an exponent beyond ±2^29 give 0 or infinity
  without flags ([#275](https://github.com/Luna-Flow/floating/issues/275),
  open): the random generator does not draw such operands and the sweep does
  not include that function.
- *`rSqrt`, `compound` and `powr`* (family `elem3` of the generator): 1,000,000
  native cases and 100,000 on each of Wasm, JavaScript and Wasm-GC agree with
  MPFR 4.2.2, and so do 718,824 range-boundary rows (precisions 2 to 300, six
  contexts, both tininess rules; the thresholds of $1/\sqrt{x}$,
  $(1 + x)^n$ for $n \in \{\pm 3, \pm 7, \pm 100\}$ and $x^y$ with $y$ placed on
  $\log_2$ of each threshold). The comparison needed two corrections of the
  oracle, both documented in `testdata/binary/README.md`: `mpfr_compound_si`
  is wrong for a negative `n` in the directed modes and near the range limits
  (proved with exact rational arithmetic on all 2,017 boundary rows; the rows
  use the exact rational instead), and `mpfr_rec_sqrt(-0)` is +inf where the
  standard says -inf. The library had no disagreement in either case.
- *`asinPi`, `acosPi`, `atanPi` and `atan2Pi`* (family `elem4` of the generator):
  1,000,000 native cases and 100,000 on each of Wasm, JavaScript and Wasm-GC
  agree with MPFR 4.2.2 (`mpfr_asinpi`, `mpfr_acospi`, `mpfr_atanpi`,
  `mpfr_atan2pi`), and so do 1,654,315 range-boundary rows (precisions 2 to 300,
  six contexts, both tininess rules): the underflow thresholds
  ($\operatorname{asinPi}(x) \approx x/\pi$ at $x = \pi 2^{k}$), the anchors
  $\pm 1/2$ and $\pm 1$ for $\operatorname{atanPi}$ of a huge argument,
  $\operatorname{acosPi}$ of a tiny one and $\operatorname{atan2Pi}$ of an extreme
  ratio (leading-exponent difference $D$ from $\pm(p + 4)$ to $\pm(p + 12)$,
  around the point $|D| = p + 8$ where the library switches to the anchor rule),
  and arguments next to $\pm 1$. 11,661 `atan2pi` rows with operands more than
  100,000 binades apart are not oracle rows: `mpfr_atan2pi` of MPFR 4.2.2
  slows down with the exponent difference (5 s at 2^(2*10^7)), so they are
  skipped and covered by `library/src/binary/pi_inverse_wbtest.mbt` against an
  independent model and against `atanpi` of an exact power of two. The library
  had no disagreement.
- *Decimal arithmetic*: `multiply`, `divide`, `squareroot`, `apply`, `tosci` and
  `toeng` agreed with libmpdec in all 6,000,000 native cases. `add`,
  `subtract` and `fma` disagreed in 83 of 3,000,000 (overflow reported when an
  operand rounds past Nmax: [#264](https://github.com/Luna-Flow/floating/issues/264)).
  The campaign's first run had 10 further disagreements whose operand was above
  Emax; decTest converts operands subject to the directives, so they are a
  property of the rows, not findings (the generator now keeps operands within
  Emax).
- *Decimal `power`*: 100,000 native cases disagreed with libmpdec in at least
  300 of them; four defects are filed: the sign of an overflowing result
  ([#265](https://github.com/Luna-Flow/floating/issues/265)), trailing zeros of
  inexact results ([#266](https://github.com/Luna-Flow/floating/issues/266)), a
  spurious Clamped ([#267](https://github.com/Luna-Flow/floating/issues/267)) and
  missing Subnormal and Underflow
  ([#268](https://github.com/Luna-Flow/floating/issues/268)). One more symptom
  (the exact result `power(0.05, -8) = 2.56E+10` raises Rounded) is not filed
  yet. `exp`, `ln` and `log10` agreed in all 300,000 native cases.

**Known intentional differences, filtered where the rows are generated.** The
numbers above exclude, and the test-data READMEs document, these cases:
MPFR has no subnormals (emulated with `mpfr_subnormalize`; nearest-away rows
that would be subnormal are drawn in nearest-even) and its range is one binade
narrower than that of `Binary` at the extreme limits (the rows set MPFR's range to the
row's own range, so those limits are compared); NaN payloads are not compared;
the decimal elementary functions answer `Invalid_context` when |Emax| or |Emin|
reaches 10^6 (the decNumber `DEC_MAX_MATH` limit the package adopts as a deliberate implementation limit, which decTest requires and GDA 1.70's Invalid context condition permits, but which the operation text does not state; opt-in
`decimal_gda-*wide` families sample those contexts); libmpdec decides Subnormal and
Underflow of `exp`, `ln`, `log10` and `power` after rounding where GDA 1.70 says before
any rounding, so elementary rows keep Emin below 0; `apply` of a signaling NaN
is not specified; `tosci` and `toeng` apply the context precision as decTest
specifies.

**An oracle defect.** `mpfr_sqrt` of MPFR 4.2.2 (Homebrew bottle, arm64) reports
an exact result, or a result on the wrong side of the root, for some operands
with an odd binary exponent whose precision is near the output precision
(`tools/mpfr_sqrt_ternary_repro.c` is a standalone reproducer). The first run of
2,000,000 `sqrt` cases had 22 failing batches from it; the generator now checks
each `sqrt` row with exact arithmetic and draws the case again when MPFR is
wrong, and the final run of 2,000,000 `sqrt` cases agreed in all cases. This is
a claim about the Homebrew build I used, not about every MPFR release.

**Not covered.** Operations the oracles lack (`rem`, `roundToIntegral`, the
integer conversions, `scaleB`/`logB`, decimal operations other than the thirteen
families); NaN payload policy; nearest-away results in the subnormal range;
decimal contexts with |Emax| or |Emin| of 10^6 or more for the elementary
functions; precisions above 700 for the binary elementary functions; the LLVM
backend; interval arithmetic. The campaign samples a finite space with fixed
seeds: the counts are what was run, not a proof of absence.

## Incremental verification

A full `just gate binary` took about 19 minutes on 2026-11-21 on one development machine with 3 jobs, 17 of them the 534 TestFloat tasks. Incremental
verification does not run a verification unit again when what it could depend on has not changed,
and says so in the report. It is available for the binary gate (`just verify binary`, or
`python3 tools/conformance.py run --backend binary --incremental`); the full gates stay, nightly
and before a release, as the audit.

### What a unit is, and what "reused" means

A unit is one TestFloat task (operation, format, rounding, tininess) or one MPFR corpus file. A
unit is **reused** when its key is in the ledger: the recorded result of the same unit, run on the
commit the report names, is cited and the unit is not executed in this run. A reused unit is never
counted as run: the report has separate lines for the units executed in this run, the sampled
reruns and the reused units, and the `TOTAL` line says that it counts only what was executed.

The key of a unit is the hash of:

| part | what it is |
| --- | --- |
| frame | the fingerprint of the compiled code reachable from the entry of the frontend (`run` of the TestFloat or MPFR frontend), start-up code included, the dispatcher covered by its own text and the operation functions left out |
| arms | the fingerprints of the operation functions (`arm_add`, ...) that the process recorded at run time (the summary prints them as `arms`) |
| input | the sha256 of the data, or for TestFloat the sha256 of the generator binary with its arguments and seed |
| arguments | the arguments of the interpreter |
| toolchain | `moon`, `moonc`, the C compiler, the compile and link command lines that `moon` prints, the runtime sources, headers and objects, the native stub sources of the library and of the dependencies, and the environment variables the stubs read (`LUNA_FLOATING_PORTABLE`, `LUNA_FLOATING_LIMBS`) |
| verifier | the `tools/` modules the runner has imported, so a change to a judging tool reruns everything |
| normalisations | the set of normalisations of the fingerprint, and the version of the key |

The fingerprint is taken from the C file that the native backend generates (about 18 MB, 6,300
definitions). It splits the file into definitions and hashes each one after four normalisations and
nothing else: `#line` directives are deleted; names that are local to one definition are renamed by
kind and order of appearance; names that carry a compiler counter (closures, records, string
literals, generic instances) are renamed by where they are first referenced; and object-header
layout indices are replaced by the layout entry they select. The last is the only one that rests on a
fact about the runtime (the index is read only as a table position) and it is a flag of the tool
(`layout=True`, `--no-layout` to compare). Whatever it cannot
attribute to a definition goes into a residue that is part of every key. When in doubt a unit runs.

### The guards

- Every run executes a random 2 % of the units it would reuse (at least one), prints the seed
  (`--sample-seed` fixes it) and compares the result with the ledger. A difference is a defect of the
  system, not a verification failure: the exit status is 70 and the line stops.
- The key is bound to the executable that runs: `build_backend` writes `<exe>.build.json` with the
  hashes of the executable and of the C file; any mismatch, or a key that cannot be formed (an
  entry that is not in the build, a parse error), prints `incremental disabled: <reason>`, runs
  every unit and records nothing.
- A unit is recorded only when it passed. The process says which frontend ran, and a mismatch with
  the unit is a defect.
- The system has its own mutation test (`python3 tools/verify_mutation.py`): edits to the kernel, to
  `binary` arithmetic and elementary functions, to `interval`, to both decimal packages, to the
  TestFloat frontend and to an initialiser. For every edit that a vector or corpus can see, the whole
  selection is also run on the mutated build, and a unit that fails there must not have been reused
  (the check that shares no code with the keys); comment-only and formatting-only edits must change no
  key.

### The ledger

`.tmp/verification-ledger/ledger.jsonl` of the main checkout, shared by all worktrees on the machine
(`--ledger` or `LUNA_VERIFICATION_LEDGER` chooses another). It is append-only and not committed; a
record holds the key, its components (frame, input, toolchain, verifier, arm fingerprints), the
result, the commit, the date, the host and the path of the log. A result recorded from a dirty tree
is as valid as any: the key is of the code that was built, the commit is information only (shown as
`+dirty`), so the ledger is never cleaned by commit.

### What a change costs

Measured by replaying the keys over 30 consecutive commits of `main` (2026-11-21, 62ac93e0 to
95fae256, one build per commit, `tools/verify_replay.py`), by the cause of the change:

| kind of change | commits | units that would run (of 538) |
| --- | --- | --- |
| no key changes (documentation, tests, code no unit reaches) | 18 | 0 |
| only the MPFR frontend changes | 9 | 4 (the MPFR files, under a second) |
| code that every TestFloat task reaches changes | 2 | 538 (the whole stage) |
| the start-up code changes (the initialisers of top-level values) | 1 | 538 (the whole stage) |

The start-up code is part of every key, so one changed initialiser reruns every unit; in this window
that happened once. Few commits rerun the whole stage, because most changes are in code that no
TestFloat task reaches.

### The kernel stages

The seven kernel stages of the binary gate (the product routes and the oracles under three states of
the limb tier, and the oracle tables) took about 220 s and always ran in full. The package under test,
`library/src/internal/binary_kernel`, is a leaf of the module: it imports only `moonbitlang/core/...`,
so nothing else of the repository is compiled into its test executable. Each stage under each state
is therefore a unit of its own, keyed by the content of the package's files (sources, tests, row
tables, the native stub, `moon.pkg`) and of the module files, the command line (which holds the
state), the `moon test` wrapper, the build commands that `moon test --dry-run` prints, the toolchain,
the variables of the environment that `moon` and the stubs read, the verifier and, for the oracle
tables, `tools/kernel_oracle.py` and the Python version. The key is of file content, which is coarser
than code: a comment-only edit of the package reruns all seven. The program checks the two
assumptions behind it: the package imports only `moonbitlang/core/...` (otherwise no kernel unit is
reused) and `tools/kernel_oracle.py` imports only the standard library (otherwise that unit runs).

A reused kernel stage is printed as `REUSED` with the commit it ran on and is not executed. A stage
that ran is recorded when it passes and when its files are still those of the key (a stage runs for
minutes: an edit meanwhile is reported as "passed but not recorded"). Each reusable stage is rerun
with probability 2 %, drawn per stage (the "at least one" rule of the TestFloat units would rerun a
stage on every run with only seven units); the seed is printed, and a sampled stage that fails
although its key is recorded as passing is a defect of the system (status 70). `just verify binary`
runs the stages this way; `--full-kernel` runs them in full.

### The stages of the interval and GDA gates

`just verify interval` and `just verify decimal_gda` run three whole stages as units, with the same
ledger, `REUSED` lines, 2 % sampling and exit status 70 as the kernel stages. Two are `moon test`
stages (the reverse trigonometric reference tests of `interval`, and the package tests of
`decimal_gda`): the key is the content of the packages and of everything they import inside the two
modules, read from `moon.pkg`, with the module files, the command, the build commands of `moon test
--dry-run`, the toolchain and the verifier. A package whose closure imports the file system, the
environment or async is not keyed, because a test that cannot import them cannot read a data file at
run time; and a `moon test` run that selects no test, or a package that is not found, fails instead
of passing. The third is a Python stage (the oracle checks of the interval gate, about two minutes):
its key is a declared set of files and directories written in `tools/stage_units.py`, chosen from an
audit of one run and rounded up to whole directories, with the `sys.version` of the interpreter of the
stage command (asked of that interpreter, not taken from the verifier) and the directory of the audit
hook, which is an input of every unit. What a run happened to open is not a key, so every real run of the stage executes under an audit
hook: the process of the stage reports what it opens and lists, and a read of anything below the
repository outside the declared set fails the stage with exit status 70 and the path: the declaration
cannot go stale silently. A path with a `.git` or `__pycache__` part is left out of the key of a
declared directory, so a read of one is undeclared too, unless the unit declares that very file. Every
such run also gets an empty directory of its own as the cache of compiled modules
(`PYTHONPYCACHEPREFIX`), so that a compiled module of the tree, stale or made by hand, cannot run in
place of a source file that the key covers.

A pass of a Python stage is recorded only when the log of the hook shows that the audit saw the whole
run. The log must hold exactly one start line, the one of the stage's own process, and no launch
event: nothing that starts or replaces a process (`subprocess.Popen`, `os.posix_spawn`, `os.exec*`,
`os.spawn*`, `os.system`, `os.fork`, `os.forkpty`, `pty.spawn`, `os.startfile`, `webbrowser.open`) and
no `ctypes` event. A Python process started with `-I`, `-E` or `-S` writes no start line; a second
start line without a launch event is another Python process, for example a `multiprocessing` child.
A stage that starts children through one of these events is therefore never recorded, whatever the
children read; if a later unit needs children, that is a design of its own. Besides, the start line has the version of the key, the
stage read no compiled module from the tree, and it read or listed nothing outside the repository
except the standard library of the interpreter (not its site-packages), the directories that are
entries of the interpreter's own `sys.path` at start-up (the import system looking for a module;
opening a file below one of them is still an outside read), the cache directory of the run, and what
the run created before reading it (a file that did not exist and that an open with `O_CREAT` creates,
whatever the mode, as `tempfile` does; a directory that `os.mkdir` creates, and everything below it).
A file that existed is not the run's own, with any mode. A read or a listing outside the repository that the key does
not cover (a cache file, a toolchain file, a shared library, an installed package, a directory of
another tool) does not fail the stage; the stage passes, `verify` says why it was not recorded, and
the stage runs again next time. A stage that imports an installed package is therefore never recorded.

The audit is a check against an honest mistake, not a sandbox. It finds an input that the author of a
stage forgot to declare, through the events that CPython reports. A stage written to deceive it, for
example by starting a process through a private or foreign-function interface that raises no launch
event (`_posixsubprocess.fork_exec`, `ctypes`), is outside what it claims. One such route is not a
deception but a configuration: `multiprocessing` with the `spawn` method after `set_executable` of a
program that is not Python starts the child through `_posixsubprocess.fork_exec`, raises no launch
event and writes no second start line, so that run is recorded although a child ran. The stage scripts are code
of the repository and are reviewed as such, and the 2 % reruns of the verifier exist for what a key
misses. A `ctypes` event, which is a call into a foreign library, is still refused.

What the audit still cannot see: `os.stat`, `os.path.exists`, `os.path.isfile`, `os.path.getsize`,
`os.path.getmtime`, `os.access` and `os.readlink` raise no audit event, so a stage whose result
depends on whether a file exists, how large or how old it is, or where a link points, without opening
it, is not seen (only a directory that the key lists as a whole covers a new file in it); a stage whose
result depends only on whether an installed package exists is not seen either, because the import
system's own listing of the package directories is not counted; environment variables, the clock,
random numbers and sockets are not files and the hook does not log them; and a process started
through an interface that raises no launch event is not seen. The oracle checks of the interval gate
need the ITF1788 corpus, which the continuous-integration runner does not have, so the real unit is
not run there; two tests that run on every interpreter show that a stage that reads only declared
files, and a stage that imports only standard-library modules, are recorded.

The stages that stay full are listed by `verify`: the interval corpus (it needs the
split of the interval frontend into arms), the differential stage of the interval gate, and the three
short stages of the GDA gate (the frontend tests and the two decTest corpora, about seven seconds).

### What it does not cover

The decimal gate (`just gate decimal` runs generated `moon test` fixtures on native, Wasm, Wasm-GC
and JavaScript), the elementary gate, the other `moon test` stages (units per test block), the other
targets, and the full stages listed above are outside this version.

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

1. align `library/moon.mod`, `library/README.md`, the manual and `library/CHANGELOG.md`;
2. run `just docs`, `lunadoc check`, and inspect generated interface
   differences;
3. run `just pr` while iterating;
4. run `just ci` on the release candidate;
5. publish through the repository's `publish.yml` GitHub Actions workflow.

Local `moon publish` is not the Luna-Flow release path, because the
organization's credentials are supplied by the workflow.

## Conformance checklist

One line per row of the clause traceability tables of the conformance pages
([binary](./conformance/binary.md#clause-traceability),
[IEEE decimal](./conformance/decimal.md#clause-traceability),
[GDA](./conformance/decimal_gda.md#clause-traceability),
[interval](./conformance/interval.md#clause-traceability)). A checked box is
a `conforming` row; an unchecked box names its state (`partial`,
`not implemented`, `not applicable`) and carries the clause level in brackets:
`required` (the standard says "shall"), `recommended` ("should") or `optional`.
The counts separate gaps in required clauses from gaps in recommended or
optional ones. The block is generated by
`tools/conformance_checklist.py` and `just docs` fails when it is stale.

<!-- conformance-checklist-start -->
| Standard | Rows | Conforming | Partial | Not implemented | Not applicable | Required gaps | Recommended or optional gaps |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| IEEE 754-2019: binary | 28 | 22 | 1 | 5 | 0 | 0 | 6 |
| IEEE 754-2019: decimal | 32 | 28 | 0 | 3 | 1 | 0 | 3 |
| General Decimal Arithmetic 1.70: decimal_gda | 20 | 20 | 0 | 0 | 0 | 0 | 0 |
| IEEE 1788-2015: interval | 18 | 14 | 1 | 3 | 0 | 1 | 3 |

**IEEE 754-2019: binary**

- [x] §3.3–§3.6 binary16/32/64/128 interchange formats [required]
- [x] §3.7 extendable precisions [recommended]
- [x] §4.3 rounding-direction attributes [required]
- [x] §5.3.1 addition, subtraction, multiplication, division, squareRoot [required]
- [x] §5.3.1 fusedMultiplyAdd [required]
- [x] §5.3.1 remainder [required]
- [x] §5.3.1, §5.9 roundToIntegral (five directions, exact) [required]
- [x] §5.3.1 nextUp, nextDown [required]
- [x] §5.3.1 scaleB, logB [required]
- [x] §5.4.1 convertFromInt [required]
- [x] §5.4.1, §5.8 convertToInteger (exact and inexact) [required]
- [x] §5.4.2 convertFormat [required]
- [x] §5.5 copy, negate, abs, copySign [required]
- [x] §5.6, §5.11 comparison predicates, quiet and signaling [required]
- [x] §5.7 class and sign predicates [required]
- [x] §5.10 totalOrder, totalOrderMag [required]
- [x] §5.12 decimal character conversion, both directions [required]
- [x] §5.12 hexadecimal character conversion [required]
- [x] §6.1–§6.3 infinities, NaNs, sign bit [required]
- [x] §7.2–§7.6 exceptions and default handling [required]
- [x] §7.5 tininess detection [required]
- [ ] §8 alternate exception handling [recommended] (not implemented)
- [x] §9.2 recommended mathematical functions [recommended]
- [ ] §9.3 dynamic mode operations [recommended] (not implemented)
- [ ] §9.4 reduction operations [recommended] (not implemented)
- [ ] §9.5 augmented arithmetic [recommended] (not implemented)
- [ ] §9.6 minimum, maximum and magnitude variants [recommended] (not implemented)
- [ ] §9.7 NaN payload operations [recommended] (partial)

**IEEE 754-2019: decimal**

- [x] §3.5 decimal32/64/128 interchange, DPD and BID [required]
- [x] §3.7 extendable precisions [recommended]
- [x] §4.3 rounding-direction attributes [required]
- [x] §5.2 preferred exponents [required]
- [x] §5.3.1 addition, subtraction, multiplication, division, squareRoot [required]
- [x] §5.3.1 fusedMultiplyAdd [required]
- [x] §5.3.1 remainder [required]
- [x] §5.3.1 roundToIntegral (all five, exact) [required]
- [x] §5.3.1 nextUp, nextDown [required]
- [x] §5.3.1 scaleB, logB [required]
- [x] §5.3.2 quantize [required]
- [x] §5.3.2 quantum [recommended]
- [x] §5.7.3 sameQuantum [required]
- [x] §5.4.1 convertFromInt [required]
- [x] §5.4.1, §5.8 convertToInteger (exact and inexact) [required]
- [x] §5.4.2 convertFormat [required]
- [x] §5.5 copy, negate, abs, copySign [required]
- [x] §5.6, §5.11 comparison, quiet and signaling [required]
- [x] §5.7 class, isCanonical, radix [required]
- [x] §5.10 totalOrder, totalOrderMag [required]
- [x] §5.12 decimal character conversion (decimal to decimal) [required]
- [x] §6.1–§6.3 infinities, NaNs, sign bit [required]
- [x] §7.2–§7.4, §7.6 invalid operation, division by zero, overflow, inexact [required]
- [x] §7.5 underflow and tininess [required]
- [ ] §8 alternate exception handling [recommended] (not implemented)
- [x] §9.2 recommended mathematical functions [recommended]
- [x] §9.2.2 preferred exponents of pow and pown [recommended]
- [ ] §9.3 dynamic mode operations [recommended] (not implemented)
- [ ] §9.4 reduction operations [recommended] (not implemented)
- [ ] §9.5 augmented arithmetic [recommended] (not applicable)
- [x] §9.6 minimum and maximum, eight variants [recommended]
- [x] §9.7 NaN payload operations [recommended]

**General Decimal Arithmetic 1.70: decimal_gda**

- [x] abs, minus, plus [required]
- [x] add, subtract, multiply [required]
- [x] divide, divide-integer, remainder, remainder-near [required]
- [x] fused-multiply-add [required]
- [x] square-root [required]
- [x] power [required]
- [x] exp, ln, log10 [required]
- [x] compare, compare-signal, compare-total, compare-total-mag [required]
- [x] max, max-magnitude, min, min-magnitude [required]
- [x] next-minus, next-plus, next-toward [required]
- [x] quantize, rescale, same-quantum, reduce, trim [required]
- [x] round-to-integral-exact, round-to-integral-value [required]
- [x] scaleb, logb, rotate, shift [required]
- [x] and, or, xor, invert [required]
- [x] class, copy, copy-abs, copy-negate, copy-sign [required]
- [x] to-number, to-scientific-string, to-engineering-string [required]
- [x] canonical [required]
- [x] context: precision, rounding, clamp, exponent limits [required]
- [x] status flags and traps (Appendix and Exceptional conditions) [required]
- [x] subset arithmetic (Appendix A) [required]

**IEEE 1788-2015: interval**

- [x] §4.2 set-based interval arithmetic flavor [required]
- [ ] §4.2.2 compressed decorated interval arithmetic [optional] (not implemented)
- [x] §9.1, §10.5.3 forward-mode arithmetic and elementary functions [required]
- [x] §10.5.4 reverse-mode elementary functions [required]
- [x] §10.5.5, §12.12.3 two-output division [required]
- [x] §9.2, §10.5.6 cancellative addition and subtraction [required]
- [x] §9.3, §10.5.7 set operations [required]
- [x] §9.8, §10.5.8 constructors [required]
- [x] §9.4, §10.5.9 numeric functions of intervals [required]
- [x] §9.5, §10.5.10 boolean functions of intervals [required]
- [ ] §10.6.2 slope functions [recommended] (not implemented)
- [ ] §10.6.4 extended interval comparisons [recommended] (partial)
- [x] §9.6, §11 decoration system [required]
- [x] §9.7, §12.11, §12.12.7, §13.2 interval and number literals, text input [required]
- [x] §13.3 interval text output (`intervalToText`) [required]
- [x] §13.4 exact text (`intervalToExact`, `exactToInterval`) [required]
- [x] §12.10 accuracy of operations [required]
- [ ] §12.6 754-conformance of the interval types [required] (not implemented)
<!-- conformance-checklist-end -->

## Implementation-defined choices

IEEE 754-2019 and IEEE 1788-2015 leave these points to the implementation, and
IEEE 754 asks for them to be documented. Each entry names the clause that
leaves it open and the choice made. The clause tables of the
[binary](./conformance/binary.md#clause-traceability),
[IEEE decimal](./conformance/decimal.md#clause-traceability),
[GDA](./conformance/decimal_gda.md#clause-traceability) and
[interval](./conformance/interval.md#clause-traceability) conformance pages
cite them.

| Clause | Choice left open | Choice made |
| --- | --- | --- |
| IEEE 754 §7.5 | Tininess detection for binary formats | `BinaryContext` defaults to after rounding; before rounding is selectable and the TestFloat gate runs both. For decimal the standard requires before rounding and `DecimalContext` defaults to it; after rounding is an explicit non-standard option. |
| IEEE 754 §6.2 | Which NaN payload a NaN result carries | `binary`: the payload and sign of the selected NaN operand are kept and a signaling NaN is quieted. `decimal`: the first NaN operand's sign and payload, cut to its low `p` digits (`p - 1` with `clamp`, the width of the interchange payload field). |
| IEEE 754 §9.7 | Admissible payloads of `setPayload` | `decimal`: non-negative integers of at most `precision - 1` digits of the receiver; anything else gives `+0`. `binary` has no setPayload. |
| IEEE 754 §3.7 | Exponent range and precision of an extendable format | `binary`: leading-bit exponents in `[2 - 2^30, 2^30 - 1]` (`e_min = 1 - e_max`), precision at most `2^28` bits. `decimal`: `e_min` and `e_max` within ±999,999,999, precision within `1..999,999,999`. |
| IEEE 754 §4.3 | Rounding directions beyond the five required | none in `binary` and `decimal` (the GDA modes `HalfDown`, `Up`, `ZeroFiveUp` are in `decimal_gda`). |
| IEEE 754 §4.1, §9.3 | How attributes are specified | Static: a context value passed to each operation; there are no dynamic modes and no global state. |
| IEEE 754 §7 | How flags are exposed | Returned per operation (`BinaryFlags`, `DecimalFlags`) and combined by the caller; no sticky ambient flags in the IEEE packages. |
| IEEE 754 §9.2 | Accuracy of recommended functions | Correctly rounded in every rounding direction (certified enclosures refined until the rounding is unique). When the refinement budget is exhausted `try_*_ctx` returns `Err` and the plain form returns NaN; decimal contexts with a precision or an exponent bound beyond 999,999 in magnitude return `invalid_context`. |
| IEEE 754 §9.2.2 | Preferred exponent when undefined (infinite or NaN `y` in `pow`) | `decimal`: `pow(+1, y)` is the plain `1`. |
| IEEE 754 §5.12 | Character sequences accepted and produced (`binary`) | Decimal: `[+-]digits[.digits][e[+-]digits]`, `inf`, `infinity`, `nan`, `snan` (case-insensitive); output `d.ddde±x`, shortest form formatted like ECMAScript `Number#toString` with `-0` kept. Hexadecimal: `0x<hex>p<exp>`. |
| IEEE 754 §6.3 | Sign of a zero `remainder` result (`decimal`) | The sign of the dividend, kept in extended contexts. |
| IEEE 1788 §7, §4.2 | Flavor | Set-based. |
| IEEE 1788 §12.10 | Accuracy of the elementary functions | Documented per operation in the [interval accuracy table](./conformance/interval.md#accuracy-of-operations): basic arithmetic, `abs`, `minimum`, `maximum` and `pown` are tightest; certified trigonometric, arctangent and power endpoints are tightest; the other elementary functions are valid and were tightest on every ITF1788 case. When range reduction cannot be certified, `sin` and `cos` return `[-1, 1]` and `tan` returns Entire. |
| IEEE 1788 §12.5 | Interval types | Inf-sup intervals with `Binary` endpoints of any precision (binary32 and binary64 named formats); no mid-rad type. |
| General Decimal Arithmetic | Exponent limit | ±999,999,999 and precision up to 999,999,999, the limits of decNumber; the specification itself only requires a limit above `5 × mlength`. |

## Known gaps and deviations

A gap is listed here when the standard asks for something the package does
not provide or provides differently. Each item links the issue that tracks it
or the page that documents the decision.

| Standard | Gap | Tracking |
| --- | --- | --- |
| IEEE 754-2019 §7.5 | `decimal` offers after-rounding tininess as a non-standard option (the default is before rounding, as §7.5 requires) | none; closed by issue [#217](https://github.com/Luna-Flow/floating/issues/217) |
| IEEE 754-2019 §8 | No alternate exception handling | by design (flags are values) |
| IEEE 754-2019 §9.3 | No dynamic mode operations in the core packages (contexts are explicit values) | by design; optional wrapper package: [#247](https://github.com/Luna-Flow/floating/issues/247) |
| IEEE 754-2019 §9.4, §9.6 | No reduction operations; `binary` has no minimum/maximum family | [#237](https://github.com/Luna-Flow/floating/issues/237), [#238](https://github.com/Luna-Flow/floating/issues/238), [#240](https://github.com/Luna-Flow/floating/issues/240) |
| IEEE 754-2019 §9.5 | No augmented arithmetic for `binary` | [#239](https://github.com/Luna-Flow/floating/issues/239) |
| IEEE 754-2019 §5.3.2 | decNumber folds a zero `quantize` result above `e_max - p + 1` down; `decimal` does too (every result is a member of the format) | [#234](https://github.com/Luna-Flow/floating/issues/234) |
| IEEE 754-2019 §3.7 | The implementation exponent range is one binade above MPFR's at both ends | documented in `testdata/binary/README.md` |
| IEEE 1788-2015 §10.6.2 | No slope functions | [#242](https://github.com/Luna-Flow/floating/issues/242) |
| Public API | The clause to API mapping may change when the public API is narrowed | issue [#22](https://github.com/Luna-Flow/floating/issues/22); the whole roadmap is [#245](https://github.com/Luna-Flow/floating/issues/245) |
