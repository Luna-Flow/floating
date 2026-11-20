// The fast coefficient paths (`binary_coeff_fast_mul`, `binary_coeff_fast_div`,
// `binary_coeff_fast_add`) add and subtract Int32 exponents of their operands.
// They cannot wrap: `binary_coeff_fast_operands_ok` admits only operands whose
// exponents satisfy |e| <= binary_fast_exponent_limit = 2^28, so a sum or a
// difference of two exponents is at most 2^29 in magnitude, and the division
// scale is at most precision + 2 + bits(divisor) <= 2^20 + 2 + 2^20, so
// `left.exponent2 - right.exponent2 - scale` stays within 2^29 + 2^21 < 2^31.
// Operands outside that window take the general path, which works in Int64.

///|
test "the fast path exponent window cannot wrap an Int32 (bound)" {
  let limit = binary_fast_exponent_limit.to_int64()
  let bits = binary_coeff_fast_bits_limit.to_int64()
  let max_sum = 2L * limit
  let max_scale = bits + 2L + bits
  assert_true(max_sum + max_scale < 2147483648L)
  assert_true(-max_sum - max_scale > -2147483649L)
}

///|
test "mul and div at the edge of the fast window and just outside it agree" {
  let limit = binary_fast_exponent_limit
  let ctx = BinaryContext::new(precision=53)
  for offset in [-1, 0, 1, 2] {
    let e = limit + offset
    let big = BinFloat::make(BinCoeff::one(), e, 53)
    let small = BinFloat::make(BinCoeff::one(), -e, 53)
    // 2^e * 2^e = 2^(2e), 2^e / 2^-e = 2^(2e), 2^-e * 2^-e = 2^(-2e)
    let square = big.mul_ctx(big, ctx).0
    assert_true(square.coefficient() == BinCoeff::one())
    assert_eq(square.exponent2(), 2 * e)
    let quotient = big.div_ctx(small, ctx).0
    assert_true(quotient.coefficient() == BinCoeff::one())
    assert_eq(quotient.exponent2(), 2 * e)
    let tiny = small.mul_ctx(small, ctx).0
    assert_true(tiny.coefficient() == BinCoeff::one())
    assert_eq(tiny.exponent2(), -2 * e)
    let inverse = small.div_ctx(big, ctx).0
    assert_true(inverse.coefficient() == BinCoeff::one())
    assert_eq(inverse.exponent2(), -2 * e)
  }
}
