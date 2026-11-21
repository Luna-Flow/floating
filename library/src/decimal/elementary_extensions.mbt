///|
#derive(Eq)
priv enum DecimalUnaryElementary {
  Exp2
  Exp10
  Expm1
  Log2
  Log1p
  Sin
  Cos
  Tan
  SinPi
  CosPi
  TanPi
  Asin
  Acos
  Atan
  Sinh
  Cosh
  Tanh
  Asinh
  Acosh
  Atanh
  Rootn(Int32)
}

///|
fn DecimalUnaryElementary::name(self : DecimalUnaryElementary) -> String {
  match self {
    Exp2 => "exp2"
    Exp10 => "exp10"
    Expm1 => "expm1"
    Log2 => "log2"
    Log1p => "log1p"
    Sin => "sin"
    Cos => "cos"
    Tan => "tan"
    SinPi => "sinpi"
    CosPi => "cospi"
    TanPi => "tanpi"
    Asin => "asin"
    Acos => "acos"
    Atan => "atan"
    Sinh => "sinh"
    Cosh => "cosh"
    Tanh => "tanh"
    Asinh => "asinh"
    Acosh => "acosh"
    Atanh => "atanh"
    Rootn(_) => "rootn"
  }
}

///|
fn DecimalUnaryElementary::evaluate(
  self : DecimalUnaryElementary,
  input : @interval.Interval,
) -> Result[@interval.Interval, @def.ArithmeticError] {
  match self {
    Exp2 => input.try_exp2()
    Exp10 => input.try_exp10()
    Expm1 => input.try_expm1()
    Log2 => input.try_log2()
    Log1p => input.try_log1p()
    Sin => input.try_sin()
    Cos => input.try_cos()
    Tan => input.try_tan()
    SinPi => input.try_sinpi()
    CosPi => input.try_cospi()
    TanPi => input.try_tanpi()
    Asin => input.try_asin()
    Acos => input.try_acos()
    Atan => input.try_atan()
    Sinh => input.try_sinh()
    Cosh => input.try_cosh()
    Tanh => input.try_tanh()
    Asinh => input.try_asinh()
    Acosh => input.try_acosh()
    Atanh => input.try_atanh()
    Rootn(degree) => input.try_rootn(degree)
  }
}

///|
fn decimal_elementary_invalid(ctx : DecimalContext) -> (Decimal, DecimalFlags) {
  (
    Decimal::nan(precision=finite_precision_for_coeff(dec_coeff_zero(), ctx)),
    invalid_flags(),
  )
}

///|
fn decimal_elementary_division_by_zero(
  sign : Sign,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  (
    Decimal::inf(
      negative=sign == Sign::Negative,
      precision=finite_precision_for_coeff(dec_coeff_zero(), ctx),
    ),
    { ..DecimalFlags::new(), division_by_zero: true, },
  )
}

///|
fn decimal_elementary_zero(
  negative : Bool,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  (
    if negative {
      Decimal::negative_zero(
        precision=finite_precision_for_coeff(dec_coeff_zero(), ctx),
      )
    } else {
      Decimal::zero(precision=finite_precision_for_coeff(dec_coeff_zero(), ctx))
    },
    DecimalFlags::new(),
  )
}

///|
let decimal_half_constant : Decimal = Decimal::from_string("0.5").unwrap()

///|
fn decimal_certified_saturated_unary_result(
  value : Decimal,
  operation : DecimalUnaryElementary,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  if ctx.precision <= 0 {
    return None
  }
  let saturates = match operation {
    Tanh => true
    Expm1 => value.negative
    _ => false
  }
  if !saturates {
    return None
  }
  let magnitude = { ..value, negative: false, }
  let threshold = Decimal::from_int(ctx.precision * 6)
  if magnitude.compare(threshold) < 0 {
    return None
  }
  // Since e > 5/2, the function's gap from ±1 is below 10^(-2p).
  // The representative ±(1 - 10^(-(p+2))) is on the same side of the
  // limit and within that bound, so it has the same rounded result. Running
  // it through normal context rounding also supplies tininess/overflow flags.
  let scale = ctx.precision + 2
  let power = dec_coeff_power10_repr(scale)
  let coefficient = dec_coeff_magnitude_sub_unit(power, 1)
  Some(
    normalize_decimal_parts_math_ctx_repr(
      value.negative,
      coefficient,
      -scale,
      ctx,
    ),
  )
}

