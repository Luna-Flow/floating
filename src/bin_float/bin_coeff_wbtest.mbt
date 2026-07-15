///|
fn bin_coeff_test_from_bigint(value : BigInt) -> BinCoeff {
  BinCoeff::parse(value.to_string()).unwrap()
}

///|
fn bin_coeff_test_assert_matches(
  value : BinCoeff,
  expected : BigInt,
) -> Unit raise {
  assert_eq(value.to_string(), expected.to_string())
}

///|
fn bin_coeff_test_bigint_gcd(left : BigInt, right : BigInt) -> BigInt {
  let mut left = left
  let mut right = right
  while !right.is_zero() {
    let remainder = left % right
    left = right
    right = remainder
  }
  left
}

///|
test "BinCoeff canonical boundaries and serialization" {
  let sources = [
    "0", "1", "4294967295", "4294967296", "18446744073709551615", "18446744073709551616",
    "340282366920938463463374607431768211455", "340282366920938463463374607431768211456",
    "1461501637330902918203684832716283019655932542975",
  ]
  for source in sources {
    let value = BinCoeff::parse(source).unwrap()
    assert_eq(value.to_string(), source)
    assert_eq(BinCoeff::from_bytes_be(value.to_bytes_be()), value)
  }
  assert_eq(BinCoeff::from_bytes_be(b"").to_string(), "0")
  assert_eq(BinCoeff::zero().to_bytes_be(), b"\x00")
}

///|
test "BinCoeff exhaustive small arithmetic" {
  for left in 0..<96 {
    for right in 0..<96 {
      let left_coeff = BinCoeff::from_uint64(left.to_uint64())
      let right_coeff = BinCoeff::from_uint64(right.to_uint64())
      let left_big = BigInt::from_int(left)
      let right_big = BigInt::from_int(right)
      bin_coeff_test_assert_matches(
        left_coeff + right_coeff,
        left_big + right_big,
      )
      bin_coeff_test_assert_matches(
        left_coeff * right_coeff,
        left_big * right_big,
      )
      bin_coeff_test_assert_matches(
        left_coeff.bit_and(right_coeff),
        left_big & right_big,
      )
      bin_coeff_test_assert_matches(
        left_coeff.bit_or(right_coeff),
        left_big | right_big,
      )
      bin_coeff_test_assert_matches(
        left_coeff.bit_xor(right_coeff),
        left_big ^ right_big,
      )
      if left >= right {
        bin_coeff_test_assert_matches(
          left_coeff.sub_checked(right_coeff).unwrap(),
          left_big - right_big,
        )
      } else {
        assert_true(left_coeff.sub_checked(right_coeff) is Err(_))
      }
      if right != 0 {
        let (quotient, remainder) = left_coeff
          .div_rem_checked(right_coeff)
          .unwrap()
        bin_coeff_test_assert_matches(quotient, left_big / right_big)
        bin_coeff_test_assert_matches(remainder, left_big % right_big)
      }
    }
  }
}

///|
test "BinCoeff large arithmetic differential" {
  let values = [
    (1N << 31) - 1N,
    1N << 32,
    (1N << 63) + 17N,
    (1N << 64) - 1N,
    (1N << 64) + 1N,
    (1N << 96) + (1N << 47) + 3N,
    (1N << 127) - 1N,
    (1N << 128) + 1N,
    (1N << 159) + (1N << 93) + 0xffffN,
    (1N << 257) + (1N << 129) + 37N,
    (1N << 521) - 1N,
  ]
  for left_big in values {
    for right_big in values {
      let left = bin_coeff_test_from_bigint(left_big)
      let right = bin_coeff_test_from_bigint(right_big)
      bin_coeff_test_assert_matches(left.add(right), left_big + right_big)
      bin_coeff_test_assert_matches(left.mul(right), left_big * right_big)
      bin_coeff_test_assert_matches(left.bit_and(right), left_big & right_big)
      bin_coeff_test_assert_matches(left.bit_or(right), left_big | right_big)
      bin_coeff_test_assert_matches(left.bit_xor(right), left_big ^ right_big)
      if left_big >= right_big {
        bin_coeff_test_assert_matches(
          left.sub_checked(right).unwrap(),
          left_big - right_big,
        )
      }
      let (quotient, remainder) = left.div_rem_checked(right).unwrap()
      bin_coeff_test_assert_matches(quotient, left_big / right_big)
      bin_coeff_test_assert_matches(remainder, left_big % right_big)
      bin_coeff_test_assert_matches(
        quotient.mul(right).add(remainder),
        left_big,
      )
    }
  }
}

