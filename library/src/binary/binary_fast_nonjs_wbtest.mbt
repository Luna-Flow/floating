///|
/// The addition without the sign flip of the subtraction (the production name
/// carries the flag).
fn binary_fast_add(left : Binary, right : Binary) -> Binary? {
  binary_fast_add_signed(left, right, false)
}

///|
struct FastTestRandom {
  mut state : UInt64
}

///|
fn FastTestRandom::next(self : FastTestRandom) -> UInt64 {
  self.state = self.state * 6364136223846793005UL + 1442695040888963407UL
  self.state >> 11
}

///|
fn FastTestRandom::below(self : FastTestRandom, limit : Int32) -> Int32 {
  (self.next() % limit.to_uint64()).to_int()
}

///|
/// A finite operand: a coefficient of 1 to 64 bits (small widths are frequent,
/// so ties, carries and exact results occur), a nearby or far exponent, and its
/// own precision. Also draws zeros now and then.
fn fast_test_operand(random : FastTestRandom, around : Int32) -> Binary {
  let precision = 2 + random.below(61)
  let width = match random.below(4) {
    0 => 1 + random.below(4)
    1 => 1 + random.below(20)
    _ => 1 + random.below(64)
  }
  let mut word = (random.next() << 13) | (random.next() & 0x1fffUL)
  if width < 64 {
    word = word >> (64 - width)
  }
  word = word | (1UL << (width - 1)) | 1UL
  let exponent = around +
    random.below(9) -
    4 -
    (if random.below(8) == 0 { random.below(150) } else { 0 })
  let negative = random.below(2) == 0
  if random.below(60) == 0 {
    Binary::zero(precision~)
  } else {
    Binary::make_coeff(Coeff::from_uint64(word), exponent, precision, negative~)
  }
}

///|
fn fast_test_same(actual : Binary, expected : Binary) -> Bool {
  actual.identical(expected) &&
  actual.precision() == expected.precision() &&
  actual.is_sign_minus() == expected.is_sign_minus() &&
  actual.exponent2() == expected.exponent2()
}

///|
test "one-word add equals the general path" {
  let random = { state: 0x5DEECE66DUL, }
  let mut fast = 0
  for index in 0..<40000 {
    let around = random.below(120) - 60
    let left = fast_test_operand(random, around)
    let right = fast_test_operand(random, around + random.below(7) - 3)
    let general = left.add_ctx(
        right,
        BinaryContext::new(precision=max_precision(left, right)),
      ).0
    match binary_fast_add(left, right) {
      Some(result) => {
        fast += 1
        assert_true(fast_test_same(result, general))
      }
      None => ()
    }
    // the public entry point is the same value either way
    assert_true(fast_test_same(left.add(right), general))
    ignore(index)
  }
  assert_true(fast > 20000)
}

///|
test "one-word mul equals the general path" {
  let random = { state: 0x2545F4914F6CDD1DUL, }
  let mut fast = 0
  for _ in 0..<40000 {
    let around = random.below(400) - 200
    let left = fast_test_operand(random, around)
    let right = fast_test_operand(random, random.below(400) - 200)
    let general = left.mul_ctx(
        right,
        BinaryContext::new(precision=max_precision(left, right)),
      ).0
    match binary_fast_mul(left, right) {
      Some(result) => {
        fast += 1
        assert_true(fast_test_same(result, general))
      }
      None => ()
    }
    assert_true(fast_test_same(left.mul(right), general))
  }
  assert_true(fast > 20000)
}

///|
test "one-word div equals the general path" {
  let random = { state: 0x9E3779B97F4A7C15UL, }
  let mut fast = 0
  for _ in 0..<40000 {
    let left = fast_test_operand(random, random.below(400) - 200)
    let right = fast_test_operand(random, random.below(400) - 200)
    if right.is_zero() {
      continue
    }
    let general = left.div_ctx(
        right,
        BinaryContext::new(precision=max_precision(left, right)),
      ).0
    match binary_fast_div(left, right) {
      Some(result) => {
        fast += 1
        assert_true(fast_test_same(result, general))
      }
      None => ()
    }
    assert_true(fast_test_same(left.div(right), general))
  }
  assert_true(fast > 20000)
}

