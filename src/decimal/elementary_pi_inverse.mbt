///|
// asinPi, acosPi, atanPi and atan2Pi (IEEE 754-2019 9.2, Table 9.1): the
// inverse circular functions measured in half-revolutions, asin(x)/pi,
// acos(x)/pi, atan(x)/pi and atan2(y, x)/pi. The design note is on issue #236
// and in `doc/manual/design/decimal.md`.
//
// 9.2.1: "For the operations sin, tan, sinPi, tanPi, asin, atan, asinPi, atanPi,
// ... f(+0) is +0 and f(-0) is -0 with no exception." "acos(1), acosPi(1), and
// acosh(1) are +0." "atanPi(+-inf) is +-1/2 with no exception." The 11 special
// rows of atan2Pi(y, x) are exact constants that signal no exception.
//
// By Niven's theorem the only exact (dyadic) results are those constants and
// atanPi(+-1) = +-1/4, atan2Pi(+-a, +-a) = +-1/4 or +-3/4. asinPi(+-1/2) =
// +-1/6 and acosPi(+-1/2) = 1/3, 2/3 are not terminating decimals, so they sit
// strictly inside a rounding cell and the enclosure decides them.

///|
/// Certified `pi` intervals by working precision. The interval of a precision
/// is a pure function of it, so a cached one is the interval the evaluation
/// would compute again (the results do not change, only the cost of every Ziv
/// step and every call).
let decimal_pi_cache : Map[Int32, @ball_float.BallFloat] = Map([])

///|
/// The tightest `precision`-bit enclosure `[RD(pi), RU(pi)]`, taken from the
/// cached binary-splitting constant: `atan(+inf) = pi/2` is served from that
/// cache by `bin_float`, and the scaling by 2 is exact (unbounded exponent
/// range), so `[2 RD(pi/2), 2 RU(pi/2)] = [RD(pi), RU(pi)]`. This is the same
/// interval, bit for bit, as `4 [RD(atan 1), RU(atan 1)]` (scaling by powers of
/// two commutes with directed rounding).
fn decimal_pi_enclosure(
  precision : Int32,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  let infinity = @bin_float.BinFloat::inf(Sign::Positive, precision~)
  let exact = @bin_float.BinaryContext::unbounded(precision)
  let two = @bin_float.BinFloat::from_int(2, precision=2)
  let bound = fn(rounding) {
    let context = @bin_float.BinaryContext::unbounded(precision, rounding~)
    match infinity.try_atan_ctx(context) {
      Ok(result) => result.0.mul_ctx(two, exact).0
      Err(error) => abort(error.message)
    }
  }
  (
    bound(@bin_float.BinaryRoundingMode::RoundTowardNegative),
    bound(@bin_float.BinaryRoundingMode::RoundTowardPositive),
  )
}

///|
/// `pi` enclosed at `precision` bits.
fn decimal_pi_ball(precision : Int32) -> @ball_float.BallFloat {
  match decimal_pi_cache.get(precision) {
    Some(value) => return value
    None => ()
  }
  let bounds = decimal_pi_enclosure(precision)
  let value = @ball_float.BallFloat::from_bounds(bounds.0, bounds.1, precision~)
  // The Ziv schedule visits a few precisions per target precision; keep the
  // table small for long-running programs with many precisions.
  if decimal_pi_cache.length() >= 64 {
    decimal_pi_cache.clear()
  }
  decimal_pi_cache.set(precision, value)
  value
}

///|
/// The signed exact constant `numerator * 10^exponent10`, rounded once by the
/// context, at the preferred exponent 0 (9.2.2).
fn decimal_pi_constant(
  negative : Bool,
  numerator : Int32,
  exponent10 : Int32,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_exact_constant(
    negative,
    dec_coeff_from_int(numerator),
    exponent10,
    0L,
    ctx,
  )
}

///|
/// The signed anchor `numerator * 10^exponent10` of a one-sided cluster.
fn decimal_pi_anchor(
  negative : Bool,
  numerator : Int32,
  exponent10 : Int32,
) -> Decimal {
  finite_with_exponent_repr(
    negative,
    dec_coeff_from_int(numerator),
    exponent10,
    1,
  )
}

///|
/// Whether `x`, with `t` decimal digits of smallness (`x^2 < 10^-t`), is small
/// enough for the scaled evaluation: the relative error `x^2` of `asin(x) ~ x`
/// and `atan(x) ~ x` must be far below the working precisions of the loop.
fn decimal_pi_tiny_enough(
  t : Int64,
  digits : Int32,
  ctx : DecimalContext,
) -> Bool {
  let need = 8L *
    Int32::max(digits, decimal_math_target_precision(ctx)).to_int64() +
    400L
  t * 3L >= need
}

