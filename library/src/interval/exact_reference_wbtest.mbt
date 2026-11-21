///|
/// The exact sum `a + b` of two finite values by integer arithmetic (aligned `BinCoeff` sums, no
/// rounding, no surrogate for a far addend) rounded once to `precision` bits in the direction
/// `mode` by `Binary::make`, the rounding of the binary layer (overflow and the grid below
/// the range floor included). The reference of the tests of the endpoint operations; it shares
/// with the code under test only `BinCoeff` arithmetic and `make`.
fn exact_sum_rounded(
  a : @binary.Binary,
  b : @binary.Binary,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> @binary.Binary {
  if a.is_zero() || b.is_zero() {
    let x = if a.is_zero() { b } else { a }
    return @binary.Binary::make(
      x.coefficient(),
      x.exponent2(),
      precision,
      negative=x.is_sign_minus(),
      mode~,
    )
  }
  let target = Int32::min(a.exponent2(), b.exponent2())
  let left = coeff_shift_left(a.coefficient(), a.exponent2() - target)
  let right = coeff_shift_left(b.coefficient(), b.exponent2() - target)
  let (coefficient, negative) = if a.is_sign_minus() == b.is_sign_minus() {
    (coeff_add(left, right), a.is_sign_minus())
  } else {
    let order = left.compare(right)
    if order == 0 {
      (@binary.BinCoeff::zero(), false)
    } else if order > 0 {
      (coeff_sub(left, right), a.is_sign_minus())
    } else {
      (coeff_sub(right, left), b.is_sign_minus())
    }
  }
  @binary.Binary::make(coefficient, target, precision, negative~, mode~)
}

///|
/// The exact product `a * b` of two finite values rounded once to `precision` bits in the
/// direction `mode` by `Binary::make` (the exponent sum saturates, so that an exponent beyond 32
/// bits keeps its direction).
fn exact_product_rounded(
  a : @binary.Binary,
  b : @binary.Binary,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> @binary.Binary {
  let exponent = a.exponent2().to_int64() + b.exponent2().to_int64()
  let exponent = if exponent > 2147483647L {
    2147483647
  } else if exponent < -2147483648L {
    -2147483648
  } else {
    exponent.to_int()
  }
  @binary.Binary::make(
    coeff_mul(a.coefficient(), b.coefficient()),
    exponent,
    precision,
    negative=a.is_sign_minus() != b.is_sign_minus(),
    mode~,
  )
}

///|
/// `a * b` of two finite values, exactly (`exact_value` with `exact_range`), for the tests whose
/// operands are far from the ends of the exponent range.
fn exact_mul_full(a : @binary.Binary, b : @binary.Binary) -> @binary.Binary {
  exact_value(
    coeff_mul(a.coefficient(), b.coefficient()),
    a.exponent2() + b.exponent2(),
    negative=a.is_sign_minus() != b.is_sign_minus(),
    exact_range=true,
  )
}
