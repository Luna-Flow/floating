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
/// A `Binary` or the first `ArithmeticError` of a computation: a wrapper around
/// `Result[Binary, ArithmeticError]` for pipelines whose failure channel stays
/// explicit. An operation on a failed wrapper returns that failure, and a binary
/// operation with two failed operands keeps the left one. It adds no flags,
/// context or recovery; use `binary` directly for those.
pub struct BinaryChecked {
  priv inner : Result[@binary.Binary, @def.ArithmeticError]
}

///|
/// Wraps a `Result` as it is, with no check.
pub fn BinaryChecked::from_result(
  inner : Result[@binary.Binary, @def.ArithmeticError],
) -> BinaryChecked {
  { inner, }
}

///|
/// A successful wrapper around `value`, with no check.
pub fn BinaryChecked::ok(value : @binary.Binary) -> BinaryChecked {
  { inner: Ok(value), }
}

///|
/// A failed wrapper that carries `err`.
pub fn BinaryChecked::err(err : @def.ArithmeticError) -> BinaryChecked {
  { inner: Err(err), }
}

///|
fn bin_result_precision_error(
  operation : String,
  precision : Int32,
) -> BinaryChecked? {
  if precision < 1 || precision > @binary.binary_precision_max {
    Some(
      BinaryChecked::err(
        @def.ArithmeticError::domain_error(
          "\{operation}: precision must be within 1..=\{@binary.binary_precision_max} (got \{precision})",
        ),
      ),
    )
  } else {
    None
  }
}

///|
/// The integer `value` as a `Binary` of `precision` bits (default 53). A
/// `precision` outside `1..=binary_precision_max` gives a failed wrapper with a
/// `DomainError` instead of aborting.
///
/// ```mbt check
/// test {
///   let x = @binary_checked.BinaryChecked::from_int(7)
///   inspect(x.is_ok(), content="true")
///   inspect(
///     @binary_checked.BinaryChecked::from_int(7, precision=0).is_err(),
///     content="true",
///   )
/// }
/// ```
pub fn BinaryChecked::from_int(
  value : Int32,
  precision~ : Int32 = 53,
) -> BinaryChecked {
  if bin_result_precision_error("BinaryChecked::from_int", precision)
    is Some(failure) {
    return failure
  }
  BinaryChecked::ok(@binary.Binary::from_int(value, precision~))
}

///|
/// The integer `coefficient`, negated when `negative` is true, as a `Binary` of
/// `precision` bits (default 53), rounded to `precision` bits when it does not
/// fit. A `precision`
/// outside `1..=binary_precision_max` gives a failed wrapper with a
/// `DomainError`.
pub fn BinaryChecked::from_coefficient(
  value : @binary.BinCoeff,
  precision~ : Int32 = 53,
  negative~ : Bool = false,
) -> BinaryChecked {
  if bin_result_precision_error("BinaryChecked::from_coefficient", precision)
    is Some(failure) {
    return failure
  }
  BinaryChecked::ok(
    @binary.Binary::from_coefficient(value, precision~, negative~),
  )
}

///|
/// The `Double` `value` as a `Binary` of `precision` bits (default 53). NaN and
/// the infinities give a successful NaN or infinity. A `precision` outside
/// `1..=binary_precision_max` gives a failed wrapper with a `DomainError`.
pub fn BinaryChecked::from_double(
  value : Double,
  precision~ : Int32 = 53,
) -> BinaryChecked {
  if bin_result_precision_error("BinaryChecked::from_double", precision)
    is Some(failure) {
    return failure
  }
  BinaryChecked::ok(@binary.Binary::from_double(value, precision~))
}

///|
/// The `Float` `value` as a `Binary` of `precision` bits (default 24). NaN and
/// the infinities give a successful NaN or infinity. A `precision` outside
/// `1..=binary_precision_max` gives a failed wrapper with a `DomainError`.
pub fn BinaryChecked::from_float(
  value : Float,
  precision~ : Int32 = 24,
) -> BinaryChecked {
  if bin_result_precision_error("BinaryChecked::from_float", precision)
    is Some(failure) {
    return failure
  }
  BinaryChecked::ok(@binary.Binary::from_float(value, precision~))
}

