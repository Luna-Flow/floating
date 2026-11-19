///|
// rSqrt, compound and powr (IEEE 754-2019 9.2, Table 9.1): the design note
// of issue #236 and `doc/manual/design/decimal.md`.

///|
/// The widest context the decimal math functions accept: used to convert a
/// moderate binary endpoint to an exact decimal with no range representative.
fn decimal_rcp_wide_ctx() -> DecimalContext {
  DecimalContext::new(precision=1, e_min=-999_999, e_max=999_999).unwrap()
}

///|
/// The Ziv loop of `decimal_certified_unary_result` for `f(x) = 10^shift *
/// g(scaled)`, where `scaled` is a moderate decimal: `g` is enclosed and its
/// endpoints, converted exactly, are scaled by `10^shift` (an exponent shift)
/// before the context rounds them. The acceptance test is the loop's (both
/// endpoints give one representation and one flag set), so the result is the
/// one the loop would return on `f(x)` itself, without expanding binary
/// endpoints near `10^shift`.
fn decimal_certified_scaled_result(
  scaled : Decimal,
  shift : Int32,
  ctx : DecimalContext,
  operation : String,
  evaluate : (@ball_float.BallFloat) -> Result[
    @ball_float.BallFloat,
    @def.ArithmeticError,
  ],
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  decimal_certified_scaled_loop(
    decimal_certified_work_precision(scaled, ctx),
    shift,
    ctx,
    operation,
    fn(precision) { evaluate(decimal_to_certified_ball(scaled, precision)) },
  )
}

///|
/// The loop of `decimal_certified_scaled_result` for a function of any number
/// of moderate decimal operands: `evaluate` converts them at the given working
/// precision and returns the enclosure of `g`, and `initial` is the first
/// working precision.
fn decimal_certified_scaled_loop(
  initial : Int32,
  shift : Int32,
  ctx : DecimalContext,
  operation : String,
  evaluate : (Int32) -> Result[@ball_float.BallFloat, @def.ArithmeticError],
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  let wide = decimal_rcp_wide_ctx()
  let target_ctx = decimal_math_result_ctx(ctx)
  let mut budget = CertifiedRefinementBudget::new(initial)
  while budget.available() {
    match evaluate(budget.precision()) {
      Ok(interval) => {
        let decided = if interval.is_empty() {
          None
        } else {
          match
            (
              decimal_exact_dyadic_endpoint(interval.lower_bound(), wide),
              decimal_exact_dyadic_endpoint(interval.upper_bound(), wide),
            ) {
            (Some(lower), Some(upper)) if lower.class == FpClass::Finite &&
              upper.class == FpClass::Finite => {
              let scale = fn(endpoint : Decimal) -> Decimal {
                if endpoint.coefficient.is_zero() {
                  endpoint
                } else {
                  { ..endpoint, exponent10: endpoint.exponent10 + shift, }
                }
              }
              let lower_result = decimal_apply_finite_ctx(
                scale(lower),
                target_ctx,
              )
              let upper_result = decimal_apply_finite_ctx(
                scale(upper),
                target_ctx,
              )
              if lower_result.0.compare_total(upper_result.0) == 0 &&
                lower_result.1 == upper_result.1 {
                Some(lower_result)
              } else {
                None
              }
            }
            _ => None
          }
        }
        match decided {
          Some(result) => return Ok(result)
          None => budget = budget.next()
        }
      }
      Err(error) =>
        if error.certification_failure_detail() is Some(_) {
          budget = budget.next()
        } else {
          return Err(error)
        }
    }
  }
  Err(decimal_certified_failure(operation, ctx, budget))
}

