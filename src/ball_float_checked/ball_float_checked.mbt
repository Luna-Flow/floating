///|
fn[A, B, E, C] ball_result_lift2(
  left : Result[A, E],
  right : Result[B, E],
  combine : (A, B) -> C,
) -> Result[C, E] {
  left.bind(fn(lhs) { right.map(fn(rhs) { combine(lhs, rhs) }) })
}

///|
pub struct BallFloatResult {
  priv inner : Result[@ball_float.BallFloat, @def.ArithmeticError]
}

///|
pub fn BallFloatResult::from_result(
  inner : Result[@ball_float.BallFloat, @def.ArithmeticError],
) -> BallFloatResult {
  { inner, }
}

///|
pub fn BallFloatResult::ok(value : @ball_float.BallFloat) -> BallFloatResult {
  { inner: Ok(value) }
}

///|
pub fn BallFloatResult::err(err : @def.ArithmeticError) -> BallFloatResult {
  { inner: Err(err) }
}

///|
pub fn BallFloatResult::from_int(
  value : Int,
  precision? : Int = 16,
) -> BallFloatResult {
  BallFloatResult::ok(@ball_float.BallFloat::from_int(value, precision~))
}

///|
pub fn BallFloatResult::from_coefficient(
  value : @bin_float.BinCoeff,
  precision? : Int = 16,
  negative? : Bool = false,
) -> BallFloatResult {
  BallFloatResult::ok(
    @ball_float.BallFloat::from_coefficient(value, precision~, negative~),
  )
}

///|
pub fn BallFloatResult::from_double(
  value : Double,
  precision? : Int = 53,
) -> BallFloatResult {
  BallFloatResult::from_result(
    @ball_float.BallFloat::try_from_double(value, precision~),
  )
}

///|
pub fn BallFloatResult::from_float(
  value : Float,
  precision? : Int = 24,
) -> BallFloatResult {
  BallFloatResult::from_result(
    @ball_float.BallFloat::try_from_float(value, precision~),
  )
}

///|
pub fn BallFloatResult::exact(
  value : @bin_float.BinFloat,
  precision? : Int = value.precision(),
) -> BallFloatResult {
  BallFloatResult::from_result(
    @ball_float.BallFloat::try_exact(value, precision~),
  )
}

///|
pub fn BallFloatResult::from_bounds(
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
  precision? : Int = Int::max(lo.precision(), hi.precision()),
) -> BallFloatResult {
  BallFloatResult::from_result(
    @ball_float.BallFloat::try_from_bounds(lo, hi, precision~),
  )
}

///|
pub fn BallFloatResult::whole(precision? : Int = 53) -> BallFloatResult {
  BallFloatResult::ok(@ball_float.BallFloat::whole(precision~))
}

///|
pub fn BallFloatResult::result(
  self : BallFloatResult,
) -> Result[@ball_float.BallFloat, @def.ArithmeticError] {
  self.inner
}

///|
pub fn BallFloatResult::is_ok(self : BallFloatResult) -> Bool {
  match self.inner {
    Ok(_) => true
    Err(_) => false
  }
}

///|
pub fn BallFloatResult::is_err(self : BallFloatResult) -> Bool {
  !self.is_ok()
}

///|
pub fn BallFloatResult::error(self : BallFloatResult) -> @def.ArithmeticError? {
  match self.inner {
    Ok(_) => None
    Err(error) => Some(error)
  }
}

///|
pub fn BallFloatResult::map(
  self : BallFloatResult,
  f : (@ball_float.BallFloat) -> @ball_float.BallFloat,
) -> BallFloatResult {
  BallFloatResult::from_result(self.inner.map(f))
}

///|
pub fn BallFloatResult::bind(
  self : BallFloatResult,
  f : (@ball_float.BallFloat) -> BallFloatResult,
) -> BallFloatResult {
  BallFloatResult::from_result(self.inner.bind(fn(value) { f(value).inner }))
}

///|
#deprecated("Use bind instead")
pub fn BallFloatResult::flat_map(
  self : BallFloatResult,
  f : (@ball_float.BallFloat) -> BallFloatResult,
) -> BallFloatResult {
  self.bind(f)
}

///|
pub fn BallFloatResult::normalized(self : BallFloatResult) -> BallFloatResult {
  self.map(fn(value) { value.normalized() })
}

///|
pub fn BallFloatResult::with_precision(
  self : BallFloatResult,
  precision : Int,
  mode : @def.RoundingMode,
) -> BallFloatResult {
  self.map(fn(value) { value.with_precision(precision, mode) })
}

///|
pub fn BallFloatResult::neg(self : BallFloatResult) -> BallFloatResult {
  self.map(fn(value) { value.neg() })
}

///|
pub fn BallFloatResult::abs(self : BallFloatResult) -> BallFloatResult {
  self.map(fn(value) { value.abs() })
}

///|
pub fn BallFloatResult::add(
  self : BallFloatResult,
  other : BallFloatResult,
) -> BallFloatResult {
  BallFloatResult::from_result(
    ball_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs + rhs }),
  )
}

///|
pub fn BallFloatResult::sub(
  self : BallFloatResult,
  other : BallFloatResult,
) -> BallFloatResult {
  BallFloatResult::from_result(
    ball_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs - rhs }),
  )
}

///|
pub fn BallFloatResult::mul(
  self : BallFloatResult,
  other : BallFloatResult,
) -> BallFloatResult {
  BallFloatResult::from_result(
    ball_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs * rhs }),
  )
}