///|
/// The wrapped `Result`: the `Binary` or the first error.
pub fn BinaryChecked::result(
  self : BinaryChecked,
) -> Result[@binary.Binary, @def.ArithmeticError] {
  self.inner
}

///|
/// The error of a failed pipeline, `None` for a success: the exit that
/// `DecimalChecked` and `GdaDecimalChecked` have beside `result`, `is_ok` and
/// `is_err`.
pub fn BinaryChecked::error(self : BinaryChecked) -> @def.ArithmeticError? {
  match self.inner {
    Ok(_) => None
    Err(error) => Some(error)
  }
}

///|
/// Whether the wrapper holds a value.
pub fn BinaryChecked::is_ok(self : BinaryChecked) -> Bool {
  match self.inner {
    Ok(_) => true
    Err(_) => false
  }
}

///|
/// Whether the wrapper holds an error.
pub fn BinaryChecked::is_err(self : BinaryChecked) -> Bool {
  !self.is_ok()
}

///|
/// Applies `f` to the value of a successful wrapper; a failed one is returned
/// unchanged and `f` is not called. `f` cannot fail: use `bind` for that.
pub fn BinaryChecked::map(
  self : BinaryChecked,
  f : (@binary.Binary) -> @binary.Binary,
) -> BinaryChecked {
  BinaryChecked::from_result(self.inner.map(f))
}

///|
/// Passes the value of a successful wrapper to `f`, which may return a failed
/// wrapper; a failed one is returned unchanged and `f` is not called.
pub fn BinaryChecked::bind(
  self : BinaryChecked,
  f : (@binary.Binary) -> BinaryChecked,
) -> BinaryChecked {
  BinaryChecked::from_result(self.inner.bind(fn(value) { f(value).inner }))
}

///|
pub fn BinaryChecked::normalized(self : BinaryChecked) -> BinaryChecked {
  self.map(fn(value) { value.normalized() })
}

///|
pub fn BinaryChecked::with_precision(
  self : BinaryChecked,
  precision : Int32,
  mode : @binary.BinaryRoundingMode,
) -> BinaryChecked {
  self.map(fn(value) { value.with_precision(precision, mode) })
}

///|
/// The negation (`map` of `Binary::neg`).
pub fn BinaryChecked::neg(self : BinaryChecked) -> BinaryChecked {
  self.map(fn(value) { value.neg() })
}

///|
pub fn BinaryChecked::abs(self : BinaryChecked) -> BinaryChecked {
  self.map(fn(value) { value.abs() })
}

///|
pub fn BinaryChecked::ulp(self : BinaryChecked) -> BinaryChecked {
  self.map(fn(value) { value.ulp() })
}

///|
/// The sum, at the larger of the two operand precisions, rounded to nearest
/// even. A failed operand gives its error (the left one when both fail). The
/// operation itself never fails: `inf - inf`-like invalid cases give a
/// successful NaN. `add_ctx` is the form that reports them. This is the `+`
/// operator.
///
/// ```mbt check
/// test {
///   let one = @binary_checked.BinaryChecked::from_int(1)
///   let two = @binary_checked.BinaryChecked::from_int(2)
///   inspect((one + two).is_ok(), content="true")
/// }
/// ```
pub fn BinaryChecked::add(
  self : BinaryChecked,
  other : BinaryChecked,
) -> BinaryChecked {
  BinaryChecked::from_result(
    bin_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs + rhs }),
  )
}

///|
pub fn BinaryChecked::add_ctx(
  self : BinaryChecked,
  other : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  BinaryChecked::from_result(
    bin_result_lift2_checked(self.inner, other.inner, fn(lhs, rhs) {
      bin_result_checked_flags("add", lhs.add_ctx(rhs, context))
    }),
  )
}

///|
/// The difference, as `add` is the sum. This is the `-` operator.
pub fn BinaryChecked::sub(
  self : BinaryChecked,
  other : BinaryChecked,
) -> BinaryChecked {
  BinaryChecked::from_result(
    bin_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs - rhs }),
  )
}

