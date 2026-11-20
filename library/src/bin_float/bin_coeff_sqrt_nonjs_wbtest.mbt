///|
/// Deterministic pseudo-random value of exactly `bits` bits (top bit set).
fn bin_coeff_sqrt_test_value(bits : Int32, seed : UInt64) -> BigInt {
  let mut state = seed * 6364136223846793005UL + 1442695040888963407UL
  let mut value = 0N
  let mut produced = 0
  while produced < bits {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    value = (value << 32) | BigInt::from_uint64(state >> 32)
    produced += 32
  }
  let trimmed = value >> (produced - bits)
  trimmed | (1N << (bits - 1))
}

///|
fn bin_coeff_sqrt_test_check(value_big : BigInt) -> Unit raise {
  let value = bin_coeff_test_from_bigint(value_big)
  let root_big = bin_coeff_test_integer_sqrt_floor(value_big)
  let remainder_big = value_big - root_big * root_big
  // The production dispatch, the divide-and-conquer path and the restoring
  // reference must agree with the BigInt oracle.
  let paths = [
    bin_coeff_sqrt_rem_kernel(value),
    bin_coeff_sqrt_rem_divide_conquer(value),
    bin_coeff_sqrt_rem_restoring(value),
  ]
  if value.bit_length() > 256 {
    let array = bin_coeff_sqrt_rem_words_recursive(value)
    bin_coeff_test_assert_matches(array.0, root_big)
    bin_coeff_test_assert_matches(array.1, remainder_big)
  }
  for path in paths {
    bin_coeff_test_assert_matches(path.0, root_big)
    bin_coeff_test_assert_matches(path.1, remainder_big)
  }
  if value.bit_length() <= 512 {
    let fixed = bin_coeff_sqrt_rem_fixed_width(value)
    bin_coeff_test_assert_matches(fixed.0, root_big)
    bin_coeff_test_assert_matches(fixed.1, remainder_big)
  }
}

///|
test "BinCoeff sqrt divide-and-conquer around the base-case and kernel cutoffs" {
  let sizes = [
    65, 127, 128, 129, 191, 192, 193, 255, 256, 257, 258, 383, 384, 385, 511, 512,
    513, 514, 515, 767, 768, 769, 1023, 1024, 1025, 1026, 1500, 2047, 2048, 2049,
    2050, 4095, 4096, 4097, 320, 321, 448, 449, 576, 577, 640, 641, 1087, 1088, 1089,
    1151, 1152, 1153, 1279, 1280, 1281,
  ]
  for bits in sizes {
    for seed in 1..<4 {
      bin_coeff_sqrt_test_check(
        bin_coeff_sqrt_test_value(bits, seed.to_uint64()),
      )
    }
    // all ones, a single bit, and the neighbours of an exact square
    bin_coeff_sqrt_test_check((1N << bits) - 1N)
    bin_coeff_sqrt_test_check(1N << (bits - 1))
    let root = bin_coeff_sqrt_test_value((bits + 1) / 2, 77UL)
    let square = root * root
    bin_coeff_sqrt_test_check(square)
    bin_coeff_sqrt_test_check(square - 1N)
    bin_coeff_sqrt_test_check(square + 1N)
    bin_coeff_sqrt_test_check(square + 2N * root)
    bin_coeff_sqrt_test_check(square + 2N * root + 1N)
  }
}

///|
test "BinCoeff sqrt divide-and-conquer random data" {
  for index in 0..<200 {
    let bits = 129 + index * 37 % 1400
    bin_coeff_sqrt_test_check(
      bin_coeff_sqrt_test_value(bits, (1000 + index).to_uint64()),
    )
  }
}

///|
test "BinCoeff sqrt cutoffs are inside the fixed-width kernel range" {
  assert_true(bin_coeff_sqrt_dc_base_bits >= 128)
  assert_true(bin_coeff_sqrt_dc_base_bits <= 512)
}

///|
/// Large radicands, checked by the defining inequalities
/// `root^2 <= value < (root + 1)^2` and `remainder = value - root^2` (no
/// second implementation involved) and against the `BinCoeff` recursion.
fn bin_coeff_sqrt_test_check_large(value : BinCoeff) -> Unit raise {
  let (root, remainder) = bin_coeff_sqrt_rem_words_recursive(value)
  let (reference_root, reference_remainder) = bin_coeff_sqrt_rem_divide_conquer(
    value,
  )
  assert_true(root == reference_root)
  assert_true(remainder == reference_remainder)
  assert_true(root.square().add(remainder) == value)
  assert_true(remainder.compare(root.shift_left(1)) <= 0)
}

///|
test "BinCoeff sqrt word recursion on large and adversarial radicands" {
  let sizes = [
    1537, 1600, 2049, 3000, 4097, 5000, 8191, 8192, 8193, 12289, 16385, 33000,
  ]
  for bits in sizes {
    bin_coeff_sqrt_test_check_large(
      bin_coeff_test_from_bigint(bin_coeff_sqrt_test_value(bits, 5UL)),
    )
    bin_coeff_sqrt_test_check_large(
      bin_coeff_test_from_bigint((1N << bits) - 1N),
    )
    bin_coeff_sqrt_test_check_large(
      bin_coeff_test_from_bigint(1N << (bits - 1)),
    )
    // zero limbs inside the value
    let sparse = (1N << (bits - 1)) | (1N << (bits / 2)) | 1N
    bin_coeff_sqrt_test_check_large(bin_coeff_test_from_bigint(sparse))
    let root = bin_coeff_sqrt_test_value((bits + 1) / 2, 9UL)
    let square = root * root
    bin_coeff_sqrt_test_check_large(bin_coeff_test_from_bigint(square))
    bin_coeff_sqrt_test_check_large(bin_coeff_test_from_bigint(square - 1N))
    bin_coeff_sqrt_test_check_large(
      bin_coeff_test_from_bigint(square + 2N * root),
    )
  }
}