///|
/// Uses the first nonzero correction term to certify a tiny argument without
/// resolving that correction in the binary input enclosure.
fn decimal_tiny_unary_result(
  value : Decimal,
  operation : DecimalUnaryElementary,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard value.class == FpClass::Finite && !value.coefficient.is_zero() else {
    return None
  }
  let magnitude = { ..value, negative: false, }
  guard magnitude.compare(decimal_half_constant) < 0 else { return None }
  let top = value.exponent10.to_int64() +
    value.coefficient.digits10().to_int64()
  let (anchor, above, order) = match operation {
    Sin => (value, value.negative, 3L)
    Tan => (value, !value.negative, 3L)
    Atan => (value, value.negative, 3L)
    Asin => (value, !value.negative, 3L)
    Sinh => (value, !value.negative, 3L)
    Tanh => (value, value.negative, 3L)
    Asinh => (value, value.negative, 3L)
    Atanh => (value, !value.negative, 3L)
    // expm1(x) - x = x^2 / 2 + x^3 / 6 + ... > 0 and x - log1p(x) = x^2 / 2 -
    // x^3 / 3 + ... > 0, both below x^2 < 10^(2 top) for 0 < |x| < 1/2: expm1
    // lies above x and log1p below it, for either sign of x.
    Expm1 => (value, true, 2L)
    Log1p => (value, false, 2L)
    Cos => (Decimal::from_int(1, precision=ctx.precision), false, 2L)
    // 0 < 1 - cospi(x) = 2 sin^2(pi x / 2) <= (pi x)^2 / 2 < 5 x^2 < 10^(2 top
    // + 1) for 0 < |x| < 1/2: the same one-sided cluster below 1 as `cos`, one
    // decade wider.
    CosPi =>
      return decimal_tiny_argument_result(
        Decimal::from_int(1, precision=ctx.precision),
        false,
        2L * top + 1L,
        ctx,
      )
    Cosh => (Decimal::from_int(1, precision=ctx.precision), true, 2L)
    _ => return None
  }
  decimal_tiny_argument_result(anchor, above, order * top, ctx)
}

///|
/// `value` modulo 4 for an integer `value`, without expanding the power of ten
/// of a large exponent: `4 | 10^e` for `e >= 2` and `10^1 c = 2 (c mod 2)`
/// (mod 4), so only the low limb of the coefficient is read. `None` when
/// `value` is not an integer that the exact expansion can decide.
fn decimal_elementary_integer_mod4(value : Decimal) -> Int32? {
  if value.class == FpClass::Finite &&
    value.exponent10 >= 0 &&
    !value.coefficient.is_zero() {
    let low = dec_coeff_limb_at(value.coefficient, 0).reinterpret_as_int() % 4
    let residue = if value.exponent10 >= 2 {
      0
    } else if value.exponent10 == 1 {
      low % 2 * 2
    } else {
      low
    }
    return Some(
      if value.negative && residue != 0 {
        4 - residue
      } else {
        residue
      },
    )
  }
  match decimal_exact_integer_coeff(value) {
    Some((negative, magnitude)) => {
      let residue = dec_coeff_limb_at(magnitude, 0).reinterpret_as_int() % 4
      Some(if negative && residue != 0 { 4 - residue } else { residue })
    }
    None => None
  }
}

///|
/// With `listed_only`, only the results IEEE 754-2019 9.2.1 lists: `sinPi` of an
/// integer, `cosPi` of a half-integer, `tanPi` of an integer and of a
/// half-integer. The others (`cosPi(n)` = +-1, `sinPi(n + 1/2)` = +-1) are exact
/// results of ordinary operands.
fn decimal_pi_scaled_exact(
  value : Decimal,
  operation : DecimalUnaryElementary,
  ctx : DecimalContext,
  listed_only~ : Bool = false,
) -> (Decimal, DecimalFlags)? {
  guard operation == SinPi || operation == CosPi || operation == TanPi else {
    return None
  }
  let precision = finite_precision_for_coeff(dec_coeff_zero(), ctx)
  match decimal_elementary_integer_mod4(value) {
    Some(_) if listed_only && operation == CosPi => return None
    Some(residue) => {
      let sine = decimal_elementary_zero(value.negative, ctx).0
      let cosine = Decimal::from_int(
        if residue % 2 == 0 {
          1
        } else {
          -1
        },
        precision~,
      )
      // tanPi(n) = sinPi(n) / cosPi(n), a zero whose sign is the product of
      // the signs of the two (IEEE 754-2019 9.2.1): -0 at positive odd n.
      let tangent = if residue % 2 == 0 {
        sine
      } else {
        decimal_elementary_zero(!value.negative, ctx).0
      }
      return Some(
        (
          match operation {
            SinPi => sine
            TanPi => tangent
            CosPi => cosine
            _ => sine
          },
          DecimalFlags::new(),
        ),
      )
    }
    None => ()
  }
  let doubled = finite_with_exponent_repr(
    value.negative,
    dec_coeff_multiply_by_unit_repr(value.coefficient, 2),
    value.exponent10,
    Int32::max(value.precision_, value.coefficient.digits10() + 1),
  )
  match decimal_elementary_integer_mod4(doubled) {
    Some(_) if listed_only && operation == SinPi => None
    Some(residue) if residue % 2 != 0 => {
      let sine_negative = residue == 3
      let sine = Decimal::from_int(
        if sine_negative {
          -1
        } else {
          1
        },
        precision~,
      )
      let result = match operation {
        SinPi => sine
        CosPi => decimal_elementary_zero(false, ctx).0
        TanPi => Decimal::inf(negative=sine_negative, precision~)
        _ => sine
      }
      Some(
        (
          result,
          if operation == TanPi {
            { ..DecimalFlags::new(), division_by_zero: true, }
          } else {
            DecimalFlags::new()
          },
        ),
      )
    }
    _ => None
  }
}

