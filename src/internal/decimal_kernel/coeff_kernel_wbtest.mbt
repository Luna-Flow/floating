///|
fn dec_coeff_test_dense_pattern(length : Int32, salt : Int32) -> DecCoeff {
  let limbs = Array::make(length, 0U)
  for index in 0..<length {
    let value = ((index + 1) * 104729 + salt * 13007) % (dec_coeff_base - 1) + 1
    limbs[index] = value.reinterpret_as_uint()
  }
  limbs[length - 1] = (dec_coeff_base - 1 - salt).reinterpret_as_uint()
  dec_coeff_from_unit_accumulator(limbs, limbs.length())
}

///|
fn reference_count_factor(base : Int32, n : BigInt) -> (BigInt, Int32) {
  let factor = BigInt::from_int(base)
  let mut value = n
  let mut count = 0
  while (value % factor).is_zero() {
    value = value / factor
    count += 1
  }
  (value, count)
}

///|
fn dec_coeff_test_division_algorithm(
  denominator : DecCoeff,
) -> DecCoeffDivAlgorithm {
  dec_coeff_division_algorithm(
    dec_coeff_shift_limbs(denominator, dec_coeff_unit_len(denominator)),
    denominator,
  )
}

///|
fn reference_gcd_bigint(a : BigInt, b : BigInt) -> BigInt {
  let mut x = abs_bigint(a)
  let mut y = abs_bigint(b)
  while !y.is_zero() {
    let remainder = x % y
    x = y
    y = remainder
  }
  if x.is_zero() {
    bigint_one()
  } else {
    x
  }
}

///|
test "decimal small coefficient helpers preserve direct representations" {
  assert_eq(dec_coeff_from_int(123).to_bigint(), 123N)
  assert_eq(dec_coeff_from_nonnegative_int(999999999).to_bigint(), 999999999N)
  assert_eq(dec_coeff_from_nonnegative_int(1000000000).to_bigint(), 1000000000N)
  assert_eq(
    dec_coeff_div_rem_by_unit_repr(dec_coeff_from_int(987654321), 97).0.to_bigint(),
    10182003N,
  )
  assert_eq(
    dec_coeff_div_rem_by_unit_repr(dec_coeff_from_int(987654321), 97).1,
    30,
  )
}

///|
test "decimal signed Int magnitude layout matches GDA from-int32 decomposition" {
  let min_int = -2147483647 - 1
  assert_eq(dec_coeff_from_int_magnitude(0).to_bigint(), 0N)
  assert_eq(dec_coeff_from_int_magnitude(999).to_bigint(), 999N)
  assert_eq(dec_coeff_from_int_magnitude(-1000).to_bigint(), 1000N)
  assert_eq(
    dec_coeff_from_int_magnitude(min_int).to_bigint(),
    abs_bigint(BigInt::from_int(min_int)),
  )
}

///|
test "decimal coefficient string lays out GDA units without BigInt" {
  let coeff = dec_coeff_from_bigint_repr(123456789012345678901N)
  assert_eq(coeff.to_string(), "123456789012345678901")
  assert_eq(dec_coeff_zero().to_string(), "0")
  assert_eq(dec_coeff_from_bigint_repr(1000001N).to_string(), "1000001")
}

///|
test "decimal coefficient unit subtraction handles borrow and zero exactly" {
  assert_eq(
    dec_coeff_magnitude_sub_unit(dec_coeff_from_bigint_repr(1000N), 1).to_bigint(),
    999N,
  )
  assert_eq(
    dec_coeff_magnitude_sub_unit(dec_coeff_from_bigint_repr(1N), 1).to_bigint(),
    0N,
  )
  assert_eq(
    dec_coeff_magnitude_sub_unit(dec_coeff_from_bigint_repr(5000N), 0).to_bigint(),
    5000N,
  )
}

///|
test "decimal signed coefficient step crosses zero in both directions" {
  let one = dec_coeff_from_bigint_repr(1N)
  let two = dec_coeff_from_bigint_repr(2N)
  let zero = dec_coeff_zero()
  let (neg_to_zero_sign, neg_to_zero_mag) = dec_coeff_signed_step_unit_repr(
    true, one, true,
  )
  assert_false(neg_to_zero_sign)
  assert_eq(neg_to_zero_mag.to_bigint(), 0N)
  let (pos_to_zero_sign, pos_to_zero_mag) = dec_coeff_signed_step_unit_repr(
    false, one, false,
  )
  assert_false(pos_to_zero_sign)
  assert_eq(pos_to_zero_mag.to_bigint(), 0N)
  let (zero_to_neg_sign, zero_to_neg_mag) = dec_coeff_signed_step_unit_repr(
    false, zero, false,
  )
  assert_true(zero_to_neg_sign)
  assert_eq(zero_to_neg_mag.to_bigint(), 1N)
  let (neg_to_less_neg_sign, neg_to_less_neg_mag) = dec_coeff_signed_step_unit_repr(
    true, two, true,
  )
  assert_true(neg_to_less_neg_sign)
  assert_eq(neg_to_less_neg_mag.to_bigint(), 1N)
}

