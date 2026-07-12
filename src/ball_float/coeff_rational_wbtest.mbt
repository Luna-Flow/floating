///|
fn coeff_for_test(value : BigInt) -> @bin_float.BinCoeff {
  guard value >= 0N else { abort("test coefficient must be non-negative") }
  @bin_float.BinCoeff::parse(value.to_string()).unwrap()
}

///|
fn signed_coeff_for_test(value : BigInt) -> SignedBinCoeff {
  signed_coeff_from_parts(
    value < 0N,
    coeff_for_test(if value < 0N { -value } else { value }),
  )
}

///|
fn coeff_bigint_for_test(value : @bin_float.BinCoeff) -> BigInt {
  BigInt::from_string(value.to_string())
}

///|
fn signed_coeff_bigint_for_test(value : SignedBinCoeff) -> BigInt {
  let magnitude = coeff_bigint_for_test(value.magnitude)
  if value.negative {
    -magnitude
  } else {
    magnitude
  }
}

///|
fn rat_for_test(numerator : BigInt, denominator : BigInt) -> CertifiedRat {
  guard denominator > 0N else { abort("test denominator must be positive") }
  certified_rat_coeff(
    signed_coeff_for_test(numerator),
    coeff_for_test(denominator),
  )
}

///|
fn rat_pair_for_test(value : CertifiedRat) -> (BigInt, BigInt) {
  (signed_coeff_bigint_for_test(value.num), coeff_bigint_for_test(value.den))
}

///|
test "coefficient rational normalization and arithmetic stay canonical" {
  let normalized = rat_pair_for_test(rat_for_test(-42N, 30N))
  assert_eq(normalized.0, -7N)
  assert_eq(normalized.1, 5N)
  let left = rat_for_test((1N << 127) + 17N, (1N << 89) + 3N)
  let right = rat_for_test(-((1N << 101) + 9N), (1N << 67) + 5N)
  let left_num = (1N << 127) + 17N
  let left_den = (1N << 89) + 3N
  let right_num = -((1N << 101) + 9N)
  let right_den = (1N << 67) + 5N
  let sum = rat_add(left, right)
  assert_eq(
    signed_coeff_bigint_for_test(sum.num) * left_den * right_den,
    (left_num * right_den + right_num * left_den) *
    coeff_bigint_for_test(sum.den),
  )
  let product = rat_mul(left, right)
  assert_eq(
    signed_coeff_bigint_for_test(product.num) * left_den * right_den,
    left_num * right_num * coeff_bigint_for_test(product.den),
  )
  let quotient = rat_div(left, right)
  assert_eq(
    signed_coeff_bigint_for_test(quotient.num) * left_den * right_num,
    left_num * right_den * coeff_bigint_for_test(quotient.den),
  )
}

///|
test "coefficient rational floor and ceil handle negative values" {
  for
    item in [
      (7N, 3N, 2N, 3N),
      (-7N, 3N, -3N, -2N),
      (6N, 3N, 2N, 2N),
      (-6N, 3N, -2N, -2N),
    ] {
    let (numerator, denominator, floor, ceil) = item
    let value = rat_for_test(numerator, denominator)
    assert_eq(signed_coeff_bigint_for_test(rat_floor(value)), floor)
    assert_eq(signed_coeff_bigint_for_test(rat_ceil(value)), ceil)
  }
}
