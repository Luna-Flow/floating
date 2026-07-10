///|
// Public comparison and ordering APIs.

fn plain_minmax_nan_result(lhs : Decimal, rhs : Decimal) -> Decimal? {
  match quiet_nan_pair_plain(lhs, rhs) {
    Some(value) =>
      if lhs.is_signaling_nan() || rhs.is_signaling_nan() {
        Some(value)
      } else if lhs.is_nan() && rhs.is_nan() {
        Some(value)
      } else if lhs.is_nan() {
        Some(rhs)
      } else {
        Some(lhs)
      }
    None => None
  }
}

///|
fn compare_same_adjusted_magnitude(
  a : Decimal,
  b : Decimal,
  a_digits : Int,
  b_digits : Int,
) -> Int {
  if a_digits == b_digits {
    return dec_coeff_compare_repr(a.coefficient, b.coefficient)
  }
  if a_digits > b_digits &&
    dec_coeff_compare_repr(a.coefficient, dec_coeff_power10_repr(a_digits - 1)) ==
    0 {
    return dec_coeff_compare_repr(
      dec_coeff_power10_repr(b_digits - 1),
      b.coefficient,
    )
  }
  if b_digits > a_digits &&
    dec_coeff_compare_repr(b.coefficient, dec_coeff_power10_repr(b_digits - 1)) ==
    0 {
    return dec_coeff_compare_repr(
      a.coefficient,
      dec_coeff_power10_repr(a_digits - 1),
    )
  }
  if a_digits > b_digits {
    dec_coeff_compare_scaled_repr(
      a.coefficient,
      b.coefficient,
      a_digits - b_digits,
    )
  } else {
    -dec_coeff_compare_scaled_repr(
      b.coefficient,
      a.coefficient,
      b_digits - a_digits,
    )
  }
}

///|
fn compare_finite_magnitude_repr(
  lhs_coefficient : DecCoeff,
  lhs_exponent10 : Int,
  rhs_coefficient : DecCoeff,
  rhs_exponent10 : Int,
) -> Int {
  if lhs_coefficient.is_zero() || rhs_coefficient.is_zero() {
    return compare_int(
      if lhs_coefficient.is_zero() {
        0
      } else {
        1
      },
      if rhs_coefficient.is_zero() {
        0
      } else {
        1
      },
    )
  }
  let lhs_digits = lhs_coefficient.digits10()
  let rhs_digits = rhs_coefficient.digits10()
  let adjusted_cmp = compare_int(
    lhs_exponent10 + lhs_digits - 1,
    rhs_exponent10 + rhs_digits - 1,
  )
  if adjusted_cmp != 0 {
    return adjusted_cmp
  }
  if lhs_exponent10 <= rhs_exponent10 {
    dec_coeff_compare_scaled_repr(
      lhs_coefficient,
      rhs_coefficient,
      rhs_exponent10 - lhs_exponent10,
    )
  } else {
    -dec_coeff_compare_scaled_repr(
      rhs_coefficient,
      lhs_coefficient,
      lhs_exponent10 - rhs_exponent10,
    )
  }
}

///|
fn compare_finite(a : Decimal, b : Decimal) -> Int {
  if a.coefficient.is_zero() {
    if b.coefficient.is_zero() {
      return 0
    }
    return if b.negative { 1 } else { -1 }
  }
  if b.coefficient.is_zero() {
    return if a.negative { -1 } else { 1 }
  }
  if a.negative != b.negative {
    return if a.negative { -1 } else { 1 }
  }
  let direction = if a.negative { -1 } else { 1 }
  let adjusted_cmp = compare_int(adjusted_exponent(a), adjusted_exponent(b))
  if adjusted_cmp != 0 {
    return direction * adjusted_cmp
  }
  let a_digits = a.coefficient.digits10()
  let b_digits = b.coefficient.digits10()
  let magnitude_cmp = compare_same_adjusted_magnitude(a, b, a_digits, b_digits)
  direction * magnitude_cmp
}

///|
pub fn Decimal::compare_checked(
  self : Decimal,
  other : Decimal,
) -> Result[Int, @def.ArithmeticError] {
  guard self.class != FpClass::NaN && other.class != FpClass::NaN else {
    return Err(@def.ArithmeticError::unordered_comparison("NaN is unordered"))
  }
  Ok(
    match (self.class, other.class) {
      (FpClass::Infinity, FpClass::Infinity) =>
        if self.negative == other.negative {
          0
        } else if self.negative {
          -1
        } else {
          1
        }
      (FpClass::Infinity, _) =>
        if self.sign() == Sign::Negative {
          -1
        } else {
          1
        }
      (_, FpClass::Infinity) =>
        if other.sign() == Sign::Negative {
          1
        } else {
          -1
        }
      (FpClass::Finite, FpClass::Finite) => compare_finite(self, other)
      _ => 0
    },
  )
}