///|
fn decimal_certified_atan_infinity(
  negative : Bool,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  decimal_certified_quarter_pi_multiple(2, negative, ctx, "atan")
}

///|
/// Correctly rounds `quarters * pi / 4`, negated when `negative` is set.
fn decimal_certified_quarter_pi_multiple(
  quarters : Int32,
  negative : Bool,
  ctx : DecimalContext,
  operation : String,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  let zero = Decimal::zero(precision=decimal_math_target_precision(ctx))
  decimal_certified_unary_result(zero, ctx, operation, fn(input) {
    let precision = input.precision()
    // pi/4 = [RD(pi), RU(pi)] / 4, exact scaling of the cached enclosure.
    let pi = decimal_pi_enclosure(precision)
    let scale = @binary.Binary::make(@binary.BinCoeff::one(), -2, 2)
    let exact = @binary.BinaryContext::new(precision~)
    let quarter = @interval.Interval::from_bounds(
      pi.0.mul_ctx(scale, exact).0,
      pi.1.mul_ctx(scale, exact).0,
      precision~,
    )
    let multiple = quarter.mul(
      @interval.Interval::from_int(quarters, precision~),
    )
    Ok(if negative { multiple.neg() } else { multiple })
  })
}

///|
fn Decimal::try_unary_elementary_ctx(
  self : Decimal,
  operation : DecimalUnaryElementary,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  // The special operands and the exact points (IEEE 754-2019 9.2.1) are
  // answered in every context; the limit of the context is tested after them,
  // before the first step that computes.
  let limited = math_context_is_restricted(ctx) ||
    decimal_math_operand_out_of_range(self)
  let precision = finite_precision_for_coeff(dec_coeff_zero(), ctx)
  if self.class == FpClass::NaN {
    return Ok(quiet_nan_operand(self, ctx))
  }
  if self.class == FpClass::Infinity {
    let result = match operation {
      Exp2 | Exp10 =>
        Ok(
          (
            if self.negative {
              Decimal::zero(precision~)
            } else {
              Decimal::inf(precision~)
            },
            DecimalFlags::new(),
          ),
        )
      Expm1 =>
        Ok(
          (
            if self.negative {
              Decimal::from_int(-1, precision~)
            } else {
              Decimal::inf(precision~)
            },
            DecimalFlags::new(),
          ),
        )
      Log2 | Log1p =>
        Ok(
          if self.negative {
            decimal_elementary_invalid(ctx)
          } else {
            (Decimal::inf(precision~), DecimalFlags::new())
          },
        )
      Asin | Acos | Atanh | Sin | Cos | Tan | SinPi | CosPi | TanPi =>
        Ok(decimal_elementary_invalid(ctx))
      Atan => decimal_certified_atan_infinity(self.negative, ctx)
      Sinh | Asinh =>
        Ok(
          (
            Decimal::inf(negative=self.is_sign_minus(), precision~),
            DecimalFlags::new(),
          ),
        )
      Cosh => Ok((Decimal::inf(precision~), DecimalFlags::new()))
      Acosh =>
        Ok(
          if self.negative {
            decimal_elementary_invalid(ctx)
          } else {
            (Decimal::inf(precision~), DecimalFlags::new())
          },
        )
      Tanh =>
        Ok(
          (
            Decimal::from_int(if self.negative { -1 } else { 1 }, precision~),
            DecimalFlags::new(),
          ),
        )
      Rootn(degree) =>
        if degree == 0 || (self.negative && degree % 2 == 0) {
          Ok(decimal_elementary_invalid(ctx))
        } else if degree < 0 {
          Ok(decimal_elementary_zero(self.negative && degree % 2 != 0, ctx))
        } else {
          Ok(
            (
              Decimal::inf(negative=self.negative, precision~),
              DecimalFlags::new(),
            ),
          )
        }
    }
    return result
  }
  let zero = Decimal::zero(precision=self.precision_)
  let one = Decimal::one(precision=self.precision_)
  let minus_one = Decimal::from_int(-1, precision=self.precision_)
  if self.coefficient.is_zero() {
    let exact = match operation {
      Exp2 | Exp10 | Cos | CosPi | Cosh =>
        Some((Decimal::one(precision~), DecimalFlags::new()))
      Expm1
      | Log1p
      | Sin
      | Tan
      | SinPi
      | TanPi
      | Asin
      | Atan
      | Sinh
      | Tanh
      | Asinh
      | Atanh => Some(decimal_elementary_zero(self.negative, ctx))
      Log2 => Some(decimal_elementary_division_by_zero(Sign::Negative, ctx))
      Acosh => Some(decimal_elementary_invalid(ctx))
      Rootn(degree) if degree == 0 => Some(decimal_elementary_invalid(ctx))
      Rootn(degree) if degree < 0 =>
        Some(
          decimal_elementary_division_by_zero(
            if self.negative && degree % 2 != 0 {
              Sign::Negative
            } else {
              Sign::Positive
            },
            ctx,
          ),
        )
      // rootn(+-0, n) is +-0 for odd n > 0 and +0 for even n > 0 (IEEE 754-2019
      // 9.2.1).
      Rootn(degree) =>
        Some(decimal_elementary_zero(self.negative && degree % 2 != 0, ctx))
      Acos => None
    }
    match exact {
      Some(result) => return Ok(result)
      None => ()
    }
  }
  match decimal_pi_scaled_exact(self, operation, ctx, listed_only=true) {
    Some(result) => return Ok(result)
    None => ()
  }
  let invalid_domain = match operation {
    Log2 => self.compare(zero) <= 0
    Log1p => self.compare(minus_one) < 0
    Asin | Acos => self.abs_ctx(decimal_exact_work_context()).0.compare(one) > 0
    Acosh => self.compare(one) < 0
    Atanh => self.abs_ctx(decimal_exact_work_context()).0.compare(one) > 0
    Rootn(degree) => degree == 0 || (self.negative && degree % 2 == 0)
    _ => false
  }
  if invalid_domain {
    return Ok(decimal_elementary_invalid(ctx))
  }
  if operation == Log1p && self.compare(minus_one) == 0 {
    return Ok(decimal_elementary_division_by_zero(Sign::Negative, ctx))
  }
  if operation == Atanh &&
    self.abs_ctx(decimal_exact_work_context()).0.compare(one) == 0 {
    return Ok(decimal_elementary_division_by_zero(self.sign(), ctx))
  }
  if (operation == Log2 && self.compare(one) == 0) ||
    (operation == Acos && self.compare(one) == 0) ||
    (operation == Acosh && self.compare(one) == 0) {
    return Ok(decimal_elementary_zero(false, ctx))
  }
  if limited {
    return Err(decimal_context_limit(operation.name(), ctx))
  }
  // exact results of ordinary operands, not listed in 9.2.1: after the limit
  match decimal_pi_scaled_exact(self, operation, ctx) {
    Some(result) => return Ok(result)
    None => ()
  }
  match operation {
    Rootn(degree) =>
      match decimal_rootn_exact_result(self, degree, ctx) {
        Some(result) => return Ok(result)
        None => ()
      }
    _ => ()
  }
  // an integer operand goes through `pow_ctx` (an ordinary operand: after the
  // limit of the context)
  if operation == Exp2 || operation == Exp10 {
    match decimal_power_integer_is_odd(self) {
      Some(_) => {
        let base = Decimal::from_int(
          if operation == Exp2 {
            2
          } else {
            10
          },
          precision~,
        )
        return Ok(base.pow_ctx(self, ctx))
      }
      None => ()
    }
  }
  // exp2 and exp10 far outside the representable range (#363).
  match operation {
    Exp2 =>
      match decimal_exponential_coarse_extreme_result(Two, self, ctx) {
        Some(result) => return Ok(result)
        None => ()
      }
    Exp10 =>
      match decimal_exponential_coarse_extreme_result(Ten, self, ctx) {
        Some(result) => return Ok(result)
        None => ()
      }
    _ => ()
  }
  match decimal_certified_saturated_unary_result(self, operation, ctx) {
    Some(result) => return Ok(result)
    None => ()
  }
  match decimal_tiny_unary_result(self, operation, ctx) {
    Some(result) => return Ok(result)
    None => ()
  }
  // exp2(x) = 1 + c x (1 + d) and exp10(x), exp(x) likewise (c = ln 2, ln 10,
  // 1): for |x| < 10^top, |f(x) - 1| < 10^(top + 1) with the sign of x, so a
  // tiny x puts f(x) next to the representable 1 on one side.
  if operation == Exp2 || operation == Exp10 {
    match decimal_exp_tiny_result(self, ctx) {
      Some(result) => return Ok(result)
      None => ()
    }
  }
  // sin, cos and tan of a huge integer operand: the operand is exactly a binary
  // rational (c * 5^e * 2^e), so it enters the ball as an exact point and the
  // evaluation runs at the result precision plus the binary magnitude of the
  // argument (the reduction modulo pi). Converting it to a ball of the target
  // precision would widen it by 2^top and never decide (#377). An operand with a
  // fractional part is not a dyadic rational: its ball precision starts at its
  // binary magnitude plus the target instead.
  let huge = match operation {
    Sin | Cos | Tan if self.class == FpClass::Finite =>
      adjusted_exponent64(self) >= 32L
    _ => false
  }
  let exact_evaluate = if huge && self.exponent10 >= 0 {
    let bits = ((
      self.coefficient.digits10().to_int64() + self.exponent10.to_int64()
    ) *
    3_321_929L /
    1_000_000L +
    16L).to_int()
    let (lower, upper) = self.to_binary_bounds(bits)
    if lower.compare(upper) == 0 {
      Some(fn(precision : Int32) {
        let downward = @binary.BinaryContext::new(
          precision~,
          rounding=@binary.BinaryRoundingMode::RoundTowardNegative,
        )
        let upward = @binary.BinaryContext::new(
          precision~,
          rounding=@binary.BinaryRoundingMode::RoundTowardPositive,
        )
        let low = match operation {
          Sin => lower.try_sin_ctx(downward)
          Cos => lower.try_cos_ctx(downward)
          _ => lower.try_tan_ctx(downward)
        }
        let high = match operation {
          Sin => lower.try_sin_ctx(upward)
          Cos => lower.try_cos_ctx(upward)
          _ => lower.try_tan_ctx(upward)
        }
        low.bind(fn(a) {
          high.map(fn(b) {
            @interval.Interval::from_bounds(a.0, b.0, precision~)
          })
        })
      })
    } else {
      None
    }
  } else {
    None
  }
  let extra_bits = if huge && exact_evaluate is None {
    (adjusted_exponent64(self) + 1L) * 3_321_929L / 1_000_000L
  } else {
    0L
  }
  decimal_certified_unary_result(
    self,
    ctx,
    operation.name(),
    fn(input) { operation.evaluate(input) },
    extra_bits=extra_bits.to_int(),
    exact_evaluate~,
  )
}

