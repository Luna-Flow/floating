///|
/// The working context of the plain operators (`+ - * /`, `sqrt`) of `Decimal`:
/// precision `p`, round-half-even, extended arithmetic, no clamp, no traps, and
/// an exponent range that no user can build, `Emax = 2,147,483,646` and
/// `Emin = -2,147,483,645 + p - 1` (Etiny = -2,147,483,645), so that every
/// exponent from there to the largest a `Decimal` can hold stays in range
/// (`x + 0 == x` for these stored values) and the Int32 arithmetic of the bounds
/// does not wrap. It is not validated against the limits of `GdaContext::new`
/// (the plain operators are the only users) and never leaves the package.
fn gda_plain_working_context_build(precision : Int32) -> GdaContext {
  let e_max = gda_implementation_e_max
  // Etiny = Emin - p + 1 = -2,147,483,645: the exponent folding of an exponent
  // below the Int32 range leaves a sticky digit two places above the Int32
  // minimum, which a quantum of that size rounds away; a smaller Etiny would
  // keep it as a tiny non-zero result.
  let e_min = gda_implementation_e_tiny + precision - 1
  let decimal_ : DecimalContext = {
    precision,
    rounding: RoundingMode::ToNearestEven,
    decimal_rounding: DecimalRoundingMode::HalfEven,
    e_min,
    e_max,
    clamp: false,
    extended: true,
    refinement_limit: Some(12),
  }
  {
    precision_: precision,
    rounding_: GdaRoundingMode::HalfEven,
    e_min_: e_min,
    e_max_: e_max,
    clamp_: false,
    extended_: true,
    status_: GdaFlags::new(),
    traps_: GdaTrapSet::new(),
    decimal_,
    mathematical_: decimal_,
  }
}

///|
/// The last working context built: plain operators on values of one precision
/// (the usual case) reuse it.
let gda_plain_working_context_cache : Ref[GdaContext] = Ref(
  gda_plain_working_context_build(34),
)

///|
fn gda_plain_working_context(precision : Int32) -> GdaContext {
  let cached = gda_plain_working_context_cache.val
  if cached.precision_ == precision {
    return cached
  }
  let built = gda_plain_working_context_build(precision)
  gda_plain_working_context_cache.val = built
  built
}

///|
/// The sum of two values, the GDA `add` in the working context at the larger
/// precision of the operands, without flags.
pub fn Decimal::add(self : Decimal, other : Decimal) -> Decimal {
  add(self, other, gda_plain_working_context(max_precision(self, other))).value()
}

///|
pub fn Decimal::sub(self : Decimal, other : Decimal) -> Decimal {
  subtract(self, other, gda_plain_working_context(max_precision(self, other))).value()
}

///|
pub fn Decimal::mul(self : Decimal, other : Decimal) -> Decimal {
  multiply(self, other, gda_plain_working_context(max_precision(self, other))).value()
}

///|
pub fn Decimal::div(self : Decimal, other : Decimal) -> Decimal {
  divide(self, other, gda_plain_working_context(max_precision(self, other))).value()
}

///|
/// The square root in the working context at the precision of the value: NaN
/// outside the domain, as GDA defines it.
pub fn Decimal::sqrt(self : Decimal) -> Decimal {
  sqrt(self, gda_plain_working_context(self.precision_)).value()
}
