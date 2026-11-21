///|
/// The addition without the sign flip of the subtraction (the production name
/// carries the flag).
fn binary_coeff_fast_add(left : Binary, right : Binary) -> Binary? {
  binary_coeff_fast_add_signed(left, right, false)
}

///|
struct FastCoeffRandom {
  mut coeff_state : UInt64
}

///|
fn FastCoeffRandom::next(self : FastCoeffRandom) -> UInt64 {
  self.coeff_state = self.coeff_state * 6364136223846793005UL +
    1442695040888963407UL
  self.coeff_state >> 11
}

///|
fn FastCoeffRandom::below(self : FastCoeffRandom, limit : Int32) -> Int32 {
  (self.next() % limit.to_uint64()).to_int()
}

///|
/// A coefficient of exactly `width` bits (`width >= 1`): random, sparse (the
/// top bit with a few set bits), or all ones, so ties, carries, cancellation
/// and exact results occur.
fn fast_coeff_value(random : FastCoeffRandom, width : Int32) -> Coeff {
  if width == 1 {
    return Coeff::one()
  }
  let top = Coeff::one().shift_left(width - 1)
  let mut body = Coeff::zero()
  match random.below(5) {
    0 =>
      for _ in 0..<random.below(3) {
        body = body.add(Coeff::one().shift_left(random.below(width - 1)))
      }
    1 => body = top.sub_checked(Coeff::one()).unwrap()
    _ =>
      for _ in 0..<(width / 64 + 1) {
        body = body
          .shift_left(64)
          .add(
            Coeff::from_uint64(
              (random.next() << 13) | (random.next() & 0x1fffUL),
            ),
          )
      }
  }
  // keep the low `width - 1` bits of `body`, then set the top bit
  let excess = body.bit_length() - (width - 1)
  let kept = if excess > 0 {
    body.shift_right(excess).add(Coeff::zero())
  } else {
    body
  }
  top.add(kept)
}

///|
fn fast_coeff_operand(
  random : FastCoeffRandom,
  around : Int32,
  max_width : Int32,
  precision : Int32,
) -> Binary {
  let width = match random.below(4) {
    0 => 1 + random.below(Int32::min(8, max_width))
    1 => 1 + random.below(Int32::min(precision + 4, max_width))
    _ => 1 + random.below(max_width)
  }
  let exponent = around + random.below(9) - 4
  let negative = random.below(2) == 0
  Binary::make_coeff(
    fast_coeff_value(random, width),
    exponent,
    precision,
    negative~,
  )
}

///|
fn fast_coeff_precision(random : FastCoeffRandom) -> Int32 {
  match random.below(4) {
    0 => 53 + random.below(80)
    1 => 2 + random.below(300)
    2 => 100 + random.below(40)
    _ => 400 + random.below(200)
  }
}

///|
test "coefficient add equals the general path" {
  let random = { coeff_state: 0x5DEECE66D1UL, }
  let mut fast = 0
  for _ in 0..<30000 {
    let around = random.below(400) - 200
    let precision = fast_coeff_precision(random)
    let left = fast_coeff_operand(random, around, 700, precision)
    let right = fast_coeff_operand(
      random,
      around + random.below(9) - 4,
      700,
      precision - random.below(3) + 1,
    )
    let general = left.add_ctx(
        right,
        BinaryContext::new(precision=max_precision(left, right)),
      ).0
    match binary_coeff_fast_add(left, right) {
      Some(result) => {
        fast += 1
        assert_true(fast_test_same(result, general))
      }
      None => ()
    }
    assert_true(fast_test_same(left.add(right), general))
  }
  assert_true(fast > 15000)
}

