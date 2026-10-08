# Changelog

All notable repository-release changes are tracked here. The main
[README.md](./README.md) describes the current baseline; historical release
notes live in this file.

## Unreleased

### Added

- Added the remaining IEEE 754-2019 binary operations to `BinFloat`, each
  correctly rounded under a `BinaryContext` and returning `BinaryFlags`:
  - `fma` and `fma_ctx` (fusedMultiplyAdd), which round `x * y + z` once;
    NaN handling follows SoftFloat 3e.
  - `remainder` and `remainder_ctx` (IEEE remainder, quotient rounded to
    nearest-even), without materializing huge scaled dividends.
  - `to_integral_value_ctx`, `to_integral_exact_ctx`, `floor`, `ceil`,
    `trunc`, `round` (ties away) and `round_ties_even` (roundToIntegral).
  - `to_int_ctx`, `to_int64_ctx`, `to_uint_ctx` and `to_uint64_ctx`
    (convertToInteger, with `exact=true` for convertToIntegerExact); invalid
    conversions return `None` with *invalid*.
  - `next_up_ctx` and `next_down_ctx` (nextUp, nextDown).
  - `scaleb_ctx` and `logb_ctx` (scaleB, logB).
  - `copy_sign`, `total_order`, `total_order_compare` and `total_order_mag`
    (copySign, totalOrder, totalOrderMag), and the comparison predicates
    `compare_quiet`, `compare_signaling`, `equal_quiet`, `equal_signaling`,
    `less_quiet`, `less_signaling`, `less_equal_quiet`,
    `less_equal_signaling` and `unordered_quiet`.
  - `from_string` and `from_string_ctx` (convertFromDecimalCharacter),
    correctly rounded for any precision and exponent, including huge
    exponents decided without expansion.
  - `to_decimal_string_ctx` (convertToDecimalCharacter with a fixed digit
    count) and `to_shortest_string` / `to_shortest_string_ctx` (the fewest
    digits that read back to the same value).
- Added the binary implementation exponent range `binary_implementation_e_min`
  and `binary_implementation_e_max` ($[1 - 2^{30}, 2^{30} - 1]$ for the leading
  bit, as in MPFR) and the precision cap `binary_precision_max` ($2^{28}$
  bits).
- Extended the TestFloat frontend (`TestFloatOperation`, `TestFloatSpec::exact`,
  `TestFloatSpec::parse(..., exact?)`) and the binary gate to mulAdd, rem,
  roundToInt, the four integer conversions and the six comparison predicates:
  `just gate binary` now covers 254,227,872 TestFloat vectors, and the binary
  smoke fixture has 2,451 rows.
- Added a nightly workflow that runs the `quick`, `decimal`, `decimal_gda`,
  `binary` and `interval` gates in parallel with cached, hash-verified corpora
  and uploads each summary.
- Added `tools/check_doc_examples.py`, which compiles and runs the manual's
  MoonBit examples against the current branch. `doc/manual` lives outside `src`
  and its examples use plain `moonbit` fences, which `moon` does not compile, so
  none of them were covered by a gate before; `just docs` now checks 236
  examples across 48 pages.

### Changed

- `BinFloat::compare` and the IEEE and GDA `Decimal::compare` no longer abort
  on NaN. They keep the numeric order for other operands (`-0 == +0`) and
  order every NaN equal to every other NaN and above every number, so
  `Compare`, `<`, `<=` and sorting form a total preorder. IEEE semantics remain
  available through `compare_checked`, the quiet and signaling predicates and
  the total-order functions.
- Results outside the binary implementation exponent range are classified as
  overflow or underflow according to the rounding mode instead of being stored
  with a saturated exponent, and context precision is capped at
  `binary_precision_max`.
- The non-`try` elementary functions of `bin_float`, `decimal` and
  `decimal_gda` return defined results instead of aborting when certification
  fails: binary returns a quiet NaN with *invalid operation*, decimal and GDA
  return their invalid result so that flags and traps apply. `try_*` functions
  still report the failure detail.
- Migrated to the MoonBit 0.10 toolchain. Trait-implementation methods are no
  longer promoted implicitly, so every promoted method is declared with
  `pub extend` and the generated interfaces now list them (`equal`,
  `not_equal`, `op_lt`, `op_le`, `op_gt`, `op_ge`, `output`, `to_repr`, the
  `*_contextual` and `*_checked` methods of `BinFloat`, `Decimal` and
  `BallFloat`, and `Decimal::from_integral` / `from_nat`). Call sites that
  relied on implicit promotion keep working; the public API is otherwise
  unchanged. The tree builds cleanly
  with `--deny-warn` under moonc 0.10.14 (core packages imported explicitly,
  black-box test names qualified) and is formatted with the moonc 0.10.11
  formatter.
- Split the generated IEEE decimal public-API fixture into files of 400 tests,
  which moonc 0.10.14 requires.
- Raised `moonbitlang/x` from 0.4.46 to 0.5.5 and `moonbitlang/async` from
  0.20.1 to 0.22.4.
- **Breaking:** raised `Luna-Flow/luna-generic` from 0.3.3 to 0.4.0, which
  deprecates the `NatHomomorphism` and `IntegralHomomorphism` traits because
  they compose a lift with a canonical map, which is not a homomorphism for
  fixed-width types. `Decimal::from_nat` and `Decimal::from_integral`, in the
  IEEE and GDA packages, are replaced by `Decimal::from_natural` and
  `Decimal::from_integer`, which take the `BigInt` representative directly.
  Callers that passed another Luna-Flow integer type pick its representative
  with `Integral::normalize` first, or use `lift_to`.
- Moved the documentation to the gettext layout: English pages in
  `doc/manual` with one `api/`, `tutorial/` and `design/` page per package,
  translations as catalogs in `doc/locale`, and Typst attachments in
  `doc/attachments`. A `Docs` workflow runs `lunadoc check`, and
  `tools/doc_quality.py` checks the new layout.