///|
fn Decimal::unary_elementary_ctx(
  self : Decimal,
  operation : DecimalUnaryElementary,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_unary_elementary_ctx(operation, ctx) {
    Ok(result) => result
    Err(_) => not_computed_result(ctx)
  }
}

///|
pub fn Decimal::try_exp2_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Exp2, ctx)
}

///|
pub fn Decimal::exp2_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Exp2, ctx)
}

///|
pub fn Decimal::try_exp10_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Exp10, ctx)
}

///|
pub fn Decimal::exp10_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Exp10, ctx)
}

///|
pub fn Decimal::try_expm1_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Expm1, ctx)
}

///|
pub fn Decimal::expm1_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Expm1, ctx)
}

///|
pub fn Decimal::try_log2_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Log2, ctx)
}

///|
pub fn Decimal::log2_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Log2, ctx)
}

///|
pub fn Decimal::try_log1p_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Log1p, ctx)
}

///|
pub fn Decimal::log1p_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Log1p, ctx)
}

///|
pub fn Decimal::try_rootn_ctx(
  self : Decimal,
  degree : Int32,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Rootn(degree), ctx)
}

///|
pub fn Decimal::rootn_ctx(
  self : Decimal,
  degree : Int32,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Rootn(degree), ctx)
}

///|
/// The integer exponent of `pown_ctx` as an exact `Decimal`. Building it at
/// the context precision rounded exponents longer than the precision, which
/// could change their value and parity.
fn decimal_pown_exponent(exponent : Int32, ctx : DecimalContext) -> Decimal {
  Decimal::from_int(exponent, precision=Int32::max(ctx.precision, 10))
}