///|
/// `1 / sqrt(x)` when it is a decimal of at most `p + 1` digits. With `c` the
/// coefficient stripped of trailing zeros and `e` the stripped exponent,
/// `1 / sqrt(x)` terminates exactly when `x = 2^(2i) 5^(2j)`, i.e. `c = 2^a`
/// or `c = 5^b` with `a`, `b` and `e` even: the value is
/// `5^(a/2) 10^-((e+a)/2)` or `2^(b/2) 10^-((e+b)/2)`. A longer exact value
/// ends in a 5 or a non-zero even digit beyond the `(p+1)`-th, so it is neither
/// representable nor a midpoint, and the enclosure decides it.
fn decimal_rsqrt_exact_result(
  value : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  let target = decimal_math_target_precision(ctx).to_int64()
  let (coefficient, exponent) = remove_factor10_repr(
    value.coefficient,
    value.exponent10,
  )
  guard exponent % 2 == 0 else { return None }
  // 5^b has ~0.7 b digits and 2^(b/2) ~0.15 b; 2^a ~0.3 a and 5^(a/2) ~0.35 a.
  guard coefficient.digits10().to_int64() <= 5L * (target + 3L) else {
    return None
  }
  let (result_coefficient, result_exponent) = match
    decimal_coeff_power_of_two_exponent(coefficient) {
    Some(a) => {
      guard a % 2L == 0L else { return None }
      guard (a / 2L).to_double() * 0.69897 <= (target + 1L).to_double() else {
        return None
      }
      (
        dec_coeff_pow_unit_repr(5, (a / 2L).to_int()),
        -((exponent.to_int64() + a) / 2L),
      )
    }
    None =>
      match decimal_coeff_power_of_five_exponent(coefficient) {
        Some(b) => {
          guard b % 2L == 0L else { return None }
          guard (b / 2L).to_double() * 0.30103 <= (target + 1L).to_double() else {
            return None
          }
          (
            dec_coeff_pow_unit_repr(2, (b / 2L).to_int()),
            -((exponent.to_int64() + b) / 2L),
          )
        }
        None => return None
      }
  }
  guard result_exponent >= -2147483647L && result_exponent <= 2147483647L else {
    return None
  }
  // IEEE 754-2019 9.2.2: Q(rSqrt(x)) is -floor(Q(x)/2).
  let preferred = -decimal_floor_div64(value.exponent10.to_int64(), 2L)
  Some(
    decimal_exact_constant(
      false,
      result_coefficient,
      result_exponent.to_int(),
      preferred,
      ctx,
    ),
  )
}

///|
pub fn Decimal::try_rsqrt_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  if math_context_is_restricted(ctx) || decimal_math_operand_out_of_range(self) {
    return Ok(invalid_context_result(ctx))
  }
  let (value, operand_flags) = prepare_operand_for_context(self, ctx)
  let finish = fn(result : (Decimal, DecimalFlags)) {
    (result.0, operand_flags.combine(result.1))
  }
  if value.class == FpClass::NaN {
    return Ok(finish(quiet_nan_operand(value, ctx)))
  }
  if value.class == FpClass::Infinity {
    // 9.2.1: rSqrt(+inf) is +0 with no exception; -inf is outside the domain
    // [0, +inf] (Table 9.1: x < 0 is invalid).
    return Ok(
      finish(
        if value.negative {
          decimal_elementary_invalid(ctx)
        } else {
          decimal_elementary_zero(false, ctx)
        },
      ),
    )
  }
  if value.coefficient.is_zero() {
    // 9.2.1: rSqrt(+-0) is +-inf and signals divideByZero.
    let sign = if value.negative { Sign::Negative } else { Sign::Positive }
    return Ok(finish(decimal_elementary_division_by_zero(sign, ctx)))
  }
  if value.negative {
    return Ok(finish(decimal_elementary_invalid(ctx)))
  }
  match decimal_rsqrt_exact_result(value, ctx) {
    Some(result) => return Ok(finish(result))
    None => ()
  }
  // x = s 10^(2k) with s = x 10^(-2k) in [1, 100): 1/sqrt(x) = 10^-k / sqrt(s).
  let adjusted = adjusted_exponent64(value)
  let even = adjusted - (adjusted % 2L + 2L) % 2L
  let scaled = {
    ..value,
    exponent10: (value.exponent10.to_int64() - even).to_int(),
  }
  decimal_certified_scaled_result(
    scaled,
    (-(even / 2L)).to_int(),
    ctx,
    "rsqrt",
    fn(input) { Ok(input.sqrt_interval().reciprocal()) },
  ).map(finish)
}

///|
pub fn Decimal::rsqrt_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_rsqrt_ctx(ctx) {
    Ok(result) => result
    Err(_) => decimal_elementary_invalid(ctx)
  }
}

///|
/// The exact result 1 of `compound`, at the cohort member nearest `preferred`.
fn decimal_compound_one(
  preferred : Int64,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_exact_constant(false, dec_coeff_from_int(1), 0, preferred, ctx)
}

