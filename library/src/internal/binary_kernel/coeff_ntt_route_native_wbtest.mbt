///|
/// The routes of `Coeff::mul` between the NTT, Toom-3 and the Karatsuba blocks
/// on native (`bin_coeff_ntt_mul_min_words` and `bin_coeff_ntt_mul_min_product_words`):
/// the default product against `bin_coeff_mul_ntt`, an independent algorithm, on
/// shapes on both sides of each limit and four operand patterns. Run in the three
/// states of the row implementation (`LUNA_FLOATING_PORTABLE`, `LUNA_FLOATING_LIMBS`).

///|
fn bin_ntt_route_operand(len : Int32, pattern : Int32, seed : UInt64) -> Coeff {
  let words = bin_limbs_pattern(len, seed)
  match pattern {
    // random limbs
    0 => ()
    // all limbs ones
    1 =>
      for index in 0..<len {
        words[index] = 0xffff_ffff_ffff_ffffUL
      }
    // a single bit at the top
    2 =>
      for index in 0..<len {
        words[index] = 0UL
      }
    // random limbs with runs of zero limbs
    _ =>
      for index in 0..<len {
        if index / 61 % 3 != 0 {
          words[index] = 0UL
        }
      }
  }
  words[len - 1] = if pattern == 2 {
    0x8000_0000_0000_0000UL
  } else {
    words[len - 1] | 0x8000_0000_0000_0000UL
  }
  bin_coeff_from_words(words, len)
}

///|
fn bin_ntt_route_check(
  label : String,
  left_len : Int32,
  right_len : Int32,
  pattern : Int32,
) -> Unit {
  let left = bin_ntt_route_operand(
    left_len,
    pattern,
    11UL + left_len.to_uint64(),
  )
  let right = bin_ntt_route_operand(
    right_len,
    pattern,
    23UL + right_len.to_uint64(),
  )
  let expected = bin_coeff_mul_ntt(left, right)
  if !left.mul(right).equal(expected) {
    abort(
      "Coeff::mul differs from the NTT: \{label} \{left_len} x \{right_len}, pattern \{pattern}",
    )
  }
}

///|
/// Shapes: balanced on both sides of the 4,096 limit and of the product limit,
/// ratio up to 2 (Toom-3), ratio above 2 below the product limit (Karatsuba
/// blocks), and at and above the product limit (the NTT again).
fn bin_ntt_route_shapes() -> Array[(String, Int32, Int32)] {
  let limit = bin_coeff_ntt_mul_min_product_words
  let half = Int32::max(limit / 2, 4096)
  [
    ("balanced", 4096, 4096),
    ("balanced", 4097, 4097),
    ("balanced", 5120, 5120),
    ("balanced", 6143, 6143),
    ("balanced", 7168, 7168),
    ("balanced", 14336, 14336),
    ("ratio 2", 8192, 4096),
    ("ratio 2", 15360, 7680),
    ("ratio just below 2", 8191, 4096),
    ("ratio above 2", 12288, 4096),
    ("ratio above 2", 10240, 4096),
    ("ratio above 2", 13000, 4097),
    ("below the product limit", half - 1, half - 1),
    ("at the product limit", half, half),
    ("above the product limit", half + 1, half + 1),
    ("unbalanced at the product limit", Int32::max(limit - 4096, 4096), 4096),
    (
      "unbalanced just below the product limit",
      Int32::max(limit - 4097, 4096),
      4096,
    ),
  ]
}

///|
// oracle: B
// source: bin_coeff_mul_ntt, the two-prime number-theoretic transform, a different algorithm from the Toom-3 and Karatsuba routes that Coeff::mul takes on these shapes, on the balanced, ratio 2, ratio above 2 and product-limit shapes of bin_ntt_route_shapes and four operand patterns
// shares: bin_coeff_from_words and the Coeff limb layout (both products are read through Coeff::equal)
// primitives: bin_coeff_mul_ntt: level A in the product table (coeff_product_oracle_wbtest.mbt, CPython product, route `ntt`) on the balanced shapes 4,095 to 7,169, 14,336 to 15,361 and 30,719 to 30,721 limbs and on the unbalanced shapes 8,191 x 4,096, 8,192 x 4,096, 10,240 x 4,096, 12,288 x 4,096, 13,000 x 4,097, 15,360 x 7,680 and 30,000 x 4,096; not on the shapes at the product limit of the other tiers, nor on (limit - 4,096) x 4,096 and (limit - 4,097) x 4,096, whose NTT product rests on the convolution rows of the NTT table (operands up to 1,000 limbs) and on this block's agreement with the other routes; patterns: the table draws regression_value shapes, not these four patterns
#skip("full list: the binary gate runs it with --include-skipped, in the three states")
test "the default product equals the NTT product on every shape and pattern" {
  let mut cases = 0
  for shape in bin_ntt_route_shapes() {
    let (label, left_len, right_len) = shape
    for pattern in 0..<4 {
      bin_ntt_route_check(label, left_len, right_len, pattern)
      bin_ntt_route_check(label, right_len, left_len, pattern)
      cases += 2
    }
  }
  println(
    "ntt route: \{cases} products, product limit \{bin_coeff_ntt_mul_min_product_words} limbs",
  )
}

