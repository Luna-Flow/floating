///|
// Public logical digit and shift/rotate context operations.

fn is_logical_operand(x : Decimal) -> Bool {
  guard x.class == FpClass::Finite && !x.negative && x.exponent10 == 0 else {
    return false
  }
  for limb_index in 0..<dec_coeff_unit_len(x.coefficient) {
    let mut limb = dec_coeff_limb_at(x.coefficient, limb_index)
    for _ in 0..<dec_coeff_dpun {
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
    Decimal::nan_raw(precision=finite_precision_for_default(ctx)),
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
                lhs.with_precision_raw(
                  finite_precision_for_default(ctx),
                  ctx.rounding,
                ),
                DecimalFlags::new(),
              )
            FpClass::Finite => {
              let precision = finite_precision_for_default(ctx)
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
fn Decimal::logical_and(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard is_logical_operand(self) && is_logical_operand(other) else {
    return logical_invalid_result(ctx)
  }
  let precision = finite_precision_for_default(ctx)
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
fn Decimal::logical_or(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard is_logical_operand(self) && is_logical_operand(other) else {
    return logical_invalid_result(ctx)
  }
  let precision = finite_precision_for_default(ctx)
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
fn Decimal::logical_xor(
  self : Decimal,
  other : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard is_logical_operand(self) && is_logical_operand(other) else {
    return logical_invalid_result(ctx)
  }
  let precision = finite_precision_for_default(ctx)
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
fn Decimal::logical_invert(
  self : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  guard is_logical_operand(self) else { return logical_invalid_result(ctx) }
  (
    finite_with_exponent_repr(
      false,
      logical_invert_digits_repr(self.coefficient, ctx),
      0,
      finite_precision_for_default(ctx),
    ),
    DecimalFlags::new(),
  )
}

///|
fn Decimal::shift_ctx(
  self : Decimal,
  count : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_shift_rotate(self, count, ctx, false)
}

///|
fn Decimal::rotate_ctx(
  self : Decimal,
  count : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  decimal_shift_rotate(self, count, ctx, true)
}
