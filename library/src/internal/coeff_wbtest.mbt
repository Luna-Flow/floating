///|
fn coeff_reference_values() -> Array[BigInt] {
  let values : Array[BigInt] = [0N, 1N, 2N, 3N, 1073741823N, 1073741824N]
  for shift in [30, 53, 63, 64, 65, 90, 127, 191, 257] {
    let power = 1N << shift
    values.push(power - 1N)
    values.push(power)
    values.push(power + 1N)
    values.push(power + (power >> 2) + 17N)
  }
  values
}

///|
fn coeff_assert_shift_round_sticky(value : BigInt, shift : Int32) -> Unit raise {
  let coefficient = coeff_from_nonnegative_bigint(value)
  let quotient = coeff_shift_right(coefficient, shift)
  let expected_quotient = value >> shift
  let expected_round_bit = shift > 0 && !((value >> (shift - 1)) % 2N).is_zero()
  let expected_sticky_bit = shift > 1 &&
    value != value >> (shift - 1) << (shift - 1)
  assert_eq(coeff_to_bigint(quotient), expected_quotient)
  let expected_rounded = if expected_round_bit &&
    (expected_sticky_bit || expected_quotient % 2N == 1N) {
    expected_quotient + 1N
  } else {
    expected_quotient
  }
  let (fused_rounded, fused_inexact) = coeff_round_shift_ties_even(
    coefficient, shift,
  )
  assert_eq(coeff_to_bigint(fused_rounded), expected_rounded)
  assert_eq(fused_inexact, expected_round_bit || expected_sticky_bit)
  match fused_rounded {
    Small(_) => assert_true(expected_rounded.bit_length() <= 64)
    Medium(high, _) => {
      assert_true(high != 0UL)
      assert_true(expected_rounded.bit_length() > 64)
      assert_true(expected_rounded.bit_length() <= 128)
    }
    Large(units) => {
      assert_true(expected_rounded.bit_length() > 128)
      assert_true(units.length() > 0)
      assert_true(units[units.length() - 1] != 0U)
    }
  }
}

///|
fn coeff_test_next_random(state : BigInt) -> BigInt {
  (state * 6364136223846793005N + 1442695040888963407N) % ((1N << 127) - 1N)
}

///|
fn coeff_test_random_value(state : BigInt, bits : Int32) -> (BigInt, BigInt) {
  let mut state = state
  let mut value = 0N
  let mut remaining = bits
  while remaining > 0 {
    state = coeff_test_next_random(state)
    let chunk_bits = Int32::min(remaining, 60)
    value = (value << chunk_bits) + state % (1N << chunk_bits)
    remaining -= chunk_bits
  }
  (state, value)
}

///|
fn coeff_assert_uint64_add(left : UInt64, right : UInt64) -> Unit raise {
  let result = coeff_add(coeff_from_uint64(left), coeff_from_uint64(right))
  let expected = BigInt::from_uint64(left) + BigInt::from_uint64(right)
  assert_eq(coeff_to_bigint(result), expected)
  assert_eq(coeff_bits(result), expected.bit_length())
  match result {
    Small(value) => {
      assert_true(expected.bit_length() <= 64)
      assert_eq(BigInt::from_uint64(value), expected)
    }
    Medium(high, low) => {
      assert_eq(expected.bit_length(), 65)
      assert_eq(high, 1UL)
      assert_eq(low, left + right)
    }
    Large(_) => fail("sum of two UInt64 values must not use limbs")
  }
}

///|
fn coeff_assert_medium_bigint_split(value : BigInt) -> Unit raise {
  assert_true(value.bit_length() > 64)
  assert_true(value.bit_length() <= 128)
  let coefficient = coeff_from_nonnegative_bigint(value)
  assert_eq(coeff_to_bigint(coefficient), value)
  match coefficient {
    Medium(high, low) => {
      assert_eq(high, (value >> 64).to_uint64())
      assert_eq(low, value.to_uint64())
      assert_true(high != 0UL)
    }
    Small(_) | Large(_) => fail("65-128 bit values must use Medium")
  }
}