///|
test "advanced decimal multiplication algorithms cross-check" {
  let modulus = pow10(520) - 159N
  let left_bigint = modulus - 123456789N
  let right_bigint = pow10(513) + 987654321N
  let left = dec_coeff_from_bigint_repr(left_bigint)
  let right = dec_coeff_from_bigint_repr(right_bigint)
  let expected = left_bigint * right_bigint
  for algorithm in [Schoolbook, Karatsuba, Toom3, Ntt] {
    assert_eq(
      dec_coeff_multiply_forced(algorithm, left, right).to_bigint(),
      expected,
    )
  }
  assert_eq(dec_coeff_square_repr(left).to_bigint(), left_bigint * left_bigint)
  assert_eq(dec_coeff_square_ntt(left).to_bigint(), left_bigint * left_bigint)
  let sparse_left = dec_coeff_from_bigint_repr(pow10(450) + 7N)
  let sparse_right = dec_coeff_from_bigint_repr(pow10(440) + 11N)
  assert_eq(
    dec_coeff_mul_sparse(sparse_left, sparse_right).to_bigint(),
    (pow10(450) + 7N) * (pow10(440) + 11N),
  )
  let block_left_bigint = pow10(1000) - 1N
  let block_right_bigint = pow10(2500) + pow10(1900) + 13N
  assert_eq(
    dec_coeff_multiply_forced(
      Unbalanced,
      dec_coeff_from_bigint_repr(block_left_bigint),
      dec_coeff_from_bigint_repr(block_right_bigint),
    ).to_bigint(),
    block_left_bigint * block_right_bigint,
  )
  let carry_short_bigint = pow10(9 * dec_coeff_karatsuba_threshold) - 1N
  let carry_long_bigint = pow10(9 * (dec_coeff_karatsuba_threshold * 4 + 3)) -
    1N
  let carry_short = dec_coeff_from_bigint_repr(carry_short_bigint)
  let carry_long = dec_coeff_from_bigint_repr(carry_long_bigint)
  let unbalanced_product = dec_coeff_multiply_forced(
    Unbalanced,
    carry_short,
    carry_long,
  )
  assert_eq(
    unbalanced_product.to_bigint(),
    carry_short_bigint * carry_long_bigint,
  )
  assert_eq(carry_short.to_bigint(), carry_short_bigint)
  assert_eq(carry_long.to_bigint(), carry_long_bigint)
}

///|
test "decimal NTT transform identity and CRT reconstruction" {
  let values = [0UL, 1UL, 9999UL, 42UL, 998UL, 17UL, 5UL, 3UL]
  let original = values.copy()
  dec_coeff_ntt_transform(
    values, false, dec_coeff_ntt_prime1, dec_coeff_ntt_root1,
  )
  dec_coeff_ntt_transform(
    values, true, dec_coeff_ntt_prime1, dec_coeff_ntt_root1,
  )
  for index in 0..<values.length() {
    assert_eq(values[index], original[index])
  }
  let product = dec_coeff_ntt_prime1 * dec_coeff_ntt_prime2
  for value in [0UL, 1UL, 99999999UL, product / 2UL, product - 1UL] {
    assert_eq(
      dec_coeff_ntt_crt(
        value % dec_coeff_ntt_prime1,
        value % dec_coeff_ntt_prime2,
      ),
      value,
    )
  }
  assert_true(dec_coeff_ntt_limits_fit(1 << 22, 1 << 22))
  assert_false(dec_coeff_ntt_limits_fit((1 << 22) + 1, (1 << 22) + 1))
  let coefficient = dec_coeff_from_bigint_repr(pow10(73) + 123456789N)
  assert_eq(
    dec_coeff_ntt_digit_len(coefficient),
    dec_coeff_ntt_digits(coefficient).length(),
  )
}

///|
test "advanced decimal division algorithms cross-check" {
  let numerator_bigint = pow10(620) - 123456789N
  let denominator_bigint = pow10(310) + 987654321N
  let numerator = dec_coeff_from_bigint_repr(numerator_bigint)
  let denominator = dec_coeff_from_bigint_repr(denominator_bigint)
  let expected_q = numerator_bigint / denominator_bigint
  let expected_r = numerator_bigint % denominator_bigint
  let (bz_q, bz_r) = dec_coeff_div_rem_burnikel_ziegler(numerator, denominator)
  assert_eq(bz_q.to_bigint(), expected_q)
  assert_eq(bz_r.to_bigint(), expected_r)
  let (newton_q, newton_r) = dec_coeff_div_rem_newton(numerator, denominator)
  assert_eq(newton_q.to_bigint(), expected_q)
  assert_eq(newton_r.to_bigint(), expected_r)
}

