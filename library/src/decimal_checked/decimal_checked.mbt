///|
/// The state of an IEEE 754 decimal pipeline: the current value, one
/// `DecimalContext`, the flags raised by the latest step (`raised`), the flags
/// accumulated over the steps (`flags`) and an optional `ArithmeticError`. Each
/// operation applies the `Decimal::*_ctx` operation of the same name in the
/// context of the left operand and returns a new state; nothing is mutated.
/// Exceptional results (NaN, infinity, a rounded value) are values that set
/// flags; an error is recorded when an elementary function cannot be certified,
/// and an operation on a state with an error returns it.
pub struct DecimalChecked {
  priv value_ : @decimal.Decimal
  priv context_ : @decimal.DecimalContext
  priv raised_ : @decimal.DecimalFlags
  priv flags_ : @decimal.DecimalFlags
  priv error_ : @def.ArithmeticError?
}

///|
fn DecimalChecked::record(
  self : DecimalChecked,
  outcome : (@decimal.Decimal, @decimal.DecimalFlags),
) -> DecimalChecked {
  guard self.error_ is None else { return self }
  let (value, raised) = outcome
  {
    value_: value,
    context_: self.context_,
    raised_: raised,
    flags_: self.flags_.combine(raised),
    error_: None,
  }
}

///|
fn DecimalChecked::record_result(
  self : DecimalChecked,
  outcome : Result[
    (@decimal.Decimal, @decimal.DecimalFlags),
    @def.ArithmeticError,
  ],
) -> DecimalChecked {
  guard self.error_ is None else { return self }
  match outcome {
    Ok(value) => self.record(value)
    Err(error) => { ..self, error_: Some(error), }
  }
}

///|
/// The operation with a pipeline as its right operand. An error of the left
/// pipeline stays; an error of the right one is taken before the operation
/// runs, and the value of the left pipeline is kept. The operation runs in the
/// context of the left pipeline, and the conditions of the right pipeline join
/// `raised` and `flags` (the pattern of `GdaDecimalChecked`).
fn DecimalChecked::join(
  self : DecimalChecked,
  other : DecimalChecked,
  operation : (@decimal.Decimal, @decimal.Decimal, @decimal.DecimalContext) -> Result[
    (@decimal.Decimal, @decimal.DecimalFlags),
    @def.ArithmeticError,
  ],
) -> DecimalChecked {
  guard self.error_ is None else { return self }
  if other.error_ is Some(_) {
    return {
      ..self,
      raised_: other.raised_,
      flags_: self.flags_.combine(other.flags_),
      error_: other.error_,
    }
  }
  let result = self.record_result(
    operation(self.value_, other.value_, self.context_),
  )
  {
    ..result,
    raised_: result.raised_.combine(other.raised_),
    flags_: result.flags_.combine(other.flags_),
  }
}

///|
fn DecimalChecked::from_outcome(
  value : @decimal.Decimal,
  context : @decimal.DecimalContext,
  flags : @decimal.DecimalFlags,
) -> DecimalChecked {
  {
    value_: value,
    context_: context,
    raised_: flags,
    flags_: flags,
    error_: None,
  }
}

///|
/// Rounds `value` into `context` (`Decimal::apply_ctx`) and starts a pipeline
/// there; the flags of that rounding are both `raised` and `flags`.
pub fn DecimalChecked::from_decimal(
  value : @decimal.Decimal,
  context : @decimal.DecimalContext,
) -> DecimalChecked {
  let ieee_context = context
  let (checked, flags) = value.apply_ctx(ieee_context)
  DecimalChecked::from_outcome(checked, ieee_context, flags)
}

///|
/// Converts the string `source` under `context` (`Decimal::from_string_ctx`).
/// Extra digits are rounded and raise `inexact`; an invalid string gives a NaN
/// with `invalid_operation` raised, not an error.
///
/// ```mbt check
/// test {
///   let ctx = @decimal.DecimalContext::new(precision=5)
///   let x = @decimal_checked.DecimalChecked::parse("1.234567", ctx)
///   inspect(x.value().to_string(), content="1.2346")
///   inspect(x.raised().inexact(), content="true")
/// }
/// ```
pub fn DecimalChecked::parse(
  source : String,
  context : @decimal.DecimalContext,
) -> DecimalChecked {
  let ieee_context = context
  let (value, flags) = @decimal.Decimal::from_string_ctx(source, ieee_context)
  DecimalChecked::from_outcome(value, ieee_context, flags)
}

///|
/// The integer `value` under `context`: its decimal string is parsed, so an
/// integer with more digits than the precision is rounded and raises `inexact`.
pub fn DecimalChecked::from_int(
  value : Int32,
  context : @decimal.DecimalContext,
) -> DecimalChecked {
  DecimalChecked::parse(value.to_string(), context)
}

