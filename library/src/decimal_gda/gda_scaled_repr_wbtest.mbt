///|
test "scaled representation of a tiny value is zero without a power of ten" {
  // exponent -2_000_000: the divisor 10^1_999_990 would have two million digits
  let tiny = finite_with_exponent_repr(
    false,
    dec_coeff_from_int(123456789),
    -2_000_000,
    9,
  )
  let (negative, magnitude) = decimal_finite_to_scaled_repr(tiny, 10)
  assert_true(!negative && magnitude.is_zero())
  let (negative, magnitude) = decimal_finite_to_scaled_repr(
    { ..tiny, negative: true, },
    10,
  )
  assert_true(!negative && magnitude.is_zero())
  // both sides of the boundary: digits == -shift (quotient 0), digits < -shift,
  // and digits > -shift (quotient nonzero)
  let value = finite_with_exponent_repr(
    true,
    dec_coeff_from_int(987654321),
    -20,
    9,
  )
  for scale in [8, 11, 12, 13, 15, 19, 20, 25] {
    let (negative, magnitude) = decimal_finite_to_scaled_repr(value, scale)
    let shift = -20 + scale
    let expected = if shift >= 0 {
      dec_coeff_shift_power10_repr(value.coefficient, shift)
    } else {
      dec_coeff_div_rem_repr(value.coefficient, dec_coeff_power10_repr(-shift)).0
    }
    assert_eq(magnitude.to_string(), expected.to_string())
    assert_eq(negative, !expected.is_zero())
  }
}