///|
// oracle: A, S
// source: A: the representation class at 2^64 - 1, 2^64, 2^128 - 1, 2^128 by definition of the three forms, and the limbs of four values as literals (little-endian digits in base 2^30 computed with Python integers); S: the round trip through core BigInt and the bit length
// shares: nothing for the A rows; the S rows use both conversions
test "coefficient conversion preserves inline and limb values" {
  for value in coeff_reference_values() {
    let coefficient = coeff_from_nonnegative_bigint(value)
    assert_eq(coeff_to_bigint(coefficient), value)
    assert_eq(coeff_bits(coefficient), value.bit_length())
  }
  match coeff_from_nonnegative_bigint((1N << 64) - 1N) {
    Small(_) => ()
    Medium(_, _) | Large(_) => fail("64-bit coefficient should stay inline")
  }
  match coeff_from_nonnegative_bigint(1N << 64) {
    Small(_) | Large(_) => fail("65-bit coefficient should stay inline")
    Medium(_, _) => ()
  }
  match coeff_from_nonnegative_bigint((1N << 128) - 1N) {
    Small(_) | Large(_) => fail("128-bit coefficient should stay inline")
    Medium(_, _) => ()
  }
  match coeff_from_nonnegative_bigint(1N << 128) {
    Small(_) | Medium(_, _) => fail("129-bit coefficient should use limbs")
    Large(_) => ()
  }
  // Limb literals, little-endian digits in base 2^30 computed with Python
  // integers (v & (2^30 - 1), v >>= 30), independent of coeff_to_bigint.
  let limb_rows : Array[(BigInt, Array[UInt32])] = [
    (1N << 128, [0U, 0U, 0U, 0U, 256U]),
    ((1N << 128) + (1N << 64) + 5N, [5U, 0U, 16U, 0U, 256U]),
    ((1N << 191) + (1N << 93) + 15N, [15U, 0U, 0U, 8U, 0U, 0U, 2048U]),
    (
      (1N << 150) - 1N,
      [1073741823U, 1073741823U, 1073741823U, 1073741823U, 1073741823U],
    ),
  ]
  for row in limb_rows {
    match coeff_from_nonnegative_bigint(row.0) {
      Large(units) => assert_eq(units, row.1)
      Small(_) | Medium(_, _) => fail("expected limbs")
    }
  }
}

///|
// oracle: B
// source: the high and low word of each 65 to 128 bit value from core BigInt shifts and to_uint64; inputs are boundary values and a fixed-seed generator of the test file
// shares: coeff_from_nonnegative_bigint and coeff_to_bigint (the round trip assertion)
// primitives: the test generator coeff_test_next_random (only chooses inputs, never an expected value)
test "BigInt conversion splits Medium values without limbs" {
  for
    value in [
      1N << 64,
      (1N << 64) + 1N,
      (1N << 65) - 1N,
      1N << 65,
      1N << 127,
      (1N << 128) - 1N,
      (0x123456789abcdefN << 64) + 0xfedcba9876543210N,
    ] {
    coeff_assert_medium_bigint_split(value)
  }
  let mut state = 0x3c6ef372fe94f82bN
  for bits in 65..<129 {
    let top = 1N << (bits - 1)
    for _ in 0..<16 {
      let (next_state, random) = coeff_test_random_value(state, bits)
      state = next_state
      coeff_assert_medium_bigint_split(top + random % top)
    }
  }
}

///|
// oracle: B
// source: core BigInt +, *, - on the reference values (boundaries at 2^30, 2^53, 2^63, 2^64, 2^65, 2^90, 2^127, 2^191, 2^257 and a mixed value)
// shares: coeff_from_nonnegative_bigint and coeff_to_bigint to enter and leave the representation
// primitives: coeff_from_nonnegative_bigint and coeff_to_bigint; the representation class of 2^64 - 1, 2^64, 2^128 - 1, 2^128 and the base-2^30 limbs of four values are level A rows in `coefficient conversion preserves inline and limb values`, the Medium split in `BigInt conversion splits Medium values without limbs` (B: high and low word from core BigInt shifts)
test "coefficient arithmetic matches BigInt oracle" {
  let values = coeff_reference_values()
  for left in values {
    let left_coefficient = coeff_from_nonnegative_bigint(left)
    for right in values {
      let right_coefficient = coeff_from_nonnegative_bigint(right)
      assert_eq(
        coeff_to_bigint(coeff_add(left_coefficient, right_coefficient)),
        left + right,
      )
      assert_eq(
        coeff_to_bigint(coeff_mul(left_coefficient, right_coefficient)),
        left * right,
      )
      if left >= right {
        assert_eq(
          coeff_to_bigint(coeff_sub(left_coefficient, right_coefficient)),
          left - right,
        )
      }
    }
  }
}

