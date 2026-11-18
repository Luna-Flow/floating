///|
test "GDA coefficient stores one through eighteen digits inline" {
  for value in [0N, 1N, 9N, 10N, 999999999N, 1000000000N, 999999999999999999N] {
    let coefficient = dec_coeff_from_bigint_repr(value)
    assert_true(coefficient is DecCoeff::Small(_))
    assert_eq(coefficient.to_bigint(), value)
    assert_eq(coefficient.digits10(), digits10(value))
  }
  let boundary = dec_coeff_from_bigint_repr(1000000000000000000N)
  assert_true(boundary is DecCoeff::Limbs(_, _))
  assert_eq(boundary.to_bigint(), 1000000000000000000N)
}

///|
test "GDA coefficient scalar and limb paths remain canonical" {
  let left = dec_coeff_from_bigint_repr(999999999999999998N)
  let one = dec_coeff_from_int(1)
  let inline_sum = dec_coeff_magnitude_add_repr(left, one)
  assert_true(inline_sum is DecCoeff::Small(_))
  assert_eq(inline_sum.to_bigint(), 999999999999999999N)
  let limb_sum = dec_coeff_magnitude_add_repr(inline_sum, one)
  assert_true(limb_sum is DecCoeff::Limbs(_, _))
  assert_eq(limb_sum.to_bigint(), 1000000000000000000N)
  assert_eq(
    dec_coeff_magnitude_sub_repr(limb_sum, one).to_bigint(),
    999999999999999999N,
  )
}

///|
test "GDA coefficient power table is read only" {
  for shift in 0..<dec_coeff_small_powers10.length() {
    assert_eq(
      BigInt::from_uint64(dec_coeff_small_powers10[shift]),
      pow10(shift),
    )
  }
  let shifted = dec_coeff_shift_power10_repr(dec_coeff_from_int(9), 17)
  assert_eq(shifted.to_bigint(), 900000000000000000N)
  assert_eq(dec_coeff_small_powers10[17], 100000000000000000UL)
}
