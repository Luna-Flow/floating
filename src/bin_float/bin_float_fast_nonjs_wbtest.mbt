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
fn fast_test_operand(random : FastTestRandom, around : Int32) -> BinFloat {
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
    BinFloat::zero(precision~)
  } else {
    BinFloat::make(BinCoeff::from_uint64(word), exponent, precision, negative~)
  }
}

///|
fn fast_test_same(actual : BinFloat, expected : BinFloat) -> Bool {
  actual == expected &&
  actual.precision() == expected.precision() &&
  actual.is_negative() == expected.is_negative() &&
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
        BinaryContext::unbounded(max_precision(left, right)),
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
        BinaryContext::unbounded(max_precision(left, right)),
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
        BinaryContext::unbounded(max_precision(left, right)),
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
  let one = BinFloat::from_int(1, precision=53)
  let big = BinFloat::make(
    BinCoeff::one().shift_left(100).add(BinCoeff::one()),
    0,
    128,
  )
  assert_true(binary_fast_add(one, BinFloat::zero(precision=53)) is None)
  assert_true(binary_fast_add(one, BinFloat::nan(precision=53)) is None)
  assert_true(
    binary_fast_mul(one, BinFloat::inf(Sign::Positive, precision=53)) is None,
  )
  assert_true(binary_fast_div(one, BinFloat::zero(precision=53)) is None)
  assert_true(binary_fast_add(one, big) is None)
  // an exact zero sum
  assert_true(binary_fast_add(one, one.neg()) is None)
  // exponents near the implementation limits
  let far = BinFloat::make(BinCoeff::one(), 400000000, 53)
  assert_true(binary_fast_mul(far, far) is None)
  // far apart operands use the general path
  let tiny = BinFloat::make(BinCoeff::one(), -200, 53)
  assert_true(binary_fast_add(one, tiny) is None)
  assert_true(
    fast_test_same(
      one.add(tiny),
      one.add_ctx(tiny, BinaryContext::unbounded(53)).0,
    ),
  )
}

///|
test "one-word paths handle ties, carries and cancellation" {
  // 1 + 2^-53 is a tie at 53 bits (round to even keeps 1); 1 + 3 * 2^-54 rounds up
  let one = BinFloat::from_int(1, precision=53)
  for tail in [1, 3, 5, 7] {
    let small = BinFloat::make(BinCoeff::from_uint64(tail.to_uint64()), -55, 53)
    let general = one.add_ctx(small, BinaryContext::unbounded(53)).0
    assert_true(fast_test_same(one.add(small), general))
    let general_sub = one.add_ctx(small.neg(), BinaryContext::unbounded(53)).0
    assert_true(fast_test_same(one.sub(small), general_sub))
  }
  // all ones plus one carries into a new bit
  let ones = BinFloat::make(
    BinCoeff::one().shift_left(53).sub_checked(BinCoeff::one()).unwrap(),
    0,
    53,
  )
  let general = ones.add_ctx(one, BinaryContext::unbounded(53)).0
  assert_true(fast_test_same(ones.add(one), general))
  // heavy cancellation
  let near = BinFloat::make(
    BinCoeff::one().shift_left(53).add(BinCoeff::one()),
    -53,
    54,
  )
  let general_diff = near.add_ctx(one.neg(), BinaryContext::unbounded(54)).0
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
        assert_true(fast_test_same(result, general.unwrap()))
      }
      None => ()
    }
    assert_true(fast_test_same(value.sqrt().unwrap(), general.unwrap()))
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
        let value = BinFloat::make(
          BinCoeff::from_uint64(word),
          exponent,
          precision,
        )
        let general = sqrt_for_precision(value, value.precision()).unwrap()
        assert_true(fast_test_same(value.sqrt().unwrap(), general))
        let squared = value.mul_ctx(value, BinaryContext::unbounded(precision)).0
        let general_root = sqrt_for_precision(squared, squared.precision()).unwrap()
        assert_true(fast_test_same(squared.sqrt().unwrap(), general_root))
      }
    }
  }
  assert_true(binary_fast_sqrt(BinFloat::from_int(-4, precision=53)) is None)
  assert_true(binary_fast_sqrt(BinFloat::zero(precision=53)) is None)
  assert_true(
    binary_fast_sqrt(BinFloat::inf(Sign::Positive, precision=53)) is None,
  )
}