///|
test "decimal coefficient dispatch covers operand shapes and thresholds" {
  assert_true(
    dec_coeff_mul_algorithm(dec_coeff_from_int(3), dec_coeff_from_int(7)) ==
    Inline,
  )
  let balanced = dec_coeff_from_bigint_repr(pow10(360) - 1N)
  let expected_balanced = if dec_coeff_karatsuba_threshold <= 40 {
    Karatsuba
  } else {
    Schoolbook
  }
  assert_true(dec_coeff_mul_algorithm(balanced, balanced) == expected_balanced)
  let toom = dec_coeff_from_bigint_repr(pow10(1200) - 1N)
  let toom_algorithm = dec_coeff_mul_algorithm(toom, toom)
  let expected_toom = if dec_coeff_toom3_threshold <= 134 {
    Toom3
  } else {
    Karatsuba
  }
  assert_true(toom_algorithm == expected_toom)
  let ntt = dec_coeff_from_bigint_repr(pow10(5200) - 1N)
  let ntt_algorithm = dec_coeff_mul_algorithm(ntt, ntt)
  let expected_ntt = if dec_coeff_ntt_mul_threshold <= 578 {
    Ntt
  } else if dec_coeff_toom3_threshold <= 578 {
    Toom3
  } else if dec_coeff_karatsuba_threshold <= 578 {
    Karatsuba
  } else {
    Schoolbook
  }
  assert_true(ntt_algorithm == expected_ntt)
  let sparse = dec_coeff_from_bigint_repr(pow10(500) + 1N)
  assert_true(dec_coeff_mul_algorithm(sparse, sparse) == Sparse)
  assert_true(dec_coeff_maybe_sparse(sparse))
  assert_false(dec_coeff_maybe_sparse(balanced))
  let shorter_dense = dec_coeff_from_bigint_repr(pow10(500) - 1N)
  let unbalanced = dec_coeff_from_bigint_repr(pow10(5000) - 1N)
  assert_true(dec_coeff_mul_algorithm(shorter_dense, unbalanced) == Unbalanced)
  assert_true(
    dec_coeff_division_algorithm(dec_coeff_from_int(49), dec_coeff_from_int(7)) ==
    Word,
  )
  assert_true(
    dec_coeff_test_division_algorithm(dec_coeff_from_bigint_repr(pow10(9 * 48))) ==
    Knuth,
  )
  assert_true(
    dec_coeff_test_division_algorithm(
      dec_coeff_test_dense_pattern(dec_coeff_burnikel_ziegler_threshold - 1, 17),
    ) ==
    Knuth,
  )
  assert_true(
    dec_coeff_test_division_algorithm(
      dec_coeff_test_dense_pattern(dec_coeff_burnikel_ziegler_threshold, 19),
    ) ==
    BurnikelZiegler,
  )
  assert_true(
    dec_coeff_test_division_algorithm(
      dec_coeff_test_dense_pattern(dec_coeff_newton_threshold - 1, 23),
    ) ==
    BurnikelZiegler,
  )
  assert_true(
    dec_coeff_test_division_algorithm(
      dec_coeff_test_dense_pattern(dec_coeff_newton_threshold, 29),
    ) ==
    (if dec_coeff_newton_enabled { Newton } else { BurnikelZiegler }),
  )
  assert_true(
    dec_coeff_test_division_algorithm(
      dec_coeff_test_dense_pattern(
        dec_coeff_burnikel_ziegler_threshold_8k - 1,
        31,
      ),
    ) ==
    Knuth,
  )
  assert_true(
    dec_coeff_test_division_algorithm(
      dec_coeff_test_dense_pattern(dec_coeff_burnikel_ziegler_threshold_8k, 37),
    ) ==
    (if dec_coeff_newton_enabled &&
      dec_coeff_burnikel_ziegler_threshold_8k >= dec_coeff_newton_threshold {
      Newton
    } else {
      BurnikelZiegler
    }),
  )
  let threshold_denominator = dec_coeff_test_dense_pattern(
    dec_coeff_burnikel_ziegler_threshold, 41,
  )
  let same_length_numerator = dec_coeff_magnitude_add_unit(
    threshold_denominator, 1,
  )
  assert_eq(
    dec_coeff_unit_len(same_length_numerator),
    dec_coeff_unit_len(threshold_denominator),
  )
  assert_true(
    dec_coeff_division_algorithm(same_length_numerator, threshold_denominator) ==
    Knuth,
  )
  let (same_length_quotient, same_length_remainder) = dec_coeff_div_rem_repr(
    same_length_numerator, threshold_denominator,
  )
  assert_eq(same_length_quotient.to_bigint(), 1N)
  assert_eq(same_length_remainder.to_bigint(), 1N)
}

///|
test "decimal multiplication dispatch crosses every target threshold exactly" {
  for delta in [-1, 0, 1] {
    let length = dec_coeff_karatsuba_threshold + delta
    let lhs = dec_coeff_test_dense_pattern(length, 23)
    let rhs = dec_coeff_test_dense_pattern(length, 29)
    assert_true(
      dec_coeff_mul_algorithm(lhs, rhs) ==
      (if delta < 0 { Schoolbook } else { Karatsuba }),
    )
  }
  for delta in [-1, 0, 1] {
    let length = dec_coeff_toom3_threshold + delta
    let lhs = dec_coeff_test_dense_pattern(length, 31)
    let rhs = dec_coeff_test_dense_pattern(length, 37)
    assert_true(
      dec_coeff_mul_algorithm(lhs, rhs) ==
      (if delta < 0 { Karatsuba } else { Toom3 }),
    )
  }
  for delta in [-1, 0, 1] {
    let length = dec_coeff_ntt_mul_threshold + delta
    let lhs = dec_coeff_test_dense_pattern(length, 41)
    let rhs = dec_coeff_test_dense_pattern(length, 43)
    assert_true(
      dec_coeff_mul_algorithm(lhs, rhs) == (if delta < 0 { Toom3 } else { Ntt }),
    )
  }
  for delta in [-1, 0, 1] {
    let length = dec_coeff_karatsuba_square_threshold + delta
    let value = dec_coeff_test_dense_pattern(length, 47)
    assert_true(
      dec_coeff_square_algorithm(value) ==
      (if delta < 0 { Schoolbook } else { Karatsuba }),
    )
    assert_eq(
      dec_coeff_square_repr(value).to_bigint(),
      dec_coeff_multiply_forced(Schoolbook, value, value).to_bigint(),
    )
  }
}

