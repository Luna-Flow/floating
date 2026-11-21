///|
/// Reference: the multi-limb add of 0.11 (before the aligned pass), kept
/// verbatim except for the names.

///|
/// Word `index` of `words << shift` (`words` has `len` words).
fn ref_aligned_word(
  words : FixedArray[UInt64],
  len : Int32,
  shift : Int32,
  index : Int32,
) -> UInt64 {
  let source = index - shift / 64
  if source < 0 || source > len {
    return 0UL
  }
  let bit_shift = shift % 64
  let word = if source < len { words.unsafe_get(source) } else { 0UL }
  if bit_shift == 0 {
    word
  } else if source == 0 {
    word << bit_shift
  } else {
    (word << bit_shift) | (words.unsafe_get(source - 1) >> (64 - bit_shift))
  }
}

///|
/// Sums wider than this many words are added with whole-coefficient
/// operations (bulk shifts and one addition), which beat the word loops
/// there.
let ref_add_words_limit : Int32 = 24

///|
fn ref_add_wide(
  left : Binary,
  right : Binary,
  target : Int32,
  left_shift : Int32,
  right_shift : Int32,
  precision : Int32,
) -> Binary? {
  let aligned_left = left.coefficient_().shift_left(left_shift)
  let aligned_right = right.coefficient_().shift_left(right_shift)
  if left.negative() == right.negative() {
    return Some(
      ref_finish(
        left.negative(),
        aligned_left.add(aligned_right),
        target,
        precision,
        false,
      ),
    )
  }
  let comparison = aligned_left.compare(aligned_right)
  if comparison == 0 {
    None
  } else if comparison > 0 {
    Some(
      ref_finish(
        left.negative(),
        aligned_left.sub_checked(aligned_right).unwrap(),
        target,
        precision,
        false,
      ),
    )
  } else {
    Some(
      ref_finish(
        right.negative(),
        aligned_right.sub_checked(aligned_left).unwrap(),
        target,
        precision,
        false,
      ),
    )
  }
}

///|
/// Whether both operands are finite, nonzero, narrow enough, and have exponents
/// far from the implementation limits (the reference of the scalar test of
/// `binary_coeff_fast_scalars_ok`).
fn binary_coeff_fast_operands_ok(left : Binary, right : Binary) -> Bool {
  left.class() == FpClass::Finite &&
  right.class() == FpClass::Finite &&
  binary_coeff_fast_scalars_ok(
    Int32::max(left.precision_(), right.precision_()),
    left.exponent2_(),
    right.exponent2_(),
  ) &&
  !left.coefficient_is_zero() &&
  !right.coefficient_is_zero()
}