///|
/// The factor `1 + e` (`above`) or `1 - e` with `0 <= e <= 10^-t`, as
/// `e <= 2^-k` for `k = min(floor(3.32 t), precision + 64)`: the ratio `asin(x) / x` lies in
/// `[1, 1 + x^2]` and `atan(x) / x` in `[1 - x^2, 1]` for `|x| <= 1/2`.
fn decimal_pi_tiny_factor(
  above : Bool,
  t : Int64,
  precision : Int32,
) -> @ball_float.BallFloat {
  // Any k up to 3.32 t is sound; more than the working precision only makes
  // the subtraction below align operands millions of bits apart.
  let k = Int64::min(t * 3321928L / 1000000L, (precision + 64).to_int64()).to_int()
  let bound = @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -k, 32)
  let epsilon = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::zero(precision=32),
    bound,
    precision~,
  )
  let one = @ball_float.BallFloat::from_int(1, precision~)
  if above {
    one.add(epsilon)
  } else {
    one.sub(epsilon)
  }
}

///|
/// `scaled = x 10^-adj(x)` and the shift `adj(x)` of `x`.
fn decimal_pi_scale_to_unit(value : Decimal) -> (Decimal, Int32) {
  let adjusted = adjusted_exponent64(value)
  (
    { ..value, exponent10: (value.exponent10.to_int64() - adjusted).to_int(), },
    adjusted.to_int(),
  )
}

///|
fn decimal_pi_is_unit(value : Decimal) -> Bool {
  value.coefficient.digits10() > 0 &&
  value.abs_ctx(DecimalContext::exact()).0.compare(
    Decimal::from_int(1, precision=1),
  ) ==
  0
}

///|
fn Decimal::pi_asin_like(
  self : Decimal,
  ctx : DecimalContext,
  acos : Bool,
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
  // Table 9.1: |x| > 1 (infinities included) is invalid.
  if value.class == FpClass::Infinity {
    return Ok(finish(decimal_elementary_invalid(ctx)))
  }
  let one = Decimal::from_int(1, precision=1)
  let comparison = value.abs_ctx(DecimalContext::exact()).0.compare(one)
  if comparison > 0 {
    return Ok(finish(decimal_elementary_invalid(ctx)))
  }
  if value.coefficient.is_zero() {
    return Ok(
      finish(
        if acos {
          decimal_pi_constant(false, 5, -1, ctx)
        } else {
          decimal_elementary_zero(value.negative, ctx)
        },
      ),
    )
  }
  if comparison == 0 {
    return Ok(
      finish(
        if acos {
          if value.negative {
            decimal_pi_constant(false, 1, 0, ctx)
          } else {
            decimal_elementary_zero(false, ctx)
          }
        } else {
          decimal_pi_constant(value.negative, 5, -1, ctx)
        },
      ),
    )
  }
  if acos {
    // 1/2 - asin(x)/pi with 0 < |asin(x)/pi| <= |x|/2 < 10^(adjusted(x) + 1):
    // one-sided next to the representable 1/2, above it for x < 0.
    match
      decimal_tiny_argument_result(
        decimal_pi_anchor(false, 5, -1),
        value.negative,
        adjusted_exponent64(value) + 1L,
        ctx,
      ) {
      Some(result) => return Ok(finish(result))
      None => ()
    }
  }
  let name = if acos { "acospi" } else { "asinpi" }
  // A tiny x: asin(x) / pi = (s / pi) 10^adj (1 + e) with s = x 10^-adj and
  // 0 <= e <= x^2, so the loop encloses a moderate value and shifts it; the
  // exact decimal endpoints of a result near 10^-2,000,000 are never formed.
  if !acos {
    let t = -(2L * adjusted_exponent64(value) + 2L)
    if decimal_pi_tiny_enough(t, value.coefficient.digits10(), ctx) {
      let (scaled, shift) = decimal_pi_scale_to_unit(value)
      return decimal_certified_scaled_result(scaled, shift, ctx, name, fn(
        input,
      ) {
        Ok(
          input
          .div(decimal_pi_ball(input.precision()))
          .mul(decimal_pi_tiny_factor(true, t, input.precision())),
        )
      }).map(finish)
    }
  }
  decimal_certified_unary_result(value, ctx, name, fn(input) {
    let angle = if acos {
      input.try_acos_interval()
    } else {
      input.try_asin_interval()
    }
    angle.map(fn(a) { a.div(decimal_pi_ball(input.precision())) })
  }).map(finish)
}

///|
pub fn Decimal::try_asinpi_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.pi_asin_like(ctx, false)
}

///|
pub fn Decimal::asinpi_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_asinpi_ctx(ctx) {
    Ok(result) => result
    Err(_) => decimal_elementary_invalid(ctx)
  }
}