///|
test "decimal square NTT profitability uses exact transform bands" {
  let capacity_4k = dec_coeff_test_dense_pattern(640, 53)
  assert_eq(dec_coeff_ntt_transform_length(capacity_4k, capacity_4k), 4096)
  assert_true(
    dec_coeff_ntt_square_profitable(capacity_4k) ==
    (640 >= dec_coeff_ntt_square_threshold),
  )
  for length in [1152, 1250, 1400] {
    let capacity_8k = dec_coeff_test_dense_pattern(length, 59)
    assert_eq(dec_coeff_ntt_transform_length(capacity_8k, capacity_8k), 8192)
    assert_true(
      dec_coeff_ntt_square_profitable(capacity_8k) ==
      (length >= dec_coeff_ntt_square_threshold_8k),
    )
  }
  let toom3_8k = dec_coeff_test_dense_pattern(1152, 61)
  assert_true(
    dec_coeff_ntt_square_toom3_profitable(toom3_8k) ==
    (1152 >= dec_coeff_ntt_square_toom3_threshold_8k),
  )
}

///|
test "decimal coefficient-native powers of ten match bigint powers" {
  assert_eq(dec_coeff_power10_repr(0).to_bigint(), pow10(0))
  assert_eq(dec_coeff_power10_repr(1).to_bigint(), pow10(1))
  assert_eq(dec_coeff_power10_repr(17).to_bigint(), pow10(17))
}

///|
test "decimal coefficient parity matches bigint parity" {
  let even = dec_coeff_from_bigint_repr(12345678901234567890N)
  let odd = dec_coeff_from_bigint_repr(12345678901234567891N)
  assert_false(dec_coeff_is_odd(even))
  assert_true(dec_coeff_is_odd(odd))
}

///|
test "decimal coefficient factor counting matches bigint factor counting" {
  let coeff = dec_coeff_from_bigint_repr(160000N)
  let (without_twos_repr, twos_repr) = dec_coeff_count_factor_unit_repr(
    coeff, 2,
  )
  let (without_twos_big, twos_big) = reference_count_factor(2, 160000N)
  assert_eq(without_twos_repr.to_bigint(), without_twos_big)
  assert_eq(twos_repr, twos_big)

  let (without_fives_repr, fives_repr) = dec_coeff_count_factor_unit_repr(
    without_twos_repr, 5,
  )
  let (without_fives_big, fives_big) = reference_count_factor(
    5, without_twos_big,
  )
  assert_eq(without_fives_repr.to_bigint(), without_fives_big)
  assert_eq(fives_repr, fives_big)
}

///|
test "power-of-ten modular scaling handles huge exponent gaps" {
  let residue = dec_coeff_shift_power10_mod_repr(
    dec_coeff_from_int(9),
    1_000_000_008,
    dec_coeff_from_int(469_135_780),
  )
  assert_eq(residue.to_bigint(), 188_902_320N)
}

///|
test "Knuth quotient clamp preserves the full normalized remainder" {
  let numerator = 81531386803002131355773364661909970000000000000000000000000000000000000000000000000000000000000000000N
  let denominator = 8153138680300213135577336466220607N
  let (quotient, remainder) = dec_coeff_div_rem_knuth_repr(
    dec_coeff_from_bigint_repr(numerator),
    dec_coeff_from_bigint_repr(denominator),
  )
  assert_eq(quotient.to_bigint(), numerator / denominator)
  assert_eq(remainder.to_bigint(), numerator % denominator)
  assert_eq(
    quotient.to_bigint() * denominator + remainder.to_bigint(),
    numerator,
  )
}

///|
test "decimal coefficient exact power-of-ten division uses unit shifts" {
  match
    exact_divide_by_power_of_ten_repr(dec_coeff_from_bigint_repr(12345000N), 3) {
    Some(value) => assert_eq(value.to_bigint(), 12345N)
    None => fail("expected exact division by 10^3")
  }
  match
    exact_divide_by_power_of_ten_repr(dec_coeff_from_bigint_repr(5000N), 2) {
    Some(value) => assert_eq(value.to_bigint(), 50N)
    None => fail("expected exact division by 10^2")
  }
  assert_true(
    exact_divide_by_power_of_ten_repr(dec_coeff_from_bigint_repr(12345N), 1)
    is None,
  )
}