///|
test "one-word paths decline what they do not cover" {
  let one = Binary::from_int(1, precision=53)
  let big = Binary::make_coeff(
    Coeff::one().shift_left(100).add(Coeff::one()),
    0,
    128,
  )
  assert_true(binary_fast_add(one, Binary::zero(precision=53)) is None)
  assert_true(binary_fast_add(one, Binary::nan(precision=53)) is None)
  assert_true(binary_fast_mul(one, Binary::inf(precision=53)) is None)
  assert_true(binary_fast_div(one, Binary::zero(precision=53)) is None)
  assert_true(binary_fast_add(one, big) is None)
  // an exact zero sum
  assert_true(binary_fast_add(one, one.neg()) is None)
  // exponents near the implementation limits
  let far = Binary::make_coeff(Coeff::one(), 400000000, 53)
  assert_true(binary_fast_mul(far, far) is None)
  // far apart operands use the general path
  let tiny = Binary::make_coeff(Coeff::one(), -200, 53)
  assert_true(binary_fast_add(one, tiny) is None)
  assert_true(
    fast_test_same(
      one.add(tiny),
      one.add_ctx(tiny, BinaryContext::new(precision=53)).0,
    ),
  )
}

///|
test "one-word paths handle ties, carries and cancellation" {
  // 1 + 2^-53 is a tie at 53 bits (round to even keeps 1); 1 + 3 * 2^-54 rounds up
  let one = Binary::from_int(1, precision=53)
  for tail in [1, 3, 5, 7] {
    let small = Binary::make_coeff(
      Coeff::from_uint64(tail.to_uint64()),
      -55,
      53,
    )
    let general = one.add_ctx(small, BinaryContext::new(precision=53)).0
    assert_true(fast_test_same(one.add(small), general))
    let general_sub = one.add_ctx(small.neg(), BinaryContext::new(precision=53)).0
    assert_true(fast_test_same(one.sub(small), general_sub))
  }
  // all ones plus one carries into a new bit
  let ones = Binary::make_coeff(
    Coeff::one().shift_left(53).sub_checked(Coeff::one()).unwrap(),
    0,
    53,
  )
  let general = ones.add_ctx(one, BinaryContext::new(precision=53)).0
  assert_true(fast_test_same(ones.add(one), general))
  // heavy cancellation
  let near = Binary::make_coeff(
    Coeff::one().shift_left(53).add(Coeff::one()),
    -53,
    54,
  )
  let general_diff = near.add_ctx(one.neg(), BinaryContext::new(precision=54)).0
  assert_true(fast_test_same(near.sub(one), general_diff))
}

///|
test "one-word sqrt equals the general path" {
  let random = { state: 0x1234ABCD5678EF01UL, }
  let mut fast = 0
  for _ in 0..<40000 {
    let value = fast_test_operand(random, random.below(600) - 300).abs()
    if value.is_zero() {
      continue
    }
    let general = sqrt_for_precision(value, value.precision())
    match binary_fast_sqrt(value) {
      Some(result) => {
        fast += 1
        assert_true(fast_test_same(result, general))
      }
      None => ()
    }
    assert_true(fast_test_same(value.sqrt(), general))
  }
  assert_true(fast > 20000)
}

///|
test "one-word sqrt handles perfect squares, powers of two and odd exponents" {
  for precision in [2, 24, 53, 60] {
    for
      word in [
        1UL, 3UL, 9UL, 25UL, 0xFFFFFFFFUL, 0xFFFFFFFFFFFFFFFFUL, 0x4000000000000001UL,
      ] {
      for exponent in [-7, -6, -1, 0, 1, 2, 3, 100, 101] {
        let value = Binary::make_coeff(
          Coeff::from_uint64(word),
          exponent,
          precision,
        )
        let general = sqrt_for_precision(value, value.precision())
        assert_true(fast_test_same(value.sqrt(), general))
        let squared = value.mul_ctx(value, BinaryContext::new(precision~)).0
        let general_root = sqrt_for_precision(squared, squared.precision())
        assert_true(fast_test_same(squared.sqrt(), general_root))
      }
    }
  }
  assert_true(binary_fast_sqrt(Binary::from_int(-4, precision=53)) is None)
  assert_true(binary_fast_sqrt(Binary::zero(precision=53)) is None)
  assert_true(binary_fast_sqrt(Binary::inf(precision=53)) is None)
}

