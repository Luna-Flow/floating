// Accessors of the private engine context that only the white-box tests use.

///|
fn DecimalContext::precision(self : DecimalContext) -> Int32 {
  self.precision
}

///|
fn DecimalContext::rounding(self : DecimalContext) -> RoundingMode {
  self.rounding
}

///|
fn DecimalContext::e_max(self : DecimalContext) -> Int32 {
  self.e_max
}

///|
fn DecimalContext::clamp(self : DecimalContext) -> Bool {
  self.clamp
}

///|
fn DecimalContext::exact() -> DecimalContext {
  decimal_exact_work_context()
}

///|
impl Eq for DecimalContext with fn equal(a, b) {
  a.precision == b.precision &&
  a.rounding == b.rounding &&
  a.decimal_rounding == b.decimal_rounding &&
  a.e_min == b.e_min &&
  a.e_max == b.e_max &&
  a.clamp == b.clamp &&
  a.extended == b.extended &&
  a.refinement_limit == b.refinement_limit
}
