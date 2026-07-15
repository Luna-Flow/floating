///|
fn[A, B, E, C] bin_result_lift2(
  left : Result[A, E],
  right : Result[B, E],
  combine : (A, B) -> C,
) -> Result[C, E] {
  left.bind(fn(lhs) { right.map(fn(rhs) { combine(lhs, rhs) }) })
}

///|
fn[A, B, E, C] bin_result_lift2_checked(
  left : Result[A, E],
  right : Result[B, E],
  combine : (A, B) -> Result[C, E],
) -> Result[C, E] {
  left.bind(fn(lhs) { right.bind(fn(rhs) { combine(lhs, rhs) }) })
}

///|
pub struct BinFloatResult {
  priv inner : Result[@bin_float.BinFloat, @def.ArithmeticError]
}

///|
pub fn BinFloatResult::from_result(
  inner : Result[@bin_float.BinFloat, @def.ArithmeticError],
) -> BinFloatResult {
  { inner, }
}

///|
pub fn BinFloatResult::ok(value : @bin_float.BinFloat) -> BinFloatResult {
  { inner: Ok(value) }
}

///|
pub fn BinFloatResult::err(err : @def.ArithmeticError) -> BinFloatResult {
  { inner: Err(err) }
}

///|
pub fn BinFloatResult::from_int(
  value : Int,
  precision? : Int = 53,
) -> BinFloatResult {
  BinFloatResult::ok(@bin_float.BinFloat::from_int(value, precision~))
}

///|
pub fn BinFloatResult::from_coefficient(
  value : @bin_float.BinCoeff,
  precision? : Int = 53,
  negative? : Bool = false,
) -> BinFloatResult {
  BinFloatResult::ok(
    @bin_float.BinFloat::from_coefficient(value, precision~, negative~),
  )
}

///|
pub fn BinFloatResult::from_double(
  value : Double,
  precision? : Int = 53,
) -> BinFloatResult {
  BinFloatResult::ok(@bin_float.BinFloat::from_double(value, precision~))
}

///|
pub fn BinFloatResult::from_float(
  value : Float,
  precision? : Int = 24,
) -> BinFloatResult {
  BinFloatResult::ok(@bin_float.BinFloat::from_float(value, precision~))
}

///|
pub fn BinFloatResult::result(
  self : BinFloatResult,
) -> Result[@bin_float.BinFloat, @def.ArithmeticError] {
  self.inner
}

///|
pub fn BinFloatResult::is_ok(self : BinFloatResult) -> Bool {
  match self.inner {
    Ok(_) => true
    Err(_) => false
  }
}

///|
pub fn BinFloatResult::is_err(self : BinFloatResult) -> Bool {
  !self.is_ok()
}

///|
pub fn BinFloatResult::map(
  self : BinFloatResult,
  f : (@bin_float.BinFloat) -> @bin_float.BinFloat,
) -> BinFloatResult {
  BinFloatResult::from_result(self.inner.map(f))
}

///|
pub fn BinFloatResult::bind(
  self : BinFloatResult,
  f : (@bin_float.BinFloat) -> BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(self.inner.bind(fn(value) { f(value).inner }))
}

///|
#deprecated("Use bind instead")
pub fn BinFloatResult::flat_map(
  self : BinFloatResult,
  f : (@bin_float.BinFloat) -> BinFloatResult,
) -> BinFloatResult {
  self.bind(f)
}

///|
pub fn BinFloatResult::normalized(self : BinFloatResult) -> BinFloatResult {
  self.map(fn(value) { value.normalized() })
}

///|
pub fn BinFloatResult::with_precision(
  self : BinFloatResult,
  precision : Int,
  mode : @def.RoundingMode,
) -> BinFloatResult {
  self.map(fn(value) { value.with_precision(precision, mode) })
}

///|
pub fn BinFloatResult::neg(self : BinFloatResult) -> BinFloatResult {
  self.map(fn(value) { value.neg() })
}

///|
pub fn BinFloatResult::abs(self : BinFloatResult) -> BinFloatResult {
  self.map(fn(value) { value.abs() })
}

///|
pub fn BinFloatResult::ulp(self : BinFloatResult) -> BinFloatResult {
  self.map(fn(value) { value.ulp() })
}

///|
pub fn BinFloatResult::add(
  self : BinFloatResult,
  other : BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs + rhs }),
  )
}

///|
pub fn BinFloatResult::add_ctx(
  self : BinFloatResult,
  other : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2_checked(self.inner, other.inner, fn(lhs, rhs) {
      Ok(lhs.add_ctx(rhs, context).0)
    }),
  )
}

///|
pub fn BinFloatResult::sub(
  self : BinFloatResult,
  other : BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs - rhs }),
  )
}

///|
pub fn BinFloatResult::sub_ctx(
  self : BinFloatResult,
  other : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2_checked(self.inner, other.inner, fn(lhs, rhs) {
      Ok(lhs.sub_ctx(rhs, context).0)
    }),
  )
}

///|
pub fn BinFloatResult::mul(
  self : BinFloatResult,
  other : BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs * rhs }),
  )
}