///|
test "coefficient add of very wide operands equals the general path" {
  let random = { coeff_state: 0x7777AAAA11UL, }
  let mut fast = 0
  for _ in 0..<1500 {
    let around = random.below(400) - 200
    let precision = 1000 + random.below(1000)
    let left = fast_coeff_operand(random, around, 3200, precision)
    let right = fast_coeff_operand(
      random,
      around + random.below(9) - 4,
      3200,
      precision,
    )
    let general = left.add_ctx(
        right,
        BinaryContext::new(precision=max_precision(left, right)),
      ).0
    match binary_coeff_fast_add(left, right) {
      Some(result) => {
        fast += 1
        assert_true(fast_test_same(result, general))
      }
      None => ()
    }
  }
  assert_true(fast > 600)
}

///|
test "coefficient add of near-equal and cancelling values" {
  let random = { coeff_state: 0x1234ABCDUL, }
  let mut fast = 0
  for _ in 0..<20000 {
    let precision = fast_coeff_precision(random)
    let left = fast_coeff_operand(random, 0, 300, precision)
    // the negated value with a few low bits changed
    let delta = Binary::make_coeff(
      fast_coeff_value(random, 1 + random.below(40)),
      left.exponent2() + random.below(20) - 10,
      precision,
      negative=left.is_sign_minus(),
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
    match binary_coeff_fast_add(left, right) {
      Some(result) => {
        fast += 1
        assert_true(fast_test_same(result, general))
      }
      None => ()
    }
    assert_true(fast_test_same(left.add(right), general))
  }
  assert_true(fast > 5000)
}

///|
test "coefficient mul equals the general path" {
  let random = { coeff_state: 0x2545F4914F6CDD1DUL, }
  let mut fast = 0
  for _ in 0..<30000 {
    let precision = fast_coeff_precision(random)
    let left = fast_coeff_operand(
      random,
      random.below(400) - 200,
      700,
      precision,
    )
    let right = fast_coeff_operand(
      random,
      random.below(400) - 200,
      700,
      precision - random.below(3) + 1,
    )
    let general = left.mul_ctx(
        right,
        BinaryContext::new(precision=max_precision(left, right)),
      ).0
    match binary_coeff_fast_mul(left, right) {
      Some(result) => {
        fast += 1
        assert_true(fast_test_same(result, general))
      }
      None => ()
    }
    assert_true(fast_test_same(left.mul(right), general))
  }
  assert_true(fast > 25000)
}

///|
test "coefficient div equals the general path" {
  let random = { coeff_state: 0x9E3779B97F4A7C15UL, }
  let mut fast = 0
  let mut exact = 0
  for index in 0..<30000 {
    let precision = fast_coeff_precision(random)
    let right = fast_coeff_operand(
      random,
      random.below(400) - 200,
      700,
      precision - random.below(3) + 1,
    )
    // every third dividend is `right * factor`, so the quotient is exact
    let left = if index % 3 == 0 {
      let factor = fast_coeff_operand(
        random,
        random.below(40) - 20,
        1 + random.below(300),
        precision,
      )
      right.mul_ctx(factor, BinaryContext::new(precision=2000)).0
    } else {
      fast_coeff_operand(random, random.below(400) - 200, 700, precision)
    }
    let general = left.div_ctx(
        right,
        BinaryContext::new(precision=max_precision(left, right)),
      ).0
    match binary_coeff_fast_div(left, right) {
      Some(result) => {
        fast += 1
        if index % 3 == 0 {
          exact += 1
        }
        assert_true(fast_test_same(result, general))
      }
      None => ()
    }
    assert_true(fast_test_same(left.div(right), general))
  }
  assert_true(fast > 25000)
  assert_true(exact > 5000)
}

///|
test "coefficient sqrt equals the general path" {
  let random = { coeff_state: 0xC0FFEE123UL, }
  let mut fast = 0
  let mut squares = 0
  for index in 0..<20000 {
    let precision = fast_coeff_precision(random)
    let base = fast_coeff_operand(
      random,
      random.below(300) - 150,
      1 + random.below(300),
      precision,
    )
    // every third radicand is an exact square
    let value = if index % 3 == 0 {
      let square = base.mul_ctx(base, BinaryContext::new(precision=2000)).0
      Binary::make_coeff(
        square.coefficient_(),
        square.exponent2_(),
        precision,
        negative=false,
      )
    } else {
      base.abs()
    }
    let general = sqrt_for_precision(value, value.precision())
    match binary_coeff_fast_sqrt(value) {
      Some(result) => {
        fast += 1
        if index % 3 == 0 {
          squares += 1
        }
        assert_true(fast_test_same(result, general))
      }
      None => ()
    }
    assert_true(fast_test_same(value.sqrt(), general))
  }
  assert_true(fast > 15000)
  assert_true(squares > 3000)
}

///|
test "coefficient finish equals binary_round_dyadic" {
  let random = { coeff_state: 0xABCDEF01UL, }
  for _ in 0..<30000 {
    let precision = 1 + random.below(300)
    let magnitude = fast_coeff_value(random, 1 + random.below(700)).shift_left(
      random.below(70),
    )
    let exponent = random.below(2000) - 1000
    let negative = random.below(2) == 0
    let expected = binary_round_dyadic(
        negative,
        magnitude,
        exponent,
        BinaryContext::new(precision~),
      ).0
    let actual = binary_coeff_fast_finish(
      negative, magnitude, exponent, precision, false,
    )
    assert_true(fast_test_same(actual, expected))
  }
}

///|
test "coefficient paths decline what they do not cover" {
  let one = Binary::from_int(1, precision=100)
  let wide = Binary::make_coeff(
    Coeff::one().shift_left(150).add(Coeff::one()),
    0,
    200,
  )
  assert_true(binary_coeff_fast_add(one, Binary::zero(precision=100)) is None)
  assert_true(binary_coeff_fast_add(one, Binary::nan(precision=100)) is None)
  assert_true(binary_coeff_fast_mul(one, Binary::inf(precision=100)) is None)
  assert_true(binary_coeff_fast_div(one, Binary::zero(precision=100)) is None)
  assert_true(binary_coeff_fast_div(Binary::zero(precision=100), one) is None)
  assert_true(binary_coeff_fast_sqrt(one.neg()) is None)
  assert_true(binary_coeff_fast_sqrt(Binary::zero(precision=100)) is None)
  // exact cancellation is left to the general path
  assert_true(binary_coeff_fast_add(wide, wide.neg()) is None)
  // operands whose exponents are far apart are added through a sticky bit
  let far = Binary::make_coeff(Coeff::one(), 100000, 100)
  match binary_coeff_fast_add(wide, far) {
    Some(sum) =>
      assert_true(
        fast_test_same(
          sum,
          wide.add_ctx(far, BinaryContext::new(precision=200)).0,
        ),
      )
    None => abort("far operands are added by the coefficient path")
  }
  // exponents near the implementation limits
  let huge = Binary::make_coeff(
    Coeff::one().shift_left(120).add(Coeff::one()),
    binary_value_e_max - 200,
    128,
  )
  assert_true(binary_coeff_fast_mul(huge, huge) is None)
}

///|
/// Operands that are hard for the short division: exact quotients (`A = T * B`),
/// their neighbours, all-ones and `2^k + 1` divisors, and every precision from a
/// word boundary to a few bits above it. `binary_coeff_fast_div` and the plain
/// `div` must equal `div_ctx` in the unbounded nearest-even context.
test "coefficient div equals the general path on exact quotients, neighbours and hard divisors" {
  let mut checked = 0
  for limbs in [2, 3, 4, 8, 9, 17, 32, 33, 64, 100, 128] {
    let divisors = [
      Coeff::one().shift_left(limbs * 64).sub_checked(Coeff::one()).unwrap(),
      Coeff::one().shift_left(limbs * 64 - 1).add(Coeff::one()),
      Coeff::one()
      .shift_left(limbs * 64 - 1)
      .add(Coeff::one().shift_left(64))
      .add(Coeff::one()),
      fast_coeff_value(
        { coeff_state: 77UL + limbs.to_uint64(), },
        limbs * 64 - 5,
      ),
    ]
    for divisor in divisors {
      for
        precision in [
          limbs * 64 - 1,
          limbs * 64,
          limbs * 64 + 1,
          limbs * 64 + 40,
        ] {
        for multiplier_bits in [1, 2, 3, 40] {
          let multiplier = fast_coeff_value(
            { coeff_state: 5UL + multiplier_bits.to_uint64(), },
            multiplier_bits,
          )
          let product = multiplier.mul(divisor)
          if product.bit_length() > precision {
            continue
          }
          for delta in [-3, -1, 0, 1, 2] {
            let dividend = if delta == 0 {
              product
            } else if delta > 0 {
              product.add(Coeff::from_uint64(delta.to_uint64()))
            } else {
              product
              .sub_checked(Coeff::from_uint64((-delta).to_uint64()))
              .unwrap()
            }
            for exponent in [-40, 0, 7] {
              let left = Binary::make_coeff(dividend, exponent, precision)
              let right = Binary::make_coeff(
                divisor,
                3,
                precision,
                negative=true,
              )
              if left.is_zero() || right.is_zero() {
                continue
              }
              let general = left.div_ctx(
                  right,
                  BinaryContext::new(precision=max_precision(left, right)),
                ).0
              match binary_coeff_fast_div(left, right) {
                Some(result) => {
                  checked += 1
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
  }
  assert_true(checked > 1000)
}

///|
/// Products next to rounding boundaries through the short product: powers of
/// two plus or minus small numbers (`(2^k + 1) (2^k - 1)`), all ones, a top
/// limb just above half, at precisions around the limb boundaries.
/// `binary_coeff_fast_mul` and the plain `mul` must equal `mul_ctx`.
test "coefficient mul equals the general path on structured and random operands" {
  let mut checked = 0
  for limbs in [3, 4, 5, 8, 9, 17, 32, 33, 63, 64] {
    for precision_offset in [0, -1, -63] {
      let precision = limbs * 64 + precision_offset
      let power = Coeff::one().shift_left(precision - 1)
      let ones = Coeff::one()
        .shift_left(precision)
        .sub_checked(Coeff::one())
        .unwrap()
      let operands = [
        power.add(Coeff::one()),
        power.sub_checked(Coeff::one()).unwrap().add(Coeff::one()),
        ones,
        ones.sub_checked(Coeff::from_uint64(2UL)).unwrap(),
        power.add(Coeff::one().shift_left(64)).add(Coeff::one()),
        power.add(power.shift_right(1)).add(Coeff::one()),
        Coeff::one().shift_left(precision / 2).add(Coeff::one()),
        fast_coeff_value({ coeff_state: 31UL + limbs.to_uint64(), }, precision),
        fast_coeff_value(
          { coeff_state: 99UL + limbs.to_uint64(), },
          precision - 17,
        ),
      ]
      for left_coefficient in operands {
        for right_coefficient in operands {
          if left_coefficient.bit_length() > precision ||
            right_coefficient.bit_length() > precision {
            continue
          }
          for exponent in [-100, 0, 9] {
            let left = Binary::make_coeff(left_coefficient, exponent, precision)
            let right = Binary::make_coeff(
              right_coefficient,
              exponent / 2,
              precision,
              negative=true,
            )
            if left.is_zero() || right.is_zero() {
              continue
            }
            let general = left.mul_ctx(
                right,
                BinaryContext::new(precision=max_precision(left, right)),
              ).0
            match binary_coeff_fast_mul(left, right) {
              Some(result) => {
                checked += 1
                assert_true(fast_test_same(result, general))
              }
              None => ()
            }
            assert_true(fast_test_same(left.mul(right), general))
          }
        }
      }
    }
  }
  assert_true(checked > 2000)
}
