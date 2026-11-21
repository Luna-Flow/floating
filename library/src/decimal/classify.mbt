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
    dec_coeff_mod_repr(value.coefficient, dec_coeff_power10_repr(limit))
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
  let selected = if lhs.is_nan() {
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
  let selected = if first.is_nan() {
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
pub fn Decimal::exponent10(self : Decimal) -> Int32 {
  self.exponent10
}

///|
pub fn Decimal::is_negative(self : Decimal) -> Bool {
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
pub fn Decimal::is_signaling_nan(self : Decimal) -> Bool {
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
  let precision = self.precision_
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
/// Whether `self` and `other` are the same datum: the same class, sign,
/// signaling bit, coefficient (the payload of a NaN), exponent and precision
/// label. Equal values of different cohort members, a zero and its negative and
/// two NaNs that differ only in payload are not identical; `==` compares values
/// and `total_order_compare` orders representations.
pub fn Decimal::identical(self : Decimal, other : Decimal) -> Bool {
  self.class == other.class &&
  self.negative == other.negative &&
  self.signaling_nan == other.signaling_nan &&
  self.precision_ == other.precision_ &&
  self.exponent10 == other.exponent10 &&
  dec_coeff_compare_repr(self.coefficient, other.coefficient) == 0
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
/// The ten-valued class of IEEE 754-2019 clause 5.7.2; `class_name` is its
/// textual form.
pub fn Decimal::class_of(self : Decimal, ctx : DecimalContext) -> IeeeClass {
  match self.class {
    FpClass::NaN => if self.signaling_nan { SignalingNaN } else { QuietNaN }
    FpClass::Infinity =>
      if self.negative {
        NegativeInfinity
      } else {
        PositiveInfinity
      }
    FpClass::Finite =>
      if self.coefficient.is_zero() {
        if self.negative {
          NegativeZero
        } else {
          PositiveZero
        }
      } else if self.is_subnormal(ctx) {
        if self.negative {
          NegativeSubnormal
        } else {
          PositiveSubnormal
        }
      } else if self.negative {
        NegativeNormal
      } else {
        PositiveNormal
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
pub fn Decimal::copy_sign(self : Decimal, other : Decimal) -> Decimal {
  { ..self, negative: other.negative, }
}