///|
#skip("full list: the binary gate runs it with --include-skipped, in the three states")
// oracle: B
// source: bin_coeff_mul_ntt, the two-prime number-theoretic transform, a different algorithm from Toom-3 and the Karatsuba blocks, on the shapes of the route tests
// shares: bin_coeff_from_words and the Coeff limb layout (the products are read through Coeff::equal)
// primitives: bin_coeff_mul_ntt: level A in the product table (coeff_product_oracle_wbtest.mbt, CPython product, route `ntt`)
test "Toom-3 and the Karatsuba blocks, called directly, equal the NTT product" {
  for
    shape in [
      (4096, 4096),
      (4097, 4097),
      (5120, 5120),
      (6143, 6143),
      (8192, 4096),
      (8191, 4096),
      (6000, 4096),
    ] {
    let (left_len, right_len) = shape
    for pattern in 0..<4 {
      let left = bin_ntt_route_operand(left_len, pattern, 5UL)
      let right = bin_ntt_route_operand(right_len, pattern, 7UL)
      let expected = bin_coeff_mul_ntt(left, right)
      assert_true(bin_coeff_mul_toom3(left, right).equal(expected))
      assert_true(bin_coeff_mul_words(left, right).equal(expected))
    }
  }
  for shape in [(12288, 4096), (10240, 4096), (13000, 4097)] {
    let (left_len, right_len) = shape
    for pattern in 0..<4 {
      let left = bin_ntt_route_operand(left_len, pattern, 5UL)
      let right = bin_ntt_route_operand(right_len, pattern, 7UL)
      let expected = bin_coeff_mul_ntt(left, right)
      assert_true(bin_coeff_mul_words(left, right).equal(expected))
    }
  }
}

///|
/// The subset of the package tests (about two seconds): one balanced shape just
/// above 4,096 limbs, one just below the product limit of the tier, one with a
/// ratio above 2, one at the limit, two operand patterns, and Toom-3 called
/// directly once. The full list is the two `#skip` tests above, run by the binary
/// gate.
// oracle: B
// source: bin_coeff_mul_ntt, the two-prime number-theoretic transform, a different algorithm from the Toom-3 and Karatsuba routes that Coeff::mul takes on these shapes, on the balanced, ratio 2, ratio above 2 and product-limit shapes of bin_ntt_route_shapes and four operand patterns
// shares: bin_coeff_from_words and the Coeff limb layout (both products are read through Coeff::equal)
// primitives: bin_coeff_mul_ntt: level A in the product table (coeff_product_oracle_wbtest.mbt, CPython product, route `ntt`) on the balanced shapes 4,095 to 7,169, 14,336 to 15,361 and 30,719 to 30,721 limbs and on the unbalanced shapes 8,191 x 4,096, 8,192 x 4,096, 10,240 x 4,096, 12,288 x 4,096, 13,000 x 4,097, 15,360 x 7,680 and 30,000 x 4,096; not on the shapes at the product limit of the other tiers, nor on (limit - 4,096) x 4,096 and (limit - 4,097) x 4,096, whose NTT product rests on the convolution rows of the NTT table (operands up to 1,000 limbs) and on this block's agreement with the other routes; patterns: the table draws regression_value shapes, not these four patterns
test "the default product equals the NTT product: balanced above 4,096, below, with ratio above 2 and at the product limit" {
  let half = Int32::max(bin_coeff_ntt_mul_min_product_words / 2, 4096)
  for shape in [(4097, 4097), (half - 1, half - 1), (12288, 4096), (half, half)] {
    let (left_len, right_len) = shape
    for pattern in [0, 1] {
      bin_ntt_route_check("subset", left_len, right_len, pattern)
    }
  }
  let left = bin_ntt_route_operand(4097, 0, 5UL)
  let right = bin_ntt_route_operand(4097, 0, 7UL)
  assert_true(
    bin_coeff_mul_toom3(left, right).equal(bin_coeff_mul_ntt(left, right)),
  )
}
