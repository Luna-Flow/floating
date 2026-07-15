///|
// Public logical digit and shift/rotate context operations.

fn is_logical_operand(x : Decimal) -> Bool {
  guard x.class == FpClass::Finite && !x.negative && x.exponent10 == 0 else {
    return false
  }
  for limb_index in 0..<gda_coeff_unit_len(x.coefficient) {
    let mut limb = gda_coeff_limb_at(x.coefficient, limb_index)
    for _ in 0..<gda_coeff_dpun {
      let digit = limb % 10U
      if digit != 0U && digit != 1U {
        return false
      }
      limb /= 10U
    }
  }
  true
}

///|
fn logical_invalid_result(ctx : DecimalContext) -> (Decimal, DecimalFlags) {
  (
    Decimal::nan(precision=finite_precision_for(bigint_zero(), ctx)),
    invalid_flags(),
  )
}

///|
fn logical_coeff_digits_lsd(coeff : GdaCoeff, precision : Int) -> Array[Int] {
  let digits : Array[Int] = []
  for index in 0..<precision {
    let limb_index = index / gda_coeff_dpun
    let digit_index = index % gda_coeff_dpun
    let limb = if limb_index < gda_coeff_unit_len(coeff) {
      gda_coeff_limb_at(coeff, limb_index)
    } else {
      0U
    }
    digits.push(
      (limb / gda_coeff_powers[digit_index].reinterpret_as_uint() % 10U).reinterpret_as_int(),
    )
  }
  digits
}

///|
fn logical_coeff_from_digits_lsd(digits : Array[Int]) -> GdaCoeff {
  let limbs : Array[UInt] = []
  let mut index = 0
  while index < digits.length() {
    let end = Int::min(index + gda_coeff_dpun, digits.length())
    let mut limb = 0U
    let mut power = 1U
    for digit_index in index..<end {
      limb += digits[digit_index].reinterpret_as_uint() * power
      power *= 10U
    }
    limbs.push(limb)
    index = end
  }
  gda_coeff_from_unit_accumulator(limbs, limbs.length())
}

///|
// GDA logical operations are digit-wise over coefficient digits in base 10;
// this mirrors decNumber-style repeated coefficient digit extraction.
fn logical_binary_digits_repr(
  lhs : GdaCoeff,
  rhs : GdaCoeff,
  precision : Int,
  op : (Bool, Bool) -> Bool,
) -> GdaCoeff {
  let lhs_digits = logical_coeff_digits_lsd(lhs, precision)
  let rhs_digits = logical_coeff_digits_lsd(rhs, precision)
  let result_digits : Array[Int] = []
  for index in 0..<precision {
    let lhs_digit = lhs_digits[index] == 1
    let rhs_digit = rhs_digits[index] == 1
    let out_digit = op(lhs_digit, rhs_digit)
    result_digits.push(if out_digit { 1 } else { 0 })
  }
  logical_coeff_from_digits_lsd(result_digits)
}

///|
fn logical_invert_digits_repr(
  value : GdaCoeff,
  ctx : DecimalContext,
) -> GdaCoeff {
  let precision = finite_precision_for_coeff(value, ctx)
  let digits = logical_coeff_digits_lsd(value, precision)
  let result_digits : Array[Int] = []
  for index in 0..<precision {
    result_digits.push(if digits[index] == 1 { 0 } else { 1 })
  }
  logical_coeff_from_digits_lsd(result_digits)
}

///|
fn decimal_shift_count(rhs : Decimal, ctx : DecimalContext) -> Int? {
  guard rhs.class == FpClass::Finite && rhs.exponent10 == 0 else { return None }
  let limit = if ctx.precision != 0 { ctx.precision } else { 999_999_999 }
  match gda_coeff_to_bounded_int(rhs.coefficient, limit) {
    Some(value) =>
      Some(
        if rhs.negative && !rhs.coefficient.is_zero() {
          -value
        } else {
          value
        },
      )
    None => None
  }
}

///|
fn coefficient_shift_digits_repr(
  coefficient : GdaCoeff,
  count : Int,
  precision : Int,
) -> GdaCoeff {
  if coefficient.is_zero() {
    return coefficient
  }
  if count == 0 {
    return coefficient
  }
  let digits = logical_coeff_digits_lsd(coefficient, precision)
  let shifted : Array[Int] = []
  if count > 0 {
    for index in 0..<precision {
      shifted.push(if index >= count { digits[index - count] } else { 0 })
    }
  } else {
    let shift = -count
    for index in 0..<precision {
      shifted.push(
        if index + shift < precision {
          digits[index + shift]
        } else {
          0
        },
      )
    }
  }
  logical_coeff_from_digits_lsd(shifted)
}