///|
pub fn BinaryChecked::sub_ctx(
  self : BinaryChecked,
  other : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  BinaryChecked::from_result(
    bin_result_lift2_checked(self.inner, other.inner, fn(lhs, rhs) {
      bin_result_checked_flags("sub", lhs.sub_ctx(rhs, context))
    }),
  )
}

///|
/// The product, as `add` is the sum. This is the `*` operator.
pub fn BinaryChecked::mul(
  self : BinaryChecked,
  other : BinaryChecked,
) -> BinaryChecked {
  BinaryChecked::from_result(
    bin_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs * rhs }),
  )
}

///|
pub fn BinaryChecked::mul_ctx(
  self : BinaryChecked,
  other : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  BinaryChecked::from_result(
    bin_result_lift2_checked(self.inner, other.inner, fn(lhs, rhs) {
      bin_result_checked_flags("mul", lhs.mul_ctx(rhs, context))
    }),
  )
}

///|
/// The quotient, at the larger of the two operand precisions, rounded to
/// nearest even. A failed operand gives its error (the left one when both
/// fail). An invalid division (`0 / 0`, `inf / inf`) gives a `DomainError` and a
/// finite non-zero number divided by zero gives `DivisionByZero`. This is the
/// `/` operator.
///
/// ```mbt check
/// test {
///   let one = @binary_checked.BinaryChecked::from_int(1)
///   let zero = @binary_checked.BinaryChecked::from_int(0)
///   inspect((one / zero).is_err(), content="true")
/// }
/// ```
pub fn BinaryChecked::div(
  self : BinaryChecked,
  other : BinaryChecked,
) -> BinaryChecked {
  BinaryChecked::from_result(
    bin_result_lift2_checked(self.inner, other.inner, fn(lhs, rhs) {
      bin_result_checked_flags(
        "div",
        lhs.div_ctx(
          rhs,
          @binary.BinaryContext::new(
            precision=Int32::max(lhs.precision(), rhs.precision()),
          ),
        ),
      )
    }),
  )
}

///|
pub fn BinaryChecked::div_ctx(
  self : BinaryChecked,
  other : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  BinaryChecked::from_result(
    bin_result_lift2_checked(self.inner, other.inner, fn(lhs, rhs) {
      bin_result_checked_flags("div", lhs.div_ctx(rhs, context))
    }),
  )
}

///|
pub fn BinaryChecked::min_num(
  self : BinaryChecked,
  other : BinaryChecked,
) -> BinaryChecked {
  BinaryChecked::from_result(
    bin_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs.min_num(rhs) }),
  )
}

///|
pub fn BinaryChecked::max_num(
  self : BinaryChecked,
  other : BinaryChecked,
) -> BinaryChecked {
  BinaryChecked::from_result(
    bin_result_lift2(self.inner, other.inner, fn(lhs, rhs) { lhs.max_num(rhs) }),
  )
}

///|
pub fn BinaryChecked::clamp(
  self : BinaryChecked,
  min~ : BinaryChecked,
  max~ : BinaryChecked,
) -> BinaryChecked {
  self.bind(fn(value) {
    min.bind(fn(lo) {
      max.bind(fn(hi) {
        BinaryChecked::from_result(value.clamp_checked(min=lo, max=hi))
      })
    })
  })
}

///|
/// The square root at the precision of the operand, rounded to nearest even.
/// A negative number (`-0` excepted) gives a `DomainError`.
pub fn BinaryChecked::sqrt(self : BinaryChecked) -> BinaryChecked {
  self.bind(fn(value) {
    BinaryChecked::from_result(
      bin_result_checked_flags(
        "sqrt",
        value.sqrt_ctx(@binary.BinaryContext::new(precision=value.precision())),
      ),
    )
  })
}

///|
pub fn BinaryChecked::sqrt_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  self.bind(fn(value) {
    BinaryChecked::from_result(
      bin_result_checked_flags("sqrt", value.sqrt_ctx(context)),
    )
  })
}

