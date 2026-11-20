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
  assert_true(
    binary_pair_mul(one, BinFloat::inf(Sign::Positive, precision=100)) is None,
  )
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
