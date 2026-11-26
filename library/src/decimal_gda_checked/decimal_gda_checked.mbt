///|
/// A pipeline of GDA operations: the current outcome (the defined result, the
/// context with its sticky status and the conditions of the last operation).
/// Every operation continues from the value and the context of the pipeline,
/// and after a trap the pipeline stays trapped (`resume_defined` continues it).
/// The right operand of a binary operation is a pipeline too: its conditions are
/// merged into the result and its trap short-circuits.
pub struct GdaDecimalChecked {
  priv outcome_ : @decimal_gda.GdaOutcome[@decimal_gda.Decimal]
}

///|
/// Any outcome is a valid state of the pipeline.
pub fn GdaDecimalChecked::from_outcome(
  outcome : @decimal_gda.GdaOutcome[@decimal_gda.Decimal],
) -> GdaDecimalChecked {
  { outcome_: outcome, }
}

///|
/// The value converted under the context (GDA `apply`), as a pipeline.
pub fn GdaDecimalChecked::from_decimal(
  value : @decimal_gda.Decimal,
  context : @decimal_gda.GdaContext,
) -> GdaDecimalChecked {
  GdaDecimalChecked::from_outcome(@decimal_gda.apply(value, context))
}

///|
/// GDA to-number of a string under the context, as a pipeline.
pub fn GdaDecimalChecked::to_number(
  source : String,
  context : @decimal_gda.GdaContext,
) -> GdaDecimalChecked {
  GdaDecimalChecked::from_outcome(@decimal_gda.to_number(source, context))
}

///|
/// The current `GdaOutcome`: `Completed` with the value, the next context and
/// the conditions of the last operation, or `Trapped` with the signal as well.
pub fn GdaDecimalChecked::outcome(
  self : GdaDecimalChecked,
) -> @decimal_gda.GdaOutcome[@decimal_gda.Decimal] {
  self.outcome_
}

///|
/// The defined result, also after a trap.
pub fn GdaDecimalChecked::value(
  self : GdaDecimalChecked,
) -> @decimal_gda.Decimal {
  self.outcome_.value()
}

///|
/// The context with the sticky status of the pipeline so far.
pub fn GdaDecimalChecked::context(
  self : GdaDecimalChecked,
) -> @decimal_gda.GdaContext {
  self.outcome_.next_context()
}

///|
/// The conditions of the last operation only.
pub fn GdaDecimalChecked::raised(
  self : GdaDecimalChecked,
) -> @decimal_gda.GdaFlags {
  self.outcome_.raised()
}

///|
/// The sticky status of the context.
pub fn GdaDecimalChecked::flags(
  self : GdaDecimalChecked,
) -> @decimal_gda.GdaFlags {
  self.outcome_.next_context().flags()
}

///|
/// The signal of the trap that stopped the pipeline, `None` when it completed.
pub fn GdaDecimalChecked::error(
  self : GdaDecimalChecked,
) -> @decimal_gda.GdaSignal? {
  match self.outcome_ {
    @decimal_gda.Trapped(signal, _, _, _) => Some(signal)
    @decimal_gda.Completed(_, _, _) => None
  }
}

///|
/// `Ok(value)` when the pipeline completed, `Err(signal)` when a trap stopped it.
pub fn GdaDecimalChecked::result(
  self : GdaDecimalChecked,
) -> Result[@decimal_gda.Decimal, @decimal_gda.GdaSignal] {
  match self.outcome_ {
    @decimal_gda.Completed(value, _, _) => Ok(value)
    @decimal_gda.Trapped(signal, _, _, _) => Err(signal)
  }
}

///|
/// Whether the pipeline completed, that is no trap stopped it.
pub fn GdaDecimalChecked::is_ok(self : GdaDecimalChecked) -> Bool {
  self.error() is None
}

///|
/// Whether a trap stopped the pipeline.
pub fn GdaDecimalChecked::is_err(self : GdaDecimalChecked) -> Bool {
  self.error() is Some(_)
}

///|
/// Continues after a trap with the defined result, the GDA rule for a trap that
/// supplies a result.
pub fn GdaDecimalChecked::resume_defined(
  self : GdaDecimalChecked,
) -> GdaDecimalChecked {
  GdaDecimalChecked::from_outcome(self.outcome_.resume_defined())
}

