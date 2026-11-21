///|
/// The addition without the sign flip of the subtraction (the production name
/// carries the flag).
fn binary_pair_add(left : BinFloat, right : BinFloat) -> BinFloat? {
  binary_pair_add_signed(left, right, false)
}

///|
/// A precision from 54 to 128, with the large values frequent.
fn fast_pair_precision(random : FastCoeffRandom) -> Int32 {
  match random.below(3) {
    0 => 128
    1 => 54 + random.below(75)
    _ => 100 + random.below(29)
  }
}

///|
test "pair add equals the general path" {
  let random = { coeff_state: 0x7F4A7C15D1UL, }
  let mut fast = 0
  for _ in 0..<60000 {
    let around = random.below(300) - 150
    let precision = fast_pair_precision(random)
    let left = fast_coeff_operand(random, around, 128, precision)
    let right = fast_coeff_operand(
      random,
      around +
      random.below(9) -
      4 -
      (if random.below(8) == 0 { random.below(130) } else { 0 }),
      128,
      precision - random.below(3) + 1,
    )
    let general = left.add_ctx(
        right,
        BinaryContext::new(precision=max_precision(left, right)),
      ).0
    match binary_pair_add(left, right) {
      Some(result) => {
        fast += 1
        assert_true(fast_test_same(result, general))
      }
      None => ()
    }
    assert_true(fast_test_same(left.add(right), general))
  }
  assert_true(fast > 30000)
}

///|
test "pair add of near-equal and cancelling values" {
  let random = { coeff_state: 0x1234ABCD99UL, }
  let mut fast = 0
  for _ in 0..<40000 {
    let precision = fast_pair_precision(random)
    let left = fast_coeff_operand(random, 0, 128, precision)
    let delta = BinFloat::make_coeff(
      fast_coeff_value(random, 1 + random.below(40)),
      left.exponent2() + random.below(20) - 10,
      precision,
      negative=left.is_negative(),
    )
    let right = if random.below(3) == 0 {
      left.neg()
    } else {
      left.neg().add(delta)
    }
    let general = left.add_ctx(
        right,
        BinaryContext::new(precision=max_precision(left, right)),
      ).0
    match binary_pair_add(left, right) {
      Some(result) => {
        fast += 1
        assert_true(fast_test_same(result, general))
      }
      None => ()
    }
    assert_true(fast_test_same(left.add(right), general))
  }
  assert_true(fast > 8000)
}

///|
test "pair add and mul at every alignment of all-ones operands" {
  // all-ones coefficients round up to a power of two at the full precision
  let ones = Coeff::one().shift_left(128).sub_checked(Coeff::one()).unwrap()
  let mut adds = 0
  let mut muls = 0
  for width in [1, 2, 63, 64, 65, 100, 127, 128] {
    let coefficient = Coeff::one()
      .shift_left(width)
      .sub_checked(Coeff::one())
      .unwrap()
    for precision in [53, 64, 65, 127, 128] {
      for shift in 0..<135 {
        for negative in [false, true] {
          let left = BinFloat::make_coeff(coefficient, 0, 128)
          let right = BinFloat::make_coeff(ones, -shift, 128, negative~)
          let tight = BinFloat::make_coeff(coefficient, shift, precision)
          for
            pair in [
              (left, right),
              (right, left),
              (left, tight),
              (tight, right),
            ] {
            let (a, b) = pair
            let sum = a.add_ctx(
                b,
                BinaryContext::new(precision=max_precision(a, b)),
              ).0
            match binary_pair_add(a, b) {
              Some(result) => {
                adds += 1
                assert_true(fast_test_same(result, sum))
              }
              None => ()
            }
            let product = a.mul_ctx(
                b,
                BinaryContext::new(precision=max_precision(a, b)),
              ).0
            match binary_pair_mul(a, b) {
              Some(result) => {
                muls += 1
                assert_true(fast_test_same(result, product))
              }
              None => ()
            }
          }
        }
      }
    }
  }
  assert_true(adds > 10000)
  assert_true(muls > 10000)
}

