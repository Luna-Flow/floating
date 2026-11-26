///|
fn bin_coeff_test_from_bigint(value : BigInt) -> Coeff {
  Coeff::parse(value.to_string()).unwrap()
}

///|
fn bin_coeff_test_assert_matches(
  value : Coeff,
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
// oracle: S
// source: round trips of nine decimal literals written out (parse then print gives the text back; bytes out and in gives the value back); the only written values are b"" parsing to "0" and zero serialising to b"\x00"
// shares: Coeff::parse, Coeff::to_string, Coeff::from_bytes_be and Coeff::to_bytes_be are both sides of each round trip
test "Coeff canonical boundaries and serialization" {
  let sources = [
    "0", "1", "4294967295", "4294967296", "18446744073709551615", "18446744073709551616",
    "340282366920938463463374607431768211455", "340282366920938463463374607431768211456",
    "1461501637330902918203684832716283019655932542975",
  ]
  for source in sources {
    let value = Coeff::parse(source).unwrap()
    assert_eq(value.to_string(), source)
    assert_eq(Coeff::from_bytes_be(value.to_bytes_be()), value)
  }
  assert_eq(Coeff::from_bytes_be(b"").to_string(), "0")
  assert_eq(Coeff::zero().to_bytes_be(), b"\x00")
}

///|
// oracle: B
// source: core BigInt + * & | ^ - / % on every pair of 0 to 95, compared through the decimal text; subtraction below zero and division by zero must fail
// shares: Coeff::parse, Coeff::to_string (the comparison goes through the decimal text, so a fault that is the same in both would pass; the text of powers of the radix is written out in the radix block)
// primitives: core BigInt (moonbitlang/core) arithmetic is an implementation independent of the kernel; the decimal text path (Coeff::parse, Coeff::to_string): the powers of the radix and their neighbours are written out as text in `radix conversion of powers of the radix and their neighbours at chunk edges` (coeff_radix_nonjs_wbtest.mbt)
test "Coeff exhaustive small arithmetic" {
  for left in 0..<96 {
    for right in 0..<96 {
      let left_coeff = Coeff::from_uint64(left.to_uint64())
      let right_coeff = Coeff::from_uint64(right.to_uint64())
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
// oracle: B
// source: core BigInt + * & | ^ - / % on every pair of 11 edge values from 2^31 - 1 to 2^521 - 1 (bits at 31, 32, 63, 64, 96, 127, 128, 159, 257, 521), compared through the decimal text; the identity q d + r = n is also checked with the kernel product and sum
// shares: Coeff::parse, Coeff::to_string (the comparison goes through the decimal text, so a fault that is the same in both would pass; the text of powers of the radix is written out in the radix block); the kernel mul and add in the identity
// primitives: core BigInt (moonbitlang/core) arithmetic is an implementation independent of the kernel; the decimal text path (Coeff::parse, Coeff::to_string): the powers of the radix and their neighbours are written out as text in `radix conversion of powers of the radix and their neighbours at chunk edges` (coeff_radix_nonjs_wbtest.mbt)
test "Coeff large arithmetic differential" {
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
// oracle: B, S
// source: B: core BigInt << >> and bit_length, bit k as (n >> k) & 1, Euclid written in the test on BigInt (bin_coeff_test_bigint_gcd), 37^19 from BigInt::pow, the trailing zero count 93 of a value shifted by 93; S: the radix text round trip for radixes 2 to 36
// shares: Coeff::parse, Coeff::to_string (the comparison goes through the decimal text, so a fault that is the same in both would pass; the text of powers of the radix is written out in the radix block); Coeff::parse and Coeff::to_radix_string are both sides of the round trip
// primitives: core BigInt (moonbitlang/core) arithmetic is an implementation independent of the kernel; the decimal text path (Coeff::parse, Coeff::to_string): the powers of the radix and their neighbours are written out as text in `radix conversion of powers of the radix and their neighbours at chunk edges` (coeff_radix_nonjs_wbtest.mbt)
test "Coeff shifts bits gcd powers and radices" {
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
    Coeff::from_uint64(37UL).pow_nat(19U),
    BigInt::from_int(37).pow(BigInt::from_int(19)),
  )
  for radix in [2, 3, 8, 10, 16, 31, 36] {
    let text = source.to_radix_string(radix)
    assert_eq(Coeff::parse(text, radix~).unwrap(), source)
  }
}

///|
// oracle: B
// source: Euclid written in the test on core BigInt (bin_coeff_test_bigint_gcd) for every pair of eight edge values from 0 to 2^128 - 1 (the 64-bit and 128-bit inline limits)
// shares: Coeff::parse, Coeff::to_string (the comparison goes through the decimal text, so a fault that is the same in both would pass; the text of powers of the radix is written out in the radix block)
// primitives: core BigInt (moonbitlang/core) arithmetic is an implementation independent of the kernel; the decimal text path (Coeff::parse, Coeff::to_string): the powers of the radix and their neighbours are written out as text in `radix conversion of powers of the radix and their neighbours at chunk edges` (coeff_radix_nonjs_wbtest.mbt)
test "Coeff inline binary gcd boundaries" {
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
/// Operands of different lengths used to give the Lehmer loop leading digits
/// of unrelated scales; this pair (from `ln(1 + 2^-243)` at 245 bits) needed
/// about 2^220 rounds.
// oracle: B
// source: Euclid written in the test on core BigInt for six pairs of unrelated lengths (a pair from ln(1 + 2^-243) at 245 bits that needed about 2^220 Lehmer rounds), both orders of the operands
// shares: Coeff::parse, Coeff::to_string (the comparison goes through the decimal text, so a fault that is the same in both would pass; the text of powers of the radix is written out in the radix block)
// primitives: core BigInt (moonbitlang/core) arithmetic is an implementation independent of the kernel; the decimal text path (Coeff::parse, Coeff::to_string): the powers of the radix and their neighbours are written out as text in `radix conversion of powers of the radix and their neighbours at chunk edges` (coeff_radix_nonjs_wbtest.mbt)
test "Coeff gcd of operands with different lengths" {
  let odd_big = bigint_from_text(
    "2037035976334486086268445688409378161051468393665936250636140449354381299691279112145469441",
  )
  let pairs = [
    (odd_big, 1N << 543),
    (odd_big << 7, 1N << 543),
    (odd_big, (1N << 4000) + 3N),
    ((1N << 600) - 1N, (1N << 300) - 1N),
    ((1N << 1000) + 1N, (1N << 999) + 7N),
    ((3N << 700) + 5N, odd_big * odd_big * odd_big),
  ]
  for pair in pairs {
    let (left_big, right_big) = pair
    let left = bin_coeff_test_from_bigint(left_big)
    let right = bin_coeff_test_from_bigint(right_big)
    let expected = bin_coeff_test_bigint_gcd(left_big, right_big)
    bin_coeff_test_assert_matches(left.gcd(right), expected)
    bin_coeff_test_assert_matches(right.gcd(left), expected)
  }
}

///|
// oracle: S
// source: round trip of a 2,200-digit decimal text and a 6,000-digit ternary text (parse then print gives the text back); no independent value
// shares: Coeff::parse and Coeff::to_string / to_radix_string are both sides of the round trip
test "Coeff divide-and-conquer radix conversion" {
  let decimal_builder = StringBuilder()
  decimal_builder.write_char('9')
  for index in 1..<2200 {
    decimal_builder.write_char(
      Int32::unsafe_to_char('0'.to_int() + (index * 7 + 3) % 10),
    )
  }
  let decimal = decimal_builder.to_string()
  let decimal_value = Coeff::parse(decimal).unwrap()
  assert_eq(decimal_value.to_string(), decimal)
  let ternary_builder = StringBuilder()
  ternary_builder.write_char('2')
  for index in 1..<6000 {
    ternary_builder.write_char(
      Int32::unsafe_to_char('0'.to_int() + (index * 5 + 1) % 3),
    )
  }
  let ternary = ternary_builder.to_string()
  let ternary_value = Coeff::parse(ternary, radix=3).unwrap()
  assert_eq(ternary_value.to_radix_string(3), ternary)
}

///|
// oracle: A
// source: written out: 1 - 2 is an error, division by zero is an error, the empty text, "-1", the digit 2 in radix 2 and radix 1 are rejected
// shares: nothing
test "Coeff checked failures" {
  assert_true(Coeff::one().sub_checked(Coeff::from_uint64(2UL)) is Err(_))
  assert_true(Coeff::one().div_rem_checked(Coeff::zero()) is Err(_))
  assert_true(Coeff::parse("") is Err(_))
  assert_true(Coeff::parse("-1") is Err(_))
  assert_true(Coeff::parse("2", radix=2) is Err(_))
  assert_true(Coeff::parse("0", radix=1) is Err(_))
}

///|
fn bin_coeff_test_limb_pattern(limbs : Int32, phase : Int32) -> BigInt {
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
// oracle: B
// source: core BigInt product and square of bit patterns of 3 to 769 limbs on both sides of every multiplication cutoff (Comba, Karatsuba, Toom, NTT) and of one unbalanced pair, compared through the decimal text
// shares: Coeff::parse, Coeff::to_string (the comparison goes through the decimal text, so a fault that is the same in both would pass; the text of powers of the radix is written out in the radix block); bin_coeff_test_limb_pattern builds the operands (never the expected value)
// primitives: core BigInt (moonbitlang/core) arithmetic is an implementation independent of the kernel; the decimal text path (Coeff::parse, Coeff::to_string): the powers of the radix and their neighbours are written out as text in `radix conversion of powers of the radix and their neighbours at chunk edges` (coeff_radix_nonjs_wbtest.mbt)
test "Coeff multiplication algorithm thresholds" {
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
// oracle: B
// source: core BigInt product of a 96-limb and a 193-limb bit pattern, compared through the decimal text
// shares: Coeff::parse, Coeff::to_string (the comparison goes through the decimal text, so a fault that is the same in both would pass; the text of powers of the radix is written out in the radix block); bin_coeff_test_limb_pattern builds the operands
// primitives: core BigInt (moonbitlang/core) arithmetic is an implementation independent of the kernel; the decimal text path (Coeff::parse, Coeff::to_string): the powers of the radix and their neighbours are written out as text in `radix conversion of powers of the radix and their neighbours at chunk edges` (coeff_radix_nonjs_wbtest.mbt)
test "Coeff unbalanced multiplication accumulates exact limbs" {
  let short_big = bin_coeff_test_limb_pattern(96, 2)
  let long_big = bin_coeff_test_limb_pattern(193, 11)
  let short = bin_coeff_test_from_bigint(short_big)
  let long = bin_coeff_test_from_bigint(long_big)
  bin_coeff_test_assert_matches(short.mul(long), short_big * long_big)
}

///|
// oracle: B
// source: core BigInt product (and square when the operands are equal) of every pair of nine values around 2^63, 2^64, 2^95, 2^127 and 2^128, the inline limits
// shares: Coeff::parse, Coeff::to_string (the comparison goes through the decimal text, so a fault that is the same in both would pass; the text of powers of the radix is written out in the radix block)
// primitives: core BigInt (moonbitlang/core) arithmetic is an implementation independent of the kernel; the decimal text path (Coeff::parse, Coeff::to_string): the powers of the radix and their neighbours are written out as text in `radix conversion of powers of the radix and their neighbours at chunk edges` (coeff_radix_nonjs_wbtest.mbt)
test "Coeff inline Comba multiplication boundaries" {
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
// oracle: B
// source: core BigInt / and % of limb patterns around the division cutoffs (divisors of 46 to 50 limbs, dividends of three times the length plus 5), the remainder below the divisor, and q d + r = n with the kernel product and sum
// shares: Coeff::parse, Coeff::to_string (the comparison goes through the decimal text, so a fault that is the same in both would pass; the text of powers of the radix is written out in the radix block); bin_coeff_test_limb_pattern builds the operands; the kernel mul and add in the identity
// primitives: core BigInt (moonbitlang/core) arithmetic is an implementation independent of the kernel; the decimal text path (Coeff::parse, Coeff::to_string): the powers of the radix and their neighbours are written out as text in `radix conversion of powers of the radix and their neighbours at chunk edges` (coeff_radix_nonjs_wbtest.mbt)
test "Coeff division algorithm thresholds" {
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
// oracle: B, S
// source: B: floor square root by Newton iteration written in the test on core BigInt (bin_coeff_test_integer_sqrt_floor) for limb patterns of 3 to 257 limbs around the cutoffs, and the remainder n - root^2; S: the identity root^2 + rem = n with rem <= 2 root for every value below 4,096, with the kernel square and add
// shares: Coeff::parse, Coeff::to_string (the comparison goes through the decimal text, so a fault that is the same in both would pass; the text of powers of the radix is written out in the radix block); the kernel square, add, shift_left in the identity
// primitives: core BigInt (moonbitlang/core) arithmetic is an implementation independent of the kernel; the decimal text path (Coeff::parse, Coeff::to_string): the powers of the radix and their neighbours are written out as text in `radix conversion of powers of the radix and their neighbours at chunk edges` (coeff_radix_nonjs_wbtest.mbt)
test "Coeff sqrtrem identity and thresholds" {
  for integer in 0..<4096 {
    let value = Coeff::from_uint64(integer.to_uint64())
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

///|
// oracle: E
// source: equivalence of add_shifted_left with the two-step route shift_left then add, on random limbs, all-ones runs (carry chains), small and zero operands, 11 shifts from 0 to 1,031
// shares: Coeff::shift_left, Coeff::add and Coeff::compare (the two-step route is the reference)
// underneath: shift_left and add: level B against core BigInt in `Coeff shifts bits gcd powers and radices` and `Coeff large arithmetic differential` (this file)
test "add_shifted_left equals shift_left then add" {
  // Pseudo-random limbs, all-ones runs (carry chains), small and zero operands.
  let mut state = 88172645463325252UL
  let next = fn() -> UInt64 {
    state = state ^ (state << 13)
    state = state ^ (state >> 7)
    state = state ^ (state << 17)
    state
  }
  let make = fn(limbs : Int32, ones : Bool) -> Coeff {
    let mut value = Coeff::zero()
    for _ in 0..<limbs {
      let limb = if ones { 18446744073709551615UL } else { next() }
      value = value.shift_left(64).add(Coeff::from_uint64(limb))
    }
    value
  }
  let shapes = [0, 1, 2, 3, 5, 17, 40]
  let shifts = [0, 1, 17, 63, 64, 65, 127, 128, 300, 1024, 1031]
  for a_limbs in shapes {
    for b_limbs in shapes {
      for shift in shifts {
        for ones in [false, true] {
          let a = make(a_limbs, ones)
          let b = make(b_limbs, ones)
          assert_eq(
            a.add_shifted_left(shift, b).compare(a.shift_left(shift).add(b)),
            0,
          )
        }
      }
    }
  }
}
