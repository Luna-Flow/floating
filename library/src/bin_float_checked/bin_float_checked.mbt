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
  { inner: Ok(value), }
}

///|
pub fn BinFloatResult::err(err : @def.ArithmeticError) -> BinFloatResult {
  { inner: Err(err), }
}

///|
fn bin_result_precision_error(
  operation : String,
  precision : Int32,
) -> BinFloatResult? {
  if precision < 1 || precision > @bin_float.binary_precision_max {
    Some(
      BinFloatResult::err(
        @def.ArithmeticError::domain_error(
          "\{operation}: precision must be within 1..=\{@bin_float.binary_precision_max} (got \{precision})",
        ),
      ),
    )
  } else {
    None
  }
}

///|
pub fn BinFloatResult::from_int(
  value : Int32,
  precision~ : Int32 = 53,
) -> BinFloatResult {
  if bin_result_precision_error("BinFloatResult::from_int", precision)
    is Some(failure) {
    return failure
  }
  BinFloatResult::ok(@bin_float.BinFloat::from_int(value, precision~))
}

///|
pub fn BinFloatResult::from_coefficient(
  value : @bin_float.BinCoeff,
  precision~ : Int32 = 53,
  negative~ : Bool = false,
) -> BinFloatResult {
  if bin_result_precision_error("BinFloatResult::from_coefficient", precision)
    is Some(failure) {
    return failure
  }
  BinFloatResult::ok(
    @bin_float.BinFloat::from_coefficient(value, precision~, negative~),
  )
}

///|
pub fn BinFloatResult::from_double(
  value : Double,
  precision~ : Int32 = 53,
) -> BinFloatResult {
  if bin_result_precision_error("BinFloatResult::from_double", precision)
    is Some(failure) {
    return failure
  }
  BinFloatResult::ok(@bin_float.BinFloat::from_double(value, precision~))
}

///|
pub fn BinFloatResult::from_float(
  value : Float,
  precision~ : Int32 = 24,
) -> BinFloatResult {
  if bin_result_precision_error("BinFloatResult::from_float", precision)
    is Some(failure) {
    return failure
  }
  BinFloatResult::ok(@bin_float.BinFloat::from_float(value, precision~))
}

///|
pub fn BinFloatResult::result(
  self : BinFloatResult,
) -> Result[@bin_float.BinFloat, @def.ArithmeticError] {
  self.inner
}

///|
/// The error of a failed pipeline, `None` for a success: the exit that
/// `DecimalChecked` and `GdaDecimalChecked` have beside `result`, `is_ok` and
/// `is_err`.
pub fn BinFloatResult::error(self : BinFloatResult) -> @def.ArithmeticError? {
  match self.inner {
    Ok(_) => None
    Err(error) => Some(error)
  }
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
pub fn BinFloatResult::normalized(self : BinFloatResult) -> BinFloatResult {
  self.map(fn(value) { value.normalized() })
}

///|
pub fn BinFloatResult::with_precision(
  self : BinFloatResult,
  precision : Int32,
  mode : @bin_float.BinaryRoundingMode,
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
      bin_result_checked_flags("add", lhs.add_ctx(rhs, context))
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
      bin_result_checked_flags("sub", lhs.sub_ctx(rhs, context))
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
      bin_result_checked_flags("mul", lhs.mul_ctx(rhs, context))
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
      bin_result_checked_flags(
        "div",
        lhs.div_ctx(
          rhs,
          @bin_float.BinaryContext::new(
            precision=Int32::max(lhs.precision(), rhs.precision()),
          ),
        ),
      )
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
      bin_result_checked_flags("div", lhs.div_ctx(rhs, context))
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
  self.bind(fn(value) {
    BinFloatResult::from_result(
      bin_result_checked_flags(
        "sqrt",
        value.sqrt_ctx(
          @bin_float.BinaryContext::new(precision=value.precision()),
        ),
      ),
    )
  })
}

///|
pub fn BinFloatResult::sqrt_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  self.bind(fn(value) {
    BinFloatResult::from_result(
      bin_result_checked_flags("sqrt", value.sqrt_ctx(context)),
    )
  })
}

