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
    gda_coeff_zero()
  } else if value.coefficient.digits10() > limit {
    gda_coeff_div_rem_repr(value.coefficient, gda_coeff_power10_repr(limit)).1
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
  let selected = if lhs.is_signaling_nan() {
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
  match selected {
    Some(operand) => {
      let (value, flags) = quiet_nan_operand(operand, ctx)
      let has_signaling = lhs.is_signaling_nan() || rhs.is_signaling_nan()
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
  let has_signaling = first.is_signaling_nan() ||
    second.is_signaling_nan() ||
    third.is_signaling_nan()
  let selected = if first.is_signaling_nan() {
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
pub fn Decimal::precision(self : Decimal) -> Int32 {
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
pub fn Decimal::exponent10(self : Decimal) -> Int32 {
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
  // IEEE 754-2019 §9.7 getPayload: -1 when the operand is not a NaN.
  if self.class == FpClass::NaN {
    self.nan_payload()
  } else {
    BigInt::from_int(-1)
  }
}

///|
/// IEEE 754-2019 §9.7 setPayload and setPayloadSignaling: a NaN carrying the
/// payload when it is a non-negative integer the format can hold (at most
/// `precision - 1` digits, like the trailing significand of an interchange
/// NaN), otherwise +0 with preferred exponent 0. The receiver only supplies the
/// format precision and the sign bit of a NaN result.
fn Decimal::payload_result(
  self : Decimal,
  payload : BigInt,
  signaling : Bool,
) -> Decimal {
  let precision = Int32::max(1, self.precision_)
  let coefficient = coeff_from_bigint(payload)
  if payload < BigInt::from_int(0) ||
    (coeff_digits(coefficient) > precision - 1 && !coefficient.is_zero()) {
    return Decimal::zero(precision~)
  }
  make_special_repr(
    FpClass::NaN,
    self.negative,
    coefficient,
    precision,
    signaling,
  )
}

///|
pub fn Decimal::set_payload(self : Decimal, payload : BigInt) -> Decimal {
  Decimal::payload_result(self, payload, false)
}

///|
pub fn Decimal::set_payload_signaling(
  self : Decimal,
  payload : BigInt,
) -> Decimal {
  Decimal::payload_result(self, payload, true)
}

///|
pub fn Decimal::quantum(self : Decimal) -> Int32 {
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