///|
fn ref_add(left : Binary, right : Binary) -> Binary? {
  guard binary_coeff_fast_operands_ok(left, right) else { return None }
  let precision = Int32::max(left.precision_(), right.precision_())
  let left_bits = left.coefficient_bits()
  let right_bits = right.coefficient_bits()
  guard left_bits <= binary_coeff_fast_bits_limit &&
    right_bits <= binary_coeff_fast_bits_limit else {
    return None
  }
  let left_exponent = left.exponent2_()
  let right_exponent = right.exponent2_()
  let gap = (left_exponent + left_bits - right_exponent - right_bits).to_int64()
  let far = (precision + 3).to_int64()
  guard gap <= far && gap >= -far else { return None }
  let target = Int32::min(left_exponent, right_exponent)
  let left_shift = left_exponent - target
  let right_shift = right_exponent - target
  let left_top = left_bits + left_shift
  let right_top = right_bits + right_shift
  let count = Int32::max(left_top, right_top) / 64 + 1
  if count > ref_add_words_limit {
    return ref_add_wide(left, right, target, left_shift, right_shift, precision)
  }
  let words = FixedArray::make(count, 0UL)
  let left_words = binary_coeff_fast_array(left.coefficient_())
  let left_len = binary_coeff_fast_len(left.coefficient_())
  let right_words = binary_coeff_fast_array(right.coefficient_())
  let right_len = binary_coeff_fast_len(right.coefficient_())
  if left.negative() == right.negative() {
    let mut carry = 0UL
    for index in 0..<count {
      let a = ref_aligned_word(left_words, left_len, left_shift, index)
      let b = ref_aligned_word(right_words, right_len, right_shift, index)
      let partial = a + b
      let sum = partial + carry
      carry = if partial < a || sum < partial { 1UL } else { 0UL }
      words.unsafe_set(index, sum)
    }
    return Some(
      ref_finish(
        left.negative(),
        bin_coeff_from_words(words, count),
        target,
        precision,
        false,
      ),
    )
  }
  // opposite signs: the larger aligned magnitude minus the smaller
  let mut comparison = if left_top != right_top {
    if left_top > right_top {
      1
    } else {
      -1
    }
  } else {
    0
  }
  let mut index = count - 1
  while comparison == 0 && index >= 0 {
    let a = ref_aligned_word(left_words, left_len, left_shift, index)
    let b = ref_aligned_word(right_words, right_len, right_shift, index)
    if a != b {
      comparison = if a > b { 1 } else { -1 }
    }
    index -= 1
  }
  if comparison == 0 {
    return None
  }
  let negative = if comparison > 0 { left.negative() } else { right.negative() }
  let mut borrow = 0UL
  for index in 0..<count {
    let left_word = ref_aligned_word(left_words, left_len, left_shift, index)
    let right_word = ref_aligned_word(
      right_words, right_len, right_shift, index,
    )
    let a = if comparison > 0 { left_word } else { right_word }
    let b = if comparison > 0 { right_word } else { left_word }
    let partial = a - b
    let difference = partial - borrow
    borrow = if a < b || partial < borrow { 1UL } else { 0UL }
    words.unsafe_set(index, difference)
  }
  Some(
    ref_finish(
      negative,
      bin_coeff_from_words(words, count),
      target,
      precision,
      false,
    ),
  )
}

///|
fn add_test_float(
  random : FastCoeffRandom,
  precision : Int32,
  width : Int32,
  exponent : Int32,
  negative : Bool,
) -> Binary {
  Binary::make_coeff(
    fast_coeff_value(random, width),
    exponent,
    precision,
    negative~,
  )
}

///|
/// The same value moved so that its top bit is `top`.
fn add_test_with_top(value : Binary, top : Int32) -> Binary {
  let bits = value.coefficient_bits()
  Binary::make_coeff(
    value.coefficient_(),
    top - bits,
    value.precision_(),
    negative=value.negative(),
  )
}

///|
fn add_test_width(random : FastCoeffRandom, precision : Int32) -> Int32 {
  match random.below(5) {
    0 => 1 + random.below(precision)
    1 => precision - random.below(3)
    _ => precision
  }
}

///|
/// A pair with the exponent gap `gap` between the top bits (`gap` may be
/// negative), operands of precision `precision` and a precision a few bits
/// lower for the other.
fn add_test_pair_gap(
  random : FastCoeffRandom,
  precision : Int32,
  gap : Int32,
) -> (Binary, Binary) {
  let left_top = random.below(600) - 300
  let left = add_test_float(
    random,
    precision,
    add_test_width(random, precision),
    left_top,
    random.below(2) == 0,
  )
  let other_precision = if random.below(3) == 0 {
    Int32::max(2, precision - 1 - random.below(40))
  } else {
    precision
  }
  let right = add_test_float(
    random,
    other_precision,
    add_test_width(random, other_precision),
    0,
    random.below(2) == 0,
  )
  let actual_left_top = left.exponent2_() + left.coefficient_bits()
  (left, add_test_with_top(right, actual_left_top - gap))
}

