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
pub fn GdaDecimalChecked::status(
  self : GdaDecimalChecked,
) -> @decimal_gda.GdaFlags {
  self.outcome_.next_context().status()
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
pub fn GdaDecimalChecked::is_ok(self : GdaDecimalChecked) -> Bool {
  self.error() is None
}

///|
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
pub fn GdaDecimalChecked::apply(self : GdaDecimalChecked) -> GdaDecimalChecked {
  self.unary(@decimal_gda.apply)
}

///|
pub fn GdaDecimalChecked::plus(self : GdaDecimalChecked) -> GdaDecimalChecked {
  self.unary(@decimal_gda.plus)
}

///|
pub fn GdaDecimalChecked::minus(self : GdaDecimalChecked) -> GdaDecimalChecked {
  self.unary(@decimal_gda.minus)
}

///|
pub fn GdaDecimalChecked::abs(self : GdaDecimalChecked) -> GdaDecimalChecked {
  self.unary(@decimal_gda.abs)
}

///|
pub fn GdaDecimalChecked::sqrt(self : GdaDecimalChecked) -> GdaDecimalChecked {
  self.unary(@decimal_gda.sqrt)
}

///|
pub fn GdaDecimalChecked::exp(self : GdaDecimalChecked) -> GdaDecimalChecked {
  self.unary(@decimal_gda.exp)
}

///|
pub fn GdaDecimalChecked::ln(self : GdaDecimalChecked) -> GdaDecimalChecked {
  self.unary(@decimal_gda.ln)
}

///|
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
pub fn GdaDecimalChecked::add(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.add)
}

///|
pub fn GdaDecimalChecked::subtract(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.subtract)
}

///|
pub fn GdaDecimalChecked::multiply(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.multiply)
}

///|
pub fn GdaDecimalChecked::divide(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.divide)
}

///|
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
pub fn GdaDecimalChecked::power(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.power)
}

///|
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
pub fn GdaDecimalChecked::max(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.max)
}

///|
pub fn GdaDecimalChecked::min(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.min)
}

///|
pub fn GdaDecimalChecked::max_magnitude(
  self : GdaDecimalChecked,
  other : GdaDecimalChecked,
) -> GdaDecimalChecked {
  self.binary(other, @decimal_gda.max_magnitude)
}

///|
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