///|
test "decimal decNumber-style unit add/sub matches carry and borrow cases" {
  let acc1 : Array[UInt32] = [0U, 0U, 0U, 0U]
  let lhs1 : Array[UInt32] = [
    (dec_coeff_base - 1).reinterpret_as_uint(),
    (dec_coeff_base - 1).reinterpret_as_uint(),
  ]
  let rhs1 : Array[UInt32] = [2U]
  let len1 = dec_coeff_unit_add_sub(lhs1, 2, rhs1, 1, 0, acc1, 1)
  assert_eq(len1, 3)
  assert_eq(acc1[0], 1)
  assert_eq(acc1[1], 0)
  assert_eq(acc1[2], 1)

  let acc2 : Array[UInt32] = [0U, 0U, 0U]
  let lhs2 : Array[UInt32] = [0U, 1U]
  let rhs2 : Array[UInt32] = [1U]
  let len2 = dec_coeff_unit_add_sub(lhs2, 2, rhs2, 1, 0, acc2, -1)
  assert_eq(len2, 2)
  assert_eq(acc2[0], (dec_coeff_base - 1).reinterpret_as_uint())
  assert_eq(acc2[1], 0)

  let acc3 : Array[UInt32] = [0U, 0U, 0U]
  let lhs3 : Array[UInt32] = [5U]
  let rhs3 : Array[UInt32] = [7U]
  let len3 = dec_coeff_unit_add_sub(lhs3, 1, rhs3, 1, 0, acc3, -1)
  assert_eq(len3, -1)
  assert_eq(acc3[0], 2)
}

///|
test "decimal signed coefficient add matches remainder identity arithmetic" {
  let lhs = dec_coeff_from_bigint_repr(1000000N)
  let rhs = dec_coeff_from_bigint_repr(999999N)
  let (positive, one) = dec_coeff_signed_add_repr(false, lhs, true, rhs)
  assert_false(positive)
  assert_eq(one.to_bigint(), 1N)

  let (negative, minus_one) = dec_coeff_signed_add_repr(true, lhs, false, rhs)
  assert_true(negative)
  assert_eq(minus_one.to_bigint(), 1N)

  let (carry_negative, carry) = dec_coeff_signed_add_repr(
    false,
    dec_coeff_from_bigint_repr(999999N),
    false,
    dec_coeff_from_bigint_repr(2N),
  )
  assert_false(carry_negative)
  assert_eq(carry.to_bigint(), 1000001N)

  let (zero_negative, zero) = dec_coeff_signed_add_repr(false, lhs, true, lhs)
  assert_false(zero_negative)
  assert_true(zero.is_zero())
}

///|
test "decimal signed coefficient compare proves power exponent bounds" {
  let huge = dec_coeff_from_bigint_repr(100000000000000000000N)
  assert_eq(dec_coeff_signed_compare_int_repr(false, huge, 999_999_999), 1)
  assert_eq(dec_coeff_signed_compare_int_repr(true, huge, -999_999_999), -1)
  assert_eq(
    dec_coeff_signed_compare_int_repr(
      false,
      dec_coeff_from_nonnegative_int(384),
      384,
    ),
    0,
  )
}

///|
test "decimal decNumber-style coefficient multiply matches long multiplication" {
  assert_eq(
    dec_coeff_multiply_repr(
      dec_coeff_from_bigint_repr(0N),
      dec_coeff_from_bigint_repr(12345N),
    ).to_bigint(),
    0N,
  )
  assert_eq(
    dec_coeff_multiply_repr(
      dec_coeff_from_bigint_repr(999N),
      dec_coeff_from_bigint_repr(999N),
    ).to_bigint(),
    998001N,
  )
  assert_eq(
    dec_coeff_multiply_repr(
      dec_coeff_from_bigint_repr(1234567890123N),
      dec_coeff_from_bigint_repr(987654321N),
    ).to_bigint(),
    1219326311247834171483N,
  )
}

///|
test "decimal decNumber-style coefficient divide returns quotient and residue" {
  let (q0, r0) = dec_coeff_div_rem_repr(
    dec_coeff_from_bigint_repr(0N),
    dec_coeff_from_bigint_repr(37N),
  )
  assert_eq(q0.to_bigint(), 0N)
  assert_eq(r0.to_bigint(), 0N)
  let (q1, r1) = dec_coeff_div_rem_repr(
    dec_coeff_from_bigint_repr(1000N),
    dec_coeff_from_bigint_repr(7N),
  )
  assert_eq(q1.to_bigint(), 142N)
  assert_eq(r1.to_bigint(), 6N)
  let (q2, r2) = dec_coeff_div_rem_repr(
    dec_coeff_from_bigint_repr(1219326311247834171483N),
    dec_coeff_from_bigint_repr(987654321N),
  )
  assert_eq(q2.to_bigint(), 1234567890123N)
  assert_eq(r2.to_bigint(), 0N)
  let (q3, r3) = dec_coeff_div_rem_repr(
    dec_coeff_from_bigint_repr(1234567890123456789012345N),
    dec_coeff_from_bigint_repr(999999937N),
  )
  assert_eq(q3.to_bigint(), 1234567967901238N)
  assert_eq(r3.to_bigint(), 766790339N)
}

///|
test "decimal remainder-only division matches BigInt" {
  let cases : Array[(BigInt, BigInt)] = [
    (12345N, 7N),
    (pow10(18) + 123456789N, pow10(9) + 7N),
    (pow10(36) - 1N, pow10(18) - 987654321N),
    (pow10(72) + 555555555555N, pow10(27) + 999999999N),
    (123N, 1000N),
    (1234567890123456789012345N, 999999937N),
  ]
  for pair in cases {
    let numerator_bigint = pair.0
    let denominator_bigint = pair.1
    let remainder = dec_coeff_mod_repr(
      dec_coeff_from_bigint_repr(numerator_bigint),
      dec_coeff_from_bigint_repr(denominator_bigint),
    )
    assert_eq(remainder.to_bigint(), numerator_bigint % denominator_bigint)
  }
}