///|
pub fn Decimal::try_compound_ctx(
  self : Decimal,
  n : Int32,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  if math_context_is_restricted(ctx) || decimal_math_operand_out_of_range(self) {
    return Ok(invalid_context_result(ctx))
  }
  let (value, operand_flags) = prepare_operand_for_context(self, ctx)
  let finish = fn(result : (Decimal, DecimalFlags)) {
    (result.0, operand_flags.combine(result.1))
  }
  let precision = finite_precision_for_coeff(dec_coeff_zero(), ctx)
  // 9.2: a signaling NaN signals invalid; 9.2.1: "compound(x, 0) is 1 for
  // x >= -1 or quiet NaN", "compound(qNaN, n) is qNaN for n != 0".
  if value.class == FpClass::NaN {
    if value.is_signaling_nan() || n != 0 {
      return Ok(finish(quiet_nan_operand(value, ctx)))
    }
    return Ok(finish(decimal_compound_one(0L, ctx)))
  }
  // Table 9.1: the domain is [-1, +inf] x Z; "compound(x, n) is qNaN and
  // signals the invalid operation exception for x < -1" (n = 0 included).
  if value.negative &&
    (
      value.class == FpClass::Infinity ||
      value.compare(Decimal::from_int(-1, precision=1)) < 0
    ) {
    return Ok(finish(decimal_elementary_invalid(ctx)))
  }
  // Q(compound(x, n)) is floor(n * min(0, Q(x))) (9.2.2); Q(+inf) = +inf.
  let quantum = if value.class == FpClass::Finite {
    Int64::min(0L, value.exponent10.to_int64())
  } else {
    0L
  }
  let preferred = n.to_int64() * quantum
  if n == 0 {
    return Ok(finish(decimal_compound_one(0L, ctx)))
  }
  if value.class == FpClass::Infinity {
    // "compound(+inf, n) is +inf for n > 0", "+0 for n < 0".
    return Ok(
      finish(
        if n > 0 {
          (Decimal::inf(Sign::Positive, precision~), DecimalFlags::new())
        } else {
          decimal_elementary_zero(false, ctx)
        },
      ),
    )
  }
  if value.coefficient.is_zero() {
    // "compound(+-0, n) is 1".
    return Ok(finish(decimal_compound_one(preferred, ctx)))
  }
  if value.compare(Decimal::from_int(-1, precision=1)) == 0 {
    // "compound(-1, n) is +inf and signals the divideByZero exception for
    // n < 0", "compound(-1, n) is +0 for n > 0".
    return Ok(
      finish(
        if n < 0 {
          decimal_elementary_division_by_zero(Sign::Positive, ctx)
        } else {
          decimal_elementary_zero(false, ctx)
        },
      ),
    )
  }
  // Tiny x: (1 + x)^n - 1 has the sign of n x and |(1 + x)^n - 1| <=
  // |n x| e^|n x| < 10^(adjusted(x) + 12) for |n| <= 2^31, so the result is a
  // one-sided neighbour of the anchor 1 when that bound is far below its ulp;
  // 1 + x (up to two million digits) is never formed.
  let one = Decimal::one(precision~)
  let error_exponent = adjusted_exponent64(value) + 12L
  if error_exponent < -(decimal_math_target_precision(ctx).to_int64() + 3L) {
    match
      decimal_tiny_argument_result(
        one,
        (n > 0) == !value.negative,
        error_exponent,
        ctx,
      ) {
      Some(result) => return Ok(finish(result))
      None => ()
    }
  }
  // Otherwise the exact power when it is short enough to sit on a rounding
  // boundary, else the certified exp(n log1p(x)).
  match decimal_compound_exact_result(value, n, preferred, ctx) {
    Some(result) => return Ok(finish(result))
    None => ()
  }
  decimal_compound_certified(value, n, ctx).map(finish)
}

