///|
/// Rounds a finite value to an integer under `mode`, keeping its precision and
/// the sign of a zero result. Also reports whether the value changed.
fn binary_round_to_integral(
  value : BinFloat,
  mode : BinaryRoundingMode,
) -> (BinFloat, Bool) {
  if value.coefficient_.is_zero() || value.exponent2 >= 0 {
    return (value, false)
  }
  let (retained, round_bit, sticky) = binary_split_shift(
    value.coefficient_,
    -value.exponent2,
  )
  let integral = binary_apply_round_bits(
    retained,
    round_bit,
    sticky,
    value.negative,
    mode,
  )
  let rounded = if integral.is_zero() {
    finite_zero(value.negative, value.precision_)
  } else {
    // |integral| <= 2^(top + 1), so it fits the operand precision.
    finite_from_parts(value.negative, integral, 0, value.precision_)
  }
  (rounded, round_bit || sticky)
}

///|
fn binary_integral_special(value : BinFloat) -> (BinFloat, BinaryFlags)? {
  match value.class {
    FpClass::NaN =>
      Some(
        (
          binary_quiet_nan(value, value.precision_),
          if value.signaling_nan {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity => Some((value, BinaryFlags::new()))
    FpClass::Finite => None
  }
}

///|
/// IEEE 754 roundToIntegral in the context's rounding direction. The result
/// keeps the operand's precision; only a signaling NaN raises a flag.
pub fn BinFloat::to_integral_value_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match binary_integral_special(self) {
    Some(result) => result
    None =>
      (binary_round_to_integral(self, context.rounding).0, BinaryFlags::new())
  }
}

///|
/// IEEE 754 roundToIntegralExact: as `to_integral_value_ctx`, and raises
/// inexact when the result differs from the operand.
pub fn BinFloat::to_integral_exact_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match binary_integral_special(self) {
    Some(result) => result
    None => {
      let (value, changed) = binary_round_to_integral(self, context.rounding)
      (
        value,
        if changed {
          binary_inexact_flags(false)
        } else {
          BinaryFlags::new()
        },
      )
    }
  }
}

///|
fn BinFloat::integral_with(
  self : BinFloat,
  mode : BinaryRoundingMode,
) -> BinFloat {
  match binary_integral_special(self) {
    Some(result) => result.0
    None => binary_round_to_integral(self, mode).0
  }
}

///|
/// Largest integer not greater than the value (roundToIntegralTowardNegative).
pub fn BinFloat::floor(self : BinFloat) -> BinFloat {
  self.integral_with(RoundTowardNegative)
}

///|
/// Smallest integer not less than the value (roundToIntegralTowardPositive).
pub fn BinFloat::ceil(self : BinFloat) -> BinFloat {
  self.integral_with(RoundTowardPositive)
}

///|
/// Integer part of the value (roundToIntegralTowardZero).
pub fn BinFloat::trunc(self : BinFloat) -> BinFloat {
  self.integral_with(RoundTowardZero)
}

///|
/// Nearest integer, halfway cases away from zero (roundToIntegralTiesToAway).
pub fn BinFloat::round(self : BinFloat) -> BinFloat {
  self.integral_with(RoundTiesToAway)
}

///|
/// Nearest integer, halfway cases to even (roundToIntegralTiesToEven).
pub fn BinFloat::round_ties_even(self : BinFloat) -> BinFloat {
  self.integral_with(RoundTiesToEven)
}
