///|
fn binary_scaled_integer_mod4(value : Binary, shift : Int32) -> Int32? {
  guard value.classify() == FpClass::Finite else { return None }
  guard value.exponent2() + shift >= 0 else { return None }
  let exponent = value.exponent2() + shift
  let magnitude_residue = if value.is_zero() || exponent >= 2 {
    0
  } else if exponent == 1 {
    if value.coefficient_().test_bit(0) {
      2
    } else {
      0
    }
  } else {
    (if value.coefficient_().test_bit(0) { 1 } else { 0 }) +
    (if value.coefficient_().test_bit(1) { 2 } else { 0 })
  }
  Some(
    if value.is_sign_minus() && magnitude_residue != 0 {
      4 - magnitude_residue
    } else {
      magnitude_residue
    },
  )
}

///|
fn binary_pi_scaled_exact(
  value : Binary,
  operation : BinaryTrigonometricOperation,
  context : BinaryContext,
) -> (Binary, BinaryFlags)? {
  let integer = binary_scaled_integer_mod4(value, 0)
  let twice = binary_scaled_integer_mod4(value, 1)
  let four_times = binary_scaled_integer_mod4(value, 2)
  match (integer, twice) {
    (Some(n), _) => {
      let sine = if value.is_sign_minus() {
        Binary::negative_zero_raw(precision=context.precision)
      } else {
        Binary::zero_raw(precision=context.precision)
      }
      let cosine = if n % 2 == 0 {
        Binary::one_raw(precision=context.precision)
      } else {
        Binary::one_raw(precision=context.precision).neg()
      }
      // tanPi takes the sign of sinPi(n) / cosPi(n) (IEEE 754-2019 §9.2.1,
      // C23 Annex F): -0 for positive odd and +0 for negative odd n.
      let tangent = if value.is_sign_minus() != (n % 2 != 0) {
        Binary::negative_zero_raw(precision=context.precision)
      } else {
        Binary::zero_raw(precision=context.precision)
      }
      let result = match operation {
        BinaryTrigonometricOperation::Sin => sine
        BinaryTrigonometricOperation::Cos => cosine
        BinaryTrigonometricOperation::Tan => tangent
      }
      Some((result, BinaryFlags::new()))
    }
    (_, Some(n)) if n % 2 != 0 => {
      let residue = n
      let sine = match residue {
        1 => Binary::one_raw(precision=context.precision)
        3 => Binary::one_raw(precision=context.precision).neg()
        _ => Binary::zero_raw(precision=context.precision)
      }
      let cosine = Binary::zero_raw(precision=context.precision)
      let result = match operation {
        BinaryTrigonometricOperation::Sin => sine
        BinaryTrigonometricOperation::Cos => cosine
        BinaryTrigonometricOperation::Tan =>
          Binary::inf_raw(
            if sine.is_sign_minus() {
              Sign::Negative
            } else {
              Sign::Positive
            },
            precision=context.precision,
          )
      }
      Some(
        (
          result,
          if operation == BinaryTrigonometricOperation::Tan {
            binary_division_by_zero_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    }
    _ =>
      match (operation, four_times) {
        (BinaryTrigonometricOperation::Tan, Some(n)) if n % 2 != 0 =>
          Some(
            (
              if n == 1 {
                Binary::one_raw(precision=context.precision)
              } else {
                Binary::one_raw(precision=context.precision).neg()
              },
              BinaryFlags::new(),
            ),
          )
        _ => None
      }
  }
}

///|
fn binary_pi_periodic_remainder(value : Binary) -> Binary? {
  guard value.classify() == FpClass::Finite else { return None }
  if value.is_zero() {
    return Some(value)
  }
  if value.exponent2() >= 1 {
    return Some(
      if value.is_sign_minus() {
        Binary::negative_zero_raw(precision=value.precision())
      } else {
        Binary::zero_raw(precision=value.precision())
      },
    )
  }
  let modulus_shift = 1 - value.exponent2()
  let magnitude = value.coefficient_()
  let residue = if modulus_shift >= magnitude.bit_length() {
    magnitude
  } else {
    let quotient = magnitude.shift_right(modulus_shift)
    magnitude.sub_checked(quotient.shift_left(modulus_shift)).unwrap()
  }
  if residue.is_zero() {
    return Some(
      if value.is_sign_minus() {
        Binary::negative_zero_raw(precision=value.precision())
      } else {
        Binary::zero_raw(precision=value.precision())
      },
    )
  }
  // Built at the width of the argument, not of the residue: a Binary of
  // width w stores nothing below 2^(e_min - (w - 1)), so a tiny argument near
  // the implementation subnormal limit would be flushed to zero.
  let reduced = Binary::make_coeff(
    residue,
    value.exponent2(),
    Int32::max(value.precision(), residue.bit_length()),
  )
  Some(if value.is_sign_minus() { reduced.neg() } else { reduced })
}

///|
fn binary_pi_scaled_quadrant_reduction(
  value : Binary,
  work_precision : Int32,
) -> (Binary, Int32)? {
  let threshold_precision = Int32::max(4, value.precision())
  let quarter = Binary::make_coeff(Coeff::one(), -2, threshold_precision)
  let three_quarters = Binary::make_coeff(
    Coeff::from_uint64(3UL),
    -2,
    threshold_precision,
  )
  let five_quarters = Binary::make_coeff(
    Coeff::from_uint64(5UL),
    -2,
    threshold_precision,
  )
  let seven_quarters = Binary::make_coeff(
    Coeff::from_uint64(7UL),
    -2,
    threshold_precision,
  )
  let quadrant = if value.compare(seven_quarters.neg()) < 0 {
    -4
  } else if value.compare(five_quarters.neg()) < 0 {
    -3
  } else if value.compare(three_quarters.neg()) < 0 {
    -2
  } else if value.compare(quarter.neg()) < 0 {
    -1
  } else if value.compare(quarter) < 0 {
    0
  } else if value.compare(three_quarters) < 0 {
    1
  } else if value.compare(five_quarters) < 0 {
    2
  } else if value.compare(seven_quarters) < 0 {
    3
  } else {
    4
  }
  let half_integer = match quadrant {
    -4 => Binary::from_int_raw(-2, precision=work_precision)
    -3 =>
      Binary::make_coeff(
        Coeff::from_uint64(3UL),
        -1,
        work_precision,
        negative=true,
      )
    -2 => Binary::from_int_raw(-1, precision=work_precision)
    -1 => Binary::make_coeff(Coeff::one(), -1, work_precision, negative=true)
    0 => Binary::zero_raw(precision=work_precision)
    1 => Binary::make_coeff(Coeff::one(), -1, work_precision)
    2 => Binary::one_raw(precision=work_precision)
    3 => Binary::make_coeff(Coeff::from_uint64(3UL), -1, work_precision)
    _ => Binary::from_int_raw(2, precision=work_precision)
  }
  let (residual, flags) = value.sub_ctx(
    half_integer,
    binary_working_context(work_precision),
  )
  guard !flags.inexact() else { return None }
  let residue = match quadrant {
    -3 | 1 => 1
    -2 | 2 => 2
    -1 | 3 => 3
    _ => 0
  }
  Some((residual, residue))
}

///|
fn binary_pi_scaled_bounds(
  value : Binary,
  operation : BinaryTrigonometricOperation,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let reduced = match binary_pi_periodic_remainder(value) {
    Some(remainder) => remainder
    None => return None
  }
  let reduction = match
    binary_pi_scaled_quadrant_reduction(reduced, work_precision) {
    Some(result) => result
    None => return None
  }
  let residual = reduction.0
  let quadrant = reduction.1
  let pi = match binary_pi_bounds(work_precision) {
    Some(value) => value
    None => return None
  }
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let input_lower = residual.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let input_upper = residual.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardPositive,
  )
  let lower_candidates = [
    input_lower.mul_ctx(pi.0, downward).0,
    input_lower.mul_ctx(pi.1, downward).0,
    input_upper.mul_ctx(pi.0, downward).0,
    input_upper.mul_ctx(pi.1, downward).0,
  ]
  let upper_candidates = [
    input_lower.mul_ctx(pi.0, upward).0,
    input_lower.mul_ctx(pi.1, upward).0,
    input_upper.mul_ctx(pi.0, upward).0,
    input_upper.mul_ctx(pi.1, upward).0,
  ]
  let mut lower = lower_candidates[0]
  let mut upper = upper_candidates[0]
  for candidate in lower_candidates[1:] {
    if candidate.compare(lower) < 0 {
      lower = candidate
    }
  }
  for candidate in upper_candidates[1:] {
    if candidate.compare(upper) > 0 {
      upper = candidate
    }
  }
  binary_reduced_trigonometric_bounds(
    lower, upper, quadrant, operation, work_precision,
  )
}

///|
fn Binary::try_pi_scaled_ctx(
  self : Binary,
  operation : BinaryTrigonometricOperation,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match self.class() {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling() {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity => Ok(binary_invalid_value(context))
    FpClass::Finite => {
      match binary_pi_scaled_exact(self, operation, context) {
        Some(result) => return Ok(result)
        None => ()
      }
      let mut budget = CertifiedRefinementBudget::new(
        Int32::max(context.precision + 96, self.precision() + 32),
        limit=context.refinement_limit,
      )
      while budget.available() {
        match binary_pi_scaled_bounds(self, operation, budget.precision()) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_inexact_target_rounding(
              bounds.0,
              bounds.1,
              context,
            )
            if unique {
              return Ok((result, flags))
            }
          }
          None => ()
        }
        budget = budget.next()
      }
      Err(
        binary_refinement_failure_for(operation.name() + "pi", context, budget),
      )
    }
  }
}

///|
pub fn Binary::try_sinpi_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  self.try_pi_scaled_ctx(BinaryTrigonometricOperation::Sin, context)
}

///|
pub fn Binary::sinpi_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_sinpi_ctx(context), context)
}

///|
pub fn Binary::sinpi(self : Binary) -> Binary {
  self.sinpi_ctx(binary_working_context(self.precision())).0
}

///|
pub fn Binary::try_cospi_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  self.try_pi_scaled_ctx(BinaryTrigonometricOperation::Cos, context)
}

///|
pub fn Binary::cospi_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_cospi_ctx(context), context)
}

///|
pub fn Binary::cospi(self : Binary) -> Binary {
  self.cospi_ctx(binary_working_context(self.precision())).0
}

///|
pub fn Binary::try_tanpi_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  self.try_pi_scaled_ctx(BinaryTrigonometricOperation::Tan, context)
}

///|
pub fn Binary::tanpi_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_tanpi_ctx(context), context)
}

///|
pub fn Binary::tanpi(self : Binary) -> Binary {
  self.tanpi_ctx(binary_working_context(self.precision())).0
}
