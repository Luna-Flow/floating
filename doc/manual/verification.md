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
  square-root data, 2,088 hash-pinned witnesses covering 29 elementary
  operations at binary32/64/128 precision under all six `BinaryRoundingMode`
  values, and the decimal character conversions of IEEE 754-2019 §5.12:
  1,716 `mpfr_strtofr` witnesses (decimal text to binary at 11 to 200 bits,
  including exact halfway points and the exponent limits) and 3,300
  `mpfr_get_str` witnesses (fixed digit counts, exact ties and the shortest
  round-trip digit count).
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
binary smoke, for example, has 7,467 rows (240 TestFloat vectors, 3
square-root witnesses, 120 integer-power witnesses, 2,088 elementary witnesses,
1,716 `strtofr` witnesses and 3,300 decimal output witnesses).

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

## Conformance checklist

One line per row of the clause traceability tables of the conformance pages
([binary](./conformance/bin_float.md#clause-traceability),
[IEEE decimal](./conformance/decimal.md#clause-traceability),
[GDA](./conformance/decimal_gda.md#clause-traceability),
[interval](./conformance/ball_float.md#clause-traceability)). A checked box is
a `conforming` row; an unchecked box names its state (`partial`,
`not implemented`, `not applicable`) and carries the clause level in brackets:
`required` (the standard says "shall"), `recommended` ("should") or `optional`.
The counts separate gaps in required clauses from gaps in recommended or
optional ones. The block is generated by
`tools/conformance_checklist.py` and `just docs` fails when it is stale.

<!-- conformance-checklist-start -->
| Standard | Rows | Conforming | Partial | Not implemented | Not applicable | Required gaps | Recommended or optional gaps |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| IEEE 754-2019: bin_float | 28 | 18 | 5 | 5 | 0 | 3 | 7 |
| IEEE 754-2019: decimal | 30 | 22 | 4 | 3 | 1 | 3 | 4 |
| General Decimal Arithmetic 1.70: decimal_gda | 20 | 19 | 1 | 0 | 0 | 1 | 0 |
| IEEE 1788-2015: ball_float | 16 | 7 | 3 | 6 | 0 | 6 | 3 |

**IEEE 754-2019: bin_float**

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
- [ ] §5.4.2 convertFormat [required] (partial)
- [x] §5.5 copy, negate, abs, copySign [required]
- [x] §5.6, §5.11 comparison predicates, quiet and signaling [required]
- [ ] §5.7 class and sign predicates [required] (partial)
- [x] §5.10 totalOrder, totalOrderMag [required]
- [x] §5.12 decimal character conversion, both directions [required]
- [ ] §5.12 hexadecimal character conversion [required] (partial)
- [x] §6.1–§6.3 infinities, NaNs, sign bit [required]
- [x] §7.2–§7.6 exceptions and default handling [required]
- [x] §7.5 tininess detection [required]
- [ ] §8 alternate exception handling [recommended] (not implemented)
- [ ] §9.2 recommended mathematical functions [recommended] (partial)
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
- [x] §5.3.2 quantize, quantum, sameQuantum [required]
- [x] §5.4.1 convertFromInt [required]
- [ ] §5.4.1 convertToInteger [required] (partial)
- [ ] §5.4.2 convertFormat [required] (partial)
- [x] §5.5 copy, negate, abs, copySign [required]
- [x] §5.6, §5.11 comparison, quiet and signaling [required]
- [x] §5.7 class, isCanonical, radix [required]
- [ ] §5.10 totalOrder, totalOrderMag [required] (partial)
- [x] §5.12 decimal character conversion (decimal to decimal) [required]
- [x] §6.1–§6.3 infinities, NaNs, sign bit [required]
- [x] §7.2–§7.4, §7.6 invalid operation, division by zero, overflow, inexact [required]
- [x] §7.5 underflow and tininess [required]
- [ ] §8 alternate exception handling [recommended] (not implemented)
- [ ] §9.2 recommended mathematical functions [recommended] (partial)
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
- [ ] subset arithmetic (Appendix A) [required] (partial)

**IEEE 1788-2015: ball_float**

- [x] §4.2 set-based interval arithmetic flavor [required]
- [ ] §4.2.2 compressed decorated interval arithmetic [optional] (not implemented)
- [x] §9.1, §10.5.3 forward-mode arithmetic and elementary functions [required]
- [ ] §10.5.4 reverse-mode elementary functions [required] (not implemented)
- [ ] §10.5.5 two-output division [required] (not implemented)
- [x] §9.2, §10.5.6 cancellative addition and subtraction [required]
- [x] §9.3, §10.5.7 set operations [required]
- [ ] §9.8, §10.5.8 constructors [required] (partial)
- [x] §9.4, §10.5.9 numeric functions of intervals [required]
- [x] §9.5, §10.5.10 boolean functions of intervals [required]
- [ ] §10.6.2 slope functions [recommended] (not implemented)
- [ ] §10.6.4 extended interval comparisons [recommended] (partial)
- [x] §9.6, §11 decoration system [required]
- [ ] §9.7, §12.11 interval and number literals [required] (not implemented)
- [ ] §12.10 accuracy of operations [required] (partial)
- [ ] §12.6 754-conformance of the interval types [required] (not implemented)
<!-- conformance-checklist-end -->

## Implementation-defined choices

IEEE 754-2019 and IEEE 1788-2015 leave these points to the implementation, and
IEEE 754 asks for them to be documented. Each entry names the clause that
leaves it open and the choice made. The clause tables of the
[binary](./conformance/bin_float.md#clause-traceability),
[IEEE decimal](./conformance/decimal.md#clause-traceability),
[GDA](./conformance/decimal_gda.md#clause-traceability) and
[interval](./conformance/ball_float.md#clause-traceability) conformance pages
cite them.

| Clause | Choice left open | Choice made |
| --- | --- | --- |
| IEEE 754 §7.5 | Tininess detection for binary formats | `BinaryContext` defaults to after rounding; before rounding is selectable and the TestFloat gate runs both. For decimal the standard requires before rounding and `DecimalContext` defaults to it; after rounding is an explicit non-standard option. |
| IEEE 754 §6.2 | Which NaN payload a NaN result carries | `bin_float`: the payload and sign of the selected NaN operand are kept and a signaling NaN is quieted. `decimal`: the first NaN operand's sign and payload, cut to its low `p` digits (`p - 1` with `clamp`, the width of the interchange payload field). |
| IEEE 754 §9.7 | Admissible payloads of `setPayload` | `decimal`: non-negative integers of at most `precision - 1` digits of the receiver; anything else gives `+0`. `bin_float` has no setPayload. |
| IEEE 754 §3.7 | Exponent range and precision of an extendable format | `bin_float`: leading-bit exponents in `[1 - 2^30, 2^30 - 1]`, precision at most `2^28` bits (one binade above MPFR at both ends). `decimal`: `e_min` and `e_max` within ±999,999,999, precision within `1..999,999,999`. |
| IEEE 754 §4.3 | Rounding directions beyond the five required | `RoundAwayFromZero` (binary); `HalfDown`, `Up`, `ZeroFiveUp` (decimal). |
| IEEE 754 §4.1, §9.3 | How attributes are specified | Static: a context value passed to each operation; there are no dynamic modes and no global state. |
| IEEE 754 §7 | How flags are exposed | Returned per operation (`BinaryFlags`, `DecimalFlags`) and combined by the caller; no sticky ambient flags in the IEEE packages. |
| IEEE 754 §9.2 | Accuracy of recommended functions | Correctly rounded in every rounding direction (certified enclosures refined until the rounding is unique). When the refinement budget is exhausted `try_*_ctx` returns `Err` and the plain form returns NaN; decimal contexts with a precision or an exponent bound beyond 999,999 in magnitude return `invalid_context`. |
| IEEE 754 §9.2.2 | Preferred exponent when undefined (infinite or NaN `y` in `pow`) | `decimal`: `pow(+1, y)` is the plain `1`. |
| IEEE 754 §5.12 | Character sequences accepted and produced (`bin_float`) | Decimal: `[+-]digits[.digits][e[+-]digits]`, `inf`, `infinity`, `nan`, `snan` (case-insensitive); output `d.ddde±x`, shortest form formatted like ECMAScript `Number#toString` with `-0` kept. Hexadecimal: `0x<hex>p<exp>`. |
| IEEE 754 §6.3 | Sign of a zero `remainder` result (`decimal`) | The sign of the dividend, kept in extended contexts. |
| IEEE 1788 §7, §4.2 | Flavor | Set-based. |
| IEEE 1788 §12.10 | Accuracy of the elementary functions | Valid (the result contains the exact image); not the tightest enclosure. When range reduction cannot be certified, `sin` and `cos` return `[-1, 1]` and `tan` returns Entire. |
| IEEE 1788 §12.5 | Interval types | Inf-sup intervals with `BinFloat` endpoints of any precision (binary32 and binary64 named formats); no mid-rad type. |
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
| IEEE 754-2019 §9.2 | Missing `rSqrt`, `compound`, `powr`, `asinPi`, `acosPi`, `atanPi`, `atan2Pi`, `exp2m1`, `exp10m1`, `log2p1`, `log10p1` in `bin_float` and `decimal` | [#235](https://github.com/Luna-Flow/floating/issues/235), [#236](https://github.com/Luna-Flow/floating/issues/236) |
| IEEE 754-2019 §9.4, §9.6 | No reduction operations; `bin_float` has no minimum/maximum family | [#237](https://github.com/Luna-Flow/floating/issues/237), [#238](https://github.com/Luna-Flow/floating/issues/238), [#240](https://github.com/Luna-Flow/floating/issues/240) |
| IEEE 754-2019 §9.5 | No augmented arithmetic for `bin_float` | [#239](https://github.com/Luna-Flow/floating/issues/239) |
| IEEE 754-2019 §5.4.1 | `decimal` has no convertToInteger | [#226](https://github.com/Luna-Flow/floating/issues/226) |
| IEEE 754-2019 §5.3.2 | A zero `quantize` result above `e_max - p + 1` under `clamp` is not folded down or flagged `clamped` (General Decimal Arithmetic does) | decided: opt-in GDA-style fold, default unchanged; [#234](https://github.com/Luna-Flow/floating/issues/234); see the pull request of issue #187 |
| IEEE 754-2019 §3.7 | The implementation exponent range is one binade above MPFR's at both ends | documented in `testdata/bin_float/README.md` |
| IEEE 1788-2015 §10.5.4, §9.7, §12.11 | No reverse-mode operations and no interval literals (text input and output) | [#230](https://github.com/Luna-Flow/floating/issues/230) (reverse mode), [#21](https://github.com/Luna-Flow/floating/issues/21) (text) |
| IEEE 1788-2015 §10.5.5, §10.6.2 | No two-output division, no slope functions | [#231](https://github.com/Luna-Flow/floating/issues/231), [#242](https://github.com/Luna-Flow/floating/issues/242) |
| Public API | The clause to API mapping may change when the public API is narrowed | issue [#22](https://github.com/Luna-Flow/floating/issues/22); the whole roadmap is [#245](https://github.com/Luna-Flow/floating/issues/245) |
