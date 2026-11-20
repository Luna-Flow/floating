# Changelog

All notable repository-release changes are tracked here. The main
[README.md](./README.md) describes the current baseline; historical release
notes live in this file.

## Unreleased

### Breaking

- `bin_float`: a context is a format of IEEE 754-2019 3.3 ([#438](https://github.com/Luna-Flow/floating/issues/438), items A3 and A4). It is built from the precision and `e_max`, with `e_min = 1 - e_max`; there is no one-sided or asymmetric range, `RoundAwayFromZero` (no clause 4.3 attribute) is removed, and a context given by its precision alone is the extendable precision format of 3.7 (`e_max` is `binary_implementation_e_max`). The implementation range of stored values is the same range: `binary_implementation_e_min` is `2 - 2^30` (it was `1 - 2^30`), so every stored value is a member of `BinaryContext::new(precision=p)` and a plain operation is the contextual operation in that context. A result whose leading bit is exactly `1 - 2^30` is now subnormal.

  | before | after | note |
  | --- | --- | --- |
  | `BinaryContext::new(p, e_min=a, e_max=b)` | `BinaryContext::new(precision=p, e_max=b)` | `e_min` is `1 - e_max`; `e_max` must be within `1..=binary_implementation_e_max` |
  | `BinaryContext::unbounded(p, rounding=r)` | `BinaryContext::new(precision=p, rounding=r)` | the precision is labelled; `new()` is the 53-bit extendable format |
  | `BinaryContext::try_new(p, ...)` | `BinaryContext::try_new(precision=p, ...)` | the same labelled parameters |
  | `ctx.e_min()`, `ctx.e_max()` returning `Int32?` | `Int32` | never absent |
  | `BinaryContext::from_arithmetic_context(c)` returning a context (aborted on a bad precision) | returns `Result` | an `Err` for `AwayFromZero`, an `e_min` that is not `1 - e_max` and a precision or `e_max` outside the limits; `e_min` alone gives `e_max = 1 - e_min` |
  | `BinaryRoundingMode::RoundAwayFromZero` | removed | use a directed mode; `@arithmetic.RoundingMode::AwayFromZero` has no binary counterpart |
  | `BinaryRoundingMode::from_arithmetic(m)` returning `BinaryRoundingMode` | returns `BinaryRoundingMode?` | `None` for `AwayFromZero` |
  | `BinFloat::make(.., mode=@arithmetic.RoundingMode)`, `x.with_precision(p, @arithmetic.RoundingMode)` | `mode : BinaryRoundingMode` | `RoundTiesToAway` is available; the `BinFloatResult::with_precision` mode likewise |
  | `binary_implementation_e_min` is `1 - 2^30` | `2 - 2^30` | boundary rows move by one binade |
  | (new) | `BinaryContext::with_precision`, `with_rounding`, `with_e_max`, `with_tininess` | each aborts outside the limits of `new` |

  The MPFR corpora no longer contain rows that no IEEE 754-2019 context has: the generators draw only `emin = 1 - emax` ranges and the five attributes of clause 4.3, the committed corpora were regenerated (`mpfr-4.2.2-elementary`, `-strtofr`, `-decimal-output`, `-random`, `smoke/mpfr-pow-si.txt`), and 13 regression rows with an away-from-zero mode or a range of another shape were dropped from `random-regressions.txt`.

- `bin_float`: the count of `scaleb_ctx` is a `BinFloat` ([#438](https://github.com/Luna-Flow/floating/issues/438), item N5). `BinFloat::scaleb_ctx` took an `Int32` while `Decimal::scaleb_ctx` and the `decimal_gda` `scaleb` take the value kind that `logb_ctx` returns; the three packages now agree.

  | before | after | note |
  | --- | --- | --- |
  | `x.scaleb_ctx(n : Int32, ctx)` | `x.scaleb_ctx(BinFloat::from_int(n), ctx)` | an integer count only: a NaN count propagates, an infinite or non-integer count is a NaN with `invalid_operation`; an integer beyond the `Int32` range acts as the largest count of its sign |

- `decimal`: the comparison family is the one of `bin_float` ([#438](https://github.com/Luna-Flow/floating/issues/438), item N6). `compare_ctx` and `compare_signal_ctx` returned the `Decimal` -1, 0 or 1 (or a NaN), a General Decimal Arithmetic result; IEEE 754-2019 5.11 defines a relation with flags, which `BinFloat` already returned.

  | before | after | note |
  | --- | --- | --- |
  | `x.compare_ctx(y, ctx) -> (Decimal, DecimalFlags)` | `x.compare_quiet(y) -> (@def.PartialOrder, DecimalFlags)` | `Less`, `Equal`, `Greater` or `Unordered` in place of -1, 0, 1 or a NaN; no context; invalid only for a signaling NaN |
  | `x.compare_signal_ctx(y, ctx) -> (Decimal, DecimalFlags)` | `x.compare_signaling(y) -> (@def.PartialOrder, DecimalFlags)` | invalid for every unordered pair |
  | (new) | `compare_quiet_equal`, `compare_quiet_less`, `compare_quiet_less_equal`, `compare_quiet_unordered`, `compare_signaling_equal`, `compare_signaling_less`, `compare_signaling_less_equal` | `(Bool, DecimalFlags)`, the predicates `bin_float` has |

- `decimal`, `ball_float`: conversions between the radices take a required precision and the rounding type of the radix of their result ([#438](https://github.com/Luna-Flow/floating/issues/438), item S8 for `decimal`, as `decimal_gda` already has). `Decimal::to_bin_float` counted its default precision in digits (the precision field of the decimal) where it makes bits, `Decimal::from_bin_float` counted bits where it makes digits, and `to_bin_float` took the `@arithmetic.RoundingMode` of neither radix. `BallFloat::from_int` defaulted to 53 bits without being asked.

  | before | after | note |
  | --- | --- | --- |
  | `x.to_bin_float()`, `x.to_bin_float(precision=p)` | `x.to_bin_float(precision=p)` | required, counts bits, aborts outside `1..=binary_precision_max`; the default was the digits of `x` |
  | `x.to_bin_float(mode=@arithmetic.RoundingMode::X)` | `x.to_bin_float(precision=p, mode=@bin_float.BinaryRoundingMode::Y)` | the rounding-direction attributes of IEEE 754-2019 4.3.1, which add ties-to-away; `ToNearestEven` is `RoundTiesToEven`, `TowardZero` is `RoundTowardZero`, `TowardPositive` is `RoundTowardPositive`, `TowardNegative` is `RoundTowardNegative`, `AwayFromZero` is the one of the sign |
  | `Decimal::from_bin_float(b)`, `Decimal::from_bin_float(b, precision=d)` | `Decimal::from_bin_float(b, precision=d)` | required, counts digits; the default was the bits of `b` |
  | (half-even only) | `Decimal::from_bin_float(b, precision=d, mode=DecimalRoundingMode::Y)` | `mode` defaults to `RoundTiesToEven`; new |
  | `BallFloat::from_int(n)` | `BallFloat::from_int(n, precision=53)` | the precision is required; 53 was the default |

- The flag and trap types share one access style: methods ([#438](https://github.com/Luna-Flow/floating/issues/438), item A5). The fields of `decimal.DecimalFlags`, `decimal_gda.DecimalFlags`, `GdaFlags`, `GdaTrapSet` and `BallFlags` are private; each flag is read with a method of the same name, as `BinaryFlags` already did. `GdaFlags::none` and `GdaTrapSet::none` are `new`, like every other flag constructor. `contains` stays on the types of packages that have a signal enum (`decimal`, `decimal_gda`); `has_error` is unchanged (true for `invalid_operation`, `conversion_syntax`, `division_by_zero`, `division_undefined`, `division_impossible`, `invalid_context`; false for overflow, underflow, inexact and the other conditions, which deliver a usable result).

  | before | after |
  | --- | --- |
  | `flags.inexact` (any of the 13 flag names, on `decimal.DecimalFlags`, `decimal_gda.DecimalFlags`, `GdaFlags`) | `flags.inexact()` |
  | `traps.inexact` (any of the 13 names, on `GdaTrapSet`) | `traps.inexact()` |
  | `flags.inexact`, `flags.overflow`, `flags.underflow` on `BallFlags` | `flags.inexact()`, `flags.overflow()`, `flags.underflow()` (the methods already existed) |
  | `GdaFlags::none()` | `GdaFlags::new()` |
  | `GdaTrapSet::none()` | `GdaTrapSet::new()` |

- `decimal_gda`: `GdaSignal` and `GdaTrapSet` are the nine signals of GDA 1.70 ([#438](https://github.com/Luna-Flow/floating/issues/438), decision 13). The specification has eight signals (page 15) and `LostDigits` in Appendix A, one trap-enabler for each. Conversion syntax, division impossible, division undefined and invalid context are conditions that signal invalid-operation (pages 51 and 52), not signals: they stay flags of `GdaFlags` (still thirteen, because the decTest files name conditions) and a trap on `InvalidOperation` catches all four, as before. `GdaFlags::contains(InvalidOperation)` was already true for them; the trapped signal of such an outcome was already `InvalidOperation` when that trap was on.

  | before | after | note |
  | --- | --- | --- |
  | `GdaSignal::ConversionSyntax`, `DivisionImpossible`, `DivisionUndefined`, `InvalidContext` | removed | read the condition with `flags.conversion_syntax()`, `division_impossible()`, `division_undefined()`, `invalid_context()`, or the signal with `flags.contains(InvalidOperation)` |
  | `traps.with_signal(ConversionSyntax)` (and the three others), `ctx.trap(ConversionSyntax)` | `with_signal(InvalidOperation)`, `ctx.trap(InvalidOperation)` | a trap on one condition alone has no GDA counterpart; the one trap fires for all four |
  | `GdaTrapSet::conversion_syntax()`, `division_impossible()`, `division_undefined()`, `invalid_context()` | removed | `traps.invalid_operation()` |
  | `GdaOutcome::Trapped(ConversionSyntax, ...)` and the three others | `Trapped(InvalidOperation, ...)` | for a trap on one condition alone; the trap on `InvalidOperation` already reported `InvalidOperation` |
  | order of the trapped signal | `InvalidOperation`, `DivisionByZero`, `Overflow`, `Underflow`, `Subnormal`, `Inexact`, `Rounded`, `Clamped`, `LostDigits` | the four detailed conditions are no longer in the list |

- `decimal_gda`: contexts follow GDA 1.70 ([#438](https://github.com/Luna-Flow/floating/issues/438), context rules of the 0.12 plan). `GdaContext::new` and `try_new` accept an exponent range only when it satisfies page 10 of the specification: `e_min` is `-e_max`, `1 - e_max` or `-e_max - 1`. Before, any pair with `e_min <= 0 <= e_max` was accepted, so a context such as `e_min=-50, e_max=60` existed that no format has. `clamp` and `extended` stay as documented decNumber extensions (the official decTest files use both). The default contexts are named after the specification.

  | before | after | note |
  | --- | --- | --- |
  | `GdaContext::new(e_min=-50, e_max=60)` (and `try_new`, any pair outside the rule) | `Err` from `try_new`, abort from `new`, message `e_min must be -e_max, 1 - e_max or -e_max - 1` | use `e_min=-60`, or `-59`, `-61` |
  | `GdaContext::basic()`, `GdaContext::default()` | `GdaContext::basic_default()` | the basic default context of GDA 1.70 (page 16); `GdaContext::new()` was never this context |
  | `GdaContext::decimal32()`, `decimal64()`, `decimal128()` | the same, now `decimal32(rounding?)` and so on | the extended default contexts; `rounding` replaces round-half-even |
  | (new) | `GdaContext::with_precision`, `with_rounding`, `with_exponent_range(e_min~, e_max~)` | each aborts on an invalid result and keeps status, traps and the refinement limit |

- `decimal_gda`: the package exports its GDA 1.70 layer only ([#438](https://github.com/Luna-Flow/floating/issues/438), item A1). `Decimal`, `GdaContext`, the `Gda*` types and the functions named after the GDA operations stay. The status-free engine (`DecimalContext`, `DecimalFlags`, `DecimalRoundingMode`, `DecimalSignal`, `DecimalTininessDetection` and the 52 `Decimal` methods that took a `DecimalContext` or returned `DecimalFlags`) is private to the package, so each operation has one public spelling. GDA 1.70 has no tininess choice (Subnormal is judged before rounding, page 53): `DecimalTininessDetection` and its after-rounding rule are removed, not kept.

  | before | after | note |
  | --- | --- | --- |
  | `x.add_ctx(y, dctx)` (also `sub_ctx`, `mul_ctx`, `div_ctx`, `fma_ctx`) | `add(x, y, gctx)` (`subtract`, `multiply`, `divide`, `fma`) | `o.value()`, `o.raised()` (`GdaFlags`, the same 13 conditions) instead of the tuple |
  | `x.plus_ctx`, `minus_ctx`, `abs_ctx`, `apply_ctx`, `reduce_ctx`, `sqrt_ctx`, `exp_ctx`, `ln_ctx`, `log10_ctx`, `power_ctx`, `scaleb_ctx`, `logb_ctx`, `shift_ctx`, `rotate_ctx`, `compare_ctx`, `compare_signal_ctx`, `max_ctx`, `min_ctx`, `max_magnitude_ctx`, `min_magnitude_ctx` | the free function without the suffix | |
  | `x.quantize`, `rescale`, `divide_integer`, `remainder`, `remainder_near`, `logical_*`, `next_*` (methods taking a `DecimalContext`) | the free function of the same name | |
  | `x.compare_total_ctx(y, d)`, `compare_total_magnitude_ctx` | `compare_total(x, y, gctx)`, `compare_total_magnitude(x, y, gctx)` | the context matters only in a subset context (operands rounded first) |
  | free `same_quantum(x, y, gctx)` | `x.same_quantum(y)` | context-free and quiet (GDA 1.70 page 48) |
  | `x.is_normal(d)`, `is_subnormal(d)`, `class_name(d)` | `is_normal(x, gctx)`, `is_subnormal(x, gctx)`, `class_name(x, gctx)` | |
  | `Decimal::from_string_ctx(s, d)` | `to_number(s, gctx)` | to-number, page 21 |
  | free `parse(s, gctx)` | `to_number(s, gctx)` | renamed to the GDA name |
  | `Decimal::to_sci_string(s, d)`, `to_eng_string(s, d)` | `to_number(s, gctx)` then `v.to_sci_string()`, `v.to_eng_string()` | new: `to_sci_string(Self)`, `to_eng_string(Self)`; neither conversion uses a context (pages 19, 20) |
  | free `to_integral_exact`, `to_integral_value`; methods of the same names | `round_to_integral_exact`, `round_to_integral_value` | the GDA 1.70 names (page 39) |
  | `x.try_exp_ctx(d)`, `try_ln_ctx`, `try_log10_ctx`, `try_power_ctx` | `try_exp(x, gctx)`, `try_ln`, `try_log10`, `try_power` | new free functions: `Ok(outcome)` for every defined case, `Err` only when the library could not certify the result |
  | free `context(precision~, ...)` | `GdaContext::try_new(...)` or `GdaContext::new(...)` | one constructor pair |
  | `DecimalContext::new(precision~, rounding~, decimal_rounding~, ...)`, `DecimalContext::decimal64()` | `GdaContext::new(precision~, rounding=GdaRoundingMode::X, ...)`, `GdaContext::decimal64()` | one rounding parameter |
  | `DecimalContext::with_refinement_limit(l)`, `refinement_limit()` | `GdaContext::with_refinement_limit(l)`, `refinement_limit()` | new methods on `GdaContext` |
  | `DecimalContext::with_tininess(...)` | none | no tininess choice in GDA 1.70 |
  | `GdaInterchangeFormat::context(f)` returning `DecimalContext` | returns `GdaContext` | the same presets |
  | `GdaInterchange::from_decimal(v, f)` returning `(Self, DecimalFlags)` | returns `(Self, GdaFlags)` | |
  | `GdaInterchange::to_decimal_ctx()` | `i.to_decimal()`, plus `is_subnormal(v, f.context())` | the old method only added the subnormal flag |
  | `Decimal::to_interchange_hex(f)`, `from_interchange_hex(s, f)` | `GdaInterchange::from_decimal(v, f).0.to_hex()`, `GdaInterchange::from_hex(s, f)` | one spelling |

- `def`: `Floating::with_precision` has no rounding parameter ([#438](https://github.com/Luna-Flow/floating/issues/438), item A3b and section 1.3 of the shared decisions). A trait method that cannot return an error would have to abort on a valid rounding mode once `RoundAwayFromZero` leaves `bin_float` and `decimal` has the five IEEE modes, so the trait rounds to nearest, ties to even (IEEE 754-2019 4.3.1). The inherent `with_precision` of `BinFloat`, `BallFloat` and both `Decimal` types is unchanged for now and keeps its mode.

  | before | after |
  | --- | --- |
  | `fn with_precision(Self, Int32, @arithmetic.RoundingMode) -> Self` in `@def.Floating` | `fn with_precision(Self, Int32) -> Self` |
  | `@def.Floating::with_precision(x, p, @arithmetic.RoundingMode::ToNearestEven)` | `@def.Floating::with_precision(x, p)` |
  | `@def.Floating::with_precision(x, p, mode)` with another mode | the inherent `T::with_precision(x, p, mode)` of the concrete type |

- `bin_float`, `bin_float_checked`: the precision of a value is checked where the value is made ([#442](https://github.com/Luna-Flow/floating/issues/442); step S5 of [#438](https://github.com/Luna-Flow/floating/issues/438)). A precision outside `1..=binary_precision_max` was replaced by 1 in most constructors, accepted above the limit (later operations aborted), and aborted inside `BinFloat::from_string`. A value-returning constructor now aborts with a message naming the constructor, the range and the value; `from_string`, `from_hex` and the constructors of `BinFloatResult` return an `Err`.

  | before | after | note |
  | --- | --- | --- |
  | `BinFloat::from_int(3, precision=0)` is the value `4` at precision 1 | aborts | the same for `make`, `from_coefficient`, `from_double`, `from_float`, `zero`, `negative_zero`, `one`, `inf`, `nan`, `quiet_nan`, `signaling_nan` and `with_precision` |
  | a precision above `binary_precision_max` accepted | aborts | the check is on the constructors; operations on an existing value no longer build a context from an unchecked precision |
  | `BinFloat::from_string(s, precision=0)` aborted | `Err(DomainError)` | `from_hex` likewise, also for a precision above the limit |
  | `BinFloatResult::from_int(3, precision=0)` is `Ok` | `Err(DomainError)` | the four constructors of the checked tier |

- `bin_float`: the payload of a NaN is checked at construction and truncated only by conversions (step S6 of [#438](https://github.com/Luna-Flow/floating/issues/438), IEEE 754-2019 6.2.1 and 6.2.3). A NaN of precision `p` has `p - 2` payload bits.

  | before | after | note |
  | --- | --- | --- |
  | `quiet_nan(payload=wide)` accepted any width | aborts when the payload needs more than `p - 2` bits | `signaling_nan` also aborts below `p = 3`, where no signaling NaN exists |
  | `with_precision`, `from_double`, `from_hex` and every operation under a context copied the whole payload | the payload keeps its low `p - 2` bits | a signaling NaN whose payload does not survive becomes quiet; a context of precision 2 or less gives payload 0 |

- `decimal`: one rounding parameter per context, and it is an IEEE 754-2019 attribute ([#438](https://github.com/Luna-Flow/floating/issues/438), A2, N7, first step of A4). `DecimalContext` took two rounding parameters, `rounding` (the shared `@arithmetic.RoundingMode`) and `decimal_rounding`; finite results rounded by `decimal_rounding`, `rounding` only tagged infinities, and `rounding()` could report a mode that was not applied. A context now has one `rounding`, of the type `DecimalRoundingMode`, which has the five rounding-direction attributes of IEEE 754-2019 4.3 in the spelling of `BinaryRoundingMode`. The three GDA algorithms `HalfDown`, `Up` and `ZeroFiveUp` are not attributes of an IEEE decimal format: a context cannot select them any more (they stay in `decimal_gda`, and as working modes inside the library). The old variant names are removed without an alias.

  | before | after | note |
  | --- | --- | --- |
  | `DecimalRoundingMode::HalfEven` | `DecimalRoundingMode::RoundTiesToEven` | the type keeps its name; every old variant name stops compiling |
  | `DecimalRoundingMode::HalfUp` | `DecimalRoundingMode::RoundTiesToAway` | GDA `round-half-up` is IEEE `roundTiesToAway` |
  | `DecimalRoundingMode::Down`, `Ceiling`, `Floor` | `RoundTowardZero`, `RoundTowardPositive`, `RoundTowardNegative` | |
  | `DecimalRoundingMode::HalfDown`, `Up`, `ZeroFiveUp` | none | use `decimal_gda` (`GdaContext`) for these algorithms |
  | `DecimalContext::new(rounding=@arithmetic.RoundingMode::X)`, `try_new` | `DecimalContext::new(rounding=DecimalRoundingMode::Y)` | `AwayFromZero` has no counterpart |
  | `DecimalContext::new(decimal_rounding=m)`, `try_new` | `DecimalContext::new(rounding=m)` | the parameter `decimal_rounding` is removed |
  | `ctx.decimal_rounding()` | `ctx.rounding()` | `rounding()` returns `DecimalRoundingMode` |
  | `ctx.with_rounding(@arithmetic.RoundingMode::X)` | `ctx.with_rounding(DecimalRoundingMode::Y)` | |
  | `DecimalContext::decimal32()`, `decimal64()`, `decimal128()` | the same, with an optional `rounding~` | |
  | (new) | `DecimalContext::with_precision(Int)` | aborts outside `1..=decimal_precision_max` |
  | `Decimal::make(.., mode=@arithmetic.RoundingMode::X)`, `Decimal::with_precision(p, @arithmetic.RoundingMode::X)` | `mode=DecimalRoundingMode::Y` | the inherent forms take the package's own type |
  | `DecimalRoundingMode::from_arithmetic(m) -> DecimalRoundingMode`, `to_arithmetic` | `from_arithmetic(m) -> DecimalRoundingMode?`, `to_arithmetic` | `None` for `AwayFromZero` and for `RoundTiesToAway` respectively |
  | `DecimalContext::from_arithmetic_context`, the `_contextual` and `_checked` trait forms with `AwayFromZero` | `Err(domain_error)` | `AwayFromZero` is not an attribute of IEEE 754-2019 4.3 |

  The `Floating` trait still passes an `@arithmetic.RoundingMode` to `with_precision`; the implementation maps all five of its modes as before. `Decimal::to_bin_float` keeps its `@arithmetic.RoundingMode` parameter until the cross-radix conversions get their required precision. Data: the IEEE elementary oracle (`testdata/decimal/ieee/elementary_mpfr_oracle.json`) has 3,060 rows (was 4,896: the rows of the three removed algorithms are gone), and the rows of the three removed algorithms are removed from `pi_inverse.txt`, `huge_trig.txt` and the two `mpfr-decimal-random` files; they are regenerated by the generators once those emit IEEE contexts only (the next step of #438, A3).

- `decimal_gda`: constructors check where a value is made, `from_string` returns a `Result`, conversions to and from binary take a required precision and the rounding type of the radix of their result ([#438](https://github.com/Luna-Flow/floating/issues/438), items S5, S6, S8, N1, N4 for the GDA `Decimal`). Before, a precision below 1 was replaced by 1 without a word, a precision above the limit was never checked, a negative NaN payload was replaced by its absolute value and a payload of any width was stored; `to_bin_float` and `from_bin_float` took an optional precision that counted digits as bits (or bits as digits).

  | before | after | note |
  | --- | --- | --- |
  | `Decimal::zero(precision=0)` (also `one`, `negative_zero`, `nan`, `inf`, `quiet_nan`, `signaling_nan`, `from_int`, `from_bigint`, `from_double`, `from_float`, `make`, `with_precision`) | aborts, naming the function and the argument | the range is `1..=999999999`; no silent replacement by 1 |
  | `Decimal::quiet_nan(payload=-5N)` stored `5` | aborts | page 11: zero or a positive integer |
  | `Decimal::quiet_nan(payload=P, precision=p)` with more than `p - 1` digits | aborts | the payload is no larger than the coefficient less one digit; at precision 1 only the payload 0 |
  | `Decimal::inf(Sign::Negative)`, `inf(sign)` | `Decimal::inf(negative=true)`, `inf()` | one spelling with the other packages |
  | `Decimal::from_string(s, precision~) -> Decimal?` and `Decimal::parse(s, precision~) -> Result` | `Decimal::from_string(s, precision~) -> Result[Decimal, ArithmeticError]` | `parse` goes; `Err` for a malformed string, a precision outside the range and a NaN payload wider than `precision - 1` digits |
  | `GdaInterchange::from_hex(...) -> GdaInterchange?` | `-> Result[GdaInterchange, ArithmeticError]` | |
  | `Decimal::from_bin_float(x)` (precision of `x` taken as digits) | `Decimal::from_bin_float(x, precision=d)` | required, counts decimal digits |
  | `Decimal::from_bin_float(x, precision=d)` | `from_bin_float(x, precision=d, rounding=GdaRoundingMode::X)` | `rounding` defaults to `HalfEven`; new |
  | `x.to_bin_float()`, `x.to_bin_float(precision=p, mode=@arithmetic.RoundingMode::X)` | `x.to_bin_float(precision=p)`, `x.to_bin_float(precision=p, mode=@bin_float.BinaryRoundingMode::RoundTowardZero)` | required, counts bits; the rounding attributes of IEEE 754-2019 4.3.1, which add ties-to-away; aborts outside `1..=binary_precision_max` |
  | `Decimal::make(c, e, p, mode=@arithmetic.RoundingMode::X)`, `x.with_precision(p, @arithmetic.RoundingMode::X)` | `make(c, e, p, rounding=GdaRoundingMode::Y)`, `x.with_precision(p, GdaRoundingMode::Y)` | the eight modes of the context; `ToNearestEven` is `HalfEven`, `TowardZero` is `Down`, `TowardPositive` is `Ceiling`, `TowardNegative` is `Floor`, `AwayFromZero` is `Up` |

- `decimal`: `Decimal::from_string` returns a `Result` ([#438](https://github.com/Luna-Flow/floating/issues/438), item N1). It returned `Decimal?` while `parse` returned a `Result` with the reason; the two are one function now and `parse` is removed. No error message changed: the texts of the former `parse` stay, including the stored-range text.

  | before | after | note |
  | --- | --- | --- |
  | `Decimal::from_string(s, precision~) -> Decimal?` | `Decimal::from_string(s, precision~) -> Result[Decimal, ArithmeticError]` | `None` becomes `Err` with the reason; `Some(x)` becomes `Ok(x)` |
  | `Decimal::parse(s, precision~) -> Result[Decimal, ArithmeticError]` | `Decimal::from_string(s, precision~)` | `parse` is removed; the result and the messages are the same |

- `decimal`: the interchange decoders return a `Result` that says what was wrong, and `to_sci_string` and `to_eng_string` format a value ([#438](https://github.com/Luna-Flow/floating/issues/438), items N2 and the decoder half of N1). A text that was not interchange hex gave `None`; `to_sci_string(text, ctx)` parsed text under a context, a second job beside the first.

  | before | after | note |
  | --- | --- | --- |
  | `Decimal::from_interchange_hex(s, f)`, `from_interchange_hex_with_encoding(s, f, e)` returning `Decimal?` | `Result[Decimal, ArithmeticError]` | `Err` is a parse error that names the digits wanted and found, or the first character that is not a hexadecimal digit and its place; the length is checked first |
  | `DecimalInterchange::from_hex(s, f)`, `from_hex_with_encoding(s, f, e)` returning `DecimalInterchange?` | `Result[DecimalInterchange, ArithmeticError]` | the same text rules and errors; the types of `decimal_gda` already returned a `Result` |
  | `Decimal::to_sci_string(text, ctx) -> (String, DecimalFlags)`, `to_eng_string(text, ctx)` | `v.to_sci_string() -> String`, `v.to_eng_string()` | for text under a context: `let (v, flags) = Decimal::from_string_ctx(text, ctx)` first; the names and the result are those of `decimal_gda` |

  No bit pattern of the right length is refused: a non-canonical declet or coefficient still decodes to the value IEEE 754-2019 3.5 gives it, as before.

- `decimal_gda`: `make` keeps the exponent it is given ([#438](https://github.com/Luna-Flow/floating/issues/438), item S7), and the optional rounding argument of the value-level functions is spelled `mode?` as in `bin_float` and `decimal`. `make` always stripped trailing zeros, so `make(1200, 0, 34)` was `1.2E+3` and `make(0, 5, 5)` was `0` (a `Decimal` built any other way keeps its exponent: `from_int(1200)` and `from_string("1200")` were `1200`). The rounding argument of `make` and `from_bin_float` was spelled `rounding?` in the previous change of this release, which was not released: no migration row for that.

  | before | after | note |
  | --- | --- | --- |
  | `Decimal::make(1200N, 0, 34)` printed `1.2E+3` | `1200` | `x.normalized()` or `x.trim()` for the reduced member |
  | `Decimal::make(100N, 0, 5)` printed `1E+2` | `100` | |
  | `Decimal::make(0N, 5, 5)` printed `0` | `0E+5` | the given exponent |
  | `Decimal::make(1000000N, 0, 3)` printed `1E+6` | `1.00E+6` | the rounded coefficient is not reduced; the value is the same |
  | `Decimal::make(c, e, p, rounding=...)`, `from_bin_float(x, precision=d, rounding=...)` | `mode=...` | one spelling for the optional rounding of value-level functions |

- `decimal`: a context is an IEEE 754-2019 format ([#438](https://github.com/Luna-Flow/floating/issues/438), A3 and A4 for `decimal`). `DecimalContext` is built from the precision and `e_max`; `e_min` is `1 - e_max` (3.3) and is not a parameter. The options that no IEEE format has are gone: `clamp` (every finite result is a member of the format, so exponents above `e_max - p + 1` are always folded down), `extended` (the X3.274 subset of GDA appendix A), `tininess` (7.5: decimal formats detect tininess before rounding), `clamp_fold` (the fold of a zero `quantize` result is the rule now), and `exact()` (precision 0 is not a format). A context without `e_max` has the range `max(999999, 1000 * precision)` (3.7), so `DecimalContext::new()` is `(34, 999999)` and the certified elementary functions run on it. The old names have no alias.

  | before | after | note |
  | --- | --- | --- |
  | `DecimalContext::new(precision, e_min, e_max, ..)` | `DecimalContext::new(precision, e_max)` | `e_min` is `1 - e_max`: a pair with another `e_min` has no counterpart; `e_max` is `1..=999999999` (was `0..=`) |
  | `DecimalContext::new()` (range +-999999999) | `DecimalContext::new()` is `(34, 999999)`; `new(e_max=999999999)` for the old `e_max` | `decimal_implementation_e_min` is now `-999999998` (was `-999999999`) |
  | `clamp=true` in presets | (nothing) | `decimal32()`, `decimal64()`, `decimal128()` are unchanged |
  | `clamp=false` (the default) | none | results with `q > e_max - p + 1` are folded down; the NaN payload has `precision - 1` digits |
  | `extended=false` | none | use `decimal_gda` for the GDA subset |
  | `tininess=..`, `with_tininess`, `DecimalContext::tininess`, `DecimalTininessDetection` | none | tininess is detected before rounding |
  | `with_clamp_fold`, `clamp_fold` | none | a zero is always folded |
  | `DecimalContext::exact()` | none | a context of `digits(a) + digits(b)` digits makes `mul_ctx` exact; there is no replacement for exact addition |
  | `ctx.clamp()`, `ctx.extended()`, `ctx.is754version2019()`, `ctx.ieee754()` | none | |
  | (new) | `DecimalContext::with_e_max(Int)` | aborts outside `1..=999999999` |
  | `DecimalContext::from_arithmetic_context(c)` with `clamp` | `clamp` ignored; `e_min` given must be `1 - e_max` (alone: `e_max = 1 - e_min`) else `Err` | |

  The flag `lost_digits` (only the subset mode raised it) is never raised any more; it goes with the other GDA flags. Data: every row table, the random corpus and the generators use legal contexts only (`tools/corpus_common.py` `check_ieee_decimal_context` is the one definition that the generators and the library share): `pi_inverse.txt` 9,691 rows, the pm1, rcp, exp_range and atan2pi tables regenerated, `mpfr-decimal-random.txt` 468 rows (its fixed-findings file `mpfr-decimal-random-regressions.txt` is empty: its rows used contexts that no format has, and the findings have white-box tests), the `tininess` column of the row format is kept and is always `b`. White-box and consistency tests of non-IEEE behaviour were deleted (the list is in the pull request).

- `ball_float` and `ball_float_checked`: the operations that duplicated another or belonged to a scalar interface are removed ([#438](https://github.com/Luna-Flow/floating/issues/438), items B4, A6 and the duplicates of B1). `BallFloat` no longer implements `@def.Floating`: `is_zero` meant "contains 0", `is_nan` meant "empty", `sign` aborted on the empty set and `with_precision` ignored its rounding mode, so generic scalar code gave answers that were true of no single number. The five `@arithmetic` trait implementations (`Contains`, `Overlaps`, `MaybeEq`, `DefinitelyLt`, `DefinitelyLe`) stay and are the only spelling of those relations; their results on an empty operand (false) differ from `disjoint`, `precedes` and `strictly_precedes` (true, IEEE 1788-2015 Table 10.4), which the API page now says. A name that had one meaning is not reused: `BallFloat::sign` is gone and a later `sign` is the interval function of Table 9.1.

  | before | after | note |
  | --- | --- | --- |
  | `x.add_ctx(y, ctx)`, `sub_ctx`, `mul_ctx`, `div_ctx` | `(x + y).apply_ctx(ctx)` (the operators) | no use outside the package |
  | `x.exp_ctx(ctx)`, `x.ln_ctx(ctx)` | `x.with_precision(ctx.precision() + 32).exp_interval().apply_ctx(ctx)` (and `ln_interval`) | same work precision; no use outside the package |
  | `@def.is_zero(x)`, `@def.is_nan(x)`, `@def.is_finite(x)`, `@def.is_infinite(x)`, `@def.Floating::{classify, sign, precision, with_precision, normalized}` on a `BallFloat` | `x.is_empty()`, `x.is_common_interval()`, `x.is_entire()`, `x.contains(zero)`, `x.precision()`, `x.with_precision(p)`, `x.normalized()` | 3 uses in tests |
  | `x.classify()` | none | `Floating` is not implemented by intervals |
  | `x.sign()` returning a `Sign` (aborted on Empty) | `x.sign()` returning an interval | the `sign` of IEEE 1788-2015 Table 9.1 (see the integer functions entry below); `Sign` of a point is `x.sign().lower_bound().sign()` when `x` does not contain 0 |
  | `x.with_precision(p, mode)`, `BallFloatResult::with_precision(p, mode)` | `x.with_precision(p)` | the mode was ignored: endpoints always round outward |
  | `x.separated_from(y)` | `x.disjoint(y)` | duplicate (empty operand: both true) |
  | `x.is_bounded()` | `x.is_common_interval()` | duplicate |
  | `x.contains_zero()` | `x.contains(BinFloat::zero(precision=x.precision()))` | one use outside the package (`decimal`) |
  | `x.overlaps(y)`, `x.maybe_eq(y)` | `@arithmetic.Overlaps::overlaps(x, y)`, `@arithmetic.MaybeEq::maybe_eq(x, y)`; the IEEE negation is `not x.disjoint(y)` for non-empty operands | the trait implementations stay |
  | `x.definitely_lt(y)`, `x.definitely_le(y)` | `@arithmetic.DefinitelyLt::definitely_lt(x, y)`, `@arithmetic.DefinitelyLe::definitely_le(x, y)` | the trait implementations stay |
  | `x.definitely_gt(y)` | `@arithmetic.DefinitelyLt::definitely_lt(y, x)` | |
  | `BallFloatResult::pow_nat(n)` | `pow_int(n)` | `PowNatChecked` stays on `BallFloat::pow_nat_checked` |
  | `BallFloatResult::flat_map(f)` (deprecated) | `bind(f)` | |

- `ball_float` and `ball_float_checked`: the operations are named as in IEEE 1788-2015 ([#438](https://github.com/Luna-Flow/floating/issues/438), item B1). The suffix `_interval` goes from the 26 elementary functions and from their `try_` forms (on `BallFloat` and on `BallFloatDecorated`), which makes the plain tier spell what the checked tier (`BallFloatResult::exp`, `sin`, `ln`, `log1p`, `pow`) already did; `ln` and `log1p` keep the spelling of `BinFloat`, as the naming rules list them as exceptions. The names of Table 9.1 (`sqr`, `recip`, `min`, `max`), 10.5.2 (`entire`), Table 10.3 (`strict_less`, `strict_precedes`) and 10.6.4 (`overlap`) replace the library's own spellings, and the point-membership method `contains` (which collided with the inclusion of `Contains::contains`) becomes `is_member` (10.6.3). The long observer names (`lower_bound`, `upper_bound`, `midpoint`, `width`, `radius`, `magnitude`, `mignitude`) stay as documented exceptions. No alias is kept.

  | before | after | note |
  | --- | --- | --- |
  | `exp_interval`, `try_exp_interval` | `exp`, `try_exp` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `exp2_interval`, `try_exp2_interval` | `exp2`, `try_exp2` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `exp10_interval`, `try_exp10_interval` | `exp10`, `try_exp10` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `expm1_interval`, `try_expm1_interval` | `expm1`, `try_expm1` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `ln_interval`, `try_ln_interval` | `ln`, `try_ln` | strict rule would be `log`; kept as `BinFloat`.  `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `log2_interval`, `try_log2_interval` | `log2`, `try_log2` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `log10_interval`, `try_log10_interval` | `log10`, `try_log10` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `log1p_interval`, `try_log1p_interval` | `log1p`, `try_log1p` | strict rule would be `logp1`; kept as `BinFloat`.  `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `sin_interval`, `try_sin_interval` | `sin`, `try_sin` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `cos_interval`, `try_cos_interval` | `cos`, `try_cos` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `tan_interval`, `try_tan_interval` | `tan`, `try_tan` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `sinpi_interval`, `try_sinpi_interval` | `sinpi`, `try_sinpi` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `cospi_interval`, `try_cospi_interval` | `cospi`, `try_cospi` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `tanpi_interval`, `try_tanpi_interval` | `tanpi`, `try_tanpi` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `asin_interval`, `try_asin_interval` | `asin`, `try_asin` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `acos_interval`, `try_acos_interval` | `acos`, `try_acos` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `atan_interval`, `try_atan_interval` | `atan`, `try_atan` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `atan2_interval`, `try_atan2_interval` | `atan2`, `try_atan2` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `sinh_interval`, `try_sinh_interval` | `sinh`, `try_sinh` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `cosh_interval`, `try_cosh_interval` | `cosh`, `try_cosh` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `tanh_interval`, `try_tanh_interval` | `tanh`, `try_tanh` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `asinh_interval`, `try_asinh_interval` | `asinh`, `try_asinh` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `acosh_interval`, `try_acosh_interval` | `acosh`, `try_acosh` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `atanh_interval`, `try_atanh_interval` | `atanh`, `try_atanh` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `pow_interval`, `try_pow_interval` | `pow`, `try_pow` | `BallFloat` and `BallFloatDecorated` (the decorated type has no `try_` forms) |
  | `sqrt_interval` | `sqrt` | no `try_` form (a directed square root cannot fail) |
  | `square`, `reciprocal` | `sqr`, `recip` | `BallFloat`, `BallFloatDecorated` |
  | `minimum`, `maximum` | `min`, `max` | `BallFloat`, `BallFloatDecorated` |
  | `whole` | `entire` | `BallFloat`, `BallFloatResult` |
  | `strictly_less`, `strictly_precedes` | `strict_less`, `strict_precedes` | `BallFloat`, `BallFloatDecorated` |
  | `overlap_state` | `overlap` | `BallFloat`, `BallFloatDecorated` |
  | `x.contains(point)` | `x.is_member(point)` | `BallFloat`, `BallFloatDecorated`; `@arithmetic.Contains::contains(x, y)` (inclusion) is unchanged |
  | `BallFloatResult::pow_int(n)` | `BallFloatResult::pown(n)` | the plain tier already has `pown`; `PowIntChecked` keeps its trait name |

- `ball_float` and `ball_float_checked`: `OverlapState` follows Table 10.7 of IEEE 1788-2015 and the checked tier has the operations it lacked ([#438](https://github.com/Luna-Flow/floating/issues/438), item B5). `Undefined`, which was not one of the 16 states, goes: the decorated `overlap` has no value for NaI (11.7.2) and returns an option. Also added, not breaking: `Decoration` derives `Compare` in the propagation order (the comparisons of decorations of 11.5.3), and `BallFloatResult` gets `sqrt`, `sqr`, `recip`, `min`, `max`, `fma`, `intersection`, `convex_hull`, `cancel_plus` and `cancel_minus`.

  | before | after | note |
  | --- | --- | --- |
  | `OverlapState::OverlapsState` | `OverlapState::Overlaps` | Table 10.7 `overlaps` |
  | `OverlapState::EqualIntervals` | `OverlapState::Equals` | `equals` |
  | `OverlapState::ContainsInterval` | `OverlapState::Contains` | `contains` |
  | `OverlapState::Undefined` | none | not a state; see the next row |
  | `BallFloatDecorated::overlap(x, y) -> OverlapState`, `Undefined` for NaI | `-> OverlapState?`, `None` for NaI | `Some(state)` otherwise |

- `decimal_gda_checked`: the right operand of a binary operation is a pipeline, one set of exits, every operation that returns a number has a method ([#438](https://github.com/Luna-Flow/floating/issues/438), item S9). The right operand was a plain `Decimal`, so the conditions and the trap of the computation that produced it could not reach the result; the exits were `is_trapped` and `trapped_signal` where `DecimalChecked` has `is_ok`, `is_err`, `error` and `result`. The result context is the one of the left pipeline; the conditions of the right pipeline join `raised` and the status, and its trap short-circuits (new `GdaOutcome::absorb` and `GdaOutcome::completed` in `decimal_gda`).

  | before | after | note |
  | --- | --- | --- |
  | `p.add(x)` with `x : Decimal` (also `subtract`, `multiply`, `divide`, `power`, `quantize`, `remainder`, `next_toward`) | `p.add(q)` with `q : GdaDecimalChecked` | `GdaDecimalChecked::from_decimal(x, ctx)` to wrap a value |
  | `p.fma(b, c)` with two `Decimal` | `p.fma(b, c)` with two pipelines | |
  | `p.is_trapped()` | `p.is_err()` | `is_ok()` is the opposite |
  | `p.trapped_signal()` | `p.error()` | `Some(signal)` for a trapped pipeline |
  | (new) | `p.result()` | `Ok(value)` or `Err(signal)` |
  | `GdaDecimalChecked::parse(s, ctx)` | `GdaDecimalChecked::to_number(s, ctx)` | the GDA name |
  | (new) | `divide_integer`, `remainder_near`, `rescale`, `round_to_integral_exact`, `round_to_integral_value`, `scaleb`, `shift`, `rotate`, `logb`, `logical_and`, `logical_or`, `logical_xor`, `logical_invert`, `max`, `min`, `max_magnitude`, `min_magnitude`, `compare`, `compare_signal` | the 19 operations that had no method; the functions that return a string, a boolean or an integer stay on `value()` and `context()` |
  | priority order of the trapped signal | `InvalidOperation`, `DivisionByZero`, `Overflow`, `Underflow`, `Subnormal`, `Inexact`, `Rounded`, `Clamped`, `LostDigits` | the nine signals (previous change) |

- `ball_float`: `==` is the `equal` of IEEE 1788-2015, and `from_int` defaults to 53 bits ([#438](https://github.com/Luna-Flow/floating/issues/438), items S3 and S8). `BallFloat` derived `Eq`, which compared the representation (endpoints, precision tag): the same interval at two precisions, or with differently represented endpoints, was not `==`, and `compare`-style reasoning about intervals failed. `==` is now set equality (Table 10.3, 12.12.9; two empty intervals are equal); equality of the datum (12.3) is `identical`. On `BallFloatDecorated` `==` is the `equal` relation: false when either operand is NaI (so NaI is not equal to itself, as NaN is not) and decorations are ignored. `BallFloat::from_int` and `from_coefficient` defaulted to 16 bits while every other constructor defaults to 53 (24 for floats).

  | before | after | note |
  | --- | --- | --- |
  | `x == y` on `BallFloat` (representation, precision tag included) | `x.identical(y)` | `==` is now `x.equal(y)`, the set equality |
  | `x == y` on `BallFloatDecorated` (representation) | `x.identical(y)` | `==` is now false when either is NaI, decorations ignored |
  | `x.set_equal(y)` | `x == y`, or `x.equal(y)` | `BallFloat` and `BallFloatDecorated`; the old derived `equal` (representation) is gone with it |
  | `BallFloat::from_int(n, precision=53)`, `from_coefficient(c)`, `BallFloatResult::from_int`, `from_coefficient` without `precision` | the same call, precision 53 | was 16; pass `precision=16` for the old enclosure |

- `ball_float`: the observers are total and follow IEEE 1788-2015 12.12.8 ([#438](https://github.com/Luna-Flow/floating/issues/438), item B2). `midpoint` and `radius` no longer abort on the empty set or on a half-bounded interval; `width`, `magnitude`, `mignitude` return NaN, not 0, for the empty set; `BallFloat::try_new` returns an error where `new` aborts. The exact center and half-width of the ball view are no longer public.

  | before | after | note |
  | --- | --- | --- |
  | `x.midpoint()` on Empty or a half-bounded interval: abort | NaN; the largest finite number of the precision (widest exponent range) with the sign of the unbounded side | 0 for Entire, as before; `midpoint_ctx` takes the format |
  | `x.radius()` on Empty or an unbounded interval: abort | NaN; `+inf` | |
  | `x.radius()` on a bounded interval: the half-width around the exact center | the larger of `midpoint - lower` and `upper - midpoint`, rounded up | see Fixed ([#477](https://github.com/Luna-Flow/floating/issues/477)); equal to the old value when the center is representable |
  | `x.radius_extended()` | `x.radius()` | the `+inf` for an unbounded interval is kept; Empty is NaN, not 0 |
  | `x.center()` | `x.midpoint()` | the exact center is no longer public; `midpoint` is the center rounded to nearest |
  | `x.width()`, `x.magnitude()`, `x.mignitude()` on Empty: 0 | NaN | 12.12.8 |
  | `BallFloat::new(c, r)` aborting on a non-finite or negative argument | `BallFloat::try_new(c, r)` returns `Err` | `new` still aborts |

- `ball_float`: `BallContext` is a binary format of IEEE 754-2019 3.3, and a precision is checked where a value is made ([#438](https://github.com/Luna-Flow/floating/issues/438), items A4 and S5, [#442](https://github.com/Luna-Flow/floating/issues/442)). `e_min` is derived (`1 - e_max`), not a parameter; the pair is validated by `BinaryContext::try_new`, so the two packages share one definition of a format and the precision has the upper limit `binary_precision_max` (268,435,456) that `BallContext` lacked (`ctx.precision + 32` wrapped negative near `Int32::MAX`). The default range of a context given a precision alone is the implementation range of `bin_float`, as for `BinaryContext`, not binary64. A precision below 1 was replaced by 1 silently in the constructors, in `with_precision` and in `BallFloat::empty` and `entire`: it now aborts, and the `try_` constructors and the checked tier return an error. The package also stops converting `@arithmetic.RoundingMode` internally and uses `BinaryRoundingMode` directly.

  | before | after | note |
  | --- | --- | --- |
  | `BallContext::new(precision~, e_min~, e_max~)`, `try_new` | `BallContext::new(precision~, e_max?)`, `try_new` | `e_min()` is `1 - e_max`; the default `e_max` is `@bin_float.binary_implementation_e_max`; `e_max >= 1` |
  | `BallContext::new()` (binary64 range) | `BallContext::binary64()` for that range | `new()` is precision 53 with the implementation range |
  | `BallContext::new(precision=4, e_min=-2, e_max=10)` and other pairs with `e_min != 1 - e_max` | none | no format has them (IEEE 754-2019 3.3); a test that needs `e_min = -2` uses `e_max=3` |
  | none | `with_precision(Int32)`, `with_e_max(Int32)`, `binary16()`, `binary128()` | additive |
  | `BallFloat::from_bounds(lo, hi, precision=0)` (also `exact`, `empty`, `entire`, `from_int`, `new`, `with_precision`) building precision 1 | aborts naming `1..=binary_precision_max`; `try_from_bounds`, `try_exact`, `try_from_double`, `try_from_float` and `BallFloatResult::*` return `Err` | no silent replacement |
  | precision above `binary_precision_max` accepted | aborts or `Err` | |

- `ball_float` and `ball_float_checked`: the six integer functions of IEEE 1788-2015 Table 9.1, `sign`, `ceil`, `floor`, `trunc`, `round_ties_to_even` and `round_ties_to_away`, on `BallFloat`, `BallFloatDecorated` and `BallFloatResult` ([#257](https://github.com/Luna-Flow/floating/issues/257), item B6). The ITF1788 gate runs the 143 corpus cases of these functions in a new `integer-functions` phase (4,656 to 4,799 strict cases). A decorated result is the strongest decoration of 11.2 (11.6 note 3) combined with the input decoration by the min-rule: `def` when the function is not constant on the box, `dac` when it is constant but the box contains a point where the function is discontinuous on the real line, `com` otherwise.

  | before | after | note |
  | --- | --- | --- |
  | `x.sign()` returning a `Sign` (removed earlier in this release) | `x.sign()` returning an interval inside [-1, 1] | Table 9.1 |
  | none | `ceil`, `floor`, `trunc`, `round_ties_to_even`, `round_ties_to_away` | `BallFloat`, `BallFloatDecorated`, `BallFloatResult`; exact, no rounding, no `try_` form |

- `ball_float` and `ball_float_checked`: reverse multiplication and two-output division of IEEE 1788-2015 10.5.4 and 10.5.5, `mul_rev` and `mul_rev_to_pair`, on `BallFloat`, `BallFloatDecorated` and `BallFloatResult` ([#231](https://github.com/Luna-Flow/floating/issues/231), item B6). `mul_rev_to_pair(b, c)` returns the closures of the (zero, one or two) connected components of `c /set b`, ordered; the decorated version follows 12.12.3. `mul_rev(b, c, x?)` is the hull of `c /set b` inside the prior `x`, taken of the set itself, so a prior that only touches an unattained end (`x = [-1, 0]` against `(0, 1]`) gives Empty; its decorated version is the trivial one of 11.7.1. The ITF1788 gate runs the 533 corpus cases of `mulRev`, `mulRevTen` and `mulRevToPair` in a new `multiplicative-reverse` phase (4,799 to 5,332 strict cases; the `reverse` phase keeps 1,300 unsupported).

  | before | after | note |
  | --- | --- | --- |
  | none | `b.mul_rev_to_pair(c)`, `b.mul_rev(c, x?)` | `BallFloat`, `BallFloatDecorated`, `BallFloatResult` (the checked pair is a pair of wrappers); no `try_` form, no input fails |

- `decimal_gda`: the plain operators are the free functions in a private working context ([#438](https://github.com/Luna-Flow/floating/issues/438), items S1 and S2). `+`, `-`, `*`, `/` and `sqrt` run `add`, `subtract`, `multiply`, `divide` and `sqrt` with the larger precision attribute of the operands, half-even rounding, the extended rules, no clamp, no traps and a private exponent range (largest adjusted exponent 2,147,483,646, smallest exponent -2,147,483,645). The result is the cohort member GDA prescribes, not the shortest one, and `*` rounds to the precision (it was exact). `Decimal::sqrt` returns a `Decimal` (NaN for a negative operand) and `Decimal::div_checked` is removed; `DivChecked::div_checked` and `sqrt_checked` stay. Equality compares values, so `x + 0 == x` and `x * 1 == x` hold for every stored finite value (the stored range is in the next entry).

  | before | after | note |
  | --- | --- | --- |
  | `1.10 + 3.50` prints `4.6` | prints `4.60` | `+` and `-` keep the smaller exponent |
  | `1.50 / 0.5` prints `3` | prints `3.0` | preferred exponent is the difference of the exponents |
  | `1.10 * 2.20` prints `2.4200` | `2.4200` | `*` adds the exponents; a product of more than `P` digits is now rounded to `P` |
  | `1E+1 + 1E-1000000000` exact sum | `P` digits, half-even | `+` is rounded to the precision, as GDA says |
  | `x.sqrt() : Result[Decimal, ArithmeticError]` | `x.sqrt() : Decimal`, NaN for negative | `Decimal::sqrt_checked` keeps the `Result` |
  | `x.div_checked(y)` | `x / y` (infinity or NaN) or `divide(x, y, ctx)` with a trapping context | the method is removed |
  | smallest result exponent `-2147483648` | `-2147483645` | the working range is a context |

- `ball_float` and `ball_float_checked`: the reverse functions `sqr_rev`, `abs_rev`, `pown_rev` and `cosh_rev` of IEEE 1788-2015 Table 10.1, on `BallFloat`, `BallFloatDecorated` and `BallFloatResult` ([#230](https://github.com/Luna-Flow/floating/issues/230), item B6). Each is the hull of `{ x in x | f(x) in c }` for the optional prior `x` (default Entire), taken of the set itself, with the trivial decoration of 11.7.1 on the decorated forms; `pown_rev(c, p, x?)` takes the power before the prior. A negative power excludes 0, and a piece that ends at the unattained limit 0 is open there. The ITF1788 gate runs the 360 corpus cases of `sqrRev`, `absRev`, `pownRev`, `coshRev` and their `Bin` forms in a new `algebraic-reverse` phase (5,332 to 5,692 strict cases; the `reverse` phase keeps 940 unsupported).

  | before | after | note |
  | --- | --- | --- |
  | none | `c.sqr_rev(x?)`, `c.abs_rev(x?)`, `c.pown_rev(p, x?)`, `c.cosh_rev(x?)` | `BallFloat`, `BallFloatDecorated`, `BallFloatResult`; no `try_` form, no input fails |

- `decimal`, `decimal_checked`: the package exports the operations of IEEE 754-2019 only, and `DecimalFlags` has the flags of 7.2 to 7.6 ([#438](https://github.com/Luna-Flow/floating/issues/438), N7, the strict step). The General Decimal Arithmetic operations that IEEE has no counterpart for leave; `decimal_gda` keeps them. `DecimalFlags` is `inexact`, `underflow`, `overflow`, `division_by_zero`, `invalid_operation` and `not_computed` (added; no operation raises it yet). A text that is not a number, a context an elementary function does not support and `0/0` raise `invalid_operation`. The inherent `normalized` stays: `x.normalized()` does not resolve through the `@def.Floating` trait with dot syntax. The text row format of the decimal corpora is `mpfr-decimal-random-v2`: columns `id op rounding precision emax a b n expected flags`, flags a subset of `xouvz`.

  | before | after | note |
  | --- | --- | --- |
  | `x.plus_ctx(ctx)` | `x.apply_ctx(ctx)` | the rounding of one operand into the context |
  | `x.minus_ctx(ctx)` | `x.neg().apply_ctx(ctx)` or `Decimal::zero().sub_ctx(x, ctx)` | the first keeps the cohort and the zero sign rule of `negate`, the second is the subtraction |
  | `x.reduce_ctx(ctx)`, `x.trim()` | `x.apply_ctx(ctx).0.normalized()` | IEEE 754-2019 has no operation that strips trailing zeros |
  | `x.rescale_ctx(n, ctx)` | `x.quantize_ctx(Decimal::make(1, n, 1), ctx)` | the invalid-operand rules of `quantize` apply |
  | `x.divide_integer_ctx(y, ctx)`, `x.remainder_trunc_ctx(y, ctx)` | none (use `decimal_gda`) | IEEE 754-2019 has `remainder_ctx` (round to nearest) and `to_integral_*` |
  | `logical_and_ctx`, `logical_or_ctx`, `logical_xor_ctx`, `logical_invert_ctx`, `shift_ctx`, `rotate_ctx` | none (use `decimal_gda`) | digit-wise operations of GDA |
  | `DecimalChecked::plus`, `minus`, `reduce` | `apply`, or none | as above |
  | `flags.rounded()`, `subnormal()`, `clamped()`, `lost_digits()` | none | `inexact` and `underflow` carry the IEEE meaning; `x.is_subnormal(ctx)` tests a value |
  | `flags.conversion_syntax()`, `division_impossible()`, `division_undefined()`, `invalid_context()` | `flags.invalid_operation()` | conditions of the invalid operation signal |
  | `flags.contains(DecimalSignal::X)`, `DecimalSignal` | the accessor of the flag | `contains` and `DecimalSignal` go |
  | `flags.has_error()` | the same name, `invalid_operation \|\| not_computed \|\| division_by_zero` | |
  | `mpfr-decimal-random-v1` rows `id op rounding precision emin emax clamp tininess a b n expected flags` | `mpfr-decimal-random-v2` rows `id op rounding precision emax a b n expected flags` | the flag letters `r`, `s`, `c` go |

- `decimal_gda`: a finite `Decimal` can only hold a value of the stored range ([#438](https://github.com/Luna-Flow/floating/issues/438)). The exponent of its least digit is at least `gda_value_e_tiny` (-2,147,483,645) and its adjusted exponent is at most `gda_value_e_max` (2,147,483,646): the range of the working context of the plain operators, so `x + 0 == x`, `x * 1 == x` and `x - 0 == x` hold for every stored finite value. `Decimal::make` aborts, and the new `Decimal::try_make` and `Decimal::from_string` return `Err` of the domain-error kind, naming both limits and the exponent, for a value outside the range (a zero included), after the rounding to the precision; `from_string` no longer folds such a text into an infinity or a zero (read it with `to_number` and a context for that). Operations are unchanged: they overflow and underflow by the rules of their context, and `with_precision` at the top follows the GDA Overflow rule of the working range, so it never returns a finite value above the limit.

  | before | after | note |
  | --- | --- | --- |
  | `Decimal::make(1N, 2147483647, p)` stores `1E+2147483647` | aborts; `try_make` returns `Err` | adjusted exponent above `gda_value_e_max` |
  | `Decimal::make(1N, -2147483648, p)` stores `1E-2147483648` | aborts; `try_make` returns `Err` | exponent below `gda_value_e_tiny` |
  | `from_string("1e2147483647")` is `1E+2147483647` | `Err` (domain error) | also `9.99E+2147483647` |
  | `from_string("1e3000000000")` is `inf` | `Err` (domain error) | `to_number` with a context overflows |
  | `from_string("1e-3000000000")` is `0E-2147483648` | `Err` (domain error) | `to_number` with a context underflows |
  | `from_string("1E-2147483646")` and `("0E-2147483648")` store | `Err` (domain error) | a zero is rejected like any other value |
  | the four exponents that could be stored, -2147483648 to -2147483646 and an adjusted exponent of 2147483647 | no longer storable | the limits are the constants `gda_value_e_tiny` and `gda_value_e_max` |
  | `Decimal::with_precision` of the largest values at the top could give a finite value above 2,147,483,646 | `inf`, or the largest finite value of the width in the modes toward zero | GDA Overflow rule of the working range |

- `decimal`: the values of the package check where they are made, `make` keeps the cohort member it is given, `inf` takes a flag, `sqrt` returns a value, and `identical` compares representations ([#438](https://github.com/Luna-Flow/floating/issues/438), S5, S6, S7, N4, S2). The precision label of a value names a format a context could have (`1..=999999999`); a constructor that returns a `Decimal` aborts on any other precision (`"Decimal::from_int: precision must be within 1..=999999999"`) where the silent repair `max(1, p)` used to hide it, and an oversized label no longer survives to fail later in `sqrt`. The payload of a NaN is the trailing significand field: `quiet_nan` and `signaling_nan` abort on a negative payload or one of more than `precision - 1` digits; a conversion to a narrower format keeps the low digits. `Decimal::make(c, q, p)` keeps the exponent `q` when `c` has at most `p` digits and rounds a longer coefficient to `p` digits without reducing it; it used to strip trailing zeros before and after rounding.

  | before | after | note |
  | --- | --- | --- |
  | `Decimal::zero(precision=0)`, `from_int(3, precision=2_000_000_000)`, `quiet_nan(precision=-1)` (and `one`, `negative_zero`, `inf`, `nan`, `signaling_nan`, `from_bigint`, `from_double`, `from_float`, `make`, `with_precision`, `from_bin_float`) | abort, naming the function and the range | the range is `1..=decimal_precision_max` |
  | `Decimal::quiet_nan(payload=P, precision=p)` with a negative `P` or more than `p - 1` digits | aborts | `set_payload` still returns `+0` for a payload that does not fit (IEEE 754-2019 9.7); a conversion keeps the low digits |
  | `Decimal::make(100N, 0, 5)` is `1E+2` | `100` | the coefficient keeps the exponent given |
  | `Decimal::make(0N, 5, 5)` is `0` | `0E+5` | |
  | `Decimal::make(1000000N, 0, 3)` is `1E+6` | `100E+4` | rounded to exactly `p` digits, not reduced |
  | `Decimal::inf(Sign::Negative, precision~)`, `inf(x.sign())` | `Decimal::inf(negative=true, precision~)`, `inf(negative=x.is_negative())` | `inf()` is `+inf` |
  | `x.sqrt() -> Result[Decimal, ArithmeticError]` | `x.sqrt() -> Decimal` | a negative operand gives NaN; `sqrt_checked` and `sqrt_ctx` are unchanged |
  | (none) | `x.identical(y)` | every field of the representation, including the precision label |

- `decimal_gda`: `Decimal::identical` is the relation "the same datum" ([#438](https://github.com/Luna-Flow/floating/issues/438)), as `BallFloat::identical`.

  | before | after | note |
  | --- | --- | --- |
  | none | `x.identical(y)` | the same datum: class, sign, coefficient, exponent (NaN: payload and kind) and precision attribute; `compare_total(x, y, ctx)` is 0 and the attributes are equal exactly then |

- `ball_float` and `ball_float_checked`: the reverse functions `sin_rev`, `cos_rev` and `tan_rev` of IEEE 1788-2015 Table 10.1, on `BallFloat`, `BallFloatDecorated` and `BallFloatResult` ([#230](https://github.com/Luna-Flow/floating/issues/230), item B6). Each is the hull of `{ x in x | f(x) in c }` for the optional prior `x` (default Entire), with the trivial decoration of 11.7.1 on the decorated forms. The preimage is a periodic union of intervals; with a bounded prior only the first and last piece that meet it are evaluated, so the cost does not depend on how many periods the prior spans. Every comparison of a prior end with a piece end is decided exactly (a piece end is irrational unless it is 0, which is tested exactly) and an end written to the result is the exact directed rounding of the piece end, by raising the working precision until the enclosure decides; the cap is 12 doublings and an end of the prior beyond the working-precision limit of the forward trigonometric functions is kept. The ITF1788 gate runs the 136 corpus cases of `sinRev`, `cosRev`, `tanRev` and their `Bin` forms in a new `trigonometric-reverse` phase (5,692 to 5,828 strict cases; the `reverse` phase keeps 804 unsupported).

  | before | after | note |
  | --- | --- | --- |
  | none | `c.sin_rev(x?)`, `c.cos_rev(x?)`, `c.tan_rev(x?)` | `BallFloat`, `BallFloatDecorated`, `BallFloatResult`; no `try_` form, no input fails |

- `decimal`: the plain operators are the `_ctx` operations in a private working context ([#438](https://github.com/Luna-Flow/floating/issues/438), S1, S2; closes [#548](https://github.com/Luna-Flow/floating/issues/548), [#549](https://github.com/Luna-Flow/floating/issues/549) and [#553](https://github.com/Luna-Flow/floating/issues/553)). `+`, `-`, `*`, `/` and `sqrt` compute `add_ctx`, `sub_ctx`, `mul_ctx`, `div_ctx` and `sqrt_ctx` in the format of the larger operand precision, round half even, with the storage range of a value (largest adjusted exponent 2,147,483,646, smallest exponent -2,147,483,645) and no fold, flags dropped; the separate implementations (`add_decimal_impl`, `mul_decimal_impl`, `div_decimal_impl`, `plain_sticky_sum_result`) are deleted. The results now carry the cohort member of IEEE 754-2019 5.4.1 and 5.2, and the product is rounded. Three defects of the old operators are gone with them: a finite value plus or minus zero was NaN when its exponent was more than 2,000,000,000 away from the zero's (`1E2147483646 + 0`), a division by a zero always gave `-inf`, and a negative value times `+0` gave `+0`.

  | before | after | note |
  | --- | --- | --- |
  | `1.20 + 3.40` is `4.6`, `1.20 - 1.20` is `0`, `6.0 / 2` is `3` | `4.60`, `0.00`, `3.0` | the member closest to the preferred exponent; an inexact result has `p` digits and is not reduced |
  | `1.25 * 2.50 * ...` grows without bound (the product was exact, up to `2p` digits) | rounded to `p` digits half even | `x * y` is `mul_ctx` in the working context; exact products of at most `p` digits are unchanged |
  | `x + 0` is NaN for `1E2147483646`, `1E-2147483645` (gap above 2,000,000,000) | `x` | `x + 0 == x`, `x - 0 == x`, `x * 1 == x` for every finite value inside the working range |
  | `1 / 0`, `1 / -0`, `-1 / 0`, `-1 / -0` are all `-inf` | `inf`, `-inf`, `-inf`, `inf` | the sign of the exact quotient |
  | `-2 * 0` is `+0` | `-0` | the sign of a zero product is the exclusive or |
  | `123E-2147483640 * 1E-10` is `1E-2147483648` | `0E-2147483645` | below the smallest exponent of the working context the result rounds to it (a zero here) |
  | a sum with adjusted exponent 2,147,483,647 | `inf` | beyond the largest adjusted exponent of the working context, an overflow |

- `decimal`: a finite `Decimal` holds only values of the stored range, and the exact constructors refuse the others ([#438](https://github.com/Luna-Flow/floating/issues/438), S1 range; same rule as `decimal_gda`). Largest adjusted exponent `decimal_value_e_max` = 2,147,483,646, smallest exponent `decimal_value_e_tiny` = -2,147,483,645, the limits of the working context of the plain operators (the largest and smallest the 32-bit exponent field allows once `e_max`, `e_min` and `etiny = e_min - p + 1` must fit in it), so that `x + 0 == x`, `x - 0 == x` and `x * 1 == x` hold for every stored value. `make` aborts naming the exponent and both limits and `from_string` returns the domain error where it (and `make`) used to return an infinity, round to the smallest exponent, or store the value; a zero is refused like any finite value; the range is checked after the rounding to the precision, a carry included; nothing is replaced silently. New `Decimal::try_make` is the `Result` form. Operations that round without a context (`with_precision`, the plain operators) overflow and underflow like a context result at the limits. A text outside the limits is read with `from_string_ctx` when a rounded value is wanted.

  | before | after | note |
  | --- | --- | --- |
  | `Decimal::from_string("1e3000000000")` is `Some(inf)`, `"12e2147483647"` is `Some(inf)` | `Err` (the domain error) | read the text with `from_string_ctx` for the infinity and the `overflow` flag |
  | `Decimal::from_string("1e-3000000000")` is `Some(0E-2147483648)`, `"123e-2147483650"` is `Some(1E-2147483648)` | `Err` (the domain error) | the exponent after the rounding to the precision must be at least -2,147,483,645 (`"1249e-2147483646"` at precision 3 is `1.25E-2147483643`) |
  | `Decimal::from_string("1E2147483647")`, `make(1N, 2147483647, p)`, `make(1N, -2147483648, p)`, `make(0N, 2147483647, p)` stored the value | `from_string` is `Err`, `make` aborts, `try_make` returns the domain error | adjusted exponent 2,147,483,647 and exponents -2,147,483,648 to -2,147,483,646 are outside the range |
  | (none) | `Decimal::try_make(c, q, p, mode?) -> Result[Decimal, ArithmeticError]` | the `Result` form of `make`, as in `decimal_gda` |
  | (none) | `decimal_value_e_max`, `decimal_value_e_tiny` | public lets; the context limits `decimal_implementation_e_max`, `decimal_implementation_e_min` keep their meaning |
  | `top.with_precision(2, mode)` for `9999E+2147483644` rounded to `9.9E+2147483647` | `9.9E+2147483646` for `9999E+2147483643`, `inf` where the mode overflows | a result beyond `decimal_value_e_max` overflows by the mode |

- `ball_float` and `ball_float_checked`: the reverse function `pow_rev1(b, c, x?)` of IEEE 1788-2015 Table 10.1, on `BallFloat`, `BallFloatDecorated` and `BallFloatResult` ([#230](https://github.com/Luna-Flow/floating/issues/230), item B6). It is the hull of `{ x in x | exists beta in b : x^beta is defined and in c }` (`x^beta` is defined for `x > 0`, and for `x = 0` with `beta > 0`); the set is `exp(L /set b)` with `L = ln(c inter (0, +inf))` plus the point 0, the set division of `mul_rev` in logarithm coordinates, with the open ends at 0 and 1. Every comparison of a prior end with a piece end is exact and an end written to the result is the exact directed rounding of `c^(1/beta)`: the exact value is classified from the structure of `c` and `beta` (dyadic, rational and not dyadic such as `9^(1/-2) = 1/3`, irrational) with budgets in bits, and the irrational ends are decided by a loop on the working precision. The ITF1788 gate runs the 429 corpus cases of `powRev1` in a new `power-reverse-1` phase (5,828 to 6,257 strict cases; the `reverse` phase keeps 375 unsupported).

  | before | after | note |
  | --- | --- | --- |
  | none | `b.pow_rev1(c, x?)` | `BallFloat`, `BallFloatDecorated`, `BallFloatResult`; no `try_` form, no input fails |

- `ball_float` and `ball_float_checked`: the reverse function `pow_rev2(a, c, x?)` of IEEE 1788-2015 Table 10.1, on `BallFloat`, `BallFloatDecorated` and `BallFloatResult` ([#230](https://github.com/Luna-Flow/floating/issues/230), item B6). It is the hull of `{ beta in x | exists a0 in a : a0^beta is defined and in c }` (the unknown is the exponent, the receiver the base); the set is the set division `ln(c inter (0, +inf)) /set ln(a inter (0, +inf))` plus `(0, +inf)` for the base 0, with the open ends at the infinities and at an unattained 0. Every comparison of a prior end with a piece end is exact and an end written to the result is the exact directed rounding of `ln(c_end) / ln(a_end)`: the end is classified by the multiplicative Euclidean algorithm on the odd parts of `a_end` and `c_end` (a float, a rational that is not a float such as `ln 3 / ln 27 = 1/3`, or irrational), with budgets in bits, and the irrational ends are decided by a loop on the working precision. The ITF1788 gate runs the 375 corpus cases of `powRev2` in a new `power-reverse-2` phase, which replaces the `reverse` phase (6,257 to 6,632 strict cases; no unsupported case is left: `atan2Rev1` and `atan2Rev2` have no corpus cases). Two corpus statements expect a value wider than the exact hull and are refinements (`interpreter_refinements.json`, now 14 entries).

  | before | after | note |
  | --- | --- | --- |
  | none | `a.pow_rev2(c, x?)` | `BallFloat`, `BallFloatDecorated`, `BallFloatResult`; no `try_` form, no input fails |

- `ball_float` and `ball_float_checked`: the reverse functions `atan2_rev1(b, c, x?)` and `atan2_rev2(a, c, x?)` of IEEE 1788-2015 Table 10.1 (10.5.4, equations (6) and (7)), on `BallFloat`, `BallFloatDecorated` and `BallFloatResult` ([#230](https://github.com/Luna-Flow/floating/issues/230), item B6; every reverse function of Table 10.1 is now provided). `atan2_rev1` is the hull of `{ y in x | exists b0 in b : atan2(y, b0) is defined and in c }` (the unknown is the ordinate, the receiver the abscissa interval), `atan2_rev2` the hull of `{ x0 in x | exists a0 in a : atan2(a0, x0) is defined and in c }` (the unknown is the abscissa). The set is the projection of the sector of the angles `c inter (-pi, pi]` (the angle `pi` on the cut `y = 0, x < 0` is attained, `-pi` never, the origin is excluded): at most five interval products of an operand part of one sign with the tangent (cotangent) of an angle region, and the axis rays. The exact ends are 0 and the infinities; every other end is `b_end tan(c_end)` or `a_end / tan(c_end)`, irrational, decided by the loop on the working precision of `pow_rev1`. The ITF1788 corpus has no `atan2Rev` case: the gate runs 16,260 cases of ours (`testdata/interval/generated/atan2_rev.itl`, written by `tools/itl_atan2_reverse_oracle.py`, whose expected hulls are validated by the forward definition) as a new `atan2-reverse` phase, counted apart from the ITF1788 total (6,632 stays).

  | before | after | note |
  | --- | --- | --- |
  | none | `b.atan2_rev1(c, x?)`, `a.atan2_rev2(c, x?)` | `BallFloat`, `BallFloatDecorated`, `BallFloatResult`; no `try_` form, no input fails |

- `decimal`: a result the library cannot compute is `not_computed`, not `invalid_operation`, and the `try_` forms keep `Err` for it ([#438](https://github.com/Luna-Flow/floating/issues/438), item S4, `decimal`). Before, a context beyond the elementary kernels (`p` or `e_max` above 999,999, or `e_min` below -999,999), an operand beyond their range, an exact sum of operands with an exponent gap beyond the work bound, and a certification that did not conclude all gave a NaN with `invalid_operation`, the flag of a domain error, and the `try_` forms returned `Ok` for the first two kinds. `DecimalFlags::not_computed()` existed and was never raised. Now `invalid_operation` is raised only for a case for which IEEE 754-2019 defines an invalid result.

  | before | after | note |
  | --- | --- | --- |
  | `x.exp_ctx(ctx)` (every plain elementary `_ctx`, 39 functions) in a restricted context or after a certification failure: NaN with `invalid_operation` | NaN with `not_computed`, without `invalid_operation` | the plain form without `_ctx` is the `.0` of it |
  | `x.try_exp_ctx(ctx)` (every `try_*_ctx`, 39 functions) in a restricted context or for an operand out of range: `Ok((NaN, invalid_operation))` | `Err` of the certification-failure kind | `Err` now means only "could not compute"; domain cases stay `Ok((NaN, invalid_operation))` |
  | `x.add_ctx(y, ctx)`, `sub_ctx` with an exponent gap beyond the work bound: NaN with `invalid_operation` | NaN with `not_computed` | |
  | `Decimal::from_bin_float_ctx(x, ctx)` with an unlimited precision and a binary exponent beyond 2^22: NaN with `invalid_operation` | NaN with `not_computed` | |
  | `*_contextual`, `*_checked`: a computation with `invalid_operation` or `not_computed`, `Err(domain_error)` | `invalid_operation` is `Err(domain_error)`, `not_computed` is `Err(certification_failure)` | the two kinds are told apart by `error.is_domain_error()` and `error.is_certification_failure()` |
  | `DecimalChecked` elementary mirrors in a restricted context: a recorded NaN with `invalid_operation`, no error | `error()` is a certification failure | |

### Added

- `bin_float`, `decimal`: every comparison predicate of IEEE 754-2019 5.11 has a function ([#438](https://github.com/Luna-Flow/floating/issues/438), item N6). The clause lists 22 predicates, 10 in Table 5.1 and 12 in Table 5.2; `bin_float` had 7 and `decimal` none. Both now have the 15 others, with the names of the first seven (`compare_quiet_*`, `compare_signaling_*`): `not_equal`, `greater`, `greater_equal`, `not_greater`, `less_unordered`, `not_less` and `greater_unordered` for both kinds, and `compare_quiet_ordered`. Each returns `(Bool, flags)`, is defined from `compare_quiet` or `compare_signaling` and raises invalid where the table says (a signaling NaN for the quiet ones, any NaN for the signaling ones). Nothing existing changes in `bin_float`.

- `ball_float` and `ball_float_checked`: text input, IEEE 1788-2015 `textToInterval` ([#21](https://github.com/Luna-Flow/floating/issues/21), item B6): `BallFloat::from_string(s, precision?)`, `BallFloatDecorated::from_string(s, precision?)` and `BallFloatResult::from_string` return `Result[_, ArithmeticError]` (the shape of `BinFloat::from_string`), and the public constant `interval_literal_max_length` (65,536 characters; a longer string gives Entire, as 12.11.5 allows). Every portable literal of 12.11 is accepted (decimal, hexadecimal and rational numbers, `inf`, inf-sup with omitted bounds, point, uncertain form `m?rve`, `[]`, `[empty]`, `[entire]`, the decorations `_trv _def _dac _com`, `[nai]`); the bounds are parsed exactly and rounded outward, `l <= u` is decided from the exact values, and every rejection names the rule that was broken. Output (`Show`, `to_exact_string`) follows in the next change.

  | before | after | note |
  | --- | --- | --- |
  | none | `BallFloat::from_string(s)`, `BallFloatDecorated::from_string(s)`, `BallFloatResult::from_string(s)`, `interval_literal_max_length` | additive; `Err` is the standard's failed call (Empty or NaI with `UndefinedOperation`) |

- `bin_float`: `BinaryFlags` has the flag `not_computed`, as `DecimalFlags` does ([#438](https://github.com/Luna-Flow/floating/issues/438), item S4, first step): `BinaryFlags::not_computed()` reports an operation that could not be carried out within a limit of the implementation, with a NaN value; it is not an IEEE 754-2019 flag and is distinct from `invalid_operation`. `new()` clears it, `combine` accumulates it and `==` compares it. No operation raises it yet; the next steps make the elementary functions raise it where they now raise `invalid_operation` for a failure to compute.

- `bin_float`: `BinFloat::ilogb(self) -> Int32?`, the exponent of the leading bit of a finite non-zero value (`floor(log2 |x|)`, `exponent2() + coefficient().bit_length() - 1`), read without building the coefficient ([#438](https://github.com/Luna-Flow/floating/issues/438)). It is `logB` of IEEE 754-2019 5.3.3 with an integral `logBFormat`: a subnormal gives the exponent of its leading bit; `logB(0)`, `logB(infinity)` and `logB(NaN)`, which the standard sends to language-defined values outside the range of the exponents and signals the invalid operation for, are `None` here and raise no flag. `logb_ctx` is the operation with a floating-point `logBFormat`.

### Fixed

- `ball_float`: `BallFloat::fma` returns the tightest interval at the bottom of the exponent range ([#607](https://github.com/Luna-Flow/floating/issues/607); present in 0.11.0). The product bounds and the sums with the addend were made at their own bit length, so below the normal range a few-bit product was rounded outward to the quantum of those few bits before the sum; IEEE 1788-2015 12.10.2 requires the accuracy of the basic operations to be tightest. They are now exact (`exact_range`) and the result is rounded outward once at the end. Example, 53 bits, `t = 2^(e_min - 3)`: `[t].fma([1], [t])` was `[1p-1073741825, 9p-1073741825]`, it is the point `1p-1073741824` (`2t`). Away from the bottom of the range the results are identical (2,500 cases).

- The arm64 assembly tier of the native limb rows is no longer selected when the stub is compiled by tcc, which defines `__GNUC__` but has no AArch64 inline assembly and stopped with "ARM asm not implemented"; such a build takes the C rows, like the x86-64 line already did ([#438](https://github.com/Luna-Flow/floating/issues/438), section 8).

- `ball_float`: the ball of `BallFloat::new` was wider than needed at the bottom of the exponent range ([#581](https://github.com/Luna-Flow/floating/issues/581); present in 0.11.0). Its endpoints `center' - R` and `center' + R` (`center'` the center rounded to the precision, `R` the radius plus the rounding error of the center, both rounded upward to the precision) were made at their own bit length, which rounds a result of a few bits below the normal range outward to the quantum of those few bits, and the sum `R` was made the same way. Both are now exact (`exact_range`). Example: center `133022375522373997p-1073741877`, radius `389p-1073741869`, 53 bits: the ball was `[8313623592241431p-1073741873, 8314173348055319p-1073741873]`, it is `[16627796940284301p-1073741874, 16627796940309199p-1073741874]` (the exact `c' - R`, `c' + R`, symmetric around `c'`). Away from the bottom of the range the endpoints are identical (3,000 cases).

- `ball_float`: `BallFloat::radius` and `BallFloat::width` returned a value far above the smallest bound for intervals in the subnormal range ([#579](https://github.com/Luna-Flow/floating/issues/579); present in 0.11.0). IEEE 1788-2015 12.12.8 defines `rad(x)` as the smallest F-number `r` with `x` inside `[m - r, m + r]` (`m = mid(x)`) and `wid(x)` as the Level 1 width rounded toward +infinity; the distances were made at their own bit length, so below the normal range a few-bit difference was rounded upward to the quantum of those few bits. They are now formed exactly and rounded upward once at the precision. Example: `[1, 3] * 2^(e_min - 60)` at 113 bits: `radius()` was `1p-1073741822` (`2^e_min`), it is `1p-1073741882`; `width()` was `1p-1073741823`, it is `1p-1073741881`. Away from the bottom of the range the results are identical (tested on 3,000 intervals). Tests check that the result is the smallest number with the property (the next number below fails it) on 3,000 intervals near the bottom of the range.

- `ball_float`: `cancel_plus` and `cancel_minus` returned a finite interval, or a single point, where the result is `Entire`, for intervals in the subnormal range ([#582](https://github.com/Luna-Flow/floating/issues/582); present in 0.11.0). IEEE 1788-2015 12.12.5 returns `Entire` when `width(x) < width(y)`; the decision `lower > upper` was made on end values made at their own bit length, which below the normal range are rounded outward to the quantum of a few bits. The end values are now exact and the decision is made on them; the ends are then rounded outward once at the precision. Example, `u = 2^(e_min - 60)`, balls of 113 bits: `[1u, 2u].cancel_plus([1u, 3u])` returned `[0, 1p-1073741823]`, it is `Entire`; `[1u, 3u].cancel_minus([1u, 5u])` returned the point `{0}` (`lo = 0`, `hi = -0`), it is `Entire`. Equal widths still give a point, with a positive zero when the point is 0.

- `ball_float`: `BallFloat::midpoint` (and `midpoint_ctx`, and the exact center of the ball view) returned 0 for an interval whose endpoints lie in the subnormal range, even when 0 is not a member ([#578](https://github.com/Luna-Flow/floating/issues/578); present in 0.11.0). The exact sum of the endpoints and its half were made at their own bit length in the nearest mode, so below the normal range a few-bit value was rounded to the quantum of those few bits. The sum and its half are now formed exactly (at `max(bit length, e_min - exponent2 + 1)` bits, one more bit for the half) and `midpoint` rounds the exact midpoint once to nearest at the precision, as IEEE 1788-2015 12.12.8 and Table 9.2 require. Example: `[1, 3] * 2^(e_min - 60)` at 113 bits: `midpoint()` was `0` (not a member), it is `1p-1073741881`; all 126 cases of the issue returned 0. Only when an operand has `binary_precision_max` bits with its lowest bit at the lowest representable position can the half not be formed exactly (it needs one bit more than the format allows): it is then rounded to nearest at `binary_precision_max` bits before the final rounding. Not changed: `radius` and `width` are bounds that are far above the smallest one at the bottom of the range ([#579](https://github.com/Luna-Flow/floating/issues/579)).

- `ball_float`: `BallFloat::new` and `try_new` (`quantize_center_radius`) could return a ball that does not contain its center ([#576](https://github.com/Luna-Flow/floating/issues/576); present in 0.11.0). The error of rounding the center to the precision was taken from an exact difference made at its own bit length in the nearest mode, so below the normal range a difference of a few bits was rounded to its own coarse quantum, in the example below to 0. The error is now the difference rounded upward once to the precision. Example: center `4296885932855670455593739022497658821269217831p-1073741878` (152 bits), radius `34625p-1073741882`, `precision=128`: the ball was `[68750174925690727289499824359962541140425537727p-1073741882, 68750174925690727289499824359962541140425606977p-1073741882]`, 118,052,431 units of `2^-1073741882` above the center; the center is now inside. 10 of 4,000 balls of a seeded class near the bottom of the exponent range missed their centers; none does now.

- `ball_float`: the total elementary forms (`exp_interval`, `exp2_interval`, `exp10_interval`, `ln_interval`, `log2_interval`, `log10_interval`, `sin_interval`, `cos_interval`, `tan_interval`, `asin_interval`, `acos_interval`, `atan_interval`, the six hyperbolic functions and their inverses, `pow_interval`, `rootn`) are now the `try_` form with a fallback, one kernel instead of two ([#449](https://github.com/Luna-Flow/floating/issues/449); Closes #449). They used an exact-rational series of their own that aborted ("certified log series did not converge") from about 32,000 bits for `ln_interval` (about 150,000 for `exp_interval`, about 200,000 for `atan_interval`), and that lost all relative accuracy for a tiny argument in `sinh`, `tanh`, `asinh` and `atanh` (`sinh_interval` of `2^-300` at 53 bits was `[0, 3 * 2^-246]`, now two ulps wide). The `try_` forms used the `bin_float` kernels and had neither limit. Whenever the `try_` form succeeds, the total form returns the same interval; when it reports a certification failure the total form returns the range of the function over its domain (`[0, +inf)` for `exp`, `[-1, 1]` for `sin`, `[-pi/2, pi/2]` for `atan`, Entire for `ln`, and so on; the table is in the API page), which is valid at every precision and cannot itself fail. An argument outside the domain still gives Empty, decided before the kernel runs. Results of these functions can differ from the previous release in the last bit (the `try_` kernels round each endpoint directly); all 4,656 strict ITF1788 cases pass.

- `ball_float`: `try_atanh_interval` (and so `atanh_interval`) aborted ("ball lower bound must not be positive infinity") for an interval whose only point in the closure of the domain is `1` or `-1` (`[1, 1]`, `[1, +inf]`, `[-inf, -1]`). The open domain leaves nothing, so the result is Empty.

- `ball_float`: `BallFloat::radius` and `radius_extended` returned the half-width around the exact center, not the `rad` of IEEE 1788-2015 12.12.8, which is measured from the value `midpoint` returns ([#477](https://github.com/Luna-Flow/floating/issues/477); Closes #477). When the center is not representable, `midpoint` rounds it and `[midpoint - radius, midpoint + radius]` missed a bound: for `[1, 1 + 3 * 2^-52]` at 53 bits the midpoint is `1 + 2^-51` and the radius was `3 * 2^-53`, so the lower bound 1 was outside. `radius` is now the larger of `midpoint - lower` and `upper - midpoint`, rounded up, which is `2^-51` there.

- `ball_float`: the half-width of the ball view (the second part of the text `center +/- half-width` of a ball, `BallFloat::half_width`) was far above the half-width for an interval below the normal range ([#583](https://github.com/Luna-Flow/floating/issues/583); present in 0.11.0). The difference of the bounds and its half were made at their own bit length and rounded upward there, to the quantum of a few bits. They are now exact (`exact_range`). Example: `[1, 3] * 2^(e_min - 60)` at 113 bits: the half-width was `1p-1073741822` (`2^e_min`), it is `1p-1073741882`, and the text is `1p-1073741881 +/- 1p-1073741882`. Away from the bottom of the range the value is identical (3,000 cases).

- `ball_float`: `add`, `sub`, `mul` and `sqr` return the tightest interval at the edge of the exponent range: the bounds are the correctly rounded ones when the exact result has fewer bits than the precision ([#606](https://github.com/Luna-Flow/floating/issues/606); present in 0.11.0). IEEE 1788-2015 12.10.2 requires the accuracy of the basic operations to be tightest (the T-hull of the Level 1 result). `fma` is not covered ([#607](https://github.com/Luna-Flow/floating/issues/607)). They were made at the bit length of the exact result before they were rounded to the precision, so below the normal range the lower bound of a positive result was rounded to zero and the upper one to the next multiple of the coarser quantum of the short result, and in the overflow band the lower bound of a positive result was the largest finite value of the short result, not of the precision. Example at 53 bits: `2^(e_min - 3) + 2^(e_min - 3)` had lower bound `0` and upper bound `2^(e_min - 1)`; both are now `2^(e_min - 2)`. The new interval is always inside the old one; there are no other changes of results (`identical` endpoints, the same zero), verified on 6,672 random and range-edge operand pairs against the old exact route and against the exact route made at `max(bits, p)` bits.

### Performance

- `ball_float`: the interval operations no longer read the coefficient only to measure it, and the bounds of sums, differences and products are made once at the precision ([#438](https://github.com/Luna-Flow/floating/issues/438)). `BinFloat::ilogb()` replaces `exponent2() + coefficient().bit_length() - 1` at the six places that wanted the leading bit (four of the twelve allocations that the layout of the previous change added to `BallFloat::add` came from `far_addend_surrogate` alone), and `add`, `sub`, `mul`, `sqr`, `radius` and `width` round each endpoint once in its direction (`fma` is not covered: its product is still made at its own bit length, [#607](https://github.com/Luna-Flow/floating/issues/607)). Instructions per call (the two-count method of the entry above: 1,000 and 3,000 calls, minimum of 9 runs; operands `sqrt(3)` and `sqrt(5)` as balls of the stated precision; three builds of different code, so only differences well above the 3 to 9 percent that two builds of the same code differ by are evidence, and the allocation counts, which are exact, carry the comparison) and allocations (the same difference of 20 and 60 calls under `lldb`):

  | `BallFloat` call | bits | instructions before the layout | after the layout | after this change | allocations before | after the layout | after this change |
  | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
  | `add` | 53 | 3,570 | 5,430 | 4,027 | 14 | 26 | 18 |
  | `sub` | 53 | 4,291 | 6,121 | 3,793 | 16 | 29 | 17 |
  | `mul` | 53 | 3,148 | 3,981 | 3,999 | 13 | 19 | 19 |
  | `sqr` | 53 | 4,060 | 4,199 | 4,220 | 15 | 19 | 19 |
  | `mul_rev` | 53 | 10,053 | 9,054 | 9,054 | 47 | 47 | 47 |
  | `add` | 128 | 4,676 | 6,127 | 4,642 | 18 | 30 | 20 |
  | `sub` | 128 | 4,890 | 6,177 | 4,293 | 18 | 31 | 19 |
  | `mul` | 128 | 4,826 | 5,308 | 5,420 | 23 | 27 | 27 |
  | `sqr` | 128 | 5,602 | 5,625 | 5,601 | 25 | 27 | 27 |
  | `mul_rev` | 128 | 12,751 | 11,704 | 11,734 | 56 | 56 | 56 |
  | `add` | 512 | 4,802 | 5,391 | 5,261 | 16 | 16 | 16 |
  | `sub` | 512 | 6,113 | 6,598 | 5,652 | 21 | 21 | 19 |
  | `mul` | 512 | 5,959 | 6,209 | 6,306 | 16 | 16 | 16 |
  | `sqr` | 512 | 8,317 | 8,628 | 8,710 | 24 | 24 | 24 |
  | `mul_rev` | 512 | 19,823 | 19,696 | 19,657 | 67 | 67 | 67 |
  | `add` | 2048 | 8,412 | 8,918 | 8,396 | 21 | 21 | 20 |
  | `sub` | 2048 | 7,512 | 8,046 | 7,099 | 21 | 21 | 19 |
  | `mul` | 2048 | 25,959 | 26,202 | 26,279 | 24 | 24 | 24 |
  | `sqr` | 2048 | 27,168 | 27,436 | 27,566 | 26 | 26 | 26 |
  | `mul_rev` | 2048 | 46,101 | 45,982 | 45,925 | 67 | 67 | 67 |

  `add` and `sub` recover most of what the layout cost, `mul` and `sqr` do not move: the exact product reads `coefficient()` of both operands (an allocation each since the previous change), which needs either a word reader on `BinFloat` or a contextual core that reads words. The measured alternative is `add_ctx`, `sub_ctx` and `mul_ctx` in a context of the result precision with the direction as the rounding (no exact intermediate). The two forms of the endpoint helper were measured in one executable (instructions per call: the difference of 1,000 and 41,000 calls at 53 bits and of 1,000 and 31,000, 21,000 and 5,500 at the larger widths, the median of 5 runs of each count with the range of the 25 pairwise differences; allocations as above); the difference of the counts is at least 50 million instructions except for the rows marked below 50:

  | operation (endpoint helper) | bits | instructions, exact route (median, range) | instructions, contexts (median, range) | measured difference (millions) | allocations, exact route | allocations, contexts |
  | --- | ---: | ---: | ---: | ---: | ---: | ---: |
  | `directed_add` | 53 | 1,329 (1,267 to 1,341) | 1,379 (1,374 to 1,385) | 53, 55 | 6 | 8 |
  | `directed_sub` | 53 | 1,697 (1,691 to 1,702) | 1,570 (1,540 to 1,575) | 68, 63 | 8 | 9 |
  | `directed_mul` | 53 | 1,933 (1,906 to 1,974) | 1,978 (1,974 to 1,990) | 77, 79 | 10 | 12 |
  | `directed_add` | 128 | 2,811 (2,777 to 2,815) | 2,797 (2,792 to 2,802) | 84, 84 | 12 | 15 |
  | `directed_sub` | 128 | 2,186 (2,180 to 2,190) | 2,030 (2,011 to 2,039) | 66, 61 | 10 | 11 |
  | `directed_mul` | 128 | 2,635 (2,629 to 2,641) | 2,731 (2,680 to 2,740) | 79, 82 | 14 | 17 |
  | `directed_add` | 512 | 1,895 (1,890 to 1,915) | 1,514 (1,486 to 1,522) | 38, 30 | 6 | 6 |
  | `directed_sub` | 512 | 2,345 (2,340 to 2,351) | 1,735 (1,728 to 1,748) | 47, 35 | 8 | 7 |
  | `directed_mul` | 512 | 3,064 (3,060 to 3,069) | 3,153 (3,143 to 3,161) | 61, 63 | 8 | 11 |
  | `directed_add` | 2048 | 5,636 (5,586 to 5,665) | 5,531 (5,492 to 5,743) | 28, 28 | 13 | 16 |
  | `directed_sub` | 2048 | 2,816 (2,627 to 2,856) | 2,606 (2,575 to 2,645) | 14, 13 | 8 | 9 |
  | `directed_mul` | 2048 | 10,830 (10,785 to 10,865) | 10,879 (10,681 to 11,052) | 54, 54 | 8 | 11 |

  In instructions the two forms are equal within the resolution of the method (at most 4 percent) for `add` at 53, 128 and 2,048 bits and for `mul` at every width, and the contexts are lower for `sub` (7, 7, 26 and 7 percent) and for `add` at 512 bits (20 percent); the rows with a measured difference below 50 million (`add` and `sub` at 512 bits, `add` and `sub` at 2,048 bits) are weaker evidence. In allocations the exact route has 1 to 3 fewer for `add` (6 against 8 at 53 bits; equal at 512), 2 to 3 fewer for `mul` and 1 fewer for `sub` except at 512 bits where the contexts have 1 fewer. A context is built per call by `BinaryContext::new` (155 instructions, one allocation) and the contextual operations return a tuple and a flag set; the exact route is the one with the fewer allocations today.

  The exact route stays; the contexts are the oracle of the differential test (`directed_bounds_wbtest.mbt`), and they replace the exact route when the contextual core reads words (PR F of the 0.12 plan).

  Not recovered here, owner PR F (to be recovered before the 0.12 release): `BallFloat::add` at 53 bits is 18 allocations and 4,027 instructions against 14 and 3,570 before the layout, `mul` 19 and 3,999 against 13 and 3,148, `sqr` 19 and 4,220 against 15 and 4,060, and the 128-bit rows (`add` 20 and 4,642 against 18 and 4,676, `mul` 27 and 5,420 against 23 and 4,826), because the exact sum and product read `coefficient()` of both operands.

- `bin_float`: `BinaryFlags` is a scalar ([#438](https://github.com/Luna-Flow/floating/issues/438), item F1 of the performance plan). The record of six Booleans (a heap object) becomes `pub struct BinaryFlags(FlagBits)` over the abstract `struct FlagBits(UInt)`: a newtype over a scalar is erased on every target, so the pair `(BinFloat, BinaryFlags)` of a contextual operation holds the flags inline. The interface changes in these lines of `pkg.generated.mbti`: `pub struct BinaryFlags { // private fields }` becomes `pub struct BinaryFlags(FlagBits)`, `#derive(Eq, @debug.Debug)` becomes `#derive(Eq)` with `pub impl @debug.Debug for BinaryFlags` (the printed form is the one of the record, compared by a test over the 64 combinations), and `type FlagBits` is added; the methods (`new`, `combine`, the six accessors, `equal`, `not_equal`, `to_repr`) are unchanged, no call changes, and the bit layout is not readable by a caller (`flags.0` is an opaque `FlagBits`). `to_testfloat_bits` keeps its values; `not_computed` is one more bit outside the TestFloat mask. Allocations per call (exact, `lldb` on `mi_malloc`, binary64 contexts, 53-bit operands) before and after: `mul_ctx` 11 and 10, `fma` 17 and 16, `div_ctx` 14 and 13, `add_ctx` 7 and 7, `scaleb_ctx` 14 and 14. A struct with one private field is not erased (a heap object on native, JS and wasm-gc): the newtype is the shape.

- `bin_float`: a `BinFloat` is one heap object when its coefficient has at most 128 bits ([#438](https://github.com/Luna-Flow/floating/issues/438), items X1 and X2 of the performance plan). The record of seven fields (and a coefficient object) is replaced by a newtype over the internal enum `@bin_kernel.BinRepr` (`Fin64`, `Fin128`, `FinBig`, `Inf`, `NaN`; `FinBig`, `Inf` and `NaN` on the JavaScript target). The public methods are unchanged; the type prints in the interface as `pub struct BinFloat(@bin_kernel.BinRepr)` like `BinCoeff`. The plain operations read the precision once and dispatch to the word, two-word or limb path by it; the wide paths read two wide operands by one match.

  | call (operands of the stated width, the result rounds) | instructions before | after | allocations before | after |
  | --- | ---: | ---: | ---: | ---: |
  | `add` at 53 bits | 466 | 284 | 2 | 1 |
  | `mul` at 53 bits | 462 | 280 | 2 | 1 |
  | `div` at 53 bits | 412 | 257 | 2 | 1 |
  | `sqrt` at 53 bits | 524 | 363 | 3 | 2 |
  | `add` at 64 bits | 530 | 355 | 2 | 1 |
  | `mul` at 64 bits | 512 | 333 | 2 | 1 |
  | `div` at 64 bits | 1,104 | 935 | 2 | 1 |
  | `sqrt` at 64 bits | 1,492 | 1,581 | 8 | 9 |
  | `add` at 128 bits | 568 | 381 | 2 | 1 |
  | `mul` at 128 bits | 581 | 406 | 2 | 1 |
  | `div` at 128 bits | 1,156 | 984 | 2 | 1 |
  | `sqrt` at 128 bits | 2,078 | 2,170 | 9 | 10 |
  | `add` at 512 bits | 1,289 | 1,233 | 3 | 3 |
  | `mul` at 512 bits | 2,028 | 2,004 | 4 | 4 |
  | `div` at 512 bits | 4,665 | 4,589 | 6 | 6 |
  | `sqrt` at 512 bits | 8,674 | 8,713 | 31 | 31 |

  Instructions per call by the difference of two repetition counts (5,000 and 25,000 calls, minimum of 9 runs); operands `sqrt(3)` and `sqrt(5)` rounded to the stated width, so every result rounds; allocations counted on `mi_malloc` under `lldb` by the same difference (200 and 1,000 calls). The `sqrt` rows at 64 and 128 bits are the general contextual path, which builds the coefficient object of a small operand once (one allocation more); a word-based entry of `sqrt_ctx` would remove it.

  The readers and the contextual operations, same method (53 bits, and 128 where the operation has a 128-bit case; `BallFloat` rows are a client of the package; the `==` rows read operands from an array by a varying index so that the comparison is not folded; the `sqrt` rows of the first table were taken on main after the `sqrt_ctx` change of PR 564):

  | call | bits | instructions before | after | allocations before | after |
  | --- | ---: | ---: | ---: | ---: | ---: |
  | `compare equal exponents` | 53 | 264 | 96 | 1 | 0 |
  | `compare different exponents` | 53 | 66 | 77 | 0 | 0 |
  | `==` | 53 | 70 | 57 | 0 | 0 |
  | `neg` | 53 | 211 | 149 | 1 | 1 |
  | `abs` | 53 | 13 | 20 | 0 | 0 |
  | `is_zero` | 53 | 13 | 3 | 0 | 0 |
  | `sign` | 53 | 8 | 15 | 0 | 0 |
  | `from_double` | 53 | 611 | 532 | 3 | 3 |
  | `with_precision 64 to 53` | 53 | 710 | 780 | 3 | 4 |
  | `fma` | 53 | 2,462 | 2,901 | 14 | 18 |
  | `scaleb_ctx` | 53 | 429 | 493 | 2 | 3 |
  | `next_up_ctx` | 53 | 2,634 | 2,718 | 15 | 17 |
  | `to_integral_value_ctx` | 53 | 1,155 | 1,250 | 7 | 8 |
  | `to_decimal_string_ctx 17 digits` | 53 | 11,371 | 11,056 | 59 | 60 |
  | `from_string 17 digits` | 53 | 8,576 | 8,521 | 41 | 41 |
  | `add_ctx binary64` | 53 | 985 | 1,175 | 5 | 7 |
  | `mul_ctx binary64` | 53 | 1,494 | 1,714 | 9 | 11 |
  | `compare equal exponents` | 128 | 71 | 85 | 0 | 0 |
  | `compare different exponents` | 128 | 70 | 78 | 0 | 0 |
  | `==` | 128 | 78 | 57 | 0 | 0 |
  | `neg` | 128 | 215 | 156 | 1 | 1 |
  | `abs` | 128 | 14 | 28 | 0 | 0 |
  | `is_zero` | 128 | 4 | 5 | 0 | 0 |
  | `fma` | 128 | 3,846 | 4,263 | 21 | 24 |
  | `add_ctx binary128` | 128 | 2,612 | 2,841 | 13 | 15 |
  | `mul_ctx binary128` | 128 | 2,170 | 2,413 | 13 | 15 |
  | `BallFloat add` | 53 | 3,442 | 5,416 | 14 | 26 |
  | `BallFloat mul` | 53 | 3,156 | 3,940 | 13 | 19 |
  | `BallFloat add` | 128 | 4,688 | 6,154 | 18 | 30 |
  | `BallFloat mul` | 128 | 4,873 | 5,317 | 23 | 27 |
  | `BallFloat mul_rev` | 53 | 10,038 | 9,018 | 47 | 47 |
  | `BallFloat sqr_rev` | 53 | 17,476 | 16,642 | 93 | 93 |

  `compare`, `==`, `is_zero` and `neg` get cheaper; `compare` decides on the words when both operands have at most 128 coefficient bits (equal values have equal exponents because the coefficient is odd, so only the leading-bit exponents, then the shifted words, are compared). Known regressions: the contextual operations (`fma`, `add_ctx`, `mul_ctx`, `scaleb_ctx`, `with_precision`, `to_integral_value_ctx`, `next_up_ctx`) and `sqrt` at 64 and 128 bits build a coefficient object from the words of a small operand (one allocation each, 2 to 4 more per call, +3 % to +20 % instructions); they go to the word-based exact core of the later layout PR (`bin_finish_*`) and to a word entry of `sqrt_ctx`. `abs`, `sign` and `compare` of unequal exponents cost 6 to 13 instructions more (a match on the form instead of a field read). `BallFloat::add` and `mul` read `BinFloat::coefficient()`, which now allocates for a value of at most 128 bits, so they allocate 6 to 12 more per call (`add` at 53 bits +57 % instructions); `BinFloat` has no public word reader, so the fix is one in the package or a ball-side reader (owner: `ball_float`). These regressions are to be recovered before the 0.12 release.

- `bin_float`: `mul` of operands of 13 to 64 limbs (precisions from 768 to about 4,000 bits) forms the high limbs of the product only (the basecase short product: the rows of limb products with `i + j >= m - 1`, about half of them) with one extra limb of guard, and uses them when the rounding is certain from a proved error bound (exact products and products next to a rounding boundary take the full product as before). Instructions per call fall to 0.97 (768 bits), 0.86 (1,024) and 0.75 (2,048); below 768 bits the setup costs more than the rows save, so the short product is not used there. Results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).
- `bin_float`: `sub` no longer allocates the negated right operand: the word, two-word and coefficient paths of the addition read its sign flipped (`add_signed_impl`), so a subtraction costs what an addition costs (0.68 of the instructions at 53 to 128 bits, 0.87 at 512 bits); the two-word addition aligns the shifted operand by three shifts of two words when the exponent difference is below 64, and the two-word rounding extracts the kept words and the dropped bits in one expression for a result less than a word too wide (`add` at 128 bits 0.89, at 113 bits 0.95). Results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).

- `bin_float`: `mul`, `div` and `sqrt` with a result wider than 128 bits round the array that the coefficient kernel returns in place instead of copying it first (the kernel owns that array; see the contract in its design page), and `binary_coeff_fast_mul` and `binary_coeff_fast_div` no longer go through an option of a scalar for the operand test. Results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).

- `bin_float`: `add` and `sub` of coefficients wider than one word form the aligned sum in one pass over one array of the size of the result, read through the exponent shifts of both operands, instead of two shifted copies, an addition or a comparison and a subtraction, each into a new array. An operand that reaches below the rounding position, or lies entirely below it, is reduced to a sticky bit (its limbs are not read in the second case), so the former limit on the exponent gap of the fast path is gone. The result is rounded by the in-place finisher. Results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).
- `bin_float`: `div` of operands of 2 to 256 limbs computes an approximate quotient with a truncated divisor (Knuth's digit loop where the digit at position `k` multiplies only the top limbs of the divisor, about half the limb products) with 32 guard bits, and uses it when the rounding is certain from a proved error bound (the exact quotients and those next to a rounding boundary take the exact division as before). Instructions per call fall to 0.92 (512 bits), 0.81 (1024), 0.69 (2048), 0.62 (4096) and 0.56 (8192). Results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).

- `bin_float`: the word helpers of the fast paths (`binary_fast_word`, `binary_pair_words`, `binary_coeff_fast_words`, `binary_fast_isqrt`) and the kernel entries of the scaled division and square root no longer return an option of a scalar, a tuple or an option of a tuple, each a heap object in the native build; the test and the words are separate functions returning scalars, and the inexact bit travels as the lowest bit of the quotient. Instructions per call fall by 20 to 37 percent for `add`, `mul`, `div` at 53 and 128 bits and by 9 percent for `add` at 512 bits. Results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).

- `bin_float`: the rounding of a result wider than 128 bits (`add`, `mul`, `div`, `sqrt` fast paths) is one in-place finisher: it finds the top bit, rounds in the direction it is given (the plain operators pass nearest even) with the sticky bit, and shifts the kept bits and strips the trailing zeros in one pass over the array, with no carry propagation, instead of copying, incrementing and normalising in three passes. Instructions retired per call on Native: `add` at 2,048 bits 28 percent fewer, `mul` 3 to 4 percent fewer at 512 and 2,048 bits, `div` 3 percent, `sqrt` 1 percent. Results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).

- `bin_float`: on the native target the schoolbook product and square of the 64-bit coefficient kernel (Karatsuba leaves included) run in C with a 128-bit limb product (`internal/bin_kernel/luna_limbs.c`), behind the same functions and with results identical bit for bit to the MoonBit loops, which stay as the reference and the code of every other target. On arm64 the probe rows take 0.79 (mul 512 bits), 0.65 (2048) and 0.65 (8192) of the instructions. `LUNA_FLOATING_PORTABLE=1` forces the portable loops on native ([#438](https://github.com/Luna-Flow/floating/issues/438), section 8).

- `bin_float`: on Apple arm64 the limb rows of the native kernel (`mul_1`, `addmul_1`, `submul_1`, and the schoolbook product and square on them) run in inline assembly with two carry chains, 4.9 to 7.0 instructions per limb against 9.2 to 13.1 for the C rows. On the probe rows `mul`, `div` and `sqrt` at 2,048 and 8,192 bits take 0.67 to 0.88 of the instructions of the C rows; results are identical, the C rows stay the code of every other native target, and `LUNA_FLOATING_LIMBS=c` selects them ([#438](https://github.com/Luna-Flow/floating/issues/438), section 8).

- `bin_float`: the cutoffs of the native kernel follow the row implementation ([#438](https://github.com/Luna-Flow/floating/issues/438), section 8). With the assembly rows the short product runs from 31 to 384 limbs of the extended precision (was 20 to 192: at 21 to 29 limbs it cost 3 to 18 percent more than the full product), the schoolbook product is used up to 47 limbs (was 31; 8,040 against 9,237 instructions at 32 limbs, 27,481 against 30,001 at 64) and the schoolbook square up to 95 limbs (was 35; 18,043 against 20,129 at 64 limbs); with the C rows the square cutoff is 64 (was 36; 37,433 against 40,412 at 80 limbs) and the other limits stay. Results are identical; on the probe rows of `mul`, `div`, `sqrt` at 512 to 8,192 bits the counts change by less than 1 percent (2 percent for `sqrt` at 8,192 bits), because those rows lie inside both old and new limits.

- `bin_float`: the rows of the Knuth quotient (full, and the truncated divisor of the short division) and of the short product run on the row primitives `bin_limbs_mul_1`, `bin_limbs_addmul_1` and `bin_limbs_submul_1` (C on native, the portable loops elsewhere and with `LUNA_FLOATING_PORTABLE=1`); no row length is short enough for the call to lose (one, three and six limbs measured within 2 percent). The short product now covers 20 to 192 limbs on native with C rows (before: 13 to 64): against the Karatsuba product it takes 0.94 of the instructions at 21 limbs, 0.71 at 65 and 0.94 at 193; the portable targets keep 13 to 64. Instructions per call (two-count method, native), before / after: `mul` 1,024 bits 6,240 / 4,641, 2,048 bits 15,979 / 10,565, 8,192 bits 124,277 / 105,733; `div` 2,048 bits 22,187 / 15,730, 8,192 bits 234,123 / 131,710; `sqrt` 2,048 bits 27,037 / 24,232, 8,192 bits 205,883 / 144,738; with `LUNA_FLOATING_PORTABLE=1` no row is more than 3 percent above its previous value. Results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438), section 8).

- `bin_float`: the digit estimate of the Knuth quotient loops (full divisor and short division) is the quotient of the top three limbs of the window by the top two of the divisor with a precomputed reciprocal, instead of a 128 by 64 bit division and a correction against the next divisor limb: Möller and Granlund, "Improved division by invariant integers" (IEEE Transactions on Computers 60(2), 2011), Algorithm 5 (DIV3BY2, Theorem 3) with the reciprocal of Algorithm 6, once per division; the old estimate stays for the rare digit with the window's top limb equal to the divisor's. The digits are the same (differential test against the old estimate and the exact quotient on edge and random limbs, the reciprocal against `floor((B^3 - 1) / D) - B`). Instructions per call (two-count method, native, C rows): `div` 0.96 at 512 bits, 0.93 at 1,024, 0.94 at 2,048, 0.96 at 4,096 and 8,192 bits; `sqrt` 1.00 to 0.96; with `LUNA_FLOATING_PORTABLE=1` 0.96 to 1.01 ([#438](https://github.com/Luna-Flow/floating/issues/438), section 8).

- `bin_float`: `div` of operands wider than one word forms the quotient and the inexact flag from the working array of Knuth's algorithm directly (one shift pass for the scaling and the normalisation, no remainder value built), and the digit loop hoists the halves of the trial digit. Results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).

- `bin_float`: `div` of operands whose coefficients take at most two words, at precisions from 61 to 128 bits, runs three 3-by-2 word steps of Knuth's algorithm on registers instead of the general coefficient division; only the result is allocated. Results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).

- `bin_float`: `sqrt` of a coefficient above 256 bits (precisions from about 128 bits up) runs the Karatsuba square root on limb arrays: the divisor of each level is the root of the upper part, used without a copy or a shift, the quotient, remainder and square are formed on arrays, and the radicand is shifted once instead of twice. Results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).

- `bin_float`: the schoolbook loops of the 64-bit coefficient kernel (product, square, Karatsuba leaves) hoist the halves of the left limb out of the inner loop, compute the high word of the limb product with two operations fewer, and fold the two carries without a branch. About 7 percent fewer instructions for products and divisions of 2048 bits and more; results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).

- `decimal`, `decimal_gda`: the integer square root of the shared coefficient kernel starts from the exact root of the upper half of the digits and runs Newton's step from that overestimate (a word below 10^18 takes the hardware root), so the working size doubles per level instead of every step running at full size from a power of ten, and the division that ends the loop also yields the remainder, without a squaring. About 3.4 times fewer instructions for `sqrt` at 1000 digits, 1.4 to 1.9 times fewer at 16 to 100 digits; results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).

- `decimal`, `decimal_gda`: rounding a multi-limb coefficient by a power of ten (every inexact add, multiplication, division) shifts, reads the rounding digit and the sticky digits and adds the rounding unit in one pass into one new array, instead of four allocations and about five passes; the kernel also offers the same rounding in place for a caller that owns the limb array. About 1.33 times fewer instructions for `add` at 34 digits, 1.17 for `multiply`, 1.10 for `divide`; results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).

- `bin_float`: `div` and `sqrt` at precision 53 form the quotient or root of the two coefficients (at most 53 bits, exact in binary64) with one binary64 division or square root, which IEEE 754 rounds to nearest even exactly as the general path does. Results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).
- `bin_float`: `ln` at working precisions from 384 to 1151 bits starts with the verified Newton step, whose `exp` runs on the table kernel (the step called the bit-burst kernel directly and was enabled from 1152 bits only). 9 to 21 percent fewer instructions for `ln` at 320 to 1024 bits; 1152 bits and above, and the nested steps, are unchanged. Results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).
- `bin_float`: `ln` at working precisions from 640 bits (native) uses the arithmetic-geometric mean, a plain iteration of one product and one square root with a rigorous enclosure (the error of the mean, `pi`, `ln 2`, the cancellation and the model bound are in the design page; the model bound `ln s >= F (1 - 4/s^2)` is taken from the literature with a sixteen-fold margin), instead of the Newton step on `exp`. Instructions per call: 0.83 at 640 bits, 0.53 at 1024, 0.44 at 2048, 0.51 at 4096, 0.62 at 8192 of the Newton step; `log2`, `log10` and `asinh` at 2048 bits 0.46, 0.49 and 0.44. Arguments within `2^-16` of 1 keep the series, the other targets keep the Newton step (not measured), and the Newton step is the fallback of the width check. Results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).
- `bin_float`: the binary-splitting trees of the `exp`, `sin` and `cos` bit-burst stages read the power of the numerator from one table (no product of the two child powers at every node, no dead power at the root and at right children), form the shift and the sum of a merge in one limb array (`Coeff::add_shifted_left` in the coefficient kernel) and write out the nodes of two leaves. The integers of every node are the same as before, so every enclosure and result is unchanged. Instructions per call: `exp` 0.77 at 2048 bits and 0.84 at 8192, `sin` 0.79 and 0.86; allocations of one `exp` at 2048 bits 878 to 649 ([#438](https://github.com/Luna-Flow/floating/issues/438)).
- `decimal_gda`: `add` and `subtract` of two finite nonzero operands in an extended, non-clamping context (the case where no operand is absorbed and the result is neither subnormal nor beyond the range) form the exact sum in one limb array, round it in place and build the outcome once, instead of the general route through the context engine: 6 allocations per 34-digit call instead of 28.9 (5 when the status of the context already contains the raised conditions, which makes the outcome carry the input context), and about 2.5 times fewer instructions at 34, 100 and 1000 digits. `dec_coeff_unit_add_sub` no longer allocates a tuple for every limb that carries, `trapped_signal` no longer builds an array, and the empty flag sets (`GdaFlags::new()`, the private `DecimalFlags::new()`) are shared constants, which also shortens `multiply`, `divide` and the word paths. Results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).
- `decimal_gda`: `multiply` and `divide` of two finite nonzero operands in an extended, non-clamping context (result neither subnormal nor beyond the range) round the exact product, or the quotient formed to `p + 2` digits by one division, once into one new array and build the outcome once, instead of the general route through the context engine. A quotient with a finite decimal expansion keeps the general route. The quotient uses the scale `p + 2 + digits(b) - digits(a)` instead of a scale independent of the dividend, which halves its length. Allocations per call: multiply 34 digits 22 to 9, 100 digits 23.75 to 9; divide 34 digits 52 to 36.7, 1000 digits 66 to 48.5 (the rest is the division kernel). About 1.7 times fewer instructions for `multiply` at 34 digits, 1.4 at 100, 1.4 to 1.9 for `divide` at 34 to 1000 digits. Results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).

- `bin_float`: the `exp` bit-burst kernel folds each chunk into the running pair with one full product and two products by short numbers instead of two full products (`U s = L l + L (s - l) + (U - L) s`, exact; the first chunk without a product), and the `sin`/`cos` kernel forms only the component the result reads in its last fold (two ball products instead of four). The integers are the same as before, so every result is unchanged; when the sine is read the last fold no longer declines on a negative cosine midpoint, so the kernel may answer where it used to fall back to the series, with the same correctly rounded value ([#438](https://github.com/Luna-Flow/floating/issues/438)).
- `decimal`, `decimal_gda`: the division kernel on limb arrays. Knuth's algorithm D works on one scratch array per operand (`FixedArray`, unchecked access) instead of four `Array[UInt64]` plus wide accumulators converted afterwards, writes the quotient limbs once into the array that becomes the result, builds the remainder only when the caller needs it, and drops the defensive correction branch that could not be taken. `decimal_gda` `divide` forms the scaled dividend and normalizes it in place and decides the finite-expansion test without a second division for divisors prime to 10 (`dec_coeff_div_scaled_inexact`). The schoolbook product reads limbs in place and writes limbs below the base directly (no packed copies, no conversion). About 2.2 times fewer instructions for `divide` at 34 digits, 2.0 at 100, 1.6 at 1000; 1.4 for `multiply` at 100 digits and 1.15 at 1000; 1.2 to 1.35 for `sqrt` (its Newton steps divide). Results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).
- `decimal`, `decimal_gda`: the schoolbook product and square of the shared coefficient kernel sum each column in one word (up to 16 products between folds, one reduction per column) instead of reducing after every limb product, and the native Karatsuba thresholds are re-measured for the faster loops (192 limbs for the product, 352 for the square, were 96 and 48). About 1.7 times fewer instructions for `multiply` at 1000 digits, 1.5 at 2000, 1.2 for `sqrt` at 1000 and 2000 digits, the square of 112 limbs 3.8 times fewer; operands of at most 18 limbs, `add` and the word paths unchanged. Results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).

- `bin_float`: the loop of the arithmetic-geometric mean for `ln` takes the correctly rounded square root from the limb-array kernel of the public `sqrt` (the context form returns the same value and costs 39 percent more at 2140 bits), halves the sum exactly by changing the exponent instead of renormalizing, and forms the difference of the stopping test only when the exponents of the two means differ by at most 1. Instructions per call of `ln` 0.81 of before at 1024, 2048, 4096 and 8192 bits; results unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).
- `bin_float`: the chunk constants of the `exp`, `sin` and `cos` bit-burst kernels are functions of the working precision on Native: up to 3000 bits a first chunk of 24 bits, factor 8 and splitting from 80 terms, up to 6000 bits the same with factor 4, above that the previous (16, 4, 40); the other targets keep (16, 4, 40). Instructions per call at working precisions up to 4160 bits: 0.69 to 0.99 of before for `sin`, 0.81 to 0.98 for `exp` (kernel level, three arguments per size); results unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).
- `bin_float`: the binary-splitting stages of the `sin` and `cos` bit-burst kernel evaluate the real series of the sine in `y^2` (a tree of half the leaves with a signed `T`) instead of the complex series of `exp(i y)`, and take the cosine of a stage from the sine by two exact integer square roots over the sine ball; the fold by rotation and the fixed-point stages are unchanged. Instructions per call of `sin` and `cos` 0.68 to 0.83 of before at 2048, 4096 and 8192 bits (three arguments per size); results unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).

- `bin_float`: `sqrt_ctx` (and with it `BallFloat::sqrt`, `sqrt_checked` and every IEEE context) decides whether the square root lies above the midpoint of the two nearest results from the remainder of the integer root instead of from a full square: with `N = root^2 + remainder`, `sqrt(N) > root + 1/2` exactly when `remainder > root` (`sqrt(N) = root + 1/2` would need `N = root^2 + root + 1/4`, not an integer, so there is no tie), and the radicand is shifted once into the limb array of the root recursion (`bin_coeff_sqrt_rem_scaled`; the host-bigint kernel on js, unchanged). Instructions per call on native, before / after: 53 bits 2,650 / 1,925, 128 bits 4,570 / 2,650, 512 bits 12,330 / 9,193, 2,048 bits 35,404 / 24,825, 8,192 bits 235,827 / 144,723 (the public `sqrt` takes 142,412 at 8,192 bits); `BallFloat::sqrt` 5,858 / 4,380 at 53 bits and 71,056 / 49,983 at 2,048 bits. Results, flags and representations are identical (differential test against the previous split for every rounding direction, small-range contexts, perfect squares and their neighbours, exact midpoints, all ones and random radicands at precisions 2 to 8,192) ([#438](https://github.com/Luna-Flow/floating/issues/438), section 8).
- `decimal`: the rejection of a quotient without a finite decimal expansion in front of the exact division route (`exact_decimal_division_result`) is the kernel's `has_finite_decimal_expansion_repr` (the quotient is finite iff the part of the divisor prime to 10 divides the dividend, proved in the kernel): the factors 2 and 5 are read from the lowest limb instead of being stripped by two copying divisions, and a divisor prime to 10 needs no unit division. `DecimalFlags::new()` is one shared value and `combine` returns the other operand when one is clear. About 7 to 13 percent fewer instructions for `divide` and `div_ctx` at 16 to 100 digits, 3 to 4 percent at 1000 digits, 2 allocations fewer per contextual `add`, `multiply` and `divide` call; results are unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).
- `bin_float`: the chunk constants of the `exp` bit-burst kernel on Native have their own thresholds, re-measured with the assembly limb rows: up to 2200 working bits (24, 8, 80), up to 2700 bits (24, 8, 120), up to 6000 bits (24, 4, 80), above that (16, 4, 40); the previous setting (24, 8, 80) up to 3000 bits lost 6 to 15 percent against (16, 4, 40) on random arguments between 2300 and 3000 bits. No measured argument is above 1.00 of (16, 4, 40) in the default state or above 1.01 with `LUNA_FLOATING_LIMBS=c`; `sin` and `cos` unchanged; results unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).

- `decimal`: the context forms (`add_ctx`, `mul_ctx`, `div_ctx`, `compare_ctx`, `remainder_ctx`, `quantize_ctx`, `sqrt_ctx`, the unary and elementary context forms, `hypot_ctx`, `atan2_ctx` and the like) no longer pass their operands through a preparation step that returned the operand and empty flags. Six allocations less per call of `add_ctx`, `mul_ctx` and `div_ctx`, 600 to 700 instructions less per call at 16 and 34 digits, results and flags bit-identical. Refs #438.

- `decimal`: `add_ctx`, `sub_ctx`, `mul_ctx`, `div_ctx` and the plain operators `+ - * /` compute the plain case straight from the coefficients: finite nonzero operands, a context with a precision, and a result that is neither absorbed, subnormal, beyond the range, nor folded down by the clamp (a quotient with a finite decimal expansion keeps the general route). The sum is formed and rounded in one limb array, the product and the quotient are rounded once with the kernel's scalar entries, and the flag sets are shared constants. At 34 digits `add_ctx` makes 5 allocations and 1,739 instructions instead of 20 and 4,427, `mul_ctx` 8 and 2,500 instead of 14 and 3,251, `div_ctx` 13 and 3,840 instead of 38 and 9,212; the plain operators gain about as much (`+` 6 and 1,933, `*` 9 and 2,637, `/` 14 and 4,010, from 21, 4,515, 15, 3,339, 39 and 9,348). Results and flags are bit-identical; the general route stays the definition and a white-box test compares both. Refs #438.

- `decimal_gda`: `sqrt` of an operand that is certainly not a square takes one integer root instead of two. The exactness test (a first root of the operand) and the second root with its midpoint comparison (three products as long as the radicand) are replaced by one root of the scaled operand: the root is exact iff the remainder is 0, and the result rounds up iff the remainder exceeds the root, one comparison. An operand is taken when its exponent (with its trailing zeros) is odd, or its coefficient is not a square modulo 64, 63, 65 or 11 (a remainder by a word each); squares, and about one non-square in 120, keep the general route and pay five remainders more (+2% to +8%). At 16, 34, 100 and 1000 digits a random operand makes 59.5, 137, 212 and 364 allocations instead of 86, 223, 391 and 693, and 10,978, 28,758, 59,603 and 809,014 instructions instead of 15,471, 44,717, 102,781 and 1,169,638; a near square (`s^2 + 1`) gains 24% to 33%. Results and conditions are bit-identical (white-box test against the general route at the public level). Refs #438.

- `bin_float`: the long division of the rounding path (`bin_coeff_short_div_rem`, so `div`, `div_ctx`, the decimal conversions and every `binary_round_rational`) is recursive from a divisor length that depends on the row tier (Burnikel and Ziegler, "Fast Recursive Division", MPI-I-98-1-022, 1998, Algorithms 1 to 3: 752 limbs on the assembly rows, 352 on the C rows, 208 on the portable loops, each measured so that no size is more than 3 percent slower than the better algorithm of its tier), instead of Knuth's quadratic division at every size; the divisor is padded to `j * 2^k` limbs (Algorithm 3, steps 1 and 2) instead of the next power of two, which also makes `Coeff::div_rem_checked` 0.7 to 0.9 times the instructions of the old recursive division and removes its loss against Knuth below the threshold (the threshold was 96 limbs, where the recursion took 1.2 to 2 times Knuth's instructions). Instructions per `BinFloat::div` of two full-width operands, native, assembly rows: 65,536 bits 7.32M / 6.39M, 125,000 bits 26.2M / 16.9M, 250,000 bits 104M / 50.6M, 500,000 bits 414M / 149M, 1,000,000 bits 1.65G / 470M (the cost per doubling from 250,000 to 1,000,000 bits falls from 3.99 to 3.04; 8,192 bits and below are unchanged); C rows 1,000,000 bits 2.93G / 574M, portable loops 5.38G / 817M. Quotients, remainders, rounding bits and flags are those of Knuth's division by construction (differential tests against Knuth around every padding boundary, unbalanced shapes, and constructed round and sticky bits in five rounding directions). The Wasm, Wasm-GC and LLVM thresholds stay at 96 limbs ([#560](https://github.com/Luna-Flow/floating/issues/560), [#438](https://github.com/Luna-Flow/floating/issues/438)).
- `bin_float`: the series path of `sin`, `cos` and `tan` below the bit-burst threshold takes `pi / 2` and `pi / 4` from the cached `pi` enclosure by changing the exponent (exact) instead of four directed products by 1/2 per call. About 4,700 instructions and 4 allocations fewer per call at 53 to 2048 bits of precision: 0.91 to 0.97 of before at 53 bits, 0.93 to 0.97 at 128, 0.96 to 0.99 at 512; results unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).
- `bin_float`: `sin`, `cos` and `tan` of an argument that needs the reduction (|x| above about pi/4) evaluate the series once at the midpoint of the reduced interval and add the half-width, rounded upward, to the radius (sine and cosine are 1-Lipschitz), instead of one series at each end; the widened enclosure is clamped to the range bounds -1 and 1 and, for a one-signed sine, to its sign (a bound the true value sits on must not be crossed: the first form of this change returned an error for the directed rounding of `cospi` of a tiny argument). Instructions per call of the public functions, before and after (two builds, median of five, differences of at least 52 million instructions, control rows `sin(0.3)` and `exp(1.3)` within 2.1% across the builds): `sin` and `cos` of 1.3, 3.7 and 123456.789 take 0.67 to 0.77 of the instructions at 53 and 128 bits and 0.58 to 0.61 at 512 bits, `tan` 0.63 to 0.69 at 53 and 128 bits, 0.56 to 0.58 at 512 bits and 0.52 at 2,048 bits; `sin` and `cos` at 2,048 bits and the arguments below pi/4 are unchanged (the bit-burst kernel does not use this path); results unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438)).

- `bin_float`: `sqrt_ctx` of a value of one word at a precision of up to 60 bits (the binary64 and binary32 contexts, every rounding direction) takes the word route of the public `sqrt`: the root and remainder of the radicand on two words, rounded in the direction of the context from the round bit and the sticky bit, in place of a `Coeff` and the general rounding (`binary_round_sqrt`, which stays the path for wider values and for results outside the normal range of the context: subnormal, overflowing, or at the range limits). Results, flags and representations are identical (differential test against the general path in all five directions, small and large ranges, perfect squares and their neighbours, exact ties of the precision, all ones). Instructions per call on native: `sqrt_ctx` at 53 bits 1,985 / 693 (the public `sqrt` takes 378), the binary64 context with `e_max` 1,023 1,984 / 692, round toward zero 1,976 / 692, the binary32 context 2,306 / 690, `BallFloat::sqrt` at 53 bits 4,553 / 1,869 ([#438](https://github.com/Luna-Flow/floating/issues/438), section 8).

- `decimal_gda`: the small-value fast paths of `add`, `subtract`, `multiply` and `divide` (operands of one limb, precision up to 18 digits) make 4 allocations per call instead of 8: the operands are read as words (an `Option[UInt64]` is a heap object), and the conditions Rounded and Inexact are raised through shared constants by `complete_gda_raised`, as `gda_add_plain` already did, instead of an engine flag record and its conversion. At 16 digits `add`, `multiply` and `divide` take 1,126, 1,130 and 1,170 instructions instead of 1,666, 1,661 and 1,703 (-32%). Values, conditions, status and traps are unchanged (differential tests against the general route). Refs #438.
- `decimal`, `decimal_gda`: the integer square root of the shared coefficient kernel is Zimmermann's Karatsuba square root (`SqrtRem`, INRIA RR-3805) on limbs of base 10^9 from three limbs on, instead of Newton's iteration with a full division per step: 3.8 to 6 times fewer instructions at every size from 3 to 512 limbs (3 limbs 7,967 to 2,096; 8 limbs 24,168 to 6,465; 128 limbs 341,256 to 66,536; 512 limbs 3,627,494 to 594,956), with identical roots and remainders. A new scalar entry `dec_coeff_sqrt_rounding` returns the root and how the remainder compares with it, which is all the rounding of a root needs; `decimal_gda`'s `sqrt` uses it: at 16, 34, 100 and 1000 digits a random operand takes 4,311, 10,252, 16,091 and 155,690 instructions instead of 11,003, 28,762, 59,619 and 810,983 (allocations 21.8, 46, 57.5 and 98 instead of 59.5, 137, 212 and 364), a near square gains 65% to 87%, a square 62% to 77% from 34 digits. Refs #438.

- `decimal_gda`: `add` and `subtract` of operands of up to four limbs (36 digits) in an extended context of at most 36 digits take a fast path (`gda_fast_wide_sum`): the operands are read into 128-bit words, aligned, summed and rounded once there, and the result is written to its four limbs in one array, instead of the limb accumulators and the rounding in place of `gda_add_plain`. A 34-digit `add` takes 1,922 instructions instead of 2,266 (-15%); the allocations stay at 6 (the result array is two objects, its coefficient box, the `Decimal`, the outcome and the context copy). Values, conditions, status and traps are unchanged (differential tests against the general route, ties, carries, cancellation and the edges of the 128-bit arithmetic). Refs #438.
- `decimal`, `decimal_gda`: the product of an unbalanced pair of coefficients (the longer operand more than twice the shorter) below the Karatsuba threshold takes the column schoolbook of the balanced case instead of a per-product loop that cost about 45 instructions a product: 4.7 to 5 times fewer instructions (a 20 by 270 limb product 250,515 to 57,148, 112 by 270 limbs 1,353,343 to 272,595, 150 by 1000 limbs 6,691,949 to 1,344,509); balanced products are unchanged. Results are bit-identical. Refs #438.
- `decimal_gda`: the exact decimal expansion of a binary endpoint (`decimal_exact_dyadic_endpoint`, used by the certified `ln`, `log10` and the other certified functions that round a binary enclosure) no longer passes through a host big integer: the binary coefficient is read from its big-endian bytes into decimal limbs (Horner by words of 32 bits) and multiplied by the power of two or five in the kernel, instead of a `BigInt` product converted to decimal limbs by the quadratic conversion. `ln` takes 5.8%, 7.1%, 12.5% and 17.8% fewer instructions at 16, 34, 100 and 1000 digits (`exp` does not use this route: no change). Values are bit-identical (differential tests against the previous route). Refs #438.

- `bin_float`: the limb pass of the wide sum (`add` and `sub` above two words, `binary_coeff_fast_add_parts`) is a row primitive of the kernel, `bin_limbs_window_combine`, with a C body (four limbs per iteration, one carry chain, one specialised loop per combination of shifted and unshifted operand) on the native tiers for windows of 14 limbs and more, and a rewritten portable body (one loop per combination of shifted operands) elsewhere; the results are those of the previous loop (differential test against it). There is no assembly body yet, so the assembly tier runs the C body. Instructions per call of `add` on native: 2,048 bits 1,971 / 1,773 (C and assembly tiers), 1,972 / 1,885 (portable loops); 8,192 bits 3,619 / 2,481 and 3,621 / 3,154; 512 bits 1,263 / 1,219 on all tiers; `sub` the same within 1 percent; the two-word path (128 bits) is unchanged ([#438](https://github.com/Luna-Flow/floating/issues/438), section 8).

- `ball_float`: `exp` and `ln` of a point ball (`lo == hi`) make one certified evaluation instead of two. `BinFloat::try_exp_directed_pair` and `BinFloat::try_ln_directed_pair` (new, public) return exactly the values of `try_exp_ctx` or `try_ln_ctx` under `RoundTowardNegative` and `RoundTowardPositive` for every operand (or the error of the first call that fails), taking both from one certified enclosure where one decides them (a correctly rounded directed value does not depend on the working precision at which it was certified) and answering every other operand with the two calls themselves; results are bit identical (checked against the kept two-call route on a corpus at several precisions). Instructions and allocations per call, same executable, two-count method, median of five runs (range in brackets), every difference at least 58 million instructions:

  | call | precision | instructions before | instructions after | allocations before | allocations after |
  | --- | --- | --- | --- | --- | --- |
  | `BallFloat::try_exp` | 53 | 81,031 (80,744 to 82,902) | 44,356 (42,739 to 44,533) | 130 | 65 |
  | `BallFloat::try_exp` | 256 | 162,270 (159,747 to 163,796) | 85,705 (85,644 to 85,896) | 233 | 122 |
  | `BallFloat::try_exp` | 1024 | 618,906 (607,273 to 621,738) | 316,107 (312,217 to 317,505) | 487 | 249 |
  | `BallFloat::try_ln` | 53 | 204,869 (204,271 to 205,450) | 106,633 (106,513 to 106,669) | 294 | 147 |
  | `BallFloat::try_ln` | 256 | 564,721 (563,814 to 573,846) | 288,244 (286,092 to 295,024) | 801 | 406 |
  | `BallFloat::try_ln` | 1024 | 1,107,675 (1,089,874 to 1,118,904) | 566,072 (564,804 to 567,397) | 1,401 | 706 |

## 0.11.0 - 2026-11-20

0.11.0 is the performance round of the binary and decimal cores (64-bit coefficient limbs, the certified elementary functions, the shared decimal kernel), the conformance additions (the remaining IEEE 754-2019 §9.2 functions, `convert_format`, totalOrder, `class_of`, and the fixes that the differential campaigns found), and step B of [#22](https://github.com/Luna-Flow/floating/issues/22): the library module is split from the developer tools, public surfaces are narrowed and operations are named after their standards. The breaking changes come first, with their migration tables; 0.12 completes them ([#438](https://github.com/Luna-Flow/floating/issues/438)).

### Breaking

- `decimal`: the `_ctx` suffix on the contextual operations ([#22](https://github.com/Luna-Flow/floating/issues/22), rows D14 and D15 of the naming decisions). `_ctx` marks a method that takes a context and returns the value with its flags; the nine methods below did, without the suffix. The checked tier keeps bare names (`DecimalChecked::quantize` is unchanged). No other change: same arguments, same results.

  | before | after |
  | --- | --- |
  | `Decimal::quantize`, `rescale` | `quantize_ctx`, `rescale_ctx` |
  | `Decimal::divide_integer` | `divide_integer_ctx` |
  | `Decimal::to_integral_exact`, `to_integral_value` | `to_integral_exact_ctx`, `to_integral_value_ctx` (as in `bin_float`) |
  | `Decimal::logical_and`, `logical_or`, `logical_xor`, `logical_invert` | `logical_and_ctx`, `logical_or_ctx`, `logical_xor_ctx`, `logical_invert_ctx` |

- `decimal`, `decimal_checked`: IEEE names ([#22](https://github.com/Luna-Flow/floating/issues/22), rows D08 word order, D10 to D13 of the naming decisions). The names follow IEEE 754-2019; there are no aliases, and the calls in this release's library, tooling, tools and manual are migrated.

  | before | after | note |
  | --- | --- | --- |
  | `Decimal::minimum_number_magnitude_ctx`, `maximum_number_magnitude_ctx` | `minimum_magnitude_number_ctx`, `maximum_magnitude_number_ctx` | IEEE word order (`minimumMagnitudeNumber`) |
  | `Decimal::power_ctx`, `try_power_ctx`; `DecimalChecked::power` | `pow_ctx`, `try_pow_ctx`; `DecimalChecked::pow` | the IEEE `pow` (§9.2) |
  | `Decimal::compare_total` | `total_order_compare` | three-way, same order |
  | (new) | `Decimal::total_order`, `total_order_mag` | the booleans of IEEE 754-2019 §5.10 (`x` at or before `y`, and of the absolute values), as in `bin_float` |
  | `Decimal::compare_total_magnitude` | `a.abs().total_order_compare(b.abs())`, or `total_order_mag` | |
  | `Decimal::compare_total_ctx`, `compare_total_magnitude_ctx` | `total_order_compare`, `total_order_mag` | the `_ctx` forms first rounded the operands into the context (subset mode only) and returned flags; totalOrder takes no context and raises no flag |
  | `Decimal::remainder` (truncating, GDA) | `remainder_trunc_ctx` | this is the old truncating `remainder`; the IEEE remainder is `remainder_ctx` and was not renamed. A call that meant the truncating remainder must not end up on `remainder_ctx`: the results differ (`remainder(10, 6)` is `4`, `remainder_ctx(10, 6)` is `-2`) |
  | `Decimal::next_minus`, `next_plus`, `next_toward` | `next_down_ctx`, `next_up_ctx`, `next_toward_ctx` | IEEE `nextDown`, `nextUp`; the checked tier keeps bare names: `DecimalChecked::next_down`, `next_up`, `next_toward` replace `next_minus`, `next_plus`, `next_toward` |

- `decimal_gda`: `max_mag` and `min_mag` are spelled out ([#22](https://github.com/Luna-Flow/floating/issues/22), naming row G07; `max`, `min`, `max_ctx` and `min_ctx` keep their names, as GDA 1.70 names the operations `max`, `min`, `max-magnitude` and `min-magnitude`). The old names are removed without an alias; `decimal` and `decimal_gda_checked` are not affected. Migration:

  | before | after |
  | --- | --- |
  | `decimal_gda::max_mag`, `decimal_gda::min_mag` (free functions) | `decimal_gda::max_magnitude`, `decimal_gda::min_magnitude` |
  | `Decimal::max_mag_ctx`, `Decimal::min_mag_ctx` | `Decimal::max_magnitude_ctx`, `Decimal::min_magnitude_ctx` |

- `decimal`, `decimal_checked`: one spelling per operation ([#22](https://github.com/Luna-Flow/floating/issues/22), rows D01 to D03, D05 to D09, D12 and D17 of the naming decisions). `decimal` is named after IEEE 754-2019; the General Decimal Arithmetic spellings and operations are removed and live in `decimal_gda`. There are no aliases. The calls in this release's library, tooling, tools and manual are migrated.

  | removed | use instead | note |
  | --- | --- | --- |
  | `Decimal::is_signed` | `is_negative` | same predicate |
  | `Decimal::is_qnan`, `is_snan` | `is_quiet_nan`, `is_signaling_nan` | same predicates |
  | `Decimal::magnitude` | `coefficient` | same value |
  | `Decimal::from_integer`, `from_natural` (inherent methods) | `Decimal::from_bigint(n).normalized()`, or `from_bigint(n)` | the `FromInteger` and `FromNat` trait implementations stay and return `from_bigint(n).normalized()`, so trailing zeros are removed (`100` is `1E+2`); plain `from_bigint(n)` keeps exponent 0 |
  | `Decimal::normalize_ctx` | `reduce_ctx` | same operation |
  | `Decimal::copy_abs`, `copy_negate` | `abs`, `neg` | same operations (`DecimalInterchange::copy_abs` and `copy_negate` are unchanged) |
  | `Decimal::minimum_mag_ctx`, `maximum_mag_ctx`, `minimum_number_mag_ctx`, `maximum_number_mag_ctx` | `minimum_magnitude_ctx`, `maximum_magnitude_ctx`, `minimum_number_magnitude_ctx`, `maximum_number_magnitude_ctx` | same operations |
  | `Decimal::min_ctx`, `max_ctx`, `min_mag_ctx`, `max_mag_ctx` | `decimal_gda` `Decimal::min_ctx` and its siblings for the GDA operation; `minimum_number_ctx`, `maximum_number_ctx`, `minimum_number_magnitude_ctx`, `maximum_number_magnitude_ctx` for the IEEE one | not the same: a signaling NaN with a number gives the number and `invalid_operation` (GDA: a quiet NaN and `invalid_operation`), and there is no subset-mode left-operand tie rule |
  | `DecimalChecked::min`, `max` | `minimum_number`, `maximum_number` | wrappers of `minimum_number_ctx` and `maximum_number_ctx`; a signaling NaN with a number gives the number and `invalid_operation`, equal operands give either member without a total-order choice; the GDA `min` and `max` are in `decimal_gda_checked` |
  | `Decimal::remainder_near` | `remainder_ctx` | the IEEE remainder; `remainder_ctx` now holds the implementation, no change of result |
  | `Decimal::class_name` | `class_of` | returns an `IeeeClass`; there is no text form, match on the class |

- `decimal_gda`: one spelling per operation ([#22](https://github.com/Luna-Flow/floating/issues/22), naming rows G01 to G06, G08 and G09; the name of an operation follows GDA 1.70 and there is no alias). Twenty-three methods of `Decimal` are removed; `decimal_gda_checked` had none of them. The `decimal` package is not affected. Migration:

  | row | removed | use instead |
  | --- | --- | --- |
  | G01 | `Decimal::is_negative` | `Decimal::is_signed` |
  | G02 | `Decimal::is_quiet_nan`, `Decimal::is_signaling_nan` | `Decimal::is_qnan`, `Decimal::is_snan` |
  | G03 | `Decimal::magnitude` | `Decimal::coefficient` |
  | G04 | `Decimal::get_payload`, `Decimal::set_payload`, `Decimal::set_payload_signaling` | `Decimal::nan_payload` for reading; the IEEE 754-2019 §9.7 operations are in `decimal`; to build a NaN with a payload, `Decimal::quiet_nan(payload=)` and `Decimal::signaling_nan(payload=)` |
  | G05 | `Decimal::from_integer`, `Decimal::from_natural` (the inherent forms of the `FromInteger` and `FromNat` implementations, which stay) | `FromInteger::from_integer` and `FromNat::from_natural`, or `Decimal::from_bigint(n).normalized()` (note: `Decimal::from_bigint(n)` alone keeps trailing zeros, `1200` rather than `1.2E+3`) |
  | G06 | `Decimal::normalize_ctx` | `Decimal::reduce_ctx` |
  | G08 | `Decimal::minimum_ctx`, `maximum_ctx`, `minimum_number_ctx`, `maximum_number_ctx`, `minimum_magnitude_ctx`, `maximum_magnitude_ctx`, `minimum_number_magnitude_ctx`, `maximum_number_magnitude_ctx` and the four `*_mag_ctx` forms of the magnitude variants | the GDA operations `min_ctx`, `max_ctx`, `min_mag_ctx`, `max_mag_ctx` (they return the number when one operand is a quiet NaN, as `minimumNumber` and `maximumNumber` do); the IEEE 754-2019 §9.6 variants are in `decimal` |
  | G09 | `Decimal::remainder_ctx` | `Decimal::remainder_near` (the IEEE remainder; `remainder` is the truncating GDA remainder) |
- `decimal`, `decimal_gda`: `DecimalContext::new` (both packages) and `GdaContext::new` return the context and abort on an invalid parameter, and `try_new` returns `Result[_, ArithmeticError]`, the shape of `BinaryContext::new` and `BinaryContext::try_new` (part of step B of [#22](https://github.com/Luna-Flow/floating/issues/22)). The abort message names the parameter (`DecimalContext::new: precision must be within 1..=999999999`); the `Err` messages of `try_new` are the ones `new` returned before. The presets and `exact()` are unchanged, and the free function `decimal_gda.context(...)` still returns a `Result`. Migration: `X::new(...).unwrap()` becomes `X::new(...)`; code that handles the error (a `match`, `is Err(_)`, a returned `Result`) calls `X::try_new(...)`, which until now was an alias of the old `new`.
- `bin_float` and `bin_float_checked`: IEEE 754-2019 names for the integer power and the quiet and signaling comparisons ([#22](https://github.com/Luna-Flow/floating/issues/22)). The two names of the integer power are one, `pown`; the seven comparison predicates take the standard's word order (§5.6.1). The old names are removed without alias. Migration:

  | removed | replacement |
  | --- | --- |
  | `BinFloat::pow_int(n)` | `BinFloat::pown(n)` |
  | `BinFloat::pow_int_ctx(n, ctx)` | `BinFloat::pown_ctx(n, ctx)` |
  | `BinFloatResult::pow_int(n)` | `BinFloatResult::pown(n)` |
  | `BinFloatResult::pow_int_ctx(n, ctx)` | `BinFloatResult::pown_ctx(n, ctx)` |
  | `BinFloat::equal_quiet` | `BinFloat::compare_quiet_equal` |
  | `BinFloat::equal_signaling` | `BinFloat::compare_signaling_equal` |
  | `BinFloat::less_quiet` | `BinFloat::compare_quiet_less` |
  | `BinFloat::less_signaling` | `BinFloat::compare_signaling_less` |
  | `BinFloat::less_equal_quiet` | `BinFloat::compare_quiet_less_equal` |
  | `BinFloat::less_equal_signaling` | `BinFloat::compare_signaling_less_equal` |
  | `BinFloat::unordered_quiet` | `BinFloat::compare_quiet_unordered` |

  The `PowIntChecked::pow_int_checked` implementation of `BinFloat` (a trait of `Luna-Flow/arithmetic`) and `BallFloatResult::pow_int` are not touched. `decimal` has no method under the old comparison names.
- `bin_float`: `BinCoeff` has no arithmetic any more ([#22](https://github.com/Luna-Flow/floating/issues/22), step B2): a coefficient can be built (`zero`, `one`, `from_uint64`, `from_bytes_be`, `parse`), converted (`to_uint64`, `to_bytes_be`, `to_string`, `to_radix_string`, `Show`), compared (`compare`, `Eq`, `Compare`) and queried (`is_zero`, `bit_length`), and nothing else. The arithmetic and bit operations moved into the internal kernel package, which only code inside this module can import. `Debug` of `BinCoeff` prints the integer value instead of the representation. The type is now `pub(all) struct BinCoeff(@bin_kernel.Coeff)`: the inner type belongs to the internal package, carries no compatibility promise and is inert outside the module (a method call, `==` and an import of its package are all rejected), so the field exposes no operation.

  | removed | replacement |
  | --- | --- |
  | `BinCoeff::add`, `mul`, `square`, `pow_nat`, `sub_checked`, `div_rem_checked`, `gcd`, and the `Add` and `Mul` implementations (`+`, `*`) | do the arithmetic on `BinFloat` (`add`, `mul`, `div`, `sqrt`, `pown` at a precision large enough to be exact), or convert with `to_string` or `to_bytes_be` and use `BigInt` |
  | `BinCoeff::shift_left`, `shift_right`, `shl`, `shr`, and the `Shl` and `Shr` implementations (`<<`, `>>`) | `BinFloat::scaleb_ctx` (multiplication by a power of two) or `BigInt` |
  | `BinCoeff::bit_and`, `bit_or`, `bit_xor` | convert to `BigInt` or work on `to_bytes_be` |
  | `BinCoeff::ctz`, `test_bit` | `to_bytes_be`, or `BinFloat::exponent2` for the trailing zeros of a normalized value |

  The tools module follows: the benchmark `bin-float/autotune/square` (the crossover of `mul(x, x)` against `square(x)` on a coefficient), its test and `just bench auto-tune` are removed, because they measured an internal function; the arithmetic benchmarks use `BigInt` for the `kernel/coefficient` baseline and for the expected results. Refs [#22](https://github.com/Luna-Flow/floating/issues/22).
- `decimal_gda`: the free functions `decimal32_context()`, `decimal64_context()` and `decimal128_context()` are removed (part of step B of [#22](https://github.com/Luna-Flow/floating/issues/22)). Migration: `GdaContext::decimal32()`, `GdaContext::decimal64()` and `GdaContext::decimal128()` return the same shared preset values. The free function `context(...)` stays.
- `decimal_gda`: `GdaOutcome` is `pub enum` instead of `pub(all) enum` (part of step B of [#22](https://github.com/Luna-Flow/floating/issues/22)). Code outside the package can still `match` on `Completed` and `Trapped` and use `value`, `next_context` and `raised`, but can no longer construct a `GdaOutcome` or mutate one; only the GDA operations produce it. Migration: to continue after a trap with the defined result, call the new `GdaOutcome::resume_defined(Self) -> Self` (`Completed` unchanged, `Trapped(s, v, C, R)` becomes `Completed(v, C, none)`) instead of building `Completed(v, C, GdaFlags::none())`. `GdaDecimalChecked::resume_defined` now uses it; nothing else in the library, tooling or manual constructed an outcome.
- `bin_float`, `bin_float_checked`: the `exp_ln` family is removed ([#22](https://github.com/Luna-Flow/floating/issues/22), step B1): `BinFloat::exp_ln`, `BinFloat::exp_ln_ctx`, `BinFloat::try_exp_ln_ctx`, `BinFloatResult::exp_ln` and `BinFloatResult::exp_ln_ctx`. It computed $\ln(e^x) = x$ and was certified only for $|x| \le 1/8$ (any other finite argument was a certification failure), it is not an IEEE 754-2019 operation, and the decimal packages have no counterpart. Migration: none needed; the value was $x$ rounded once into the context, which is `x.round_ctx(context)` (or `plus`). `ball_float` and `ball_float_checked` had no wrapper of it.
- `bin_float`: three public items without a user outside the package are gone ([#22](https://github.com/Luna-Flow/floating/issues/22)). `sqrt_for_precision` and `sqrt_bounds_for_precision` are private: use `BinFloat::sqrt_ctx` with `BinaryContext::unbounded(precision)` for the root at another precision, and the same call under `RoundTowardNegative` and `RoundTowardPositive` for the two bounds. `BinaryFlags::to_testfloat_bits` is removed: the five flags are read with `inexact()`, `underflow()`, `overflow()`, `division_by_zero()` and `invalid_operation()`; the TestFloat mask is inexact `0x01`, underflow `0x02`, overflow `0x04`, divideByZero `0x08`, invalid `0x10`, and the TestFloat front end in `tooling/` builds it itself.
- `bin_float_checked`: the deprecated `BinFloatResult::flat_map` is removed ([#22](https://github.com/Luna-Flow/floating/issues/22)); use `BinFloatResult::bind`.
- `bin_float_checked`: one flag rule for all 46 `BinFloatResult::*_ctx` methods ([#371](https://github.com/Luna-Flow/floating/issues/371)). `x_ctx` is `x` with an explicit context and the same map: invalid operation is `Err(DomainError)`, divideByZero is `Err(DivisionByZero)`, overflow, underflow and inexact are dropped. The 39 elementary methods already followed it; the seven arithmetic methods `add_ctx`, `sub_ctx`, `mul_ctx`, `div_ctx`, `sqrt_ctx`, `pow_int_ctx` and `pown_ctx` changed. No signature changes. Migration: for the raw IEEE default result together with its flags, call the unwrapped `BinFloat::div_ctx` and its siblings, which still return `(value, flags)`.

  | case | before | after |
  | --- | --- | --- |
  | `div_ctx(x, +-0)`, `x` finite nonzero; `pown_ctx(+-0, n)` (called `pow_int_ctx` or `pown_ctx` before this release) with `n < 0` | `Ok(+-inf)` | `Err(DivisionByZero)` |
  | `div_ctx(0, 0)`, `div_ctx(inf, inf)`, `add_ctx(+inf, -inf)`, `sub_ctx(inf, inf)`, `mul_ctx(0, inf)`, `sqrt_ctx(x < 0)` | `Ok(NaN)` | `Err(DomainError)` |
  | a signaling NaN operand | `Ok(NaN)` | `Err(DomainError)` |
  | quiet NaN operand, overflow, underflow, inexact | unchanged | unchanged |

- **Breaking**: the library module `Luna-Flow/floating` now imports `Luna-Flow/arithmetic` and `Luna-Flow/luna-generic` only ([#22](https://github.com/Luna-Flow/floating/issues/22), step A). Everything that needs `Luna-Flow/mare_mark`, `moonbitlang/async`, `moonbitlang/x` or `Luna-Flow/type_theory` moved to a second module of this repository, `Luna-Flow/floating-tools` (directory `tooling/`, not published), which depends on the library from the same working tree. The repository is a `moon.work` workspace of the two modules. Consumers of the library no longer resolve the four tooling modules. These packages left the published module; their import paths change from `Luna-Flow/floating/<package>` to `Luna-Flow/floating-tools/<package>` and they are no longer part of the published module: `bench`, `bench/ball_float`, `bench/bin_float`, `bench/decimal`, `bench/decimal_gda`, `bench/external`, `cli`, `cli/gda_expr_cli`, `cli/itl_expr_cli`, `cli/mpfr_expr_cli`, `cli/testfloat_expr_cli`, `differential`, `frontend/gda_expr`, `frontend/itl_expr`, `frontend/mpfr_expr`, `frontend/testfloat_expr`, `numeric_expr`, `doc_examples`, `internal/conformance` and `internal/runner_cli`. Anyone who imported the frontends, the CLI or the bench packages from `Luna-Flow/floating` must instead build inside this repository's workspace (a `tooling/` package imports them by the new path) or copy the packages; they are not published to mooncakes. The public interfaces of the numeric packages (`bin_float`, `decimal`, `decimal_gda`, `ball_float`, the `*_checked` tiers, `def`, `semantic`, `consistency`) are unchanged. `moon check`, `moon test`, `moon fmt` and `moon info` run from the repository root cover both modules; `-p <package>` or a package path narrows a command (see CONTRIBUTING.md, "Two modules"). Known limit: `moon package` has no exclusion, so the zip of the library still contains `tooling/` as plain files, like `doc/`, `testdata/` and `tools/`; no tooling package is part of the library.
- **Breaking**: the package `semantic` (exact, representation-independent projection of `BinFloat`, `Decimal` and `BallFloat` values: `ExactRational`, `SemanticScalar`, `SemanticInterval`, `SemanticResult`, `SemanticError`) moved from the library module to the tools module `Luna-Flow/floating-tools` ([#22](https://github.com/Luna-Flow/floating/issues/22), step B7). Replacement: import `Luna-Flow/floating-tools/semantic` (a package of the workspace, or the published tools module once it is published); the package, its interface and its results are unchanged. It was a provisional integration surface used only by `consistency` and the documentation examples, which are tools too; the published package no longer contains it. The `SemanticScalar`, `SemanticResult` and `SemanticError` enums stay `pub(all)` because the cross-package tests and the manual construct expected values. Its exact rational (`ExactRat`) is private code of the package since it stopped importing `internal` ([#22](https://github.com/Luna-Flow/floating/issues/22), step B7); `internal` lost `ExactRat` (it cannot be imported outside the module) and the helper tests of `consistency` moved into `internal`.
- **Breaking**: the package `consistency` (cross-package laws and API audits, white-box tests only, no public items) moved from the library module to the tools module `Luna-Flow/floating-tools` ([#22](https://github.com/Luna-Flow/floating/issues/22), step B7). Its import path is `Luna-Flow/floating-tools/consistency`; it exported nothing, so no program that depends on the library is affected, and its 254 tests run in the workspace like before (`moon test -p Luna-Flow/floating-tools/consistency`, `just pr`). The published package no longer contains it. Tests of the cross-package laws go to `tooling/src/consistency`.

### Added

- `decimal`: `Decimal::total_order` and `total_order_mag`, the boolean totalOrder and totalOrderMag predicates of IEEE 754-2019 §5.10 (see Breaking for the renamed three-way `total_order_compare`). The §5.10 corpus (all matrix cells of the four formats) runs against both the boolean and the three-way form.

- `decimal`: the public constants `decimal_implementation_e_max` (999,999,999), `decimal_implementation_e_min` (-999,999,999) and `decimal_precision_max` (999,999,999), the counterpart of `binary_implementation_e_max`, `binary_implementation_e_min` and `binary_precision_max` ([#22](https://github.com/Luna-Flow/floating/issues/22)). They are the limits `DecimalContext::try_new` (and `new`) already enforced, now named, and the validation uses them, so the values cannot drift. The certified elementary functions keep their own lower limit (`|e| <= 999999`, `p <= 999999`), described in the manual. No behaviour changes.

- `decimal_gda`: `GdaOutcome::resume_defined(Self) -> Self`, the GDA continuation of a trapped operation with its defined result: `Completed` is unchanged, `Trapped(s, v, C, R)` becomes `Completed(v, C, none)`. It was added with the read-only `GdaOutcome` of step B ([#22](https://github.com/Luna-Flow/floating/issues/22)); `GdaDecimalChecked::resume_defined` calls it.
- `decimal_checked`: `DecimalChecked::minimum_number` and `maximum_number`, the checked wrappers of `minimum_number_ctx` and `maximum_number_ctx` (they replace `min` and `max`, see Breaking).

- `def`, `bin_float`, `decimal`: the ten-valued `IeeeClass` of IEEE 754-2019 §5.7.2 (`SignalingNaN`, `QuietNaN`, `NegativeInfinity`, `NegativeNormal`, `NegativeSubnormal`, `NegativeZero`, `PositiveZero`, `PositiveSubnormal`, `PositiveNormal`, `PositiveInfinity`) in `def`, with `BinFloat::class_of(Self, BinaryContext) -> IeeeClass` and `Decimal::class_of(Self, DecimalContext) -> IeeeClass` ([#224](https://github.com/Luna-Flow/floating/issues/224)). `BinFloat` also gets the predicates `is_normal(Self, BinaryContext)`, `is_subnormal(Self, BinaryContext)`, `is_finite`, `is_infinite` and `is_nan`, as `Decimal` has them. Normal and subnormal compare the leading-bit exponent with the context's `e_min`. `classify`, `is_negative` and `Decimal::class_name` are unchanged, and `class_name` is the text of `class_of`.

- `bin_float`: `BinFloat::convert_format(Self, BinaryInterchangeFormat, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> (BinFloat, BinaryFlags)`, the IEEE 754-2019 §5.4.2 formatOf-convertFormat operation with the parameters of `to_interchange` and the value instead of the encoding ([#222](https://github.com/Luna-Flow/floating/issues/222)): a wider destination is exact, a narrower one rounds with `inexact`, `underflow` and `overflow`, a signaling NaN gives a quiet NaN and `invalid` (also for the same format), and a NaN payload that does not fit is truncated to its low bits (6.2.3). `round_ctx` and `to_interchange` are unchanged. The TestFloat binary gate runs all twelve format pairs among binary16, 32, 64 and 128 (52,632 vectors at level 1, all passing; 2,734,536 at level 2, all passing).

- `decimal`: `DecimalContext::with_clamp_fold(Self, Bool) -> Self` and `DecimalContext::clamp_fold(Self) -> Bool`, off by default and in every preset (`DecimalContext::new` keeps its signature, and the field takes part in `==` like the refinement limit). With it on, and under `clamp`, a zero `quantize` or `rescale` result whose exponent is above `e_max - precision + 1` is folded down to that exponent with `clamped`, as decNumber does (`quantize(0, 1E+380)` in decimal64 is `0E+369 Clamped` instead of `0E+380`); every other operation that produces such a zero already folded. With it off nothing changes ([#234](https://github.com/Luna-Flow/floating/issues/234)).
- `decimal`: `Decimal::to_int_ctx`, `to_int64_ctx`, `to_uint_ctx` and `to_uint64_ctx` of IEEE 754-2019 §5.4.1 and §5.8 (convertToInteger and convertToIntegerExact), each `(Self, DecimalContext, exact? : Bool) -> (integer?, DecimalFlags)` and mirroring the `BinFloat` functions of the same names: the context's rounding direction (the five of §5.8 and the other three of `decimal`), `None` with the invalid operation flag for a NaN, an infinity and an out-of-range value, `inexact` only with `exact=true`. The power of ten of the exponent is never formed (`1E+999999`, `1E-999999`). Closes the `decimal` gap of the conformance table ([#226](https://github.com/Luna-Flow/floating/issues/226)).
- `bin_float`: `BinFloat::from_hex_ctx(String, BinaryContext) -> Result[(BinFloat, BinaryFlags), ArithmeticError]`, the IEEE 754-2019 §5.12.3 conversion from a hexSequence, the counterpart of `from_string_ctx` ([#256](https://github.com/Luna-Flow/floating/issues/256)): the exact value is rounded once under the rounding direction, precision, exponent range (subnormals) and tininess rule of the context, and `inexact`, `underflow` and `overflow` are signaled; `inf`, `nan` and `snan` give the special values without a flag, and a binary exponent beyond the 32-bit range overflows or underflows instead of being a parse error. `from_hex(String, Int32)` is unchanged (it shares the parser). 4,554 rows against exact rational arithmetic; `bin_float_checked` has no `from_string_ctx` or `from_hex` wrapper, so there is none for `from_hex_ctx` either.

- `bin_float`, `decimal` and `decimal_gda`: `BinaryContext::with_refinement_limit` and `BinaryContext::refinement_limit`, and the same pair on the `DecimalContext` of both decimal packages ([#15](https://github.com/Luna-Flow/floating/issues/15)). The limit is the number of refinement steps of the certified elementary functions: `Some(n)` allows `n` (a value below 1 counts as 1), the default `Some(12)` is the former hard-coded value and changes no result, and `None` removes the count limit (the work precision then stops at a cap of at least 8,000,000 bits). Reaching the limit is still a `CertificationFailure` with the refinement count. The limit is part of the context, so contexts that differ only in it are different (`==`). `ball_float` has no context argument and is not part of this change; neither is `GdaContext`, which reaches the certified functions through its `DecimalContext`.
- `decimal`: `Decimal::convert_format`, `Decimal::from_bin_float_ctx` and `Decimal::to_bin_float_ctx` of IEEE 754-2019 §5.4.2 with the flags: `convert_format(Self, DecimalInterchangeFormat)` rounds once into decimal32, decimal64 or decimal128 keeping the quantum of the source; `from_bin_float_ctx(BinFloat, DecimalContext)` rounds the exact binary value once in the context with the preferred exponent of §5.4.2 (0 when exact, `precision` digits when inexact); `to_bin_float_ctx(Self, BinaryContext)` returns the `BinaryFlags`. Signs of zeros and NaNs are kept, a signaling NaN gives a quiet NaN with the invalid operation exception, and a NaN payload is kept when the destination holds it (§6.2.3). `from_bin_float` and `to_bin_float` keep their results. The new rows run both directions through the MPFR `mpfr_strtofr` and `mpfr_get_str` corpora and through exact rows for every pair of decimal32/64/128 and binary16/32/64/128 (`tools/generate_decimal_conversion_rows.py`); the conformance row is `conforming` ([#223](https://github.com/Luna-Flow/floating/issues/223)).
- `decimal`: `asinpi`, `acospi`, `atanpi` and `atan2pi` of IEEE 754-2019 §9.2 (`*_ctx`, `try_*_ctx` and the `DecimalChecked` methods), the last of the recommended functions: `decimal` now has all of §9.2, which closes [#236](https://github.com/Luna-Flow/floating/issues/236). They are the certified enclosures of the angle divided by π in the existing Ziv driver, with the exact constants of §9.2.1 and Niven's other exact values (`atanpi(±1)`, `atan2pi(±a, ±a)`) at the preferred exponent 0, `|x| > 1` invalid, the one-sided clusters next to ±1/2 and ±1 (`atanpi` of a large `|x|`, `acospi` of a tiny `|x|`, `atan2pi` at extreme ratios) decided from a bound on the distance, and tiny results enclosed as a moderate value and shifted, so an operand `1E-1999996` costs what `1E-300` costs. Evidence: 19,134 generated white-box rows (exact arithmetic and certified MPFR 4.2.2 enclosures), 768 new rows of the certified elementary oracle, and `decimal-*` random cases without a disagreement: 400,000 native and 240,000 Wasm, Wasm-GC and JavaScript cases of seed 20261118.
- `decimal`: `rsqrt`, `compound` and `powr` of IEEE 754-2019 §9.2 (`*_ctx`, `try_*_ctx` and the `DecimalChecked` methods), the second step of [#236](https://github.com/Luna-Flow/floating/issues/236). `rsqrt` decides the exact results `x = 2^(2i)*5^(2j)` with the preferred exponent `-floor(Q(x)/2)` and evaluates every other operand as `10^-k / sqrt(s)`, `s` in [1, 100), so extreme operands cost what moderate ones cost; `compound` anchors tiny arguments at 1, forms the exact powers that can sit on a rounding boundary and otherwise certifies `exp(n*log1p(x))` (every `Int32` `n`); `powr` adds the invalid and NaN rows of §9.2.1 to `pow` on `|x|`. Evidence: 14,267 generated white-box rows (exact arithmetic and certified MPFR enclosures, never `mpfr_compound_si`), 576 new rows of the certified elementary oracle, and `decm-*` random cases without a disagreement: 750,000 native and 900,000 Wasm, Wasm-GC and JavaScript cases of seed 20261118 and 1,200,000 of seed 20261202 on all four targets.
- `decimal`: `exp2m1`, `exp10m1`, `log2p1` and `log10p1` of IEEE 754-2019 §9.2 (`*_ctx`, `try_*_ctx` and the `DecimalChecked` methods), the first step of [#236](https://github.com/Luna-Flow/floating/issues/236). They evaluate the certified `expm1(x ln b)` and `log1p(x) / ln b` enclosures in the existing Ziv driver, with the special values of §9.2.1, the exact cases (`2^n - 1`, `10^n - 1`, `1 + x = b^k`) rounded once with the preferred exponent 0 of §9.2.2, the clusters near large integers and near -1, certain overflow and results below the subnormal range decided before the loop. A shared internal layer (`library/src/decimal/elementary_range.mbt`) holds the exact-constant and range decisions; `pow` uses it with unchanged results and instruction counts. Evidence: 10,673 generated white-box rows (exact rational arithmetic and certified MPFR enclosures, all eight rounding modes, both tininess rules, precisions 1 to 220), 768 new rows of the certified elementary oracle, 1,000,000 native `decm-*` random cases and 400,000 on each of Wasm, Wasm-GC and JavaScript (seed 20261118), and a second seed (20261202) of 400,000 cases on each of the four targets, without a disagreement with MPFR 4.2.2.
- `bin_float`: `asinpi`, `acospi`, `atanpi` and `atan2pi` of IEEE 754-2019 §9.2 (`*_ctx`, `try_*_ctx`, the plain form, and the `BinFloatResult` wrappers), the last of the recommended functions: `bin_float` now has all of §9.2 ([#235](https://github.com/Luna-Flow/floating/issues/235)). They are the certified enclosures of the angle divided by π, with the exact constants of §9.2.1 (`atan2Pi` of 0 and ∞, `acosPi(1) = +0`, `atanPi(±∞) = ±1/2`, `atanPi(±1) = ±1/4`, `atan2Pi(±a, ±a) = ±1/4, ±3/4`), the invalid domain, and decisions from a certified distance to the anchors ±1/2 and ±1 for huge, tiny and extreme-ratio arguments (`atanPi` of a huge argument, `acosPi` of a tiny one, `atan2Pi` whose ratio exponent exceeds the range), so that no value is built below the subnormal limit. The oracle generator gains the family `elem4`; 1,000,000 native and 100,000 Wasm, JavaScript and Wasm-GC cases and 1,654,315 range-boundary rows agree with MPFR 4.2.2 (`mpfr_atan2pi` is too slow beyond 100,000 binades of exponent difference, and those rows are skipped and covered by white-box tests). A handover note on the range layer and the oracle findings is in `doc/manual/design/bin_float.md`.
- `bin_float`: `rsqrt`, `compound` and `powr` of IEEE 754-2019 §9.2 (`*_ctx`, `try_*_ctx`, the plain form, and the `BinFloatResult` wrappers) with the special values of §9.2.1 (`rSqrt(±0) = ±∞` with `divideByZero`, `compound(-1, n)`, the invalid pairs of `powr`), exact cases (`rsqrt` of a power of four, `compound` and `powr` through `pown` and `pow`), a tiny-`x` rule for `compound` and certified Ziv rounding, on the range layer of `elementary_range.mbt`; the second step of [#235](https://github.com/Luna-Flow/floating/issues/235) (the π-scaled inverses follow). The oracle generator gains the family `elem3` (the rows of every other family are unchanged) and the boundary sweeper the three functions; 1,000,000 native and 100,000 Wasm, JavaScript and Wasm-GC cases and 718,824 range-boundary rows agree with MPFR 4.2.2 once the oracle is corrected for two MPFR 4.2.2 findings: `mpfr_compound_si` is not correctly rounded for a negative `n` in the directed modes (the generator rounds the exact rational instead) and `mpfr_rec_sqrt(-0)` is +∞ where §9.2.1 says -∞.
- Random differential testing of the IEEE `decimal` elementary functions against MPFR 4.2.2 ([#236](https://github.com/Luna-Flow/floating/issues/236)): `tools/generate_mpfr_decimal_random.py` and `tools/mpfr_decimal_enclosure.c` generate rows whose expected value is the rounding of a certified enclosure (2048-bit operand bounds, 768-bit directed results, one ulp of slack) in random decimal32/64/128 and small, medium and wide contexts, all eight rounding modes, clamp on and off, both tininess rules; the new `mpfr-decimal-random-v1` row kind of `frontend/mpfr_expr` (`parse_decimal_random_data`, `execute_decimal_random_data`) runs them through the `try_*_ctx` forms and compares value, cohort and flags; `just random-diff run --decm` (one `decm-<function>` family per function, opt-in), `replay`, `minimize`, `smoke` and a committed sample of 336 rows (`testdata/decimal/random/mpfr-decimal-random.txt`) cover the 28 existing functions, ready for the IEEE 754 §9.2 functions that `decimal` does not have yet.
- `bin_float`: `exp2m1`, `exp10m1`, `log2p1` and `log10p1` of IEEE 754-2019 §9.2 (`*_ctx`, `try_*_ctx`, the plain form, and the `BinFloatResult` wrappers), correctly rounded in every direction and both tininess modes, with the special values of §9.2.1, exact cases (`2^n - 1`, `10^n - 1`, `log2(2^k)`, `log10(10^k)`) and certain overflow and saturation decided before the Ziv loop. They take their range decisions from a new internal layer (`elementary_range.mbt`), the first step of [#235](https://github.com/Luna-Flow/floating/issues/235) (`rSqrt`, `compound`, `powr` and the π-scaled inverses follow). The oracle generator gains the family `elem2` for them (the rows of `elem` and every other family are unchanged); the verification page records 1,000,000 native and 100,000 Wasm, JavaScript and Wasm-GC cases and a 303,108-row range-boundary sweep, without a disagreement with MPFR 4.2.2.
- Seeded random differential testing against MPFR 4.2.2 (binary) and libmpdec 4.0.0 (decimal), run through the mare_mark harness: `tools/generate_mpfr_random_oracle.c` and `tools/generate_libmpdec_random.py` generate rows (precisions 2 to 10,000, mixed operand widths, all rounding directions, exponent limits, halfway inputs, string conversion, elementary functions); the new `mpfr-random-v1` row kind of `frontend/mpfr_expr` and the `tooling/src/differential` executable validate them in batches, record JSONL and delta-debug failures; `just random-diff` runs, replays, minimizes and smoke-tests; committed samples and `xfail`-annotated regression fixtures are part of `just pr`. A campaign of 37,090,000 cases (native, Wasm, JavaScript, Wasm-GC) found five `decimal_gda` disagreements ([#264](https://github.com/Luna-Flow/floating/issues/264) to [#268](https://github.com/Luna-Flow/floating/issues/268)) and no binary arithmetic disagreement ([#16](https://github.com/Luna-Flow/floating/issues/16)).
- `just bench external quick`: the floating side of the external baseline only, a few rounds without the quiet-machine gate, divided by the MPFR and libmpdec medians stored in `testdata/external_baseline/summary-0.11.0.json`, with a flag for ratios above 10 ([#20](https://github.com/Luna-Flow/floating/issues/20)).
- `tools/range_boundary_rows.py` writes `mpfr-random-v1` rows that put the arguments of `exp`, `exp2`, `exp10`, `expm1`, `pow`, `pown` and `rootn` on their underflow and overflow thresholds, for every precision of a range, six contexts and both tininess rules. Its 1,269,554 rows of precisions 2 to 300 found [#272](https://github.com/Luna-Flow/floating/issues/272), [#273](https://github.com/Luna-Flow/floating/issues/273), [#274](https://github.com/Luna-Flow/floating/issues/274) and [#278](https://github.com/Luna-Flow/floating/issues/278) beside [#271](https://github.com/Luna-Flow/floating/issues/271).
- `tools/check_imports.py`, part of `just pr`: fails if `decimal` imports `decimal_gda` or the reverse (test and white-box imports included), or if `internal/decimal_kernel` imports any module package other than `internal`. The `decimal_gda` design page already claimed such a scan; none existed ([#17](https://github.com/Luna-Flow/floating/issues/17)).

### Changed

- `def`: `Floating` is documented as implemented by the types of this library only ([#22](https://github.com/Luna-Flow/floating/issues/22)): implementing it outside this module is not supported and is not covered by the compatibility promise (methods may be added to the trait in a minor release). The trait stays `pub(open)`, because its implementations are in other packages of the module and a readonly trait (`pub trait`) fails with error 4145 there. The tutorial section that implemented `Floating` for a user type is removed. No signature changes.
- `bin_float`: the binary coefficient kernel moved into the internal package `Luna-Flow/floating/internal/bin_kernel` ([#22](https://github.com/Luna-Flow/floating/issues/22), step B1): the type `Coeff`, the multiplication, division, square-root, GCD and radix-conversion algorithms with their per-target thresholds (about 8,900 lines and their white-box tests; the thresholds of the elementary functions stay in `bin_float`). The public type `BinCoeff` is a newtype over `Coeff` and forwards each public method, so the interface of `bin_float` is unchanged (the `.mbti` has no difference) and `BinFloat` holds the kernel type directly. Retired instructions on Native for the 20 rows of the previous table: geometric mean 0.998, 18 rows within 0.978 to 1.001. The package is internal: it cannot be imported from outside this module. New manual pages for the package, and `tools/check_imports.py` checks that it imports nothing of this module. Refs [#22](https://github.com/Luna-Flow/floating/issues/22).
- `internal/decimal_kernel` and `internal`: narrowed the public surface of the two internal packages (not reachable from other modules): 102 of the 217 public items of the decimal kernel and the unused helpers `result_lift2`, `result_lift2_checked`, `sign_of_bigint`, `remove_factor2` and `pow2` are private or removed, and `SignedDecCoeff` can no longer be constructed outside the kernel ([#22](https://github.com/Luna-Flow/floating/issues/22)). No change of behaviour.
- Version and publishing ([#22](https://github.com/Luna-Flow/floating/issues/22)): the manifests of `library/moon.mod` and `tooling/moon.mod` are at `0.11.0` and the tools module imports `Luna-Flow/floating@0.11.0`; this is version 0.11.0. `tools/check_imports.py` (quick gate, and the first step of the publish workflow) fails when the library version, the tools version and the library version named by the tools imports differ. The `moon add Luna-Flow/floating@0.10.2` lines of the manual stay: `0.10.2` is the latest published release, and the stored external baseline `testdata/external_baseline/summary-0.10.2.json` keeps its name and content (`just bench external publish` takes the measured release from `--version`, by default the manifest version). The publish workflow has an input `module` (`library`, the default, or `tools`), publishes with `moon -C library publish` or `moon -C tooling publish`, and each path runs its own package-contents check (`tools/check_package_contents.py`, also a quick-gate stage) and `moon publish --dry-run` first; the library zip holds only `moon.mod`, `README.md`, `LICENSE`, `CHANGELOG.md` and `src/`. The tools module has its own `tooling/CHANGELOG.md`.
- Random differential testing of `decimal_gda-power` ([#402](https://github.com/Luna-Flow/floating/issues/402)): the known, explained differences from libmpdec are named expected differences of the generator, each checked, instead of failures: `integer-power-accuracy` (the decNumber algorithm, within 0.6 ulp of the exact power), `noninteger-power-rounding`, `underflow-with-inexact-subnormal` and `subnormal-before-rounding` (GDA 1.70, Underflow and Subnormal), next to `power-of-ten #351`. A row outside every shape still fails. The exponent-zero rows under clamp needed no class: they were a defect of this library, fixed with [#405](https://github.com/Luna-Flow/floating/issues/405). The manual lists the classes with their reasons.
- Repository layout ([#22](https://github.com/Luna-Flow/floating/issues/22)): the library module `Luna-Flow/floating` moved to its own directory `library/` (`library/moon.mod`, `library/src/`, `library/README.md`, `library/LICENSE`, this `library/CHANGELOG.md`), next to the tools module in `tooling/`; the repository root has no module, only `moon.work` (members `./library` and `./tooling`), a short `README.md`, `LICENSE`, `CONTRIBUTING.md`, the manual in `doc/`, `testdata/`, `tools/` and `justfile`. **The import paths of the published module do not change** (`Luna-Flow/floating/<package>`), and no package, API or result changes; the `.mbti` of every package is identical. The published package now holds only `moon.mod`, `README.md`, `LICENSE`, `CHANGELOG.md` and `src/`: it no longer contains `doc/`, `testdata/`, `tools/`, `justfile` and `CONTRIBUTING.md`, and the links of its README that pointed into the repository are absolute URLs. Contributors: the library sources are under `library/src/` (previously `src/`) and the commands are unchanged (`just pr`, `moon check`, `-p <package>`); see CONTRIBUTING.md, "Two modules". `tools/check_imports.py` also checks that the three `LICENSE` files are identical.
- Documentation: the test counts of the `decimal` conformance page match the gate: 531/531 public API tests per target and a 103,527/103,527 full gate (`just gate decimal 3`), not 516/516 and 26,931/26,931. The counts of `decimal_gda`, `bin_float` and `ball_float` were checked against their gates and are unchanged ([#392](https://github.com/Luna-Flow/floating/issues/392)).
- Documentation: the 999,999 limit on precision and exponents of `exp`, `ln`, `log10` and non-integral `power` in `decimal_gda` (and the same limit in `decimal`) is described as what it is, a deliberate implementation limit (decNumber's `DEC_MAX_MATH`) that the official decTest suite requires (`power.decTest` powx4001 to powx4005 and the matching `exp`, `ln`, `log10` rows) and that GDA 1.70 permits through its Invalid context condition, not a rule of the operation text ([#354](https://github.com/Luna-Flow/floating/issues/354)). No behaviour change.
- Tools module ([#22](https://github.com/Luna-Flow/floating/issues/22), step A): the main packages `cli` and `differential` are entry points only, as the toolchain asks (main packages will stop generating blackbox tests). Their behaviour, tests and `README.mbt.md` moved to the new library packages `cli/dispatch` (`dispatch(arguments) -> Int32`) and `differential/harness` (`run(args)`), with their own manual pages; an executable package keeps a plain `README.md`, which `tools/doc_quality.py` now requires instead of `README.mbt.md`. The two `unused_value` warnings of the other targets are gone (the protocol helpers of `bench/external` moved next to the native-only async test that uses them), so the quick gate checks the other targets with `--deny-warn` too. The Python tests of the deprecated `dec-` and `decm-` family aliases capture the expected warnings, and the CI workflows set `init.defaultBranch` before the checkout step, so the logs of `ci` and `nightly` contain no line with the word warning except tool flags such as `--warning=no-unknown-keyword`.
- `bin_float`: the enclosure kernels of `exp`, `ln`, `sin`, `cos`, `ln 2`, `ln 10` and `pi` share one private fixed-point toolkit (`library/src/bin_float/elementary_toolkit.mbt`, [#368](https://github.com/Luna-Flow/floating/issues/368)) instead of one copy of each building block per kernel: directed conversion between floats and fixed-point integers, one bounded cache helper, the term-by-term `exp` stage, one binary-splitting state and merge step (constants, `exp`, and the real and imaginary parts of `sin`/`cos`), a rectangular-splitting evaluator parametrized by its coefficient sequence, and the `ln 2` reduction and chunk schedule of the bit-burst. Pure refactor, no public interface change: every kernel returns the same enclosure `(L, U)`, bit for bit, as before, which a digest table generated on the previous kernels and asserted by `elementary_toolkit_digest_wbtest.mbt` checks on all four targets. The design page describes each piece and its error bound once.
- Gate output and documentation no longer use the middle dot (U+00B7) as a separator ([#373](https://github.com/Luna-Flow/floating/issues/373)). Stage and suite names are `CATEGORY: detail` (`TEST: native`, `SMOKE: IEEE 754`, `DECIMAL_GDA: official decTest`), facts joined in one line use a comma (`scope=quick, workers=4`, `25,385/25,385 passed, 12m 00s`), and the products in the changelog and the binary design page are written with `*` in code. Tests and scripts that read the labels are updated, the rule is in the contribution guidelines, and the catalogs follow.
- Names of the two decimal packages are separated ([#362](https://github.com/Luna-Flow/floating/issues/362)): `decimal` means the IEEE 754-2019 package only and `decimal_gda` the General Decimal Arithmetic package only. External bench cases are `decimal_gda/<op>/<digits>` (were `decimal/...`; `--decimal-digits` is now `--decimal-gda-digits`), `random-diff` families are `decimal_gda-<op>` (were `dec-<op>`) and `decimal-<function>` (were `decm-<function>`, `--decm` is now `--decimal`), and the GDA corpora and random rows moved from `testdata/decimal/` to `testdata/decimal_gda/`. The old `dec-*`, `decm-*`, `--decm` and `--decimal-digits` spellings are still accepted as deprecated aliases.
- `decimal` and `decimal_gda` share one coefficient kernel, the new internal package `internal/decimal_kernel` ([#17](https://github.com/Luna-Flow/floating/issues/17)). The limb representation (`Small(UInt64)` below 10^18, base-10^9 limbs above), addition, subtraction, comparison, shifts by powers of ten, trimming, division by a limb, Knuth, Burnikel-Ziegler and Newton division, schoolbook, Karatsuba, Toom-3 and NTT multiplication, the per-target thresholds and `SignedDecCoeff` existed twice with 1,552 differing lines in `coeff_kernel.mbt` alone, so a fix or tuning in one package did not reach the other. The shared package is the union of both copies on the `decimal_gda` representation; `decimal` gains the small-value fast paths, the numerator-aware division dispatch, the allocation-free scaled comparison and the 10^5-digit NTT (the bound `2^22 * 99999^2 < p1 * p2` is in the design page), and `decimal_gda` gains `gcd`, `mod` and the whole-limb `trim`. It contains integer functions only: no rounding mode, context, flag or condition, and it imports neither decimal package. The finalizers, flags, traps, `Decimal` types and the DPD codec stay in each package, and the public interfaces of `decimal` and `decimal_gda` are unchanged. Results are bit-identical: a differential harness against copies of both previous kernels (162,109 checks over every kernel function, sizes from 1 to 2,000 digits, forced multiplication and division algorithms) found no difference, the 200,000-row `just random-diff` sweep gives the same failures before and after, and both gates pass.
- `decimal` and `decimal_gda` share their rounding-direction decisions and the pure coefficient helpers that existed twice, in `internal/decimal_kernel` ([#17](https://github.com/Luna-Flow/floating/issues/17)): the increment decision for the eight directions behind a `DecCoeffRounding` enum that each package converts its own rounding mode into, division and rounding to a digit count, the half-ulp addend step, the square-root increment, finite-magnitude comparison, integer square and n-th roots, the finite-decimal-expansion test, the atanh series of `ln`, scaled floor division and the digit-wise logical, shift and rotate helpers. Each package keeps thin wrappers with its own types; flags, clamp, subnormal and overflow handling stay in the finalizers. Results are bit-identical: a differential harness against copies of both previous implementations (159,556 checks over every moved function, all eight directions, sizes from 1 to 120 digits) found no difference.

### Performance

- External baseline: the run of release 0.11.0 against MPFR 4.2.2 and libmpdec (commit `4a052ed`, `moonc` 0.10.22, standard preset, 7 rounds, AC power, idle machine) is stored in `testdata/external_baseline/summary-0.11.0.json` (and `summary.md`; `summary-0.10.2.json` is kept). Against the 0.10.2 summary the ratio of floating to the reference fell for every binary cell (`add` at 53 bits 22.1 to 8.7, `mul` 20.0 to 7.6, `div` 33.4 to 7.9, `sqrt` 39.5 to 10.1, `exp` 65 to 3.1, `ln` 141 to 6.9, `sin` 435 to 8.8); the full comparison is in the pull request of the release.
- `bin_float`: `BinCoeff` is stored as an abstract newtype over its representation (`type BinCoeff` in `pkg.generated.mbti` instead of `pub struct BinCoeff { // private fields }`, same for users: it cannot be constructed or read as a record; the JavaScript declaration was already `pub type BinCoeff`), so a coefficient is one allocation instead of two ([#22](https://github.com/Luna-Flow/floating/issues/22), step B0). Retired instructions on Native: 0.55 times for `BinCoeff::add` of small values, 0.70 times for a small `mul`, 0.87 to 0.90 times for `BinFloat` `add`, `mul`, `div` and `sqrt` at 53 and 128 bits, 0.86 to 0.93 times at 512 bits, 0.92 to 0.99 times at 2,048 bits, 0.83 and 0.87 times for `exp` at 53 and 512 bits. No behaviour or signature change. Refs [#22](https://github.com/Luna-Flow/floating/issues/22).
- `bin_float`: the last stage of the 64-bit limbs of `BinCoeff` ([#19](https://github.com/Luna-Flow/floating/issues/19)): the multiplication and squaring dispatch, the unbalanced product (now the block multiplication of the word Karatsuba), Burnikel–Ziegler, the NTT digit conversion and overlap-add, the one-limb division, the sparse product, the bit operations, byte and power-of-two radix conversion and the 256-bit square root kernel work on 64-bit limbs; the 32-bit view of the storage is used only by the 32-bit-limb routes of Wasm and by the tests. Every cutoff is named `*_min_words` or `*_words` and documented in 64-bit limbs (same values halved; LLVM takes the Native cutoffs, it carried an old copy of the Wasm ones). Retired instructions on Native against the previous build: sparse products of 8,192-bit operands 3.3 times fewer, `bit_and` and `bit_xor` 2.8 times, division by a divisor below 2^32 2.2 times, `from_bytes_be` 1.2 times, the other products, divisions and NTT products 1.00 to 1.09 times; nothing slower. Results are unchanged (regression digests, BigInt oracle, new tests of the converted kernels). On Wasm and Wasm-GC the parsing cutoff of the radix conversion is raised to 4,608 chunks (paired wall-clock runs: in place is 1.2 to 6.5 times faster up to 131,072 bits); the formatting cutoff stays at 64 limbs. The NTT digit conversion stays on the 32-bit view on Wasm and Wasm-GC (`bin_coeff_ntt_limb32_conversion`), where the 64-bit limb conversion measured 0.88 times (product) and 0.78 times (square) as fast at 300,000 bits on Wasm-GC. The design page's coefficient-kernel table is corrected (it still listed 32-bit limb counts and thresholds from before #324). Stages of the design note not done because they gave less than 1.3 times on their own operation at 2,048 and 8,192 bits: a limb-array rewrite of Burnikel–Ziegler and Newton (division at 2,048 bits is Knuth, unchanged; at 8,192 bits one Burnikel–Ziegler level costs about the Knuth estimate, 478k instructions), and NTT digit conversions for speed (the NTT starts at 262,144 bits for products). Completes [#19](https://github.com/Luna-Flow/floating/issues/19).
- `bin_float`: `BinCoeff::to_radix_string` and `BinCoeff::parse` in a radix that is not a power of two convert in place on one limb array below the divide-and-conquer cutoffs ([#19](https://github.com/Luna-Flow/floating/issues/19), stage 4): one 64 by 32 bit division or multiplication per 32-bit half-limb instead of a coefficient allocation and the 32-bit accessors per chunk (113 against about 10 instructions per limb step). Retired instructions per operation on Native in base 10: formatting 4.9, 5.7, 4.2 and 2.0 times fewer at 512, 2,048, 8,192 and 65,536 bits, parsing 6.1, 8.3, 4.7 and 1.5 times; the divide-and-conquer conversion now starts at 6,144 limbs (formatting) and 4,608 chunks (parsing) on Native and LLVM (measured crossover; LLVM unmeasured), the Wasm targets keep 128 limbs and 64 chunks until measured. Chunks of 64 bits (19 digits) were not used: a 128 by 64 bit division digit costs two hardware divisions, so the pass costs the same per digit; the saving is the overhead. Output is unchanged (tests against the previous chunk loops and against divide and conquer, values of the form `r^(9k)` and `r^(9k) - 1`). Refs [#19](https://github.com/Luna-Flow/floating/issues/19).
- `bin_float`: the integer square root above 256 bits ([#19](https://github.com/Luna-Flow/floating/issues/19), stage 4) runs Zimmermann's `SqrtRem` on word arrays (`bin_coeff_sqrt_array_nonjs.mbt`): an even number of limbs with the top two bits set after an even shift, blocks of a quarter of the limbs, one division and one squaring per level, one correction at most, and the remainder of the original radicand from a one-limb product, instead of about twenty-five `BinCoeff` temporaries per level. Retired instructions per root on Native, paired with the previous build: 2.0 times fewer for a 512-bit root, 1.85 for 2,048 bits, 1.3 for 8,192 bits, 1.04 for 65,536 bits (division and squaring dominate). Results are unchanged (tests against the previous recursion, the restoring loop, a BigInt oracle and the defining inequalities). Paired wall-clock runs (medians of five, radicand of twice the root width) show no size slower on any target, so it is selected on Native, LLVM (unmeasured, takes the Native value), Wasm and Wasm-GC (2.2 and 2.0 times at 512 and 2,048 bits on Wasm, 4.9 and 2.2 on Wasm-GC, 1.3 to 1.4 at 8,192 bits, 1.05 at 65,536 bits); JavaScript is untouched. The previous recursion stays as the test reference behind `bin_coeff_sqrt_array_enabled`. Refs [#19](https://github.com/Luna-Flow/floating/issues/19).

- `bin_float`: squaring on Native and LLVM runs a word-range Karatsuba square from 36 64-bit limbs (`lo^2`, `hi^2` and `(lo - hi)^2` on array ranges, [#19](https://github.com/Luna-Flow/floating/issues/19) stage 2) and the NTT square starts at 7,168 32-bit limbs instead of 768, where the Karatsuba square stops being cheaper (measured with retired instructions). The word-range Karatsuba product takes one scratch array per call instead of five arrays and two copies per node. Retired instructions per operation on Native against the previous build: `sqr` 1.39 and 1.52 times fewer at 8,192 and 65,536 bits (2.2 at 32,768 bits, 1.0 at 512 and 2,048 bits), `mul` 1.02 to 1.04 times fewer at 2,048 to 65,536 bits, the integer square root of a 65,536-bit root 1.23 times. Results are unchanged (tests against the previous allocating Karatsuba, the schoolbook product and square, and the NTT square at its cutoff). Wasm and Wasm-GC keep their squaring (`bin_coeff_square_words_enabled` is false there until measured); LLVM takes the Native values, unmeasured. Refs [#19](https://github.com/Luna-Flow/floating/issues/19).
- Quick gate: the full 19,134-row table of `asinpi`, `acospi`, `atanpi` and `atan2pi` is compiled into `library/src/decimal` again ([#369](https://github.com/Luna-Flow/floating/issues/369)). With the tiny-operand path of `atan2pi` fixed it runs in 2.4 s of a debug native build (the 4,416-row sample ran in 0.5 s) and adds about 1.4 s to the build; the extreme-exponent sampling rule is removed, and the sampling mechanism stays in `tools/generate_decimal_pi_inverse_rows.py` as `--sample-step N`. The data file is unchanged.
- `bin_float`: `rootn` for degrees `2 <= |n| <= 12` at every precision and `13 <= |n| <= 32` up to a context precision of 1024 bits (the measured range where it is faster; beyond it the integer grows with `n (p + 2)` bits and the certified loop with its fast kernels wins), and so `rsqrt` and `pow` with an exponent `+-1/2^k`, round with one integer root instead of the certified `exp(ln(x) / n)` loop: the root of the scaled coefficient is taken to `p + 1` bits on the half-ulp grid, and the round and sticky bits decide the result and flags as for `sqrt` (subnormal range and tininess included); larger degrees and exact roots keep their paths. Instructions retired (native release, paired builds, 14.7 M harness overhead subtracted): `rsqrt` 57, 23 and 35 times fewer at 53, 128 and 512 bits, `rootn` with `n = 3` 2.1, 3.6 and 11 times fewer. Values, flags and cohorts are unchanged: the integer path equals the certified loop on 14,000 random cases per run (six rounding modes, both tininess rules, binary16, binary32, a small bounded format and unbounded precisions 1 to 130, degrees `+-2` to `+-32`, exponents up to the implementation limits), on perfect powers plus or minus one and on the subnormal boundary, and 8,840 public results of `rootn`, `rsqrt` and `pow` equal those of `main` ([#378](https://github.com/Luna-Flow/floating/issues/378)). The design page describes the rounding core, the single `exp` of `sinh`, `cosh` and `tanh`, the corner choice by sign, the trigonometric shortcuts and the integer root.
- `bin_float`: the Taylor leaf of `atan` (and so `asin`, `acos`, `atan2`, the pi-scaled inverses and the series `pi` of small widths) is evaluated in fixed point: integer chains with floors and ceilings, single-word divisions by `2k + 1`, and the remainder `R(x) = x - atan x` bracketed by the alternating partial sums, with the first term kept apart so that the relative accuracy is kept for small arguments (below `2^-(w/2 + 7)` the remainder is bounded by its first term). Instructions retired (native release, paired builds, harness overhead subtracted): `atan` 2.2, 2.5 and 2.3 times fewer at 53, 128 and 512 bits, `asin` 2.1, 2.3 and 2.3, `acos` 2.1, 2.3 and 2.3, `atan2` 2.2, 2.4 and 2.3. Values, flags and cohorts are unchanged, and the Ziv loops take the same number of attempts on the corpus (228 against 228); the enclosure of the series `pi` for widths below 64 bits changes by an ulp, so four rows of the toolkit digest test (`const_pi` at 20, 30, 40 and 63) are updated, and the new enclosure still contains pi at widths 8 to 69. This is finding 3 of [#374](https://github.com/Luna-Flow/floating/issues/374) ([#378](https://github.com/Luna-Flow/floating/issues/378)).
- `bin_float`: repeated work removed from the rounding core and the certified kernels ([#378](https://github.com/Luna-Flow/floating/issues/378)). `binary_round_dyadic` rounds once (it rounded twice with the same inputs), exits early for every exactly representable value in the context range and skips the general renormalization of a value that already fits; `sinh`, `cosh` and `tanh` evaluate `exp` once (`exp(-x)` is its reciprocal) and pick the `tanh` corners by sign; `exp2` and `log2` take the cached `ln 2`; the interval product and quotient take the extreme corner by sign instead of the minimum of four; `sin`, `cos` and `tan` skip the reduction below pi/4, run the series once for a point and pick the `tan` corners by sign; a point enclosure is evaluated once in `exp2`, `exp10`, `pow`, `rootn`, `log1p`, `asinh`, `acosh`, `atanh`, `exp2m1`, `exp10m1` and `compound`. Instructions retired (native release, paired builds, harness overhead of 14.7 M subtracted): `add` 1.25 and 1.35 times fewer at 53 and 128 bits, `mul` 1.22 and 1.51, `div` and `sqrt` unchanged (1.03); `sinh` and `cosh` 1.26, 1.24, 1.15 at 53, 128, 512 bits, `tanh` 1.41, 1.41, 1.20, `exp2` 1.22, 1.21, 1.05, `log2` 1.48, 1.34, 1.13, `sin` and `cos` 1.66, 1.59, 1.43, `tan` 1.65, 1.58, 1.44, `expm1` 1.28, 1.23, 1.18, `atanh` 1.08. Values, flags and cohorts are unchanged. The `bin_float` white-box tests got cheaper: a zero input made the fixed-width restoring square roots count down through the whole `Int32` range (one test took 51 s, now 0.47 s), and the burst trigonometric reference is computed once per value (3.8 s to 1.2 s).
- Quick gate structure ([#378](https://github.com/Luna-Flow/floating/issues/378), [#369](https://github.com/Luna-Flow/floating/issues/369)): the manual examples run in one `moon test` call over all 50 page packages (40 s to 9 s, same 269 blocks and 260 tests); native is checked once, in the dependency stage (`moon check --target native --deny-warn`), instead of again before the tests, and the other targets get an errors-only check (`moon check --target wasm,wasm-gc,js`, about 5 s) in the following stage; `tools/random_differential.py smoke` reuses the conformance CLI build instead of building its own; and the independent stages run in three concurrent lanes (`tools/ci_schedule.py`): `moon` (shared `_build`), `python` (no moon) and `conformance` (own target directory, starts after the manual examples). Output is captured per stage and printed in one piece, the first failure stops the others, and the `all` and package scopes stay sequential. The white-box row-table tests of `decimal` compare values and flags directly and format text only on failure. `tools/native_test_timing.py` lists the slowest native debug test files, and the gate prints a warning when the native test stage exceeds 150 s (`NATIVE_TEST_WARN_SECONDS`).
- `decimal`: the certified driver costs less for operands and results of extreme exponent ([#378](https://github.com/Luna-Flow/floating/issues/378)): a decimal operand is converted to binary with one division and a tight shift (and bounds of `5^e` for an exponent of 4096 or more), the first working precision scales with the target (`max(64, 3.3219281 max(D, p) + 31)` bits), tiny arguments of `exp`, `exp2`, `exp10`, `expm1` and `log1p` are decided next to 1 or next to `x` without the loop, the exact-root test of `rootn` is skipped unless the exponent is a multiple of the degree and uses the kernel root, `atan2` and `compound` skip the exact ratio and sum when it cannot succeed, digits are counted with `digits10`, and scaled endpoints are rounded outward. Results, cohorts and flags are unchanged (bit-identical conversion tests against the previous implementation, random differential against MPFR). Instruction tables are in the pull request.
- Quick gate: the 19,134 `asinpi`, `acospi`, `atanpi` and `atan2pi` rows of `decimal` (`elementary_pi_inverse_rows_wbtest.mbt`, 2.2 MB of MoonBit source, 466 s in a debug build, 90 % of it in about 50 `atan2pi` rows with an operand `1E-1999996`) are now data, `testdata/decimal/ieee/rows/pi_inverse.txt`, that `just gate decimal` and the nightly run execute on native, Wasm, Wasm-GC and JavaScript through the release-built conformance CLI (value, cohort and flags compared as before; the same 19,134 rows pass on each target). The quick gate compiles a deterministic sample of 4,416 rows (every exact row, one MPFR row in eight per operation and rounding mode, one extreme-exponent row per operation) that runs in about 20 s; the rule is in the verification page. The native test stage and the IEEE smoke stage of CI had grown from 3m34s to 25m47s with the table ([#369](https://github.com/Luna-Flow/floating/issues/369)).
- `ball_float`: fewer evaluations per interval operation, with bit-identical results ([#378](https://github.com/Luna-Flow/floating/issues/378)). Division and `sqrt_interval` take one directed quotient or root per bound (2 instead of 4), a product with one factor straddling zero needs 2 products (was 4) and one with an unbounded factor shares the coefficient product of each corner between both directions, `pown` no longer computes powers it discards, `try_atan2_interval` evaluates the two extreme corners (2 correctly rounded calls instead of 8 to 16), and `try_sinpi_interval` and `try_cospi_interval` 2 instead of 4, each with the monotonicity argument in the design page. `try_sin_interval`, `try_cos_interval` and `try_tan_interval` use the correctly rounded binary kernels with directed rounding on the endpoints and one enclosure of pi for the critical points and poles, instead of 8 exact-rational series and a rebuilt pi on every refinement round, which `decimal` `sin`, `cos` and `tan` pay on every attempt. The exact-rational family used by the non-`try` functions loses the term it computed twice per iteration of the exp series, the duplicated `rat_dyadic_bounds` calls, the general gcd against a power-of-two denominator (a trailing-zero count) and the second evaluation of a point interval in `exp`. The old implementations are kept in white-box tests as oracles over corpora with signed zeros, infinities, empty intervals and critical points. Evidence tables are in the pull request.
- `bin_float`, `decimal`, `ball_float`: `atan`, `asin`, `acos`, `atan2` and the four π-scaled inverses evaluate their enclosure with one series per call instead of one to eight: the reduction `atan x = 2 atan(x / (1 + sqrt(1 + x^2)))` carries the pair of bounds through one chain (the map is increasing), and the ratio pairs of `asin` and `atan2` come from the monotone corner instead of eight directed quotients. `decimal` and `ball_float` take π from the cached binary-splitting constant (twice the correctly rounded `atan(+inf)`) instead of `4 atan(1)` and a per-call Machin evaluation. Instructions retired (native release, paired builds): `atan` 2.3 times, `asin` and `acos` 4.3 to 4.4 times and `atan2` 3.8 to 4.7 times fewer at 53, 128 and 512 bits; 10,000 random rows of `decimal` `asinpi`, `acospi`, `atanpi` and `atan2pi` 3.7 to 3.8 times fewer. The full generated-row test of IEEE `decimal` (before the sampling of [#379](https://github.com/Luna-Flow/floating/issues/379)) dropped only 3.3 % (4.81 to 4.65 trillion instructions with the first two findings): its time is in the decimal-to-binary conversion of operands such as `1E-1999996`, not in these series. Values, flags and cohorts are unchanged; the soundness evidence is in the design page ([#374](https://github.com/Luna-Flow/floating/issues/374), finding 3 of that issue stays open).
- `decimal`: `atan2pi` of operands whose exponents are millions of digits no longer forms the exact decimal expansion of the binary operand ([#378](https://github.com/Luna-Flow/floating/issues/378)). Both operands are first scaled by `10^-adjusted(x)` (the ratio is unchanged) and, for `x > 0` and a ratio below `10^(D+1)` with `3 t >= 8 max(digits, p) + 400`, `t = -(2 D + 2)`, the loop encloses `(sy / sx) / pi (1 - e)`, `0 <= e <= r^2`, and shifts it by `D`, as `atanpi` does. `atan2pi(1E-1999996, 1)` in decimal32 takes 57 million instructions where it took 143 billion (native debug), results, cohorts and flags unchanged; the first test of `elementary_pi_inverse_wbtest.mbt` takes 2.2e11 instructions where it took 4.8e12. The shortcut has a derivation (design page), and 7,072 generated rows with independent expected values (Python `decimal`, `tools/generate_decimal_atan2pi_scaled_rows.py`) on both sides of its condition for both signs of `y` and `x`, four formats and all eight rounding directions.
- `decimal_gda` and `decimal` coefficient basics ([#378](https://github.com/Luna-Flow/floating/issues/378)): the certified `exp` takes its candidate from the interval midpoint on every attempt (the series candidate ran at a precision given in bits used as digits, about 150 digits for decimal64) with the result, cohort and flags unchanged; `GdaContext` builds its `DecimalContext` once; the scaled representation of a tiny value no longer builds `10^k`; one-word digit counts use a leading-zero count; the unit accumulator no longer scans or pops limbs; an inexact `decimal_gda` division reads exactness off its one division; and `etiny` and `etop` no longer build a bounds struct (nor a `BigInt` in `decimal`) on each call. Results are bit for bit unchanged; the instruction counts are in the pull request.
- `bin_float`: `exp` and everything built on it (`expm1`, `exp2`, `exp10`, `pow`, `compound`, `powr`, the hyperbolic functions and the IEEE `decimal` elementary functions, which evaluate two binary `exp` enclosures per Ziv step) use a medium-precision kernel up to a per-target working precision (1792 bits on Native and LLVM, 2048 on Wasm, 1536 on Wasm-GC, 3072 on JavaScript): reduction by `ln 2`, two levels of lazily built tables `exp(j / 2^k)` taken from the certified kernels, and the Taylor series of the remainder by rectangular splitting on fixed-point integers with collected integer coefficients (after Johansson, ARITH 22, 2015); the error analysis is in `doc/manual/design/bin_float.md`. Only the enclosure changes, so values and flags are bit-identical (correct rounding is unique). `just bench external quick`, Native, paired runs: binary `exp` at 53, 128 and 512 bits 4.35, 6.08 and 17.5 µs to 2.13, 2.60 and 6.65 µs (2.0, 2.3 and 2.6 times); decimal `exp` at 16, 34 and 100 digits (decimal64 `exp_ctx` is the 16-digit row) 14.7, 22.9 and 44.2 µs to 8.72, 14.6 and 26.6 µs; 2048 bits and above are unchanged ([#356](https://github.com/Luna-Flow/floating/issues/356)).
- `decimal`: the certified Ziv driver rounds a non-degenerate enclosure's endpoints outward to `max(p + 12, ...)` digits with directed binary powers of 5 and 2 instead of expanding them exactly ([#334](https://github.com/Luna-Flow/floating/issues/334)). The cost no longer depends on the decimal exponent of the argument: `expm1(1E-999990)` in a precision-20, exponent ±999,999 context goes from more than 120 s to about 0.4 s (release build, same harness on both sides), `1E-100000` from 2.1 s to 0.06 s; decimal64 `exp` is unchanged within noise. Results, cohorts and flags are bit-identical; the soundness argument is in the decimal design page.
- `decimal`: `pow`, and `powr` through it, evaluates the enclosure of a non-integral power as `exp(y ln x)` in interval arithmetic with `ceil(log2 |y ln x|)` guard bits, instead of eight correctly rounded binary powers per enclosure. Results, cohorts and flags are unchanged (correct rounding makes them unique). Instructions retired on 10,000 `decm-pow` / `decm-powr` rows (decimal, native release) fall from 89.4 G to 24.3 G and from 88.2 G to 24.7 G (3.7 and 3.6 times fewer; wall 6.6 s to 2.0 s and 4.8 s to 1.7 s); `decm-exp`, `decm-ln` and `decm-compound` are unchanged within 0.1 % ([#352](https://github.com/Luna-Flow/floating/issues/352)).
- `decimal_gda`: `add`, `subtract`, `multiply` and `divide` on single-limb coefficients (below 10^18) in an extended context of at most 18 digits (17 for `divide`) round the exact sum, product or guarded quotient once on `UInt64` pairs and build the result and flags directly, with the general path as the exact fallback for everything else (zeros, special values, exact quotients, clamped, subnormal or out-of-range results). At 16 digits `add` is 4.6 times, `multiply` 4.0 and `divide` 8.2 times faster on Native (paired medians; 9.3, 10.2 and 7.8 on Wasm-GC); values, flags and next contexts are unchanged, checked against the general path on 60,000 random operand pairs per operation ([#20](https://github.com/Luna-Flow/floating/issues/20)).
- `decimal_gda`: the certified `exp` of an argument below 1000 in magnitude in a context that holds every result starts from the binary enclosure alone (its midpoint, converted to decimal, picks the rounding cell; about 3.33 bits per digit plus guard bits certify it) instead of evaluating the Taylor series in decimal arithmetic at four bits per digit plus 64, which only arguments in [1, 10) avoided; a hard case falls back to the former procedure. Paired native runs: 3.9 times faster at 16 digits, 8.2 at 34, 22 at 100 and 305 at 1,000 digits; results, flags and cohorts are unchanged, compared with the former procedure on random and near-midpoint arguments ([#20](https://github.com/Luna-Flow/floating/issues/20)).

- `bin_float`: the integer square root of values of up to 256 bits uses word-level kernels instead of a bit-by-bit loop on Native, LLVM and Wasm-GC (a double-precision estimate with one Newton step up to 128 bits, Zimmermann's word-level Karatsuba root up to 256 bits), and 257 to 512-bit values on Native and LLVM go through the divide-and-conquer root with that base case. `BinFloat::sqrt` is 2.0 and 2.3 times faster at 100 and 128 bits (Native and Wasm-GC), 1.4 and 1.5 times at 200 and 256 bits, 1.1 times at 512 bits and 1.05 at 2,048 bits (Native); linear Wasm keeps the loops; results are unchanged, checked against the loops and a BigInt oracle at every width up to 256 bits ([#19](https://github.com/Luna-Flow/floating/issues/19), [#20](https://github.com/Luna-Flow/floating/issues/20)).
- `decimal`: the finalizer rounds with the limb-based division by a power of ten of `decimal_gda` (shared in `internal/decimal_kernel`) instead of a full coefficient division. Instructions retired per operation fall by 11 to 59 % for `add` and `mul` at 16 to 1,000 digits (`mul` at 100 digits 2.1 times cheaper) and 18 % for `sqrt` at 16 digits; division and larger square roots are unchanged, and `decimal_gda` runs 0.0 to 0.2 % more instructions for the wrapper ([#17](https://github.com/Luna-Flow/floating/issues/17)).
- `decimal`: the shared coefficient kernel gives `decimal` the small-value fast paths, the numerator-aware division dispatch and the 10^5-digit NTT of `decimal_gda`, and its division no longer pays for batched factor counting. Instructions retired per operation (random signed operands, paired old/new builds) fall by 4 to 62 % for `add`, `mul`, `div` and `sqrt` at 16 and 34 digits, 3 to 14 % at 100 digits and 0 to 10 % at 1,000 digits (`div` at 16 digits 2.6 times cheaper); `decimal_gda` executes the same instructions as before for `add`, `mul` and `sqrt` and 1 to 11 % fewer for `div` ([#17](https://github.com/Luna-Flow/floating/issues/17)).
- `bin_float`: the certified elementary functions memoize their `ln 2`, `ln 10` and `pi` enclosures per working precision (six precisions each, up to 65,536 bits) instead of recomputing them in every call. `ln` is 2.4 to 2.6 times and `sin` 2.4 to 3.7 times faster on Native at 53 to 512 bits (paired medians), decimal `ln` 2.5 times; results, flags and certification failures are unchanged ([#20](https://github.com/Luna-Flow/floating/issues/20), [#18](https://github.com/Luna-Flow/floating/issues/18)).
- `bin_float`: the `exp` enclosure evaluates its Taylor series once instead of twice when the argument is exact at the working precision, and the sine/cosine enclosure skips the series that the requested function and quadrant do not read. `exp` is 1.8 to 2.0 times faster on Native at 53 to 512 bits (paired medians), decimal `exp` 1.3 to 1.4 times, `sin` 1.15 to 1.2 times; enclosures, results, flags and certification failures are unchanged, checked against copies of the previous code ([#20](https://github.com/Luna-Flow/floating/issues/20), [#18](https://github.com/Luna-Flow/floating/issues/18)).
- `bin_float`: the divide-and-conquer integer square root now ends its recursion in the fixed-width kernels (256 bits on Native/LLVM, 512 bits on Wasm/Wasm-GC) instead of a restoring loop over heap integers at 128 bits, so a 512-bit `BinFloat::sqrt` is about 3.4 times faster on Native (paired medians; 2,048 bits 1.7 times). Results, flags and encodings are unchanged and checked against a BigInt oracle at every cutoff ([#20](https://github.com/Luna-Flow/floating/issues/20)).
- `bin_float`: the certified `exp` enclosure bounds the Taylor series of the reduced argument in fixed point (16 guard bits, a proven per-term error bound) when the argument is exact at the working precision, instead of one rounded floating-point operation per term. `exp` is 9 to 10 times faster on Native at 53 to 2,048 bits (paired medians), 7 to 11 times on Wasm and Wasm-GC, decimal `exp` 1.7 to 2.2 times; refinement attempts, results, flags and certification failures are unchanged, checked against the previous series in white-box tests ([#20](https://github.com/Luna-Flow/floating/issues/20), [#18](https://github.com/Luna-Flow/floating/issues/18)).
- `bin_float`: `BinFloat::add`, `mul`, `div` and `sqrt` on operands with one-word coefficients and a precision of at most 62 bits (60 for `div` and `sqrt`) run on `UInt64` pairs and allocate only the result instead of going through the general path, with the general path as the exact fallback. At 53 bits `add` is 2.9 times, `mul` 3.0, `div` 4.9 and `sqrt` 2.8 times faster on Native (paired medians), 3 to 8 times on Wasm and Wasm-GC; results, flags and encodings are unchanged, checked against the general path on 40,000 random operand pairs per operation ([#20](https://github.com/Luna-Flow/floating/issues/20)).
- `bin_float`: `BinFloat::add` and `mul` on coefficients of up to 128 bits at a precision of at most 128 bits run on `UInt64` words (a 192-bit aligned sum, a 256-bit product), and `add`, `mul`, `div` and `sqrt` on wider operands go through coefficient-level paths that skip the context, flags record and result tuple and round once, with the general path as the exact fallback. At 128 bits `add` is 3.3 times and `mul` 3.5 times faster on Native (paired medians; 2.5 and 3.7 on Wasm-GC), `sqrt` 1.4 times, `div` 1.1 times, and `add`/`mul` 1.5 to 1.9 times at 512 bits; results, flags and encodings are unchanged, checked against the general path on tens of thousands of operand sets per operation on Native, Wasm and Wasm-GC ([#20](https://github.com/Luna-Flow/floating/issues/20)).
- `bin_float`: `pi`, `ln 2` and `ln 10` are computed by binary splitting (the Chudnovsky series for `pi`, `ln 2 = 18 artanh(1/26) - 2 artanh(1/4801) + 8 artanh(1/8749)`, `ln 10 = 3 ln 2 + 2 artanh(1/9)`) from a working precision of 64 bits, instead of the arctangent and artanh series with a rounded operation per term. This only changes the cost of a cache miss: a first call at 8,192 bits takes 0.67 ms for `pi` (449 ms before), 1.3 ms for `ln 2` (178 ms) and 1.0 ms for `ln 10` (89 ms, `ln 2` cached), 7 to 670 times less on Native (512 to 8,192 bits) (single enclosures at `p + 64` bits, `moon bench`; 2,048 bits: 71 us, 156 us and 114 us against 14 ms, 5.6 ms and 2.8 ms), and also 3 to 19 times at 64 bits and on Wasm-GC and JavaScript. Calls that find the constant in the cache, which is what the steady-state external benchmark measures, are unchanged, so `just bench external` does not show this change. The enclosures are no wider than before and contain the old ones (white-box tests against the old series at 256 more bits), and every enclosure from 64 to 100,000 bits agrees with MPFR 4.2.2 (`mpfr_const_pi`, `mpfr_const_log2`, `mpfr_log(10)`), one to two units in the last place wide; the error bounds are paper arguments in the design page ([#18](https://github.com/Luna-Flow/floating/issues/18)).
- `bin_float`: the certified `ln` series on the normalized argument (and the `ln 2` and `ln 10` constants) is summed in fixed point when the argument is exact at the working precision, with guard bits that follow the size of `z` and a proven error bound per term. `ln` is 5 to 7 times faster on Native at 53 to 2,048 bits (paired medians, without the constant cache), 5.5 to 7.5 times on Wasm and Wasm-GC, decimal `ln` 6 times; refinement attempts, results, flags and certification failures are unchanged, checked against the previous series in white-box tests ([#20](https://github.com/Luna-Flow/floating/issues/20), [#18](https://github.com/Luna-Flow/floating/issues/18)).
- `bin_float`: the certified `exp` enclosure uses argument reduction with `ln 2` and a bit-burst evaluation (the reduced argument is cut into chunks of 16, 48, 192, ... bits; each chunk's exponential is bounded in integers by the fixed-point series or, when it has 40 terms or more, by binary splitting, and the chunks are multiplied) from a per-target working precision: 1,024 bits on Native and LLVM, 640 on Wasm and Wasm-GC, 256 on JavaScript. Paired alternating timings of `just bench external quick --ops exp` against the previous build on Native: 8,192 bits 20.2 and 20.4 ms against 1.78 and 1.69 ms (9.1 to 12.1 times), 2,048 bits 508 and 517 us against 187 and 196 us (2.1 to 2.7 times), 53 and 512 bits unchanged within the noise of the machine; the two noisy earlier rounds gave 9.1 and 9.5 times at 8,192 bits. The kernel is slower than the series below about 1,000 bits on Native and 600 on Wasm-GC, hence the thresholds. Every enclosure it returns is an integer-bound argument on paper (design page), contains the series enclosure at 256 more bits and is no wider than it in the white-box tests, and three deliberately wrong variants of the kernel fail those tests; 35,040 `exp` rows of 256 to 4,096 bits in four rounding directions (arguments from 2^-60 to 2^28 and next to multiples of `ln 2`) agree with MPFR 4.2.2 and are byte-identical on Native, Wasm, Wasm-GC and JavaScript, and 100,000 random `elem` cases on Native and 20,000 on each other target agree. Results, flags and certification failures of `exp` are unchanged; `exp2`, `exp10`, `sinh`, `cosh`, `tanh`, `pow` and `rootn` use the same enclosure. The ratio to MPFR of `exp` at 8,192 bits is about 5.6 times on the drift-corrected scale of the tools (about 66 before) and still limited by the multiplication kernel ([#18](https://github.com/Luna-Flow/floating/issues/18)).

- `bin_float`: the sine and cosine Taylor series of the certified `sin`, `cos` and `tan` are summed in fixed point when the reduced argument is exact at the working precision (20 guard bits, extra bits for a small sine argument, a proven error bound per term). On top of the memoized constants `sin` is 4.3 to 5.7 times faster on Native at 53 to 2,048 bits (paired medians), 4.6 times on Wasm-GC; on its own against the previous release 1.3 to 1.4 times. Refinement attempts, results, flags and certification failures are unchanged: sin, cos and tan results are bit-identical to the previous build on 1,350 random arguments at 24 to 512 bits, and white-box tests check the enclosures ([#20](https://github.com/Luna-Flow/floating/issues/20), [#18](https://github.com/Luna-Flow/floating/issues/18)).

- `bin_float`: `BinCoeff` stores values above 128 bits in 64-bit limbs instead of 32-bit limbs on every non-JavaScript target (stage 1 of [#19](https://github.com/Luna-Flow/floating/issues/19)): addition, subtraction, comparison, shifts, schoolbook multiplication and squaring, Karatsuba and Toom-3 work on 64-bit limbs, the other kernels read a 32-bit view of the same storage. Native paired medians: 2,048 to 8,192-bit multiplication 2.2 times faster, 8,192-bit addition 2.3 times, `exp` and `ln` at 2,048 bits 2.0 times; Wasm and Wasm-GC are faster below about 6,000 bits and up to 1.8 times slower above about 9,000 bits until the next stage. Results are unchanged, checked by regression digests recorded with the 32-bit implementation (identical on native, Wasm, Wasm-GC and the JavaScript backend).
- `bin_float`: the Karatsuba multiplication of `BinCoeff` runs on limb arrays instead of wrapping every intermediate value in a `BinCoeff` (stage 2 of [#19](https://github.com/Luna-Flow/floating/issues/19)), with the schoolbook/Karatsuba cutoff measured per target (32 64-bit limbs). On Wasm and Wasm-GC, where a 64-bit limb product costs four `i64.mul`, multiplication from 160 limbs and squaring from 80 limbs run on 32-bit limbs and pack the result back, so that no size is slower than before. Native paired medians against the 32-bit implementation: coefficient multiplication 2 to 3 times faster from 1,024 to 32,768 bits, `BinFloat` `mul` 1.6/2.5/2.9 times at 512/2,048/8,192 bits, `sqrt` 1.5/2.0 times at 2,048/8,192 bits; Wasm-GC 1.1 to 2.2 times and Wasm 1.1 to 2.1 times on coefficient multiplication. Results are unchanged (the regression digests pass on all four targets).
- `bin_float`: Knuth division runs on 64-bit digits (stage 3 of [#19](https://github.com/Luna-Flow/floating/issues/19)); the Burnikel-Ziegler cutoffs move to 192 divisor limbs with Knuth leaves up to 128, and Newton reciprocal division, which had become 3 to 12 times slower than Burnikel-Ziegler from 32,768 bits, is no longer selected. Native paired medians: `div` 1.5/2.3/2.9 times faster at 512/2,048/8,192 bits, `sqrt` of 8,192 bits 1.5 times; Wasm-GC `div` 1.9/3.3 times at 2,048/8,192 bits, Wasm 1.3/3.3 times. Native switches multiplication to the NTT at 8,192 limbs (was 2,048). Results are unchanged (the #308 digests pass; new tests compare 64-bit-digit Knuth with the 32-bit one on random and adversarial operands and divisions of up to 134,000 bits with the multiplication).
- `bin_float`: the working precision from which the certified `exp` uses the bit-burst enclosure is 1,088 on Wasm (was 640, shared with Wasm-GC). After the 64-bit limb multiplication the series wins on Wasm up to about 1,000 bits: paired runs of `exp` are 1.4 to 1.7 times faster at 576 to 768 bits and equal at 1,024 bits and above. Wasm-GC (640) and Native (1,024) were re-measured against the never-burst and always-burst builds and keep their values; results are unchanged ([#18](https://github.com/Luna-Flow/floating/issues/18)).
- `bin_float`: the certified `ln` of a number in `(1, 2]` (the unit enclosure behind `ln`, `log2`, `log10`, `log1p`, `pow`, `rootn` and the inverse hyperbolic functions) uses a verified Newton step on the bit-burst `exp` from a per-target working precision: 1,152 bits on Native and LLVM, 1,280 on Wasm and JavaScript, 576 on Wasm-GC. A start value of half the precision comes from the same function one level down; `exp` of it is enclosed, the quotient `v / exp(y0)` is bounded with directed division, and `(q - 1) - (q - 1)^2 <= ln q <= q - 1` for `|q - 1| <= 1/2` closes the enclosure, so the correctness of the enclosure does not depend on the quality of the start value. Paired alternating timings of `just bench external quick --ops ln` against the previous build on Native (after the 64-bit limbs, Karatsuba and division kernels, on a loaded machine): 8,192 bits 27.0, 25.6, 25.6 and 28.0 ms against 2.43, 2.40, 2.57 and 2.44 ms (paired ratios 10.0 to 11.5), 2,048 bits 565 to 856 us against 295 to 378 us (1.7 to 2.35 times); 53 and 512 bits are on the old path. The raw ratio to the stored MPFR medians (floating of the day over the stored MPFR median) at 8,192 bits goes from 221 to 243 to 21 to 22, at 2,048 bits from 37 to 57 to 20 to 25; MPFR re-measured on the machine at that time reads about 1.95 times slower than the stored run at 8,192 bits and 1.65 times at 2,048, so the drift-corrected ratios are about 10.7 to 11.4 and 12 to 15 (an earlier run on a quiet machine gave 11.5 to 13.6 at 8,192 bits). The enclosure contains the series enclosure at 256 more bits and is no wider than it in the white-box tests, two deliberately wrong variants fail those tests, and 13,200 `ln` rows of 256 to 4,096 bits in four rounding directions (arguments from `2^-1000` to `2^100000`, near 1 and near powers of two, every row through the kernel) agree with MPFR 4.2.2 and are byte-identical on Native, Wasm, Wasm-GC and JavaScript. Results, flags and certification failures of `ln` are unchanged ([#18](https://github.com/Luna-Flow/floating/issues/18)).
- `bin_float`: the certified `sin` and `cos` use argument reduction with `pi / 2` in integers (one Euclidean division, an exact reduced argument and a 2-unit bound from the Lipschitz property) and a bit-burst evaluation of `exp(i y)`: the reduced argument is cut into chunks of 16, 48, 192, ... bits, each chunk's sine and cosine is bounded as a midpoint-radius ball by the fixed-point series or, from 40 terms, by binary splitting with a complex state, and the balls are folded by rotation, from a per-target working precision: 1,536 bits on Native and LLVM, 2,112 on Wasm, 640 on Wasm-GC, 256 on JavaScript. `tan` and the argument-reduction path below the thresholds are unchanged. Paired alternating timings of `just bench external quick --ops sin` against the previous build on Native: 8,192 bits 6.92, 6.66, 6.73 and 6.66 ms against 1.47, 1.32, 1.29 and 1.38 ms (paired ratios 4.7 to 5.2), 2,048 bits 268 to 288 us against 183 to 204 us (1.3 to 1.5 times); 53 and 512 bits unchanged. The raw ratio to the stored MPFR medians (floating of the day over the stored MPFR median) at 8,192 bits goes from 34 to 35 to 6.5 to 7.4, at 2,048 bits from 19 to 20 to 13 to 14; the machine reads about 1.45 times slower than the stored run, so the drift-corrected ratios are about 4.5 to 5.1 and 9 to 10. The enclosure contains the series enclosure at 256 more bits and is no wider than it in the white-box tests, three deliberately wrong variants fail those tests, and 23,424 `sin` and 23,424 `cos` rows of 256 to 4,096 bits in four rounding directions (arguments from `2^-60` to `2^1000` and next to multiples of `pi / 2`, every row through the kernel) agree with MPFR 4.2.2 and are byte-identical on Native, Wasm, Wasm-GC and JavaScript. Results, flags and certification failures of `sin` and `cos` are unchanged ([#18](https://github.com/Luna-Flow/floating/issues/18)).

### Fixed

- `decimal` and `decimal_gda`: the plain `Decimal::from_bin_float` no longer forms the whole expansion `c * 5^k` (or `c << e2`) of the binary value before it rounds to `precision` digits: for a binary exponent above 1024 in magnitude and a precision of at most half of it, the digits come from `BinFloat::to_decimal_string_ctx` (the bounded path of `from_bin_float_ctx`, a private copy in `decimal_gda`) and are rounded once, so the cost no longer grows with the exponent ([#467](https://github.com/Luna-Flow/floating/issues/467)). The result is the one of the expansion: same coefficient, exponent, sign and precision field. `3 * 2^-1000000` at precision 34 took 192,593,646,672 instructions (18.6 s) and now takes the start-up cost only.
- `decimal_gda`: `Decimal::to_bin_float` no longer forms `5^e` or `10^scale` for a decimal exponent of 4096 or more in magnitude: it converts through `BinFloat::from_string_ctx`, the exact decimal conversion of `bin_float`, so time and memory no longer grow with the exponent ([#468](https://github.com/Luna-Flow/floating/issues/468)). `1E-30000000` took 990,293,090,629 instructions and 2.7 GB and now takes the start-up cost only. The results are the ones of the expansion, bit for bit.
- `bin_float`: `BinFloat::remainder` and `remainder_ctx` returned a wrong result, with no flag, when the exponents of the two operands differed by more than $2^{31} - 1$ ([#445](https://github.com/Luna-Flow/floating/issues/445)). The gap was computed in `Int32` and wrapped, so the power of two $2^{\text{gap}} \bmod 2c$ was skipped and the residue stayed at 1; with $x = 2^{1073741822}$ and $d = 3 \cdot 2^{-1073741875}$ the result was $+2^{-1073741875}$ instead of $-2^{-1073741875}$ (IEEE 754-2019 5.3.1: the nearest integer quotient of $2^{2147483697}/3$ is one above the floor). The gap is now an `Int64`. Gaps up to $2^{31} - 1$ and every other operation are unchanged.
- `bin_float`: `BinFloat::make` (and `from_coefficient`, `from_hex`, `with_precision`, `normalized` and every other path through the same normalization) now rounds a value whose leading bit is inside the implementation range but whose lowest bit lies below the smallest quantum $2^{e_{\min} - (p - 1)}$ ([#441](https://github.com/Luna-Flow/floating/issues/441)). It kept such a value unrounded, so `3 * 2^(binary_implementation_e_min - 53)` at precision 53 (1.5 quanta) was stored as is, and any other operation then moved it to 2 quanta: one number had two representations. Below $2^{e_{\min}}$ the kept bits are now $\min(p, \mathrm{top} - (e_{\min} - p + 1) + 1)$, in the rounding mode given to `make`, one rounding for precision and range together. The internal helper that builds enclosure endpoints near the subnormal limit (`binary_inexact_inner_endpoint`) relied on the old behaviour and now chooses a width that holds every bit of the endpoint. Values in the normal range, and values below the quantum, are unchanged.
- `decimal` and `decimal_gda`: the plain `+` and `-` of `Decimal` no longer panic when the exponents of the operands differ by more than 2^31 - 1 and no longer allocate memory proportional to the gap ([#446](https://github.com/Luna-Flow/floating/issues/446)). The far smaller operand is absorbed as one sticky digit below the rounding position, as `add_ctx` does (the gap is taken in `Int64`, the cost does not depend on it); the result is the one the exact aligned sum gave. Under `DecimalContext::exact()` a gap above 2,000,000,000 digits returns a NaN with the `invalid_context` flag instead of panicking; what `exact()` may cost is decided for 0.12.
- `decimal` and `decimal_gda`: `Decimal::to_bin_float` no longer panics for a very negative or very positive exponent (the negation of -2^31 in `decimal`, `precision + scale * 4 + 2` in `decimal_gda`) and no longer forms an unbounded power ([#447](https://github.com/Luna-Flow/floating/issues/447)). A value whose adjusted exponent puts it outside the binary implementation range is decided in `Int64` before any power is formed: overflow or underflow as the rounding direction says, at a cost independent of the exponent. The result is the one `to_bin_float_ctx` and the exact parser give.
- `ball_float`: `BallFloatDecorated::new(x, decoration=Ill)` returns NaI, as IEEE 1788-2015 11.5.2 requires of `setDec(x, ill)` for any `x`, empty or not ([#443](https://github.com/Luna-Flow/floating/issues/443)). It returned `x` with the decoration `Trv` (and an empty interval with `Ill` is NaI too, not `Trv`). The result equals `BallFloatDecorated::nai(precision=x.precision())`. The other two forbidden combinations of 11.5.2 were already repaired as the clause says (empty with `Com` is `Trv`, unbounded with `Com` is `Dac`) and are unchanged. The API page said `new` never builds NaI; it now states the clause.
- `bin_float`: `BinFloat::to_shortest_string_ctx` no longer panics when the operand is not representable in the context ([#448](https://github.com/Luna-Flow/floating/issues/448)); for example `(1/3 at precision 113).to_shortest_string_ctx(BinaryContext::binary64())` aborted. The operand is first rounded into the context (`round_ctx`, in the rounding direction of the context, with the overflow and underflow of the context) and the result is the shortest string of that rounded value, so it is `0.3333333333333333` there, `inf` on overflow and `0` or `-0` on underflow. A representable operand prints as before. Whether the function keeps its name and gains a `Result` form is a decision of the 0.12 list (#438).
- Quick gate ([#431](https://github.com/Luna-Flow/floating/issues/431)): the guard of the Python test stage (#417) compared `git status` of `library/src` and `tooling/src` before and after the tests and so failed on a fresh worktree when the concurrent stage "DOCS: manual examples" wrote `_generated_doc_examples` meanwhile. The comparison leaves out the generated sources, taken from one list (`tools/generated_paths.py`, shared with `tools/check_package_contents.py`); a stray write of a test or of its subprocess is still reported, and a test that writes a generated file itself is still reported by the in-process recorder.
- `decimal_gda`: `quantize` and `rescale` of a zero under `clamp` fold the exponent down to `e_max - precision + 1` and raise Clamped when the requested exponent is above it: `quantize(0, 1E+380)` in decimal64 (precision 16, `e_max` 384) is `0E+369 Clamped`, no longer `0E+380` without flags. decNumber's `decQuantizeOp` calls `decFinalize` for a zero operand, whose clamp branch does this, and every other zero-producing operation of the package already did; the unfolded zero cannot be encoded in the interchange formats. Non-zero results, contexts without `clamp` and exponents at or below the top are unchanged; the IEEE `decimal` package is not changed here (see its opt-in `with_clamp_fold`, [#234](https://github.com/Luna-Flow/floating/issues/234)) ([#419](https://github.com/Luna-Flow/floating/issues/419)).
- Quick gate ([#417](https://github.com/Luna-Flow/floating/issues/417)): a local or CI `just pr` sometimes failed in a `moon` stage (`PACKAGE: published contents`, once a `_build` that had to be cleared) with `decimal@WhiteboxTest@Check:0: input .../ieee_corpus_generated_00_wbtest.mbt missing` and passed when rerun. Two Python tests wrote the generated IEEE corpus files into the real `library/src/decimal` for a moment while the `moon` lane scanned it; they now use a temporary root (`run_targets(..., root=...)`). The stage `TEST: Python tooling` runs `tools/run_python_tests.py`, which fails if any test writes into `library/`, `tooling/`, `doc/` or `testdata/`; a SIGTERM removes the generated files before the process exits; the files are git-ignored and `tools/check_package_contents.py` rejects them (and `_generated_doc_examples`) in a package. The manual examples are compiled with `--deny-warn` and two deprecated calls (`inspect` of an `Option` in the `Decimal` tutorial, `BigInt::from_string` in the `internal` tutorial) were replaced.
- `decimal`: `Decimal::from_bin_float_ctx` converts an in-range binary value at any binary exponent, correctly rounded, at a cost that no longer grows with the exponent: it took the digits from `BinFloat::to_decimal_string_ctx` (the first `precision + 1` digits and a sticky digit, one rounding by `apply_ctx`) instead of the exact expansion `c * 5^k`, and it no longer returns NaN with `invalid_context` beyond a binary exponent of 2^22 for a value the context holds (2^5000000 in a wide context is `9.513052773090666E+1505149`). Instructions retired of one conversion at the binary exponents 2^16, 2^20 and 2^22: 100 M, 18.7 G and 292 G before, 20 M, 18 M and 18 M after (a trivial test is 17.5 M); results, cohorts and flags of every existing row are unchanged. Only the unlimited precision of `DecimalContext::exact()` still refuses a binary exponent beyond 2^22 ([#423](https://github.com/Luna-Flow/floating/issues/423)).
- `decimal_gda`: a non-integral `power` no longer raises `Clamped` for a nonzero result in a clamped context: `power 0.01 0.5` at precision 4, `e_min` -4, `e_max` 0 with `clamp` and `down` was `0.1000 Inexact Rounded Clamped`, it is `0.1000 Inexact Rounded`. The short exact form of the value (a square root, an exact rational power) went through a fold-down before the result was padded to `precision` digits, and the flag stayed; the padded form has an exponent of at most `e_max - precision + 1`, so nothing is altered to fit (GDA 1.70, Clamped). A result that rounds to zero keeps Clamped. Also fixes the exponent `-0.5` (`power 4 -0.5`) and the exact rational and power-of-ten routes. Values and the other conditions are unchanged; the IEEE `decimal` package is not affected ([#397](https://github.com/Luna-Flow/floating/issues/397)).
- `decimal_gda`: `power(x, 0)` in a clamped context returns the integer `1` without folding it down: `power 9.99 0` with precision 5, `e_max` 0 and `clamp` was `1.0000 Clamped`, it is now `1` with no conditions, as GDA 1.70 says ("the result will be 1 and exact"), as decNumber (`decNumberPower` leaves before its final clamp) and libmpdec do. IEEE formats are not affected: their encoders fold at an exponent above 90, 369 and 6111 (decimal32, decimal64, decimal128), far above the exponent 0 of `1`, and only a clamped context with `e_max < precision - 1` could tell the results apart. `power(x, 0)` of the IEEE `decimal` package already returned the unfolded `1`; `1 ** n` is unchanged in both ([#405](https://github.com/Luna-Flow/floating/issues/405)).
- `decimal`, `ball_float`, `bin_float`: `sin`, `cos` and `tan` of an argument of huge exponent returned a certification failure (or did not finish) and now return the correctly rounded result over the whole operand range, `1E+999999` included ([#377](https://github.com/Luna-Flow/floating/issues/377)). Three limits were behind it: the 1,000,000-bit reduction cap of `BinFloat::try_sin_ctx`, `try_cos_ctx` and `try_tan_ctx` (now 8,000,000 bits, an argument of binary exponent k needs p + k + 96), the `ball_float` cutoff of `max(65536, 4p)` bits of exponent (now the same 8,000,000-bit work limit) and the starting precision of the `decimal` driver, which never reached the operand's own size (a huge integer operand now enters `BinFloat` exactly, at the result precision). **Results that were errors are now values, and they cost time**: about 5 s per call at `1E+300000` and about 40 s at `1E+999999` (native release; the table is in the `bin_float` design page). For `ball_float`, `try_sin_interval`, `try_cos_interval` and `try_tan_interval` of such arguments change from `Err` to a tight interval, and `sin_interval`, `cos_interval` and `tan_interval` from `[-1, 1]` or the whole line to the same tight interval; only a work size above 8,000,000 bits is still reported as a resource limit. Callers of the limits: `BinFloat::sin_ctx`, `cos_ctx`, `tan_ctx` and their `try_` forms, the `bin_float_checked` tier, `BallFloat` `sin_interval`, `cos_interval`, `tan_interval` and their `try_` forms, the `ball_float_checked` tier, `Decimal::sin_ctx`, `cos_ctx`, `tan_ctx` and the `decimal_checked` tier.
- `bin_float`: `sin`, `cos` and `tan` of an argument above 256 bits of exponent ran the series at the full reduction precision p + k + 96 instead of the result precision; the reduced enclosure is now rounded outward to `work - k` bits before the series. `sin(2^400000)` at p = 53 takes 0.65 s instead of 164 s with the same value (table in the PR); arguments of at most 256 bits of exponent are unchanged ([#377](https://github.com/Luna-Flow/floating/issues/377)).
- `decimal`: `cospi` of an operand next to zero (`1E-999999`, `1E-1999996`) returned a certification failure; `0 < 1 - cospi(x) < 5 x^2` now decides it before the loop in every rounding direction ([#377](https://github.com/Luna-Flow/floating/issues/377)).
- `decimal`: `sinpi`, `cospi` and `tanpi` of an integer with 4,097 or more digits (`1E+20000`, `7.5E+400000`, `1E+999999`) returned a certification failure because the exact rule expanded the power of ten; the residue modulo 4 is now read from the low limb of the coefficient and the operand is never expanded ([#377](https://github.com/Luna-Flow/floating/issues/377)).
- Tests: the opt-in table `testdata/decimal/ieee/rows/huge_trig_extreme.txt` (9 rows from `1E+300000` to `1E+999999`, 4 to 55 s each) is run on demand with `python3 tools/run_huge_trig_extreme.py`; `huge_trig.txt` (84 rows, up to `1E+100000`) is part of `just gate decimal`. Expected values come from MPFR 4.2.2 at the exact operand (`tools/mpfr_huge_trig.c`).
- `bin_float`: `BinFloat::try_atan2_ctx(y, x, ctx)` with `x > 0` and a quotient `|y/x|` far below the exponent range (for example `5 * 2^-1073741000` over `7 * 2^1073741000`) returned a certification failure; it now returns the correctly rounded result, which is the result of `y / x` there: zero or the smallest subnormal by the rounding direction, with `inexact` and `underflow`, the sign of `y` ([#383](https://github.com/Luna-Flow/floating/issues/383)). The decision uses `0 < atan(t) < t` and applies when `|y/x| < 2^(e_min - p - 1)` of the context, so the results of every other input are unchanged. The point enclosures of `ball_float` `try_atan2_interval` at such arguments change from `Err` to `[0, smallest subnormal]` (mirrored for `y < 0`). `atan`, `atanpi`, `atan2pi` and the `decimal` `atan2` were checked at the same extremes and were already correct.
- `decimal_gda`: `power` of a base that is a power of ten with a non-integral exponent `y` such that `k*y` is an integer returns the exact value `10^(k*y)` padded to the context precision, with Inexact and Rounded, in every rounding mode (GDA 1.70, power: the result "will be inexact" and inexact finite results should be correctly rounded; decTest powx2039 and powx2040 show the same shape). The directed modes (`floor`, `ceiling`, `down`, `up`) changed from NaN with Invalid operation to this result, `power 1E-5 1.2` in decimal64 is `0.000001000000000000000 Inexact Rounded`; `half_even`, `half_up` and `half_down` already gave it. Results beyond the exponent range overflow or underflow through the ordinary rounding of the exact value. Exponents where `k*y` is not an integer keep the certified path. libmpdec is one unit in the last place away in some directed modes for this input class; the `decimal_gda-power` random differential registers the class as an expected difference ([#351](https://github.com/Luna-Flow/floating/issues/351)).
- `decimal`: `pown(1E+999999, -2000000000)` (and the same power of a power of ten with a very negative integer exponent) returned `inf` with overflow instead of the underflow result: `exponent10 * n` wrapped around `Int32` and the decision on the adjusted exponent of the power covered only a positive count ([#375](https://github.com/Luna-Flow/floating/issues/375)). `rootn` with a degree of 10^6 or more no longer spends the exact-root test on operands whose exponent is not a multiple of the degree ([#376](https://github.com/Luna-Flow/floating/issues/376)), and `exp`, `expm1` of a tiny argument such as `1E-999999` and `atan2pi(1E-1999996, 1)` do not form the exact decimal expansion of the binary operand ([#377](https://github.com/Luna-Flow/floating/issues/377) for the `exp` part).
- `decimal`: `exp2_ctx` and `exp10_ctx` (and their `try_` forms) returned a certification failure for a very negative non-integer argument whose result lies far below the subnormal range, in every rounding direction (`exp2(-6773329072.88)` in the context of precision 51, `e_min = -14`, `e_max = 11`; [#363](https://github.com/Luna-Flow/floating/issues/363)). Beyond `2^31` binades the enclosure of the result is `[0, tiny]`, whose endpoints round with different flags, so the Ziv loop never agreed. `exp`, `exp2` and `exp10` now share one exact, proven decision before the loop (`x >= k (e_max + 1)` overflows and `x <= -k (1 - etiny)` is below half of the smallest subnormal, with `k = 3, 4, 1` for base e, 2, 10; derivation in the design page) that returns the result and flags of IEEE 754-2019 7.4 and 7.5 for the rounding direction. The audit of `expm1`, `exp2m1`, `exp10m1`, `sinh`, `cosh`, `pow`, `powr`, `pown`, `compound` and `rsqrt` found no other failure at the range limits; `decimal_gda` `exp` has none either.
- `decimal`: `pow_ctx` and `pown_ctx` with an integer exponent of magnitude at least 2^31 (including `pown` at the `Int32` minimum) were not correctly rounded: the single half-even evaluation lost the deviation of a base near 1, so `pown(1.000000000000000000000000000001, -2^31)` gave `1` in every mode instead of `0.9999999999999999` in Floor (IEEE 754-2019 §9.2). An inexact result of that path is now refined with directed bounds like the `Int` exponent path ([#348](https://github.com/Luna-Flow/floating/issues/348)).
- `decimal`: `pow_ctx` of a power of ten with a non-integral exponent missed exact results: `(1E-5)^1.2` was `1.000000000000000E-6` with Inexact in the nearest modes and NaN (certification failure) in the directed ones. `10^(k*y)` with `k*y` an integer is now returned exact, with the preferred exponent `floor(y * Q(x))` of §9.2.2 ([#349](https://github.com/Luna-Flow/floating/issues/349)).
- `decimal`: `pown_ctx` and integer `pow_ctx` could raise a spurious `clamped` for an inexact result near 1 in a clamped context (`pown(1.000000000000000006354, -40)` at precision 4, `e_max = 0`): a short exact work member was folded down. Inexact work values are now rounded from a full-length member ([#350](https://github.com/Luna-Flow/floating/issues/350)).
- `Decimal::exp_ctx` raised neither underflow nor subnormal for a result far below the range when `precision = 1`, the non-standard `AfterRounding` tininess option is selected and the direction is `Up`, `Ceiling` or `ZeroFiveUp` (`exp(-8E+4)` with `e_min = -10004` gave `1E-10004` with inexact and rounded only): the smallest subnormal equals the smallest normal number then, and the coarse underflow path compared the wrong adjusted exponent. By the option's own rule the result is tiny because it is below `10^e_min` with an unbounded exponent range; tininess before rounding, the rule of IEEE 754-2019 §7.5 for decimal formats and the default, was correct (found by the MPFR decimal random oracle, 22 of 20,000 rows; [#333](https://github.com/Luna-Flow/floating/issues/333)).
- `decimal_gda`: `power_ctx` with an integer exponent raises `Underflow` for an inexact subnormal result whose working value already fits the context: `power 10.000000000000000000000000001 -9` at precision 23, Emin -1, Emax 1 is `1.00000000000000E-9 Inexact Rounded Subnormal Underflow`, no longer without `Underflow`. The exact power `9.99999999999999999999999991E-10` has 27 digits, its 26-digit working value is already `1.00000000000000000000000E-9`, so the final rounding to the context was exact and added no inexactness; the inexactness of the working arithmetic was not used for the Underflow of a delivered value below `10^emin`. Underflow is Subnormal with an inexact result (GDA 1.70, Exceptional conditions, Subnormal and Underflow; IEEE 754-2019 §7.5). Positive exponents and the `-9.E+0` spelling take the same path; `decimal` already delivered these rows and gets regression rows. Found by the seeded random differential (seed 20261119, case `d20261119.power.12658`); Python `decimal` (libmpdec 4.0.0) is the oracle, not the specification ([#342](https://github.com/Luna-Flow/floating/issues/342)).
- `Decimal::atan2_ctx` returned a zero of exponent 0 when the result underflows to zero (`atan2(1E-500, 9)` in decimal64 gave `0`); the zero now has the least exponent `e_min - p + 1`, as for every other function, with the sign of the ordinate (IEEE 754-2019 §5.2; found by the MPFR decimal random oracle, 54 of 20,000 rows; [#332](https://github.com/Luna-Flow/floating/issues/332)).
- `BinFloat::sinpi_ctx`, `tanpi_ctx` and `cospi_ctx` of a tiny argument within about `p + 8` bits of the implementation subnormal limit returned a certification failure (`sinpi`), `-0` with no flags (`tanpi`) and exactly `1` with no `inexact` (`cospi`; round down gave `1` instead of `1 - 2^-p`): the periodic reduction rebuilt the argument with a `BinFloat::make` at the width of its residue, which flushes a value that small. It is rebuilt at the argument's own width ([#316](https://github.com/Luna-Flow/floating/issues/316)).
- `BinFloat::hypot_ctx` returned `0` or `+inf` with no flags, or failed to certify, for operands whose exponent is beyond `2^29` in magnitude, and `0` for an operand beside a much smaller one near the implementation subnormal limit: the exact sum of squares was built with a doubled exponent, which leaves the range of `BinFloat::make` (and of the 32-bit exponent). The sum is now kept at the operands' own scale and rounded by a square root of `T * 2^(2 m)` that never forms the doubled exponent; the power-of-two stand-in for a negligible operand is built wide enough not to be flushed ([#275](https://github.com/Luna-Flow/floating/issues/275)).
- `BinFloat::expm1_ctx`, `log1p_ctx`, `sinh_ctx`, `tanh_ctx`, `asinh_ctx`, `atanh_ctx`, `sin_ctx`, `tan_ctx` and `asin_ctx` returned the argument itself with no flags, in every rounding direction, for a tiny argument within about `p + 8` bits of the implementation subnormal limit (`expm1(2^-1073741860)` at `p = 53`), and `expm1` returned NaN for such an argument at `p = 2`: the offset and the inner endpoint of the tiny-argument enclosure were built with a `BinFloat::make` at their own width, which flushes a value that small, so the enclosure collapsed to the exact argument. Both are now built wide enough to be kept; the correctly rounded result and its `inexact` and `underflow` flags follow ([#315](https://github.com/Luna-Flow/floating/issues/315)).
- `decimal_gda`: an inexact integer `power_ctx` result that rounds to a power of ten no longer raises `Clamped` under `clamp`: `power 0.9999999 -1` at precision 4, Emax 0 is `1.000 Inexact Rounded`. The final rounding trims the zeros (`1000` to `1`), the trimmed exponent is above Etop, and the fold-down was flagged although the full-precision form of an inexact result, with the exponent adjusted - precision + 1, is at most Etop and nothing is altered to fit (GDA 1.70, Exceptional conditions, Clamped). #282 only took the flag back when padding changed the coefficient. Found as rows .1081 and .1129 of the seeded random differential; `decimal` is not affected and gets regression rows ([#305](https://github.com/Luna-Flow/floating/issues/305)).
- `decimal_gda`: the power of a base of value 1 to a non-integer exponent is `1` with `precision` digits, `Inexact` and `Rounded`, whatever Emax is: `power 1 1.03` at precision 5, Emax 0 is `1.0000 Inexact Rounded`, where it was the exact `1` (and `Clamped` under clamp). A shortcut for exponents whose adjusted exponent is at least Emax, meant for astronomically large exponents, also caught 1.03 when Emax is 0. GDA 1.70 *power*: "the result will be inexact unless the right-hand side has an integral value and the result is finite and can be expressed exactly within precision digits"; the official corpus agrees (`power 1 1.01 -> 1.00 Inexact Rounded`). `decimal` is not affected: IEEE 754-2019 §9.2.1 gives `pow(+1, y)` the exact value 1 for any y. Found as row .3705 of the seeded random differential ([#306](https://github.com/Luna-Flow/floating/issues/306)).
- `BinFloat::exp2_ctx` of an integer `n` below `e_min = 1 - 2^30` (for example `exp2(-2^30)` at `p = 2`, where `2^n` is an exactly representable subnormal) returned `+0` with no flags, because the exact power was built by a one-bit `BinFloat::make`, which flushes below `2^e_min` before the context rounds it; it now returns `2^n` with no flags, or the rounded neighbour with `inexact` and `underflow` below the smallest subnormal, in every rounding direction (IEEE 754-2019 §9.2, §7.5). The interval `BallFloat::try_exp2_interval` enclosed `{0}` for the same arguments and now contains the value ([#271](https://github.com/Luna-Flow/floating/issues/271)).
- `BinFloat::pow_ctx` returned `+0` with no flags for an exact power of two below `2^e_min`, such as `(1/4)^(2^29 + 1/2)`, through the same one-bit `make` ([#272](https://github.com/Luna-Flow/floating/issues/272)).
- `BinFloat::pown_ctx` omitted `underflow` under after-rounding tininess when the `p`-bit rounding of a result near the implementation limit `2^(1 - 2^30)` is tiny but the subnormal grid delivers `2^e_min`: the unbounded rounding of the tininess test still had the implementation subnormal range ([#273](https://github.com/Luna-Flow/floating/issues/273)).
- `BinFloat::pown_ctx` rounded a result between half and the whole smallest subnormal (for example `3^-677455689` toward negative at `p = 40`) to the wrong neighbour: the endpoints of its Ziv enclosure were built at the bit length of their coefficients and flushed to zero or to the smallest value of that width ([#278](https://github.com/Luna-Flow/floating/issues/278)).
- `BinFloat::try_hypot_ctx` returned `+inf` for `hypot(±inf, sNaN)`; IEEE 754-2019 §9.2 gives `+inf` only beside a quiet NaN, and a signaling NaN operand is an invalid operation whose result is a quiet NaN (payload and sign kept). The `invalid` flag was already raised ([#293](https://github.com/Luna-Flow/floating/issues/293)).
- `BinFloat::try_pow_ctx` (and `pow_ctx`, `pow`) returned `1` with no flags for `pow(sNaN, 0)` and `pow(+1, sNaN)`, because the two shortcuts of IEEE 754-2019 §9.2.1 ran before the NaN handling; a signaling NaN operand now gives a quiet NaN with the payload and sign kept and `invalid`, and `pow(qNaN, 0)` and `pow(+1, qNaN)` still give `1` without a flag ([#289](https://github.com/Luna-Flow/floating/issues/289)).
- `BinFloat::expm1_ctx` returned NaN with `invalid` instead of overflowing when `x log2(e)` lies in `[e_max + 1, e_max + 2)`: the overflow pre-check left that window to a loop that cannot certify an out-of-range enclosure ([#274](https://github.com/Luna-Flow/floating/issues/274)).
- `bin_float_checked`: the elementary `BinFloatResult` methods (`exp` ... `tanpi` and their `_ctx` forms) and `pow`, `pow_ctx`, `rootn`, `rootn_ctx`, `hypot`, `hypot_ctx`, `atan2`, `atan2_ctx` no longer drop the exception flags of the `try_*_ctx` operation. As for `div` and `pown` (formerly `pow_int`, #262), the invalid operation exception (IEEE 754-2019 §7.2, §9.2: a signaling NaN operand or an argument outside the Table 9.1 domain) is a `DomainError` and divideByZero (a §9.2 pole) a `DivisionByZero` error: `ln(0)`, `log1p(-1)`, `atanh(1)`, `tanpi(0.5)`, `rootn(0, -2)` and `pow(0, -1.5)` were `Ok(±inf)`, `ln(-inf)` and every signaling NaN operand `Ok(NaN)`. Overflow, underflow and inexact are still dropped; the arithmetic `_ctx` methods (`add_ctx` ... `pown_ctx`) still keep the IEEE default value. The design page now states the two contracts ([#290](https://github.com/Luna-Flow/floating/issues/290)).
- `bin_float`: `pown_ctx` (formerly `pow_int_ctx`) and the natural-exponent power behind `PowNatChecked` no longer return 1 for a signaling NaN base with a zero exponent. IEEE 754-2019 §9.2.1 gives `pown(x, 0) = 1` only for an `x` that is not a signaling NaN, so the result is now the quieted NaN (payload kept, §6.2) with the invalid flag (§7.2 a), and the checked tier (`pown`, formerly `pow_int`, `pow_int_checked`, `pow_nat_checked`, `BinFloatResult`) returns `DomainError`. A quiet NaN with a zero exponent still gives 1 without a flag ([#286](https://github.com/Luna-Flow/floating/issues/286)).
- `bin_float` and `bin_float_checked`: the checked division, square root and integer powers (`DivChecked`, `SqrtChecked`, `PowNatChecked`, `PowIntChecked`, `BinFloat::div_checked`, `sqrt`, `sqrt_for_precision` (private since this release), `pown` (formerly `pow_int`) and the `BinFloatResult` methods built on them) now derive their error from the flags of the contextual operation instead of guarding on the operands. The checked result is the IEEE 754-2019 default result, with the invalid operation exception (§7.2) as `DomainError` and divideByZero (§7.3) as `DivisionByZero`, as the `Double` instances of Luna-Flow/arithmetic and both `Decimal` instances do: `NaN / 0` is `Ok(NaN)` and `inf / 0` is `Ok(inf)` (both were `DivisionByZero`), `0 / 0` is `DomainError` (was `DivisionByZero`), `inf / inf` is `DomainError` (was `Ok(NaN)`), `sqrt(-NaN)` is `Ok(NaN)` (was `DomainError`), and a signaling NaN operand is `DomainError` (§7.2 a; was `Ok(NaN)` or `DivisionByZero`). A clause-annotated table covers every special-value combination in five rounding directions at precisions 24, 53 and 113 ([#262](https://github.com/Luna-Flow/floating/issues/262)).
- `decimal_gda` and `decimal`: `power_ctx` (`pow_ctx` in `decimal`) with a negative integer exponent in a non-extended context (`extended = false`, the subset arithmetic) no longer aborts with `decimal_apply_finite_ctx expects a finite operand` when the reciprocal of a tiny positive power leaves the working range. That is the overflow of the result (GDA 1.70, Exceptional conditions, Overflow; IEEE 754-2019 §7.4), now delivered as the overflow result of the context with the sign of `x^n`. 71 of 20,000 random subset rows aborted before; the other 19,929 rows give the same results and flags as before. The `Known deviations` list of the `decimal_gda` conformance page now records the exponent limit of nine digits, the last-digit differences in the directed modes and the zero base with a negative exponent ([#283](https://github.com/Luna-Flow/floating/issues/283)).
- `decimal_gda` and `decimal`: `power_ctx` (`pow_ctx` in `decimal`) with an integer exponent no longer raises `Clamped` (or the `Rounded` that the padding behind it caused) for a result whose exponent was not altered: `power 6E-1 2` at precision 1, Emin -1, Emax 0 with `clamp` is `0.4 Inexact Rounded`, not also `Clamped`. The working-precision multiplications inherited `clamp`, folded an intermediate product down to the working Etop and let its flag and padded coefficient reach the result; the working context no longer clamps, so only the delivered result is folded and flagged (GDA 1.70, Exceptional conditions, Clamped). In `decimal`, `clamped` and `rounded` are conditions of the package's own contract, for which IEEE 754 has no clause. Python `decimal` (libmpdec 4.0.0) is the oracle, not the specification ([#267](https://github.com/Luna-Flow/floating/issues/267)).
- `decimal_gda` and `decimal`: an exact negative integer power keeps the cohort of repeated multiplication from the reciprocal. Without `clamp`, the exact reciprocal that starts the power was padded towards exponent 0 (`1 / 5E-2` gave `20`, not `2E+1`), so `power 0.05 -8` at precision 5 was `2.5600E+10` (not `2.56E+10`) and at precision 3 raised `Rounded` for an exact result; `power 0.05 -3` at precision 2 was `8.0E+3`, not `8E+3` (GDA 1.70 *power*: the exponent of an unrounded result is the one repeated multiplication gives; IEEE 754-2019 §5.2 and §9.2.2 for `decimal`). The reciprocal now keeps the cohort of the division, as it already did under `clamp`. 50 of 12,288 rows of an exact-reciprocal grid failed in each package, none now ([#284](https://github.com/Luna-Flow/floating/issues/284)).
- `decimal_gda` and `decimal`: `power_ctx` (`pow_ctx` in `decimal`) with an integer exponent signals `Subnormal` and `Underflow` for an inexact power whose exact value is just below `10^emin` but whose delivered result is `10^emin`: `1 / 1.00000000000000000001` at precision 1 and Emin 0 is `1` with `Underflow Subnormal Inexact Rounded`. Tininess is judged on the exact result before rounding (GDA 1.70, Exceptional conditions, Subnormal and Underflow; IEEE 754-2019 §7.5 for decimal formats). The working arithmetic only knew the rounded power; `decimal_gda` now decides the side of the exact power by repeating the multiplication at a doubled precision with a proven error bound, and the `decimal` enclosure is refined while it straddles `10^emin`. The side of the exact power in the new rows comes from exact rational arithmetic; Python `decimal` (libmpdec 4.0.0) supplies the rest and is an oracle, not the specification ([#268](https://github.com/Luna-Flow/floating/issues/268)).
- `decimal_gda` and `decimal`: `power_ctx` (`pow_ctx` in `decimal`) of a power of ten under `clamp` folds an exponent above Etop down and signals `Clamped`: `(-1E+998)^1` at precision 7, Emax 999 is `-1.00000E+998 Clamped`, `(-1E+1)^-1` at precision 3, Emax 0 is `-0.10 Clamped`. The exact power-of-ten shortcut (`decimal_power_ten_cohort_result`) returned the preferred cohort without the fold-down (GDA 1.70, Exceptional conditions, Clamped). The value 1 keeps its cohort, as it does in libmpdec; whether `x^0` and the powers of 1 should fold is an open question on the issue. 94 of 31,284 rows of a powers-of-ten grid failed, none new now. In `decimal` the `clamped` condition is the package's own contract, for which IEEE 754 has no clause ([#287](https://github.com/Luna-Flow/floating/issues/287)).
- `decimal_gda` and `decimal`: `add_ctx`, `sub_ctx` and `fma_ctx` no longer report `Overflow` when an operand (or the exact product) would round past the largest finite number on its own but the rounded sum is in range, as in `9.5 + -0.5` at precision 1 and Emax 0, which is `9`. Overflow is judged on the result after rounding (GDA 1.70, Exceptional conditions, Overflow; IEEE 754-2019 §7.4); non-extended contexts are unchanged. The oracle for the new rows is Python `decimal` (libmpdec 4.0.0), which is evidence, not the specification ([#264](https://github.com/Luna-Flow/floating/issues/264)).
- `decimal_gda` and `decimal`: `power_ctx` (`pow_ctx` in `decimal`) of a negative base and an even negative integer exponent that overflows now returns `+Infinity` (or the largest finite number in the directed modes), not `-Infinity`. The reciprocal that overflowed the working context carried the sign of the base into the result; GDA 1.70 *power* gives the result sign 1 only for an odd integral exponent and a negative base, and IEEE 754-2019 §7.4 gives an overflow the sign of the intermediate result. Odd exponents, signed zeros and underflow signs have tests. Python `decimal` (libmpdec 4.0.0) is the oracle, not the specification ([#265](https://github.com/Luna-Flow/floating/issues/265)).
- `decimal_gda`: an inexact `power_ctx` result with an integer exponent keeps `precision` digits, trailing zeros included: `99999E-1 ^ -1` at precision 2 is `0.00010`, not `0.0001`. GDA 1.70 rounds a result with more digits than the precision "to exactly precision digits", IEEE 754-2019 §5.2 uses the cohort member of least possible exponent for an inexact result, the official decTest corpus has 126 inexact `power` rows with a trailing zero and none that is shorter than the precision, and Python `decimal` (libmpdec 4.0.0) agrees. The non-integer power already padded; a subset context (`extended = false`) still strips the zeros (GDA 1.70, Appendix A). Padding also takes back a `Clamped` that the trimmed coefficient had caused (the padded coefficient is at most Etop, so nothing was altered to fit). `decimal` already returned the padded result and gets regression rows only ([#266](https://github.com/Luna-Flow/floating/issues/266)).
- `BinFloat::from_hex` reads the whole IEEE 754-2019 §5.12.3 hexSequence grammar: a hexadecimal significand with a point (`0x1.8p0`, `0x.8p1`, `0x1.p0`) was rejected before, the exponent is read as decimal digits only, and `snan` in any case (§5.12.1) gives a signaling NaN. Every production has accepting and rejecting tests and a round trip; the signature is unchanged. The missing rounding direction and flags are tracked in [#256](https://github.com/Luna-Flow/floating/issues/256) ([#225](https://github.com/Luna-Flow/floating/issues/225)).

### Verified

- `rootn(x, 0)` is pinned as an invalid operation for every `x`, a quiet NaN and `±0` included, and not `divideByZero` (IEEE 754-2019 Table 9.1 "n = 0: invalid operation"; §7.3 keeps divideByZero for `rootn(±0, n)` with `n < 0`): a contextual test, the checked-tier rows, and a sentence in both API pages ([#294](https://github.com/Luna-Flow/floating/issues/294)).
- IEEE 1788-2015 §12.10: the `ball_float` conformance page documents the tightness of every interval operation with its range and evidence (§12.10.3). The ITF1788 strict gate compares both endpoints with the corpus's tightest binary64 result, so the arithmetic, `abs`/`minimum`/`maximum`, `pown`, trigonometric, `atan2` and power phases are tightness evidence; the page said containment before. The forward-operation row is now partial, because the integer functions of Table 9.1 are not provided ([#257](https://github.com/Luna-Flow/floating/issues/257)) ([#229](https://github.com/Luna-Flow/floating/issues/229)).
- IEEE 754-2019 §5.10 totalOrder and totalOrderMag for `decimal` are checked against an independent corpus: a transcription of §5.10 cross-checked with libmpdec, every ordered pair of cohorts, signed zeros, subnormals, infinities and NaNs with payloads in decimal32/64/128 (18,816 pairs) on four targets ([#227](https://github.com/Luna-Flow/floating/issues/227)).
- General Decimal Arithmetic Appendix A (subset arithmetic) is conforming: the `DECIMAL_GDA` gate runs the pinned subset corpus `dectest0.zip` (16,124/16,124 executable rows); the clause row and checklist now say so ([#228](https://github.com/Luna-Flow/floating/issues/228)).

## 0.10.2 - 2026-11-12

### Changed

- Dependencies: `Luna-Flow/arithmetic` 0.5.2 (was 0.5.1), `Luna-Flow/type_theory` 0.4.1 (was 0.4.0), `Luna-Flow/mare_mark` 0.4.2 (was 0.4.1).
- Require MoonBit `moonc` 0.10.20 or later, verified with `moon 0.1.20261104` and `moonc v0.10.20`: `derive(...)` clauses are now `#derive(...)` attributes, which older 0.10 compilers ignore. No public API changed.
- Replace the deprecated `String::view(start_offset~, end_offset~)` with `exact_view(start~, end~)`, which keeps the same bounds check.
- Bump `moonbitlang/async` from 0.22.5 to 0.22.9. It has no wasm-gc runtime ([moonbitlang/core#4584](https://github.com/moonbitlang/core/issues/4584)), so the skipped `async test` benchmarks in `bench/*` now live in files built only for native, JS and wasm instead of relying on the old pin.
- Sync the API snapshots in `doc/manual/api` with the regenerated interfaces.

## 0.10.1 - 2026-10-31

- Documentation: the known-limitations list of the `ball_float` design page and the known-gaps table no longer claim that decorated `rootn` with a negative degree keeps its decoration when 0 is in the argument. The decoration has been lowered to `trv` since the pole fix (`e008dd1`), and `src/ball_float/ball_float_decorated_wbtest.mbt` checks it; issue [#233](https://github.com/Luna-Flow/floating/issues/233) was opened from the stale text and is closed.
- Documentation: the "Known gaps and deviations" table of `doc/manual/verification.md` now links the issue that tracks each gap (roadmap [#245](https://github.com/Luna-Flow/floating/issues/245)).

### Changed

- Dependencies: Luna-Flow/mare_mark 0.4.1, moonbitlang/x 0.5.7, moonbitlang/async 0.22.5. async 0.22.6 and later make moonc v0.10.18 emit invalid wasm-gc for the `bench` tests, so async stays at 0.22.5. Interfaces regenerated with moon 0.1.20261028.


## 0.10.0 - 2026-10-13

### Added

- **Required versus recommended:** each clause row of the IEEE 754-2019 and 1788-2015 conformance tables now has a `Level` (`required`, `recommended`, `optional`), the checklist counts required gaps separately from recommended ones, and the §9.5 decimal row now says augmented arithmetic is recommended for binary formats only.
- **Conformance checklist:** `doc/manual/verification.md` has a task-list checklist and per-standard counts (IEEE 754-2019 for `bin_float` and `decimal`, General Decimal Arithmetic 1.70, IEEE 1788-2015) generated from the clause traceability tables by `tools/conformance_checklist.py`; `just docs` fails when it is stale.
- **Standards conformance statement ([#157](https://github.com/Luna-Flow/floating/issues/157); Closes #157):** each conformance page now has a clause traceability table (IEEE 754-2019 for `bin_float` and `decimal`, General Decimal Arithmetic 1.70 for `decimal_gda`, IEEE 1788-2015 for `ball_float`: clause, public API, evidence, status), and `verification.md` lists the implementation-defined choices (tininess, NaN payload and sign, exponent ranges, accuracy, interval flavor) and the known gaps with their issues. `tools/doc_quality.py` fails when a cited `src/`, `testdata/` or `tools/` path does not exist. The decimal IEEE matrix (`testdata/decimal/ieee/conformance_matrix.json`) now lists the trigonometric, hyperbolic, exp/log and power families as covered, which the MPFR-certified oracle has long exercised. Writing the tables found that `decimal` defaults to after-rounding tininess although IEEE 754-2019 §7.5 requires before rounding for decimal formats: issue [#217](https://github.com/Luna-Flow/floating/issues/217).
- **MPFR differential corpora for decimal character conversion ([#11](https://github.com/Luna-Flow/floating/issues/11), [#12](https://github.com/Luna-Flow/floating/issues/12); Closes #11, Closes #12):** two hash-pinned MPFR 4.2.2 fixtures generated by `tools/generate_mpfr_decimal_string_oracle.c` and run by `frontend/mpfr_expr`, the `mpfr-expr` CLI, the committed binary smoke and the binary gate: 1,716 `mpfr_strtofr` rows (decimal text to binary at 11 to 200 bits under all six roundings, including exact halfway points, one-unit-off-halfway strings, 400-digit mantissas, exponents up to ±`3*10^8` and the exponent limits) and 3,300 `mpfr_get_str` rows (fixed digit counts, exact ties, and the shortest round-trip digit count of 1,200 values). All rows pass. The binary smoke grows from 2,451 to 7,467 rows.

### Fixed

- **Caller-visible, behavior change ([#217](https://github.com/Luna-Flow/floating/issues/217); Closes #217):** `DecimalContext` (`new`, `try_new`, `decimal32/64/128`, `from_arithmetic_context`, `exact`) now defaults to `DecimalTininessDetection::BeforeRounding`, as IEEE 754-2019 §7.5 requires for decimal formats ("For decimal formats, tininess is detected before rounding"). A result whose exact value is below `10^e_min` but rounds up to `10^e_min` (decimal64 `0.99951` at `p = 3`, `e_min = 0`) now raises `underflow` and `subnormal` when inexact. Values and every other flag are unchanged. `AfterRounding` stays available as an explicit non-standard option (`tininess=` or `with_tininess`).
- **Caller-visible ([#196](https://github.com/Luna-Flow/floating/issues/196); Closes #196):** `decimal` `power_ctx` and `pown`-style integral exponents with more than 4,096 digits no longer give NaN with `invalid_context` for a base other than `±1`, `±0` and `±inf`: `pow(2, 1E+4100)` is `inf` with `overflow`, `pow(0.5, 1E+400000)` underflows to zero or the smallest subnormal by the rounding direction. The result is decided from `|y ln|x||` (at least `10^(digits(y) - 2 + min(q, 0))` for a base with exponent `q`) without exponent-sized work.
- **Caller-visible ([#185](https://github.com/Luna-Flow/floating/issues/185); Closes #185):** `BinFloat::tanh_ctx` and `try_tanh_ctx` no longer fail for a finite argument beyond about `2^30` (`Err`, NaN with empty flags): for `|x| > (p + 4) ln 2 / 2` the result is `±1` or the adjacent value `±(1 - 2^-p)` by the rounding direction, with `inexact`, as `expm1` already did at negative saturation. `sinh`, `cosh`, `asinh`, `acosh` and `expm1` were checked at `2^30` to `2^1000` and are unaffected.
- `BinFloat::from_string_ctx` no longer aborts ("precision exceeds binary_precision_max") for a literal whose value lies within a few binades of the exponent limit, such as `1e323228497`. `10^k` left the exponent range before `D * 10^k` did, so the certified rounding retried at ever higher precision; the working enclosure now uses `5^k` and applies `2^k` after rounding, in the context with its exponent range shifted by `k`.
- Documentation: the implementation exponent range `[1 - 2^30, 2^30 - 1]` for the leading bit is one binade higher at both ends than MPFR's (`emax = 2^30 - 1` in MPFR's `0.1xxx * 2^e` convention gives the leading bit `2^30 - 2`); the conformance notes now say so.
- **Caller-visible ([#187](https://github.com/Luna-Flow/floating/issues/187); Closes #187):** `decimal` and `decimal_gda` no longer abort or return wrong values for operands whose exponents are near the `Int` limits. Fixed: `sqrt` of a tiny operand (`5E-2147483648` aborted, `5E-2147483647` gave `inf`; both now underflow like any value below `Etiny`), `remainder`/`remainder_near` quotient-length checks (the exponent difference wrapped; `remainder(7, 9E-2147483648)` is NaN with `division_impossible`, and the IEEE `decimal` `remainder_near` forms its exact remainder with the power of ten reduced in chunks), `rescale` with an exponent operand beyond `Int`, `add`/`sub`/`fma` with a zero operand at a very low exponent in `decimal_gda` (negative shift abort, extra `clamped`), `fma`/`mul` whose product exponent exceeds `Int` (overflow, not underflow) or whose tiny result takes the sign of the larger operand, the nearest-quotient comparison (adjusted exponent of the doubled dividend), and a rounding carry at `Int` max (`add(10E100, 99E2147483646)` at precision 1 returned `1E-999999999`, now overflows). 2,000+ extreme-operand cases per package agree with Python `decimal`, apart from two documented semantic differences (see the PR): the `decimal` `sqrt` tininess rule (IEEE after rounding) and a zero `quantize` result above `e_max - p + 1` with `clamp`.
- **Caller-visible ([#211](https://github.com/Luna-Flow/floating/issues/211); Closes #211):** `decimal_gda` `power_ctx` keeps the exponent of repeated multiplication (General Decimal Arithmetic, *power*) for integer powers of `1`, `-1` and of `1E+q`: precision 16 `power(1.00, 2)` is `1.0000` (was `1`), `power(-1.0, 3)` is `-1.000`, `power(1E+5, 2)` is `1E+10` (was `10000000000`) and `power(-1E+5, 5)` is `-1E+25` without `rounded`. 828 integer-power cases agree with Python `decimal` (215 differed).
- **Caller-visible ([#194](https://github.com/Luna-Flow/floating/issues/194); Closes #194):** `decimal` `pown_ctx` and `power_ctx` deliver an exact result in the cohort member closest to the IEEE 754-2019 §9.2.2 preferred exponent, `floor(n * Q(x))` for `pown` and `floor(y * Q(x))` for `pow`: decimal64 `pown(1.00, 2)` is `1.0000` (was `1`), `pown(-1.0, 3)` is `-1.000`, `power(1.00, 1.5)` is `1.000`, `power(4.00, 1.5)` is `8.000`, and `pown(-1E+5, 5)` is `-1E+25` without `rounded` (was `-1.000000000000000E+25|rounded`). `decimal_gda` is not changed here.
- **Caller-visible ([#60](https://github.com/Luna-Flow/floating/issues/60); Closes #60):** `bench.tune_dataset` gives `@tune.select_best` a real secondary criterion, the interquartile range of the candidate's samples, so `practical_delta_pct` now has an effect: candidates within the threshold of the smallest median are decided by the smaller IQR, then the smaller candidate id, independent of `candidate_ids` order. The `paired_hotspot` confidence argument was already fixed by [#80](https://github.com/Luna-Flow/floating/pull/80).
- **Caller-visible ([#150](https://github.com/Luna-Flow/floating/issues/150); Closes #150):** `Decimal::from_int`, `from_bigint`, `from_double`, `from_float` and `from_bin_float` (`decimal` and `decimal_gda`) return the IEEE 754-2019 preferred cohort instead of the reduced member. An integer of at most `precision` digits keeps exponent 0 (`from_int(1000)` is `1000`, was `1E+3`); an exact binary value takes the exponent closest to 0 (`from_double(0.5)` is `0.5`, `from_double(100.0)` is `100`); an inexact or too long value is rounded to exactly `precision` digits (`from_double(0.1, precision=16)` is `0.1000000000000000`, was `0.1`). `Decimal::make` is unchanged and still returns the reduced member.
- **Caller-visible ([#151](https://github.com/Luna-Flow/floating/issues/151), [#152](https://github.com/Luna-Flow/floating/issues/152); Closes #151, Closes #152):** `decimal` and `decimal_gda` NaN payloads follow IEEE 754-2019. `get_payload` returns `-1` for a non-NaN (§9.7); `set_payload` and `set_payload_signaling` return a NaN with the payload only for a non-negative integer of at most `precision - 1` digits and `+0` otherwise, whatever the receiver is (a negative payload used to give NaN with its absolute value, and a non-NaN receiver was returned unchanged). A NaN propagated through a `clamp` (interchange-shaped) context keeps at most `p - 1` payload digits, as `from_string_ctx` does: decimal64 `NaN1234567890123456 + 1` is `NaN234567890123456`.
- **Caller-visible ([#180](https://github.com/Luna-Flow/floating/issues/180); Closes #180):** `decimal_gda` `Decimal::parse` and `from_string` no longer return the reduced cohort member for a literal with more digits than the precision. Following the General Decimal Arithmetic to-number conversion, the coefficient is shortened to exactly `precision` digits and keeps its trailing zeros: at precision 3, `1.0001` is `1.00` (was `1`), `10001` is `1.00E+4`, `99999` is `1.00E+5` and `9.9999` is `10.0`. The shared rounding helper also keeps `precision` digits after a carry into `10^p`, as `decimal` does since #178.
- **Caller-visible ([#168](https://github.com/Luna-Flow/floating/issues/168); Closes #168):** `decimal` and `decimal_gda` integer powers (`pown_ctx`, `power_ctx`, `exp10_ctx`) whose exact value lies below the smallest subnormal now round in the rounding direction (IEEE 754-2019 §4.3, §7.5) instead of returning zero in every mode: `pown(9.9E-200, 2)` is `1E-398` to nearest (it is `9.801E-399`), and `pow(0.1, 400)` is `1E-398` rounding up, as `mul_ctx` already was. The bound shortcut no longer fires when the adjusted exponent is `Etiny - 1`, and an exact power of ten with a non-unit coefficient (`10`, not `1E+1`) takes the same overflow/underflow route, so `decimal_gda` `power(10, -1E+30)` no longer returns NaN.
- **Caller-visible ([#171](https://github.com/Luna-Flow/floating/issues/171); Closes #171):** Decimal and binary `rootn` now handle every nonzero `Int` degree. Decimal exact-root detection skips impossible high-degree probes using a coefficient-size bound, avoiding degree-sized integer powers; binary certification handles the full signed `Int` range, including `Int.min`.

## 0.9.0 - 2026-10-13

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

- Builds with the latest MoonBit toolchain (moon 0.1.20261012, moonc 0.10.15):
  the dependencies are raised to `Luna-Flow/arithmetic` 0.5.1,
  `Luna-Flow/type_theory` 0.4.0 and `Luna-Flow/mare_mark` 0.4.0 (their earlier
  releases depend on packages that ship the legacy `moon.mod.json`, which the new
  toolchain rejects), the four decimal cache cells use `@ref.Ref(...)` instead
  of the deprecated `@ref.new(...)`, and the sources follow the formatter of that
  toolchain.

- **Caller-visible:** `decimal_gda`'s `Decimal::exp_contextual` (and any other
  `*_contextual` adapter that meets the condition), `pow_int_checked` and
  `pow_nat_checked` now report a GDA `Invalid_context` as
  `Err(unsupported)` with an `invalid context:` message instead of
  `Err(domain_error)`. Code that matched `is_domain_error()` for this case must
  match `is_unsupported()` instead; `Luna-Flow/arithmetic` 0.5.0 has no
  invalid-context error kind (#111).
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

- **Caller-visible ([#183](https://github.com/Luna-Flow/floating/issues/183); Closes #183):** `decimal_gda` `remainder` and `remainder_near` now use the exact integer quotient and report only the flags of the delivered remainder, so extended contexts no longer leak the quotient's Division impossible/Clamped flags or return wrong results for large quotients; zero dividends are handled (GDA 1.70 `remainder`, `remainder-near`). `divide_integer` of a zero dividend no longer reports Division impossible or Clamped, and the subset zero is `+0`.

- **Caller-visible ([#192](https://github.com/Luna-Flow/floating/issues/192); Closes #192):** Interval `pow` and `atan2` now treat `-0` and `+0` endpoints as the real zero. This changes results for intervals with a signed-zero endpoint.

- **Caller-visible ([#170](https://github.com/Luna-Flow/floating/issues/170); Closes #170):** Tiny arguments to decimal elementary functions, `hypot` and `atan2` in wide formats now return correctly rounded results promptly instead of NaN or taking minutes to certify.

- **Caller-visible ([#193](https://github.com/Luna-Flow/floating/issues/193)):** IEEE decimal `power_ctx` no longer aborts or performs unbounded work for fractional bases with very large negative integral exponents. The result now follows the context's overflow direction, including finite values on both sides of the overflow boundary.

- **Caller-visible ([#167](https://github.com/Luna-Flow/floating/issues/167)):** IEEE `Decimal::power_ctx` now accepts finite integral exponents above the decNumber count bound in the default context. Previously those inputs returned `invalid_context`; powers within the bounded work path now return their correctly rounded finite, overflow, or underflow result. Exponent coefficient expansion is capped at 4,096 decimal digits; larger coefficients return NaN with `invalid_context` without entering an exponent-sized loop. `decimal_gda` keeps its GDA compatibility behavior.

- **Caller-visible ([#166](https://github.com/Luna-Flow/floating/issues/166)):** IEEE `Decimal::power_ctx` and `pown_ctx` now
  return 1 for $0^0$, signed zero for positive integer powers of zero, and
  signed infinity with `division_by_zero` for a zero base and negative integer
  exponent. `pow(1, y)` and `pow(-1, ±inf)` are 1. The checked integer-power
  routes return `Ok(1)` for a zero or quiet-NaN base with exponent zero and
  `Err(division_by_zero)` for a zero base with a negative exponent. Signaling
  NaN operands still produce a quiet NaN with `invalid_operation`; `decimal_gda`
  retains its distinct GDA behavior.

- **Breaking:** Decimal and GDA context constructors now return `Result` and
  reject precision outside `1..=999,999,999`, `e_min` outside
  `-999,999,999..=0`, or `e_max` outside `0..=999,999,999`; positive `e_min`
  and negative `e_max` are rejected. These sign constraints imply
  `e_min <= e_max`, so the former separate ordering check is redundant. The
  exponent limits adopt decNumber's `decContext.h`; GDA 1.70 specifies no fixed
  limit and requires a balanced range, which this library does not enforce. The
  changed signatures also include `DecimalContext::from_arithmetic_context`
  and `decimal_gda::context()`; callers must handle the returned domain error.
  Both decimal implementations use the same checked Etiny/Etop bounds and
  FMA exponent-gap handling (#145, #186, #188).
- Fused multiply-add no longer materializes an exponent-sized alignment for
  operands inside the supported context range. Far-gap products use a sticky
  addend, while an opposite-sign addend at the `e_max + 1` boundary can round
  back to the largest finite value without a false `Overflow` signal (#145).
- Fixed decimal and GDA engineering-string formatting at the `Int` exponent
  endpoints: engineering exponents are now calculated in `Int64`, so the
  output exponent keeps its sign and value instead of wrapping (#153).

- Fixed `Decimal::tanh_ctx` and `Decimal::expm1_ctx` returning NaN when large
  finite inputs made the certified loop unable to distinguish a result from
  its saturation limit. IEEE 754-2019 §9.2 now returns the correctly rounded
  limit or adjacent value with `Rounded` and `Inexact`
  ([#169](https://github.com/Luna-Flow/floating/issues/169)).
- Fixed `decimal_gda::Decimal::divide_integer` zero quotients in clamped
  extended contexts: the preferred exponent is folded to the clamp limit and
  `Clamped` is raised for finite and infinite divisors (#179).
- **Caller-visible:** Fixed `Decimal::parse` and `Decimal::from_string`
  reducing the cohort of a literal rounded to `precision`: `"1.0001"` at
  precision 3 came back as `1` and `"99999"` as `1E+5`. IEEE 754-2019 §5.2
  keeps all $p$ digits of an inexact conversion, so they are now `1.00` and
  `1.00E+5`; an exact literal keeps the member closest to its own exponent
  (#149).
- Fixed `Decimal::divide_integer` returning a zero integer quotient with
  exponent 0 and no `clamped` flag in a clamped extended context, both for a
  finite zero quotient such as `-8.95E-6 // 2.40E-5` and for `x // Inf`. The
  preferred exponent 0 is now folded down to $e_{\max}-p+1$ and `clamped` is
  raised (#147).
- Fixed IEEE and GDA `Decimal::parse_checked` using only the context precision.
  Parsing now uses the context's rounding direction, exponent bounds and clamp
  setting through `from_string_ctx`; invalid syntax still returns
  `Err(parse_error)` (#154).
- Fixed `Decimal::rootn_ctx` missing the exact results for degree `1` and
  `-1`: `rootn(5, -1)` came back as `0.2` with `inexact` and the directed
  modes failed certification with NaN. `rootn(x, 1)` and `rootn(x, -1)` are
  now decided exactly like the other degrees (#165).
- Fixed `Decimal::hypot_ctx` returning `+Infinity` for an infinity and a
  signaling NaN. Only a quiet NaN leaves `hypot(+-inf, y)` at `+Infinity`; a
  signaling NaN signals `invalid_operation` and the result is a quiet NaN
  (#172).
- Fixed `Decimal::rootn_ctx` returning `-0` for `rootn(-0, n)` with an even
  `n > 0`; IEEE 754-2019 9.2.1 makes it `+0` (odd `n` keeps the sign) (#164).
- Fixed `Decimal::tanpi_ctx` returning the zero with the argument's sign at
  every integer. `tanPi(n)` is `sinPi(n) / cosPi(n)`, so it is `-0` at
  positive odd `n` and `+0` at negative odd `n` (IEEE 754-2019 9.2.1), as
  `BinFloat::tanpi` has done since #81 (#163).
- Fixed `Decimal::to_bin_float` (in `decimal` and `decimal_gda`) rounding
  twice under `ToNearestEven`: the scaled quotient was first rounded to an
  integer in the target mode and then to the binary precision, so a value
  just above a binary midpoint, such as `0.0003` or `0.00001` at 53 bits,
  was rounded onto the midpoint and then the wrong way. The quotient is now
  truncated with a sticky bit (round to odd) and rounded once (#148).
- Fixed `Decimal::div_ctx` deciding `underflow`, `subnormal` and `clamped`
  for an inexact quotient from the delivered value instead of from rounding
  the quotient. A tiny quotient that rounds up to `10^e_min`, such as
  `9.999998E-96 / 0.9999999` in decimal32, lost `underflow`, and a quotient
  rounded to zero below Etiny lost `clamped`. The flags now come from the
  rounding of the guarded quotient, under either tininess rule (#140).
- Fixed `Decimal::sqrt_ctx` raising `underflow` and `subnormal` for an
  inexact root below `10^e_min` regardless of the context's tininess rule.
  Under `AfterRounding` a root whose rounding to `p` digits with an unbounded
  exponent range reaches `10^e_min` is not tiny, so `sqrt(0.9999999)` at
  precision 7, `e_min = 0` raises only `inexact` and `rounded` under `Up` and
  `Ceiling` (#141).
- Fixed `Decimal::remainder` reporting the flags of its internal integer
  quotient: an exact remainder such as `6E-6 rem -9.99999999E-15` at
  precision 9 and `e_max = 4` came back with `inexact`, `rounded` and
  `overflow`, and a spurious `clamped` appeared when `e_max - p + 1 < 0`. In a
  subset context the remainder was even taken with a quotient that had
  overflowed to infinity, so `123456789 rem 7` with `e_max = 4` returned
  infinity. The remainder now uses the exact integer quotient and reports only
  its own flags. A remainder with a zero quotient (also in `remainder_near`)
  is likewise clamped only at its result, not at the dividend's exponent
  (#144).
- Fixed `Decimal::add_ctx`, `sub_ctx` and `fma_ctx` raising `clamped` when
  one operand of the sum is zero and the other one, at its own exponent,
  would need clamping, although the delivered result does not: `fma(1E+90,
  1E+1, -0E+80)` in decimal32 now raises only `rounded`. The nonzero operand
  is moved towards the ideal exponent first and normalized once (#146).
- Fixed `Decimal::divide_integer`, `remainder` and `remainder_near`
  returning NaN with `division_impossible` for a zero dividend whose exponent
  exceeds the divisor's by at least the precision, such as `0E+10 / 3` in
  decimal32. The integer quotient of a zero dividend is zero and always fits,
  so they now return zeros with no flags (#143).
- Fixed `Decimal::plus_ctx` and `Decimal::minus_ctx` returning `+0` for
  `plus(-0)` and `minus(+0)` under `Floor` (`TowardNegative`). They are
  `0 + x` and `0 - x`, so a zero result now follows the sign rule of addition
  like `add_ctx`: `-0` under `Floor` when the zeros have opposite signs, `+0`
  otherwise (#142).
- Fixed `Decimal::power_ctx`, `Decimal::try_power_ctx` and `decimal_gda`
  `power` for an exact non-integral power whose base raised to `p` passes 1024
  digits, such as `(2^1200 * 10^-1200)^1.5 = 2^1800 * 10^-1800` at precision
  1000. The exactness test gave up on such a power, so it came back with
  `inexact` in the half modes and, after minutes of refinement, as an invalid
  NaN in the directed modes. The test now takes the `q`-th root of the base
  first and only then raises it to `p` (the root's reciprocal for a negative
  exponent), so no intermediate is longer than the result, and it covers every
  exact result of at most `precision + 1` digits — the only ones that sit on a
  rounding boundary. A longer exact value lies inside its rounding cell and is
  rounded by the enclosure. The reduced exponent `p / q` is no longer capped
  at `q <= 1000` and `p <= 4096` either: `q` is bounded by the base (a root of
  at least 2 needs `q < digits * log2(10)`) and `p` by the result, so
  `(5^1024)^(2^-10) = 5` and `0.25^4096.5 = 0.5^8193` are decided too. The
  integer root takes exact square roots for the factors of two and Newton
  steps from a leading-digit estimate, as `bin_float` does (#138).
- Fixed `Decimal::power_ctx` and `Decimal::try_power_ctx` for an exact
  non-integral power whose value is not a binary fraction. The enclosure
  decides such a power only when it is a point interval, which needs the exact
  value to be representable in binary, so `4^1.5` was returned as `8` while
  `power_ctx(0.0016, 0.25)`, `power_ctx(32, 0.2)` and `power_ctx(0.04, 1.5)`
  came back padded to the full precision with `inexact` in the half modes and
  failed certification with an invalid NaN in the directed modes. The exponent
  is now reduced to `p / q` in lowest terms before the loop — a decimal
  exponent is `c * 10^-k`, so `q` keeps only the twos and fives the
  coefficient cannot cancel — and the power is decided exactly when the base
  raised to `p` is a perfect `q`-th power, which a bisection over the root's
  digit count tests. The search is bounded by that digit count rather than by
  the context, because the enclosure cannot round an exactly representable
  value however coarse the decimal target is; a power past the bound is left
  to the enclosure as before (#53).
- Fixed the `decimal_gda` contextual and checked adapters for operations that
  need exponent bounds (`exp`, `ln`, `log10` and non-integral `power` accept
  precision, `e_max` and `-e_min` of at most 999,999). An `ArithmeticContext`
  without `e_min` or `e_max` is no longer given any default bounds: such calls
  now fail with an explicit `invalid context:` error that names the missing
  bounds, and the GDA forms keep raising `Invalid_context` (decTest
  `expx901`–`905`, `lnx901`–`905`, `logx901`–`905`, `powx4001`–`4006`, now
  covered by unit tests) (#111).
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
  (`BallFloat::from_int(100001, precision=53)` at the default 16 bits returned exactly
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
  results with extreme exponents in the IEEE and GDA decimal packages (#108).
  The literal splitter saturated the written exponent at
  $\pm 1\,500\,000\,000$, so `Decimal::from_string("1e1600000000")` returned
  `1E+1500000000` and a context with `e_max = 2e9` raised no overflow; the
  `Int` exponent sums of `*`, `mul_ctx`, `fma_ctx` and `div_ctx` wrapped, so
  `1E+1500000000 * 1E+1500000000` gave `1E-1294967296` and GDA `multiply`
  underflowed instead of overflowing, and a rounding carry at the top of the
  exponent range wrapped as well. Exponents are now read and combined in
  `Int64`: context conversions and operations overflow or underflow as the
  exponent range requires. Without a context the limits of the
  representation apply (adjusted exponent at most $2^{31}-1$, stored exponent
  at least $-2^{31}$), and, as IEEE 754 §5.12, §7.4 and §7.5 and the GDA
  to-number conversion require, a valid literal or a result beyond them is
  not rejected: `parse`/`from_string`, `+`, `-`, `*` and `/` give a signed
  infinity when it is too large and round it once, half-even, to the exponent
  $-2^{31}$ when it is too small (`"1e3000000000"` is `inf`,
  `"15e-2147483649"` is `2E-2147483648`). `internal` gains
  `split_decimal_string_wide`; `split_decimal_string` now returns `None` for
  an exponent outside `Int` instead of a saturated one. The `gda_expr`
  decTest frontend reads operand exponents beyond $\pm 2 \cdot 10^9$ as
  $\pm 2 \cdot 10^9$, the range that the decTest rule "sufficient precision
  under the directives' exponent limits" gives with the reference
  implementation's maximum precision, so rows such as
  `quantize 0 1e3000000000` and the subset `qua531` keep their expected
  results.
- Fixed `Decimal::to_integral_exact` and `to_integral_value` in `decimal` for
  operands longer than the context precision. An operand with a non-negative
  exponent was rounded to the precision (`12345` at precision 3 gave `1.23E+4`
  with `inexact`, even from `to_integral_value`), and one with a negative
  exponent was quantized at the context precision, so `12345.6` gave NaN with
  `invalid_operation`. IEEE 754-2019 §5.9 defines roundToIntegral for an
  operand in the destination format (at most p digits), where the old and new
  results agree; an operand longer than the precision is outside §5.9, so its
  result is implementation-defined. The package now chooses the GDA-style
  behaviour (General Decimal Arithmetic rounds at the operand's own
  precision): an integer longer than the precision is returned unchanged, and
  a fraction is quantized to exponent 0 at a working precision of
  max(p, its digit count) (`12345.6` at precision 3 gives `12346`) (#118).
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
- Fixed `Decimal::ln_ctx` and `log10_ctx` (and their `try_` forms) of a zero
  in the IEEE `decimal` package, which returned $-\infty$ without
  `division_by_zero`. IEEE 754-2019 §9.2.1 defines $\log(\pm 0) = -\infty$
  with divideByZero, as `log2_ctx`, `log1p_ctx(-1)` and `logb_ctx` already
  did; the flag is now raised (#94). `decimal_gda` keeps the General Decimal
  Arithmetic rule, which raises no condition.
- Fixed NaN payloads in the BID encoder of the IEEE `decimal` package. It
  wrote the payload with as many digits as the value's precision field and
  kept the leading $p-1$ of them, so a payload survived only when that field
  equalled the format precision: `Decimal::quiet_nan(payload=123)` (precision
  34) encoded to decimal64 BID with payload 0, and a decimal32 payload 256
  became $256 \cdot 10^{27}$ in decimal128. IEEE 754-2019 §3.5.2 defines the
  BID payload as the integer value of the trailing significand field (and
  §9.7 the payload as an integer), so the encoder now stores the payload
  integer, keeping its low $p-1$ digits when it is longer, as the DPD encoder
  does (#54).
- Fixed `Decimal::from_bin_float` and `Decimal::to_bin_float` in the IEEE
  `decimal` package, which mapped every zero to $+0$, so a binary $-0$ became
  $+0$ and a decimal $-0$ became a binary $+0$. IEEE 754-2019 §5.4.2 and §6.3
  make conversions keep the sign of zero; both directions now do (#55).

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
