///|
// oracle: A, B
// source: the literals 0 to 999999999999999999 round trip through to_bigint (A, with an identity part); the digit
//   count of each is compared with the kernel digits10 of the BigInt (B)
// shares: @internal.digits10, to_bigint
// primitives: @internal.digits10 (the boundary test of internal/helpers_wbtest.mbt: digits10 of 10^e is e + 1, 0 has 1 digit)
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
// oracle: A
// source: hand derivation: 999999999999999998 + 1 and +1 again, 10^18 minus 1; Small versus Limbs tag at the
//   18/19 digit boundary
// shares: nothing
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
// oracle: A, B
// source: the entries 9E17 and 1E17 are literals (A); each table entry is compared with pow10(shift), another
//   algorithm (BigInt power) of the kernel (B)
// shares: pow10 and BigInt::from_uint64
// primitives: pow10 (level A literals for 0, 1, 18 and 19 in internal/helpers_wbtest.mbt; the table spans 0 to 18)
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
