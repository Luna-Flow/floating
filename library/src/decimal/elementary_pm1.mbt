///|
// exp2m1, exp10m1, log2p1 and log10p1 (IEEE 754-2019 9.2, Table 9.1): the
// design note of issue #236 and `doc/manual/design/decimal.md`.

///|
#derive(Eq)
priv enum DecimalPm1 {
  Exp2m1
  Exp10m1
  Log2p1
  Log10p1
}

///|
fn DecimalPm1::name(self : DecimalPm1) -> String {
  match self {
    Exp2m1 => "exp2m1"
    Exp10m1 => "exp10m1"
    Log2p1 => "log2p1"
    Log10p1 => "log10p1"
  }
}

///|
fn DecimalPm1::base(self : DecimalPm1) -> Int32 {
  match self {
    Exp2m1 | Log2p1 => 2
    Exp10m1 | Log10p1 => 10
  }
}

///|
fn DecimalPm1::is_exp(self : DecimalPm1) -> Bool {
  self == Exp2m1 || self == Exp10m1
}

///|
/// Certified `ln 2` and `ln 10` intervals by working precision. The interval
/// of a precision is a pure function of it, so a cached one is the interval
/// the evaluation would compute again (the results do not change, only the
/// cost of every Ziv step and every call).
let decimal_pm1_ln_cache : Map[Int64, @ball_float.BallFloat] = Map([])

///|
fn decimal_pm1_ln_base(
  base : Int32,
  precision : Int32,
) -> Result[@ball_float.BallFloat, @def.ArithmeticError] {
  let key = precision.to_int64() * 16L + base.to_int64()
  match decimal_pm1_ln_cache.get(key) {
    Some(value) => return Ok(value)
    None => ()
  }
  match @ball_float.BallFloat::from_int(base, precision~).try_ln_interval() {
    Ok(value) => {
      // The Ziv schedule visits a few precisions per target precision; keep
      // the table small for long-running programs with many precisions.
      if decimal_pm1_ln_cache.length() >= 64 {
        decimal_pm1_ln_cache.clear()
      }
      decimal_pm1_ln_cache.set(key, value)
      Ok(value)
    }
    Err(error) => Err(error)
  }
}

///|
/// The certified enclosure: `expm1(x ln b)` or `log1p(x) / ln b`. Both
/// primitives are series in `x`, so the relative width stays that of the
/// working precision near zero (no cancellation).
fn DecimalPm1::evaluate(
  self : DecimalPm1,
  input : @ball_float.BallFloat,
) -> Result[@ball_float.BallFloat, @def.ArithmeticError] {
  let precision = input.precision()
  match decimal_pm1_ln_base(self.base(), precision) {
    Err(error) => Err(error)
    Ok(ln_base) =>
      if self.is_exp() {
        input.mul(ln_base).try_expm1_interval()
      } else {
        input.try_log1p_interval().map(fn(value) { value.div(ln_base) })
      }
  }
}

///|
/// A non-negative integer as an exact `Decimal` with exponent 0.
fn decimal_pm1_integer(magnitude : Int64) -> Decimal {
  let coefficient = coeff_from_bigint(BigInt::from_int64(magnitude))
  finite_with_exponent_repr(
    false,
    coefficient,
    0,
    Int32::max(1, coefficient.digits10()),
  )
}

///|
/// A result certainly below `10^(etiny - 2)`, decided without converting the
/// operand to binary (that conversion of `10^-1999996` costs seconds). For
/// `|x| <= 10^-5` all four functions satisfy `0 < |f(x)| < 3 |x|` with the
/// sign of `x` (`|b^x - 1| <= |x| ln 10 * 10^|x|`,
/// `|log_b(1 + x)| <= |x| / (ln 2 (1 - |x|))`), so `|x| < 10^(etiny - 3)`
/// puts `f(x)` in `(0, 10^(etiny - 2))`, below half the smallest subnormal.
/// Every such value rounds like the representative `10^(etiny - 2)` of the
/// same sign in every mode, with the same flags under both tininess rules
/// (the representative `decimal_out_of_range_endpoint` uses for an enclosure
/// endpoint): the result is that rounding, never a constant zero.
fn decimal_pm1_below_subnormal_range(
  value : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  let top = adjusted_exponent64(value) + 1L // |x| < 10^top
  let tiny = etiny(ctx).to_int64() - 2L
  guard top <= -5L && top + 1L <= tiny else { return None }
  Some(
    decimal_apply_finite_ctx(
      finite_with_exponent(
        value.negative,
        BigInt::from_int(1),
        tiny.to_int(),
        1,
      ),
      decimal_math_result_ctx(ctx),
    ),
  )
}