///|
fn coefficient_rotate_digits_repr(
  coefficient : GdaCoeff,
  count : Int,
  precision : Int,
) -> GdaCoeff {
  if coefficient.is_zero() {
    return coefficient
  }
  let digits = logical_coeff_digits_lsd(coefficient, precision)
  let mut shift = count % precision
  if shift < 0 {
    shift += precision
  }
  if shift == 0 {
    return coefficient
  }
  let rotated : Array[Int] = []
  for index in 0..<precision {
    let source = (index - shift + precision) % precision
    rotated.push(digits[source])
  }
  logical_coeff_from_digits_lsd(rotated)
}

///|
fn decimal_shift_rotate(
  lhs : Decimal,
  rhs : Decimal,
  ctx : DecimalContext,
  rotate : Bool,
) -> (Decimal, DecimalFlags) {
  match quiet_nan_pair_for_next_toward(lhs, rhs, ctx) {
    Some(result) => result
    None =>
      match decimal_shift_count(rhs, ctx) {
        None => logical_invalid_result(ctx)
        Some(count) =>
          match lhs.class {
            FpClass::Infinity =>
              (
                lhs.with_precision(
                  finite_precision_for(bigint_zero(), ctx),
                  ctx.rounding,
                ),
                DecimalFlags::new(),
              )
            FpClass::Finite => {
              let precision = finite_precision_for(bigint_one(), ctx)
              let shifted = if rotate {
                coefficient_rotate_digits_repr(
                  lhs.coefficient,
                  count,
                  precision,
                )
              } else {
                coefficient_shift_digits_repr(lhs.coefficient, count, precision)
              }
              (
                finite_with_exponent_repr(
                  lhs.negative,
                  shifted,
                  lhs.exponent10,
                  precision,
                ),
                DecimalFlags::new(),
              )
            }
            FpClass::NaN => quiet_nan_operand(lhs, ctx)
          }
      }
  }
}

///|
pub fn Decimal::logical_and(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard is_logical_operand(self) && is_logical_operand(other) else {
    return logical_invalid_result(ctx)
  }
  let precision = finite_precision_for(bigint_zero(), ctx)
  (
    finite_with_exponent_repr(
      false,
      logical_binary_digits_repr(
        self.coefficient,
        other.coefficient,
        precision,
        fn(a, b) { a && b },
      ),
      0,
      precision,
    ),
    DecimalFlags::new(),
  )
}

///|
pub fn Decimal::logical_or(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard is_logical_operand(self) && is_logical_operand(other) else {
    return logical_invalid_result(ctx)
  }
  let precision = finite_precision_for(bigint_zero(), ctx)
  (
    finite_with_exponent_repr(
      false,
      logical_binary_digits_repr(
        self.coefficient,
        other.coefficient,
        precision,
        fn(a, b) { a || b },
      ),
      0,
      precision,
    ),
    DecimalFlags::new(),
  )
}

///|
pub fn Decimal::logical_xor(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard is_logical_operand(self) && is_logical_operand(other) else {
    return logical_invalid_result(ctx)
  }
  let precision = finite_precision_for(bigint_zero(), ctx)
  (
    finite_with_exponent_repr(
      false,
      logical_binary_digits_repr(
        self.coefficient,
        other.coefficient,
        precision,
        fn(a, b) { a != b },
      ),
      0,
      precision,
    ),
    DecimalFlags::new(),
  )
}

///|
pub fn Decimal::logical_invert(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard is_logical_operand(self) else { return logical_invalid_result(ctx) }
  (
    finite_with_exponent_repr(
      false,
      logical_invert_digits_repr(self.coefficient, ctx),
      0,
      finite_precision_for(bigint_zero(), ctx),
    ),
    DecimalFlags::new(),
  )
}

///|
pub fn Decimal::shift_ctx(
  self : Decimal,
  count : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_shift_rotate(self, count, ctx, false)
}

///|
pub fn Decimal::rotate_ctx(
  self : Decimal,
  count : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_shift_rotate(self, count, ctx, true)
}