///|
fn GdaDecimalChecked::unary(
  self : GdaDecimalChecked,
  operation : (@decimal_gda.Decimal, @decimal_gda.GdaContext) -> @decimal_gda.GdaOutcome[
    @decimal_gda.Decimal,
  ],
) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(operation(value, context))
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
/// A binary operation: a trapped left pipeline stays as it is; otherwise a trapped
/// right pipeline stops the operation (its flags and its trap join the result);
/// otherwise the operation runs in the context of the left pipeline and the
/// conditions of the right one join its outcome.
fn GdaDecimalChecked::binary(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
  operation : (
    @decimal_gda.Decimal,
    @decimal_gda.Decimal,
    @decimal_gda.GdaContext,
  ) -> @decimal_gda.GdaOutcome[@decimal_gda.Decimal],
) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Trapped(_, _, _, _) => self
    @decimal_gda.Completed(value, context, _) =>
      match other.outcome_ {
        @decimal_gda.Trapped(_, _, _, _) =>
          GdaDecimalChecked::from_outcome(
            @decimal_gda.GdaOutcome::completed(value, context).absorb(
              other.outcome_,
            ),
          )
        @decimal_gda.Completed(_, _, _) =>
          GdaDecimalChecked::from_outcome(
            operation(value, other.value(), context).absorb(other.outcome_),
          )
      }
  }
}

///|
/// Rounds the current value to the context (GDA `apply`).
pub fn GdaDecimalChecked::apply(self : GdaDecimalChecked) -> GdaDecimalChecked {
  self.unary(@decimal_gda.apply)
}

///|
/// The value rounded to the context, as the GDA `plus` (the prefix `+`) does.
pub fn GdaDecimalChecked::plus(self : GdaDecimalChecked) -> GdaDecimalChecked {
  self.unary(@decimal_gda.plus)
}

///|
/// The negation of the value, rounded to the context (GDA `minus`).
pub fn GdaDecimalChecked::minus(self : GdaDecimalChecked) -> GdaDecimalChecked {
  self.unary(@decimal_gda.minus)
}

///|
/// The absolute value, rounded to the context (GDA `abs`).
pub fn GdaDecimalChecked::abs(self : GdaDecimalChecked) -> GdaDecimalChecked {
  self.unary(@decimal_gda.abs)
}

///|
/// The square root in the context (GDA `square-root`). A negative operand gives
/// NaN with `invalid_operation`.
pub fn GdaDecimalChecked::sqrt(self : GdaDecimalChecked) -> GdaDecimalChecked {
  self.unary(@decimal_gda.sqrt)
}

///|
/// The exponential in the context (GDA `exp`). In a context whose `e_max` is
/// above 999999 or whose `e_min` is below -999999 the result is NaN, with
/// `invalid_context` raised and `invalid_operation` set in the sticky flags
/// too; `GdaContext::new(precision=5)` is such a context. Inside those limits the
/// result is computed.
pub fn GdaDecimalChecked::exp(self : GdaDecimalChecked) -> GdaDecimalChecked {
  self.unary(@decimal_gda.exp)
}

///|
/// The natural logarithm in the context (GDA `ln`), with the limits of `exp`.
/// Inside them `ln(0)` is `-inf`, with no flag.
pub fn GdaDecimalChecked::ln(self : GdaDecimalChecked) -> GdaDecimalChecked {
  self.unary(@decimal_gda.ln)
}

///|
/// The base-10 logarithm in the context (GDA `log10`), with the limits of `exp`.
pub fn GdaDecimalChecked::log10(self : GdaDecimalChecked) -> GdaDecimalChecked {
  self.unary(@decimal_gda.log10)
}

///|
pub fn GdaDecimalChecked::reduce(self : GdaDecimalChecked) -> GdaDecimalChecked {
  self.unary(@decimal_gda.reduce)
}

///|
pub fn GdaDecimalChecked::next_plus(
  self : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.unary(@decimal_gda.next_plus)
}

///|
pub fn GdaDecimalChecked::next_minus(
  self : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.unary(@decimal_gda.next_minus)
}

///|
pub fn GdaDecimalChecked::logb(self : GdaDecimalChecked) -> GdaDecimalChecked {
  self.unary(@decimal_gda.logb)
}

///|
pub fn GdaDecimalChecked::logical_invert(
  self : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.unary(@decimal_gda.logical_invert)
}

///|
pub fn GdaDecimalChecked::round_to_integral_exact(
  self : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.unary(@decimal_gda.round_to_integral_exact)
}

///|
pub fn GdaDecimalChecked::round_to_integral_value(
  self : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.unary(@decimal_gda.round_to_integral_value)
}

///|
/// The sum, rounded in the context of `self` (GDA `add`). A trapped `self`
/// stays as it is, and the flags of `other` are not joined. When `other` is
/// trapped the operation does not run: the value of `self` is kept, the result is
/// trapped with the signal of `other`, `raised` becomes the `raised` of `other`
/// (the earlier `raised` of `self` is dropped) and the sticky flags are those of
/// `self` joined with those of `other`. Otherwise `raised` is the conditions of
/// this step joined with the `raised` of `other`.
///
/// ```mbt check
/// test {
///   let ctx = @decimal_gda.GdaContext::new(precision=5)
///   let a = @decimal_gda_checked.GdaDecimalChecked::to_number("1.2", ctx)
///   let b = @decimal_gda_checked.GdaDecimalChecked::to_number("2.3", ctx)
///   inspect(a.add(b).value().to_string(), content="3.5")
/// }
/// ```
pub fn GdaDecimalChecked::add(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.add)
}