- Rewrote the documentation (API, tutorial and design pages for every package,
  the overview and the guides) with Chinese and Japanese translations. API
  snapshots use the `mbti` fence, which `tools/doc_quality.py` accepts.
- Ignored local AI-agent state (`.claude/`, `.codex/`, `.cursor/` and similar)
  in `.gitignore`.
- Moved every workflow to the `ubuntu-26.04` runner ahead of the `ubuntu-latest`
  migration that GitHub rolls out between 2026-10-19 and 2026-11-19, and raised
  the actions that still targeted the deprecated Node 20 runtime:
  `actions/checkout` to v7, `actions/cache` to v6, `actions/upload-artifact` to
  v7 and `extractions/setup-just` to v4.
- Brought the manual to the Luna-Flow documentation standard: the overview
  has one Pages table per package group and a Validation section; every API
  page has Purpose and Importing sections and a heading for every public item
  of `pkg.generated.mbti`; every tutorial maps tasks to items in an
  "I want to / Use" table; every design page ends with its boundaries. The
  derivations were reviewed against the code: wrong steps were corrected (for
  example the decimal ideal exponent of an exact quotient, the interval
  product sign cases, Moore's single-occurrence theorem and the integer-power
  error bounds), missing arguments were added (termination of the certified
  refinement loop, the `ZeroFiveUp` division lemma, the shortest-digits
  bisection), and known deviations of the implementation are documented next
  to the affected operations. The Chinese and Japanese catalogs follow.

### Fixed