///|
/// The certified constant `ln b` (exp2m1, exp10m1) or `1 / ln b` (log2p1,
/// log10p1) at `precision` bits: the slope of `f` at 0.
fn DecimalPm1::slope(
  self : DecimalPm1,
  precision : Int32,
) -> Result[@ball_float.BallFloat, @def.ArithmeticError] {
  match decimal_pm1_ln_base(self.base(), precision) {
    Err(error) => Err(error)
    Ok(ln_base) =>
      if self.is_exp() {
        Ok(ln_base)
      } else {
        Ok(@ball_float.BallFloat::from_int(1, precision~).div(ln_base))
      }
  }
}

///|
/// A tiny argument, `|x| < 10^-(p + 11)`, decided on its coefficient. With
/// `x = m 10^q` and `c` the slope (`ln b` or `1 / ln b`), `f(x) = c x (1 + d)`
/// with `|d| <= 2.31 |x|` for all four functions (the series of `expm1` and
/// `log1p`), so `f(x) / 10^q` lies in `c m [1 - 2^k, 1 + 2^k]` for any
/// `2^k >= 4 |x|`. That enclosure has endpoints of a few dozen digits, while
/// the binary endpoints of `f(x)` itself would be expanded to an exact decimal
/// with about `0.7 |q|` digits (the cost of a tiny argument in a wide context).
/// Its endpoints, scaled back by `10^q`, are rounded with the context; the
/// result is accepted only when both round to one representation with one
/// flag set, which then is the correctly rounded `f(x)` with its flags (the
/// argument of `decimal_certified_unary_result`; `f(x)` is irrational).
/// Otherwise `None`, and the Ziv loop decides: the results are those of the
/// loop, only cheaper.
fn decimal_pm1_tiny_scaled(
  value : Decimal,
  operation : DecimalPm1,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard ctx.precision > 0 else { return None }
  let adjusted = adjusted_exponent64(value)
  guard adjusted <= -(ctx.precision.to_int64() + 12L) else { return None }
  let work = decimal_certified_work_precision(value, ctx)
  // |x| < 10^(adjusted + 1) <= 2^t with t = ceil(3.3 (adjusted + 1)), as
  // 3.3 < log2 10 and adjusted + 1 < 0; 2^(t + 2) >= 4 |x|, capped at the
  // working precision (a larger bound is still a bound).
  let t = 33L * (adjusted + 1L) / 10L
  let k = Int64::max(t + 2L, -(work.to_int64() + 8L)).to_int()
  let exact = @bin_float.BinaryContext::unbounded(
    -k + 4,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let one = @bin_float.BinFloat::from_int(1, precision=2)
  let bound = one.scaleb_ctx(k, exact).0
  let factor = @ball_float.BallFloat::from_bounds(
    one.sub_ctx(bound, exact).0,
    one.add_ctx(bound, exact).0,
    precision=work,
  )
  let coefficient = finite_with_exponent_repr(
    value.negative,
    value.coefficient,
    0,
    Int32::max(1, value.coefficient.digits10()),
  )
  let slope = match operation.slope(work) {
    Ok(slope) => slope
    Err(_) => return None
  }
  let scaled = decimal_to_certified_ball(coefficient, work)
    .mul(slope)
    .mul(factor)
  guard !scaled.is_empty() && !scaled.contains_zero() else { return None }
  // The scaled endpoints are moderate: convert them in the widest math
  // context, so that no range representative replaces them.
  let wide = DecimalContext::new(precision=1, e_min=-999_999, e_max=999_999)
  let (lower, upper) = decimal_certified_endpoints(scaled, wide)
  guard lower is Some(lower) &&
    upper is Some(upper) &&
    lower.class == FpClass::Finite &&
    upper.class == FpClass::Finite else {
    return None
  }
  let shift = fn(endpoint : Decimal) -> Decimal {
    { ..endpoint, exponent10: endpoint.exponent10 + value.exponent10, }
  }
  let target_ctx = decimal_math_result_ctx(ctx)
  let lower_result = decimal_apply_finite_ctx(shift(lower), target_ctx)
  let upper_result = decimal_apply_finite_ctx(shift(upper), target_ctx)
  if lower_result.0.compare_total(upper_result.0) == 0 &&
    lower_result.1 == upper_result.1 {
    Some(lower_result)
  } else {
    None
  }
}

///|
/// Certain overflow of `b^x - 1`. For `x >= 3.322 (e_max + 2)` (base 2) or
/// `x >= e_max + 2` (base 10), `b^x - 1 >= 10^(e_max + 2) - 1`, above the
/// largest finite number in every rounding mode, so the result is the overflow
/// result of the context. Below the guard the enclosure decides.
fn decimal_exp_m1_coarse_overflow(
  value : Decimal,
  operation : DecimalPm1,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard !value.negative && ctx.e_max >= 0 else { return None }
  let limit = ctx.e_max.to_int64() + 2L
  let guard_value = match operation {
    Exp2m1 => (limit * 3322L + 999L) / 1000L
    _ => limit
  }
  if value.compare(decimal_pm1_integer(guard_value)) >= 0 {
    Some(decimal_overflow_result(false, ctx))
  } else {
    None
  }
}

///|
/// `b^n - 1` for an integer `n` with `0 < |n| <= 4 (p + 2)`, exact and rounded
/// once: `2^n - 1` and `10^n - 1` for `n > 0`, `-(10^m - 5^m) 10^-m` and
/// `-(10^m - 1) 10^-m` for `n = -m < 0`. The preferred exponent is 0 (9.2.2).
fn decimal_exp_m1_integer(
  n : Int32,
  operation : DecimalPm1,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  if n > 0 {
    let power = if operation == Exp2m1 {
      dec_coeff_pow_unit_repr(2, n)
    } else {
      dec_coeff_power10_repr(n)
    }
    decimal_exact_constant(
      false,
      dec_coeff_magnitude_sub_unit(power, 1),
      0,
      0L,
      ctx,
    )
  } else {
    let m = -n
    let ten = dec_coeff_power10_repr(m)
    let coefficient = if operation == Exp2m1 {
      dec_coeff_magnitude_sub_repr(ten, dec_coeff_pow_unit_repr(5, m))
    } else {
      dec_coeff_magnitude_sub_unit(ten, 1)
    }
    decimal_exact_constant(true, coefficient, -m, 0L, ctx)
  }
}

///|
fn decimal_exp_m1_finite(
  value : Decimal,
  operation : DecimalPm1,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  match decimal_exp_m1_coarse_overflow(value, operation, ctx) {
    Some(result) => return Ok(result)
    None => ()
  }
  let target = decimal_math_target_precision(ctx)
  // 4 (p + 2) <= 4 * 1_000_001 fits an Int.
  let bound = 4 * (target + 2)
  // Exact cases: b^x is rational only for an integer x (2^r and 10^r are
  // irrational for a non-integer rational r).
  match decimal_power_integer_count(value, bound) {
    Some(n) => return Ok(decimal_exp_m1_integer(n, operation, ctx))
    None => ()
  }
  let integral = decimal_power_integer_is_odd(value) is Some(_)
  if integral && !value.negative {
    // n > 4 (p + 2): b^n has D >= p + 3 digits.
    match operation {
      Exp2m1 =>
        // Every rounding boundary of a D-digit integer is a multiple of
        // M = 5 * 10^(D - p - 1), which is even, and 2^n is not one (no
        // factor 5); the only integer in [2^n - 1, 2^n) is the odd 2^n - 1. So
        // 2^n - 1 and 2^n lie in one open rounding cell and round alike in
        // every mode, with the same flags: the result is exp2(n).
        return Decimal::from_int(2, precision=target).try_power_ctx(value, ctx)
      _ => {
        // 10^n - 1 (n nines) and 10^n - 10^(n - p - 2) (p + 2 nines) both lie
        // strictly between the midpoint 10^n - 5 * 10^(n - p - 1) and 10^n:
        // same rounded result and flags; 10^n itself is never formed.
        let n = match decimal_power_machine_integer_count(value) {
          Some(n) => n
          None => return Ok(decimal_overflow_result(false, ctx))
        }
        let coefficient = dec_coeff_magnitude_sub_unit(
          dec_coeff_power10_repr(target + 2),
          1,
        )
        return Ok(
          decimal_apply_finite_ctx(
            finite_with_exponent_repr(
              false,
              coefficient,
              n - target - 2,
              target + 2,
            ),
            decimal_math_result_ctx(ctx),
          ),
        )
      }
    }
  }
  // Saturation towards -1: for x <= -(p + 2) (base 10) or x <= -(4p + 8)
  // (base 2, 16^-(p + 2) < 10^-(p + 2)), b^x - 1 = -1 + d with
  // 0 < d <= 10^-(p + 2), in the same rounding cell as the representative
  // -(1 - 10^-(p + 2)) in every mode (as `expm1`).
  if ctx.precision > 0 && value.negative {
    let p = ctx.precision
    let threshold = if operation == Exp2m1 { 4 * p + 8 } else { p + 2 }
    if value.compare({
        ..decimal_pm1_integer(threshold.to_int64()),
        negative: true,
      }) <=
      0 {
      let scale = p + 2
      let coefficient = dec_coeff_magnitude_sub_unit(
        dec_coeff_power10_repr(scale),
        1,
      )
      return Ok(
        normalize_decimal_parts_math_ctx_repr(true, coefficient, -scale, ctx),
      )
    }
  }
  decimal_certified_unary_result(value, ctx, operation.name(), fn(input) {
    operation.evaluate(input)
  })
}

///|
/// The integer `k` with `1 + x = b^k`, the only exact cases of
/// `log_b(1 + x)` (`log_b q` rational forces `q` to be an integer power of
/// `b`). Decided on `x` without forming `1 + x`:
/// x >= 1 must be the integer `b^k - 1` (odd for b = 2, nines for b = 10, so
/// its stripped exponent is 0); -1 < x < 0 must be `-(1 - b^-m)` with `m` the
/// number of fractional digits: coefficient `10^m - 5^m` (b = 2) or
/// `10^m - 1` (b = 10).
fn decimal_log_p1_exact_exponent(value : Decimal, base : Int32) -> Int64? {
  guard value.class == FpClass::Finite && !value.coefficient.is_zero() else {
    return None
  }
  let (coefficient, exponent) = remove_factor10_repr(
    value.coefficient,
    value.exponent10,
  )
  if !value.negative {
    guard exponent == 0 else { return None }
    let successor = dec_coeff_magnitude_add_unit(coefficient, 1)
    if base == 10 {
      if is_power_of_ten_coeff(successor) {
        Some(coefficient.digits10().to_int64())
      } else {
        None
      }
    } else {
      decimal_coeff_power_of_two_exponent(successor)
    }
  } else {
    guard exponent < 0 else { return None }
    let m = -exponent
    guard coefficient.digits10() == m else { return None }
    let exact = if base == 10 {
      is_power_of_ten_coeff(dec_coeff_magnitude_add_unit(coefficient, 1))
    } else {
      decimal_coeff_is_ten_minus_five_power(coefficient, m)
    }
    if exact {
      Some(-m.to_int64())
    } else {
      None
    }
  }
}

///|
fn decimal_log_p1_finite(
  value : Decimal,
  operation : DecimalPm1,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  let order = value.compare(Decimal::from_int(-1, precision=1))
  // Table 9.1: x < -1 is outside the domain [-1, +inf] (invalid operation);
  // 9.2.1: f(-1) is -inf and signals divideByZero.
  if order < 0 {
    return Ok(decimal_elementary_invalid(ctx))
  }
  if order == 0 {
    return Ok(decimal_elementary_division_by_zero(Sign::Negative, ctx))
  }
  match decimal_log_p1_exact_exponent(value, operation.base()) {
    Some(k) => {
      let magnitude = coeff_from_bigint(BigInt::from_int64(k.abs()))
      return Ok(decimal_exact_constant(k < 0L, magnitude, 0, 0L, ctx))
    }
    None => ()
  }
  decimal_certified_unary_result(value, ctx, operation.name(), fn(input) {
    operation.evaluate(input)
  })
}

///|
fn Decimal::try_pm1_ctx(
  self : Decimal,
  operation : DecimalPm1,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  if math_context_is_restricted(ctx) || decimal_math_operand_out_of_range(self) {
    return Ok(invalid_context_result(ctx))
  }
  let (value, operand_flags) = prepare_operand_for_context(self, ctx)
  let finish = fn(result : (Decimal, DecimalFlags)) {
    (result.0, operand_flags.combine(result.1))
  }
  // 9.2: a signaling NaN signals invalid and gives a quiet NaN; a quiet NaN
  // propagates (payload and sign kept) with no exception.
  if value.class == FpClass::NaN {
    return Ok(finish(quiet_nan_operand(value, ctx)))
  }
  let precision = finite_precision_for_coeff(dec_coeff_zero(), ctx)
  if value.class == FpClass::Infinity {
    // 9.2.1: exp2m1 and exp10m1 of +inf are +inf and of -inf are -1, log2p1
    // and log10p1 of +inf are +inf, all with no exception; -inf is outside
    // the domain [-1, +inf] of log2p1 and log10p1.
    let result = if !value.negative {
      (Decimal::inf(Sign::Positive, precision~), DecimalFlags::new())
    } else if operation.is_exp() {
      (Decimal::from_int(-1, precision~), DecimalFlags::new())
    } else {
      decimal_elementary_invalid(ctx)
    }
    return Ok(finish(result))
  }
  // 9.2.1: f(+0) is +0 and f(-0) is -0 with no exception.
  if value.coefficient.is_zero() {
    return Ok(finish(decimal_elementary_zero(value.negative, ctx)))
  }
  match decimal_pm1_below_subnormal_range(value, ctx) {
    Some(result) => return Ok(finish(result))
    None => ()
  }
  match decimal_pm1_tiny_scaled(value, operation, ctx) {
    Some(result) => return Ok(finish(result))
    None => ()
  }
  let result = if operation.is_exp() {
    decimal_exp_m1_finite(value, operation, ctx)
  } else {
    decimal_log_p1_finite(value, operation, ctx)
  }
  result.map(finish)
}

///|
fn Decimal::pm1_ctx(
  self : Decimal,
  operation : DecimalPm1,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_pm1_ctx(operation, ctx) {
    Ok(result) => result
    Err(_) => decimal_elementary_invalid(ctx)
  }
}

///|
/// `2^x - 1`, correctly rounded in `ctx` (IEEE 754-2019 9.2 exp2m1). Exact
/// only for integer `x`; the preferred exponent of an exact result is 0.
/// `try_exp2m1_ctx` reports a certification failure instead of returning NaN.
pub fn Decimal::try_exp2m1_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_pm1_ctx(Exp2m1, ctx)
}

