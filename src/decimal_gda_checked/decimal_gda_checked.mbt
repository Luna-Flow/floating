///|
pub struct GdaDecimalChecked {
  priv outcome_ : @decimal_gda.GdaOutcome[@decimal_gda.Decimal]
}

///|
pub fn GdaDecimalChecked::from_outcome(
  outcome : @decimal_gda.GdaOutcome[@decimal_gda.Decimal],
) -> GdaDecimalChecked {
  { outcome_: outcome }
}

///|
pub fn GdaDecimalChecked::from_decimal(
  value : @decimal_gda.Decimal,
  context : @decimal_gda.GdaContext,
) -> GdaDecimalChecked {
  GdaDecimalChecked::from_outcome(@decimal_gda.apply(value, context))
}

///|
pub fn GdaDecimalChecked::parse(
  source : String,
  context : @decimal_gda.GdaContext,
) -> GdaDecimalChecked {
  GdaDecimalChecked::from_outcome(@decimal_gda.parse(source, context))
}

///|
pub fn GdaDecimalChecked::outcome(
  self : GdaDecimalChecked,
) -> @decimal_gda.GdaOutcome[@decimal_gda.Decimal] {
  self.outcome_
}

///|
pub fn GdaDecimalChecked::value(
  self : GdaDecimalChecked,
) -> @decimal_gda.Decimal {
  self.outcome_.value()
}

///|
pub fn GdaDecimalChecked::context(
  self : GdaDecimalChecked,
) -> @decimal_gda.GdaContext {
  self.outcome_.next_context()
}

///|
pub fn GdaDecimalChecked::raised(
  self : GdaDecimalChecked,
) -> @decimal_gda.GdaFlags {
  self.outcome_.raised()
}

///|
pub fn GdaDecimalChecked::status(
  self : GdaDecimalChecked,
) -> @decimal_gda.GdaFlags {
  self.outcome_.next_context().status()
}

///|
pub fn GdaDecimalChecked::is_trapped(self : GdaDecimalChecked) -> Bool {
  match self.outcome_ {
    @decimal_gda.Trapped(_, _, _, _) => true
    @decimal_gda.Completed(_, _, _) => false
  }
}

///|
pub fn GdaDecimalChecked::trapped_signal(
  self : GdaDecimalChecked,
) -> @decimal_gda.GdaSignal? {
  match self.outcome_ {
    @decimal_gda.Trapped(signal, _, _, _) => Some(signal)
    @decimal_gda.Completed(_, _, _) => None
  }
}

///|
pub fn GdaDecimalChecked::resume_defined(
  self : GdaDecimalChecked,
) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(_, _, _) => self
    @decimal_gda.Trapped(_, value, context, _) =>
      GdaDecimalChecked::from_outcome(
        @decimal_gda.Completed(value, context, @decimal_gda.GdaFlags::none()),
      )
  }
}

///|
pub fn GdaDecimalChecked::apply(self : GdaDecimalChecked) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(@decimal_gda.apply(value, context))
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::plus(self : GdaDecimalChecked) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(@decimal_gda.plus(value, context))
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::minus(self : GdaDecimalChecked) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(@decimal_gda.minus(value, context))
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::abs(self : GdaDecimalChecked) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(@decimal_gda.abs(value, context))
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::add(
  self : GdaDecimalChecked,
  other : @decimal_gda.Decimal,
) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(@decimal_gda.add(value, other, context))
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::subtract(
  self : GdaDecimalChecked,
  other : @decimal_gda.Decimal,
) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(
        @decimal_gda.subtract(value, other, context),
      )
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::multiply(
  self : GdaDecimalChecked,
  other : @decimal_gda.Decimal,
) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(
        @decimal_gda.multiply(value, other, context),
      )
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::divide(
  self : GdaDecimalChecked,
  other : @decimal_gda.Decimal,
) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(
        @decimal_gda.divide(value, other, context),
      )
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::fma(
  self : GdaDecimalChecked,
  multiplier : @decimal_gda.Decimal,
  addend : @decimal_gda.Decimal,
) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(
        @decimal_gda.fma(value, multiplier, addend, context),
      )
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::sqrt(self : GdaDecimalChecked) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(@decimal_gda.sqrt(value, context))
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::exp(self : GdaDecimalChecked) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(@decimal_gda.exp(value, context))
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::ln(self : GdaDecimalChecked) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(@decimal_gda.ln(value, context))
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::log10(self : GdaDecimalChecked) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(@decimal_gda.log10(value, context))
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::power(
  self : GdaDecimalChecked,
  exponent : @decimal_gda.Decimal,
) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(
        @decimal_gda.power(value, exponent, context),
      )
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::quantize(
  self : GdaDecimalChecked,
  quantum : @decimal_gda.Decimal,
) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(
        @decimal_gda.quantize(value, quantum, context),
      )
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::remainder(
  self : GdaDecimalChecked,
  divisor : @decimal_gda.Decimal,
) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(
        @decimal_gda.remainder(value, divisor, context),
      )
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::reduce(self : GdaDecimalChecked) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(@decimal_gda.reduce(value, context))
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::next_minus(
  self : GdaDecimalChecked,
) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(@decimal_gda.next_minus(value, context))
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::next_plus(
  self : GdaDecimalChecked,
) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(@decimal_gda.next_plus(value, context))
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}

///|
pub fn GdaDecimalChecked::next_toward(
  self : GdaDecimalChecked,
  target : @decimal_gda.Decimal,
) -> GdaDecimalChecked {
  match self.outcome_ {
    @decimal_gda.Completed(value, context, _) =>
      GdaDecimalChecked::from_outcome(
        @decimal_gda.next_toward(value, target, context),
      )
    @decimal_gda.Trapped(_, _, _, _) => self
  }
}