///|
pub fn Decimal::compare_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let (lhs, rhs, operand_flags) = prepare_binary_operands_for_context(
    self, other, ctx,
  )
  match quiet_nan_pair(lhs, rhs, ctx) {
    Some((value, flags)) => return (value, operand_flags.combine(flags))
    None => ()
  }
  (decimal_compare_result(lhs.compare(rhs), ctx), operand_flags)
}

///|
pub fn Decimal::compare_total_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Int, DecimalFlags) {
  let (lhs, rhs, operand_flags) = prepare_binary_operands_for_context(
    self, other, ctx,
  )
  (lhs.compare_total(rhs), operand_flags)
}

///|
pub fn Decimal::compare_total_magnitude_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Int, DecimalFlags) {
  let (lhs, rhs, operand_flags) = prepare_binary_operands_for_context(
    self, other, ctx,
  )
  (lhs.compare_total_magnitude(rhs), operand_flags)
}

///|
pub fn Decimal::compare_signal_ctx(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let (lhs, rhs, operand_flags) = prepare_binary_operands_for_context(
    self, other, ctx,
  )
  match quiet_nan_pair(lhs, rhs, ctx) {
    Some((value, flags)) =>
      return (
        value,
        operand_flags.combine({ ..flags, invalid_operation: true }),
      )
    None => ()
  }
  (decimal_compare_result(lhs.compare(rhs), ctx), operand_flags)
}

///|
pub fn Decimal::compare(self : Decimal, other : Decimal) -> Int {
  guard self.class != FpClass::NaN && other.class != FpClass::NaN else {
    abort("NaN is unordered")
  }
  match (self.class, other.class) {
    (FpClass::Infinity, FpClass::Infinity) =>
      if self.negative == other.negative {
        0
      } else if self.negative {
        -1
      } else {
        1
      }
    (FpClass::Infinity, _) => if self.sign() == Sign::Negative { -1 } else { 1 }
    (_, FpClass::Infinity) =>
      if other.sign() == Sign::Negative {
        1
      } else {
        -1
      }
    (FpClass::Finite, FpClass::Finite) => compare_finite(self, other)
    _ => 0
  }
}

///|
pub fn Decimal::compare_total(self : Decimal, other : Decimal) -> Int {
  if self.negative != other.negative {
    return if self.negative { -1 } else { 1 }
  }
  let direction = decimal_order_sign(self)
  match (self.class, other.class) {
    (FpClass::NaN, FpClass::NaN) => {
      let signal_cmp = compare_int(
        if self.signaling_nan {
          0
        } else {
          1
        },
        if other.signaling_nan {
          0
        } else {
          1
        },
      )
      if signal_cmp != 0 {
        return direction * signal_cmp
      }
      let payload_cmp = dec_coeff_compare_repr(
        self.coefficient,
        other.coefficient,
      )
      if payload_cmp != 0 {
        return direction * payload_cmp
      }
      0
    }
    (FpClass::NaN, _) => direction
    (_, FpClass::NaN) => -direction
    (FpClass::Infinity, FpClass::Infinity) => 0
    (FpClass::Infinity, _) => direction
    (_, FpClass::Infinity) => -direction
    (FpClass::Finite, FpClass::Finite) => {
      let numeric = compare_finite(self, other)
      if numeric != 0 {
        return numeric
      }
      let exponent_cmp = compare_int(self.exponent10, other.exponent10)
      if exponent_cmp != 0 {
        return direction * exponent_cmp
      }
      dec_coeff_compare_repr(self.coefficient, other.coefficient) * direction
    }
  }
}

///|
pub fn Decimal::compare_total_magnitude(self : Decimal, other : Decimal) -> Int {
  { ..self, negative: false }.compare_total({ ..other, negative: false })
}

///|
pub fn Decimal::min(self : Decimal, other : Decimal) -> Decimal {
  match plain_minmax_nan_result(self, other) {
    Some(result) => result
    None => if self.compare(other) <= 0 { self } else { other }
  }
}

///|
pub fn Decimal::max(self : Decimal, other : Decimal) -> Decimal {
  match plain_minmax_nan_result(self, other) {
    Some(result) => result
    None => if self.compare(other) >= 0 { self } else { other }
  }
}

///|
pub fn Decimal::clamp(
  self : Decimal,
  min~ : Decimal,
  max~ : Decimal,
) -> Decimal {
  guard min.classify() != FpClass::NaN && max.classify() != FpClass::NaN else {
    abort("clamp bounds must be ordered values")
  }
  guard min.compare(max) <= 0 else { abort("min must not exceed max") }
  if self.classify() == FpClass::NaN {
    self
  } else if self.compare(min) < 0 {
    min
  } else if self.compare(max) > 0 {
    max
  } else {
    self
  }
}
