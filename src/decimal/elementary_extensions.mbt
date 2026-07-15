///|
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
  Rootn(Int)
} derive(Eq)

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
  input : @ball_float.BallFloat,
) -> Result[@ball_float.BallFloat, @def.ArithmeticError] {
  match self {
    Exp2 => input.try_exp2_interval()
    Exp10 => input.try_exp10_interval()
    Expm1 => input.try_expm1_interval()
    Log2 => input.try_log2_interval()
    Log1p => input.try_log1p_interval()
    Sin => input.try_sin_interval()
    Cos => input.try_cos_interval()
    Tan => input.try_tan_interval()
    SinPi => input.try_sinpi_interval()
    CosPi => input.try_cospi_interval()
    TanPi => input.try_tanpi_interval()
    Asin => input.try_asin_interval()
    Acos => input.try_acos_interval()
    Atan => input.try_atan_interval()
    Sinh => input.try_sinh_interval()
    Cosh => input.try_cosh_interval()
    Tanh => input.try_tanh_interval()
    Asinh => input.try_asinh_interval()
    Acosh => input.try_acosh_interval()
    Atanh => input.try_atanh_interval()
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
      sign,
      precision=finite_precision_for_coeff(dec_coeff_zero(), ctx),
    ),
    { ..DecimalFlags::new(), division_by_zero: true },
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
fn decimal_elementary_integer_mod4(value : Decimal) -> Int? {
  match decimal_exact_integer_coeff(value) {
    Some((negative, magnitude)) => {
      let residue = dec_coeff_limb_at(magnitude, 0).reinterpret_as_int() % 4
      Some(if negative && residue != 0 { 4 - residue } else { residue })
    }
    None => None
  }
}

///|
fn decimal_pi_scaled_exact(
  value : Decimal,
  operation : DecimalUnaryElementary,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard operation == SinPi || operation == CosPi || operation == TanPi else {
    return None
  }
  let precision = finite_precision_for_coeff(dec_coeff_zero(), ctx)
  match decimal_elementary_integer_mod4(value) {
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
      return Some(
        (
          match operation {
            SinPi | TanPi => sine
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
    Int::max(value.precision_, value.coefficient.digits10() + 1),
  )
  match decimal_elementary_integer_mod4(doubled) {
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
        TanPi =>
          Decimal::inf(
            if sine_negative {
              Sign::Negative
            } else {
              Sign::Positive
            },
            precision~,
          )
        _ => sine
      }
      Some(
        (
          result,
          if operation == TanPi {
            { ..DecimalFlags::new(), division_by_zero: true }
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
  let zero = Decimal::zero(precision=decimal_math_target_precision(ctx))
  decimal_certified_unary_result(zero, ctx, "atan", fn(input) {
    let precision = input.precision()
    let quarter = @ball_float.BallFloat::from_int(1, precision~).atan_interval()
    let half = quarter.mul(@ball_float.BallFloat::from_int(2, precision~))
    Ok(if negative { half.neg() } else { half })
  })
}

///|
fn Decimal::try_unary_elementary_ctx(
  self : Decimal,
  operation : DecimalUnaryElementary,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  if math_context_is_restricted(ctx) || decimal_math_operand_out_of_range(self) {
    return Ok(invalid_context_result(ctx))
  }
  let (value, operand_flags) = prepare_operand_for_context(self, ctx)
  let precision = finite_precision_for_coeff(dec_coeff_zero(), ctx)
  let finish = fn(result : (Decimal, DecimalFlags)) {
    (result.0, operand_flags.combine(result.1))
  }
  if value.class == FpClass::NaN {
    return Ok(finish(quiet_nan_operand(value, ctx)))
  }
  if value.class == FpClass::Infinity {
    let result = match operation {
      Exp2 | Exp10 =>
        Ok(
          (
            if value.negative {
              Decimal::zero(precision~)
            } else {
              Decimal::inf(Sign::Positive, precision~)
            },
            DecimalFlags::new(),
          ),
        )
      Expm1 =>
        Ok(
          (
            if value.negative {
              Decimal::from_int(-1, precision~)
            } else {
              Decimal::inf(Sign::Positive, precision~)
            },
            DecimalFlags::new(),
          ),
        )
      Log2
      | Log1p
      | Asin
      | Acos
      | Atanh
      | Sin
      | Cos
      | Tan
      | SinPi
      | CosPi
      | TanPi => Ok(decimal_elementary_invalid(ctx))
      Atan => decimal_certified_atan_infinity(value.negative, ctx)
      Sinh | Asinh =>
        Ok((Decimal::inf(value.sign(), precision~), DecimalFlags::new()))
      Cosh | Acosh =>
        Ok(
          if value.negative {
            decimal_elementary_invalid(ctx)
          } else {
            (Decimal::inf(Sign::Positive, precision~), DecimalFlags::new())
          },
        )
      Tanh =>
        Ok(
          (
            Decimal::from_int(if value.negative { -1 } else { 1 }, precision~),
            DecimalFlags::new(),
          ),
        )
      Rootn(degree) =>
        if degree == 0 || (value.negative && degree % 2 == 0) {
          Ok(decimal_elementary_invalid(ctx))
        } else if degree < 0 {
          Ok(decimal_elementary_zero(value.negative && degree % 2 != 0, ctx))
        } else {
          Ok(
            (
              Decimal::inf(
                if value.negative {
                  Sign::Negative
                } else {
                  Sign::Positive
                },
                precision~,
              ),
              DecimalFlags::new(),
            ),
          )
        }
    }
    return result.map(finish)
  }
  let zero = Decimal::zero(precision=value.precision_)
  let one = Decimal::one(precision=value.precision_)
  let minus_one = Decimal::from_int(-1, precision=value.precision_)
  if value.coefficient.is_zero() {
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
      | Atanh => Some(decimal_elementary_zero(value.negative, ctx))
      Log2 => Some(decimal_elementary_division_by_zero(Sign::Negative, ctx))
      Acosh => Some(decimal_elementary_invalid(ctx))
      Rootn(degree) if degree == 0 => Some(decimal_elementary_invalid(ctx))
      Rootn(degree) if degree < 0 =>
        Some(
          decimal_elementary_division_by_zero(
            if value.negative && degree % 2 != 0 {
              Sign::Negative
            } else {
              Sign::Positive
            },
            ctx,
          ),
        )
      Rootn(_) => Some(decimal_elementary_zero(value.negative, ctx))
      Acos => None
    }
    match exact {
      Some(result) => return Ok(finish(result))
      None => ()
    }
  }
  match decimal_pi_scaled_exact(value, operation, ctx) {
    Some(result) => return Ok(finish(result))
    None => ()
  }
  if operation == Exp2 || operation == Exp10 {
    match decimal_exact_integer_coeff(value) {
      Some(_) => {
        let base = Decimal::from_int(
          if operation == Exp2 {
            2
          } else {
            10
          },
          precision~,
        )
        return Ok(finish(base.power_ctx(value, ctx)))
      }
      None => ()
    }
  }
  let invalid_domain = match operation {
    Log2 => value.compare(zero) <= 0
    Log1p => value.compare(minus_one) < 0
    Asin | Acos => value.abs_ctx(DecimalContext::exact()).0.compare(one) > 0
    Acosh => value.compare(one) < 0
    Atanh => value.abs_ctx(DecimalContext::exact()).0.compare(one) > 0
    Rootn(degree) => degree == 0 || (value.negative && degree % 2 == 0)
    _ => false
  }
  if invalid_domain {
    return Ok(finish(decimal_elementary_invalid(ctx)))
  }
  if operation == Log1p && value.compare(minus_one) == 0 {
    return Ok(finish(decimal_elementary_division_by_zero(Sign::Negative, ctx)))
  }
  if operation == Atanh &&
    value.abs_ctx(DecimalContext::exact()).0.compare(one) == 0 {
    return Ok(finish(decimal_elementary_division_by_zero(value.sign(), ctx)))
  }
  if (operation == Log2 && value.compare(one) == 0) ||
    (operation == Acosh && value.compare(one) == 0) {
    return Ok(finish(decimal_elementary_zero(false, ctx)))
  }
  decimal_certified_unary_result(value, ctx, operation.name(), fn(input) {
    operation.evaluate(input)
  }).map(finish)
}

///|
fn Decimal::unary_elementary_ctx(
  self : Decimal,
  operation : DecimalUnaryElementary,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_unary_elementary_ctx(operation, ctx) {
    Ok(result) => result
    Err(_) => abort("certified decimal elementary evaluation failed")
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
  degree : Int,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_unary_elementary_ctx(Rootn(degree), ctx)
}

///|
pub fn Decimal::rootn_ctx(
  self : Decimal,
  degree : Int,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.unary_elementary_ctx(Rootn(degree), ctx)
}

///|
pub fn Decimal::try_pown_ctx(
  self : Decimal,
  exponent : Int,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  self.try_power_ctx(Decimal::from_int(exponent, precision=ctx.precision), ctx)
}

///|
pub fn Decimal::pown_ctx(
  self : Decimal,
  exponent : Int,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  self.power_ctx(Decimal::from_int(exponent, precision=ctx.precision), ctx)
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
pub fn Decimal::try_hypot_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  if math_context_is_restricted(ctx) ||
    decimal_math_operand_out_of_range(self) ||
    decimal_math_operand_out_of_range(other) {
    return Ok(invalid_context_result(ctx))
  }
  let (left, right, operand_flags) = prepare_binary_operands_for_context(
    self, other, ctx,
  )
  let precision = finite_precision_for_coeff(dec_coeff_zero(), ctx)
  let nan_result = quiet_nan_pair(left, right, ctx)
  if left.class == FpClass::Infinity || right.class == FpClass::Infinity {
    let nan_flags = match nan_result {
      Some(result) => result.1
      None => DecimalFlags::new()
    }
    return Ok(
      (
        Decimal::inf(Sign::Positive, precision~),
        operand_flags.combine(nan_flags),
      ),
    )
  }
  match nan_result {
    Some(result) => return Ok((result.0, operand_flags.combine(result.1)))
    None => ()
  }
  if left.coefficient.is_zero() && right.coefficient.is_zero() {
    return Ok((Decimal::zero(precision~), operand_flags))
  }
  decimal_certified_binary_result(left, right, ctx, "hypot", fn(lhs, rhs) {
    lhs.try_hypot(rhs)
  }).map(fn(result) { (result.0, operand_flags.combine(result.1)) })
}

///|
pub fn Decimal::hypot_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match self.try_hypot_ctx(other, ctx) {
    Ok(result) => result
    Err(_) => abort("certified decimal hypot evaluation failed")
  }
}

///|
pub fn Decimal::try_atan2_ctx(
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
  match quiet_nan_pair(ordinate, x, ctx) {
    Some(result) => return Ok((result.0, operand_flags.combine(result.1)))
    None => ()
  }
  if ordinate.class == FpClass::Finite &&
    ordinate.coefficient.is_zero() &&
    x.class == FpClass::Finite &&
    x.coefficient.is_zero() &&
    !x.negative {
    return Ok(
      (decimal_elementary_zero(ordinate.negative, ctx).0, operand_flags),
    )
  }
  decimal_certified_binary_result(ordinate, x, ctx, "atan2", fn(y, x_interval) {
    y.try_atan2_interval(x_interval)
  }).map(fn(result) {
    let value = if result.0.is_zero() {
      decimal_elementary_zero(ordinate.negative, ctx).0
    } else {
      result.0
    }
    (value, operand_flags.combine(result.1))
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
    Err(_) => abort("certified decimal atan2 evaluation failed")
  }
}