///|
/// Cancellation: the same top bit, the same leading limbs, a difference of
/// a few units in the last place (or of one bit).
fn add_test_pair_cancel(
  random : FastCoeffRandom,
  precision : Int32,
) -> (Binary, Binary) {
  let left = add_test_float(
    random,
    precision,
    precision,
    random.below(200) - 100,
    false,
  )
  let coefficient = left.coefficient_()
  let delta = match random.below(4) {
    0 => Coeff::one()
    1 => Coeff::from_uint64(2UL + random.next() % 1000UL)
    2 =>
      fast_coeff_value(random, 1 + random.below(Int32::max(1, precision / 2)))
    _ => Coeff::zero()
  }
  let other = if random.below(2) == 0 {
    coefficient.add(delta)
  } else {
    match coefficient.sub_checked(delta) {
      Ok(value) => if value.is_zero() { coefficient } else { value }
      Err(_) => coefficient
    }
  }
  let right = Binary::make_coeff(
    other,
    left.exponent2_(),
    precision,
    negative=!left.negative(),
  )
  (left, right)
}

///|
/// A tie: the right operand is one half unit in the last place of the left
/// operand's precision (so the sum is exactly half way, with an even or an
/// odd neighbour depending on the last bit).
fn add_test_pair_tie(
  random : FastCoeffRandom,
  precision : Int32,
) -> (Binary, Binary) {
  let left = add_test_float(
    random,
    precision,
    precision,
    random.below(200) - 100,
    random.below(2) == 0,
  )
  let top = left.exponent2_() + left.coefficient_bits()
  let right = Binary::make_coeff(
    Coeff::one(),
    top - precision - 1,
    precision,
    negative=random.below(2) == 0,
  )
  (left, right)
}

///|
/// A tie broken by a sticky bit: the right operand is half a unit in the last
/// place of the left operand's precision plus an amount below the window of
/// the pass (its coefficient is `2^m + 1`), so the sum is just above and the
/// difference just below the tie.
fn add_test_pair_deep_tie(
  random : FastCoeffRandom,
  precision : Int32,
) -> (Binary, Binary) {
  let left = add_test_float(
    random,
    precision,
    precision,
    random.below(200) - 100,
    random.below(2) == 0,
  )
  let top = left.exponent2_() + left.coefficient_bits()
  let m = 3 + random.below(40)
  let right = Binary::make_coeff(
    Coeff::one().shift_left(m).add(Coeff::one()),
    top - precision - 1 - m,
    precision,
    negative=random.below(2) == 0,
  )
  (left, right)
}

///|
fn add_test_check(left : Binary, right : Binary) -> Int32 raise {
  assert_true(left.coefficient_().is_odd() && right.coefficient_().is_odd())
  let context = BinaryContext::new(precision=max_precision(left, right))
  let general = left.add_ctx(right, context).0
  let reference = ref_add(left, right)
  let actual = binary_coeff_fast_add(left, right)
  let mut some = 0
  match actual {
    Some(result) => {
      some += 1
      assert_true(fast_test_same(result, general))
    }
    None => assert_true(general.is_zero())
  }
  match reference {
    Some(expected) =>
      match actual {
        Some(result) => assert_true(fast_test_same(result, expected))
        None => abort("the pass declined what the reference answered")
      }
    None => ()
  }
  // the subtraction of the same operands
  let negated = right.neg()
  let difference = left.sub_ctx(right, context).0
  match binary_coeff_fast_add(left, negated) {
    Some(result) => assert_true(fast_test_same(result, difference))
    None => assert_true(difference.is_zero())
  }
  assert_true(fast_test_same(left.add(right), general))
  some
}

