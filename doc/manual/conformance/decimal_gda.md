# decimal_gda conformance

The implementation target is General Decimal Arithmetic Specification 1.70;
the pinned executable corpus is the General Decimal Arithmetic testcase suite
2.62.

## Published result

The pinned official corpus passes 64,986/64,986 legal executable scalar rows with zero failed, unsupported, or legacy rows. The remaining 141 rows are `#` placeholder or non-scalar invalid inputs and are reported as diagnostics outside the legal denominator.

## Clause traceability

General Decimal Arithmetic Specification 1.70 for `decimal_gda`, one row per operation or conversion of the specification. The decTest files are those of the pinned corpus (`testdata/decimal/corpora.json`). Status is `conforming` when the operation exists and the cited evidence exercises it, `partial` when part of the clause is missing or evidence is thin (the cell says which), `not implemented` and `not applicable` otherwise. Evidence without a corpus name is a unit test in the repository; "no external corpus" marks operations that no independent oracle checks.

| Operation | API | Evidence | Status |
| --- | --- | --- | --- |
| abs, minus, plus | `abs_ctx`, `minus_ctx`, `plus_ctx` | `abs.decTest`, `minus.decTest`, `plus.decTest` | conforming |
| add, subtract, multiply | `add_ctx`, `sub_ctx`, `mul_ctx` | `add.decTest`, `subtract.decTest`, `multiply.decTest` | conforming |
| divide, divide-integer, remainder, remainder-near | `div_ctx`, `divide_integer`, `remainder`, `remainder_near` | `divide.decTest`, `divideint.decTest`, `remainder.decTest`, `remaindernear.decTest` | conforming |
| fused-multiply-add | `fma_ctx` | `fma.decTest` | conforming |
| square-root | `sqrt_ctx` | `squareroot.decTest`, `powersqrt.decTest` | conforming |
| power | `power_ctx` | `power.decTest`; `src/decimal_gda/power_cohort_issue211_wbtest.mbt` | conforming; integer powers are within about 0.55 units in the last place (0.6 for negative exponents), as the specification allows |
| exp, ln, log10 | `exp_ctx`, `ln_ctx`, `log10_ctx` | `exp.decTest`, `ln.decTest`, `log10.decTest` | conforming |
| compare, compare-signal, compare-total, compare-total-mag | `compare_ctx`, `compare_signal_ctx`, `compare_total_ctx`, `compare_total_magnitude_ctx` | `compare.decTest`, `comparesig.decTest`, `comparetotal.decTest`, `comparetotmag.decTest` | conforming |
| max, max-magnitude, min, min-magnitude | `max_ctx`, `max_mag_ctx`, `min_ctx`, `min_mag_ctx` | `max.decTest`, `maxmag.decTest`, `min.decTest`, `minmag.decTest` | conforming |
| next-minus, next-plus, next-toward | `next_minus`, `next_plus`, `next_toward` | `nextminus.decTest`, `nextplus.decTest`, `nexttoward.decTest` | conforming |
| quantize, rescale, same-quantum, reduce, trim | `quantize`, `rescale`, `same_quantum`, `reduce_ctx`, `trim` | `quantize.decTest`, `rescale.decTest`, `samequantum.decTest`, `reduce.decTest`, `trim.decTest` | conforming |
| round-to-integral-exact, round-to-integral-value | `to_integral_exact`, `to_integral_value` | `tointegralx.decTest`, `tointegral.decTest` | conforming |
| scaleb, logb, rotate, shift | `scaleb_ctx`, `logb_ctx`, `rotate_ctx`, `shift_ctx` | `scaleb.decTest`, `logb.decTest`, `rotate.decTest`, `shift.decTest` | conforming |
| and, or, xor, invert | `logical_and`, `logical_or`, `logical_xor`, `logical_invert` | `and.decTest`, `or.decTest`, `xor.decTest`, `invert.decTest` | conforming |
| class, copy, copy-abs, copy-negate, copy-sign | `classify`, `copy`, `copy_abs`, `copy_negate`, `copy_sign` | `class.decTest`, `copy.decTest`, `copyabs.decTest`, `copynegate.decTest`, `copysign.decTest` | conforming |
| to-number, to-scientific-string, to-engineering-string | `from_string_ctx`, `parse`, `to_sci_string`, `to_eng_string` | `base.decTest`; `src/decimal_gda/parse_format_issue180_wbtest.mbt` | conforming |
| canonical | `canonical`, `is_canonical` | no decTest file; `src/consistency/api_audit_wbtest.mbt` | conforming |
| context: precision, rounding, clamp, exponent limits | `GdaContext`, `DecimalContext` | `clamp.decTest`, `rounding.decTest`, `inexact.decTest`, `randoms.decTest` | conforming |
| status flags and traps (Appendix and Exceptional conditions) | `GdaOutcome`, `GdaContext::with_traps` | every decTest row checks the flag set; trap enablement is covered by the runner's directive handling | conforming |
| subset arithmetic (Appendix A) | `extended = false` contexts | `src/decimal_gda/` white-box tests; no decTest subset run | partial |

## Legacy corpus

The pinned `official0` corpus passes 16,124/16,124 legal executable rows with zero failures. It is retained for historical compatibility checks, not as the definition of the current surface.

## State semantics

Each operation returns a `GdaOutcome` containing the defined result, flags raised by that operation, and the next context with accumulated sticky status. Enabling a trap changes the outcome variant but does not erase the defined result.

The arithmetic `ParseChecked` adapter applies its mapped DecimalContext to
GDA parsing but returns only a value or syntax error. Use the `decimal_gda::parse`
API with `GdaContext` when sticky status and traps must remain observable.

The white-box coverage includes zero `divide_integer` results in clamped
extended contexts for both finite and infinite divisors, checking the folded
exponent and the `Clamped` condition.

## Runner model

Documents are parsed once, directive state is snapshotted per case, and
deterministic shards execute disjoint case positions through the public
`GdaContext`/`GdaOutcome` operation surface. Executable, diagnostic,
unsupported, legacy, passed, and failed counts remain separate.

## Boundaries

The claim covers legal scalar rows in the pinned corpora. Placeholder/non-scalar invalid rows, future directives, unpinned revisions, and an unbounded universe of decimal strings remain outside it.

## Known deviations outside the corpus

A passing corpus is a finite claim. Review of the implementation found these
behaviours, none of which has a pinned row:

- Integer `power` is accurate to about 0.55 units in the last place (0.6 for
  negative exponents), not correctly rounded, as the specification allows.

## Isolation and native benchmark

Production dependency scans require `decimal_gda`, `decimal_gda_checked`, and
`frontend/gda_expr` to contain no IEEE `decimal` import or GDA profile bridge.
IEEE tests and its independent conformance corpus are run separately.

The quick benchmark builds only the current engine in an isolated snapshot and
runs three native samples per cell. It reports arithmetic, parser, context, and
elementary timing observations without treating performance as a conformance
requirement or comparing against a historical adapter.

## Reproduction

```bash
just conformance smoke decimal_gda
just gate decimal_gda 8
just conformance run decimal_gda --corpus official0 --strict-supported
python3 tools/run_gda_benchmark.py
```

See [the decimal data guide](../../../testdata/decimal/README.md) for manifests, filters, phases, JSON output, and failure triage.