///|
/// (1 + x)^n when it may sit on a rounding boundary, formed exactly and
/// rounded once with the preferred exponent floor(n min(0, Q(x))) (9.2.2).
/// With s = 1 + x = c 10^e (c without trailing zeros, d digits):
/// n > 0: c^n has at least max((d - 1) n, 0.301 n) + 1 digits and no
/// trailing zero (c is not divisible by both 2 and 5), so beyond p + 1 digits
/// it is neither representable nor a midpoint; it is formed below that.
/// n < 0: c^-|n| terminates only for c = 2^a (value 5^(a|n|) 10^(-(a+e)|n|))
/// or c = 5^b (value 2^(b|n|) 10^(-(b+e)|n|)), formed while that power has
/// at most p + 2 digits; a longer terminating value is no boundary either,
/// and a non-terminating one never is. c = 1 gives 10^(e n). Everything else
/// is left to the enclosure, which then always terminates.
fn decimal_compound_exact_result(
  value : Decimal,
  n : Int32,
  preferred : Int64,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  let target = decimal_math_target_precision(ctx).to_int64()
  let sum = value.add_ctx(Decimal::one(precision=1), DecimalContext::exact()).0
  let (coefficient, exponent) = remove_factor10_repr(
    sum.coefficient,
    sum.exponent10,
  )
  let count = n.to_int64() // |n| <= 2^31 as Int64
  let magnitude = count.abs()
  let digits = coefficient.digits10().to_int64()
  let in_int32 = fn(v : Int64) { v >= -2147483647L && v <= 2147483647L }
  if dec_coeff_compare_repr(coefficient, dec_coeff_from_int(1)) == 0 {
    let power = exponent.to_int64() * count
    guard in_int32(power) else { return None }
    return Some(
      decimal_exact_constant(
        false,
        dec_coeff_from_int(1),
        power.to_int(),
        preferred,
        ctx,
      ),
    )
  }
  if count > 0 {
    // c >= 2, so c^n has more than max((d - 1) n, 0.301 n) digits.
    guard (digits - 1L) * magnitude <= target + 1L &&
      magnitude * 301L / 1000L <= target + 1L else {
      return None
    }
    let power = exponent.to_int64() * count
    guard in_int32(power) else { return None }
    return Some(
      decimal_exact_constant(
        false,
        dec_coeff_exact_power_repr(coefficient, n),
        power.to_int(),
        preferred,
        ctx,
      ),
    )
  }
  // n < 0.
  // 2^a with d digits has a >= 3.32 (d - 1), so 5^(a|n|) has more than
  // 2.3 (d - 1)|n| digits; 5^b has b >= 1.43 (d - 1) and 2^(b|n|) more than
  // 0.43 (d - 1)|n|: a long c is never formed.
  guard (digits - 1L) * magnitude <= 3L * (target + 2L) else { return None }
  let (unit, factor_exponent, scale) = match
    decimal_coeff_power_of_two_exponent(coefficient) {
    Some(a) => (5, a, 0.69897)
    None =>
      match decimal_coeff_power_of_five_exponent(coefficient) {
        Some(b) => (2, b, 0.30103)
        None => return None
      }
  }
  let power_count = factor_exponent * magnitude
  guard power_count.to_double() * scale <= (target + 2L).to_double() else {
    return None
  }
  let power_exponent = -(factor_exponent + exponent.to_int64()) * magnitude
  guard in_int32(power_exponent) && in_int32(power_count) else { return None }
  Some(
    decimal_exact_constant(
      false,
      dec_coeff_pow_unit_repr(unit, power_count.to_int()),
      power_exponent.to_int(),
      preferred,
      ctx,
    ),
  )
}

///|
/// `(1 + x)^n = exp(n log1p(x))` by the Ziv loop, after the range decision of
/// `decimal_range_from_log2_bracket` on `n log1p(x) / ln 2` (128-bit
/// certified bounds). `log1p` is evaluated on x itself, so 1 + x is never
/// rounded; the width of the enclosure grows by the factor |n log1p(x)|,
/// which the Ziv schedule absorbs. `n` is taken exactly as an Int32
/// (Int32.min_value included).
fn decimal_compound_certified(
  value : Decimal,
  n : Int32,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  // |log10(1 + x)| <= B with B = max(adj(x), 0) + 2 for x >= 0 and, for
  // -1 < x < 0 (1 + x >= 10^Q(x)), B = max(1, -Q(x)); a result inside
  // [10^-(|n| B), 10^(|n| B)] cannot be decided by the bracket (which only
  // decides beyond 10^(e_max + 2) or below 10^(etiny - 2)), so the bracket is
  // skipped there: the results are unchanged, the 128-bit log1p is saved.
  let bound = if value.negative {
    Int64::max(1L, -Int64::min(value.exponent10.to_int64(), 0L))
  } else {
    Int64::max(adjusted_exponent64(value), 0L) + 2L
  }
  let reach = n.to_int64().abs() * bound
  let in_range = reach <= ctx.e_max.to_int64() + 1L &&
    reach <= -(etiny(ctx).to_int64() - 2L) - 1L
  let bracket_precision = 128
  if !in_range {
    match
      (
        @ball_float.BallFloat::from_int(2, precision=bracket_precision).try_ln_interval(),
        decimal_to_certified_ball(value, bracket_precision).try_log1p_interval(),
      ) {
      (Ok(ln2), Ok(log)) => {
        let log2 = log
          .div(ln2)
          .mul(@ball_float.BallFloat::from_int(n, precision=bracket_precision))
        if !log2.is_empty() {
          match
            decimal_range_from_log2_bracket(
              log2.lower_bound(),
              log2.upper_bound(),
              ctx,
            ) {
            Some(result) => return Ok(result)
            None => ()
          }
        }
      }
      _ => ()
    }
  }
  decimal_certified_unary_result(value, ctx, "compound", fn(input) {
    let precision = input.precision()
    match input.try_log1p_interval() {
      Ok(log) =>
        log
        .mul(@ball_float.BallFloat::from_int(n, precision~))
        .try_exp_interval()
      Err(error) => Err(error)
    }
  })
}