///|
pub fn Decimal::try_acospi_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.pi_asin_like(ctx, true)
}

///|
pub fn Decimal::acospi_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_acospi_ctx(ctx) {
    Ok(result) => result
    Err(_) => decimal_elementary_invalid(ctx)
  }
}

///|
pub fn Decimal::try_atanpi_ctx(
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
  // 9.2.1: "atanPi(+-inf) is +-1/2 with no exception."
  if value.class == FpClass::Infinity {
    return Ok(finish(decimal_pi_constant(value.negative, 5, -1, ctx)))
  }
  if value.coefficient.is_zero() {
    return Ok(finish(decimal_elementary_zero(value.negative, ctx)))
  }
  // atanPi(+-1) = +-1/4.
  if decimal_pi_is_unit(value) {
    return Ok(finish(decimal_pi_constant(value.negative, 25, -2, ctx)))
  }
  // |x| >= 10^a: atanPi(x) = +-(1/2 - d) with 0 < d < 1/(pi |x|) < 10^(-a).
  match
    decimal_tiny_argument_result(
      decimal_pi_anchor(value.negative, 5, -1),
      value.negative,
      -adjusted_exponent64(value),
      ctx,
    ) {
    Some(result) => return Ok(finish(result))
    None => ()
  }
  let t = -(2L * adjusted_exponent64(value) + 2L)
  if decimal_pi_tiny_enough(t, value.coefficient.digits10(), ctx) {
    let (scaled, shift) = decimal_pi_scale_to_unit(value)
    return decimal_certified_scaled_result(scaled, shift, ctx, "atanpi", fn(
      input,
    ) {
      Ok(
        input
        .div(decimal_pi_ball(input.precision()))
        .mul(decimal_pi_tiny_factor(false, t, input.precision())),
      )
    }).map(finish)
  }
  decimal_certified_unary_result(value, ctx, "atanpi", fn(input) {
    input
    .try_atan_interval()
    .map(fn(a) { a.div(decimal_pi_ball(input.precision())) })
  }).map(finish)
}

///|
pub fn Decimal::atanpi_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_atanpi_ctx(ctx) {
    Ok(result) => result
    Err(_) => decimal_elementary_invalid(ctx)
  }
}