///|
/// Maps the flags of a contextual result to the checked tier, as
/// the `DivChecked` trait form of `BinFloat` does (#262): the invalid operation
/// exception (IEEE 754-2019 section 7.2) becomes `DomainError`, divideByZero
/// (section 7.3) becomes `DivisionByZero`, `not_computed` (a result the library
/// could not compute, S4) becomes `CertificationFailure`, and every other result,
/// NaN and range exceptions included, is `Ok` (#290).
fn bin_result_checked_flags(
  operation : String,
  result : (@bin_float.BinFloat, @bin_float.BinaryFlags),
) -> Result[@bin_float.BinFloat, @def.ArithmeticError] {
  let (value, flags) = result
  if flags.division_by_zero() {
    Err(
      @def.ArithmeticError::division_by_zero(operation + ": division by zero"),
    )
  } else if flags.not_computed() {
    Err(
      @def.ArithmeticError::certification_failure(
        @def.CertificationFailureDetail::new(
          operation,
          @def.CertificationStage::RangeReduction,
          @def.CertificationFailureReason::ResourceLimit,
          0,
          0,
          0,
        ),
      ),
    )
  } else if flags.invalid_operation() {
    Err(@def.ArithmeticError::domain_error(operation + ": invalid operation"))
  } else {
    Ok(value)
  }
}

///|
fn bin_result_try_elementary(
  value : BinFloatResult,
  name : String,
  operation : (@bin_float.BinFloat, @bin_float.BinaryContext) -> Result[
    (@bin_float.BinFloat, @bin_float.BinaryFlags),
    @def.ArithmeticError,
  ],
) -> BinFloatResult {
  value.bind(fn(number) {
    let context = @bin_float.BinaryContext::new(precision=number.precision())
    BinFloatResult::from_result(
      operation(number, context).bind(fn(result) {
        bin_result_checked_flags(name, result)
      }),
    )
  })
}

///|
fn bin_result_try_elementary_ctx(
  value : BinFloatResult,
  name : String,
  context : @bin_float.BinaryContext,
  operation : (@bin_float.BinFloat, @bin_float.BinaryContext) -> Result[
    (@bin_float.BinFloat, @bin_float.BinaryFlags),
    @def.ArithmeticError,
  ],
) -> BinFloatResult {
  value.bind(fn(number) {
    BinFloatResult::from_result(
      operation(number, context).bind(fn(result) {
        bin_result_checked_flags(name, result)
      }),
    )
  })
}

///|
pub fn BinFloatResult::exp(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "exp", fn(value, context) {
    value.try_exp_ctx(context)
  })
}

///|
pub fn BinFloatResult::exp_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "exp", context, fn(value, ctx) {
    value.try_exp_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::expm1(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "expm1", fn(value, context) {
    value.try_expm1_ctx(context)
  })
}

///|
pub fn BinFloatResult::expm1_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "expm1", context, fn(value, ctx) {
    value.try_expm1_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::exp2(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "exp2", fn(value, context) {
    value.try_exp2_ctx(context)
  })
}

///|
pub fn BinFloatResult::exp2_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "exp2", context, fn(value, ctx) {
    value.try_exp2_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::exp10(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "exp10", fn(value, context) {
    value.try_exp10_ctx(context)
  })
}

///|
pub fn BinFloatResult::exp10_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "exp10", context, fn(value, ctx) {
    value.try_exp10_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::ln(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "ln", fn(value, context) {
    value.try_ln_ctx(context)
  })
}

///|
pub fn BinFloatResult::ln_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "ln", context, fn(value, ctx) {
    value.try_ln_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::log1p(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "log1p", fn(value, context) {
    value.try_log1p_ctx(context)
  })
}

///|
pub fn BinFloatResult::log1p_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "log1p", context, fn(value, ctx) {
    value.try_log1p_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::exp2m1(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "exp2m1", fn(value, context) {
    value.try_exp2m1_ctx(context)
  })
}

///|
pub fn BinFloatResult::exp2m1_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "exp2m1", context, fn(value, ctx) {
    value.try_exp2m1_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::exp10m1(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "exp10m1", fn(value, context) {
    value.try_exp10m1_ctx(context)
  })
}

///|
pub fn BinFloatResult::exp10m1_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "exp10m1", context, fn(value, ctx) {
    value.try_exp10m1_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::log2p1(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "log2p1", fn(value, context) {
    value.try_log2p1_ctx(context)
  })
}

///|
pub fn BinFloatResult::log2p1_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "log2p1", context, fn(value, ctx) {
    value.try_log2p1_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::log10p1(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "log10p1", fn(value, context) {
    value.try_log10p1_ctx(context)
  })
}

///|
pub fn BinFloatResult::log10p1_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "log10p1", context, fn(value, ctx) {
    value.try_log10p1_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::log2(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "log2", fn(value, context) {
    value.try_log2_ctx(context)
  })
}

///|
pub fn BinFloatResult::log2_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "log2", context, fn(value, ctx) {
    value.try_log2_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::log10(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "log10", fn(value, context) {
    value.try_log10_ctx(context)
  })
}

///|
pub fn BinFloatResult::log10_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "log10", context, fn(value, ctx) {
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
      let context = @bin_float.BinaryContext::new(
        precision=Int32::max(left.precision(), right.precision()),
      )
      left
      .try_hypot_ctx(right, context)
      .bind(fn(result) { bin_result_checked_flags("hypot", result) })
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
      left
      .try_hypot_ctx(right, context)
      .bind(fn(result) { bin_result_checked_flags("hypot", result) })
    }),
  )
}