///|
/// Maps the flags of a contextual result to the checked tier, as
/// the `DivChecked` trait form of `Binary` does (#262): the invalid operation
/// exception (IEEE 754-2019 section 7.2) becomes `DomainError`, divideByZero
/// (section 7.3) becomes `DivisionByZero`, `not_computed` (a result the library
/// could not compute, S4) becomes `CertificationFailure`, and every other result,
/// NaN and range exceptions included, is `Ok` (#290).
fn bin_result_checked_flags(
  operation : String,
  result : (@binary.Binary, @binary.BinaryFlags),
) -> Result[@binary.Binary, @def.ArithmeticError] {
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
  value : BinaryChecked,
  name : String,
  operation : (@binary.Binary, @binary.BinaryContext) -> Result[
    (@binary.Binary, @binary.BinaryFlags),
    @def.ArithmeticError,
  ],
) -> BinaryChecked {
  value.bind(fn(number) {
    let context = @binary.BinaryContext::new(precision=number.precision())
    BinaryChecked::from_result(
      operation(number, context).bind(fn(result) {
        bin_result_checked_flags(name, result)
      }),
    )
  })
}

///|
fn bin_result_try_elementary_ctx(
  value : BinaryChecked,
  name : String,
  context : @binary.BinaryContext,
  operation : (@binary.Binary, @binary.BinaryContext) -> Result[
    (@binary.Binary, @binary.BinaryFlags),
    @def.ArithmeticError,
  ],
) -> BinaryChecked {
  value.bind(fn(number) {
    BinaryChecked::from_result(
      operation(number, context).bind(fn(result) {
        bin_result_checked_flags(name, result)
      }),
    )
  })
}

///|
/// The exponential `e^x` at the precision of the operand. A range exception
/// (overflow, underflow) is not an error: `exp` of positive infinity is a
/// successful infinity.
pub fn BinaryChecked::exp(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "exp", fn(value, context) {
    value.try_exp_ctx(context)
  })
}

///|
pub fn BinaryChecked::exp_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "exp", context, fn(value, ctx) {
    value.try_exp_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::expm1(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "expm1", fn(value, context) {
    value.try_expm1_ctx(context)
  })
}

///|
pub fn BinaryChecked::expm1_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "expm1", context, fn(value, ctx) {
    value.try_expm1_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::exp2(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "exp2", fn(value, context) {
    value.try_exp2_ctx(context)
  })
}

///|
pub fn BinaryChecked::exp2_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "exp2", context, fn(value, ctx) {
    value.try_exp2_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::exp10(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "exp10", fn(value, context) {
    value.try_exp10_ctx(context)
  })
}

///|
pub fn BinaryChecked::exp10_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "exp10", context, fn(value, ctx) {
    value.try_exp10_ctx(ctx)
  })
}

///|
/// The natural logarithm at the precision of the operand. Zero gives
/// `DivisionByZero` and a negative number a `DomainError`.
pub fn BinaryChecked::ln(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "ln", fn(value, context) {
    value.try_ln_ctx(context)
  })
}

///|
pub fn BinaryChecked::ln_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "ln", context, fn(value, ctx) {
    value.try_ln_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::log1p(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "log1p", fn(value, context) {
    value.try_log1p_ctx(context)
  })
}

///|
pub fn BinaryChecked::log1p_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "log1p", context, fn(value, ctx) {
    value.try_log1p_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::exp2m1(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "exp2m1", fn(value, context) {
    value.try_exp2m1_ctx(context)
  })
}

///|
pub fn BinaryChecked::exp2m1_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "exp2m1", context, fn(value, ctx) {
    value.try_exp2m1_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::exp10m1(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "exp10m1", fn(value, context) {
    value.try_exp10m1_ctx(context)
  })
}

///|
pub fn BinaryChecked::exp10m1_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "exp10m1", context, fn(value, ctx) {
    value.try_exp10m1_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::log2p1(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "log2p1", fn(value, context) {
    value.try_log2p1_ctx(context)
  })
}

///|
pub fn BinaryChecked::log2p1_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "log2p1", context, fn(value, ctx) {
    value.try_log2p1_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::log10p1(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "log10p1", fn(value, context) {
    value.try_log10p1_ctx(context)
  })
}

