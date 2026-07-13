///|
// Public classification, predicate, and sign-copy APIs.

fn quiet_nan_operand(
  value : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard value.class == FpClass::NaN else { return (value, DecimalFlags::new()) }
  let precision = finite_precision_for_coeff(value.coefficient, ctx)
  let payload = if value.coefficient.is_zero() {
    value.coefficient
  } else if value.coefficient.digits10() > precision {
    dec_coeff_div_rem_repr(value.coefficient, dec_coeff_power10_repr(precision)).1
  } else {
    value.coefficient
  }
  (
    make_special_repr(FpClass::NaN, value.negative, payload, precision, false),
    if value.signaling_nan {
      invalid_flags()
    } else {
      DecimalFlags::new()
    },
  )
}

///|
fn quiet_nan_pair_for_next_toward(
  lhs : Decimal,
  rhs : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  if lhs.is_signaling_nan() {
    return Some(quiet_nan_operand(lhs, ctx))
  }
  if rhs.is_signaling_nan() {
    return Some(quiet_nan_operand(rhs, ctx))
  }
  if lhs.is_nan() {
    return Some(quiet_nan_operand(lhs, ctx))
  }
  if rhs.is_nan() {
    return Some(quiet_nan_operand(rhs, ctx))
  }
  None
}

///|
fn quiet_nan_pair(
  lhs : Decimal,
  rhs : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  let selected = match ctx.profile {
    DecimalSemanticProfile::GDA =>
      if lhs.is_signaling_nan() {
        Some(lhs)
      } else if rhs.is_signaling_nan() {
        Some(rhs)
      } else if lhs.is_nan() {
        Some(lhs)
      } else if rhs.is_nan() {
        Some(rhs)
      } else {
        None
      }
    DecimalSemanticProfile::IEEE754 =>
      if lhs.is_nan() {
        Some(lhs)
      } else if rhs.is_nan() {
        Some(rhs)
      } else {
        None
      }
  }
  match selected {
    Some(operand) => {
      let (value, flags) = quiet_nan_operand(operand, ctx)
      let has_signaling = lhs.is_signaling_nan() || rhs.is_signaling_nan()
      return Some(
        (
          value,
          if has_signaling {
            { ..flags, invalid_operation: true }
          } else {
            flags
          },
        ),
      )
    }
    None => return None
  }
}

///|
fn quiet_nan_triplet(
  first : Decimal,
  second : Decimal,
  third : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  let has_signaling = first.is_signaling_nan() ||
    second.is_signaling_nan() ||
    third.is_signaling_nan()
  let selected = match ctx.profile {
    DecimalSemanticProfile::GDA =>
      if first.is_signaling_nan() {
        Some(first)
      } else if second.is_signaling_nan() {
        Some(second)
      } else if third.is_signaling_nan() {
        Some(third)
      } else if first.is_nan() {
        Some(first)
      } else if second.is_nan() {
        Some(second)
      } else if third.is_nan() {
        Some(third)
      } else {
        None
      }
    DecimalSemanticProfile::IEEE754 =>
      if first.is_nan() {
        Some(first)
      } else if second.is_nan() {
        Some(second)
      } else if third.is_nan() {
        Some(third)
      } else {
        None
      }
  }
  match selected {
    Some(operand) => {
      let (value, flags) = quiet_nan_operand(operand, ctx)
      Some(
        (
          value,
          if has_signaling {
            { ..flags, invalid_operation: true }
          } else {
            flags
          },
        ),
      )
    }
    None => None
  }
}

///|
fn quiet_nan_pair_plain(lhs : Decimal, rhs : Decimal) -> Decimal? {
  let precision = max_precision(lhs, rhs)
  if lhs.is_nan() {
    return Some(
      make_special_repr(
        FpClass::NaN,
        lhs.negative,
        lhs.coefficient,
        precision,
        false,
      ),
    )
  }
  if rhs.is_nan() {
    return Some(
      make_special_repr(
        FpClass::NaN,
        rhs.negative,
        rhs.coefficient,
        precision,
        false,
      ),
    )
  }
  None
}

///|
pub fn Decimal::classify(self : Decimal) -> FpClass {
  self.class
}

///|
pub fn Decimal::precision(self : Decimal) -> Int {
  self.precision_
}

///|
pub fn Decimal::sign(self : Decimal) -> Sign {
  match self.class {
    FpClass::NaN => Sign::Zero
    _ =>
      if self.coefficient.is_zero() && self.class == FpClass::Finite {
        Sign::Zero
      } else if self.negative {
        Sign::Negative
      } else {
        Sign::Positive
      }
  }
}

///|
pub fn Decimal::coefficient(self : Decimal) -> BigInt {
  self.coefficient.to_bigint()
}

