///|
pub struct DecimalChecked {
  priv value_ : @decimal.Decimal
  priv context_ : @decimal.DecimalContext
  priv raised_ : @decimal.DecimalFlags
  priv flags_ : @decimal.DecimalFlags
}

///|
fn DecimalChecked::record(
  self : DecimalChecked,
  outcome : (@decimal.Decimal, @decimal.DecimalFlags),
) -> DecimalChecked {
  let (value, raised) = outcome
  {
    value_: value,
    context_: self.context_,
    raised_: raised,
    flags_: self.flags_.combine(raised),
  }
}

///|
pub fn DecimalChecked::from_outcome(
  value : @decimal.Decimal,
  context : @decimal.DecimalContext,
  flags : @decimal.DecimalFlags,
) -> DecimalChecked {
  { value_: value, context_: context.ieee754(), raised_: flags, flags_: flags }
}

///|
pub fn DecimalChecked::from_decimal(
  value : @decimal.Decimal,
  context : @decimal.DecimalContext,
) -> DecimalChecked {
  let ieee_context = context.ieee754()
  let (checked, flags) = value.apply_ctx(ieee_context)
  DecimalChecked::from_outcome(checked, ieee_context, flags)
}

///|
pub fn DecimalChecked::parse(
  source : String,
  context : @decimal.DecimalContext,
) -> DecimalChecked {
  let ieee_context = context.ieee754()
  let (value, flags) = @decimal.Decimal::from_string_ctx(source, ieee_context)
  DecimalChecked::from_outcome(value, ieee_context, flags)
}

///|
pub fn DecimalChecked::from_int(
  value : Int,
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
pub fn DecimalChecked::value(self : DecimalChecked) -> @decimal.Decimal {
  self.value_
}

///|
pub fn DecimalChecked::context(
  self : DecimalChecked,
) -> @decimal.DecimalContext {
  self.context_
}

///|
pub fn DecimalChecked::raised(self : DecimalChecked) -> @decimal.DecimalFlags {
  self.raised_
}

///|
pub fn DecimalChecked::flags(self : DecimalChecked) -> @decimal.DecimalFlags {
  self.flags_
}

///|
pub fn DecimalChecked::outcome(
  self : DecimalChecked,
) -> (@decimal.Decimal, @decimal.DecimalFlags) {
  (self.value_, self.flags_)
}

///|
pub fn DecimalChecked::clear_flags(self : DecimalChecked) -> DecimalChecked {
  let empty = @decimal.DecimalFlags::new()
  { ..self, raised_: empty, flags_: empty }
}

///|
pub fn DecimalChecked::with_context(
  self : DecimalChecked,
  context : @decimal.DecimalContext,
) -> DecimalChecked {
  let ieee_context = context.ieee754()
  let (value, raised) = self.value_.apply_ctx(ieee_context)
  {
    value_: value,
    context_: ieee_context,
    raised_: raised,
    flags_: self.flags_.combine(raised),
  }
}

///|
pub fn DecimalChecked::apply(self : DecimalChecked) -> DecimalChecked {
  self.record(self.value_.apply_ctx(self.context_))
}

///|
pub fn DecimalChecked::plus(self : DecimalChecked) -> DecimalChecked {
  self.record(self.value_.plus_ctx(self.context_))
}

///|
pub fn DecimalChecked::minus(self : DecimalChecked) -> DecimalChecked {
  self.record(self.value_.minus_ctx(self.context_))
}

///|
pub fn DecimalChecked::abs(self : DecimalChecked) -> DecimalChecked {
  self.record(self.value_.abs_ctx(self.context_))
}

///|
pub fn DecimalChecked::add(
  self : DecimalChecked,
  other : @decimal.Decimal,
) -> DecimalChecked {
  self.record(self.value_.add_ctx(other, self.context_))
}

///|
pub fn DecimalChecked::sub(
  self : DecimalChecked,
  other : @decimal.Decimal,
) -> DecimalChecked {
  self.record(self.value_.sub_ctx(other, self.context_))
}

///|
pub fn DecimalChecked::mul(
  self : DecimalChecked,
  other : @decimal.Decimal,
) -> DecimalChecked {
  self.record(self.value_.mul_ctx(other, self.context_))
}

///|
pub fn DecimalChecked::div(
  self : DecimalChecked,
  other : @decimal.Decimal,
) -> DecimalChecked {
  self.record(self.value_.div_ctx(other, self.context_))
}

///|
pub fn DecimalChecked::fma(
  self : DecimalChecked,
  multiplier : @decimal.Decimal,
  addend : @decimal.Decimal,
) -> DecimalChecked {
  self.record(self.value_.fma_ctx(multiplier, addend, self.context_))
}

///|
pub fn DecimalChecked::sqrt(self : DecimalChecked) -> DecimalChecked {
  self.record(self.value_.sqrt_ctx(self.context_))
}

///|
pub fn DecimalChecked::exp(self : DecimalChecked) -> DecimalChecked {
  self.record(self.value_.exp_ctx(self.context_))
}

///|
pub fn DecimalChecked::ln(self : DecimalChecked) -> DecimalChecked {
  self.record(self.value_.ln_ctx(self.context_))
}

///|
pub fn DecimalChecked::log10(self : DecimalChecked) -> DecimalChecked {
  self.record(self.value_.log10_ctx(self.context_))
}

///|
pub fn DecimalChecked::power(
  self : DecimalChecked,
  exponent : @decimal.Decimal,
) -> DecimalChecked {
  self.record(self.value_.power_ctx(exponent, self.context_))
}

///|
pub fn DecimalChecked::quantize(
  self : DecimalChecked,
  quantum : @decimal.Decimal,
) -> DecimalChecked {
  self.record(self.value_.quantize(quantum, self.context_))
}

///|
pub fn DecimalChecked::remainder(
  self : DecimalChecked,
  divisor : @decimal.Decimal,
) -> DecimalChecked {
  self.record(self.value_.remainder_ctx(divisor, self.context_))
}

///|
pub fn DecimalChecked::reduce(self : DecimalChecked) -> DecimalChecked {
  self.record(self.value_.reduce_ctx(self.context_))
}

///|
pub fn DecimalChecked::min(
  self : DecimalChecked,
  other : @decimal.Decimal,
) -> DecimalChecked {
  self.record(self.value_.min_ctx(other, self.context_))
}

///|
pub fn DecimalChecked::max(
  self : DecimalChecked,
  other : @decimal.Decimal,
) -> DecimalChecked {
  self.record(self.value_.max_ctx(other, self.context_))
}

///|
pub fn DecimalChecked::next_minus(self : DecimalChecked) -> DecimalChecked {
  self.record(self.value_.next_minus(self.context_))
}

///|
pub fn DecimalChecked::next_plus(self : DecimalChecked) -> DecimalChecked {
  self.record(self.value_.next_plus(self.context_))
}

///|
pub fn DecimalChecked::next_toward(
  self : DecimalChecked,
  target : @decimal.Decimal,
) -> DecimalChecked {
  self.record(self.value_.next_toward(target, self.context_))
}
