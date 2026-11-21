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
test "Coeff sqrt divide-and-conquer around the base-case and kernel cutoffs" {
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
test "Coeff sqrt divide-and-conquer random data" {
  for index in 0..<200 {
    let bits = 129 + index * 37 % 1400
    bin_coeff_sqrt_test_check(
      bin_coeff_sqrt_test_value(bits, (1000 + index).to_uint64()),
    )
  }
}
