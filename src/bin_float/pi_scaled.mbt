///|
fn binary_scaled_integer_mod4(value : BinFloat, shift : Int) -> Int? {
  guard value.classify() == FpClass::Finite else { return None }
  guard value.exponent2() + shift >= 0 else { return None }
  let exponent = value.exponent2() + shift
  let magnitude_residue = if value.is_zero() || exponent >= 2 {
    0
  } else if exponent == 1 {
    if value.coefficient().test_bit(0) {
      2
    } else {
      0
    }
  } else {
    (if value.coefficient().test_bit(0) { 1 } else { 0 }) +
    (if value.coefficient().test_bit(1) { 2 } else { 0 })
  }
  Some(
    if value.is_negative() && magnitude_residue != 0 {
      4 - magnitude_residue
    } else {
      magnitude_residue
    },
  )
}

///|
fn binary_pi_scaled_exact(
  value : BinFloat,
  operation : BinaryTrigonometricOperation,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags)? {
  let integer = binary_scaled_integer_mod4(value, 0)
  let twice = binary_scaled_integer_mod4(value, 1)
  let four_times = binary_scaled_integer_mod4(value, 2)
  match (integer, twice) {
    (Some(n), _) => {
      let sine = if value.is_negative() {
        BinFloat::negative_zero(precision=context.precision)
      } else {
        BinFloat::zero(precision=context.precision)
      }
      let cosine = if n % 2 == 0 {
        BinFloat::one(precision=context.precision)
      } else {
        BinFloat::one(precision=context.precision).neg()
      }
      let result = match operation {
        BinaryTrigonometricOperation::Sin => sine
        BinaryTrigonometricOperation::Cos => cosine
        BinaryTrigonometricOperation::Tan => sine
      }
      Some((result, BinaryFlags::new()))
    }
    (_, Some(n)) if n % 2 != 0 => {
      let residue = n
      let sine = match residue {
        1 => BinFloat::one(precision=context.precision)
        3 => BinFloat::one(precision=context.precision).neg()
        _ => BinFloat::zero(precision=context.precision)
      }
      let cosine = BinFloat::zero(precision=context.precision)
      let result = match operation {
        BinaryTrigonometricOperation::Sin => sine
        BinaryTrigonometricOperation::Cos => cosine
        BinaryTrigonometricOperation::Tan =>
          BinFloat::inf(
            if sine.is_negative() {
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
                BinFloat::one(precision=context.precision)
              } else {
                BinFloat::one(precision=context.precision).neg()
              },
              BinaryFlags::new(),
            ),
          )
        _ => None
      }
  }
}

///|
fn binary_pi_periodic_remainder(value : BinFloat) -> BinFloat? {
  guard value.classify() == FpClass::Finite else { return None }
  if value.is_zero() {
    return Some(value)
  }
  if value.exponent2() >= 1 {
    return Some(
      if value.is_negative() {
        BinFloat::negative_zero(precision=value.precision())
      } else {
        BinFloat::zero(precision=value.precision())
      },
    )
  }
  let modulus_shift = 1 - value.exponent2()
  let magnitude = value.coefficient()
  let residue = if modulus_shift >= magnitude.bit_length() {
    magnitude
  } else {
    let quotient = magnitude.shift_right(modulus_shift)
    magnitude.sub_checked(quotient.shift_left(modulus_shift)).unwrap()
  }
  if residue.is_zero() {
    return Some(
      if value.is_negative() {
        BinFloat::negative_zero(precision=value.precision())
      } else {
        BinFloat::zero(precision=value.precision())
      },
    )
  }
  let reduced = BinFloat::make(
    residue,
    value.exponent2(),
    Int::max(1, residue.bit_length()),
  )
  Some(if value.is_negative() { reduced.neg() } else { reduced })
}