///|
/// A finite operand of exactly `precision` bits (top bit and low bit set), the
/// full-width case of the benchmark and of binary64 use.
fn fast_test_full_operand(
  random : FastTestRandom,
  precision : Int32,
  around : Int32,
) -> Binary {
  let mut word = (random.next() << 13) | (random.next() & 0x1fffUL)
  word = (word >> (64 - precision)) | (1UL << (precision - 1))
  if random.below(4) != 0 {
    word = word | 1UL
  }
  Binary::make_coeff(
    Coeff::from_uint64(word),
    around + random.below(17) - 8,
    precision,
    negative=random.below(2) == 0,
  )
}

///|
test "binary64 quotient and root equal the integer word path and the general path" {
  let random = { state: 0xB0B0CAFE12345UL, }
  let mut done = 0
  for round in 0..<200000 {
    let around = random.below(2000) - 1000
    let left_precision = if round % 5 == 0 { 20 + random.below(34) } else { 53 }
    let right_precision = if round % 7 == 0 {
      20 + random.below(34)
    } else {
      53
    }
    let left = fast_test_full_operand(random, left_precision, around)
    let right = fast_test_full_operand(random, right_precision, around)
    let result_precision = Int32::max(left_precision, right_precision)
    let quotient = binary_fast_div(left, right).unwrap()
    let general_quotient = left.div_ctx(
        right,
        BinaryContext::new(precision=result_precision),
      ).0
    assert_true(fast_test_same(quotient, general_quotient))
    if result_precision == 53 {
      done += 1
      assert_true(
        fast_test_same(quotient, binary_fast_div_words(left, right).unwrap()),
      )
    }
    let value = left.abs()
    let root = binary_fast_sqrt(value).unwrap()
    let general_root = sqrt_for_precision(value, left_precision)
    assert_true(fast_test_same(root, general_root))
    if left_precision == 53 {
      assert_true(fast_test_same(root, binary_fast_sqrt_words(value).unwrap()))
    }
  }
  assert_true(done > 100000)
}

///|
test "binary64 quotient and root at ties, exact results and powers of two" {
  let words = [
    1UL,
    3UL,
    5UL,
    9UL,
    0x1fffffffffffffUL,
    0x10000000000001UL,
    0x15555555555555UL,
    0x1ffffffffffffeUL | 1UL,
    0x10000000000000UL | 1UL,
  ]
  for left_word in words {
    for right_word in words {
      for exponent in [-3, -2, -1, 0, 1, 2, 3, 1000, -1001] {
        let left = Binary::make_coeff(
          Coeff::from_uint64(left_word),
          exponent,
          53,
        )
        let right = Binary::make_coeff(
          Coeff::from_uint64(right_word),
          exponent / 2,
          53,
          negative=true,
        )
        let quotient = binary_fast_div(left, right).unwrap()
        assert_true(
          fast_test_same(
            quotient,
            left.div_ctx(right, BinaryContext::new(precision=53)).0,
          ),
        )
        assert_true(
          fast_test_same(quotient, binary_fast_div_words(left, right).unwrap()),
        )
      }
    }
    for exponent in [-3, -2, -1, 0, 1, 2, 3, 1000, -1001] {
      let value = Binary::make_coeff(
        Coeff::from_uint64(left_word),
        exponent,
        53,
      )
      assert_true(
        fast_test_same(
          binary_fast_sqrt(value).unwrap(),
          sqrt_for_precision(value, 53),
        ),
      )
      let square = value.mul_ctx(value, BinaryContext::new(precision=53)).0
      assert_true(
        fast_test_same(
          binary_fast_sqrt(square).unwrap(),
          sqrt_for_precision(square, 53),
        ),
      )
    }
  }
}