///|
pub fn Decimal::magnitude(self : Decimal) -> BigInt {
  self.coefficient.to_bigint()
}

///|
pub fn Decimal::exponent10(self : Decimal) -> Int {
  self.exponent10
}

///|
pub fn Decimal::is_negative(self : Decimal) -> Bool {
  self.negative
}

///|
pub fn Decimal::is_signed(self : Decimal) -> Bool {
  self.negative
}

///|
pub fn Decimal::is_finite(self : Decimal) -> Bool {
  self.class == FpClass::Finite
}

///|
pub fn Decimal::is_infinite(self : Decimal) -> Bool {
  self.class == FpClass::Infinity
}

///|
pub fn Decimal::is_nan(self : Decimal) -> Bool {
  self.class == FpClass::NaN
}

///|
pub fn Decimal::is_canonical(_self : Decimal) -> Bool {
  true
}

///|
pub fn Decimal::is_zero(self : Decimal) -> Bool {
  self.class == FpClass::Finite && self.coefficient.is_zero()
}

///|
pub fn Decimal::is_negative_zero(self : Decimal) -> Bool {
  self.is_zero() && self.negative
}

///|
pub fn Decimal::is_quiet_nan(self : Decimal) -> Bool {
  self.class == FpClass::NaN && !self.signaling_nan
}

///|
pub fn Decimal::is_qnan(self : Decimal) -> Bool {
  self.is_quiet_nan()
}

///|
pub fn Decimal::is_signaling_nan(self : Decimal) -> Bool {
  self.class == FpClass::NaN && self.signaling_nan
}

///|
pub fn Decimal::is_snan(self : Decimal) -> Bool {
  self.is_signaling_nan()
}

///|
pub fn Decimal::nan_payload(self : Decimal) -> BigInt {
  if self.class == FpClass::NaN {
    coeff_bigint(self.coefficient)
  } else {
    bigint_zero()
  }
}

///|
pub fn Decimal::get_payload(self : Decimal) -> BigInt {
  self.nan_payload()
}

///|
pub fn Decimal::set_payload(self : Decimal, payload : BigInt) -> Decimal {
  if self.class == FpClass::NaN {
    make_special_repr(
      FpClass::NaN,
      self.negative,
      coeff_from_bigint(payload),
      self.precision_,
      false,
    )
  } else {
    self
  }
}

///|
pub fn Decimal::set_payload_signaling(
  self : Decimal,
  payload : BigInt,
) -> Decimal {
  if self.class == FpClass::NaN {
    make_special_repr(
      FpClass::NaN,
      self.negative,
      coeff_from_bigint(payload),
      self.precision_,
      true,
    )
  } else {
    self
  }
}

///|
pub fn Decimal::quantum(self : Decimal) -> Int {
  self.exponent10
}

///|
pub fn Decimal::is_subnormal(self : Decimal, ctx : DecimalContext) -> Bool {
  self.class == FpClass::Finite &&
  !self.coefficient.is_zero() &&
  adjusted_exponent(self) < ctx.e_min
}

///|
pub fn Decimal::is_normal(self : Decimal, ctx : DecimalContext) -> Bool {
  self.class == FpClass::Finite &&
  !self.coefficient.is_zero() &&
  adjusted_exponent(self) >= ctx.e_min
}

///|
pub fn Decimal::class_name(self : Decimal, ctx : DecimalContext) -> String {
  match self.class {
    FpClass::NaN => if self.signaling_nan { "sNaN" } else { "NaN" }
    FpClass::Infinity => if self.negative { "-Infinity" } else { "+Infinity" }
    FpClass::Finite =>
      if self.coefficient.is_zero() {
        if self.negative {
          "-Zero"
        } else {
          "+Zero"
        }
      } else if self.is_subnormal(ctx) {
        if self.negative {
          "-Subnormal"
        } else {
          "+Subnormal"
        }
      } else if self.negative {
        "-Normal"
      } else {
        "+Normal"
      }
  }
}

///|
pub fn Decimal::neg(self : Decimal) -> Decimal {
  { ..self, negative: !self.negative }
}

///|
pub fn Decimal::abs(self : Decimal) -> Decimal {
  if self.negative {
    self.neg()
  } else {
    self
  }
}

///|
pub fn Decimal::copy(self : Decimal) -> Decimal {
  self
}

///|
pub fn Decimal::copy_abs(self : Decimal) -> Decimal {
  { ..self, negative: false }
}

///|
pub fn Decimal::copy_negate(self : Decimal) -> Decimal {
  { ..self, negative: !self.negative }
}

///|
pub fn Decimal::copy_sign(self : Decimal, other : Decimal) -> Decimal {
  { ..self, negative: other.negative }
}