///|
pub fn BinFloatResult::mul_ctx(
  self : BinFloatResult,
  other : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2_checked(self.inner, other.inner, fn(lhs, rhs) {
      Ok(lhs.mul_ctx(rhs, context).0)
    }),
  )
}

///|
pub fn BinFloatResult::div(
  self : BinFloatResult,
  other : BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2_checked(self.inner, other.inner, fn(lhs, rhs) {
      lhs.div_checked(rhs)
    }),
  )
}

///|
pub fn BinFloatResult::div_ctx(
  self : BinFloatResult,
  other : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2_checked(self.inner, other.inner, fn(lhs, rhs) {
      lhs.div_ctx(rhs, context).0 |> Ok
    }),
  )
}

///|
pub fn BinFloatResult::min(
  self : BinFloatResult,
  other : BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs.min(rhs) }),
  )
}

///|
pub fn BinFloatResult::max(
  self : BinFloatResult,
  other : BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs.max(rhs) }),
  )
}

///|
pub fn BinFloatResult::clamp(
  self : BinFloatResult,
  min~ : BinFloatResult,
  max~ : BinFloatResult,
) -> BinFloatResult {
  self.bind(fn(value) {
    min.bind(fn(lo) {
      max.bind(fn(hi) {
        BinFloatResult::from_result(value.clamp_checked(min=lo, max=hi))
      })
    })
  })
}

///|
pub fn BinFloatResult::sqrt(self : BinFloatResult) -> BinFloatResult {
  self.bind(fn(value) { BinFloatResult::from_result(value.sqrt()) })
}

///|
pub fn BinFloatResult::sqrt_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  self.bind(fn(value) { BinFloatResult::ok(value.sqrt_ctx(context).0) })
}

///|
fn bin_result_try_elementary(
  value : BinFloatResult,
  operation : (@bin_float.BinFloat, @bin_float.BinaryContext) -> Result[
    (@bin_float.BinFloat, @bin_float.BinaryFlags),
    @def.ArithmeticError,
  ],
) -> BinFloatResult {
  value.bind(fn(number) {
    let context = @bin_float.BinaryContext::unbounded(number.precision())
    BinFloatResult::from_result(
      operation(number, context).map(fn(result) { result.0 }),
    )
  })
}

///|
fn bin_result_try_elementary_ctx(
  value : BinFloatResult,
  context : @bin_float.BinaryContext,
  operation : (@bin_float.BinFloat, @bin_float.BinaryContext) -> Result[
    (@bin_float.BinFloat, @bin_float.BinaryFlags),
    @def.ArithmeticError,
  ],
) -> BinFloatResult {
  value.bind(fn(number) {
    BinFloatResult::from_result(
      operation(number, context).map(fn(result) { result.0 }),
    )
  })
}

///|
pub fn BinFloatResult::exp(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_exp_ctx(context)
  })
}

///|
pub fn BinFloatResult::exp_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_exp_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::expm1(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_expm1_ctx(context)
  })
}

///|
pub fn BinFloatResult::expm1_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_expm1_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::exp2(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_exp2_ctx(context)
  })
}

///|
pub fn BinFloatResult::exp2_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_exp2_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::exp10(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_exp10_ctx(context)
  })
}

///|
pub fn BinFloatResult::exp10_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_exp10_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::exp_ln(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_exp_ln_ctx(context)
  })
}

///|
pub fn BinFloatResult::exp_ln_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_exp_ln_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::ln(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_ln_ctx(context)
  })
}

///|
pub fn BinFloatResult::ln_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_ln_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::log1p(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_log1p_ctx(context)
  })
}

///|
pub fn BinFloatResult::log1p_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_log1p_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::log2(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_log2_ctx(context)
  })
}

///|
pub fn BinFloatResult::log2_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_log2_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::log10(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_log10_ctx(context)
  })
}

///|
pub fn BinFloatResult::log10_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_log10_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::hypot(
  self : BinFloatResult,
  other : BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2_checked(self.inner, other.inner, fn(left, right) {
      let context = @bin_float.BinaryContext::unbounded(
        Int::max(left.precision(), right.precision()),
      )
      left.try_hypot_ctx(right, context).map(fn(result) { result.0 })
    }),
  )
}

///|
pub fn BinFloatResult::hypot_ctx(
  self : BinFloatResult,
  other : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2_checked(self.inner, other.inner, fn(left, right) {
      left.try_hypot_ctx(right, context).map(fn(result) { result.0 })
    }),
  )
}

///|
pub fn BinFloatResult::pow_nat(
  self : BinFloatResult,
  exponent : UInt,
) -> BinFloatResult {
  self.bind(fn(value) {
    let ctx = @lf_arith.ArithmeticContext::new(value.precision())
    BinFloatResult::from_result(
      @lf_arith.PowNatChecked::pow_nat_checked(value, exponent, ctx),
    )
  })
}

///|
pub fn BinFloatResult::pow_int(
  self : BinFloatResult,
  exponent : Int,
) -> BinFloatResult {
  self.bind(fn(value) { BinFloatResult::from_result(value.pow_int(exponent)) })
}