///|
pub fn BinaryChecked::log10p1_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "log10p1", context, fn(value, ctx) {
    value.try_log10p1_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::log2(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "log2", fn(value, context) {
    value.try_log2_ctx(context)
  })
}

///|
pub fn BinaryChecked::log2_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "log2", context, fn(value, ctx) {
    value.try_log2_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::log10(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "log10", fn(value, context) {
    value.try_log10_ctx(context)
  })
}

///|
pub fn BinaryChecked::log10_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "log10", context, fn(value, ctx) {
    value.try_log10_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::hypot(
  self : BinaryChecked,
  other : BinaryChecked,
) -> BinaryChecked {
  BinaryChecked::from_result(
    bin_result_lift2_checked(self.inner, other.inner, fn(left, right) {
      let context = @binary.BinaryContext::new(
        precision=Int32::max(left.precision(), right.precision()),
      )
      left
      .try_hypot_ctx(right, context)
      .bind(fn(result) { bin_result_checked_flags("hypot", result) })
    }),
  )
}

///|
pub fn BinaryChecked::hypot_ctx(
  self : BinaryChecked,
  other : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  BinaryChecked::from_result(
    bin_result_lift2_checked(self.inner, other.inner, fn(left, right) {
      left
      .try_hypot_ctx(right, context)
      .bind(fn(result) { bin_result_checked_flags("hypot", result) })
    }),
  )
}

///|
pub fn BinaryChecked::pow_nat(
  self : BinaryChecked,
  exponent : UInt32,
) -> BinaryChecked {
  self.bind(fn(value) {
    let ctx = @lf_arith.ArithmeticContext::new(value.precision())
    BinaryChecked::from_result(
      @lf_arith.PowNatChecked::pow_nat_checked(value, exponent, ctx),
    )
  })
}

///|
pub fn BinaryChecked::pown(
  self : BinaryChecked,
  exponent : Int32,
) -> BinaryChecked {
  self.bind(fn(value) {
    BinaryChecked::from_result(
      bin_result_checked_flags(
        "pown",
        value.pown_ctx(
          exponent,
          @binary.BinaryContext::new(precision=value.precision()),
        ),
      ),
    )
  })
}

///|
pub fn BinaryChecked::pown_ctx(
  self : BinaryChecked,
  exponent : Int32,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  self.bind(fn(value) {
    BinaryChecked::from_result(
      bin_result_checked_flags("pown", value.pown_ctx(exponent, context)),
    )
  })
}

///|
pub fn BinaryChecked::rootn(
  self : BinaryChecked,
  degree : Int32,
) -> BinaryChecked {
  self.bind(fn(value) {
    let context = @binary.BinaryContext::new(precision=value.precision())
    BinaryChecked::from_result(
      value
      .try_rootn_ctx(degree, context)
      .bind(fn(result) { bin_result_checked_flags("rootn", result) }),
    )
  })
}

///|
pub fn BinaryChecked::rootn_ctx(
  self : BinaryChecked,
  degree : Int32,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  self.bind(fn(value) {
    BinaryChecked::from_result(
      value
      .try_rootn_ctx(degree, context)
      .bind(fn(result) { bin_result_checked_flags("rootn", result) }),
    )
  })
}

///|
/// `self` raised to `exponent`, at the larger of the two precisions. A failed
/// operand gives its error (the left one when both fail); `0` to a negative
/// power gives `DivisionByZero`.
pub fn BinaryChecked::pow(
  self : BinaryChecked,
  exponent : BinaryChecked,
) -> BinaryChecked {
  BinaryChecked::from_result(
    bin_result_lift2_checked(self.inner, exponent.inner, fn(base, power) {
      let context = @binary.BinaryContext::new(
        precision=Int32::max(base.precision(), power.precision()),
      )
      base
      .try_pow_ctx(power, context)
      .bind(fn(result) { bin_result_checked_flags("pow", result) })
    }),
  )
}

///|
pub fn BinaryChecked::pow_ctx(
  self : BinaryChecked,
  exponent : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  BinaryChecked::from_result(
    bin_result_lift2_checked(self.inner, exponent.inner, fn(base, power) {
      base
      .try_pow_ctx(power, context)
      .bind(fn(result) { bin_result_checked_flags("pow", result) })
    }),
  )
}

///|
pub fn BinaryChecked::rsqrt(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "rsqrt", fn(value, context) {
    value.try_rsqrt_ctx(context)
  })
}