///|
fn add_test_run(seed : UInt64, precision : Int32, pairs : Int32) -> Unit raise {
  let random = { coeff_state: seed + precision.to_uint64(), }
  let gaps = [
    0,
    1,
    63,
    64,
    65,
    precision - 1,
    precision,
    precision + 1,
    precision + 2,
    2 * precision,
    4 * precision + 17,
    100000,
  ]
  let mut some = 0
  for gap in gaps {
    for _ in 0..<pairs {
      let signed_gap = if random.below(2) == 0 { gap } else { -gap }
      let (left, right) = add_test_pair_gap(random, precision, signed_gap)
      some += add_test_check(left, right)
    }
  }
  for _ in 0..<pairs {
    let (left, right) = add_test_pair_cancel(random, precision)
    some += add_test_check(left, right)
  }
  for _ in 0..<pairs {
    let (left, right) = add_test_pair_tie(random, precision)
    some += add_test_check(left, right)
  }
  for _ in 0..<pairs {
    let (left, right) = add_test_pair_deep_tie(random, precision)
    some += add_test_check(left, right)
  }
  assert_true(some > pairs * 10)
}

///|
// oracle: B
// source: add_ctx general route and ref_add (the 0.11 word loops kept in the test, with ref_add_wide: Coeff operations): a different algorithm from the route under test. The general route is itself checked against exact arithmetic on the inputs this test draws from (precisions from 2 to 8192, all five directions, ties, carries between words, borrow, cancellation, far operands, exact quotients, perfect squares) by the tests "add, mul, div and sqrt are rounded once, exactly: rows from exact arithmetic" and "add, mul, div and sqrt without a context: the ties-to-even rows" of arith_rows_check_wbtest.mbt (rows of arith_rows_wbtest.mbt from tools/generate_arith_rows.py: Python fractions and math.isqrt, library-ran: no); the exponent-range edges of binary16, binary32 and binary64 are rows there for add, mul and div. Operands of 129 to 256 bits with gaps up to 100000 and exact ties. The previous path is a second B oracle on the same inputs, not an A one.
// shares: both routes call binary_inexact_flags for the flags of an exact result and the Binary constructors (finite_normalized, bin_repr_word) to build the value, which the differential does not check and the table does through the flags and the printed value; the rounding decision is written twice, in the word, pair or limb finish of the fast route and in binary_apply_round_bits behind binary_round_dyadic / binary_round_rational / binary_round_sqrt in the general route, so it is not shared; fast_test_same compares value, precision label, sign and exponent
// primitives: Coeff::add, Coeff::sub_checked, Coeff::mul, Coeff::shift_left, binary_round_dyadic, binary_round_rational, binary_round_sqrt: level A on the same operations and widths in arith_rows_wbtest.mbt and, up to 128 bits, in the TestFloat gate
test "aligned add pass equals the previous path and add_ctx, 129 to 256 bits" {
  for precision in [129, 192, 256] {
    add_test_run(0xADD0001UL, precision, 2000)
  }
}

///|
// oracle: B
// source: add_ctx general route and ref_add (the 0.11 word loops kept in the test, with ref_add_wide: Coeff operations): a different algorithm from the route under test. The general route is itself checked against exact arithmetic on the inputs this test draws from (precisions from 2 to 8192, all five directions, ties, carries between words, borrow, cancellation, far operands, exact quotients, perfect squares) by the tests "add, mul, div and sqrt are rounded once, exactly: rows from exact arithmetic" and "add, mul, div and sqrt without a context: the ties-to-even rows" of arith_rows_check_wbtest.mbt (rows of arith_rows_wbtest.mbt from tools/generate_arith_rows.py: Python fractions and math.isqrt, library-ran: no); the exponent-range edges of binary16, binary32 and binary64 are rows there for add, mul and div. Operands of 512 and 1024 bits with gaps up to 100000 and exact ties. The previous path is a second B oracle on the same inputs, not an A one.
// shares: both routes call binary_inexact_flags for the flags of an exact result and the Binary constructors (finite_normalized, bin_repr_word) to build the value, which the differential does not check and the table does through the flags and the printed value; the rounding decision is written twice, in the word, pair or limb finish of the fast route and in binary_apply_round_bits behind binary_round_dyadic / binary_round_rational / binary_round_sqrt in the general route, so it is not shared; fast_test_same compares value, precision label, sign and exponent
// primitives: Coeff::add, Coeff::sub_checked, Coeff::mul, Coeff::shift_left, binary_round_dyadic, binary_round_rational, binary_round_sqrt: level A on the same operations and widths in arith_rows_wbtest.mbt and, up to 128 bits, in the TestFloat gate
test "aligned add pass equals the previous path and add_ctx, 512 and 1024 bits" {
  for precision in [512, 1024] {
    add_test_run(0xADD0002UL, precision, 2000)
  }
}

