///|
/// The addition without the sign flip of the subtraction (the production name
/// carries the flag).
fn binary_pair_add(left : Binary, right : Binary) -> Binary? {
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
// oracle: B
// source: add_ctx general route at the larger operand precision (54 to 128 bits): a different algorithm from the route under test. The general route is itself checked against exact arithmetic on the inputs this test draws from (precisions from 2 to 8192, all five directions, ties, carries between words, borrow, cancellation, far operands, exact quotients, perfect squares) by the tests "add, mul, div and sqrt are rounded once, exactly: rows from exact arithmetic" and "add, mul, div and sqrt without a context: the ties-to-even rows" of arith_rows_check_wbtest.mbt (rows of arith_rows_wbtest.mbt from tools/generate_arith_rows.py: Python fractions and math.isqrt, library-ran: no); the exponent-range edges of binary16, binary32 and binary64 are rows there for add, mul and div.
// shares: both routes call binary_inexact_flags for the flags of an exact result and the Binary constructors (finite_normalized, bin_repr_word) to build the value, which the differential does not check and the table does through the flags and the printed value; the rounding decision is written twice, in the word, pair or limb finish of the fast route and in binary_apply_round_bits behind binary_round_dyadic / binary_round_rational / binary_round_sqrt in the general route, so it is not shared; fast_test_same compares value, precision label, sign and exponent
// primitives: Coeff::add, Coeff::sub_checked, Coeff::mul, Coeff::shift_left, binary_round_dyadic, binary_round_rational, binary_round_sqrt: level A on the same operations and widths in arith_rows_wbtest.mbt and, up to 128 bits, in the TestFloat gate
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
// oracle: B
// source: add_ctx general route on a value and its negation with a few low bits changed: a different algorithm from the route under test. The general route is itself checked against exact arithmetic on the inputs this test draws from (precisions from 2 to 8192, all five directions, ties, carries between words, borrow, cancellation, far operands, exact quotients, perfect squares) by the tests "add, mul, div and sqrt are rounded once, exactly: rows from exact arithmetic" and "add, mul, div and sqrt without a context: the ties-to-even rows" of arith_rows_check_wbtest.mbt (rows of arith_rows_wbtest.mbt from tools/generate_arith_rows.py: Python fractions and math.isqrt, library-ran: no); the exponent-range edges of binary16, binary32 and binary64 are rows there for add, mul and div.
// shares: both routes call binary_inexact_flags for the flags of an exact result and the Binary constructors (finite_normalized, bin_repr_word) to build the value, which the differential does not check and the table does through the flags and the printed value; the rounding decision is written twice, in the word, pair or limb finish of the fast route and in binary_apply_round_bits behind binary_round_dyadic / binary_round_rational / binary_round_sqrt in the general route, so it is not shared; fast_test_same compares value, precision label, sign and exponent
// primitives: Coeff::add, Coeff::sub_checked, Coeff::mul, Coeff::shift_left, binary_round_dyadic, binary_round_rational, binary_round_sqrt: level A on the same operations and widths in arith_rows_wbtest.mbt and, up to 128 bits, in the TestFloat gate
test "pair add of near-equal and cancelling values" {
  let random = { coeff_state: 0x1234ABCD99UL, }
  let mut fast = 0
  for _ in 0..<40000 {
    let precision = fast_pair_precision(random)
    let left = fast_coeff_operand(random, 0, 128, precision)
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
// oracle: B
// source: add_ctx and mul_ctx general routes at the larger operand precision, all-ones coefficients of 1 to 128 bits at every alignment from 0 to 134: a different algorithm from the route under test. The general route is itself checked against exact arithmetic on the inputs this test draws from (precisions from 2 to 8192, all five directions, ties, carries between words, borrow, cancellation, far operands, exact quotients, perfect squares) by the tests "add, mul, div and sqrt are rounded once, exactly: rows from exact arithmetic" and "add, mul, div and sqrt without a context: the ties-to-even rows" of arith_rows_check_wbtest.mbt (rows of arith_rows_wbtest.mbt from tools/generate_arith_rows.py: Python fractions and math.isqrt, library-ran: no); the exponent-range edges of binary16, binary32 and binary64 are rows there for add, mul and div.
// shares: both routes call binary_inexact_flags for the flags of an exact result and the Binary constructors (finite_normalized, bin_repr_word) to build the value, which the differential does not check and the table does through the flags and the printed value; the rounding decision is written twice, in the word, pair or limb finish of the fast route and in binary_apply_round_bits behind binary_round_dyadic / binary_round_rational / binary_round_sqrt in the general route, so it is not shared; fast_test_same compares value, precision label, sign and exponent
// primitives: Coeff::add, Coeff::sub_checked, Coeff::mul, Coeff::shift_left, binary_round_dyadic, binary_round_rational, binary_round_sqrt: level A on the same operations and widths in arith_rows_wbtest.mbt and, up to 128 bits, in the TestFloat gate
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
          let left = Binary::make_coeff(coefficient, 0, 128)
          let right = Binary::make_coeff(ones, -shift, 128, negative~)
          let tight = Binary::make_coeff(coefficient, shift, precision)
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
// oracle: B
// source: mul_ctx general route at the larger operand precision: a different algorithm from the route under test. The general route is itself checked against exact arithmetic on the inputs this test draws from (precisions from 2 to 8192, all five directions, ties, carries between words, borrow, cancellation, far operands, exact quotients, perfect squares) by the tests "add, mul, div and sqrt are rounded once, exactly: rows from exact arithmetic" and "add, mul, div and sqrt without a context: the ties-to-even rows" of arith_rows_check_wbtest.mbt (rows of arith_rows_wbtest.mbt from tools/generate_arith_rows.py: Python fractions and math.isqrt, library-ran: no); the exponent-range edges of binary16, binary32 and binary64 are rows there for add, mul and div.
// shares: both routes call binary_inexact_flags for the flags of an exact result and the Binary constructors (finite_normalized, bin_repr_word) to build the value, which the differential does not check and the table does through the flags and the printed value; the rounding decision is written twice, in the word, pair or limb finish of the fast route and in binary_apply_round_bits behind binary_round_dyadic / binary_round_rational / binary_round_sqrt in the general route, so it is not shared; fast_test_same compares value, precision label, sign and exponent
// primitives: Coeff::add, Coeff::sub_checked, Coeff::mul, Coeff::shift_left, binary_round_dyadic, binary_round_rational, binary_round_sqrt: level A on the same operations and widths in arith_rows_wbtest.mbt and, up to 128 bits, in the TestFloat gate
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
// oracle: A
// source: every declined case is written out (is None) from the entry guards of the pair routes: zero, NaN, infinity, wide operands, exact cancellation, far operands, exponents near the implementation limits
// shares: nothing
test "pair paths decline what they do not cover" {
  let one = Binary::from_int(1, precision=100)
  let wide = Binary::make_coeff(
    Coeff::one().shift_left(150).add(Coeff::one()),
    0,
    200,
  )
  let narrow = Binary::make_coeff(
    Coeff::one().shift_left(100).add(Coeff::one()),
    0,
    128,
  )
  assert_true(binary_pair_add(one, Binary::zero(precision=100)) is None)
  assert_true(binary_pair_add(one, Binary::nan(precision=100)) is None)
  assert_true(binary_pair_mul(one, Binary::inf(precision=100)) is None)
  assert_true(binary_pair_add(wide, one) is None)
  assert_true(binary_pair_mul(wide, one) is None)
  assert_true(binary_pair_add(narrow, narrow.neg()) is None)
  let far = Binary::make_coeff(Coeff::one(), 100000, 100)
  assert_true(binary_pair_add(narrow, far) is None)
  let huge = Binary::make_coeff(
    Coeff::one().shift_left(120).add(Coeff::one()),
    binary_value_e_max - 200,
    128,
  )
  assert_true(binary_pair_mul(huge, huge) is None)
}

///|
// oracle: B
// source: div_ctx general route at the larger operand precision: a different algorithm from the route under test. The general route is itself checked against exact arithmetic on the inputs this test draws from (precisions from 2 to 8192, all five directions, ties, carries between words, borrow, cancellation, far operands, exact quotients, perfect squares) by the tests "add, mul, div and sqrt are rounded once, exactly: rows from exact arithmetic" and "add, mul, div and sqrt without a context: the ties-to-even rows" of arith_rows_check_wbtest.mbt (rows of arith_rows_wbtest.mbt from tools/generate_arith_rows.py: Python fractions and math.isqrt, library-ran: no); the exponent-range edges of binary16, binary32 and binary64 are rows there for add, mul and div.
// shares: both routes call binary_inexact_flags for the flags of an exact result and the Binary constructors (finite_normalized, bin_repr_word) to build the value, which the differential does not check and the table does through the flags and the printed value; the rounding decision is written twice, in the word, pair or limb finish of the fast route and in binary_apply_round_bits behind binary_round_dyadic / binary_round_rational / binary_round_sqrt in the general route, so it is not shared; fast_test_same compares value, precision label, sign and exponent
// primitives: Coeff::add, Coeff::sub_checked, Coeff::mul, Coeff::shift_left, binary_round_dyadic, binary_round_rational, binary_round_sqrt: level A on the same operations and widths in arith_rows_wbtest.mbt and, up to 128 bits, in the TestFloat gate
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
// oracle: B
// source: div_ctx general route on exact quotients, all ones, tiny divisors and quotient estimates at the top digit: a different algorithm from the route under test. The general route is itself checked against exact arithmetic on the inputs this test draws from (precisions from 2 to 8192, all five directions, ties, carries between words, borrow, cancellation, far operands, exact quotients, perfect squares) by the tests "add, mul, div and sqrt are rounded once, exactly: rows from exact arithmetic" and "add, mul, div and sqrt without a context: the ties-to-even rows" of arith_rows_check_wbtest.mbt (rows of arith_rows_wbtest.mbt from tools/generate_arith_rows.py: Python fractions and math.isqrt, library-ran: no); the exponent-range edges of binary16, binary32 and binary64 are rows there for add, mul and div.
// shares: both routes call binary_inexact_flags for the flags of an exact result and the Binary constructors (finite_normalized, bin_repr_word) to build the value, which the differential does not check and the table does through the flags and the printed value; the rounding decision is written twice, in the word, pair or limb finish of the fast route and in binary_apply_round_bits behind binary_round_dyadic / binary_round_rational / binary_round_sqrt in the general route, so it is not shared; fast_test_same compares value, precision label, sign and exponent
// primitives: Coeff::add, Coeff::sub_checked, Coeff::mul, Coeff::shift_left, binary_round_dyadic, binary_round_rational, binary_round_sqrt: level A on the same operations and widths in arith_rows_wbtest.mbt and, up to 128 bits, in the TestFloat gate
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
            let left = Binary::make_coeff(
              dividend,
              exponent,
              precision,
              negative~,
            )
            let right = Binary::make_coeff(divisor, 3, precision)
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
fn binary_pair_add_reference(left : Binary, right : Binary) -> Binary? {
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
// oracle: B, E
// source: add_ctx general route (B), and binary_pair_add_reference, the pair add before the two-word alignment kept in the test (E)
// shares: Coeff arithmetic and binary_round_dyadic; the reference shares the word helpers of the production pair add (binary_pair_shl_word is not used by the new code)
// primitives: Coeff::add, binary_round_dyadic: level A on add at these widths in arith_rows_wbtest.mbt
// underneath: the previous pair add equals the general route in the same test (B); both are checked against exact arithmetic on the same widths by arith_rows_wbtest.mbt (A)
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
// oracle: B
// source: add_ctx of the negated operand at the same context (the general route), for one word, two words and wider operands, at cancellation and for zero sums: a different algorithm from the route under test. The general route is itself checked against exact arithmetic on the inputs this test draws from (precisions from 2 to 8192, all five directions, ties, carries between words, borrow, cancellation, far operands, exact quotients, perfect squares) by the tests "add, mul, div and sqrt are rounded once, exactly: rows from exact arithmetic" and "add, mul, div and sqrt without a context: the ties-to-even rows" of arith_rows_check_wbtest.mbt (rows of arith_rows_wbtest.mbt from tools/generate_arith_rows.py: Python fractions and math.isqrt, library-ran: no); the exponent-range edges of binary16, binary32 and binary64 are rows there for add, mul and div.
// shares: both routes call binary_inexact_flags for the flags of an exact result and the Binary constructors (finite_normalized, bin_repr_word) to build the value, which the differential does not check and the table does through the flags and the printed value; the rounding decision is written twice, in the word, pair or limb finish of the fast route and in binary_apply_round_bits behind binary_round_dyadic / binary_round_rational / binary_round_sqrt in the general route, so it is not shared; fast_test_same compares value, precision label, sign and exponent
// primitives: Coeff::add, Coeff::sub_checked, Coeff::mul, Coeff::shift_left, binary_round_dyadic, binary_round_rational, binary_round_sqrt: level A on the same operations and widths in arith_rows_wbtest.mbt and, up to 128 bits, in the TestFloat gate
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