- Fixed the sign of a zero result of `decimal_gda` `plus` and `minus`
  (`Decimal::plus_ctx`, `Decimal::minus_ctx`, `GdaDecimalChecked::plus` and
  `GdaDecimalChecked::minus`), which was always `+0`. GDA defines `plus(x)` as
  `add('0', x)` and `minus(x)` as `subtract('0', x)`, and a zero sum of
  operands with opposite signs is `-0` under round-floor, so `plus(-0)` and
  `minus(0)` are now `-0` under `Floor` (#58).
- Fixed `frontend/itl_expr::execute_case` with a `precision` other than 53:
  operands and expected values were read at `precision` bits but interval and
  `mid` results were rounded to binary64. Results are now rounded with
  `BallContext::new(precision=precision)` (binary64 exponent range), so the
  default 53 is unchanged. Decimal bounds stay rounded to nearest, which is
  the ITF1788 convention for `[l,u]` (#62).
- Fixed the decTest tokenizer of `frontend/gda_expr`, which ended a quoted
  token at the next matching quote. A doubled delimiter inside a quoted token
  (`'1E''1'`, `"1E"""""`) is now one literal quote character, as the decTest
  format specifies, so such an operand is no longer split into several (#63).
- Fixed two decorations that claimed `dac` for an argument reaching outside
  the domain. Decorated `rootn` with a negative degree now gives `trv` when the
  argument contains 0, where `x^(-1/n)` has a pole (#45), and decorated
  `tanpi_interval` gives `trv` whenever its result is unbounded, which
  includes a pole at an endpoint such as `tanpi([1/2, 1]) = [-inf, 0]`, not only
  an Entire result (#86).
- Fixed `BinCoeff::gcd` on the non-JS targets, which did not finish for some
  operands of different lengths: the Lehmer loop took each operand's own top
  limb as its leading digit, so the quotient estimate ignored the length
  difference and each round removed only a small multiple of the smaller
  operand. The leading digits now come from the same bit window, with a
  division step when the smaller operand has no bits in it. This made
  `BallFloat::ln_interval` hang for values just above 1 at high precision
  (`1 + 2^-243` at 245 bits) and `asinh_interval` and `atanh_interval` hang for
  tiny arguments at 53 bits (#85).
- Fixed `BallFloat::exp2_interval` for integer endpoints outside the binary
  exponent range. The exact power `2^n` was built rounded to nearest, so
  `exp2([-1073742000, -1073742000])` returned `{0}`, which excludes the true
  value, and `n >= 2^30` aborted with an infinite lower bound. Such endpoints
  now keep the series enclosure (#84).
- Fixed the signed-zero special cases of `BinFloat::atan2`, `atan2_ctx` and
  `try_atan2_ctx` (#48). `atan2(±0, +0)` returned $\pm\pi/2$ instead of $\pm 0$,
  `atan2(±0, -0)` returned $\pm\pi/2$ instead of $\pm\pi$, and
  `atan2(-0, x < 0)` returned $+\pi$ instead of $-\pi$; a zero ordinate now
  keeps its sign and the sign of the abscissa picks $\pm 0$ or $\pm\pi$, as
  IEEE 754-2019 §9.2.1 requires.
- Fixed the sign of `BinFloat::tanpi` at odd integers (#81): `tanpi(1)` returned
  $+0$ and `tanpi(-1)` returned $-0$. Zeros now take the sign of
  $\operatorname{sinPi}(n) / \operatorname{cosPi}(n)$ (IEEE 754-2019 §9.2.1, C23
  Annex F): $-0$ for positive odd and negative even $n$, $+0$ otherwise.
  `BallFloat::tanpi_interval` inherits the sign at such an endpoint, so
  $[1/2, 1]$ now prints as `[-inf, -0.00000e+0]`.
- Fixed `BinFloat::pow`, `pow_ctx` and `try_pow_ctx` on IEEE 754-2019 §9.2.1
  inputs they rejected or got wrong (#49, #89). A negative base with an integer
  exponent of magnitude at least $2^{31}$ was a domain error, and so was a
  negative base with an infinite exponent (`(-1)^inf` is now 1,
  `(-0.5)^inf` is $+0$); `(-0)^0.75` was a domain error instead of $+0$;
  `(-inf)^(2^31 + 1)` returned $+\infty$ instead of $-\infty$; and
  `pow(±0, -inf)` raised *division_by_zero*. Integrality and parity of the
  exponent are now read from its representation, and a negative base with an
  integer exponent is evaluated as $\pm|x|^y$ with mirrored directed rounding.
- Fixed exact `pow` results with a non-integer exponent (#49): `16^0.75`
  returned 8 with *inexact* under round-to-nearest and a certification failure
  under a directed mode. For $x = c \cdot 2^e$ and $y = m / 2^k$, a dyadic
  result exists exactly when $2^k$ divides $e$ and $c$ is a perfect $2^k$-th
  power; it is now computed and rounded once before the Ziv loop.
- Fixed `BinFloat::rootn` for exact roots with a negative degree or a degree
  above 64 (#90): `rootn(8, -3)` returned $1/2$ with *inexact*, and in a directed
  mode `rootn(8, -3)`, `rootn(2^130, 65)` and `pow(4, -0.5)` failed to certify.
  An exact root $r$ is now returned as $r$, or as the correctly rounded $1/r$.
- Fixed `BinFloat::rootn(-inf, n)` for even `n` (#90), which returned
  $+\infty$ (or $+0$ for negative `n`); like a finite negative argument it is
  now a domain error (*invalid* in `rootn_ctx`).
- Fixed certification failures of the `BinFloat` elementary functions for tiny
  arguments (#102): `sin`/`atan` of $2^{-6000}$ at 53 bits, `sin` of
  $2^{-8000}$ in binary128 and `exp`/`expm1`/`exp2` of $2^{-20000}$ returned
  `certification_failure` (NaN from the non-`try` APIs), as did `cos`, `tan`,
  `asin`, `sinh`, `cosh`, `tanh`, `asinh`, `atanh`, `log1p` and `cospi` in
  some rounding modes. An enclosure endpoint that is itself a rounding
  breakpoint now moves just inside the enclosure when the result is known to
  be irrational, and `sin`, `cos`, `tan`, `asin`, `sinh`, `cosh`, `tanh`,
  `asinh`, `atanh`, `expm1` and `log1p` decide arguments far below the target
  spacing from rigorous $O(x^2)$ and $O(x^3)$ bounds before the Ziv loop.
- Fixed `exp10` and `log10` exact results past $10^{4096}$: `exp10(n)` for an
  integer $n \ge 0$ and `log10(10^k)` are now computed exactly whenever the
  precision can hold them, instead of going through the Ziv loop.
- Fixed `BinFloat::hypot` for operands whose exponents differ by more than
  about 500,000 (#103), which returned `certification_failure`:
  `hypot(1, 2^-600000)` is now 1 (*inexact*). An operand too small to reach a
  rounding breakpoint is replaced by a power of two of the same effect before
  the exact sum of squares is formed.
- Fixed `BinFloat::rootn` and `pow` for exact roots of coefficients wider than
  4096 bits (#129). The exact-root check gave up above that width, so at 3001
  bits `rootn((2^3000 + 1)^2, 2)`, `pow((2^3000 + 1)^2, 0.5)` and
  `rootn((2^3000 + 1)^3, 3)` returned the root with *inexact* under
  round-to-nearest and `certification_failure` under the directed modes. The
  integer root now takes exact square roots for the even part of the degree
  and integer Newton steps from the root of the leading bits for the odd part,
  so there is no width limit and wide coefficients no longer cost one power per
  root bit.
- Fixed `BinFloat::pow`, `pow_ctx` and `try_pow_ctx` for tiny non-integer
  exponents (#128): `pow(2, 2^-16000)` in binary128 and `pow(3, 3 * 2^-20000)`
  at 53 bits returned `certification_failure` (NaN from the non-`try` APIs),
  because the lower end of the enclosure stayed exactly 1 and never rounded
  like the upper end. When the exact-result check shows that `x^y` is not a
  rounding breakpoint (irrational, not dyadic, or wider than the precision),
  the Ziv loop now moves a breakpoint endpoint inside the enclosure, as the
  other elementary functions do since #102.
- Fixed `tools/doc_quality.py`, which treated every package as generated when
  the checkout itself lived under an underscore-prefixed directory.
- Fixed `BinFloat::acos`, `acos_ctx` and `try_acos_ctx`, which recursed through
  the certified `asin` bounds until the stack overflowed (SIGSEGV on native, a
  `RangeError` on wasm-gc) for a NaN, an infinity or a finite `|x| > 1`. They
  now match `asin`: a quiet NaN for a NaN input and a domain error otherwise.
- Fixed `Decimal` integer powers (`power_ctx` with an integer exponent,
  `pown_ctx`, and `exp2_ctx`/`exp10_ctx` at integers), which used decNumber's
  repeated rounding at `p + digits(n) + 2` digits and could round to the wrong
  side of a midpoint: `3.339434^3` in decimal32 gave `37.24076` instead of
  `37.24077`. In extended contexts the exact power is now rounded once when it
  is short enough to form, and otherwise directed-rounding bounds are refined
  until they round alike (#104). `pown_ctx` also built its exponent at the
  context precision, so `(-1)^12345679` at seven digits was `1` (#51).
- Fixed `pow_int_checked` and `pow_nat_checked` for `Decimal` in `decimal` and
  `decimal_gda`, which still built the integer exponent at the context
  precision: an exponent longer than the precision was rounded first, so
  `(-1)^12345679` at seven digits was `1`. The exponent is now exact (#123).
- Fixed `Decimal::hypot_ctx` and `rootn_ctx`, which returned exactly
  representable results such as `hypot(0.3, 0.4)` and `rootn(0.008, 3)` padded
  to full precision with `inexact`, or failed certification in the directed
  modes. Exact norms and roots are now detected first and returned exactly
  (#105).
- Fixed `BallFloat::from_int` and `BallFloat::from_coefficient`, which rounded
  the value to the requested precision and wrapped the rounded result as a
  singleton, so the interval could exclude its own input
  (`BallFloat::from_int(100001)` at the default 16 bits returned exactly
  100000). They now build the value exactly and let the interval round outward.
- Fixed `BallFloat::with_precision`, which rebuilt a bounded interval from
  `center()` and `radius()`. The center adds the endpoints in round-to-nearest
  mode, which replaces an addend more than 65536 bits below the larger one by a
  sticky surrogate, while the radius drops that addend; once the new precision
  stored the surrogate exactly the result no longer contained the original
  lower endpoint. Both branches now round the endpoints outward, as the
  unbounded branch already did, which also makes the result the tightest
  representable enclosure instead of widening ordinary intervals. The
  rounding-mode argument is kept for signature compatibility and cannot narrow
  an enclosure. `normalized()` uses the same surrogate but is not affected: it
  keeps the interval's own precision, where the center error always folds the
  surrogate back into the radius.
- Fixed `BallFloat::normalized`, which rebuilt a bounded interval from its
  normalized center and radius and so rounded outward a second time:
  `[1, 1 + 2^-52]` at 53 bits came back as `[1 - 2^-52, 1 + 2^-52]`, breaking
  the `Floating` law that `normalized` keeps the value. It now normalizes the
  endpoints themselves. With the `with_precision` fix above, `convex_hull` with
  an Empty operand and the checked capabilities (`pow_int_checked`,
  `pow_nat_checked`, `div_checked`) no longer widen representable intervals
  either (#69).
- Fixed `BallFloat::midpoint_ctx`, which rounded a subnormal center to nearest
  twice (first to the context precision, then to the subnormal grid) and
  returned 0 instead of `2^-5` for `2^-6 + 2^-20` at 4 bits with
  `e_min = -2` (#70), and which ignored `e_max`. It now rounds once onto the
  grid the result lives on and overflows to an infinity with `overflow` and
  `inexact`, as round to nearest does in IEEE 754 (#46). It also follows the
  remaining cases of the IEEE 1788-2015 `mid` operation (12.12.8) instead of
  aborting: NaN for Empty, the context's largest finite value with the sign of
  the unbounded side for a half-bounded interval, and +0 for a zero center.
- Fixed `BallFloat::apply_ctx` and the `*_ctx` operations, which raised
  `underflow` only when the step onto the subnormal grid was inexact. An
  endpoint that is tiny after rounding and inexact in either step now raises
  it, as IEEE 754 defines (#71).
- Fixed `BallFloat::pow_nat_checked` and `BallFloatResult::pow_nat`, which
  returned `{1}` for an Empty base and exponent 0; they now return Empty, like
  `pown` (#72).
- Fixed `DecimalFlags::has_error` in the IEEE and GDA packages, which omitted
  `conversion_syntax`. Since `from_string_ctx` reports invalid text with only
  that flag, a failed parse did not count as an error.
- Fixed `Decimal::atan2_ctx`, `try_atan2_ctx` and `DecimalChecked::atan2`
  for zero and infinite operands. An infinite operand aborted the process
  inside the certified ball evaluation, `atan2(+-0, -0)` returned NaN with
  `invalid_operation`, and `atan2(-0, x < 0)` returned `+pi`. They now follow
  IEEE 754-2019 §9.2.1: an exact signed zero or a correctly rounded multiple
  of pi/4 with the ordinate's sign (#92).
- Fixed `Decimal::cosh_ctx(-inf)`, `log2_ctx(+inf)` and `log1p_ctx(+inf)`
  (and their `try_` forms), which returned NaN with `invalid_operation`
  instead of `+inf` (#93).
- Fixed double rounding in every guarded decimal division path. The guarded
  quotient was rounded with the target mode, which can manufacture an exact tie
  the exact quotient had already decided; the final rounding then applied the
  tie rule to it. `15 / 83294` at five digits returned `0.00018008` instead of
  `0.00018009`, and GDA `divide(1, 2222)` at one digit returned `0.0004`
  instead of `0.0005`. The guarded quotient is now rounded with `ZeroFiveUp`,
  which keeps the retained low digit off 0 and 5 whenever the remainder is
  nonzero, as decNumber's `DEC_ROUND_05UP` does. This covers the context-free
  `/` operator and the contextual divide of both decimal packages, including
  their subnormal and non-extended paths, and the two division helpers behind
  the GDA elementary functions.
- Fixed double rounding of `Decimal` context results whose exact exponent is
  below Etiny but whose magnitude is normal. Finalization rounded them to the
  subnormal grid first and then to the context precision, so
  `3.000001E-45 * 1.500001E-45` in decimal32 returned `4.500004E-90` instead
  of `4.500005E-90`. The same path served `mul_ctx`, `fma_ctx`, `apply_ctx`,
  `plus_ctx` and the elementary functions (`exp_ctx(-215.35)` in decimal32).
  The subnormal rounding now applies only to results that are subnormal. The
  fallback path of `div_ctx` also rounded a subnormal quotient to the context
  precision before rounding it to Etiny (`1 / 1.9999999999998E+101` in
  decimal32 gave `0E-101`, not `1E-101`); it now rounds the guarded quotient
  once (#87).
- Fixed `Decimal::add_ctx` when one operand lies far below the other's
  rounding position. The shortcut rounded the larger operand alone and moved
  the result by one unit at most, deciding the direction from that operand
  only. This was wrong when the larger operand had digits below the rounding
  position, when it was a midpoint, and for `ZeroFiveUp` with an addend that
  lowers the magnitude (`1598618 - 9.9E-11` at seven digits returned
  `1598618`). Extended contexts now replace the small operand with a sticky
  unit below every rounding boundary and round the sum once (#88).
- Fixed `Decimal::scaleb_ctx` finalization. Overflow returned an infinity in
  every rounding mode; it now follows the rounding direction, so toward zero
  gives the largest finite number (#52). A zero result kept an exponent outside
  the context range (`0 scaleb 700` in decimal64 gave `0E+700`; now
  `0E+369` with `clamped`), and a coefficient longer than the precision was
  left unrounded or, below Etiny, rounded to the subnormal grid and flagged
  `subnormal` although its magnitude was normal. The scaled value is now
  rounded once like any other context result (#95).
- Fixed `decimal_gda` `add` and `subtract` when one operand lies far below
  the other's rounding position, as for `Decimal` in #88. The shortcut rounded
  the larger operand alone and moved the result by one unit at most, so
  `1598618 - 9.9E-11` at seven digits with `ZeroFiveUp` returned `1598618` and
  `1598618.5 + 1E-20` with `HalfEven` returned `1598618`. Extended contexts now
  replace the small operand with a sticky unit and round the sum once (#120).
- Fixed double rounding in `decimal_gda` of results whose exact exponent is
  below Etiny but whose magnitude is normal, as for `Decimal` in #87.
  `3.000001E-45 * 1.500001E-45` in decimal32 returned `4.500004E-90` instead
  of `4.500005E-90` (also `fma`, `plus` and `exp`). The inexact path of
  `divide` rounded a subnormal quotient to the precision before rounding it to
  Etiny (`1 / 1.9999999999998E+101` in decimal32 gave `0E-101`, not
  `1E-101`), and its exact-quotient shortcuts rounded a normal quotient below
  Etiny to Etiny only, leaving more digits than the precision (`77223 /
  16E+21` at precision 5 gave `4.82644E-18`). Each is now rounded once (#121).
- Fixed `decimal_gda` `scaleb` finalization, as for `Decimal` in #52 and #95.
  Overflow now follows the rounding direction instead of always returning an
  infinity, a zero result has its exponent clamped into the context range
  (`0E+300 scaleb 400` in decimal64 gives `0E+369` with `Clamped`), and a
  coefficient longer than the precision is rounded once to the precision
  (#122).
- Fixed `Decimal::div_ctx` by a power of ten when the exact quotient's
  exponent is below Etiny but its magnitude is normal. The quotient was
  rounded to Etiny only and kept more digits than the precision
  (`4826437 / 1E+24` at precision 5 with `Up` gave `4.82644E-18`, not
  `4.8265E-18`); it is now rounded once to the precision. The division
  helpers behind the elementary functions had the same shortcut (#126).
- Fixed `to_integral_exact` and `to_integral_value` in `decimal_gda` (the GDA
  functions and the `Decimal` methods) for operands longer than the context
  precision. An operand with a non-negative exponent was rounded to the
  precision (`12345` at precision 3 gave `1.23E+4` with `Inexact`), and one
  with a negative exponent was quantized at the context precision, so
  `12345.6` gave NaN with `InvalidOperation`. As in decNumber, an operand with
  a non-negative exponent is now returned unchanged and the quantization to
  exponent 0 uses a working precision of at least the operand's length
  (`12345.6` gives `12346`, with `Inexact` and `Rounded` for the exact form).
- Fixed `DecimalTininessDetection::AfterRounding` in the IEEE and GDA decimal
  packages. It decided tininess from the result rounded on the subnormal grid
  (at `Etiny`), which keeps fewer digits than the precision, so a value just
  below $10^{e_{\min}}$ whose rounding to $p$ digits stays below it counted as
  not tiny: `0.9951` at precision 3 and $e_{\min} = 0$ rounded to `1.00`
  without `underflow`. Tininess after rounding now uses the value rounded to
  $p$ digits with an unbounded exponent range, as IEEE 754 §7.5 and the
  package documentation define it.
- Fixed `bench::paired_hotspot`, which passed the bootstrap confidence as
  `0.95` where Maremark expects a percentage, so its `interval` was a 0.95 %
  interval (a single point) instead of a 95 % one.
- Fixed `bench::TuneDecision::valid_samples`, which counted the negative and
  non-finite samples the median discards.
- Fixed `frontend/gda_expr::execute_documents`, which aborted on a context
  with `precision: 0` (or a negative precision, or `minexponent` above
  `maxexponent`) because it built a `DecimalContext` before classifying the
  row. Such rows are now `Diagnostic` with the reason
  `diagnostic invalid context: …`.
- Fixed `frontend/gda_expr` operand decoding, which read plain decimal
  operands at $\max(64, p)$ digits and so rounded longer operands before the
  operation rounded again: at precision 9 the 67-digit operand
  `1000000014` followed by 56 nines and a 5 gave `add … 0 -> 1.00000002E+66`
  instead of `1.00000001E+66`. Operands are now read exactly, as GDA requires.
- Fixed `frontend/itl_expr::execute_case`, which read the operands of the
  generic binary dispatch before checking the operation, so an unknown
  operation with a non-interval operand (`nums2interval 1.0 2.0`,
  `rootn [1.0,8.0] 3`) was a `Diagnostic` and made `success()` false. Unknown
  operations, including unknown boolean predicates, are now `Unsupported`.
- Fixed `frontend/itl_expr::parse_itl`, which recognized `//` comments only at
  the start of a line, so a statement followed by `; // note` did not end and
  silently swallowed the next statement. A `//` comment now ends the line.
- Fixed `frontend/mpfr_expr` elementary rows: a `pow`, `hypot` or `atan2` row
  whose second operand is `-` is now the parse diagnostic
  `invalid MPFR elementary field` instead of aborting the run, and a zero
  result must have the expected sign (`compare` identifies `-0` and `+0`).
- Fixed `cli/gda_expr_cli`, which silently skipped a named file that does not
  end in `.decTest`, so a mistyped path ran zero cases and exited with 0. The
  shared `internal/runner_cli::collect_files` now reports
  `not a .decTest file: PATH` for such a file, lists a file named twice (or
  named and inside a named directory) once, and no longer lists
  subdirectories whose names end in the suffix.
- Fixed `internal/runner_cli::parse_common_options`, which took the next
  option as the value of `--shard-count` or `--shard-index`
  (`--shard-count --json` reported `invalid shard count: --json`); it now
  reports `--shard-count requires a value`.
- Fixed the `cli` dispatcher, where an empty `--backend=` slipped past the
  at-most-once check, so `--backend= --backend gda` was accepted. An empty
  value is now the error `--backend requires a value`.
- Fixed `decimal_gda` `power` and `Decimal::power_ctx` for a non-integral
  exponent whose exact result is representable, in the directed rounding
  modes. `power(4, 1.5)` returned `8.0000` at once under `HalfEven` but did not
  return under `Down`, `Up`, `Ceiling` or `Floor`: the exact value 8 is an
  endpoint of the directed rounding cell, so the certified loop could never
  accept it. An exponent `a/q` with a small reduced denominator is now tested
  for an exact power (`x^a` a perfect `q`-th power) before the loop; the exact
  value is rounded once in the context mode and, as GDA requires for
  non-integral powers, reported as Inexact and Rounded.
- Fixed decimal literals with exponents beyond $\pm 1.5 \cdot 10^9$ and
  products and quotients of operands with extreme exponents in the IEEE and
  GDA decimal packages. The literal splitter saturated the written exponent at
  $\pm 1\,500\,000\,000$, so `Decimal::from_string("1e1600000000")` returned
  `1E+1500000000` and a context with `e_max = 2e9` raised no overflow; the
  `Int` exponent sums of `*`, `mul_ctx`, `fma_ctx` and `div_ctx` wrapped, so
  `1E+1500000000 * 1E+1500000000` gave `1E-1294967296` and GDA `multiply`
  underflowed instead of overflowing. Exponents are now read and combined in
  `Int64`: context conversions and operations overflow or underflow as the
  exponent range requires, `parse`/`from_string` reject a literal whose
  exponent cannot be stored, and the context-free `*` and `/` give a signed
  infinity or zero for an unrepresentable result. `internal` gains
  `split_decimal_string_wide`; `split_decimal_string` now returns `None` for an
  exponent outside `Int` instead of a saturated one. The `gda_expr` decTest
  frontend saturates such operand exponents at $2 \cdot 10^9$ itself, as the
  reference implementation's conversion does, so rows like
  `quantize 0 1e3000000000` keep their expected result.
- Fixed `just gate <scope>` on a clean checkout: every scope now installs the
  module dependencies first. `moon update` only refreshes the registry index, so
  the first `--frozen` command failed with "`frozen` is set, so the build system
  cannot change the modules directory". This broke the nightly `decimal_gda`
  job, the only nightly scope whose first command is `--frozen`.
- Fixed three tutorial pages that showed `moon add Luna-Flow/floating` without
  the version the other install snippets pin.
- Fixed exponent arithmetic that saturated at the 32-bit limits:
  `2^2e9 * 2^2e9` returned a finite value with no flag, and interval endpoints
  could stop enclosing the exact value.
- Fixed `exp`, `expm1`, `exp2`, `exp10`, `sinh`, `cosh` and `pow`, which could
  fail to certify results whose enclosures overflowed; they now decide
  overflow and underflow from certified bounds on $\log_2$ of the result.
- Fixed `ball_float` endpoint helpers that built exact values beyond the
  exponent range: `exp([1e9, 1e9])` aborted and `exp([-1e9, -1e9])` returned
  `[0, 0]`. Lower endpoints now clamp toward $-\infty$, upper endpoints toward
  $+\infty$, and `exp` of very large arguments returns
  `[max finite, +inf]` or `[0, smallest positive]`.
- Fixed interval addition of operands with a huge exponent gap, which built a
  two-billion-bit coefficient; an addend far below one ulp is replaced by a
  directed sticky term.
- Fixed the decimal certified bridge, which expanded binary endpoints near
  $2^{2^{30}}$ into hundreds of millions of digits (`sinh(1e300)` used several
  GB), and decimal power results far outside the exponent range, which are now
  decided before certification.

## 0.8.0 - 2026-09-06

### Added

- Added `AddContextual`, `SubContextual`, `MulContextual`, `DivContextual`,
  `AbsContextual`, `SqrtContextual`, and `ExpContextual` implementations for
  `BinFloat`, so the binary stack participates in the contextual trait surface
  already provided by the decimal stacks.
- Exposed `to_string` as an explicit public method on `BinFloat`, `BinCoeff`,
  `Decimal` (IEEE and GDA), `BallFloat`, `BallFloatDecorated`, and `Decoration`
  through `extend` declarations.

### Changed

- Raised the `Luna-Flow/arithmetic` dependency to `0.5.0`, whose
  `ArithmeticContext` carries exponent bounds and clamping.
- Changed `BinaryContext::from_arithmetic_context`, and the IEEE and GDA
  `DecimalContext::from_arithmetic_context`, to propagate `e_min`, `e_max`, and
  `clamp` from the arithmetic context instead of discarding them. Contextual and
  checked operations that previously ran unbounded now honour the caller's
  exponent range.
- Changed `BinaryContext::new` and `BinaryContext::try_new` to accept a
  one-sided exponent bound. `try_new` now fails only when `e_min` exceeds
  `e_max`; passing `e_min` or `e_max` alone previously aborted or returned an
  error.
- Changed the decimal `PowNatChecked` and `PowIntChecked` implementations to
  derive their context from the supplied arithmetic context instead of fixed
  `+/-999_999` exponent bounds.
- Renamed `BinCoeff::to_string(radix~)` to `BinCoeff::to_radix_string(Int)` so
  that `BinCoeff::to_string` denotes the `Show` implementation, consistent with
  the other numeric types. Callers that passed a radix must use the new name;
  radix-10 callers are unaffected.
- Declared `Show::to_string` explicitly with `extend` instead of relying on the
  implicit promotion of `impl Show` methods, which the MoonBit 0.10.4 toolchain
  deprecated. The repository now checks clean under `moon check --deny-warn` on
  all five backends.
- Replaced `StringBuilder::new()` with the `StringBuilder()` custom
  constructor, which MoonBit 0.10.11 requires; the previous spelling fails the
  `--deny-warn` publish gate.

### Fixed

- Fixed the native link failure of the `cli` conformance dispatcher by reading
  process arguments through `moonbitlang/core/env` instead of
  `moonbitlang/x/sys`. The `x` intrinsic still lowers to the pre-rename runtime
  symbol `moonbit_get_cli_args`, which the current split `libruntime.a` no
  longer exports; `@env.args` uses the current `moonbit_rt_get_cli_args`.

### Verified

- Passed the complete `just pr` gate: format, localized documentation, native
  check and test, IEEE 754 smoke 6,897/6,897, binary smoke 2,271/2,271, GDA
  TestFloat 3e 60/60, and interval smoke 10/10.
- Passed `moon check --deny-warn --target all` and `moon test src/bin_float
  --target all` across wasm, wasm-gc, js, and native.
- Retained the 0.7.1 performance and semantic audit unchanged; this release
  contains no new numerical measurements.

## 0.7.1 - 2026-07-16

### Changed

- Audited and retained the decimal GDA coefficient fast paths, IEEE decimal
  exact/bounded division paths, binary exact-top arithmetic paths, and interval
  endpoint dispatch introduced after the 0.7.0 release.
- Added a directed-rounding and monotonicity proof boundary to the interval
  design: every endpoint candidate is rounded outward, and negative-half-axis
  integer powers use the correct reversed endpoint order.
- Kept target-specific crossover tuning as implementation evidence only; noisy
  or non-monotonic observations are not promoted into public performance claims.
- Added package-level GDA and interval performance entry points and aligned the
  decimal performance instructions with the current Maremark runner.

### Fixed

- Removed stale decimal baseline and threshold commands from the published
  performance documentation and corrected the localized release-date record.
- Corrected `BallFloat::pown` for even powers on negative intervals and for even
  negative powers on the negative half-axis. The previous optimization could
  construct an interval with a lower bound above its upper bound or lose one
  outward-rounded ulp across zero.
- Completed the GDA half-power-of-ten coefficient comparison used by the
  optimized rounding path and covered its exact, below-half, and above-half
  boundaries.

### Verified

- Passed the native IEEE 1788 strict aggregate at 4,656/4,656 after the
  interval regression fix, including 174/174 integer-power cases.
- Passed the pinned binary, IEEE decimal, and GDA suites: 7,464,503 binary
  cases, 15,763 IEEE decimal cases, 64,986 current GDA cases, and 16,124
  legacy GDA cases.
- Completed native Maremark `all` and `auto-tune` artifacts; auto-tune output
  is retained as calibration evidence and is not treated as a universal
  crossover guarantee.
- Added a localized performance audit and semantic-proof matrix for the
  `en_US`, `zh_CN`, and `ja_JP` documentation trees.

## 0.7.0 - 2026-07-15

### Added

- Added a shared certified dyadic/interval kernel and bounded Ziv refinement
  for `BinFloat`, `Decimal`, and `BallFloat`; acceptance requires both enclosure
  endpoints to round to the same target value and flags.
- Added the complete 0.7.0 elementary families, pi-scaled functions, contextual
  and `try_*` entry points, and checked mirrors without extending the GDA
  surface beyond `exp`, `ln`, `log10`, `power`, and `sqrt`.
- Added structured certification-failure details and a unified `bench` package
  hierarchy using Maremark 0.3.0 for kernel, core, checked full-path,
  elementary, hotspot, and auto-tune measurements.

### Changed

- Exhausted certification budgets now fail explicitly instead of accepting
  repeated-approximation results.
- Decimal elementary evaluation now bridges MPFR-directed dyadic enclosures to
  exact decimal endpoint rounding; GDA `sqrt`/`exp`/`ln`/`log10` retain fixed
  HalfEven semantics while `power` follows the active GDA context.
- Aligned the GDA public context surface with Arithmetic Specification 1.70:
  the Basic context uses HalfUp and standard error traps, invalid subconditions
  signal `InvalidOperation`, and decTest execution now traverses
  `GdaContext`/`GdaOutcome` instead of bypassing the public state model.
- BallFloat checked elementary functions now preserve proof failures, while
  unchecked trigonometric functions retain only mathematically conservative
  interval fallbacks. Pi-scaled range reduction operates directly in x-space.
- Native `BinCoeff::square` now enters recursive multiplication at 512 limbs;
  Maremark auto-tune confirms a stable square policy from 8 limbs upward.

### Verified

- Passed the fixed MPFR 4.2.2 binary elementary corpus at 2,088/2,088 and the
  optional generated stress run at 966,744/966,744; only the fixed corpus is
  part of the reproducible release aggregate.
- Passed the Decimal elementary oracle at 2,784/2,784, the complete four-target
  Decimal gate at 15,735/15,735, GDA `official` at 64,986/64,986, and
  `official0` at 16,124/16,124.
- Passed the pinned ITF1788 strict aggregate at 4,656/4,656 with zero
  unsupported selected cases.
- Passed all 12 shared 0.6.1/0.7.0 native performance cells using ten
  alternating paired samples and the Maremark 95% bootstrap/3% release rule.
  New 0.7.0 elementary APIs intentionally have no fabricated 0.6.1 baseline.

## 0.6.1 - 2026-07-14

### Changed

- Reworked `decimal_checked` into an IEEE context-and-flags pipeline and added
  `decimal_gda_checked` for sticky-context composition, trap short-circuiting,
  defined results, and explicit recovery.
- Consolidated public tooling under parameterized `just conformance`, `just
  gate`, and `just bench` commands and removed the backend-specific aliases.

## 0.6.0 - 2026-07-14

### Changed

- Rebuilt the package documentation matrix across English, Simplified Chinese,
  and Japanese. Every package now has API, tutorial, design, and package README
  coverage; numerical cores have explicit conformance and performance evidence
  pages, and superseded research notes have been consolidated.
- Split IEEE tininess policy from GDA status handling; IEEE contexts default to
  after-rounding and expose an explicit before-rounding choice.
- Reject non-positive public precision and reserve zero-precision arithmetic for
  private exact work contexts.
- Added GDA contexts with radix, sticky flags, trap sets, signal precedence, and
  `GdaOutcome` defined results.
- Removed implementation-specific IEEE oracle and full-vector download paths;
  checked-in DPD/BID fixtures are validated from IEEE encoding formulas.

## 0.5.0 - 2026-07-12

### Added

- Added `BinCoeff`, the non-negative public coefficient boundary for binary
  floating-point, IEEE interchange bits, and ball arithmetic. It provides
  explicit integer/byte parsing, arithmetic, bit operations, division, and
  conversion without exposing MoonBit `BigInt`.
- Added a pure inline/limb coefficient kernel for non-JS targets and a hidden
  host `bigint` adapter for JavaScript behind the same `BinCoeff` API.

### Changed

- Reworked contextual integer powers around a single approximation with a
  conservative dyadic error enclosure and exact can-round checks, retaining
  the exact coefficient-power implementation as the permanent fallback.
- Added leading-bit coefficient exponentiation, small addition chains,
  power-of-two and bounded exact-result dispatches, and 120 fixed MPFR 4.2.2
  `pow_si` witnesses without changing the public rounding semantics.
- Changed `BinFloat`, `BinFloatResult`, `BallFloat`, and `BallFloatResult`
  constructors and accessors to use `BinCoeff` plus an independent sign.
- Changed `BinaryInterchange::bits` and `from_bits` to use `BinCoeff`.
- Renamed the checked-composition wrapper packages with the `_checked` suffix
  to align package paths with the checked arithmetic trait naming.
- Kept the existing Decimal and Semantic `BigInt` APIs unchanged; the migration
  applies only to the binary and ball stacks.

### Removed

- Removed binary-stack `from_bigint` constructors, `BinFloat::significand`, and
  the `NatHomomorphism` / `IntegralHomomorphism` implementations whose public
  boundary depended on `BigInt`. Use `from_coefficient`, `coefficient`, and
  explicit `negative?` arguments instead.

## 0.4.1 - 2026-07-11

### Fixed

- Refreshed the published package README and current-baseline entry points so
  Mooncakes displays the 0.4 release documentation and installation version.
- Recorded verified full-corpus results for both the current and legacy GDA
  suites: 81,110 executable cases passed with zero failures.

### Changed

- Moved `Decoration` and `BallFloatDecorated` into the `ball_float` package so
  bare and decorated IEEE 1788 interval APIs share one package boundary.

## 0.4.0 - 2026-07-11

Feature baseline for Decimal contexts and GDA conformance.

### Added

- Added `DecimalContext`, `DecimalFlags`, decimal-specific rounding modes, and
  context-aware arithmetic, classification, formatting, unary, extrema,
  adjacent-value, logical-digit, quantize/rescale, and elementary operations.
- Added decimal32, decimal64, and decimal128 interchange encoding through
  `DecimalInterchange` and `DecimalInterchangeFormat`.
- Added signed-zero, quiet/signaling NaN, payload, total-order, quantum, normal,
  and subnormal Decimal observers.
- Added `numeric_expr`, a private expression representation with callback-driven
  evaluation and source spans.
- Added `gda_expr` and `gda_expr_cli` for runtime parsing and execution of GDA
  `.decTest` documents, deterministic sharding, case filtering, structured
  summaries, and native CLI execution.
- Added `semantic`, which projects concrete numeric values and arithmetic errors
  into representation-independent scalar, interval, and error values.
- Added pinned external conformance-corpus metadata, a checked-in smoke fixture,
  staged interpreter tooling, and focused CI coverage.

### Changed

- Decimal parsing can preserve exponent/quantum; canonicalization is now an
  explicit `normalized()` or context reduction step.
- Repository validation now separates the focused CI white-box gate from the
  full local/release GDA conformance gate.
- Documentation now follows the package-oriented, current-baseline structure of
  `linear-algebra`, with aligned English, Chinese, and Japanese file sets.

## 0.3.0 - 2026-06-12

### Highlights

- Added `bin_float_result`, `decimal_result`, and `ball_float_result` as closed
  checked-composition wrappers around concrete numeric values.
- Added the first semantic projection layer.
- Integrated shared checked arithmetic capabilities from `Luna-Flow/arithmetic`
  and shared algebraic abstractions from `Luna-Flow/luna-generic`.
- Narrowed `Floating` to classification, sign, precision, precision retuning,
  and normalization; arithmetic capabilities remain separate.

## 0.2.0 - 2026-06-07

### Highlights

- Introduced the shared arithmetic capability boundary.
- Added the first explicit dependency on `Luna-Flow/arithmetic`.

## 0.1.1 - 2026-06-07

### Highlights

- Added the initial ecosystem dependencies needed by the floating-point types.
- Prepared the first maintenance release of the original API line.

## 0.1.0 - 2026-06-06

### Highlights

- Established the MoonBit module and the first arbitrary-precision binary,
  decimal, and ball arithmetic packages.