///|
test "pair mul equals the general path" {
  let random = { coeff_state: 0x2545F4914F6CDD1DUL, }
  let mut fast = 0
  for _ in 0..<60000 {
    let precision = fast_pair_precision(random)
    let left = fast_coeff_operand(
      random,
      random.below(400) - 200,
      128,
      precision,
    )
    let right = fast_coeff_operand(
      random,
      random.below(400) - 200,
      128,
      precision - random.below(3) + 1,
    )
    let general = left.mul_ctx(
        right,
        BinaryContext::new(precision=max_precision(left, right)),
      ).0
    match binary_pair_mul(left, right) {
      Some(result) => {
        fast += 1
        assert_true(fast_test_same(result, general))
      }
      None => ()
    }
    assert_true(fast_test_same(left.mul(right), general))
  }
  assert_true(fast > 50000)
}

///|
test "pair paths decline what they do not cover" {
  let one = BinFloat::from_int(1, precision=100)
  let wide = BinFloat::make_coeff(
    Coeff::one().shift_left(150).add(Coeff::one()),
    0,
    200,
  )
  let narrow = BinFloat::make_coeff(
    Coeff::one().shift_left(100).add(Coeff::one()),
    0,
    128,
  )
  assert_true(binary_pair_add(one, BinFloat::zero(precision=100)) is None)
  assert_true(binary_pair_add(one, BinFloat::nan(precision=100)) is None)
  assert_true(binary_pair_mul(one, BinFloat::inf(precision=100)) is None)
  assert_true(binary_pair_add(wide, one) is None)
  assert_true(binary_pair_mul(wide, one) is None)
  assert_true(binary_pair_add(narrow, narrow.neg()) is None)
  let far = BinFloat::make_coeff(Coeff::one(), 100000, 100)
  assert_true(binary_pair_add(narrow, far) is None)
  let huge = BinFloat::make_coeff(
    Coeff::one().shift_left(120).add(Coeff::one()),
    binary_implementation_e_max - 200,
    128,
  )
  assert_true(binary_pair_mul(huge, huge) is None)
}

///|
test "pair div equals the general path" {
  let random = { coeff_state: 0x5EED0D1FUL, }
  let mut fast = 0
  for _ in 0..<400000 {
    let around = random.below(300) - 150
    let precision = fast_pair_precision(random)
    let left = fast_coeff_operand(random, around, 128, precision)
    let right = fast_coeff_operand(
      random,
      around + random.below(9) - 4,
      128,
      precision - random.below(3) + 1,
    )
    let general = left.div_ctx(
        right,
        BinaryContext::new(precision=max_precision(left, right)),
      ).0
    match binary_pair_div(left, right) {
      Some(result) => {
        fast += 1
        assert_true(fast_test_same(result, general))
      }
      None => ()
    }
    assert_true(fast_test_same(left.div(right), general))
  }
  assert_true(fast > 300000)
}

///|
test "pair div at boundary operands: exact quotients, all ones, tiny divisors, estimates at the top digit" {
  let ones = Coeff::one().shift_left(128).sub_checked(Coeff::one()).unwrap()
  let mut done = 0
  let divisor_values = [
    Coeff::one(),
    Coeff::from_uint64(3UL),
    Coeff::from_uint64(0xffff_ffff_ffff_ffffUL),
    Coeff::one().shift_left(64).add(Coeff::one()),
    Coeff::one().shift_left(127).add(Coeff::one()),
    Coeff::one()
    .shift_left(127)
    .add(Coeff::from_uint64(0xffff_ffff_ffff_ffffUL)),
    ones,
    ones.sub_checked(Coeff::from_uint64(2UL)).unwrap(),
  ]
  for precision in [54, 61, 64, 65, 100, 127, 128] {
    for divisor in divisor_values {
      let dividends = [
        Coeff::one(),
        Coeff::from_uint64(0xffff_ffff_ffff_ffffUL),
        Coeff::one().shift_left(127).add(Coeff::one()),
        ones,
        divisor,
        divisor.add(Coeff::from_uint64(2UL)),
      ]
      for multiplier in [3UL, 0xffff_ffff_ffff_fffbUL] {
        let product = divisor.mul(Coeff::from_uint64(multiplier))
        if product.bit_length() <= 128 {
          dividends.push(product)
          dividends.push(product.add(Coeff::from_uint64(2UL)))
        }
      }
      for dividend in dividends {
        for exponent in [-70, -1, 0, 5, 131] {
          for negative in [false, true] {
            let left = BinFloat::make_coeff(
              dividend,
              exponent,
              precision,
              negative~,
            )
            let right = BinFloat::make_coeff(divisor, 3, precision)
            if left.is_zero() || right.is_zero() {
              continue
            }
            let general = left.div_ctx(
                right,
                BinaryContext::new(precision=max_precision(left, right)),
              ).0
            match binary_pair_div(left, right) {
              Some(result) => {
                done += 1
                assert_true(fast_test_same(result, general))
              }
              None => ()
            }
            assert_true(fast_test_same(left.div(right), general))
          }
        }
      }
    }
  }
  assert_true(done > 3000)
}