///|
/// The word route of `sqrt_ctx` (`binary_sqrt_ctx_words`) against the general
/// path `binary_round_sqrt` on the same coefficient and exponent: result,
/// representation and flags identical, in every rounding direction and in
/// contexts whose range puts results in the normal, subnormal and overflowing
/// ranges (where the route declines and the general path answers).
fn sqrt_words_check(
  coefficient : UInt64,
  exponent : Int32,
  context : BinaryContext,
) -> Unit raise {
  if coefficient == 0UL {
    return
  }
  let zeros = coefficient.reinterpret_as_int64().ctz()
  let odd = coefficient >> zeros
  let exponent2 = exponent + zeros
  let value = finite_from_parts(false, Coeff::from_uint64(odd), exponent2, 64)
  let actual = value.sqrt_ctx(context)
  let expected = binary_round_sqrt(Coeff::from_uint64(odd), exponent2, context)
  assert_identical_with_flags(actual, expected)
}

///|
test "sqrt_ctx on words equals the general path: edges and random, every direction and range" {
  let random = { state: 0x7A3C_91D5_E2B4_0F68UL, }
  let modes = [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
  ]
  for precision in [2, 3, 5, 8, 24, 31, 32, 33, 53, 58, 59, 60, 61] {
    for mode in modes {
      for e_max in [1, 3, 20, 1000, binary_value_e_max] {
        let context = BinaryContext::new(precision~, e_max~, rounding=mode)
        let span = 4 * e_max.to_int64().to_int() + 2 * precision + 10
        for round in 0..<40 {
          let width = 1 + random.below(64)
          let raw = (random.next() << 11) | (random.next() >> 53)
          let coefficient = if width == 64 {
            raw | 0x8000_0000_0000_0000UL
          } else {
            (raw & ((1UL << width) - 1UL)) | (1UL << (width - 1))
          }
          let top = if e_max == binary_value_e_max {
            random.below(2000) - 1000
          } else {
            -2 * (e_max + precision + 3) + random.below(span)
          }
          let exponent = top - (binary_fast_bits(coefficient) - 1)
          sqrt_words_check(coefficient, exponent, context)
          sqrt_words_check(coefficient, exponent + 1, context)
          // perfect squares, one above, the last value below the midpoint and
          // the first above it
          let root = coefficient >> 33
          if root > 0UL && round % 4 == 0 {
            let square = root * root
            for
              radicand in [
                square,
                square + 1UL,
                square + root,
                square + root + 1UL,
                if square > 1UL {
                  square - 1UL
                } else {
                  square
                },
              ] {
              let adjusted = top - (binary_fast_bits(radicand) - 1)
              sqrt_words_check(radicand, adjusted, context)
              sqrt_words_check(radicand, adjusted - 1, context)
            }
          }
        }
        // exact ties: the root of `r^2` with `r` odd of `precision + 1` bits is
        // exactly halfway between two `precision`-bit numbers
        if precision <= 31 {
          for _ in 0..<4 {
            let r = ((random.next() >> 10) & ((1UL << (precision + 1)) - 1UL)) |
              (1UL << precision) |
              1UL
            for exponent in [0, 2, -2, 4 * precision, -4 * precision] {
              sqrt_words_check(r * r, exponent, context)
            }
          }
        }
        // all ones and a single bit
        for width in [1, 2, 31, 32, 53, 63, 64] {
          let ones = if width == 64 {
            0xFFFF_FFFF_FFFF_FFFFUL
          } else {
            (1UL << width) - 1UL
          }
          for exponent in [-3 * precision, -1, 0, 1, 2 * precision] {
            sqrt_words_check(ones, exponent, context)
            sqrt_words_check(1UL << (width - 1), exponent, context)
          }
        }
      }
    }
  }
}