///|
test "optimized decimal coefficient primitives match BigInt boundaries" {
  let boundaries : Array[BigInt] = [
    0N, 1N, 2N, 9N, 10N, 99N, 999N, 1000N, 1001N, 999999N, 1000000N, 1000001N, 999999999N,
    1000000000N, 1000000001N, 999999999999999999N, 1000000000000000000N, 1000000000000000001N,
    9999999999999999999999999999999999N, 10000000000000000000000000000000000N,
  ]
  for left_bigint in boundaries {
    let left = dec_coeff_from_bigint_repr(left_bigint)
    for right_bigint in boundaries {
      let right = dec_coeff_from_bigint_repr(right_bigint)
      let sum = dec_coeff_magnitude_add_repr(left, right)
      assert_eq(sum.to_bigint(), left_bigint + right_bigint)
      assert_eq(dec_coeff_unit_len(sum), dec_coeff_unit_len(sum))
      let product = dec_coeff_multiply_repr(left, right)
      assert_eq(product.to_bigint(), left_bigint * right_bigint)
      if left_bigint >= right_bigint {
        let difference = dec_coeff_magnitude_sub_repr(left, right)
        assert_eq(difference.to_bigint(), left_bigint - right_bigint)
        assert_eq(
          dec_coeff_unit_len(difference),
          dec_coeff_unit_len(difference),
        )
      }
      if !right_bigint.is_zero() {
        let (quotient, remainder) = dec_coeff_div_rem_repr(left, right)
        assert_eq(quotient.to_bigint(), left_bigint / right_bigint)
        assert_eq(remainder.to_bigint(), left_bigint % right_bigint)
      }
    }
  }
}

///|
test "optimized decimal coefficient primitives match deterministic BigInt matrix" {
  let modulus = pow10(120) - 159N
  let mut left_state = 123456789N
  let mut right_state = 987654321N
  for index in 1..<97 {
    let index_bigint = BigInt::from_int(index)
    left_state = (left_state * 1000003N + index_bigint * 97N + 17N) % modulus
    right_state = (right_state * 1000033N + index_bigint * 193N + 29N) % modulus
    let divisor_bigint = right_state + 1N
    let decimal_shift = index % 37
    let numerator_bigint = left_state * pow10(decimal_shift) + right_state
    let left = dec_coeff_from_bigint_repr(left_state)
    let right = dec_coeff_from_bigint_repr(right_state)
    let numerator = dec_coeff_from_bigint_repr(numerator_bigint)
    let divisor = dec_coeff_from_bigint_repr(divisor_bigint)
    assert_eq(
      dec_coeff_magnitude_add_repr(left, right).to_bigint(),
      left_state + right_state,
    )
    assert_eq(
      dec_coeff_multiply_repr(left, right).to_bigint(),
      left_state * right_state,
    )
    let (quotient, remainder) = dec_coeff_div_rem_repr(numerator, divisor)
    assert_eq(quotient.to_bigint(), numerator_bigint / divisor_bigint)
    assert_eq(remainder.to_bigint(), numerator_bigint % divisor_bigint)
    assert_true(dec_coeff_compare_repr(remainder, divisor) < 0)
  }
}

///|
test "optimized decimal coefficient single-unit division matches BigInt" {
  let numerator_bigint = pow10(180) - 123456789N
  let numerator = dec_coeff_from_bigint_repr(numerator_bigint)
  for divisor in [1, 2, 3, 5, 7, 10, 97, 499, 998, 999] {
    let divisor_bigint = BigInt::from_int(divisor)
    let (quotient, remainder) = dec_coeff_div_rem_repr(
      numerator,
      dec_coeff_from_int(divisor),
    )
    assert_eq(quotient.to_bigint(), numerator_bigint / divisor_bigint)
    assert_eq(remainder.to_bigint(), numerator_bigint % divisor_bigint)
  }
}

///|
test "optimized decimal coefficient quotient estimate matches constructed cases" {
  let denominators : Array[BigInt] = [
    1000N, 1001N, 1999N, 500999N, 999999N, 1000001N, 999999937N, 999999999N, 1000000000N,
    1000000001N, 999999999999999999N, 1000000000000000000N, 1000000000000000001N,
    100000000000000000000000000003N,
  ]
  let quotients : Array[BigInt] = [
    1N, 2N, 499N, 998N, 999N, 1000N, 1001N, 499999N, 999999N, 1000000N, 999999999999999999N,
  ]
  for denominator_bigint in denominators {
    let denominator = dec_coeff_from_bigint_repr(denominator_bigint)
    let remainders = [0N, 1N, denominator_bigint / 2N, denominator_bigint - 1N]
    for expected_quotient in quotients {
      for expected_remainder in remainders {
        let numerator_bigint = denominator_bigint * expected_quotient +
          expected_remainder
        let (quotient, remainder) = dec_coeff_div_rem_repr(
          dec_coeff_from_bigint_repr(numerator_bigint),
          denominator,
        )
        assert_eq(quotient.to_bigint(), expected_quotient)
        assert_eq(remainder.to_bigint(), expected_remainder)
      }
    }
  }
}

