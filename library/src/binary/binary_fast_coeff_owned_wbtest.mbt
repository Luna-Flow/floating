///|
/// The words of a coefficient as a fresh array (a snapshot that no
/// in-place operation can reach).
fn owned_test_words(value : Coeff) -> Array[UInt64] {
  let count = (value.bit_length() + 63) / 64
  let result : Array[UInt64] = []
  for index in 0..<count {
    result.push(bin_coeff_word(value, index))
  }
  result
}

///|
fn owned_test_same_words(value : Coeff, snapshot : Array[UInt64]) -> Bool {
  let count = (value.bit_length() + 63) / 64
  if count != snapshot.length() {
    return false
  }
  for index in 0..<count {
    if bin_coeff_word(value, index) != snapshot[index] {
      return false
    }
  }
  true
}

///|
/// The operands of the coefficient paths are never modified by the in-place
/// finisher, the paths agree with the contextual operations, and the same
/// call twice gives the same result (nothing shared was written to).
fn owned_test_check(left : Binary, right : Binary) -> Int32 raise {
  let left_words = owned_test_words(left.coefficient_())
  let right_words = owned_test_words(right.coefficient_())
  let context = BinaryContext::new(precision=max_precision(left, right))
  let mut covered = 0
  let product = left.mul_ctx(right, context).0
  match binary_coeff_fast_mul(left, right) {
    Some(result) => {
      covered += 1
      assert_true(fast_test_same(result, product))
      match binary_coeff_fast_mul(left, right) {
        Some(again) => assert_true(fast_test_same(again, result))
        None => abort("mul answered once and declined the second time")
      }
    }
    None => ()
  }
  let quotient = left.div_ctx(right, context).0
  match binary_coeff_fast_div(left, right) {
    Some(result) => {
      covered += 1
      assert_true(fast_test_same(result, quotient))
      match binary_coeff_fast_div(left, right) {
        Some(again) => assert_true(fast_test_same(again, result))
        None => abort("div answered once and declined the second time")
      }
    }
    None => ()
  }
  if !left.is_sign_minus() {
    let root = left.sqrt_ctx(BinaryContext::new(precision=left.precision())).0
    match binary_coeff_fast_sqrt(left) {
      Some(result) => {
        covered += 1
        assert_true(fast_test_same(result, root))
        match binary_coeff_fast_sqrt(left) {
          Some(again) => assert_true(fast_test_same(again, result))
          None => abort("sqrt answered once and declined the second time")
        }
      }
      None => ()
    }
  }
  assert_true(owned_test_same_words(left.coefficient_(), left_words))
  assert_true(owned_test_same_words(right.coefficient_(), right_words))
  covered
}

///|
test "mul, div and sqrt round the kernel arrays in place without touching the operands" {
  let random = { coeff_state: 0x0B0A12D5UL, }
  let mut covered = 0
  for _ in 0..<4000 {
    let around = random.below(200) - 100
    let precision = fast_coeff_precision(random)
    let left = fast_coeff_operand(random, around, 2600, precision)
    let right = fast_coeff_operand(
      random,
      around + random.below(9) - 4,
      2600,
      precision - random.below(3) + 1,
    )
    covered += owned_test_check(left, right)
    // the same value on both sides, and a copy of it
    covered += owned_test_check(left, left)
    covered += owned_test_check(
      left,
      Binary::make_coeff(
        left.coefficient_().shift_left(0),
        left.exponent2_(),
        left.precision_(),
        negative=left.negative(),
      ),
    )
  }
  // precisions of 13 to 64 limbs, where `mul` takes the short product
  for _ in 0..<300 {
    let precision = 830 + random.below(3200)
    let left = fast_coeff_operand(random, 0, precision, precision)
    let right = fast_coeff_operand(
      random,
      random.below(9) - 4,
      precision,
      precision,
    )
    covered += owned_test_check(left, right)
    covered += owned_test_check(left, left)
  }
  // powers of two and other short coefficients at a wide precision
  for precision in [129, 200, 640, 2100] {
    for small in [1UL, 3UL, 5UL, 255UL, 0xFFFFFFFFFFFFFFFFUL] {
      let value = Binary::make_coeff(
        Coeff::from_uint64(small),
        random.below(40) - 20,
        precision,
        negative=false,
      )
      let wide = fast_coeff_operand(random, 0, precision, precision)
      covered += owned_test_check(value, wide)
      covered += owned_test_check(wide, value)
      covered += owned_test_check(value, value)
    }
  }
  assert_true(covered > 8000)
}