///|
test "BinCoeff shifts bits gcd powers and radices" {
  let source_big = (1N << 257) + (1N << 128) + (1N << 63) + 1N
  let source = bin_coeff_test_from_bigint(source_big)
  for shift in [0, 1, 31, 32, 33, 63, 64, 65, 127, 128, 129, 511] {
    bin_coeff_test_assert_matches(source << shift, source_big << shift)
    bin_coeff_test_assert_matches(source >> shift, source_big >> shift)
  }
  assert_eq(source.bit_length(), source_big.bit_length())
  for bit in [0, 1, 31, 32, 63, 64, 127, 128, 129, 257, 258] {
    assert_eq(source.test_bit(bit), ((source_big >> bit) & 1N) == 1N)
  }
  let trailing = source << 93
  assert_eq(trailing.ctz(), 93)
  let other_big = (1N << 193) - 1N
  let other = bin_coeff_test_from_bigint(other_big)
  bin_coeff_test_assert_matches(
    source.gcd(other),
    bin_coeff_test_bigint_gcd(source_big, other_big),
  )
  bin_coeff_test_assert_matches(
    BinCoeff::from_uint64(37UL).pow_nat(19U),
    BigInt::from_int(37).pow(BigInt::from_int(19)),
  )
  for radix in [2, 3, 8, 10, 16, 31, 36] {
    let text = source.to_string(radix~)
    assert_eq(BinCoeff::parse(text, radix~).unwrap(), source)
  }
}

///|
test "BinCoeff inline binary gcd boundaries" {
  let values = [
    0N,
    1N,
    2N,
    (1N << 32) - 1N,
    1N << 64,
    (1N << 96) + (1N << 32),
    (1N << 127) - 1N,
    (1N << 128) - 1N,
  ]
  for left_big in values {
    for right_big in values {
      let left = bin_coeff_test_from_bigint(left_big)
      let right = bin_coeff_test_from_bigint(right_big)
      bin_coeff_test_assert_matches(
        left.gcd(right),
        bin_coeff_test_bigint_gcd(left_big, right_big),
      )
    }
  }
}

///|
test "BinCoeff divide-and-conquer radix conversion" {
  let decimal_builder = StringBuilder::new()
  decimal_builder.write_char('9')
  for index in 1..<2200 {
    decimal_builder.write_char(
      Int::unsafe_to_char('0'.to_int() + (index * 7 + 3) % 10),
    )
  }
  let decimal = decimal_builder.to_string()
  let decimal_value = BinCoeff::parse(decimal).unwrap()
  assert_eq(decimal_value.to_string(), decimal)
  let ternary_builder = StringBuilder::new()
  ternary_builder.write_char('2')
  for index in 1..<6000 {
    ternary_builder.write_char(
      Int::unsafe_to_char('0'.to_int() + (index * 5 + 1) % 3),
    )
  }
  let ternary = ternary_builder.to_string()
  let ternary_value = BinCoeff::parse(ternary, radix=3).unwrap()
  assert_eq(ternary_value.to_string(radix=3), ternary)
}

///|
test "BinCoeff checked failures" {
  assert_true(BinCoeff::one().sub_checked(BinCoeff::from_uint64(2UL)) is Err(_))
  assert_true(BinCoeff::one().div_rem_checked(BinCoeff::zero()) is Err(_))
  assert_true(BinCoeff::parse("") is Err(_))
  assert_true(BinCoeff::parse("-1") is Err(_))
  assert_true(BinCoeff::parse("2", radix=2) is Err(_))
  assert_true(BinCoeff::parse("0", radix=1) is Err(_))
}

///|
fn bin_coeff_test_limb_pattern(limbs : Int, phase : Int) -> BigInt {
  let bits = limbs * 32
  let mut value = 1N << (bits - 1)
  let mut index = phase % 17
  while index < bits - 1 {
    value = value | (1N << index)
    index += 17 + phase % 5
  }
  value | 1N
}