///|
pub fn DecimalChecked::from_bigint(
  value : @bigint.BigInt,
  context : @decimal.DecimalContext,
) -> DecimalChecked {
  DecimalChecked::parse(value.to_string(), context)
}

///|
/// The `Double` `value` under `context`, in two roundings: first to a decimal
/// of 17 significant digits, then into `context`. It is not the correctly
/// rounded decimal of the binary number: `from_double(0.1, decimal128)` is
/// `0.10000000000000001`. For the exact binary value build a `Decimal` with
/// `Decimal::from_double` at a precision that holds it and use `from_decimal`.
pub fn DecimalChecked::from_double(
  value : Double,
  context : @decimal.DecimalContext,
) -> DecimalChecked {
  DecimalChecked::from_decimal(
    @decimal.Decimal::from_double(value, precision=17),
    context,
  )
}

///|
pub fn DecimalChecked::from_float(
  value : Float,
  context : @decimal.DecimalContext,
) -> DecimalChecked {
  DecimalChecked::from_decimal(
    @decimal.Decimal::from_float(value, precision=9),
    context,
  )
}

///|
/// The current value. After an error it is the value reached before the failing
/// step.
pub fn DecimalChecked::value(self : DecimalChecked) -> @decimal.Decimal {
  self.value_
}

///|
/// The context the operations run in.
pub fn DecimalChecked::context(
  self : DecimalChecked,
) -> @decimal.DecimalContext {
  self.context_
}

///|
/// The flags of the latest step. For a binary operation they also include the
/// `raised` flags of the right operand.
pub fn DecimalChecked::raised(self : DecimalChecked) -> @decimal.DecimalFlags {
  self.raised_
}

///|
/// The flags accumulated over the steps since construction or the last
/// `clear_flags`: the union of the flags of the steps, those of the right
/// operands included.
pub fn DecimalChecked::flags(self : DecimalChecked) -> @decimal.DecimalFlags {
  self.flags_
}

///|
/// Whether no error is recorded.
pub fn DecimalChecked::is_ok(self : DecimalChecked) -> Bool {
  self.error_ is None
}

///|
/// Whether an error is recorded.
pub fn DecimalChecked::is_err(self : DecimalChecked) -> Bool {
  self.error_ is Some(_)
}

///|
/// The recorded error, `None` when there is none.
pub fn DecimalChecked::error(self : DecimalChecked) -> @def.ArithmeticError? {
  self.error_
}

///|
/// `Err` with the recorded error, otherwise `Ok` with the value and the
/// accumulated flags.
pub fn DecimalChecked::result(
  self : DecimalChecked,
) -> Result[(@decimal.Decimal, @decimal.DecimalFlags), @def.ArithmeticError] {
  match self.error_ {
    Some(error) => Err(error)
    None => Ok((self.value_, self.flags_))
  }
}

///|
/// Resets `raised` and `flags` to the empty set; the value, the context and the
/// error stay. It applies to a state with an error too.
pub fn DecimalChecked::clear_flags(self : DecimalChecked) -> DecimalChecked {
  let empty = @decimal.DecimalFlags::new()
  { ..self, raised_: empty, flags_: empty, }
}

///|
/// Moves the pipeline to `context` and rounds the current value into it
/// (`Decimal::apply_ctx`); the flags of that rounding become `raised` and join
/// `flags`. A state with an error is returned unchanged.
pub fn DecimalChecked::with_context(
  self : DecimalChecked,
  context : @decimal.DecimalContext,
) -> DecimalChecked {
  guard self.error_ is None else { return self }
  let ieee_context = context
  let (value, raised) = self.value_.apply_ctx(ieee_context)
  {
    value_: value,
    context_: ieee_context,
    raised_: raised,
    flags_: self.flags_.combine(raised),
    error_: None,
  }
}

///|
/// Rounds the current value into the stored context and records the flags.
pub fn DecimalChecked::apply(self : DecimalChecked) -> DecimalChecked {
  self.record(self.value_.apply_ctx(self.context_))
}

///|
pub fn DecimalChecked::abs(self : DecimalChecked) -> DecimalChecked {
  self.record(self.value_.abs_ctx(self.context_))
}

///|
/// The sum, rounded once in the context of `self`. An error of `self`
/// stays; an error of `other` is taken before the operation runs and the value
/// of `self` is kept; the flags of `other` join `raised` and `flags`. `other` is
/// not rounded into the context of `self`: lift it in a context wide enough to
/// hold it to have one rounding.
///
/// ```mbt check
/// test {
///   let ctx = @decimal.DecimalContext::decimal64()
///   let a = @decimal_checked.DecimalChecked::from_int(1, ctx)
///   let b = @decimal_checked.DecimalChecked::from_int(2, ctx)
///   inspect(a.add(b).value().to_string(), content="3")
/// }
/// ```
pub fn DecimalChecked::add(
  self : DecimalChecked,
  other : DecimalChecked,
) -> DecimalChecked {
  self.join(other, fn(a, b, ctx) { Ok(a.add_ctx(b, ctx)) })
}