///|
pub fn BallFloatResult::div(
  self : BallFloatResult,
  other : BallFloatResult,
) -> BallFloatResult {
  BallFloatResult::from_result(
    ball_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs / rhs }),
  )
}

///|
pub fn BallFloatResult::pow_nat(
  self : BallFloatResult,
  exponent : UInt,
) -> BallFloatResult {
  self.bind(fn(value) {
    let ctx = @lf_arith.ArithmeticContext::new(value.precision())
    BallFloatResult::from_result(
      @lf_arith.PowNatChecked::pow_nat_checked(value, exponent, ctx),
    )
  })
}

///|
pub fn BallFloatResult::pow_int(
  self : BallFloatResult,
  exponent : Int,
) -> BallFloatResult {
  self.bind(fn(value) {
    let ctx = @lf_arith.ArithmeticContext::new(value.precision())
    BallFloatResult::from_result(
      @lf_arith.PowIntChecked::pow_int_checked(value, exponent, ctx),
    )
  })
}

///|
pub fn BallFloatResult::rootn(
  self : BallFloatResult,
  degree : Int,
) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_rootn(degree)) })
}

///|
pub fn BallFloatResult::exp(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_exp_interval()) })
}

///|
pub fn BallFloatResult::exp2(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) {
    BallFloatResult::from_result(value.try_exp2_interval())
  })
}

///|
pub fn BallFloatResult::exp10(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) {
    BallFloatResult::from_result(value.try_exp10_interval())
  })
}

///|
pub fn BallFloatResult::expm1(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) {
    BallFloatResult::from_result(value.try_expm1_interval())
  })
}

///|
pub fn BallFloatResult::ln(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_ln_interval()) })
}

///|
pub fn BallFloatResult::log2(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) {
    BallFloatResult::from_result(value.try_log2_interval())
  })
}

///|
pub fn BallFloatResult::log10(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) {
    BallFloatResult::from_result(value.try_log10_interval())
  })
}

///|
pub fn BallFloatResult::log1p(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) {
    BallFloatResult::from_result(value.try_log1p_interval())
  })
}

///|
pub fn BallFloatResult::sin(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_sin_interval()) })
}

///|
pub fn BallFloatResult::cos(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_cos_interval()) })
}

///|
pub fn BallFloatResult::tan(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) { BallFloatResult::from_result(value.try_tan_interval()) })
}

///|
pub fn BallFloatResult::sinpi(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) {
    BallFloatResult::from_result(value.try_sinpi_interval())
  })
}

///|
pub fn BallFloatResult::cospi(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) {
    BallFloatResult::from_result(value.try_cospi_interval())
  })
}

///|
pub fn BallFloatResult::tanpi(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) {
    BallFloatResult::from_result(value.try_tanpi_interval())
  })
}

///|
pub fn BallFloatResult::asin(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) {
    BallFloatResult::from_result(value.try_asin_interval())
  })
}

///|
pub fn BallFloatResult::acos(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) {
    BallFloatResult::from_result(value.try_acos_interval())
  })
}

///|
pub fn BallFloatResult::atan(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) {
    BallFloatResult::from_result(value.try_atan_interval())
  })
}

///|
pub fn BallFloatResult::sinh(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) {
    BallFloatResult::from_result(value.try_sinh_interval())
  })
}

///|
pub fn BallFloatResult::cosh(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) {
    BallFloatResult::from_result(value.try_cosh_interval())
  })
}

///|
pub fn BallFloatResult::tanh(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) {
    BallFloatResult::from_result(value.try_tanh_interval())
  })
}

///|
pub fn BallFloatResult::asinh(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) {
    BallFloatResult::from_result(value.try_asinh_interval())
  })
}

///|
pub fn BallFloatResult::acosh(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) {
    BallFloatResult::from_result(value.try_acosh_interval())
  })
}

///|
pub fn BallFloatResult::atanh(self : BallFloatResult) -> BallFloatResult {
  self.bind(fn(value) {
    BallFloatResult::from_result(value.try_atanh_interval())
  })
}

///|
pub fn BallFloatResult::hypot(
  self : BallFloatResult,
  other : BallFloatResult,
) -> BallFloatResult {
  BallFloatResult::from_result(
    self.inner.bind(fn(left) {
      other.inner.bind(fn(right) { left.try_hypot(right) })
    }),
  )
}

///|
pub fn BallFloatResult::pow(
  self : BallFloatResult,
  exponent : BallFloatResult,
) -> BallFloatResult {
  self.bind(fn(base) {
    exponent.bind(fn(power) {
      BallFloatResult::from_result(base.try_pow_interval(power))
    })
  })
}

///|
pub fn BallFloatResult::atan2(
  self : BallFloatResult,
  abscissa : BallFloatResult,
) -> BallFloatResult {
  BallFloatResult::from_result(
    self.inner.bind(fn(ordinate) {
      abscissa.inner.bind(fn(horizontal) {
        ordinate.try_atan2_interval(horizontal)
      })
    }),
  )
}

///|
pub impl Add for BallFloatResult with fn add(self, other) {
  self.add(other)
}

///|
pub impl Sub for BallFloatResult with fn sub(self, other) {
  self.sub(other)
}

///|
pub impl Mul for BallFloatResult with fn mul(self, other) {
  self.mul(other)
}

///|
pub impl Div for BallFloatResult with fn div(self, other) {
  self.div(other)
}

///|
pub impl Neg for BallFloatResult with fn neg(self) {
  self.neg()
}