///|
test "BinCoeff multiplication algorithm thresholds" {
  for
    limbs in [
      3, 4, 5, 6, 7, 8, 9, 29, 30, 31, 32, 33, 34, 94, 95, 96, 97, 98, 511, 767,
      768, 769,
    ] {
    let left_big = bin_coeff_test_limb_pattern(limbs, 3)
    let right_big = bin_coeff_test_limb_pattern(limbs - 1, 7)
    let left = bin_coeff_test_from_bigint(left_big)
    let right = bin_coeff_test_from_bigint(right_big)
    bin_coeff_test_assert_matches(left.mul(right), left_big * right_big)
    bin_coeff_test_assert_matches(left.square(), left_big * left_big)
  }
  let short_big = bin_coeff_test_limb_pattern(32, 2)
  let long_big = bin_coeff_test_limb_pattern(97, 11)
  let short = bin_coeff_test_from_bigint(short_big)
  let long = bin_coeff_test_from_bigint(long_big)
  bin_coeff_test_assert_matches(short.mul(long), short_big * long_big)
}

///|
test "BinCoeff inline Comba multiplication boundaries" {
  let values = [
    (1N << 63) - 1N,
    1N << 63,
    (1N << 64) - 1N,
    1N << 64,
    (1N << 64) + 1N,
    (1N << 95) + (1N << 31) + 1N,
    (1N << 127) - 1N,
    1N << 127,
    (1N << 128) - 1N,
  ]
  for left_big in values {
    for right_big in values {
      let left = bin_coeff_test_from_bigint(left_big)
      let right = bin_coeff_test_from_bigint(right_big)
      bin_coeff_test_assert_matches(left.mul(right), left_big * right_big)
      if left_big == right_big {
        bin_coeff_test_assert_matches(left.square(), left_big * left_big)
      }
    }
  }
}

///|
test "BinCoeff division algorithm thresholds" {
  for divisor_limbs in [46, 47, 48, 49, 50] {
    let denominator_big = bin_coeff_test_limb_pattern(divisor_limbs, 9)
    let numerator_big = bin_coeff_test_limb_pattern(divisor_limbs * 3 + 5, 4)
    let denominator = bin_coeff_test_from_bigint(denominator_big)
    let numerator = bin_coeff_test_from_bigint(numerator_big)
    let (quotient, remainder) = numerator.div_rem_checked(denominator).unwrap()
    bin_coeff_test_assert_matches(quotient, numerator_big / denominator_big)
    bin_coeff_test_assert_matches(remainder, numerator_big % denominator_big)
    assert_true(remainder.compare(denominator) < 0)
    assert_eq(quotient.mul(denominator).add(remainder), numerator)
  }
}

///|
test "BinCoeff sqrtrem identity and thresholds" {
  for integer in 0..<4096 {
    let value = BinCoeff::from_uint64(integer.to_uint64())
    let (root, remainder) = bin_coeff_sqrt_rem_kernel(value)
    assert_eq(root.square().add(remainder), value)
    assert_true(remainder.compare(root.shift_left(1)) <= 0)
  }
  for limbs in [3, 4, 5, 6, 15, 16, 17, 31, 32, 33, 95, 96, 97, 257] {
    let value_big = bin_coeff_test_limb_pattern(limbs, 14)
    let value = bin_coeff_test_from_bigint(value_big)
    let (root, remainder) = bin_coeff_sqrt_rem_kernel(value)
    let root_big = bin_coeff_test_integer_sqrt_floor(value_big)
    bin_coeff_test_assert_matches(root, root_big)
    bin_coeff_test_assert_matches(remainder, value_big - root_big * root_big)
    assert_eq(root.square().add(remainder), value)
    assert_true(remainder.compare(root.shift_left(1)) <= 0)
  }
}

///|
fn bin_coeff_test_integer_sqrt_floor(value : BigInt) -> BigInt {
  if value <= 1N {
    return value
  }
  let mut root = 1N << ((value.bit_length() + 1) / 2)
  let mut next = (root + value / root) / 2N
  while next < root {
    root = next
    next = (root + value / root) / 2N
  }
  root
}