///|
/// `2^x - 1`, correctly rounded in `ctx` (IEEE 754-2019 9.2 exp2m1).
pub fn Decimal::exp2m1_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.pm1_ctx(Exp2m1, ctx)
}

///|
/// `10^x - 1`, correctly rounded in `ctx` (IEEE 754-2019 9.2 exp10m1).
pub fn Decimal::try_exp10m1_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_pm1_ctx(Exp10m1, ctx)
}

///|
/// `10^x - 1`, correctly rounded in `ctx` (IEEE 754-2019 9.2 exp10m1).
pub fn Decimal::exp10m1_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.pm1_ctx(Exp10m1, ctx)
}

///|
/// `log2(1 + x)`, correctly rounded in `ctx` (IEEE 754-2019 9.2 log2p1).
pub fn Decimal::try_log2p1_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_pm1_ctx(Log2p1, ctx)
}

///|
/// `log2(1 + x)`, correctly rounded in `ctx` (IEEE 754-2019 9.2 log2p1).
pub fn Decimal::log2p1_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.pm1_ctx(Log2p1, ctx)
}

///|
/// `log10(1 + x)`, correctly rounded in `ctx` (IEEE 754-2019 9.2 log10p1).
pub fn Decimal::try_log10p1_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_pm1_ctx(Log10p1, ctx)
}

///|
/// `log10(1 + x)`, correctly rounded in `ctx` (IEEE 754-2019 9.2 log10p1).
pub fn Decimal::log10p1_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.pm1_ctx(Log10p1, ctx)
}