///|
pub fn Decimal::try_pown_ctx(
  self : Decimal,
  exponent : Int32,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  decimal_failure_of(
    "pown",
    self.try_pow_ctx(decimal_pown_exponent(exponent, ctx), ctx),
  )
}

///|
pub fn Decimal::pown_ctx(
  self : Decimal,
  exponent : Int32,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.pow_ctx(decimal_pown_exponent(exponent, ctx), ctx)
}

///|
pub fn Decimal::try_sin_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Sin, ctx)
}

///|
pub fn Decimal::sin_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Sin, ctx)
}

///|
pub fn Decimal::try_cos_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Cos, ctx)
}

///|
pub fn Decimal::cos_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Cos, ctx)
}

///|
pub fn Decimal::try_tan_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Tan, ctx)
}

///|
pub fn Decimal::tan_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Tan, ctx)
}

///|
pub fn Decimal::try_sinpi_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(SinPi, ctx)
}

///|
pub fn Decimal::sinpi_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(SinPi, ctx)
}

///|
pub fn Decimal::try_cospi_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(CosPi, ctx)
}

///|
pub fn Decimal::cospi_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(CosPi, ctx)
}

///|
pub fn Decimal::try_tanpi_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(TanPi, ctx)
}

///|
pub fn Decimal::tanpi_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(TanPi, ctx)
}