///|
// oracle: B
// source: core BigInt sum of two UInt64 values; the form of the sum (Small up to 64 bits, Medium with high word 1 and low word the wrapped sum) from the definition of the forms; eight operand pairs at the carry boundaries
// shares: coeff_from_uint64, coeff_to_bigint
// primitives: coeff_from_nonnegative_bigint and coeff_to_bigint; the representation class of 2^64 - 1, 2^64, 2^128 - 1, 2^128 and the base-2^30 limbs of four values are level A rows in `coefficient conversion preserves inline and limb values`, the Medium split in `BigInt conversion splits Medium values without limbs` (B: high and low word from core BigInt shifts)
test "small coefficient addition preserves the UInt64 carry" {
  coeff_assert_uint64_add(0UL, 0UL)
  coeff_assert_uint64_add(0xffffffffffffffffUL, 0UL)
  coeff_assert_uint64_add(0x7fffffffffffffffUL, 1UL)
  coeff_assert_uint64_add(0x8000000000000000UL, 0x7fffffffffffffffUL)
  coeff_assert_uint64_add(0x8000000000000000UL, 0x8000000000000000UL)
  coeff_assert_uint64_add(0xffffffffffffffffUL, 1UL)
  coeff_assert_uint64_add(0xffffffffffffffffUL, 0xffffffffffffffffUL)
  coeff_assert_uint64_add(0x8000000000000001UL, 0x8000000000000002UL)
}

///|
// oracle: B
// source: core BigInt sum of two UInt64 values: all 256 x 256 pairs just below 2^64 and 1024 fixed-seed random pairs in both orders
// shares: coeff_from_uint64, coeff_to_bigint
// primitives: coeff_from_nonnegative_bigint and coeff_to_bigint; the representation class of 2^64 - 1, 2^64, 2^128 - 1, 2^128 and the base-2^30 limbs of four values are level A rows in `coefficient conversion preserves inline and limb values`, the Medium split in `BigInt conversion splits Medium values without limbs` (B: high and low word from core BigInt shifts)
test "small coefficient addition matches boundary and random oracles" {
  let boundary_start = (1N << 64) - 256N
  for left_offset in 0..<256 {
    let left = (boundary_start + BigInt::from_int(left_offset)).to_uint64()
    for right_value in 0..<256 {
      coeff_assert_uint64_add(left, BigInt::from_int(right_value).to_uint64())
    }
  }
  let mut state = 0xbb67ae8584caa73bN
  for _ in 0..<1024 {
    let (left_state, left) = coeff_test_random_value(state, 64)
    let (right_state, right) = coeff_test_random_value(left_state, 64)
    state = right_state
    coeff_assert_uint64_add(left.to_uint64(), right.to_uint64())
    coeff_assert_uint64_add(right.to_uint64(), left.to_uint64())
  }
}

///|
// oracle: B
// source: core BigInt << and >> on the reference values for shifts 0, 1, 29, 30, 31, 63, 64, 91, 193, 300
// shares: coeff_from_nonnegative_bigint and coeff_to_bigint
// primitives: coeff_from_nonnegative_bigint and coeff_to_bigint; the representation class of 2^64 - 1, 2^64, 2^128 - 1, 2^128 and the base-2^30 limbs of four values are level A rows in `coefficient conversion preserves inline and limb values`, the Medium split in `BigInt conversion splits Medium values without limbs` (B: high and low word from core BigInt shifts)
test "coefficient shifts match BigInt oracle" {
  for value in coeff_reference_values() {
    let coefficient = coeff_from_nonnegative_bigint(value)
    for shift in [0, 1, 29, 30, 31, 63, 64, 91, 193, 300] {
      assert_eq(
        coeff_to_bigint(coeff_shift_left(coefficient, shift)),
        value << shift,
      )
      assert_eq(
        coeff_to_bigint(coeff_shift_right(coefficient, shift)),
        value >> shift,
      )
    }
  }
}

///|
// oracle: B
// source: round to nearest even and the inexact flag from the definition, computed on core BigInt: quotient v >> s, round bit bit s - 1, sticky bit = any lower bit; all values below 4096 and shifts 0 to 15
// shares: coeff_from_nonnegative_bigint, coeff_to_bigint, coeff_shift_right (the quotient is also checked against core >>)
// primitives: coeff_from_nonnegative_bigint and coeff_to_bigint; the representation class of 2^64 - 1, 2^64, 2^128 - 1, 2^128 and the base-2^30 limbs of four values are level A rows in `coefficient conversion preserves inline and limb values`, the Medium split in `BigInt conversion splits Medium values without limbs` (B: high and low word from core BigInt shifts)
test "fused coefficient round shift is exhaustive for small values" {
  for raw_value in 0..<4096 {
    let value = BigInt::from_int(raw_value)
    for shift in 0..<16 {
      coeff_assert_shift_round_sticky(value, shift)
    }
  }
}

