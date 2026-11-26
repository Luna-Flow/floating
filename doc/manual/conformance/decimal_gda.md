# decimal_gda conformance

The implementation target is General Decimal Arithmetic Specification 1.70 (GDA 1.70); the pinned
executable corpus is the General Decimal Arithmetic testcase suite 2.62. The results below hold for
the finite set of inputs in the pinned corpora and package tests; GDA 1.70 defines no conformance
clause.

## Published result

| Corpus | Scope | Result | Diagnostics |
| --- | --- | --- | --- |
| `official` | legal executable scalar rows | 64,986 / 64,986 | 141 |
| `official0` (`dectest0.zip`, Appendix A) | executable subset rows | 16,124 / 16,124 | 40 |

The pinned `official` corpus passes with zero failed, unsupported, or legacy rows. The 141 remaining
rows are `#` placeholder or non-scalar invalid inputs and are reported as diagnostics outside the
legal denominator. The pinned `official0` subset corpus excludes its 40 diagnostic rows the same way;
it is retained for historical compatibility checks, not as the definition of the current surface.

## Clause traceability

GDA 1.70 for `decimal_gda`, one row per operation or conversion of the specification. The decTest
files are those of the pinned corpus
([`testdata/decimal_gda/corpora.json`](../../../testdata/decimal_gda/corpora.json)). Status is `conforming` when the operation exists and the cited tests exercise it, `partial` when
part of the clause is missing or tests are thin (the cell says which), `not implemented` and
`not applicable` otherwise. An entry without a corpus file name is a unit test in the repository;
"no external corpus" marks operations that no independent oracle checks.