///|
/// The difference, as `add` is the sum.
pub fn DecimalChecked::sub(
  self : DecimalChecked,
  other : DecimalChecked,
) -> DecimalChecked {
  self.join(other, fn(a, b, ctx) { Ok(a.sub_ctx(b, ctx)) })
}

///|
/// The product, as `add` is the sum.
pub fn DecimalChecked::mul(
  self : DecimalChecked,
  other : DecimalChecked,
) -> DecimalChecked {
  self.join(other, fn(a, b, ctx) { Ok(a.mul_ctx(b, ctx)) })
}

///|
/// The quotient, as `add` is the sum. An invalid division (`0 / 0`) is a NaN
/// with `invalid_operation` and a division of a finite non-zero number by zero
/// an infinity with `division_by_zero`; neither is an error.
pub fn DecimalChecked::div(
  self : DecimalChecked,
  other : DecimalChecked,
) -> DecimalChecked {
  self.join(other, fn(a, b, ctx) { Ok(a.div_ctx(b, ctx)) })
}

///|
/// `self * multiplier + addend` with one rounding, in the context of `self`.
/// Errors and flags of the two operands are taken as for `add`.
pub fn DecimalChecked::fma(
  self : DecimalChecked,
  multiplier : DecimalChecked,
  addend : DecimalChecked,
) -> DecimalChecked {
  guard self.error_ is None else { return self }
  let raised = multiplier.raised_.combine(addend.raised_)
  let flags = multiplier.flags_.combine(addend.flags_)
  let error = match multiplier.error_ {
    Some(_) => multiplier.error_
    None => addend.error_
  }
  if error is Some(_) {
    return {
      ..self,
      raised_: raised,
      flags_: self.flags_.combine(flags),
      error_: error,
    }
  }
  let result = self.record(
    self.value_.fma_ctx(multiplier.value_, addend.value_, self.context_),
  )
  {
    ..result,
    raised_: result.raised_.combine(raised),
    flags_: result.flags_.combine(flags),
  }
}

///|
/// The square root, rounded once in the context. A negative operand gives
/// a NaN with `invalid_operation`, not an error.
pub fn DecimalChecked::sqrt(self : DecimalChecked) -> DecimalChecked {
  self.record(self.value_.sqrt_ctx(self.context_))
}

///|
/// The exponential in the context. A failure to certify the result records an
/// error and stops the pipeline.
pub fn DecimalChecked::exp(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_exp_ctx(self.context_))
}

///|
/// The natural logarithm in the context. Zero gives `-inf` with
/// `division_by_zero` and a negative operand a NaN with `invalid_operation`,
/// both values; a failure to certify records an error.
pub fn DecimalChecked::ln(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_ln_ctx(self.context_))
}

///|
pub fn DecimalChecked::log10(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_log10_ctx(self.context_))
}

///|
/// `self` raised to `exponent` in the context of `self`; errors and flags of
/// the operand are taken as for `add`. Zero to a negative power gives an
/// infinity with `division_by_zero`. A failure to certify records an error.
pub fn DecimalChecked::pow(
  self : DecimalChecked,
  exponent : DecimalChecked,
) -> DecimalChecked {
  self.join(exponent, fn(a, b, ctx) { a.try_pow_ctx(b, ctx) })
}

///|
pub fn DecimalChecked::exp2(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_exp2_ctx(self.context_))
}

///|
pub fn DecimalChecked::exp10(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_exp10_ctx(self.context_))
}

///|
pub fn DecimalChecked::expm1(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_expm1_ctx(self.context_))
}

///|
pub fn DecimalChecked::exp2m1(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_exp2m1_ctx(self.context_))
}

///|
pub fn DecimalChecked::exp10m1(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_exp10m1_ctx(self.context_))
}

///|
pub fn DecimalChecked::log2(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_log2_ctx(self.context_))
}

///|
pub fn DecimalChecked::log1p(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_log1p_ctx(self.context_))
}

///|
pub fn DecimalChecked::log2p1(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_log2p1_ctx(self.context_))
}

///|
pub fn DecimalChecked::log10p1(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_log10p1_ctx(self.context_))
}

///|
pub fn DecimalChecked::rsqrt(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_rsqrt_ctx(self.context_))
}

///|
pub fn DecimalChecked::compound(
  self : DecimalChecked,
  n : Int32,
) -> DecimalChecked {
  self.record_result(self.value_.try_compound_ctx(n, self.context_))
}