///|
// oracle: B
// source: round to nearest even and the inexact flag from the definition on core BigInt (quotient v >> s, round bit s - 1, sticky bit = any lower bit); values at 2^b - 1, 2^b, 2^b + 1 and 1.5 * 2^b + 1 for b at the 30, 64, 128 and 256 bit representation edges
// shares: coeff_from_nonnegative_bigint, coeff_to_bigint, coeff_shift_right
// primitives: coeff_from_nonnegative_bigint and coeff_to_bigint; the representation class of 2^64 - 1, 2^64, 2^128 - 1, 2^128 and the base-2^30 limbs of four values are level A rows in `coefficient conversion preserves inline and limb values`, the Medium split in `BigInt conversion splits Medium values without limbs` (B: high and low word from core BigInt shifts)
test "fused coefficient round shift handles representation boundaries" {
  for bits in [30, 31, 63, 64, 65, 127, 128, 129, 191, 257] {
    let power = 1N << bits
    for value in [power - 1N, power, power + 1N, power + (power >> 1) + 1N] {
      for shift in [0, 1, bits - 1, bits, bits + 1, bits * 4 + 17] {
        coeff_assert_shift_round_sticky(value, shift)
      }
    }
  }
}

///|
// oracle: B
// source: round to nearest even and the inexact flag from the definition on core BigInt (quotient v >> s, round bit s - 1, sticky bit = any lower bit); remainders 0, half - 1, half, half + 1 and 2^s - 1 around the tie for shifts up to 191, with even and odd quotients of both representations
// shares: coeff_from_nonnegative_bigint, coeff_to_bigint, coeff_shift_right
// primitives: coeff_from_nonnegative_bigint and coeff_to_bigint; the representation class of 2^64 - 1, 2^64, 2^128 - 1, 2^128 and the base-2^30 limbs of four values are level A rows in `coefficient conversion preserves inline and limb values`, the Medium split in `BigInt conversion splits Medium values without limbs` (B: high and low word from core BigInt shifts)
test "fused coefficient round shift handles ties and sticky patterns" {
  for shift in [1, 2, 29, 30, 31, 63, 64, 65, 127, 128, 129, 191] {
    let half = 1N << (shift - 1)
    let limit = 1N << shift
    let remainders : Array[BigInt] = [0N, half - 1N, half, limit - 1N]
    if half + 1N < limit {
      remainders.push(half + 1N)
    }
    for quotient in [2N, 3N, (1N << 70) + 2N, (1N << 70) + 3N] {
      for remainder in remainders {
        coeff_assert_shift_round_sticky((quotient << shift) + remainder, shift)
      }
    }
  }
}

///|
// oracle: B
// source: round to nearest even and the inexact flag from the definition on core BigInt (quotient v >> s, round bit s - 1, sticky bit = any lower bit); four values whose rounding carries into the next representation (2^65 - 1, 2^129 - 1 with shift 1, and two ties on all-ones quotients)
// shares: coeff_from_nonnegative_bigint, coeff_to_bigint, coeff_shift_right
// primitives: coeff_from_nonnegative_bigint and coeff_to_bigint; the representation class of 2^64 - 1, 2^64, 2^128 - 1, 2^128 and the base-2^30 limbs of four values are level A rows in `coefficient conversion preserves inline and limb values`, the Medium split in `BigInt conversion splits Medium values without limbs` (B: high and low word from core BigInt shifts)
test "fused coefficient shift rounding carries across representations" {
  coeff_assert_shift_round_sticky((1N << 65) - 1N, 1)
  coeff_assert_shift_round_sticky((1N << 129) - 1N, 1)
  let wide_quotient = (1N << 150) - 1N
  coeff_assert_shift_round_sticky((wide_quotient << 30) + (1N << 29), 30)
  let medium_quotient = (1N << 64) - 1N
  coeff_assert_shift_round_sticky((medium_quotient << 65) + (1N << 64), 65)
}

