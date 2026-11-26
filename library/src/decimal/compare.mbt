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
  a_digits : Int32,
  b_digits : Int32,
) -> Int32 {
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
fn compare_finite(a : Decimal, b : Decimal) -> Int32 {
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
) -> Result[Int32, @def.ArithmeticError] {
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
        if self.signum() == Sign::Negative {
          -1
        } else {
          1
        }
      (_, FpClass::Infinity) =>
        if other.signum() == Sign::Negative {
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
fn decimal_compare_relation(lhs : Decimal, rhs : Decimal) -> @def.PartialOrder {
  if lhs.class == FpClass::NaN || rhs.class == FpClass::NaN {
    return @def.PartialOrder::Unordered
  }
  let comparison = lhs.compare(rhs)
  if comparison < 0 {
    @def.PartialOrder::Less
  } else if comparison > 0 {
    @def.PartialOrder::Greater
  } else {
    @def.PartialOrder::Equal
  }
}

///|
/// IEEE 754-2019 5.11 quiet comparison: the relation of `self` to `other`,
/// where `-0 == +0` (cohort members compare equal) and a NaN is unordered.
/// Only a signaling NaN raises invalid.
pub fn Decimal::compare_quiet(
  self : Decimal,
  other : Decimal,
) -> (@def.PartialOrder, DecimalFlags) {
  (
    decimal_compare_relation(self, other),
    if self.is_signaling_nan() || other.is_signaling_nan() {
      invalid_flags()
    } else {
      DecimalFlags::new()
    },
  )
}

///|
/// IEEE 754-2019 5.11 signaling comparison: as `compare_quiet`, but any NaN
/// operand raises invalid.
pub fn Decimal::compare_signaling(
  self : Decimal,
  other : Decimal,
) -> (@def.PartialOrder, DecimalFlags) {
  let relation = decimal_compare_relation(self, other)
  (
    relation,
    if relation == @def.PartialOrder::Unordered {
      invalid_flags()
    } else {
      DecimalFlags::new()
    },
  )
}

///|
/// compareQuietEqual (IEEE 754-2019 Table 5.1).
pub fn Decimal::compare_quiet_equal(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_quiet(other)
  (relation == @def.PartialOrder::Equal, flags)
}

///|
/// compareSignalingEqual (IEEE 754-2019 Table 5.2).
pub fn Decimal::compare_signaling_equal(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_signaling(other)
  (relation == @def.PartialOrder::Equal, flags)
}

///|
/// compareQuietLess (IEEE 754-2019 Table 5.2).
pub fn Decimal::compare_quiet_less(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_quiet(other)
  (relation == @def.PartialOrder::Less, flags)
}

///|
/// compareSignalingLess (IEEE 754-2019 Table 5.1).
pub fn Decimal::compare_signaling_less(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_signaling(other)
  (relation == @def.PartialOrder::Less, flags)
}

///|
/// compareQuietLessEqual (IEEE 754-2019 Table 5.2).
pub fn Decimal::compare_quiet_less_equal(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_quiet(other)
  (
    relation == @def.PartialOrder::Less || relation == @def.PartialOrder::Equal,
    flags,
  )
}

///|
/// compareSignalingLessEqual (IEEE 754-2019 Table 5.1).
pub fn Decimal::compare_signaling_less_equal(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_signaling(other)
  (
    relation == @def.PartialOrder::Less || relation == @def.PartialOrder::Equal,
    flags,
  )
}

///|
/// compareQuietUnordered (IEEE 754-2019 Table 5.2).
pub fn Decimal::compare_quiet_unordered(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_quiet(other)
  (relation == @def.PartialOrder::Unordered, flags)
}

///|
/// Numeric three-way comparison with `-0 == +0`. NaN has no numeric order;
/// so that `Compare` stays a total preorder (and sorting never aborts), every
/// NaN compares equal to every other NaN and greater than every non-NaN.
/// Use the quiet/signaling predicates or `compare_checked` for IEEE semantics.
pub fn Decimal::compare(self : Decimal, other : Decimal) -> Int32 {
  match (self.class == FpClass::NaN, other.class == FpClass::NaN) {
    (true, true) => return 0
    (true, false) => return 1
    (false, true) => return -1
    (false, false) => ()
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
    (FpClass::Infinity, _) =>
      if self.signum() == Sign::Negative {
        -1
      } else {
        1
      }
    (_, FpClass::Infinity) =>
      if other.signum() == Sign::Negative {
        1
      } else {
        -1
      }
    (FpClass::Finite, FpClass::Finite) => compare_finite(self, other)
    _ => 0
  }
}

///|
/// Compares the representations of two values in the total order of IEEE
/// 754-2019 5.10 and returns -1, 0 or 1. The order is `-NaN < -sNaN < -inf <
/// negative finite < -0 < +0 < positive finite < +inf < +sNaN < +NaN`. Equal
/// finite values are ordered by exponent: `1.00` comes before `1.0`, and for
/// negative values the order is reversed. NaNs of the same sign and kind are
/// ordered by payload. It returns 0 only for identical representations, takes no
/// context, rounds nothing and raises no flags.
pub fn Decimal::total_order_compare(self : Decimal, other : Decimal) -> Int32 {
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
/// IEEE 754-2019 totalOrder (§5.10): `x` is ordered at or before `y`.
pub fn Decimal::total_order(self : Decimal, other : Decimal) -> Bool {
  self.total_order_compare(other) <= 0
}

///|
/// IEEE 754-2019 totalOrderMag (§5.10): totalOrder of the absolute values.
pub fn Decimal::total_order_mag(self : Decimal, other : Decimal) -> Bool {
  { ..self, negative: false, }.total_order_compare({ ..other, negative: false, }) <=
  0
}

///|
pub fn Decimal::min_num(self : Decimal, other : Decimal) -> Decimal {
  match plain_minmax_nan_result(self, other) {
    Some(result) => result
    None => if self.compare(other) <= 0 { self } else { other }
  }
}

///|
pub fn Decimal::max_num(self : Decimal, other : Decimal) -> Decimal {
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

///|
pub fn Decimal::clamp_checked(
  self : Decimal,
  min~ : Decimal,
  max~ : Decimal,
) -> Result[Decimal, @def.ArithmeticError] {
  guard min.classify() != FpClass::NaN && max.classify() != FpClass::NaN else {
    return Err(
      @def.ArithmeticError::domain_error("clamp bounds must be ordered values"),
    )
  }
  guard min.compare(max) <= 0 else {
    return Err(@def.ArithmeticError::domain_error("min must not exceed max"))
  }
  Ok(self.clamp(min~, max~))
}