///|
pub fn Decimal::try_atan2pi_ctx(
  self : Decimal,
  abscissa : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  if math_context_is_restricted(ctx) ||
    decimal_math_operand_out_of_range(self) ||
    decimal_math_operand_out_of_range(abscissa) {
    return Ok(invalid_context_result(ctx))
  }
  let (ordinate, x, operand_flags) = prepare_binary_operands_for_context(
    self, abscissa, ctx,
  )
  let finish = fn(result : (Decimal, DecimalFlags)) {
    (result.0, operand_flags.combine(result.1))
  }
  match quiet_nan_pair(ordinate, x, ctx) {
    Some(result) => return Ok(finish(result))
    None => ()
  }
  let negative = ordinate.negative
  let behind = x.negative
  let ordinate_zero = ordinate.class == FpClass::Finite &&
    ordinate.coefficient.is_zero()
  let x_zero = x.class == FpClass::Finite && x.coefficient.is_zero()
  // The exact rows of 9.2.1 (the sign bit of a zero abscissa chooses the
  // half-plane; the sign of the ordinate is the sign of the result).
  if ordinate_zero {
    return Ok(
      finish(
        if behind {
          decimal_pi_constant(negative, 1, 0, ctx)
        } else {
          decimal_elementary_zero(negative, ctx)
        },
      ),
    )
  }
  if ordinate.class == FpClass::Infinity {
    return Ok(
      finish(
        if x.class == FpClass::Infinity {
          if behind {
            decimal_pi_constant(negative, 75, -2, ctx)
          } else {
            decimal_pi_constant(negative, 25, -2, ctx)
          }
        } else {
          decimal_pi_constant(negative, 5, -1, ctx)
        },
      ),
    )
  }
  if x_zero {
    return Ok(finish(decimal_pi_constant(negative, 5, -1, ctx)))
  }
  if x.class == FpClass::Infinity {
    return Ok(
      finish(
        if behind {
          decimal_pi_constant(negative, 1, 0, ctx)
        } else {
          decimal_elementary_zero(negative, ctx)
        },
      ),
    )
  }
  // Finite nonzero operands: |y| = |x| is the only exact angle.
  let magnitude_y = { ..ordinate, negative: false, }
  let magnitude_x = { ..x, negative: false, }
  // Equal magnitudes have equal adjusted exponents; comparing first spares
  // the alignment of operands whose exponents differ by millions.
  if adjusted_exponent64(magnitude_y) == adjusted_exponent64(magnitude_x) &&
    magnitude_y.compare(magnitude_x) == 0 {
    return Ok(
      finish(
        if behind {
          decimal_pi_constant(negative, 75, -2, ctx)
        } else {
          decimal_pi_constant(negative, 25, -2, ctx)
        },
      ),
    )
  }
  // With D = adjusted(y) - adjusted(x): 10^(D-1) < |y/x| < 10^(D+1).
  let distance = adjusted_exponent64(ordinate) - adjusted_exponent64(x)
  // Large ratio: 1/2 -+ d with 0 < d < 1/(pi |y/x|) < 10^(1 - D), below 1/2 in
  // magnitude for x > 0 and above it for x < 0.
  match
    decimal_tiny_argument_result(
      decimal_pi_anchor(negative, 5, -1),
      behind != negative,
      1L - distance,
      ctx,
    ) {
    Some(result) => return Ok(finish(result))
    None => ()
  }
  // Small ratio with x < 0: 1 - d with 0 < d < |y/x|/pi < 10^(D + 1).
  if behind {
    match
      decimal_tiny_argument_result(
        decimal_pi_anchor(negative, 1, 0),
        negative,
        distance + 1L,
        ctx,
      ) {
      Some(result) => return Ok(finish(result))
      None => ()
    }
  }
  // atan2 depends on the ratio only: scaling both operands by 10^-adjusted(x)
  // keeps it, leaves x in [1, 10) and spares the conversion of operands with
  // exponents of millions of digits (`1E-1999996` against `1`).
  let x_shift = adjusted_exponent64(x).to_int()
  let ordinate = { ..ordinate, exponent10: ordinate.exponent10 - x_shift, }
  let x = { ..x, exponent10: x.exponent10 - x_shift, }
  let finalize = fn(result : (Decimal, DecimalFlags)) {
    // A result that rounds to zero keeps the exponent of the rounding; only the
    // sign of the ordinate is imposed (as for atan2, #332).
    let value = if result.0.is_zero() {
      { ..result.0, negative, }
    } else {
      result.0
    }
    finish((value, result.1))
  }
  // Small ratio with x > 0: atan2(y, x) / pi = (r / pi) (1 - e) with
  // r = |y / x| = (sy / sx) 10^D, sy and sx the operands scaled to [1, 10),
  // D = adjusted(y) - adjusted(x), and 0 <= e <= r^2 < 10^(2 D + 2) (atan r / r
  // lies in [1 - r^2, 1] for r <= 1). The loop encloses the moderate value
  // sy / (sx pi) (1 - e) and shifts it by D, so the exact decimal endpoints of a
  // result near 10^-2,000,000 are never formed (as for atanpi).
  if !behind {
    let t = -(2L * distance + 2L)
    let digits = Int32::max(
      ordinate.coefficient.digits10(),
      x.coefficient.digits10(),
    )
    if decimal_pi_tiny_enough(t, digits, ctx) {
      let (scaled_y, _) = decimal_pi_scale_to_unit(ordinate)
      let (scaled_x, _) = decimal_pi_scale_to_unit(x)
      return decimal_certified_scaled_loop(
        Int32::max(
          decimal_certified_work_precision(scaled_y, ctx),
          decimal_certified_work_precision(scaled_x, ctx),
        ),
        distance.to_int(),
        ctx,
        "atan2pi",
        fn(precision) {
          let magnitude = decimal_to_certified_ball(scaled_y, precision)
            .abs()
            .div(decimal_to_certified_ball(scaled_x, precision).abs())
            .div(decimal_pi_ball(precision))
            .mul(decimal_pi_tiny_factor(false, t, precision))
          Ok(if negative { magnitude.neg() } else { magnitude })
        },
      ).map(finalize)
    }
  }
  decimal_certified_binary_result(ordinate, x, ctx, "atan2pi", fn(
    y,
    x_interval,
  ) {
    // atan2(y, x) / pi from the ratio: atan(|y/x|) / pi for x > 0 and
    // 1 - atan(|y/x|) / pi for x < 0, with the sign of y; the operands are
    // exact nonzero decimals, so the signs are known and the enclosure of the
    // ratio never contains zero.
    y
    .abs()
    .div(x_interval.abs())
    .try_atan_interval()
    .map(fn(angle) {
      let fraction = angle.div(decimal_pi_ball(angle.precision()))
      let magnitude = if behind {
        @ball_float.BallFloat::from_int(1, precision=angle.precision()).sub(
          fraction,
        )
      } else {
        fraction
      }
      if negative {
        magnitude.neg()
      } else {
        magnitude
      }
    })
  }).map(finalize)
}

///|
pub fn Decimal::atan2pi_ctx(
  self : Decimal,
  abscissa : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_atan2pi_ctx(abscissa, ctx) {
    Ok(result) => result
    Err(_) => decimal_elementary_invalid(ctx)
  }
}