///|
pub fn BinaryChecked::rsqrt_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "rsqrt", context, fn(value, ctx) {
    value.try_rsqrt_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::compound(
  self : BinaryChecked,
  degree : Int32,
) -> BinaryChecked {
  bin_result_try_elementary(self, "compound", fn(value, context) {
    value.try_compound_ctx(degree, context)
  })
}

///|
pub fn BinaryChecked::compound_ctx(
  self : BinaryChecked,
  degree : Int32,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "compound", context, fn(value, ctx) {
    value.try_compound_ctx(degree, ctx)
  })
}

///|
pub fn BinaryChecked::powr(
  self : BinaryChecked,
  exponent : BinaryChecked,
) -> BinaryChecked {
  BinaryChecked::from_result(
    bin_result_lift2_checked(self.inner, exponent.inner, fn(base, power) {
      let context = @binary.BinaryContext::new(
        precision=Int32::max(base.precision(), power.precision()),
      )
      base
      .try_powr_ctx(power, context)
      .bind(fn(result) { bin_result_checked_flags("powr", result) })
    }),
  )
}

///|
pub fn BinaryChecked::powr_ctx(
  self : BinaryChecked,
  exponent : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  BinaryChecked::from_result(
    bin_result_lift2_checked(self.inner, exponent.inner, fn(base, power) {
      base
      .try_powr_ctx(power, context)
      .bind(fn(result) { bin_result_checked_flags("powr", result) })
    }),
  )
}

///|
pub fn BinaryChecked::sinh(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "sinh", fn(value, context) {
    value.try_sinh_ctx(context)
  })
}

///|
pub fn BinaryChecked::sinh_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "sinh", context, fn(value, ctx) {
    value.try_sinh_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::cosh(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "cosh", fn(value, context) {
    value.try_cosh_ctx(context)
  })
}

///|
pub fn BinaryChecked::cosh_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "cosh", context, fn(value, ctx) {
    value.try_cosh_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::tanh(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "tanh", fn(value, context) {
    value.try_tanh_ctx(context)
  })
}

///|
pub fn BinaryChecked::tanh_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "tanh", context, fn(value, ctx) {
    value.try_tanh_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::asinh(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "asinh", fn(value, context) {
    value.try_asinh_ctx(context)
  })
}

///|
pub fn BinaryChecked::asinh_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "asinh", context, fn(value, ctx) {
    value.try_asinh_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::acosh(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "acosh", fn(value, context) {
    value.try_acosh_ctx(context)
  })
}

///|
pub fn BinaryChecked::acosh_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "acosh", context, fn(value, ctx) {
    value.try_acosh_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::atanh(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "atanh", fn(value, context) {
    value.try_atanh_ctx(context)
  })
}

///|
pub fn BinaryChecked::atanh_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "atanh", context, fn(value, ctx) {
    value.try_atanh_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::atan(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "atan", fn(value, context) {
    value.try_atan_ctx(context)
  })
}

///|
pub fn BinaryChecked::atan_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "atan", context, fn(value, ctx) {
    value.try_atan_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::asin(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "asin", fn(value, context) {
    value.try_asin_ctx(context)
  })
}

///|
pub fn BinaryChecked::asin_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "asin", context, fn(value, ctx) {
    value.try_asin_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::acos(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "acos", fn(value, context) {
    value.try_acos_ctx(context)
  })
}

///|
pub fn BinaryChecked::acos_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "acos", context, fn(value, ctx) {
    value.try_acos_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::asinpi(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "asinpi", fn(value, context) {
    value.try_asinpi_ctx(context)
  })
}

///|
pub fn BinaryChecked::asinpi_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "asinpi", context, fn(value, ctx) {
    value.try_asinpi_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::acospi(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "acospi", fn(value, context) {
    value.try_acospi_ctx(context)
  })
}