///|
/// The difference, as `add` is the sum (GDA `subtract`).
pub fn GdaDecimalChecked::subtract(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.subtract)
}

///|
/// The product, as `add` is the sum (GDA `multiply`).
pub fn GdaDecimalChecked::multiply(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.multiply)
}

///|
/// The quotient, as `add` is the sum (GDA `divide`). A finite non-zero number
/// divided by zero is `inf` with `division_by_zero`, `0 / 0` is NaN with
/// `invalid_operation`; a trap enabled for the signal stops the pipeline.
pub fn GdaDecimalChecked::divide(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.divide)
}

///|
/// The integer part of the quotient, as `add` is the sum (GDA
/// `divide-integer`): `7` by `2` is `3`.
pub fn GdaDecimalChecked::divide_integer(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.divide_integer)
}

///|
pub fn GdaDecimalChecked::remainder(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.remainder)
}

///|
pub fn GdaDecimalChecked::remainder_near(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.remainder_near)
}

///|
/// `self` raised to `other`, in the context of `self` (GDA `power`); operands
/// are taken as for `add`. An integer exponent is computed in every context
/// probed. In a context with the restricted limits of `exp` (`e_max` above 999999
/// or `e_min` below -999999) most non-integer exponents give NaN with
/// `invalid_context` raised and `invalid_operation` set in the sticky flags
/// (`2` to `0.3`, `4` to `0.25`, `2` to `1.5`), but an exponent of `0.5` is
/// computed (`2` to `0.5` is `1.4142` at precision 5, `-8` to `0.5` is NaN with
/// `invalid_operation`). Inside the limits non-integer exponents are computed.
pub fn GdaDecimalChecked::power(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.power)
}

///|
/// The value rounded to the exponent of `other` (GDA `quantize`): `2.675` by
/// `0.01` is `2.68` at precision 5.
pub fn GdaDecimalChecked::quantize(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.quantize)
}

///|
pub fn GdaDecimalChecked::rescale(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.rescale)
}

///|
pub fn GdaDecimalChecked::scaleb(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.scaleb)
}

///|
pub fn GdaDecimalChecked::shift(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.shift)
}

///|
pub fn GdaDecimalChecked::rotate(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.rotate)
}

///|
pub fn GdaDecimalChecked::next_toward(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.next_toward)
}

///|
pub fn GdaDecimalChecked::compare(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.compare)
}

///|
pub fn GdaDecimalChecked::compare_signal(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.compare_signal)
}

///|
pub fn GdaDecimalChecked::logical_and(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.logical_and)
}

///|
pub fn GdaDecimalChecked::logical_or(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.logical_or)
}

///|
pub fn GdaDecimalChecked::logical_xor(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.logical_xor)
}

///|
/// The larger of the two (GDA `max`); a quiet NaN operand loses to a number.
pub fn GdaDecimalChecked::max(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.max)
}

///|
/// The smaller of the two (GDA `min`); a quiet NaN operand loses to a number.
pub fn GdaDecimalChecked::min(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.min)
}

///|
/// The operand of larger absolute value (GDA `max-magnitude`): `-3` against `2`
/// is `-3`.
pub fn GdaDecimalChecked::max_magnitude(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.max_magnitude)
}

///|
/// The operand of smaller absolute value (GDA `min-magnitude`): `-3` against
/// `2` is `2`.
pub fn GdaDecimalChecked::min_magnitude(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.min_magnitude)
}

///|
/// Fused multiply-add: `self * multiplier + addend`, with the conditions of both
/// operands merged and the trap of either short-circuiting.
pub fn GdaDecimalChecked::fma(
  self : GdaDecimalChecked,
  multiplier : GdaDecimalChecked,
  addend : GdaDecimalChecked,
) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Trapped(_, _, _, _) => self
    @decimal_gda.Completed(value, context, _) => {
      let operands = @decimal_gda.GdaOutcome::completed(value, context)
        .absorb(multiplier.outcome_)
        .absorb(addend.outcome_)
      match operands {
        @decimal_gda.Trapped(_, _, _, _) =>
          GdaDecimalChecked::from_outcome(operands)
        @decimal_gda.Completed(_, _, _) =>
          GdaDecimalChecked::from_outcome(
            @decimal_gda.fma(value, multiplier.value(), addend.value(), context)
            .absorb(multiplier.outcome_)
            .absorb(addend.outcome_),
          )
      }
    }
  }
}