///|
/// `binary_pair_add` as it was before the two-word alignment (six calls of
/// `binary_pair_shl_word`), kept as the reference of the tests.
fn binary_pair_add_reference(left : BinFloat, right : BinFloat) -> BinFloat? {
  let precision = Int32::max(left.precision_(), right.precision_())
  guard precision <= binary_pair_precision_limit else { return None }
  guard binary_pair_is_words(left) && binary_pair_is_words(right) else {
    return None
  }
  let left_high = binary_pair_high_of(left)
  let left_low = binary_pair_low_of(left)
  let right_high = binary_pair_high_of(right)
  let right_low = binary_pair_low_of(right)
  let left_exponent = left.exponent2_()
  let right_exponent = right.exponent2_()
  guard left_exponent <= binary_fast_exponent_limit &&
    left_exponent >= -binary_fast_exponent_limit &&
    right_exponent <= binary_fast_exponent_limit &&
    right_exponent >= -binary_fast_exponent_limit else {
    return None
  }
  let left_bits = if left_high != 0UL {
    64 + binary_fast_bits(left_high)
  } else {
    binary_fast_bits(left_low)
  }
  let right_bits = if right_high != 0UL {
    64 + binary_fast_bits(right_high)
  } else {
    binary_fast_bits(right_low)
  }
  let gap = (left_exponent + left_bits - right_exponent - right_bits).to_int64()
  let far = (precision + 3).to_int64()
  guard gap <= far && gap >= -far else { return None }
  let target = Int32::min(left_exponent, right_exponent)
  let left_shift = left_exponent - target
  let right_shift = right_exponent - target
  // both aligned operands fit 191 bits, so the sum fits three words
  guard left_bits + left_shift <= 191 && right_bits + right_shift <= 191 else {
    return None
  }
  let left2 = binary_pair_shl_word(left_high, left_low, left_shift, 2)
  let left1 = binary_pair_shl_word(left_high, left_low, left_shift, 1)
  let left0 = binary_pair_shl_word(left_high, left_low, left_shift, 0)
  let right2 = binary_pair_shl_word(right_high, right_low, right_shift, 2)
  let right1 = binary_pair_shl_word(right_high, right_low, right_shift, 1)
  let right0 = binary_pair_shl_word(right_high, right_low, right_shift, 0)
  if left.negative() == right.negative() {
    let word0 = left0 + right0
    let carry0 = if word0 < left0 { 1UL } else { 0UL }
    let partial1 = left1 + right1
    let carry1a = if partial1 < left1 { 1UL } else { 0UL }
    let word1 = partial1 + carry0
    let carry1b = if word1 < partial1 { 1UL } else { 0UL }
    let word2 = left2 + right2 + carry1a + carry1b
    Some(
      binary_pair_round(
        left.negative(),
        0UL,
        word2,
        word1,
        word0,
        target,
        precision,
      ),
    )
  } else {
    let left_larger = left2 > right2 ||
      (
        left2 == right2 &&
        (left1 > right1 || (left1 == right1 && left0 > right0))
      )
    if left2 == right2 && left1 == right1 && left0 == right0 {
      return None
    }
    if left_larger {
      let word0 = left0 - right0
      let borrow0 = if left0 < right0 { 1UL } else { 0UL }
      let partial1 = left1 - right1
      let borrow1a = if left1 < right1 { 1UL } else { 0UL }
      let word1 = partial1 - borrow0
      let borrow1b = if partial1 < borrow0 { 1UL } else { 0UL }
      let word2 = left2 - right2 - borrow1a - borrow1b
      Some(
        binary_pair_round(
          left.negative(),
          0UL,
          word2,
          word1,
          word0,
          target,
          precision,
        ),
      )
    } else {
      let word0 = right0 - left0
      let borrow0 = if right0 < left0 { 1UL } else { 0UL }
      let partial1 = right1 - left1
      let borrow1a = if right1 < left1 { 1UL } else { 0UL }
      let word1 = partial1 - borrow0
      let borrow1b = if partial1 < borrow0 { 1UL } else { 0UL }
      let word2 = right2 - left2 - borrow1a - borrow1b
      Some(
        binary_pair_round(
          right.negative(),
          0UL,
          word2,
          word1,
          word0,
          target,
          precision,
        ),
      )
    }
  }
}