///|
pub fn Decimal::compound_ctx(
  self : Decimal,
  n : Int32,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_compound_ctx(n, ctx) {
    Ok(result) => result
    Err(_) => decimal_elementary_invalid(ctx)
  }
}

///|
pub fn Decimal::try_powr_ctx(
  self : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  if gda_context_is_restricted(ctx) {
    return Ok(invalid_context_result(ctx))
  }
  let (x, y, operand_flags) = prepare_binary_operands_for_context(
    self, exponent, ctx,
  )
  let finish = fn(result : (Decimal, DecimalFlags)) {
    (result.0, operand_flags.combine(result.1))
  }
  // 9.2: a signaling NaN operand signals invalid and gives a quiet NaN.
  if x.is_signaling_nan() || y.is_signaling_nan() {
    match quiet_nan_pair(x, y, ctx) {
      Some(result) => return Ok(finish(result))
      None => ()
    }
  }
  let x_zero = x.class == FpClass::Finite && x.coefficient.is_zero()
  let y_zero = y.class == FpClass::Finite && y.coefficient.is_zero()
  // 9.2.1: "powr(x, y) signals the invalid operation exception for x < 0"
  // (-0 is not below 0). Before the NaN rule: "powr(x, qNaN) is qNaN for
  // x >= 0" leaves x < 0 to the invalid rule [ambiguous, #236 design note].
  if x.class != FpClass::NaN && x.negative && !x_zero {
    return Ok(finish(decimal_elementary_invalid(ctx)))
  }
  // "powr(x, qNaN) is qNaN for x >= 0", "powr(qNaN, y) is qNaN" (also for
  // y = +-0, unlike pow).
  match quiet_nan_pair(x, y, ctx) {
    Some(result) => return Ok(finish(result))
    None => ()
  }
  // "powr(+-0, +-0)", "powr(+inf, +-0)" and "powr(+1, +-inf)" signal the
  // invalid operation exception.
  let x_one = x.class == FpClass::Finite && is_finite_decimal_one(x)
  if (x_zero && y_zero) ||
    (x.class == FpClass::Infinity && y_zero) ||
    (x_one && y.class == FpClass::Infinity) {
    return Ok(finish(decimal_elementary_invalid(ctx)))
  }
  // Every remaining pair has x >= 0, and powr agrees with pow there: the
  // listed rows (x^+-0 = 1 for finite x > 0, +-0^y = +inf with divideByZero
  // for finite y < 0, +-0^-inf = +inf, +-0^y = +0 for y > 0, +1^y = 1 for
  // finite y) are pow's rows for +0 and x > 0, and the unlisted ones (+inf^y
  // for y != 0, x^+-inf for x not in {0, 1}) follow exp(y log x) as pow's
  // [ambiguous, #236 design note]; Q(powr) = Q(pow) = floor(y Q(x))
  // (9.2.2). -0 is passed as +0, where pow would apply its odd-integer sign
  // rule.
  let base = if x_zero { { ..x, negative: false, } } else { x }
  base.try_power_ctx(y, ctx).map(finish)
}

///|
pub fn Decimal::powr_ctx(
  self : Decimal,
  exponent : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_powr_ctx(exponent, ctx) {
    Ok(result) => result
    Err(_) => decimal_elementary_invalid(ctx)
  }
}