///|
// oracle: B
// source: add_ctx general route and ref_add (the 0.11 word loops kept in the test, with ref_add_wide: Coeff operations): a different algorithm from the route under test. The general route is itself checked against exact arithmetic on the inputs this test draws from (precisions from 2 to 8192, all five directions, ties, carries between words, borrow, cancellation, far operands, exact quotients, perfect squares) by the tests "add, mul, div and sqrt are rounded once, exactly: rows from exact arithmetic" and "add, mul, div and sqrt without a context: the ties-to-even rows" of arith_rows_check_wbtest.mbt (rows of arith_rows_wbtest.mbt from tools/generate_arith_rows.py: Python fractions and math.isqrt, library-ran: no); the exponent-range edges of binary16, binary32 and binary64 are rows there for add, mul and div. Operands of 2048 bits with gaps up to 100000 and exact ties. The previous path is a second B oracle on the same inputs, not an A one.
// shares: both routes call binary_inexact_flags for the flags of an exact result and the Binary constructors (finite_normalized, bin_repr_word) to build the value, which the differential does not check and the table does through the flags and the printed value; the rounding decision is written twice, in the word, pair or limb finish of the fast route and in binary_apply_round_bits behind binary_round_dyadic / binary_round_rational / binary_round_sqrt in the general route, so it is not shared; fast_test_same compares value, precision label, sign and exponent
// primitives: Coeff::add, Coeff::sub_checked, Coeff::mul, Coeff::shift_left, binary_round_dyadic, binary_round_rational, binary_round_sqrt: level A on the same operations and widths in arith_rows_wbtest.mbt and, up to 128 bits, in the TestFloat gate
test "aligned add pass equals the previous path and add_ctx, 2048 bits" {
  add_test_run(0xADD0003UL, 2048, 2000)
}

///|
// oracle: B
// source: add_ctx general route and ref_add (the 0.11 word loops kept in the test, with ref_add_wide: Coeff operations): a different algorithm from the route under test. The general route is itself checked against exact arithmetic on the inputs this test draws from (precisions from 2 to 8192, all five directions, ties, carries between words, borrow, cancellation, far operands, exact quotients, perfect squares) by the tests "add, mul, div and sqrt are rounded once, exactly: rows from exact arithmetic" and "add, mul, div and sqrt without a context: the ties-to-even rows" of arith_rows_check_wbtest.mbt (rows of arith_rows_wbtest.mbt from tools/generate_arith_rows.py: Python fractions and math.isqrt, library-ran: no); the exponent-range edges of binary16, binary32 and binary64 are rows there for add, mul and div. Operands of 8192 bits with gaps up to 100000 and exact ties. The previous path is a second B oracle on the same inputs, not an A one.
// shares: both routes call binary_inexact_flags for the flags of an exact result and the Binary constructors (finite_normalized, bin_repr_word) to build the value, which the differential does not check and the table does through the flags and the printed value; the rounding decision is written twice, in the word, pair or limb finish of the fast route and in binary_apply_round_bits behind binary_round_dyadic / binary_round_rational / binary_round_sqrt in the general route, so it is not shared; fast_test_same compares value, precision label, sign and exponent
// primitives: Coeff::add, Coeff::sub_checked, Coeff::mul, Coeff::shift_left, binary_round_dyadic, binary_round_rational, binary_round_sqrt: level A on the same operations and widths in arith_rows_wbtest.mbt and, up to 128 bits, in the TestFloat gate
test "aligned add pass equals the previous path and add_ctx, 8192 bits" {
  add_test_run(0xADD0004UL, 8192, 2000)
}