| Operation | API | Evidence | Status |
| --- | --- | --- | --- |
| abs, minus, plus | `abs`, `minus`, `plus` | `abs.decTest`, `minus.decTest`, `plus.decTest` | conforming |
| add, subtract, multiply | `add`, `subtract`, `multiply` | `add.decTest`, `subtract.decTest`, `multiply.decTest`; `library/src/decimal_gda/overflow_rounded_result_issue264_wbtest.mbt` (overflow judged on rounded sum) | conforming |
| divide, divide-integer, remainder, remainder-near | `divide`, `divide_integer`, `remainder`, `remainder_near` | `divide.decTest`, `divideint.decTest`, `remainder.decTest`, `remaindernear.decTest` | conforming |
| fused-multiply-add | `fma` | `fma.decTest`; `library/src/decimal_gda/overflow_rounded_result_issue264_wbtest.mbt` | conforming |
| square-root | `sqrt` | `squareroot.decTest`, `powersqrt.decTest` | conforming |
| power | `power` | `power.decTest`; [Operation notes](#operation-notes) | conforming; [Operation notes](#operation-notes) |
| exp, ln, log10 | `exp`, `ln`, `log10` | `exp.decTest`, `ln.decTest`, `log10.decTest` | conforming; [Operation notes](#operation-notes) |
| compare, compare-signal, compare-total, compare-total-mag | `compare`, `compare_signal`, `compare_total`, `compare_total_magnitude` | `compare.decTest`, `comparesig.decTest`, `comparetotal.decTest`, `comparetotmag.decTest` | conforming |
| max, max-magnitude, min, min-magnitude | `max`, `max_magnitude`, `min`, `min_magnitude` | `max.decTest`, `maxmag.decTest`, `min.decTest`, `minmag.decTest` | conforming |
| next-minus, next-plus, next-toward | `next_minus`, `next_plus`, `next_toward` | `nextminus.decTest`, `nextplus.decTest`, `nexttoward.decTest` | conforming |
| quantize, rescale, same-quantum, reduce, trim | `quantize`, `rescale`, `same_quantum`, `reduce`, `trim` | `quantize.decTest`, `rescale.decTest`, `samequantum.decTest`, `reduce.decTest`, `trim.decTest`; [Operation notes](#operation-notes) | conforming |
| round-to-integral-exact, round-to-integral-value | `round_to_integral_exact`, `round_to_integral_value` | `tointegralx.decTest`, `tointegral.decTest` | conforming |
| scaleb, logb, rotate, shift | `scaleb`, `logb`, `rotate`, `shift` | `scaleb.decTest`, `logb.decTest`, `rotate.decTest`, `shift.decTest` | conforming |
| and, or, xor, invert | `logical_and`, `logical_or`, `logical_xor`, `logical_invert` | `and.decTest`, `or.decTest`, `xor.decTest`, `invert.decTest` | conforming |
| class, copy, copy-abs, copy-negate, copy-sign | `class_name`, `copy`, `copy_abs`, `copy_negate`, `copy_sign` | `class.decTest`, `copy.decTest`, `copyabs.decTest`, `copynegate.decTest`, `copysign.decTest` | conforming |
| to-number, to-scientific-string, to-engineering-string | `to_number`, `Decimal::to_sci_string`, `Decimal::to_eng_string` | `base.decTest`; `library/src/decimal_gda/parse_format_issue180_wbtest.mbt` | conforming |
| canonical | `canonical`, `is_canonical` | no decTest file; `tooling/src/consistency/api_audit_wbtest.mbt` | conforming |
| context: precision, rounding, clamp, exponent limits | `GdaContext` | `clamp.decTest`, `rounding.decTest`, `inexact.decTest`, `randoms.decTest` | conforming |
| status flags and traps (Appendix and Exceptional conditions) | `GdaOutcome`, `GdaContext::with_traps` | every decTest row checks the flag set; trap enablement is covered by the runner's directive handling | conforming |
| subset arithmetic (Appendix A) | `extended = false` contexts | pinned subset corpus `dectest0.zip` (32 files, 31 with `extended: 0`) in `DECIMAL_GDA: official0 decTest`; `library/src/decimal_gda/` white-box tests | conforming for the corpus operations; [Subset arithmetic](#subset-arithmetic-and-operations-appendix-a-does-not-name) |

## Operation notes

GDA 1.70, page 35 (`power`) allows inexact results to be up to 1 ulp in error; integer powers in
`decimal_gda` are within about 0.55 units in the last place (0.6 for negative exponents). Ten unit
test files cover `power` edge cases:

| Test file | Coverage |
| --- | --- |
| `library/src/decimal_gda/power_cohort_issue211_wbtest.mbt` | cohort of powers |
| `library/src/decimal_gda/power_overflow_sign_issue265_wbtest.mbt` | sign of an overflowing power |
| `library/src/decimal_gda/power_inexact_trailing_zeros_issue266_wbtest.mbt` | inexact power keeping precision digits |
| `library/src/decimal_gda/power_reciprocal_cohort_issue284_wbtest.mbt` | cohort of exact negative powers |
| `library/src/decimal_gda/power_spurious_clamped_issue267_wbtest.mbt` | `Clamped` of integer powers |
| `library/src/decimal_gda/power_subnormal_underflow_issue268_wbtest.mbt` | `Subnormal` and `Underflow` of integer powers near $E_{\min}$ |
| `library/src/decimal_gda/power_subnormal_underflow_issue342_wbtest.mbt` | `Underflow` of an inexact subnormal integer power |
| `library/src/decimal_gda/power_ten_clamp_issue287_wbtest.mbt` | clamp fold-down of a power of ten |
| `library/src/decimal_gda/power_inexact_clamped_issue305_wbtest.mbt` | absence of `Clamped` on an inexact result |
| `library/src/decimal_gda/power_one_inexact_issue306_wbtest.mbt` | inexactness of 1 to a non-integer exponent |

For `exp`, `ln`, and `log10`, GDA 1.70, pages 30 and 31 allow inexact results to be up to 1 ulp in
error; the library returns the correctly rounded result in both extended and subset arithmetic. A
context with precision or an exponent limit above 999,999 answers `Invalid_context`. This is a
deliberate implementation limit (decNumber's `DEC_MAX_MATH`), required by decTest rows `powx4001` to
`powx4005`, `expx901` to `expx906`, and similar rows, and permitted by the Invalid context
condition of GDA 1.70, page 52 (Exceptional conditions), not a rule of the operation text.

For `quantize`, `library/src/decimal_gda/quantize_zero_clamp_issue419_wbtest.mbt` checks that a
zero result above `e_max - precision + 1` under `clamp` is folded down with `Clamped`.

## Subset arithmetic and operations Appendix A does not name

In a subset context (`extended=false`), the result of every operation of `decimal_gda` that takes a
context obeys the three result rules of GDA 1.70, page 55 (Appendix A, The X3.274 subset), which
the page states for any operation:

- a result whose coefficient is zero has sign 0 and, unless the operation is `quantize`, exponent 0;
- a subnormal result is not permitted: it is an Underflow, and the result is the zero of the subset,
  with `Underflow`, `Subnormal`, `Inexact`, and `Rounded` as `multiply` always gives (an operation
  that raised `Clamped` keeps it, and `exp` raises it as well); `next_plus` and `next_minus` are the
  exception, setting no flag for a numeric operand on GDA 1.70, page 34 (`next-plus` and
  `next-minus`) and returning `0` without flags, while `next_toward` raises the four flags, as the
  sum with an infinitesimal of page 35 (`next-toward`) does;
- after the rounding of its result (unless the operation is `quantize`), a positive exponent is
  reduced to 0 when the coefficient then has at most precision digits.

The library applies these rules in one step, the last of every operation in a subset context; an
extended context does not reach it. In a subset context, `add` and `subtract` follow all three
rules and refuse subnormal results: `add(1E-9, -1E-99)` at precision 3, `round-down`, with
$E_{\min}$ equal to -9, returns `0`. The copy operations (`copy`, `copy_abs`, `copy_negate`,
`copy_sign`) take no context and are outside the rules, so `copy_negate(0)` is `-0`. The one
exception is `quantize`, and with it `rescale` (the former name of `quantize`, GDA 1.70, page 37,
`quantize`, note 2): they keep the exponent of a zero and a positive exponent, while a zero still
has sign 0. Appendix A does not name `reduce`, `rescale`, `scaleb`, `shift`, `rotate`, `remainder`,
`remainder_near`, `round_to_integral_exact`, `round_to_integral_value`, or `next_toward`; the rules
say "after any operation", so they apply to these operations too. String parsing and `to_number`
keep a positive exponent, as page 55 states the rule for operations; a zero they read is `+0` with
exponent 0.

The operations `reduce`, `round_to_integral_value`, `round_to_integral_exact`, and `sqrt` obey the
rules (`reduce(1200)` is `1200`, `round_to_integral_value(1.2E+3)` is `1200`, and `sqrt(1E+2)` is
`10`). In the pinned subset corpus (`dectest0`), 64 rows expect decNumber's result for them and are
recorded as deviations ([Deviations of the corpus](#deviations-of-the-corpus)). The corpus has no
row in a subset context for `scaleb`, `shift`, `rotate`, `next_toward`, or
`round_to_integral_exact`: their results rest on the text of page 55 alone.

Every operation that takes a context also rounds an operand longer than the precision first and
raises `LostDigits` when non-zero digits are discarded (GDA 1.70, page 56, Appendix A, "Operation
differences", first item). That includes `apply`, `reduce`, `round_to_integral_exact`,
`round_to_integral_value`, `next_plus`, `next_minus`, `next_toward`, `scaleb`, `shift`, and
`rotate`: at precision 9, `next_toward(1234567891, 0)` is `1.23456788E+9` with `LostDigits` (as in
decNumber 3.68), and `shift(1234567891, 0)` is `1.23456789E+9`. decNumber 3.68 does not round the
operand of `shift` and `rotate`, and for `next_toward` it gives other results when the operand or target is longer than the precision; 40
rows of the sampled matrix of the decNumber comparison record these differences in the tests, and
the library follows the text.

Where a second operand exists, it is rounded too, as in `add`. Both `compare_total` and `compare_total_magnitude` round
their operands like `compare`; `compare_total_magnitude` drops the sign first because GDA 1.70,
page 43 (`compare-total-magnitude`) defines it through `copy-abs`, so in `Floor` and `Ceiling`
`compare_total_magnitude(-12, 1E+1)` at precision 1 rounds 12, not -12. The logical operations,
`logb`, and the classifications are not arithmetic on the value and keep their operands.

What Appendix A defines differently on GDA 1.70, pages 56 and 57 (The X3.274 subset) is unchanged:
rounding the operands first, the trailing zeros that `divide` and `power` remove, and the power
rules of pages 56 and 57.

A comparison with decNumber 3.68 (built with `DECSUBSET=1`) over 149,338 calls of 31 operations in
a subset context and in an extended context found zero differences in an extended context. In a
subset context, decNumber 3.68 gives results that the text of page 55 does not allow. The library
gives the text, and the recorded differences are (precision 9, `round-half-up`):

| Operation | Rule | Call | Library | decNumber 3.68 |
| --- | --- | --- | --- | --- |
| `add`, `subtract` | positive exponent | `add(1.2E+3, 1E+2)` | `1300` | `1.3E+3` |
| `scaleb` | positive exponent, zero | `scaleb(12, 2)`, `scaleb(0, 2)` | `1200`, `0` | `1.2E+3`, `0E+2` |
| `shift`, `rotate` | positive exponent, zero, subnormal | `shift(1.2E+3, 1)`, `shift(1.2E+3, -2)`, `rotate(1.2E+3, 0)` | `12000`, `0`, `1200` | `1.20E+4`, `0E+2`, `1.2E+3` |
| `reduce` | positive exponent | `reduce(1200)` | `1200` | `1.2E+3` |
| `round_to_integral_value`, `round_to_integral_exact` | positive exponent | `round_to_integral_value(1.2E+3)` | `1200` | `1.2E+3` |
| `sqrt` | positive exponent | `sqrt(1E+2)` | `10` | `1E+1` |
| `next_toward` | positive exponent | `next_toward(1.2E+3, 1200)` | `1200` | `1.2E+3` |
| `power` | zero | `power(-0, 3)` | `0` | `-0` |
| `shift`, `rotate`, `next_toward` | operand longer than the precision (page 56) | `rotate(123456789123, 0)` at precision 9, `round-ceiling` | `1.23456790E+11` with `LostDigits` | `123456789123` |
| `quantize`, `rescale` | second operand longer than the precision (page 56) | `quantize(0, 12)` at precision 1, `round-half-up` | `0E+1` with `LostDigits` | `0` |

In a subset context, the second operand of `quantize` is rounded to precision digits before use like
every operand (GDA 1.70, page 56, Appendix A, "Operation differences", first item), and the exponent
of the quantum is the exponent of the rounded operand: `quantize(0, 12)` at precision 1 is `0E+1`,
and `quantize(0, 96)` is `0E+2` because 96 rounds to `1E+2`. The second operand of `rescale` (GDA
1.70, page 37, `quantize`, note 2) is an operand with a coefficient too: it is rounded first, and
the rounded integer is the power of ten of the quantum, so `rescale(0, 12)` at precision 1 is
`0E+10`. The first operand is rounded by the rule above, and an extended context uses the second
operand as it stands (GDA 1.70, page 36, `quantize`). decNumber 3.68 (`DECSUBSET=1`) takes the
quantum from the unrounded operand and gives `0` and `0E+12`. In a comparison with decNumber 3.68
over 127,296 calls of the two operations, the library gives the same value and flags in all 63,648
extended calls. In a subset context, the rule changes the result in 7,908 of the 63,648 calls, and
every changed result is the one decNumber 3.68 gives for the rounded operand; the 12 rows of the
sampled matrix of the comparison that differ by it are recorded in the tests. The corpus has no row for `quantize` in this case; its 3 rows for `rescale`
are recorded as deviations ([Deviations of the corpus](#deviations-of-the-corpus)).

As a consequence of these rules, `reduce(1200)` is `1200` (integers remain unshortened),
`scaleb(12, 2)` is `1200`, and a zero of sign 1 no longer exists as a result in a subset context, so
`power(-0, 3)` is `+0`. Other differences from decNumber 3.68 remain in a subset context and are not
caused by these rules: contexts of precision 1, and the sign of a zero operand that decNumber reads
as `+0`. The comparison records what the library does; the API page lists what a zero and a
positive exponent become in [subset arithmetic](../api/decimal_gda.md#gdacontextnew-gdacontexttry_new).

## decTest rows behind statements of the API page

The [API page](../api/decimal_gda.md) states these rules without naming the rows of the corpus that
check them.

| Statement of the API page | decTest rows |
| --- | --- |
| `exp`, `ln`, `log10` and `power` with a non-integer exponent accept only a context within the [implementation limit](../api/decimal_gda.md#implementation-limit-of-exp-ln-log10-and-power) 999,999 | `power.decTest` rows `powx4001` to `powx4005`; `exp.decTest` rows `expx901` to `expx906`; `ln.decTest` rows `lnx901` to `lnx906`; `log10.decTest` rows `logx901` to `logx906` |
| `exp(-Infinity)` under a context beyond that limit is `Invalid_context` | row `expx901` |
| `pow_int_checked` returns `Err(unsupported)` for a positive exponent above 999,999,999 under a context without exponent bounds within $\pm 999\,999$ | rows `powx1183` and `powx1184` |
| the official decTest files use the parameters `clamp` and `extended` | `clamp:` in 30,649 rows; `extended: 0` in all 16,162 rows of `dectest0` |
| a NaN payload wider than the interchange format keeps its low digits, and no flag is raised | the decTest interchange rows have no payload wider than their format |

The first row's `expx901` to `expx906`, `lnx901` to `lnx906`, and `logx901` to `logx906` stand in
a section that decTest labels decNumber's restricted range for the mathematical functions.

## State semantics

Each operation returns a `GdaOutcome` containing the defined result, flags raised by that operation,
and the next context with its accumulated flags. Enabling a trap changes the outcome variant without
erasing the defined result.

The arithmetic `ParseChecked` adapter applies its mapped engine context to GDA parsing but returns
only a value or syntax error. Use the `decimal_gda::to_number` API with `GdaContext` when accumulated
flags and traps must remain observable.

White-box coverage includes zero `divide_integer` results in clamped extended contexts for both
finite and infinite divisors, and checks the folded exponent and the `Clamped` condition.

## White-box tests of the fast paths

Each of the three plain-operation fast paths of the
[design page](../design/decimal_gda.md#fast-paths-that-are-proven-equivalent) is compared with the
general route by a white-box test in `library/src/decimal_gda/`.

| Fast path | Operands | Parameters |
| --- | --- | --- |
| plain sums (`add`, `subtract`) | random, 1 to 120 digits, mixed signs, cancellations and exponent gaps | ten precisions, all eight rounding algorithms, tight and wide exponent ranges, clamping, trapped signals |
| plain products and quotients (`multiply`, `divide`) | random, 1 to 120 digits; exact quotients (a product divided by one of its factors, divisors $2^a 5^b$), short divisors with repeating expansions, carries into $10^p$ | chained contexts, all eight rounding algorithms |
| plain square roots (`sqrt`) | random, 1 to 130 digits; squares; near squares ($s^2 \pm 1$, $s^2 \pm s$); the comparison is at the public level: value, every condition and the flags of the context | all eight rounding algorithms, tight and wide exponent ranges, clamping, trapped signals |

## Runner model

Documents are parsed once, directive state is snapshotted per case, and deterministic shards execute
disjoint case positions through the public `GdaContext` and `GdaOutcome` operations. Executable,
diagnostic, unsupported, legacy, passed, and failed counts remain separate.

## Boundaries

The claim covers legal scalar rows in the pinned corpora (`testdata/decimal_gda/corpora.json`).
Placeholder and non-scalar invalid rows, future directives, unpinned revisions, and an unbounded
universe of decimal strings remain outside it.

## Deviations of the corpus

The pinned corpora (`testdata/decimal_gda/corpora.json`) are decNumber's test suite. A row is
recorded in `testdata/decimal_gda/deviations.tsv` when its result token differs from the value this
library returns. There are three kinds of row.

The first kind rests on the tolerance of the mathematical functions: decNumber's mathematical
functions use the tolerance the specification gives. Of `exp`, `ln`, and `log10`, GDA 1.70, pages 30
and 31 (`exp`, `ln`, `log10`) say that an inexact result "will be rounded using the round-half-even
algorithm" and "should be correctly rounded, but may be up to 1 ulp ... in error". The library
returns the correctly rounded value in both extended and subset arithmetic. Where a row of the
corpus holds the other value, one unit in the last place away and inside the tolerance, the row is
recorded with the corpus value, the held value, the value of decNumber 3.68, and what the held value
rests on: the corpus value is not wrong; the row is recorded because the two texts differ. The
stage judges the row against the held value, reports it as the verdict `deviation`, and fails it if
the result token of the row stops being the recorded corpus value. Nothing is reported upstream.

There is one row of this kind: `official0/ln0.decTest` row `ln116` (`ln 0.99999991000000405` at 17
digits, subset arithmetic) expects `-8.9999999999999879E-8`, decNumber's value, where the
correctly rounded result is `-8.9999999999999878E-8`; the exact result is
`-8.99999999999998784999918E-8`. The extended row `official/ln.decTest` `lnx116` lists the
correctly rounded value, and decNumber itself returns the other one for it, as it does for `lnx732`.
Every other row of `exp`, `ln`, `log10`, and `squareroot` of the two corpora (4,816 and 3,652 rows
of the supported operations) equals the correctly rounded result of CPython `decimal` in its own
context, apart from rows that depend on the exponent range of CPython or on the subset rules that
CPython does not have.

The second kind of row, 64 rows, follows from rule P of page 55 (GDA 1.70, page 55, Appendix A, The
X3.274 subset): in a subset context a positive exponent is reduced to 0 when the coefficient then
has at most precision digits, after any operation. The corpus holds decNumber's results for `reduce`,
`tointegral`, and `squareroot`, which keep the exponent, and 64 rows of `official0` differ from the
library by that rule alone, with the same number and the same flags: 47 of `reduce0.decTest`
(`red060` to `red144`), 9 of `squareroot0.decTest` (`sqtx2207` to `sqtx2847`), and 8 of
`tointegral0.decTest` (`int067` to `int090`). The row `reduce 10.0` expects `1E+1` and the library
gives `10`. Each is recorded in `testdata/decimal_gda/deviations.tsv` with the corpus value, the
held value, the value of decNumber 3.68 (equal to the corpus value), and the decision that the
library follows the text of page 55 for every operation; the corpus value is not wrong, and nothing
is reported upstream.

The third kind, 3 rows (`res397` to `res399` of `rescale0.decTest`), follows from the rounding of
the second operand of `rescale` (GDA 1.70, page 56, Appendix A, first item of "Operation
differences"): `rescale 222 +2.000000001` at precision 9 has the second operand `2.00000000` after
rounding, an integer, and the library gives `2E+2` with `Inexact`, `Lost_digits`, and `Rounded`.
The corpus value is decNumber's, which refuses the unrounded operand as not being an integer
(`Invalid_operation`, no value). The row is recorded with the held value `2E+2` and, in the eighth
column of `deviations.tsv`, the held flags, which the stage judges instead of the flags of the row.
The corpus value is not wrong, and nothing is reported upstream.

## Known deviations outside the corpus

A passing corpus is a finite claim. Review of the implementation found these behaviors, none of which
has a pinned row:

- Integer `power` is not correctly rounded, as GDA 1.70, page 35 (`power`) allows: up to 1 ulp in
  error. Under the nearest rounding algorithms the result is within about 0.55 units in the last
  place of the exact result (0.6 for negative exponents). Under the directed rounding algorithms it is
  within one unit in the last place of the correctly rounded result, and up to 1.03 units from the
  exact result (measured on 8,320 random cases in both arithmetics against Python `decimal`; no case
  at two or more units).

- An exponent of `power` with more than nine digits is not computed: the result is NaN with Invalid
  operation, the limit of the decNumber design (GDA 1.70 states none). Python `decimal` (libmpdec)
  and the IEEE `decimal` package compute these powers.

- Under the directed rounding algorithms an inexact `power` can differ from libmpdec in the last
  digit, because GDA 1.70, page 35 (`power`) allows an inexact `power` to be up to one unit in the
  last place from the correctly rounded result and libmpdec is not correctly rounded there either.

- A `power` call with a zero base and a negative exponent returns an infinity with no condition
  raised, as in libmpdec: the Division by zero condition applies when "the dividend was not zero"
  (GDA 1.70, page 51, Exceptional conditions; page 35, `power`). The IEEE `decimal` package signals
  divideByZero for it (IEEE 754-2019 9.2.1).

## Isolation and native benchmark

The dependency scan `tools/check_imports.py` requires `decimal_gda` to contain no import of the IEEE
`decimal`, and `decimal` none of `decimal_gda`; `decimal_gda_checked` and `frontend/gda_expr` import
`decimal_gda` and no IEEE `decimal`, which no scan enforces. IEEE tests and its independent
conformance corpus are run separately.

The quick benchmark builds only the current engine in an isolated snapshot and runs three native
samples per cell. It reports arithmetic, parser, context, and elementary timing observations without
treating performance as a conformance requirement or comparing against a historical adapter.

## Reproduction

```bash
just conformance smoke decimal_gda
just gate decimal_gda 8
just conformance run decimal_gda --corpus official0 --strict-supported
python3 tools/run_gda_benchmark.py
```

See [the decimal_gda data guide](../../../testdata/decimal_gda/README.md) for manifests, filters, phases, JSON output, and failure triage.
