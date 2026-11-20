///|
fn div_scaled_check(
  dividend_big : BigInt,
  scale : Int32,
  divisor_big : BigInt,
) -> Unit raise {
  let dividend = bin_coeff_test_from_bigint(dividend_big)
  let divisor = bin_coeff_test_from_bigint(divisor_big)
  let numerator_big = dividend_big << scale
  let limbs = bin_coeff_word_len(divisor)
  if bin_coeff_div_scaled_ok(dividend, scale, divisor) {
    let packed = bin_coeff_div_scaled_quotient(dividend, scale, divisor)
    // the general division of the shifted numerator is the reference
    let (reference_quotient, reference_remainder) = bin_coeff_short_div_rem(
      dividend.shift_left(scale),
      divisor,
    )
    let expected = reference_quotient
      .shift_left(1)
      .add(
        if reference_remainder.is_zero() {
          Coeff::zero()
        } else {
          Coeff::one()
        },
      )
    assert_true(packed == expected)
    // and BigInt
    let quotient_big = numerator_big / divisor_big
    let flag = if numerator_big % divisor_big != 0N { 1N } else { 0N }
    bin_coeff_test_assert_matches(packed, quotient_big * 2N + flag)
  } else {
    assert_true(
      limbs < 2 ||
      limbs >= bin_coeff_div_scaled_max_words ||
      numerator_big.bit_length() < divisor_big.bit_length(),
    )
  }
}

///|
test "scaled quotient equals the general division and BigInt" {
  let limb_counts = [
    2, 3, 4, 5, 6, 8, 9, 15, 16, 17, 31, 32, 33, 47, 64, 65, 95, 96, 97,
  ]
  for limbs in limb_counts {
    for variant in 0..<3 {
      let divisor_bits = limbs * 64 -
        (if variant == 0 { 0 } else { variant * 21 })
      for seed in 1..<40 {
        let divisor_big = bin_coeff_sqrt_test_value(
          divisor_bits,
          (seed + limbs * 100).to_uint64(),
        )
        // the divisor of a coefficient is odd
        let divisor_odd = divisor_big | 1N
        for
          dividend_bits in [
            divisor_bits,
            divisor_bits - 1,
            divisor_bits / 2 + 3,
            64,
            65,
            129,
          ] {
          if dividend_bits < 1 {
            continue
          }
          let dividend_big = bin_coeff_sqrt_test_value(
              dividend_bits,
              (seed * 7 + variant).to_uint64(),
            ) |
            1N
          for scale in [0, 1, 2, 63, 64, 65, 130, 131, 200 + seed] {
            div_scaled_check(dividend_big, scale, divisor_odd)
          }
        }
      }
    }
    // boundary values: all ones, powers of two plus one, equal operands
    let ones = (1N << (limbs * 64)) - 1N
    let power = (1N << (limbs * 64 - 1)) + 1N
    for dividend_big in [ones, power, ones - 2N, (1N << (limbs * 64 + 7)) - 1N] {
      for divisor_big in [ones, power, (1N << (limbs * 64 - 1)) + 3N] {
        for scale in [0, 1, 64, 129, 130] {
          div_scaled_check(dividend_big, scale, divisor_big)
        }
      }
    }
    // dividend = k * divisor + small, so that estimates equal the top digit
    let divisor_big = bin_coeff_sqrt_test_value(limbs * 64, 99UL) | 1N
    for
      multiplier in [
        1N,
        2N,
        0xffffffffffffffffN,
        (1N << 64) + 1N,
        (1N << 127) - 1N,
      ] {
      for offset in [-1N, 0N, 1N] {
        let dividend_big = multiplier * divisor_big + offset
        if dividend_big > 0N {
          for scale in [0, 5, 130] {
            div_scaled_check(dividend_big, scale, divisor_big)
          }
        }
      }
    }
  }
}