///|
test "Burnikel-Ziegler recursive block boundaries match exact quotients" {
  for length in [17, 31, 32, 33, 47, 48, 49, 63, 64, 65] {
    let denominator = dec_coeff_test_dense_pattern(length, 3)
    let expected_quotient = dec_coeff_test_dense_pattern(length + 7, 5)
    let expected_remainder = dec_coeff_slice(
      denominator,
      0,
      Int32::max(1, length / 2),
    )
    let numerator = dec_coeff_magnitude_add_repr(
      dec_coeff_multiply_repr(denominator, expected_quotient),
      expected_remainder,
    )
    let (quotient, remainder) = dec_coeff_div_rem_burnikel_ziegler(
      numerator, denominator,
    )
    assert_eq(quotient.to_bigint(), expected_quotient.to_bigint())
    assert_eq(remainder.to_bigint(), expected_remainder.to_bigint())
    assert_eq(
      quotient.to_bigint() * denominator.to_bigint() + remainder.to_bigint(),
      numerator.to_bigint(),
    )
    assert_true(remainder.to_bigint() < denominator.to_bigint())
  }
}

///|
test "Newton reciprocal division converges without fallback" {
  let denominator = dec_coeff_test_dense_pattern(64, 7)
  let expected_quotient = dec_coeff_test_dense_pattern(71, 11)
  let expected_remainder = dec_coeff_slice(denominator, 0, 29)
  let numerator = dec_coeff_magnitude_add_repr(
    dec_coeff_multiply_repr(denominator, expected_quotient),
    expected_remainder,
  )
  match dec_coeff_div_rem_newton_try(numerator, denominator) {
    Some((quotient, remainder)) => {
      assert_eq(quotient.to_bigint(), expected_quotient.to_bigint())
      assert_eq(remainder.to_bigint(), expected_remainder.to_bigint())
      assert_eq(
        quotient.to_bigint() * denominator.to_bigint() + remainder.to_bigint(),
        numerator.to_bigint(),
      )
      assert_true(remainder.to_bigint() < denominator.to_bigint())
    }
    None => fail("Newton reciprocal unexpectedly requested BZ fallback")
  }
}

///|
test "normalized Knuth division matches BigInt at limb boundaries" {
  let cases : Array[(BigInt, BigInt)] = [
    (pow10(18) + 123456789N, pow10(9) + 7N),
    (pow10(36) - 1N, pow10(18) - 987654321N),
    (pow10(72) + 555555555555N, pow10(27) + 999999999N),
  ]
  for pair in cases {
    let numerator_bigint = pair.0
    let denominator_bigint = pair.1
    let numerator = dec_coeff_from_bigint_repr(numerator_bigint)
    let denominator = dec_coeff_from_bigint_repr(denominator_bigint)
    let (quotient, remainder) = dec_coeff_div_rem_knuth_repr(
      numerator, denominator,
    )
    assert_eq(quotient.to_bigint(), numerator_bigint / denominator_bigint)
    assert_eq(remainder.to_bigint(), numerator_bigint % denominator_bigint)
    assert_eq(
      quotient.to_bigint() * denominator_bigint + remainder.to_bigint(),
      numerator_bigint,
    )
    assert_true(remainder.to_bigint() < denominator_bigint)
  }
}

///|
test "decimal coefficient exact powers stay native and honor precision caps" {
  let base = dec_coeff_from_bigint_repr(12345N)
  assert_eq(dec_coeff_exact_power_repr(base, 3).to_bigint(), 1881365963625N)
  match dec_coeff_exact_power_if_fits_repr(base, 3, 13) {
    Some(value) => assert_eq(value.to_bigint(), 1881365963625N)
    None => fail("expected coefficient-native exact power to fit")
  }
  assert_true(dec_coeff_exact_power_if_fits_repr(base, 3, 12) is None)
}

///|
test "decimal coefficient repr div-rem by power of ten matches bigint path" {
  let coeff = dec_coeff_from_bigint_repr(1234500N)
  let divisor = dec_coeff_power10_repr(3)
  let (quotient, remainder) = dec_coeff_div_rem_repr(coeff, divisor)
  assert_eq(quotient.to_bigint(), 1234N)
  assert_eq(remainder.to_bigint(), 500N)
}

///|
test "decimal coefficient gcd matches bigint gcd" {
  let lhs = dec_coeff_from_bigint_repr(98765432123456789N)
  let rhs = dec_coeff_from_bigint_repr(123456789N)
  assert_eq(
    dec_coeff_gcd_repr(lhs, rhs).to_bigint(),
    reference_gcd_bigint(98765432123456789N, 123456789N),
  )
  assert_eq(
    dec_coeff_gcd_repr(dec_coeff_zero(), rhs).to_bigint(),
    rhs.to_bigint(),
  )
  assert_eq(
    dec_coeff_gcd_repr(lhs, dec_coeff_zero()).to_bigint(),
    lhs.to_bigint(),
  )
  assert_eq(
    dec_coeff_gcd_repr(dec_coeff_zero(), dec_coeff_zero()).to_bigint(),
    0N,
  )
}

