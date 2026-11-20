///|
// Public logical digit and shift/rotate context operations.

fn is_logical_operand(x : Decimal) -> Bool {
  guard x.class == FpClass::Finite && !x.negative && x.exponent10 == 0 else {
    return false
  }
  let mut digits = x.coefficient
  if digits.is_zero() {
    return true
  }
  while !digits.is_zero() {
    let (quotient, digit) = dec_coeff_div_rem_by_unit_repr(digits, 10)
    if digit != 0 && digit != 1 {
      return false
    }
    digits = quotient
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
fn logical_invert_digits_repr(
  value : DecCoeff,
  ctx : DecimalContext,
) -> DecCoeff {
  let precision = finite_precision_for_coeff(value, ctx)
  let digits = logical_coeff_digits_lsd(value, precision)
  let result_digits : Array[Int32] = []
  for index in 0..<precision {
    result_digits.push(if digits[index] == 1 { 0 } else { 1 })
  }
  logical_coeff_from_digits_lsd(result_digits)
}

///|
fn decimal_shift_count(rhs : Decimal, ctx : DecimalContext) -> Int32? {
  guard rhs.class == FpClass::Finite && rhs.exponent10 == 0 else { return None }
  let limit = if ctx.precision != 0 { ctx.precision } else { 999_999_999 }
  match dec_coeff_to_bounded_int(rhs.coefficient, limit) {
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
                lhs.with_precision_round(
                  finite_precision_for(bigint_zero(), ctx),
                  ctx.decimal_rounding,
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
pub fn Decimal::logical_and_ctx(
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
pub fn Decimal::logical_or_ctx(
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
pub fn Decimal::logical_xor_ctx(
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
pub fn Decimal::logical_invert_ctx(
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
