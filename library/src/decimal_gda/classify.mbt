///|
// Public classification, predicate, and sign-copy APIs.

fn quiet_nan_operand(
  value : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard value.class == FpClass::NaN else { return (value, DecimalFlags::new()) }
  let precision = finite_precision_for_coeff(value.coefficient, ctx)
  // IEEE 754-2019 §3.5.2 and §6.2.3: a propagated payload is one the
  // destination can hold, and an interchange-shaped (clamped) format holds at
  // most p - 1 digits, as `from_string_ctx` already enforces.
  let limit = if ctx.clamp && ctx.precision > 0 {
    precision - 1
  } else {
    precision
  }
  let payload = if value.coefficient.is_zero() {
    value.coefficient
  } else if limit == 0 {
    dec_coeff_zero()
  } else if value.coefficient.digits10() > limit {
    dec_coeff_div_rem_repr(value.coefficient, dec_coeff_power10_repr(limit)).1
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
  if lhs.is_snan() {
    return Some(quiet_nan_operand(lhs, ctx))
  }
  if rhs.is_snan() {
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
  let selected = if lhs.is_snan() {
    Some(lhs)
  } else if rhs.is_snan() {
    Some(rhs)
  } else if lhs.is_nan() {
    Some(lhs)
  } else if rhs.is_nan() {
    Some(rhs)
  } else {
    None
  }
  match selected {
    Some(operand) => {
      let (value, flags) = quiet_nan_operand(operand, ctx)
      let has_signaling = lhs.is_snan() || rhs.is_snan()
      return Some(
        (
          value,
          if has_signaling {
            { ..flags, invalid_operation: true, }
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
  let has_signaling = first.is_snan() || second.is_snan() || third.is_snan()
  let selected = if first.is_snan() {
    Some(first)
  } else if second.is_snan() {
    Some(second)
  } else if third.is_snan() {
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
  match selected {
    Some(operand) => {
      let (value, flags) = quiet_nan_operand(operand, ctx)
      Some(
        (
          value,
          if has_signaling {
            { ..flags, invalid_operation: true, }
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
pub fn Decimal::classify(self : Decimal) -> FpClass {
  self.class
}

///|
pub fn Decimal::precision(self : Decimal) -> Int32 {
  self.precision_
}

///|
pub fn Decimal::signum(self : Decimal) -> Sign {
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
pub fn Decimal::exponent10(self : Decimal) -> Int32 {
  self.exponent10
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
pub fn Decimal::is_qnan(self : Decimal) -> Bool {
  self.class == FpClass::NaN && !self.signaling_nan
}

///|
pub fn Decimal::is_snan(self : Decimal) -> Bool {
  self.class == FpClass::NaN && self.signaling_nan
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
fn Decimal::is_subnormal(self : Decimal, ctx : DecimalContext) -> Bool {
  self.class == FpClass::Finite &&
  !self.coefficient.is_zero() &&
  adjusted_exponent(self) < ctx.e_min
}

///|
fn Decimal::is_normal(self : Decimal, ctx : DecimalContext) -> Bool {
  self.class == FpClass::Finite &&
  !self.coefficient.is_zero() &&
  adjusted_exponent(self) >= ctx.e_min
}

///|
fn Decimal::class_name(self : Decimal, ctx : DecimalContext) -> String {
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
  { ..self, negative: !self.negative, }
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
  { ..self, negative: false, }
}

///|
pub fn Decimal::copy_negate(self : Decimal) -> Decimal {
  { ..self, negative: !self.negative, }
}

///|
pub fn Decimal::copy_sign(self : Decimal, other : Decimal) -> Decimal {
  { ..self, negative: other.negative, }
}