///|
pub fn Decimal::try_asin_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Asin, ctx)
}

///|
pub fn Decimal::asin_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Asin, ctx)
}

///|
pub fn Decimal::try_acos_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Acos, ctx)
}

///|
pub fn Decimal::acos_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Acos, ctx)
}

///|
pub fn Decimal::try_atan_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Atan, ctx)
}

///|
pub fn Decimal::atan_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Atan, ctx)
}

///|
pub fn Decimal::try_sinh_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Sinh, ctx)
}

///|
pub fn Decimal::sinh_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Sinh, ctx)
}

///|
pub fn Decimal::try_cosh_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Cosh, ctx)
}

///|
pub fn Decimal::cosh_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Cosh, ctx)
}

///|
pub fn Decimal::try_tanh_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Tanh, ctx)
}

///|
pub fn Decimal::tanh_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Tanh, ctx)
}

///|
pub fn Decimal::try_asinh_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Asinh, ctx)
}

///|
pub fn Decimal::asinh_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Asinh, ctx)
}

///|
pub fn Decimal::try_acosh_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Acosh, ctx)
}

///|
pub fn Decimal::acosh_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Acosh, ctx)
}

///|
pub fn Decimal::try_atanh_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Atanh, ctx)
}

///|
pub fn Decimal::atanh_ctx(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Atanh, ctx)
}

///|
/// The exact `degree`-th root of `value`, or `None`: even degrees take exact
/// square roots first, then integer Newton steps from the root of the leading
/// digits (`dec_coeff_exact_nth_root_repr` of the kernel). The previous
/// iteration started at `10^ceil(d / degree)`, up to ten times the root, and
/// needed about `2.3 degree` linear steps (#376).
fn dec_coeff_exact_root_repr(value : DecCoeff, degree : Int32) -> DecCoeff? {
  dec_coeff_exact_nth_root_repr(value, degree)
}

///|
/// rootn(x, n) when the root is exactly representable at the target
/// precision. The certified evaluation cannot decide such a value: every
/// enclosure straddles it, so half modes returned it with `inexact` and the
/// directed modes failed certification.
fn decimal_rootn_exact_result(
  value : Decimal,
  degree : Int32,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard value.class == FpClass::Finite && !value.coefficient.is_zero() else {
    return None
  }
  guard degree != 0 else { return None }
  // rootn(x, 1) = x and rootn(x, -1) = 1 / x are decided without a root.
  if degree == 1 {
    return Some(apply_finite_ctx(value, ctx))
  }
  if degree == -1 {
    return exact_decimal_reciprocal(value, ctx)
  }
  guard !value.negative || degree % 2 != 0 else { return None }
  // Int.min has no positive Int magnitude; let the certified path handle it.
  guard degree != -2147483647 - 1 else { return None }
  let n = abs_int(degree)
  let target_precision = decimal_math_target_precision(ctx)
  let (coefficient, exponent) = remove_factor10_repr(
    value.coefficient,
    value.exponent10,
  )
  // Write |x| = radicand * 10^(n * root_exponent) with 0 <= shift < n.
  let shift = (exponent % n + n) % n
  // `coefficient` has no trailing zero, so `coefficient 10^shift` with
  // `0 < shift < n` has 2 and 5 adjusted by the same `shift` in the exponents of
  // the factorization, and `min(v2, v5)` of `coefficient` is 0: such a number is
  // an n-th power only if `n` divides `shift`. An exact root needs `shift == 0`.
  guard shift == 0 else { return None }
  let root_exponent = (exponent - shift) / n
  let radicand_digits = coefficient.digits10().to_int64() + shift.to_int64()
  // If r >= 2, then r^n >= 2^n. A d-digit radicand is less than
  // 10^d < 2^(4d), so a degree of at least 4d cannot be a perfect root.
  if !(dec_coeff_compare_repr(coefficient, dec_coeff_from_int(1)) == 0 &&
    shift == 0) &&
    n.to_int64() >= 4L * radicand_digits {
    return None
  }
  guard coefficient.digits10().to_int64() + shift.to_int64() <=
    n.to_int64() * target_precision.to_int64() else {
    return None
  }
  let radicand = dec_coeff_shift_power10_repr(coefficient, shift)
  let root = match dec_coeff_exact_root_repr(radicand, n) {
    Some(root) => root
    None => return None
  }
  guard root.digits10() <= target_precision else { return None }
  let exact = finite_with_exponent_repr(
    value.negative,
    root,
    root_exponent,
    target_precision,
  )
  if degree > 0 {
    Some(apply_finite_ctx(exact, ctx))
  } else {
    exact_decimal_reciprocal(exact, ctx)
  }
}