///|
pub fn BinaryChecked::acospi_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "acospi", context, fn(value, ctx) {
    value.try_acospi_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::atanpi(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "atanpi", fn(value, context) {
    value.try_atanpi_ctx(context)
  })
}

///|
pub fn BinaryChecked::atanpi_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "atanpi", context, fn(value, ctx) {
    value.try_atanpi_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::atan2pi(
  self : BinaryChecked,
  abscissa : BinaryChecked,
) -> BinaryChecked {
  BinaryChecked::from_result(
    bin_result_lift2_checked(self.inner, abscissa.inner, fn(
      ordinate,
      horizontal,
    ) {
      let context = @binary.BinaryContext::new(
        precision=Int32::max(ordinate.precision(), horizontal.precision()),
      )
      ordinate
      .try_atan2pi_ctx(horizontal, context)
      .bind(fn(result) { bin_result_checked_flags("atan2pi", result) })
    }),
  )
}

///|
pub fn BinaryChecked::atan2pi_ctx(
  self : BinaryChecked,
  abscissa : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  BinaryChecked::from_result(
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
pub fn BinaryChecked::atan2(
  self : BinaryChecked,
  abscissa : BinaryChecked,
) -> BinaryChecked {
  BinaryChecked::from_result(
    bin_result_lift2_checked(self.inner, abscissa.inner, fn(
      ordinate,
      horizontal,
    ) {
      let context = @binary.BinaryContext::new(
        precision=Int32::max(ordinate.precision(), horizontal.precision()),
      )
      ordinate
      .try_atan2_ctx(horizontal, context)
      .bind(fn(result) { bin_result_checked_flags("atan2", result) })
    }),
  )
}

///|
pub fn BinaryChecked::atan2_ctx(
  self : BinaryChecked,
  abscissa : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  BinaryChecked::from_result(
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
/// The sine of an argument in radians, at the precision of the operand. An
/// infinite argument gives a `DomainError`.
pub fn BinaryChecked::sin(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "sin", fn(value, context) {
    value.try_sin_ctx(context)
  })
}

///|
pub fn BinaryChecked::sin_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "sin", context, fn(value, ctx) {
    value.try_sin_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::cos(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "cos", fn(value, context) {
    value.try_cos_ctx(context)
  })
}

///|
pub fn BinaryChecked::cos_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "cos", context, fn(value, ctx) {
    value.try_cos_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::tan(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "tan", fn(value, context) {
    value.try_tan_ctx(context)
  })
}

///|
pub fn BinaryChecked::tan_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "tan", context, fn(value, ctx) {
    value.try_tan_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::sinpi(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "sinpi", fn(value, context) {
    value.try_sinpi_ctx(context)
  })
}

///|
pub fn BinaryChecked::sinpi_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "sinpi", context, fn(value, ctx) {
    value.try_sinpi_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::cospi(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "cospi", fn(value, context) {
    value.try_cospi_ctx(context)
  })
}

///|
pub fn BinaryChecked::cospi_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "cospi", context, fn(value, ctx) {
    value.try_cospi_ctx(ctx)
  })
}

///|
pub fn BinaryChecked::tanpi(self : BinaryChecked) -> BinaryChecked {
  bin_result_try_elementary(self, "tanpi", fn(value, context) {
    value.try_tanpi_ctx(context)
  })
}

///|
pub fn BinaryChecked::tanpi_ctx(
  self : BinaryChecked,
  context : @binary.BinaryContext,
) -> BinaryChecked {
  bin_result_try_elementary_ctx(self, "tanpi", context, fn(value, ctx) {
    value.try_tanpi_ctx(ctx)
  })
}

///|
pub impl Add for BinaryChecked with fn add(self, other) {
  self.add(other)
}

///|
pub impl Sub for BinaryChecked with fn sub(self, other) {
  self.sub(other)
}

///|
pub impl Mul for BinaryChecked with fn mul(self, other) {
  self.mul(other)
}

///|
pub impl Div for BinaryChecked with fn div(self, other) {
  self.div(other)
}

///|
pub impl Neg for BinaryChecked with fn neg(self) {
  self.neg()
}