///|
// oracle: B
// source: round to nearest even and the inexact flag from the definition on core BigInt (quotient v >> s, round bit s - 1, sticky bit = any lower bit); 256 fixed-seed random values of 1 to 1024 bits with a shift index * 37 mod (bits + 97)
// shares: coeff_from_nonnegative_bigint, coeff_to_bigint, coeff_shift_right
// primitives: coeff_from_nonnegative_bigint and coeff_to_bigint; the representation class of 2^64 - 1, 2^64, 2^128 - 1, 2^128 and the base-2^30 limbs of four values are level A rows in `coefficient conversion preserves inline and limb values`, the Medium split in `BigInt conversion splits Medium values without limbs` (B: high and low word from core BigInt shifts)
test "fused coefficient round shift matches fixed-seed random oracle" {
  let widths = [1, 30, 53, 64, 65, 113, 128, 129, 256, 1024]
  let mut state = 0x6a09e667f3bcc909N
  for index in 0..<256 {
    let bits = widths[index % widths.length()]
    let (next_state, value) = coeff_test_random_value(state, bits)
    state = next_state
    let shift = index * 37 % (bits + 97)
    coeff_assert_shift_round_sticky(value, shift)
  }
}

///|
// oracle: B
// source: core BigInt / and % on all pairs of the reference values with a non-zero divisor
// shares: coeff_from_nonnegative_bigint and coeff_to_bigint
// primitives: coeff_from_nonnegative_bigint and coeff_to_bigint; the representation class of 2^64 - 1, 2^64, 2^128 - 1, 2^128 and the base-2^30 limbs of four values are level A rows in `coefficient conversion preserves inline and limb values`, the Medium split in `BigInt conversion splits Medium values without limbs` (B: high and low word from core BigInt shifts)
test "coefficient Knuth division matches BigInt oracle" {
  let values = coeff_reference_values()
  for numerator in values {
    let numerator_coefficient = coeff_from_nonnegative_bigint(numerator)
    for denominator in values {
      if !denominator.is_zero() {
        let (quotient, remainder) = coeff_div_rem(
          numerator_coefficient,
          coeff_from_nonnegative_bigint(denominator),
        )
        assert_eq(coeff_to_bigint(quotient), numerator / denominator)
        assert_eq(coeff_to_bigint(remainder), numerator % denominator)
      }
    }
  }
}

///|
// oracle: B
// source: core BigInt +, -, * of a signed pair, and the Euclid algorithm written in the test file (internal_gcd_oracle) on core BigInt for the gcd of two products with a common factor 2^89 + 7
// shares: signed_coeff_from_bigint and signed_coeff_to_bigint, coeff_from_nonnegative_bigint, coeff_to_bigint
// primitives: coeff_from_nonnegative_bigint and coeff_to_bigint; the representation class of 2^64 - 1, 2^64, 2^128 - 1, 2^128 and the base-2^30 limbs of four values are level A rows in `coefficient conversion preserves inline and limb values`, the Medium split in `BigInt conversion splits Medium values without limbs` (B: high and low word from core BigInt shifts)
test "coefficient gcd and signed arithmetic match BigInt oracle" {
  let left = (1N << 191) + (1N << 93) + 15N
  let right = (1N << 127) + (1N << 61) + 9N
  let left_signed = signed_coeff_from_bigint(-left)
  let right_signed = signed_coeff_from_bigint(right)
  assert_eq(
    signed_coeff_to_bigint(signed_coeff_add(left_signed, right_signed)),
    -left + right,
  )
  assert_eq(
    signed_coeff_to_bigint(signed_coeff_sub(left_signed, right_signed)),
    -left - right,
  )
  assert_eq(
    signed_coeff_to_bigint(signed_coeff_mul(left_signed, right_signed)),
    -left * right,
  )
  let common = (1N << 89) + 7N
  let common_coefficient = coeff_from_nonnegative_bigint(common)
  let gcd = coeff_gcd(
    coeff_mul(coeff_from_nonnegative_bigint(left), common_coefficient),
    coeff_mul(coeff_from_nonnegative_bigint(right), common_coefficient),
  )
  let expected = internal_gcd_oracle(left * common, right * common)
  assert_eq(coeff_to_bigint(gcd), expected)
}

///|
fn internal_gcd_oracle(left : BigInt, right : BigInt) -> BigInt {
  let mut left = left
  let mut right = right
  while !right.is_zero() {
    let remainder = left % right
    left = right
    right = remainder
  }
  left
}