///|
/// hypot(x, y) when it is exactly representable at the target precision, for
/// the same reason as `decimal_rootn_exact_result`.
fn decimal_hypot_exact_result(
  left : Decimal,
  right : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard left.class == FpClass::Finite && right.class == FpClass::Finite else {
    return None
  }
  let target_precision = decimal_math_target_precision(ctx)
  if left.coefficient.is_zero() || right.coefficient.is_zero() {
    let other = if left.coefficient.is_zero() { right } else { left }
    return Some(apply_finite_ctx({ ..other, negative: false, }, ctx))
  }
  // A representable root z = sqrt(x^2 + y^2) with y << x satisfies
  // z - x ~ y^2 / (2x); with more than p + 2 orders of magnitude between the
  // operands that difference lies below the last digit z could have.
  let gap = adjusted_exponent(left) - adjusted_exponent(right)
  guard abs_int(gap) <= target_precision + 2 else { return None }
  let left_square_exponent = 2 * left.exponent10
  let right_square_exponent = 2 * right.exponent10
  let exponent = Int32::min(left_square_exponent, right_square_exponent)
  let sum = dec_coeff_magnitude_add_repr(
    dec_coeff_shift_power10_repr(
      dec_coeff_square_repr(left.coefficient),
      left_square_exponent - exponent,
    ),
    dec_coeff_shift_power10_repr(
      dec_coeff_square_repr(right.coefficient),
      right_square_exponent - exponent,
    ),
  )
  let square = finite_with_exponent_repr(false, sum, exponent, sum.digits10())
  match exact_finite_sqrt(square, target_precision) {
    Some(root) if root.coefficient.digits10() <= target_precision =>
      Some(apply_finite_ctx(root, ctx))
    _ => None
  }
}

///|
pub fn Decimal::try_hypot_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  // Special operands are answered in every context (IEEE 754-2019 9.2.1).
  let limited = math_context_is_restricted(ctx) ||
    decimal_math_operand_out_of_range(self) ||
    decimal_math_operand_out_of_range(other)
  let precision = finite_precision_for_coeff(dec_coeff_zero(), ctx)
  let nan_result = quiet_nan_pair(self, other, ctx)
  if self.class == FpClass::Infinity || other.class == FpClass::Infinity {
    // hypot(+-inf, y) is +inf for every y, even a quiet NaN. A signaling NaN
    // is not exempt: it signals invalid and the result is a quiet NaN
    // (IEEE 754-2019 6.2, 7.2, 9.2.1).
    if self.is_signaling_nan() || other.is_signaling_nan() {
      match nan_result {
        Some(result) => return Ok(result)
        None => ()
      }
    }
    let nan_flags = match nan_result {
      Some(result) => result.1
      None => DecimalFlags::new()
    }
    return Ok((Decimal::inf(precision~), nan_flags))
  }
  match nan_result {
    Some(result) => return Ok(result)
    None => ()
  }
  if self.coefficient.is_zero() && other.coefficient.is_zero() {
    return Ok((Decimal::zero(precision~), DecimalFlags::new()))
  }
  if limited {
    return Err(decimal_context_limit("hypot", ctx))
  }
  match decimal_hypot_exact_result(self, other, ctx) {
    Some(result) => return Ok(result)
    None => ()
  }
  let (large, small) = if adjusted_exponent(self) >= adjusted_exponent(other) {
    (self, other)
  } else {
    (other, self)
  }
  if !small.coefficient.is_zero() {
    let large = { ..large, negative: false, }
    let small = { ..small, negative: false, }
    let error_exponent = 2L *
      (small.exponent10.to_int64() + small.coefficient.digits10().to_int64()) -
      adjusted_exponent(large).to_int64()
    match decimal_tiny_argument_result(large, true, error_exponent, ctx) {
      Some(result) => return Ok(result)
      None => ()
    }
  }
  decimal_certified_binary_result(self, other, ctx, "hypot", fn(lhs, rhs) {
    lhs.try_hypot(rhs)
  })
}