///|
fn binary_pi_scaled_quadrant_reduction(
  value : BinFloat,
  work_precision : Int,
) -> (BinFloat, Int)? {
  let threshold_precision = Int::max(4, value.precision())
  let quarter = BinFloat::make(BinCoeff::one(), -2, threshold_precision)
  let three_quarters = BinFloat::make(
    BinCoeff::from_uint64(3UL),
    -2,
    threshold_precision,
  )
  let five_quarters = BinFloat::make(
    BinCoeff::from_uint64(5UL),
    -2,
    threshold_precision,
  )
  let seven_quarters = BinFloat::make(
    BinCoeff::from_uint64(7UL),
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
    -4 => BinFloat::from_int(-2, precision=work_precision)
    -3 =>
      BinFloat::make(
        BinCoeff::from_uint64(3UL),
        -1,
        work_precision,
        negative=true,
      )
    -2 => BinFloat::from_int(-1, precision=work_precision)
    -1 => BinFloat::make(BinCoeff::one(), -1, work_precision, negative=true)
    0 => BinFloat::zero(precision=work_precision)
    1 => BinFloat::make(BinCoeff::one(), -1, work_precision)
    2 => BinFloat::one(precision=work_precision)
    3 => BinFloat::make(BinCoeff::from_uint64(3UL), -1, work_precision)
    _ => BinFloat::from_int(2, precision=work_precision)
  }
  let (residual, flags) = value.sub_ctx(
    half_integer,
    BinaryContext::unbounded(work_precision),
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
  value : BinFloat,
  operation : BinaryTrigonometricOperation,
  work_precision : Int,
) -> (BinFloat, BinFloat)? {
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
  let downward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = BinaryContext::unbounded(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let input_lower = residual.with_precision(
    work_precision,
    RoundingMode::TowardNegative,
  )
  let input_upper = residual.with_precision(
    work_precision,
    RoundingMode::TowardPositive,
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
fn BinFloat::try_pi_scaled_ctx(
  self : BinFloat,
  operation : BinaryTrigonometricOperation,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match self.class {
    FpClass::NaN =>
      Ok(
        (
          binary_quiet_nan(self, context.precision),
          if self.signaling_nan {
            binary_invalid_flags()
          } else {
            BinaryFlags::new()
          },
        ),
      )
    FpClass::Infinity =>
      Err(
        @def.ArithmeticError::domain_error(
          "pi-scaled trigonometric input is not finite",
        ),
      )
    FpClass::Finite => {
      match binary_pi_scaled_exact(self, operation, context) {
        Some(result) => return Ok(result)
        None => ()
      }
      let mut budget = CertifiedRefinementBudget::new(
        Int::max(context.precision + 96, self.precision() + 32),
      )
      while budget.available() {
        match binary_pi_scaled_bounds(self, operation, budget.precision()) {
          Some(bounds) => {
            let (result, unique, flags) = binary_certified_target_rounding(
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
pub fn BinFloat::try_sinpi_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  self.try_pi_scaled_ctx(BinaryTrigonometricOperation::Sin, context)
}

///|
pub fn BinFloat::sinpi_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.try_sinpi_ctx(context).unwrap()
}

///|
pub fn BinFloat::sinpi(self : BinFloat) -> BinFloat {
  self.sinpi_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
pub fn BinFloat::try_cospi_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  self.try_pi_scaled_ctx(BinaryTrigonometricOperation::Cos, context)
}

///|
pub fn BinFloat::cospi_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.try_cospi_ctx(context).unwrap()
}

///|
pub fn BinFloat::cospi(self : BinFloat) -> BinFloat {
  self.cospi_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
pub fn BinFloat::try_tanpi_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  self.try_pi_scaled_ctx(BinaryTrigonometricOperation::Tan, context)
}

///|
pub fn BinFloat::tanpi_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.try_tanpi_ctx(context).unwrap()
}

///|
pub fn BinFloat::tanpi(self : BinFloat) -> BinFloat {
  self.tanpi_ctx(BinaryContext::unbounded(self.precision())).0
}