///|
pub fn BinFloatResult::pow_nat(
  self : BinFloatResult,
  exponent : UInt32,
) -> BinFloatResult {
  self.bind(fn(value) {
    let ctx = @lf_arith.ArithmeticContext::new(value.precision())
    BinFloatResult::from_result(
      @lf_arith.PowNatChecked::pow_nat_checked(value, exponent, ctx),
    )
  })
}

///|
pub fn BinFloatResult::pown(
  self : BinFloatResult,
  exponent : Int32,
) -> BinFloatResult {
  self.bind(fn(value) {
    BinFloatResult::from_result(
      bin_result_checked_flags(
        "pown",
        value.pown_ctx(
          exponent,
          @bin_float.BinaryContext::new(precision=value.precision()),
        ),
      ),
    )
  })
}

///|
pub fn BinFloatResult::pown_ctx(
  self : BinFloatResult,
  exponent : Int32,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  self.bind(fn(value) {
    BinFloatResult::from_result(
      bin_result_checked_flags("pown", value.pown_ctx(exponent, context)),
    )
  })
}

///|
pub fn BinFloatResult::rootn(
  self : BinFloatResult,
  degree : Int32,
) -> BinFloatResult {
  self.bind(fn(value) {
    let context = @bin_float.BinaryContext::new(precision=value.precision())
    BinFloatResult::from_result(
      value
      .try_rootn_ctx(degree, context)
      .bind(fn(result) { bin_result_checked_flags("rootn", result) }),
    )
  })
}

///|
pub fn BinFloatResult::rootn_ctx(
  self : BinFloatResult,
  degree : Int32,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  self.bind(fn(value) {
    BinFloatResult::from_result(
      value
      .try_rootn_ctx(degree, context)
      .bind(fn(result) { bin_result_checked_flags("rootn", result) }),
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
      let context = @bin_float.BinaryContext::new(
        precision=Int32::max(base.precision(), power.precision()),
      )
      base
      .try_pow_ctx(power, context)
      .bind(fn(result) { bin_result_checked_flags("pow", result) })
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
      base
      .try_pow_ctx(power, context)
      .bind(fn(result) { bin_result_checked_flags("pow", result) })
    }),
  )
}

///|
pub fn BinFloatResult::rsqrt(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "rsqrt", fn(value, context) {
    value.try_rsqrt_ctx(context)
  })
}

///|
pub fn BinFloatResult::rsqrt_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "rsqrt", context, fn(value, ctx) {
    value.try_rsqrt_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::compound(
  self : BinFloatResult,
  degree : Int32,
) -> BinFloatResult {
  bin_result_try_elementary(self, "compound", fn(value, context) {
    value.try_compound_ctx(degree, context)
  })
}

///|
pub fn BinFloatResult::compound_ctx(
  self : BinFloatResult,
  degree : Int32,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "compound", context, fn(value, ctx) {
    value.try_compound_ctx(degree, ctx)
  })
}

///|
pub fn BinFloatResult::powr(
  self : BinFloatResult,
  exponent : BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2_checked(self.inner, exponent.inner, fn(base, power) {
      let context = @bin_float.BinaryContext::new(
        precision=Int32::max(base.precision(), power.precision()),
      )
      base
      .try_powr_ctx(power, context)
      .bind(fn(result) { bin_result_checked_flags("powr", result) })
    }),
  )
}

///|
pub fn BinFloatResult::powr_ctx(
  self : BinFloatResult,
  exponent : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2_checked(self.inner, exponent.inner, fn(base, power) {
      base
      .try_powr_ctx(power, context)
      .bind(fn(result) { bin_result_checked_flags("powr", result) })
    }),
  )
}

///|
pub fn BinFloatResult::sinh(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "sinh", fn(value, context) {
    value.try_sinh_ctx(context)
  })
}

///|
pub fn BinFloatResult::sinh_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "sinh", context, fn(value, ctx) {
    value.try_sinh_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::cosh(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "cosh", fn(value, context) {
    value.try_cosh_ctx(context)
  })
}

///|
pub fn BinFloatResult::cosh_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "cosh", context, fn(value, ctx) {
    value.try_cosh_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::tanh(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "tanh", fn(value, context) {
    value.try_tanh_ctx(context)
  })
}

///|
pub fn BinFloatResult::tanh_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "tanh", context, fn(value, ctx) {
    value.try_tanh_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::asinh(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "asinh", fn(value, context) {
    value.try_asinh_ctx(context)
  })
}

///|
pub fn BinFloatResult::asinh_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "asinh", context, fn(value, ctx) {
    value.try_asinh_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::acosh(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "acosh", fn(value, context) {
    value.try_acosh_ctx(context)
  })
}