///|
pub fn DecimalChecked::powr(
  self : DecimalChecked,
  exponent : DecimalChecked,
) -> DecimalChecked {
  self.join(exponent, fn(a, b, ctx) { a.try_powr_ctx(b, ctx) })
}

///|
pub fn DecimalChecked::rootn(
  self : DecimalChecked,
  degree : Int32,
) -> DecimalChecked {
  self.record_result(self.value_.try_rootn_ctx(degree, self.context_))
}

///|
pub fn DecimalChecked::pown(
  self : DecimalChecked,
  exponent : Int32,
) -> DecimalChecked {
  self.record_result(self.value_.try_pown_ctx(exponent, self.context_))
}

///|
pub fn DecimalChecked::hypot(
  self : DecimalChecked,
  other : DecimalChecked,
) -> DecimalChecked {
  self.join(other, fn(a, b, ctx) { a.try_hypot_ctx(b, ctx) })
}

///|
pub fn DecimalChecked::sin(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_sin_ctx(self.context_))
}

///|
pub fn DecimalChecked::cos(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_cos_ctx(self.context_))
}

///|
pub fn DecimalChecked::tan(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_tan_ctx(self.context_))
}

///|
pub fn DecimalChecked::sinpi(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_sinpi_ctx(self.context_))
}

///|
pub fn DecimalChecked::cospi(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_cospi_ctx(self.context_))
}

///|
pub fn DecimalChecked::tanpi(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_tanpi_ctx(self.context_))
}

///|
pub fn DecimalChecked::asin(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_asin_ctx(self.context_))
}

///|
pub fn DecimalChecked::acos(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_acos_ctx(self.context_))
}

///|
pub fn DecimalChecked::atan(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_atan_ctx(self.context_))
}

///|
pub fn DecimalChecked::asinpi(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_asinpi_ctx(self.context_))
}

///|
pub fn DecimalChecked::acospi(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_acospi_ctx(self.context_))
}

///|
pub fn DecimalChecked::atanpi(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_atanpi_ctx(self.context_))
}

///|
pub fn DecimalChecked::atan2pi(
  self : DecimalChecked,
  abscissa : DecimalChecked,
) -> DecimalChecked {
  self.join(abscissa, fn(a, b, ctx) { a.try_atan2pi_ctx(b, ctx) })
}

///|
pub fn DecimalChecked::atan2(
  self : DecimalChecked,
  abscissa : DecimalChecked,
) -> DecimalChecked {
  self.join(abscissa, fn(a, b, ctx) { a.try_atan2_ctx(b, ctx) })
}

///|
pub fn DecimalChecked::sinh(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_sinh_ctx(self.context_))
}

///|
pub fn DecimalChecked::cosh(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_cosh_ctx(self.context_))
}

///|
pub fn DecimalChecked::tanh(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_tanh_ctx(self.context_))
}

///|
pub fn DecimalChecked::asinh(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_asinh_ctx(self.context_))
}

///|
pub fn DecimalChecked::acosh(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_acosh_ctx(self.context_))
}

///|
pub fn DecimalChecked::atanh(self : DecimalChecked) -> DecimalChecked {
  self.record_result(self.value_.try_atanh_ctx(self.context_))
}

///|
/// The value rounded to the exponent of `other` (`Decimal::quantize_ctx`), in
/// the context of `self`.
pub fn DecimalChecked::quantize(
  self : DecimalChecked,
  quantum : DecimalChecked,
) -> DecimalChecked {
  self.join(quantum, fn(a, b, ctx) { Ok(a.quantize_ctx(b, ctx)) })
}

///|
pub fn DecimalChecked::quantum(self : DecimalChecked) -> DecimalChecked {
  self.record(self.value_.quantum_ctx(self.context_))
}

///|
pub fn DecimalChecked::remainder(
  self : DecimalChecked,
  divisor : DecimalChecked,
) -> DecimalChecked {
  self.join(divisor, fn(a, b, ctx) { Ok(a.remainder_ctx(b, ctx)) })
}

///|
pub fn DecimalChecked::minimum_number(
  self : DecimalChecked,
  other : DecimalChecked,
) -> DecimalChecked {
  self.join(other, fn(a, b, ctx) { Ok(a.minimum_number_ctx(b, ctx)) })
}

///|
pub fn DecimalChecked::maximum_number(
  self : DecimalChecked,
  other : DecimalChecked,
) -> DecimalChecked {
  self.join(other, fn(a, b, ctx) { Ok(a.maximum_number_ctx(b, ctx)) })
}

///|
pub fn DecimalChecked::next_down(self : DecimalChecked) -> DecimalChecked {
  self.record(self.value_.next_down_ctx(self.context_))
}

///|
pub fn DecimalChecked::next_up(self : DecimalChecked) -> DecimalChecked {
  self.record(self.value_.next_up_ctx(self.context_))
}