///|
test "decimal coefficient trailing-zero trim batches whole limbs" {
  let whole_limb_zeros = dec_coeff_from_bigint_repr(
    1_000_000_000_000_000_000_000N,
  )
  let (trimmed, exponent, dropped) = trim_trailing_decimal_zeros_repr(
    whole_limb_zeros, -7,
  )
  assert_eq(trimmed.to_bigint(), 1N)
  assert_eq(exponent, 14)
  assert_eq(dropped, 21)

  let partial_limb_zeros = dec_coeff_from_bigint_repr(123_450_000_000_000_000N)
  let (trimmed, exponent, dropped) = trim_trailing_decimal_zeros_repr(
    partial_limb_zeros, 3,
  )
  assert_eq(trimmed.to_bigint(), 12345N)
  assert_eq(exponent, 16)
  assert_eq(dropped, 13)
}

///|
// The NTT keeps five decimal digits per transform coefficient. A convolution
// coefficient is at most min(left_len, right_len) * (10^5 - 1)^2, below
// prime1 * prime2 = 753649251896000513 for every length the transform accepts
// (at most 2^22 coefficients on the shorter side:
// 2^22 * (10^5 - 1)^2 = 41942201143394304), so the reconstruction is exact.
// All-nines operands reach that maximum in every coefficient.
test "NTT product of all-nines operands equals the BigInt product" {
  assert_true(
    dec_coeff_ntt_limits_fit(1 << 22, (1 << 22) + 2) == false &&
    dec_coeff_ntt_limits_fit(1 << 22, 1 << 22),
  )
  for digits in [45, 4501, 45000] {
    let text = StringBuilder()
    for _ in 0..<digits {
      text.write_char('9')
    }
    let value = dec_coeff_from_decimal_digits_repr(text.to_string()).unwrap()
    let expected = value.to_bigint() * value.to_bigint()
    assert_true(
      dec_coeff_multiply_forced(Ntt, value, value).to_bigint() == expected,
    )
    assert_true(
      dec_coeff_multiply_forced(Ntt, value, dec_coeff_from_int(7)).to_bigint() ==
      value.to_bigint() * 7N,
    )
  }
}

///|
fn small_digits_reference(value : UInt64) -> Int32 {
  let mut digits = 1
  while digits < dec_coeff_word_powers10.length() &&
        value >= dec_coeff_word_powers10[digits] {
    digits += 1
  }
  digits
}

///|
test "word digit count matches the table scan at every power of ten boundary" {
  assert_eq(dec_coeff_small_digits(0UL), 1)
  assert_eq(dec_coeff_small_digits(0xFFFFFFFFFFFFFFFFUL), 20)
  for power in dec_coeff_word_powers10 {
    for delta in [-2L, -1L, 0L, 1L, 2L] {
      let value = (power.reinterpret_as_int64() + delta).reinterpret_as_uint64()
      if power > 2UL || delta >= 0L {
        assert_eq(dec_coeff_small_digits(value), small_digits_reference(value))
      }
    }
  }
  let mut state = 0x9E3779B97F4A7C15UL
  for _ in 0..<2000 {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let value = state >> (state % 64UL).to_int()
    assert_eq(dec_coeff_small_digits(value), small_digits_reference(value))
  }
}

///|
fn limbs_are_canonical(coeff : DecCoeff) -> Bool {
  match coeff {
    Small(value) => value < dec_coeff_small_limit
    Limbs(units, digits) => {
      let mut ok = units.length() >= 3 || units.length() >= 1
      for unit in units {
        if unit >= 1_000_000_000U {
          ok = false
        }
      }
      ok = ok && units[units.length() - 1] != 0U
      ok && digits == dec_coeff_get_digits(units, units.length())
    }
  }
}

///|
test "unit accumulator producers write limbs below the base" {
  let mut state = 0x5DEECE66DUL
  let next = fn() {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    state >> 11
  }
  let random_coeff = fn() {
    let digits = 1 + (next() % 80UL).to_int()
    let buf = StringBuilder()
    buf.write_string("\{1 + (next() % 9UL).to_int()}")
    for _ in 1..<digits {
      buf.write_string("\{(next() % 10UL).to_int()}")
    }
    dec_coeff_from_decimal_digits_repr(buf.to_string()).unwrap()
  }
  for _ in 0..<300 {
    let a = random_coeff()
    let b = random_coeff()
    let shift = (next() % 40UL).to_int()
    assert_true(limbs_are_canonical(a))
    assert_true(limbs_are_canonical(dec_coeff_multiply_repr(a, b)))
    assert_true(limbs_are_canonical(dec_coeff_magnitude_add_repr(a, b)))
    assert_true(limbs_are_canonical(dec_coeff_shift_power10_repr(a, shift)))
    let (quotient, remainder) = dec_coeff_div_rem_repr(a, b)
    assert_true(limbs_are_canonical(quotient))
    assert_true(limbs_are_canonical(remainder))
    assert_true(limbs_are_canonical(dec_coeff_power10_repr(shift)))
    assert_true(
      limbs_are_canonical(dec_coeff_multiply_by_unit_repr(a, 999_999_999)),
    )
  }
}