///|
test "pair add with the two-word alignment equals the previous pair add and the general path" {
  let random = { coeff_state: 0x2D1F00DUL, }
  let mut compared = 0
  for _ in 0..<400000 {
    let around = random.below(300) - 150
    let precision = fast_pair_precision(random)
    // exponent differences below 64 (the new branch), at 64 and above
    let spread = match random.below(5) {
      0 => 0
      1 => random.below(20)
      2 => random.below(64)
      3 => 60 + random.below(10)
      _ => random.below(130)
    }
    let left = fast_coeff_operand(random, around, 128, precision)
    let right = fast_coeff_operand(
      random,
      around + (if random.below(2) == 0 { spread } else { -spread }),
      128,
      precision - random.below(3) + 1,
    )
    let general = left.add_ctx(
        right,
        BinaryContext::new(precision=max_precision(left, right)),
      ).0
    let reference = binary_pair_add_reference(left, right)
    let actual = binary_pair_add(left, right)
    match (reference, actual) {
      (Some(old), Some(new)) => {
        compared += 1
        assert_true(fast_test_same(new, old))
        assert_true(fast_test_same(new, general))
      }
      (None, None) => ()
      _ => abort("pair add declines differently from the previous pair add")
    }
    let subtracted = left.sub(right)
    let general_sub = left.add_ctx(
        right.neg(),
        BinaryContext::new(precision=max_precision(left, right)),
      ).0
    assert_true(fast_test_same(subtracted, general_sub))
  }
  assert_true(compared > 200000)
}

///|
/// `sub` reads the sign of the right operand flipped instead of negating it
/// first: for every width (one word, two words, wider) it equals `add` of the
/// negated operand and the general path, also at cancellation and zero sums.
test "sub without a negated operand equals add of the negation and the general path" {
  let random = { coeff_state: 0x5B0B5B0BUL, }
  for _ in 0..<300000 {
    let around = random.below(200) - 100
    let precision = match random.below(4) {
      0 => 20 + random.below(40)
      1 => 54 + random.below(75)
      2 => 100 + random.below(150)
      _ => 200 + random.below(400)
    }
    let spread = random.below(40) -
      20 -
      (if random.below(8) == 0 { random.below(140) } else { 0 })
    let left = fast_coeff_operand(random, around, 640, precision)
    let right = if random.below(10) == 0 {
      left
    } else {
      fast_coeff_operand(
        random,
        around + spread,
        640,
        precision - random.below(3) + 1,
      )
    }
    let context = BinaryContext::new(precision=max_precision(left, right))
    let expected = left.add_ctx(right.neg(), context).0
    assert_true(fast_test_same(left.sub(right), expected))
    assert_true(fast_test_same(left.add(right.neg()), expected))
  }
}
