///|
fn reference_round_positive_decimal_div_pow10(
  numerator : BigInt,
  shift : Int,
  negative : Bool,
  mode : DecimalRoundingMode,
) -> (BigInt, Bool) {
  guard numerator >= bigint_zero() else {
    abort("reference rounding expects a non-negative numerator")
  }
  guard shift >= 0 else {
    abort("reference rounding expects a non-negative shift")
  }
  if numerator.is_zero() || shift == 0 {
    return (numerator, false)
  }
  let digits = digits10(numerator)
  if shift < digits {
    let divisor = pow10(shift)
    let remainder = numerator % divisor
    return (
      round_positive_decimal_div(numerator, divisor, negative, mode),
      !remainder.is_zero(),
    )
  }
  let should_increment = match mode {
    Down => false
    Ceiling => !negative
    Floor => negative
    Up | ZeroFiveUp => true
    HalfEven | HalfDown =>
      shift == digits && numerator > pow10(digits - 1) * BigInt::from_int(5)
    HalfUp =>
      shift == digits && numerator >= pow10(digits - 1) * BigInt::from_int(5)
  }
  (if should_increment { bigint_one() } else { bigint_zero() }, true)
}

///|
fn reference_decimal_exact_int(rhs : Decimal) -> Int? {
  decimal_power_integer_count(rhs, 999_999_999)
}

///|
fn reference_remove_factor(base : Int, n : BigInt) -> BigInt {
  let factor = BigInt::from_int(base)
  let mut value = n
  while (value % factor).is_zero() {
    value = value / factor
  }
  value
}