///|
pub fn Decimal::hypot_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_hypot_ctx(other, ctx) {
    Ok(result) => result
    Err(_) => not_computed_result(ctx)
  }
}

///|
pub fn Decimal::try_atan2_ctx(
  self : Decimal,
  abscissa : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  // NaN operands and the zero and infinite operands that select an exact zero
  // or a multiple of pi/4 are answered in every context (IEEE 754-2019 9.2.1).
  let limited = math_context_is_restricted(ctx) ||
    decimal_math_operand_out_of_range(self) ||
    decimal_math_operand_out_of_range(abscissa)
  match quiet_nan_pair(self, abscissa, ctx) {
    Some(result) => return Ok(result)
    None => ()
  }
  // IEEE 754-2019 9.2.1: a zero or infinite operand selects an exact zero
  // or a multiple of pi/4 whose sign is that of the ordinate.
  let ordinate_zero = self.class == FpClass::Finite &&
    self.coefficient.is_zero()
  let x_zero = abscissa.class == FpClass::Finite &&
    abscissa.coefficient.is_zero()
  let quarters = if self.class == FpClass::Infinity {
    if abscissa.class == FpClass::Infinity {
      Some(if abscissa.negative { 3 } else { 1 })
    } else {
      Some(2)
    }
  } else if ordinate_zero || abscissa.class == FpClass::Infinity {
    // atan2(+-0, x) and atan2(y, +-inf) for finite y: the ordinate is
    // negligible against the abscissa, so only the abscissa's sign matters.
    Some(if abscissa.negative { 4 } else { 0 })
  } else if x_zero {
    Some(2)
  } else {
    None
  }
  match quarters {
    Some(0) =>
      return Ok(
        (decimal_elementary_zero(self.negative, ctx).0, DecimalFlags::new()),
      )
    Some(count) =>
      return decimal_certified_quarter_pi_multiple(
        count,
        self.negative,
        ctx,
        "atan2",
      )
    None => ()
  }
  if limited {
    return Err(decimal_context_limit("atan2", ctx))
  }
  // The tiny-argument decision below needs `3 top < adjusted(ratio) - p - 3`,
  // with top = adjusted(ratio) + 1 and adjusted(ratio) >= D - 1 for
  // D = adjusted(y) - adjusted(x): that is `2 D < -(p + 4)` at the most, so no
  // other ratio is formed (the exact division costs a gcd and two powers).
  let distance = adjusted_exponent64(self) - adjusted_exponent64(abscissa)
  if !abscissa.negative &&
    !self.coefficient.is_zero() &&
    !abscissa.coefficient.is_zero() &&
    2L * distance < -(ctx.precision.to_int64() + 4L) {
    match
      exact_decimal_division_result(
        self,
        abscissa,
        decimal_exact_work_context(),
      ) {
      Some((ratio, _)) => {
        let magnitude = { ..ratio, negative: false, }
        if magnitude.compare(decimal_half_constant) < 0 {
          let top = ratio.exponent10.to_int64() +
            ratio.coefficient.digits10().to_int64()
          match
            decimal_tiny_argument_result(ratio, ratio.negative, 3L * top, ctx) {
            Some(result) => return Ok(result)
            None => ()
          }
        }
      }
      None => ()
    }
  }
  decimal_certified_binary_result(self, abscissa, ctx, "atan2", fn(
    y,
    x_interval,
  ) {
    y.try_atan2(x_interval)
  }).map(fn(result) {
    // A result that rounds to zero keeps the exponent of the rounding (the
    // cohort member of least possible exponent, IEEE 754-2019 5.2, as for
    // every other function); only the sign of the ordinate is imposed (#332).
    let value = if result.0.is_zero() {
      { ..result.0, negative: self.negative, }
    } else {
      result.0
    }
    (value, result.1)
  })
}

///|
pub fn Decimal::atan2_ctx(
  self : Decimal,
  abscissa : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_atan2_ctx(abscissa, ctx) {
    Ok(result) => result
    Err(_) => not_computed_result(ctx)
  }
}