///|
pub fn BinFloatResult::acosh_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "acosh", context, fn(value, ctx) {
    value.try_acosh_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::atanh(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "atanh", fn(value, context) {
    value.try_atanh_ctx(context)
  })
}

///|
pub fn BinFloatResult::atanh_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "atanh", context, fn(value, ctx) {
    value.try_atanh_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::atan(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "atan", fn(value, context) {
    value.try_atan_ctx(context)
  })
}

///|
pub fn BinFloatResult::atan_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "atan", context, fn(value, ctx) {
    value.try_atan_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::asin(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "asin", fn(value, context) {
    value.try_asin_ctx(context)
  })
}

///|
pub fn BinFloatResult::asin_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "asin", context, fn(value, ctx) {
    value.try_asin_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::acos(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "acos", fn(value, context) {
    value.try_acos_ctx(context)
  })
}

///|
pub fn BinFloatResult::acos_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "acos", context, fn(value, ctx) {
    value.try_acos_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::asinpi(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "asinpi", fn(value, context) {
    value.try_asinpi_ctx(context)
  })
}

///|
pub fn BinFloatResult::asinpi_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "asinpi", context, fn(value, ctx) {
    value.try_asinpi_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::acospi(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "acospi", fn(value, context) {
    value.try_acospi_ctx(context)
  })
}

///|
pub fn BinFloatResult::acospi_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "acospi", context, fn(value, ctx) {
    value.try_acospi_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::atanpi(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "atanpi", fn(value, context) {
    value.try_atanpi_ctx(context)
  })
}

///|
pub fn BinFloatResult::atanpi_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "atanpi", context, fn(value, ctx) {
    value.try_atanpi_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::atan2pi(
  self : BinFloatResult,
  abscissa : BinFloatResult,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2_checked(self.inner, abscissa.inner, fn(
      ordinate,
      horizontal,
    ) {
      let context = @bin_float.BinaryContext::new(
        precision=Int32::max(ordinate.precision(), horizontal.precision()),
      )
      ordinate
      .try_atan2pi_ctx(horizontal, context)
      .bind(fn(result) { bin_result_checked_flags("atan2pi", result) })
    }),
  )
}

///|
pub fn BinFloatResult::atan2pi_ctx(
  self : BinFloatResult,
  abscissa : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  BinFloatResult::from_result(
    bin_result_lift2_checked(self.inner, abscissa.inner, fn(
      ordinate,
      horizontal,
    ) {
      ordinate
      .try_atan2pi_ctx(horizontal, context)
      .bind(fn(result) { bin_result_checked_flags("atan2pi", result) })
    }),
  )
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
      let context = @bin_float.BinaryContext::new(
        precision=Int32::max(ordinate.precision(), horizontal.precision()),
      )
      ordinate
      .try_atan2_ctx(horizontal, context)
      .bind(fn(result) { bin_result_checked_flags("atan2", result) })
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
      ordinate
      .try_atan2_ctx(horizontal, context)
      .bind(fn(result) { bin_result_checked_flags("atan2", result) })
    }),
  )
}

///|
pub fn BinFloatResult::sin(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "sin", fn(value, context) {
    value.try_sin_ctx(context)
  })
}

///|
pub fn BinFloatResult::sin_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "sin", context, fn(value, ctx) {
    value.try_sin_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::cos(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "cos", fn(value, context) {
    value.try_cos_ctx(context)
  })
}

///|
pub fn BinFloatResult::cos_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "cos", context, fn(value, ctx) {
    value.try_cos_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::tan(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "tan", fn(value, context) {
    value.try_tan_ctx(context)
  })
}

///|
pub fn BinFloatResult::tan_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "tan", context, fn(value, ctx) {
    value.try_tan_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::sinpi(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "sinpi", fn(value, context) {
    value.try_sinpi_ctx(context)
  })
}

///|
pub fn BinFloatResult::sinpi_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "sinpi", context, fn(value, ctx) {
    value.try_sinpi_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::cospi(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "cospi", fn(value, context) {
    value.try_cospi_ctx(context)
  })
}

///|
pub fn BinFloatResult::cospi_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "cospi", context, fn(value, ctx) {
    value.try_cospi_ctx(ctx)
  })
}

///|
pub fn BinFloatResult::tanpi(self : BinFloatResult) -> BinFloatResult {
  bin_result_try_elementary(self, "tanpi", fn(value, context) {
    value.try_tanpi_ctx(context)
  })
}

///|
pub fn BinFloatResult::tanpi_ctx(
  self : BinFloatResult,
  context : @bin_float.BinaryContext,
) -> BinFloatResult {
  bin_result_try_elementary_ctx(self, "tanpi", context, fn(value, ctx) {
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