///|
fn reference_count_factor(base : Int, n : BigInt) -> (BigInt, Int) {
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
fn reference_has_finite_decimal_expansion(
  numerator : BigInt,
  denominator : BigInt,
) -> Bool {
  let divisor = denominator / reference_gcd_bigint(numerator, denominator)
  let without_twos = reference_remove_factor(2, abs_bigint(divisor))
  let without_fives = reference_remove_factor(5, without_twos)
  without_fives == bigint_one()
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
  let acc1 = [0, 0, 0, 0]
  let lhs1 = [999, 999]
  let rhs1 = [2]
  let len1 = dec_coeff_unit_add_sub(lhs1, 2, rhs1, 1, 0, acc1, 1)
  assert_eq(len1, 3)
  assert_eq(acc1[0], 1)
  assert_eq(acc1[1], 0)
  assert_eq(acc1[2], 1)

  let acc2 = [0, 0, 0]
  let lhs2 = [0, 1]
  let rhs2 = [1]
  let len2 = dec_coeff_unit_add_sub(lhs2, 2, rhs2, 1, 0, acc2, -1)
  assert_eq(len2, 2)
  assert_eq(acc2[0], 999)
  assert_eq(acc2[1], 0)

  let acc3 = [0, 0, 0]
  let lhs3 = [5]
  let rhs3 = [7]
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
test "decimal exact aligned sum keeps GDA unit accumulator representation" {
  let carry_lhs = Decimal::from_string("999.999", precision=16).unwrap()
  let carry_rhs = Decimal::from_string("0.001", precision=16).unwrap()
  let (carry_negative, carry) = decimal_exact_aligned_sum_result(
    carry_lhs, carry_rhs, -3,
  )
  assert_false(carry_negative)
  assert_eq(carry.to_bigint(), 1000000N)

  let borrow_lhs = Decimal::from_string("1000", precision=16).unwrap()
  let borrow_rhs = Decimal::from_string("-0.001", precision=16).unwrap()
  let (borrow_negative, borrow) = decimal_exact_aligned_sum_result(
    borrow_lhs, borrow_rhs, -3,
  )
  assert_false(borrow_negative)
  assert_eq(borrow.to_bigint(), 999999N)

  let (reverse_negative, reverse) = decimal_exact_aligned_sum_result(
    borrow_rhs,
    Decimal::from_string("-1000", precision=16).unwrap(),
    -3,
  )
  assert_true(reverse_negative)
  assert_eq(reverse.to_bigint(), 1000001N)

  let huge_lhs = Decimal::from_string("10000E+1", precision=64).unwrap()
  let tiny_rhs = Decimal::from_string("10000E-50", precision=64).unwrap()
  let (huge_negative, huge) = decimal_exact_aligned_sum_result(
    huge_lhs, tiny_rhs, -50,
  )
  assert_false(huge_negative)
  assert_eq(huge.to_bigint(), pow10(55) + 10000N)
  assert_eq(huge.digits10(), 56)
}

///|
test "decimal plain add normalizes the GDA unit accumulator directly" {
  let sum = Decimal::from_string("999.999", precision=7)
    .unwrap()
    .add(Decimal::from_string("0.001", precision=7).unwrap())
  assert_eq(sum.coefficient.to_bigint(), 1N)
  assert_eq(sum.exponent10, 3)
  assert_false(sum.negative)

  let cancellation = Decimal::from_string("1.20", precision=7)
    .unwrap()
    .add(Decimal::from_string("-1.20", precision=7).unwrap())
  assert_true(cancellation.coefficient.is_zero())
  assert_false(cancellation.negative)
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
      assert_eq(sum.units.length(), dec_coeff_unit_len(sum))
      let product = dec_coeff_multiply_repr(left, right)
      assert_eq(product.to_bigint(), left_bigint * right_bigint)
      if left_bigint >= right_bigint {
        let difference = dec_coeff_magnitude_sub_repr(left, right)
        assert_eq(difference.to_bigint(), left_bigint - right_bigint)
        assert_eq(difference.units.length(), dec_coeff_unit_len(difference))
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
test "decimal coefficient repr rounded division is isomorphic to BigInt path" {
  let numerator = dec_coeff_from_bigint_repr(125N)
  let denominator = dec_coeff_from_bigint_repr(10N)
  assert_eq(
    round_positive_decimal_div_repr(
      numerator,
      denominator,
      false,
      DecimalRoundingMode::HalfEven,
    ).to_bigint(),
    round_positive_decimal_div(125N, 10N, false, DecimalRoundingMode::HalfEven),
  )
  assert_eq(
    round_positive_decimal_div_repr(
      numerator,
      denominator,
      false,
      DecimalRoundingMode::HalfUp,
    ).to_bigint(),
    round_positive_decimal_div(125N, 10N, false, DecimalRoundingMode::HalfUp),
  )
  assert_eq(
    round_positive_decimal_div_repr(
      dec_coeff_from_bigint_repr(123456789012345678901N),
      dec_coeff_from_bigint_repr(97N),
      true,
      DecimalRoundingMode::Floor,
    ).to_bigint(),
    round_positive_decimal_div(
      123456789012345678901N,
      97N,
      true,
      DecimalRoundingMode::Floor,
    ),
  )
}

///|
test "decimal plain division keeps GDA quotient units through normalization" {
  let exact = Decimal::from_int(1, precision=16).div(
    Decimal::from_int(8, precision=16),
  )
  assert_eq(exact.coefficient.to_bigint(), 125N)
  assert_eq(exact.exponent10, -3)
  assert_false(exact.negative)

  let rounded = Decimal::from_int(-2, precision=3).div(
    Decimal::from_int(3, precision=3),
  )
  assert_eq(rounded.coefficient.to_bigint(), 667N)
  assert_eq(rounded.exponent10, -3)
  assert_true(rounded.negative)
}

///|
test "decimal integer quotient stays in GDA unit accumulator representation" {
  let ten = Decimal::from_string("1E+1", precision=16).unwrap()
  let shifted = integer_quotient_by_power_of_ten_repr(
    Decimal::from_string("123E+2", precision=16).unwrap(),
    ten,
    false,
  ).unwrap()
  assert_eq(shifted.to_bigint(), 1230N)

  let truncated = integer_quotient_by_power_of_ten_repr(
    Decimal::from_int(125, precision=16),
    ten,
    false,
  ).unwrap()
  let even_tie = integer_quotient_by_power_of_ten_repr(
    Decimal::from_int(125, precision=16),
    ten,
    true,
  ).unwrap()
  let odd_tie = integer_quotient_by_power_of_ten_repr(
    Decimal::from_int(135, precision=16),
    ten,
    true,
  ).unwrap()
  assert_eq(truncated.to_bigint(), 12N)
  assert_eq(even_tie.to_bigint(), 12N)
  assert_eq(odd_tie.to_bigint(), 14N)
}

///|
test "decimal subset operand rounding stays coefficient-native" {
  let ctx = DecimalContext::new(
    precision=5,
    extended=false,
    decimal_rounding=DecimalRoundingMode::HalfEven,
  )
  let (exact, exact_flags) = round_operand_for_subset(
    Decimal::from_string("1234500", precision=16).unwrap(),
    ctx,
  )
  assert_eq(exact.coefficient.to_bigint(), 12345N)
  assert_eq(exact.exponent10, 2)
  assert_true(exact_flags.rounded)
  assert_false(exact_flags.inexact)

  let (inexact, inexact_flags) = round_operand_for_subset(
    Decimal::from_string("1234567", precision=16).unwrap(),
    ctx,
  )
  assert_eq(inexact.coefficient.to_bigint(), 12346N)
  assert_eq(inexact.exponent10, 2)
  assert_true(inexact_flags.rounded)
  assert_true(inexact_flags.inexact)
}

///|
test "decimal unary finalize and zero compare stay coefficient-native" {
  let ctx = DecimalContext::new(precision=3)
  let value = Decimal::from_string("1234", precision=16).unwrap()
  let (applied, flags) = value.apply_ctx(ctx)
  assert_eq(applied.coefficient.to_bigint(), 123N)
  assert_eq(applied.exponent10, 1)
  assert_true(flags.rounded)
  assert_true(flags.inexact)

  let zero = Decimal::negative_zero(precision=16)
  assert_eq(compare_finite(zero, Decimal::from_int(-1, precision=16)), 1)
  assert_eq(compare_finite(zero, Decimal::from_int(1, precision=16)), -1)
  assert_eq(compare_finite(zero, Decimal::zero(precision=16)), 0)
}

///|
test "decimal coefficient repr power-of-ten rounding matches BigInt path" {
  let (repr_half, repr_half_inexact) = round_positive_decimal_div_pow10_repr(
    dec_coeff_from_bigint_repr(12345N),
    2,
    false,
    DecimalRoundingMode::HalfEven,
  )
  let (big_half, big_half_inexact) = reference_round_positive_decimal_div_pow10(
    12345N,
    2,
    false,
    DecimalRoundingMode::HalfEven,
  )
  assert_eq(repr_half.to_bigint(), big_half)
  assert_eq(repr_half_inexact, big_half_inexact)

  let (repr_tiny, repr_tiny_inexact) = round_positive_decimal_div_pow10_repr(
    dec_coeff_from_bigint_repr(5N),
    1,
    false,
    DecimalRoundingMode::HalfUp,
  )
  let (big_tiny, big_tiny_inexact) = reference_round_positive_decimal_div_pow10(
    5N,
    1,
    false,
    DecimalRoundingMode::HalfUp,
  )
  assert_eq(repr_tiny.to_bigint(), big_tiny)
  assert_eq(repr_tiny_inexact, big_tiny_inexact)
}

///|
test "decimal coefficient-native precision helper matches bigint precision helper" {
  let coeff = dec_coeff_from_bigint_repr(1234500N)
  let exact_ctx = DecimalContext::new(precision=0)
  let fixed_ctx = DecimalContext::new(precision=9)
  assert_eq(
    finite_precision_for_coeff(coeff, exact_ctx),
    finite_precision_for(coeff.to_bigint(), exact_ctx),
  )
  assert_eq(
    finite_precision_for_coeff(coeff, fixed_ctx),
    finite_precision_for(coeff.to_bigint(), fixed_ctx),
  )
}

///|
test "decimal coefficient-native powers of ten match bigint powers" {
  assert_eq(dec_coeff_power10_repr(0).to_bigint(), pow10(0))
  assert_eq(dec_coeff_power10_repr(1).to_bigint(), pow10(1))
  assert_eq(dec_coeff_power10_repr(17).to_bigint(), pow10(17))
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
test "decimal exact integer power and reciprocal keep coefficient units" {
  let exact_ctx = DecimalContext::exact()
  let base = Decimal::from_int(40, precision=16)
  let (positive, positive_flags) = decimal_power_integer_exact_result(
    base, 3, exact_ctx,
  ).unwrap()
  assert_eq(positive.coefficient.to_bigint(), 64N)
  assert_eq(positive.exponent10, 3)
  assert_false(positive_flags.rounded)
  assert_false(positive_flags.inexact)

  let (reciprocal, reciprocal_flags) = exact_decimal_reciprocal(
    Decimal::from_int(40, precision=16),
    exact_ctx,
  ).unwrap()
  assert_eq(reciprocal.coefficient.to_bigint(), 25N)
  assert_eq(reciprocal.exponent10, -3)
  assert_false(reciprocal_flags.rounded)
  assert_false(reciprocal_flags.inexact)
}

///|
test "decimal exact square root uses GDA Newton unit operations" {
  let perfect = Decimal::from_string("15241578750190521", precision=32).unwrap()
  let exact = exact_finite_sqrt(perfect, 32).unwrap()
  assert_eq(exact.coefficient.to_bigint(), 123456789N)
  assert_eq(exact.exponent10, 0)

  let scaled = Decimal::from_string("1.4400", precision=16).unwrap()
  let scaled_exact = exact_finite_sqrt(scaled, 16).unwrap()
  assert_eq(scaled_exact.coefficient.to_bigint(), 120N)
  assert_eq(scaled_exact.exponent10, -2)

  assert_true(
    exact_finite_sqrt(Decimal::from_string("2", precision=16).unwrap(), 16)
    is None,
  )
}

///|
test "decimal exp range reduction keeps runtime coefficient units" {
  let value = Decimal::from_string("-1.25", precision=16).unwrap()
  let (negative, scaled) = decimal_finite_to_scaled_repr(value, 3)
  assert_true(negative)
  assert_eq(scaled.to_bigint(), 1250N)

  let ln10 = dec_coeff_from_bigint_repr(2303N)
  let exponent = decimal_floor_div_scaled_repr(negative, scaled, ln10)
  assert_eq(exponent, -1)
  let product = dec_coeff_multiply_repr(
    dec_coeff_from_nonnegative_int(abs_int(exponent)),
    ln10,
  )
  let (reduced_negative, reduced) = dec_coeff_signed_add_repr(
    negative,
    scaled,
    exponent >= 0,
    product,
  )
  assert_false(reduced_negative)
  assert_eq(reduced.to_bigint(), 1053N)
}

///|
test "decimal coefficient parity matches bigint parity" {
  let even = dec_coeff_from_bigint_repr(12345678901234567890N)
  let odd = dec_coeff_from_bigint_repr(12345678901234567891N)
  assert_false(dec_coeff_is_odd(even))
  assert_true(dec_coeff_is_odd(odd))
}

///|
test "decimal exact integer helpers match normalized finite values" {
  let integer = Decimal::from_string("1234500E-2", precision=16).unwrap()
  let negative = Decimal::from_string("-42.000", precision=16).unwrap()
  let fractional = Decimal::from_string("12.34", precision=16).unwrap()
  let huge = Decimal::from_string("1234567890123", precision=16).unwrap()

  match decimal_exact_integer_coeff(integer) {
    Some((negative, magnitude)) => {
      assert_false(negative)
      assert_eq(magnitude.to_bigint(), 12345N)
    }
    None => fail("expected exact positive integer coefficient")
  }
  match decimal_exact_integer_coeff(negative) {
    Some((negative, magnitude)) => {
      assert_true(negative)
      assert_eq(magnitude.to_bigint(), 42N)
    }
    None => fail("expected exact negative integer coefficient")
  }
  assert_true(decimal_exact_integer_coeff(fractional) is None)

  assert_true(reference_decimal_exact_int(integer) == Some(12345))
  assert_true(reference_decimal_exact_int(negative) == Some(-42))
  assert_true(reference_decimal_exact_int(fractional) is None)
  assert_true(reference_decimal_exact_int(huge) is None)

  assert_true(decimal_power_integer_count(integer, 20_000) == Some(12345))
  assert_true(decimal_power_integer_count(negative, 100) == Some(-42))
  assert_true(decimal_power_integer_count(huge, 999_999_999) is None)
}

///|
test "decimal integer parity helper rejects fractional values and tracks signless oddness" {
  let even = Decimal::from_string("-8.000", precision=16).unwrap()
  let odd = Decimal::from_string("-7", precision=16).unwrap()
  let zero = Decimal::from_string("0E-4", precision=16).unwrap()
  let fractional = Decimal::from_string("3.5", precision=16).unwrap()

  assert_true(decimal_power_integer_is_odd(even) == Some(false))
  assert_true(decimal_power_integer_is_odd(odd) == Some(true))
  assert_true(decimal_power_integer_is_odd(zero) == Some(false))
  assert_true(decimal_power_integer_is_odd(fractional) is None)
}

///|
test "scaleb count extracts exponent-zero integers from coeff repr" {
  let ctx = DecimalContext::new(
    precision=9,
    decimal_rounding=DecimalRoundingMode::HalfEven,
    e_min=-999,
    e_max=999,
  )
  let positive = Decimal::from_string("123", precision=16).unwrap()
  let negative = Decimal::from_string("-45", precision=16).unwrap()
  let negative_zero = Decimal::from_string("-0", precision=16).unwrap()
  let exact_nonzero_exponent = Decimal::from_string("12E-1", precision=16).unwrap()
  let huge = Decimal::from_string("1000000000000", precision=16).unwrap()

  assert_true(scaleb_count(positive, ctx) == Some(123))
  assert_true(scaleb_count(negative, ctx) == Some(-45))
  assert_true(scaleb_count(negative_zero, ctx) == Some(0))
  assert_true(scaleb_count(exact_nonzero_exponent, ctx) is None)
  assert_true(scaleb_count(huge, ctx) is None)
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
test "decimal coefficient finite-expansion predicate matches bigint predicate" {
  assert_eq(
    has_finite_decimal_expansion_repr(
      dec_coeff_from_bigint_repr(7N),
      dec_coeff_from_bigint_repr(40N),
    ),
    reference_has_finite_decimal_expansion(7N, 40N),
  )
  assert_eq(
    has_finite_decimal_expansion_repr(
      dec_coeff_from_bigint_repr(7N),
      dec_coeff_from_bigint_repr(21N),
    ),
    reference_has_finite_decimal_expansion(7N, 21N),
  )
}

///|
fn bigint_logical_binary_digits(
  lhs : BigInt,
  rhs : BigInt,
  precision : Int,
  op : (Bool, Bool) -> Bool,
) -> BigInt {
  let ten = BigInt::from_int(10)
  let mut lhs = lhs
  let mut rhs = rhs
  let mut place = bigint_one()
  let mut result = bigint_zero()
  for _ in 0..<precision {
    let lhs_digit = lhs % ten == bigint_one()
    let rhs_digit = rhs % ten == bigint_one()
    if op(lhs_digit, rhs_digit) {
      result = result + place
    }
    lhs = lhs / ten
    rhs = rhs / ten
    place = place * ten
  }
  result
}

///|
fn bigint_logical_invert_digits(value : BigInt, precision : Int) -> BigInt {
  let ten = BigInt::from_int(10)
  let mut value = value
  let mut place = bigint_one()
  let mut result = bigint_zero()
  for _ in 0..<precision {
    if value % ten != bigint_one() {
      result = result + place
    }
    value = value / ten
    place = place * ten
  }
  result
}

///|
fn bigint_shift_digits(
  coefficient : BigInt,
  count : Int,
  precision : Int,
) -> BigInt {
  if coefficient.is_zero() {
    return coefficient
  }
  if count == 0 {
    return coefficient
  }
  if count > 0 {
    coefficient * pow10(count) % pow10(precision)
  } else {
    coefficient / pow10(-count)
  }
}

///|
fn bigint_rotate_digits(
  coefficient : BigInt,
  count : Int,
  precision : Int,
) -> BigInt {
  if coefficient.is_zero() {
    return coefficient
  }
  let width = pow10(precision)
  let normalized = coefficient % width
  let mut shift = count % precision
  if shift < 0 {
    shift += precision
  }
  if shift == 0 {
    return normalized
  }
  let left = normalized * pow10(shift) % width
  let right = normalized / pow10(precision - shift)
  left + right
}

///|
fn assert_decimal_and_flags_eq(
  actual : (Decimal, DecimalFlags),
  expected : (Decimal, DecimalFlags),
) -> Unit raise {
  assert_eq(actual.0.compare_total(expected.0), 0)
  assert_eq(actual.1.inexact, expected.1.inexact)
  assert_eq(actual.1.rounded, expected.1.rounded)
  assert_eq(actual.1.invalid_operation, expected.1.invalid_operation)
  assert_eq(actual.1.division_by_zero, expected.1.division_by_zero)
  assert_eq(actual.1.overflow, expected.1.overflow)
  assert_eq(actual.1.underflow, expected.1.underflow)
  assert_eq(actual.1.subnormal, expected.1.subnormal)
  assert_eq(actual.1.clamped, expected.1.clamped)
  assert_eq(actual.1.conversion_syntax, expected.1.conversion_syntax)
  assert_eq(actual.1.division_impossible, expected.1.division_impossible)
  assert_eq(actual.1.division_undefined, expected.1.division_undefined)
  assert_eq(actual.1.invalid_context, expected.1.invalid_context)
}

///|
fn decimal_div_finite_by_small_int_work_bigint_expected(
  value : Decimal,
  divisor : Int,
  work_ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for(bigint_one(), work_ctx)
  let denominator = BigInt::from_int(divisor)
  let extra = precision + digits10(denominator) + 2
  let numerator = dec_coeff_shift_power10_repr(value.coefficient, extra).to_bigint()
  let exact = reference_has_finite_decimal_expansion(
    coeff_bigint(value.coefficient),
    denominator,
  )
  let q = round_positive_decimal_div(
    numerator,
    denominator,
    value.negative,
    work_ctx.decimal_rounding,
  )
  let (result, flags) = if exact {
    let exact_unrounded = normalize_decimal_parts_gda(
      value.negative,
      q,
      value.exponent10 - extra,
      digits10(q),
      work_ctx.decimal_rounding,
    )
    let exact_rounding = exact_result_rounding_flags(
      exact_unrounded,
      value.exponent10,
      work_ctx,
    )
    let rounded_value = normalize_decimal_parts_gda(
      value.negative,
      q,
      value.exponent10 - extra,
      precision,
      work_ctx.decimal_rounding,
    )
    if exact_rounding.rounded {
      let prefinal = if exact_unrounded.exponent10 < etiny(work_ctx) {
        exact_unrounded
      } else if !exact_rounding.inexact {
        expand_rounded_exact_cohort_toward_preferred_exponent(
          rounded_value,
          value.exponent10,
          work_ctx,
        )
      } else {
        expand_inexact_division_cohort(
          rounded_value,
          work_ctx,
          pad_precision=true,
        )
      }
      let (result, flags) = finalize_finite_ctx(
        prefinal, exact_rounding, work_ctx,
      )
      (result, with_underflow_for_inexact_subnormal(result, flags, work_ctx))
    } else {
      let exact_value = expand_exact_cohort_toward_preferred_exponent(
        rounded_value,
        value.exponent10,
        work_ctx,
      )
      let exact_value = if work_ctx.clamp {
        exact_value
      } else {
        expand_finite_cohort_toward_target_exponent(exact_value, 0, work_ctx)
      }
      finalize_finite_ctx(exact_value, DecimalFlags::new(), work_ctx)
    }
  } else {
    finalize_finite_ctx(
      normalize_decimal_parts_gda(
        value.negative,
        q,
        value.exponent10 - extra,
        precision,
        work_ctx.decimal_rounding,
      ),
      DecimalFlags::new(),
      work_ctx,
    )
  }
  if exact {
    (result, flags)
  } else {
    let result = expand_inexact_division_cohort(result, work_ctx)
    (
      result,
      with_underflow_for_inexact_subnormal(
        result,
        { ..flags, rounded: true, inexact: true },
        work_ctx,
      ),
    )
  }
}

///|
fn decimal_div_finite_work_bigint_expected(
  lhs : Decimal,
  rhs : Decimal,
  work_ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for(bigint_one(), work_ctx)
  let denominator = coeff_bigint(rhs.coefficient)
  let extra = precision + digits10(denominator) + 2
  let numerator = dec_coeff_shift_power10_repr(lhs.coefficient, extra).to_bigint()
  let exact = reference_has_finite_decimal_expansion(
    coeff_bigint(lhs.coefficient),
    denominator,
  )
  let q = round_positive_decimal_div(
    numerator,
    denominator,
    lhs.negative != rhs.negative,
    work_ctx.decimal_rounding,
  )
  let (value, round_flags) = if exact {
    let exact_unrounded = normalize_decimal_parts_gda(
      lhs.negative != rhs.negative,
      q,
      lhs.exponent10 - rhs.exponent10 - extra,
      digits10(q),
      work_ctx.decimal_rounding,
    )
    let exact_rounding = exact_result_rounding_flags(
      exact_unrounded,
      lhs.exponent10 - rhs.exponent10,
      work_ctx,
    )
    let rounded_value = normalize_decimal_parts_gda(
      lhs.negative != rhs.negative,
      q,
      lhs.exponent10 - rhs.exponent10 - extra,
      precision,
      work_ctx.decimal_rounding,
    )
    if exact_rounding.rounded {
      let prefinal = if exact_unrounded.exponent10 < etiny(work_ctx) {
        exact_unrounded
      } else if !exact_rounding.inexact {
        expand_rounded_exact_cohort_toward_preferred_exponent(
          rounded_value,
          lhs.exponent10 - rhs.exponent10,
          work_ctx,
        )
      } else {
        expand_inexact_division_cohort(
          rounded_value,
          work_ctx,
          pad_precision=true,
        )
      }
      let (value, flags) = finalize_finite_ctx(
        prefinal, exact_rounding, work_ctx,
      )
      (value, with_underflow_for_inexact_subnormal(value, flags, work_ctx))
    } else {
      let exact_value = expand_exact_cohort_toward_preferred_exponent(
        rounded_value,
        lhs.exponent10 - rhs.exponent10,
        work_ctx,
      )
      let exact_value = if work_ctx.clamp {
        exact_value
      } else {
        expand_finite_cohort_toward_target_exponent(exact_value, 0, work_ctx)
      }
      finalize_finite_ctx(exact_value, DecimalFlags::new(), work_ctx)
    }
  } else {
    finalize_finite_ctx(
      normalize_decimal_parts_gda(
        lhs.negative != rhs.negative,
        q,
        lhs.exponent10 - rhs.exponent10 - extra,
        precision,
        work_ctx.decimal_rounding,
      ),
      DecimalFlags::new(),
      work_ctx,
    )
  }
  if exact {
    (value, round_flags)
  } else {
    let value = expand_inexact_division_cohort(value, work_ctx)
    (
      value,
      with_underflow_for_inexact_subnormal(
        value,
        { ..round_flags, rounded: true, inexact: true },
        work_ctx,
      ),
    )
  }
}

///|
fn decimal_mul_finite_work_bigint_expected(
  lhs : Decimal,
  rhs : Decimal,
  work_ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  normalize_decimal_parts_math_ctx(
    lhs.negative != rhs.negative,
    lhs.coefficient.to_bigint() * rhs.coefficient.to_bigint(),
    lhs.exponent10 + rhs.exponent10,
    work_ctx,
  )
}

///|
fn finalize_scaleb_finite_ctx_bigint_expected(
  value : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(value.coefficient, ctx)
  if !value.coefficient.is_zero() && adjusted_exponent(value) > ctx.e_max {
    return (
      Decimal::inf(
        if value.negative {
          Sign::Negative
        } else {
          Sign::Positive
        },
        precision=value.precision_,
      ),
      { ..DecimalFlags::new(), overflow: true, rounded: true, inexact: true },
    )
  }
  let tiny = etiny(ctx)
  if value.exponent10 < tiny {
    let shift = tiny - value.exponent10
    let (magnitude_repr, inexact) = round_positive_decimal_div_pow10_repr(
      value.coefficient,
      shift,
      value.negative,
      ctx.decimal_rounding,
    )
    let mut flags = { ..DecimalFlags::new(), subnormal: true, rounded: true }
    if inexact {
      flags = { ..flags, inexact: true, underflow: true }
    }
    let magnitude = magnitude_repr.to_bigint()
    if magnitude_repr.is_zero() {
      return (
        finite_with_exponent(value.negative, magnitude, tiny, precision),
        { ..flags, clamped: true },
      )
    }
    if magnitude_repr.digits10() > precision {
      return finalize_scaleb_finite_ctx_bigint_expected(
        finite_with_exponent(value.negative, magnitude, tiny, precision),
        ctx,
      )
    }
    return (
      finite_with_exponent(value.negative, magnitude, tiny, precision),
      flags,
    )
  }
  finalize_finite_ctx(value, DecimalFlags::new(), ctx)
}

///|
fn scaleb_finite_result_ctx_bigint_expected(
  value : Decimal,
  count : Int,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let precision = finite_precision_for_coeff(value.coefficient, ctx)
  let target_exponent = BigInt::from_int(value.exponent10) +
    BigInt::from_int(count)
  if value.coefficient.is_zero() {
    return (
      finite_with_exponent(
        value.negative,
        bigint_zero(),
        target_exponent.to_int(),
        precision,
      ),
      DecimalFlags::new(),
    )
  }
  let adjusted = target_exponent +
    BigInt::from_int(value.coefficient.digits10() - 1)
  if adjusted > BigInt::from_int(ctx.e_max) {
    return (
      Decimal::inf(
        if value.negative {
          Sign::Negative
        } else {
          Sign::Positive
        },
        precision=value.precision_,
      ),
      { ..DecimalFlags::new(), overflow: true, rounded: true, inexact: true },
    )
  }
  let tiny = etiny(ctx)
  if target_exponent < BigInt::from_int(tiny) {
    let shift_big = BigInt::from_int(tiny) - target_exponent
    if shift_big > BigInt::from_int(value.coefficient.digits10() + 2) {
      let magnitude = huge_shift_rounded_unit(
        coeff_bigint(value.coefficient),
        value.negative,
        ctx.decimal_rounding,
      )
      let flags = {
        ..DecimalFlags::new(),
        rounded: true,
        inexact: !value.coefficient.is_zero(),
        underflow: !value.coefficient.is_zero(),
        subnormal: true,
        clamped: magnitude.is_zero(),
      }
      return (
        finite_with_exponent(value.negative, magnitude, tiny, precision),
        flags,
      )
    }
  }
  finalize_scaleb_finite_ctx_bigint_expected(
    finite_with_exponent(
      value.negative,
      value.coefficient.to_bigint(),
      target_exponent.to_int(),
      precision,
    ),
    ctx,
  )
}

///|
test "decimal logical coefficient helpers match bigint digit formulas" {
  let lhs = dec_coeff_from_bigint_repr(101011N)
  let rhs = dec_coeff_from_bigint_repr(110001N)
  let precision = 8
  assert_eq(
    logical_binary_digits_repr(lhs, rhs, precision, fn(a, b) { a && b }).to_bigint(),
    bigint_logical_binary_digits(101011N, 110001N, precision, fn(a, b) {
      a && b
    }),
  )
  assert_eq(
    logical_binary_digits_repr(lhs, rhs, precision, fn(a, b) { a || b }).to_bigint(),
    bigint_logical_binary_digits(101011N, 110001N, precision, fn(a, b) {
      a || b
    }),
  )
  assert_eq(
    logical_binary_digits_repr(lhs, rhs, precision, fn(a, b) { a != b }).to_bigint(),
    bigint_logical_binary_digits(101011N, 110001N, precision, fn(a, b) {
      a != b
    }),
  )
}

///|
test "decimal logical invert and digit motion helpers match bigint formulas" {
  let ctx = DecimalContext::new(precision=8)
  let coeff = dec_coeff_from_bigint_repr(101011N)
  assert_eq(
    logical_invert_digits_repr(coeff, ctx).to_bigint(),
    bigint_logical_invert_digits(101011N, 8),
  )
  assert_eq(
    coefficient_shift_digits_repr(coeff, 2, 8).to_bigint(),
    bigint_shift_digits(101011N, 2, 8),
  )
  assert_eq(
    coefficient_shift_digits_repr(coeff, -3, 8).to_bigint(),
    bigint_shift_digits(101011N, -3, 8),
  )
  assert_eq(
    coefficient_rotate_digits_repr(coeff, 2, 8).to_bigint(),
    bigint_rotate_digits(101011N, 2, 8),
  )
  assert_eq(
    coefficient_rotate_digits_repr(coeff, -3, 8).to_bigint(),
    bigint_rotate_digits(101011N, -3, 8),
  )
}

///|
test "decimal div_ctx repr pipeline matches bigint divide normalization" {
  let ctx = DecimalContext::new(
    precision=6,
    decimal_rounding=DecimalRoundingMode::HalfEven,
    e_min=-20,
    e_max=20,
    clamp=false,
  )
  let exact_lhs = Decimal::from_string("7.50", precision=8).unwrap()
  let exact_rhs = Decimal::from_string("16", precision=8).unwrap()
  let inexact_lhs = Decimal::from_string("22", precision=8).unwrap()
  let inexact_rhs = Decimal::from_string("7", precision=8).unwrap()
  assert_decimal_and_flags_eq(
    exact_lhs.div_ctx(exact_rhs, ctx),
    decimal_div_finite_work_bigint_expected(exact_lhs, exact_rhs, ctx),
  )
  assert_decimal_and_flags_eq(
    inexact_lhs.div_ctx(inexact_rhs, ctx),
    decimal_div_finite_work_bigint_expected(inexact_lhs, inexact_rhs, ctx),
  )
}

///|
test "decimal math small-int division repr pipeline matches bigint divide normalization" {
  let work_ctx = DecimalContext::new(
    precision=5,
    decimal_rounding=DecimalRoundingMode::HalfUp,
    e_min=-12,
    e_max=12,
    clamp=true,
  )
  let exact = Decimal::from_string("7.50", precision=8).unwrap()
  let inexact = Decimal::from_string("-2", precision=8).unwrap()
  assert_decimal_and_flags_eq(
    decimal_div_finite_by_small_int_work(exact, 8, work_ctx),
    decimal_div_finite_by_small_int_work_bigint_expected(exact, 8, work_ctx),
  )
  assert_decimal_and_flags_eq(
    decimal_div_finite_by_small_int_work(inexact, 3, work_ctx),
    decimal_div_finite_by_small_int_work_bigint_expected(inexact, 3, work_ctx),
  )
}

///|
test "decimal math finite division repr pipeline matches bigint divide normalization" {
  let work_ctx = DecimalContext::new(
    precision=5,
    decimal_rounding=DecimalRoundingMode::HalfEven,
    e_min=-15,
    e_max=15,
    clamp=false,
  )
  let exact_lhs = Decimal::from_string("7.50", precision=8).unwrap()
  let exact_rhs = Decimal::from_string("16", precision=8).unwrap()
  let inexact_lhs = Decimal::from_string("-22", precision=8).unwrap()
  let inexact_rhs = Decimal::from_string("7", precision=8).unwrap()
  assert_decimal_and_flags_eq(
    decimal_div_finite_work(exact_lhs, exact_rhs, work_ctx),
    decimal_div_finite_work_bigint_expected(exact_lhs, exact_rhs, work_ctx),
  )
  assert_decimal_and_flags_eq(
    decimal_div_finite_work(inexact_lhs, inexact_rhs, work_ctx),
    decimal_div_finite_work_bigint_expected(inexact_lhs, inexact_rhs, work_ctx),
  )
}

///|
test "decimal repr math normalization and multiplication match bigint path" {
  let work_ctx = DecimalContext::new(
    precision=6,
    decimal_rounding=DecimalRoundingMode::HalfEven,
    e_min=-20,
    e_max=20,
    clamp=false,
  )
  let value = Decimal::from_string("1234500E-3", precision=16).unwrap()
  assert_decimal_and_flags_eq(
    decimal_normalize_finite_work(value, work_ctx),
    normalize_decimal_parts_math_ctx(
      value.negative,
      coeff_bigint(value.coefficient),
      value.exponent10,
      work_ctx,
    ),
  )

  let lhs = Decimal::from_string("12.5", precision=8).unwrap()
  let rhs = Decimal::from_string("-0.08", precision=8).unwrap()
  assert_decimal_and_flags_eq(
    decimal_mul_finite_work(lhs, rhs, work_ctx),
    decimal_mul_finite_work_bigint_expected(lhs, rhs, work_ctx),
  )
  assert_decimal_and_flags_eq(
    lhs.mul_ctx(rhs, work_ctx),
    normalize_decimal_parts_ctx(
      lhs.negative != rhs.negative,
      lhs.coefficient.to_bigint() * rhs.coefficient.to_bigint(),
      lhs.exponent10 + rhs.exponent10,
      work_ctx,
    ),
  )
}

///|
test "decimal scaleb repr construction matches bigint path" {
  let ctx = DecimalContext::new(
    precision=4,
    decimal_rounding=DecimalRoundingMode::HalfUp,
    e_min=-6,
    e_max=6,
    clamp=true,
  )
  let regular = Decimal::from_string("12.34", precision=8).unwrap()
  let tiny = Decimal::from_string("12.34", precision=8).unwrap()
  assert_decimal_and_flags_eq(
    scaleb_finite_result_ctx(regular, -2, ctx),
    scaleb_finite_result_ctx_bigint_expected(regular, -2, ctx),
  )
  assert_decimal_and_flags_eq(
    scaleb_finite_result_ctx(tiny, -10, ctx),
    scaleb_finite_result_ctx_bigint_expected(tiny, -10, ctx),
  )
}

///|
test "decimal repr normalization matches bigint normalization on finite values" {
  let ctx = DecimalContext::new(
    precision=7,
    decimal_rounding=DecimalRoundingMode::HalfUp,
    e_min=-20,
    e_max=20,
    clamp=true,
  )
  let value = Decimal::from_string("1234500E-3", precision=16).unwrap()
  let expected = normalize_decimal_parts_ctx(
    value.negative,
    coeff_bigint(value.coefficient),
    value.exponent10,
    ctx,
  )
  let actual = normalize_decimal_parts_ctx_repr(
    value.negative,
    value.coefficient,
    value.exponent10,
    ctx,
  )
  assert_eq(actual.0.compare_total(expected.0), 0)
  assert_eq(actual.1.inexact, expected.1.inexact)
  assert_eq(actual.1.rounded, expected.1.rounded)
  assert_eq(actual.1.subnormal, expected.1.subnormal)
  assert_eq(actual.1.underflow, expected.1.underflow)
  assert_eq(actual.1.overflow, expected.1.overflow)
  assert_eq(actual.1.clamped, expected.1.clamped)
  assert_eq(actual.1.invalid_operation, expected.1.invalid_operation)
}

///|
test "decimal repr gda normalization matches bigint normalization" {
  let finite = Decimal::from_string("9999500E-4", precision=16).unwrap()
  let expected = normalize_decimal_parts_gda(
    finite.negative,
    coeff_bigint(finite.coefficient),
    finite.exponent10,
    5,
    DecimalRoundingMode::HalfEven,
  )
  let actual = normalize_decimal_parts_gda_repr(
    finite.negative,
    finite.coefficient,
    finite.exponent10,
    5,
    DecimalRoundingMode::HalfEven,
  )
  assert_eq(actual.compare_total(expected), 0)
}