///|
pub fn BinFloatResult::pow_int_ctx(
  self : BinFloatResult,
  exponent : Int,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  self.bind(fn(value) {
    BinFloatResult::ok(value.pow_int_ctx(exponent, context).0)
  })
}

///|
pub fn BinFloatResult::pown(
  self : BinFloatResult,
  exponent : Int,
) -> BinFloatResult {
  self.bind(fn(value) { BinFloatResult::from_result(value.pown(exponent)) })
}

///|
pub fn BinFloatResult::pown_ctx(
  self : BinFloatResult,
  exponent : Int,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  self.bind(fn(value) {
    BinFloatResult::ok(value.pown_ctx(exponent, context).0)
  })
}

///|
pub fn BinFloatResult::rootn(
  self : BinFloatResult,
  degree : Int,
) -> BinFloatResult {
  self.bind(fn(value) {
    let context = @bin_float.BinaryContext::unbounded(value.precision())
    BinFloatResult::from_result(
      value.try_rootn_ctx(degree, context).map(fn(result) { result.0 }),
    )
  })
}

///|
pub fn BinFloatResult::rootn_ctx(
  self : BinFloatResult,
  degree : Int,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  self.bind(fn(value) {
    BinFloatResult::from_result(
      value.try_rootn_ctx(degree, context).map(fn(result) { result.0 }),
    )
  })
}

///|
pub fn BinFloatResult::pow(
  self : BinFloatResult,
  exponent : BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2_checked(self.inner, exponent.inner, fn(base, power) {
      let context = @bin_float.BinaryContext::unbounded(
        Int::max(base.precision(), power.precision()),
      )
      base.try_pow_ctx(power, context).map(fn(result) { result.0 })
    }),
  )
}

///|
pub fn BinFloatResult::pow_ctx(
  self : BinFloatResult,
  exponent : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2_checked(self.inner, exponent.inner, fn(base, power) {
      base.try_pow_ctx(power, context).map(fn(result) { result.0 })
    }),
  )
}

///|
pub fn BinFloatResult::sinh(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_sinh_ctx(context)
  })
}

///|
pub fn BinFloatResult::sinh_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_sinh_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::cosh(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_cosh_ctx(context)
  })
}

///|
pub fn BinFloatResult::cosh_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_cosh_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::tanh(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_tanh_ctx(context)
  })
}

///|
pub fn BinFloatResult::tanh_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_tanh_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::asinh(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_asinh_ctx(context)
  })
}

///|
pub fn BinFloatResult::asinh_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_asinh_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::acosh(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_acosh_ctx(context)
  })
}

///|
pub fn BinFloatResult::acosh_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_acosh_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::atanh(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_atanh_ctx(context)
  })
}

///|
pub fn BinFloatResult::atanh_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_atanh_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::atan(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_atan_ctx(context)
  })
}

///|
pub fn BinFloatResult::atan_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_atan_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::asin(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_asin_ctx(context)
  })
}

///|
pub fn BinFloatResult::asin_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_asin_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::acos(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_acos_ctx(context)
  })
}

///|
pub fn BinFloatResult::acos_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_acos_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::atan2(
  self : BinFloatResult,
  abscissa : BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2_checked(self.inner, abscissa.inner, fn(
      ordinate,
      horizontal,
    ) {
      let context = @bin_float.BinaryContext::unbounded(
        Int::max(ordinate.precision(), horizontal.precision()),
      )
      ordinate.try_atan2_ctx(horizontal, context).map(fn(result) { result.0 })
    }),
  )
}

///|
pub fn BinFloatResult::atan2_ctx(
  self : BinFloatResult,
  abscissa : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2_checked(self.inner, abscissa.inner, fn(
      ordinate,
      horizontal,
    ) {
      ordinate.try_atan2_ctx(horizontal, context).map(fn(result) { result.0 })
    }),
  )
}

///|
pub fn BinFloatResult::sin(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_sin_ctx(context)
  })
}

///|
pub fn BinFloatResult::sin_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_sin_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::cos(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_cos_ctx(context)
  })
}

///|
pub fn BinFloatResult::cos_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_cos_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::tan(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_tan_ctx(context)
  })
}

///|
pub fn BinFloatResult::tan_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_tan_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::sinpi(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_sinpi_ctx(context)
  })
}

///|
pub fn BinFloatResult::sinpi_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_sinpi_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::cospi(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_cospi_ctx(context)
  })
}

///|
pub fn BinFloatResult::cospi_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_cospi_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::tanpi(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, fn(value, context) {
    value.try_tanpi_ctx(context)
  })
}

///|
pub fn BinFloatResult::tanpi_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, context, fn(value, ctx) {
    value.try_tanpi_ctx(ctx)
  })
}

///|
pub impl Add for BinFloatResult with fn add(self, other) {
  self.add(other)
}

///|
pub impl Sub for BinFloatResult with fn sub(self, other) {
  self.sub(other)
}

///|
pub impl Mul for BinFloatResult with fn mul(self, other) {
  self.mul(other)
}

///|
pub impl Div for BinFloatResult with fn div(self, other) {
  self.div(other)
}

///|
pub impl Neg for BinFloatResult with fn neg(self) {
  self.neg()
}
