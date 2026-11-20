///|
fn bin_coeff_sqrt_big(value : BinCoeff) -> BigInt raise {
  @string.parse_bigint(value.to_string())
}

///|
/// The definition of the integer square root, independent of the code under
/// test (BigInt products and comparisons only): `root^2 <= n < (root + 1)^2`.
fn bin_coeff_sqrt_assert_floor(value_big : BigInt, root : BigInt) -> Unit raise {
  assert_true(root * root <= value_big)
  assert_true(value_big < (root + 1N) * (root + 1N))
}

///|
/// `root^2 + remainder == n` and `remainder <= 2 root` (equivalent to the
/// floor property together with the remainder being `n - root^2`).
fn bin_coeff_sqrt_assert_pair(
  value_big : BigInt,
  root : BigInt,
  remainder : BigInt,
) -> Unit raise {
  assert_true(root * root + remainder == value_big)
  assert_true(remainder <= 2N * root)
}

///|
fn bin_coeff_sqrt_words_check(value_big : BigInt) -> Unit raise {
  let value = bin_coeff_test_from_bigint(value_big)
  let bits = value.bit_length()
  if bits <= 128 {
    let words = bin_coeff_sqrt_rem_u128_words(
      bin_coeff_word(value, 1),
      bin_coeff_word(value, 0),
    )
    let root = bin_coeff_sqrt_big(words.0)
    bin_coeff_sqrt_assert_pair(value_big, root, bin_coeff_sqrt_big(words.1))
    let reference = bin_coeff_sqrt_rem_u128(
      bin_coeff_word(value, 1),
      bin_coeff_word(value, 0),
    )
    // The two entries agree with each other and with the definition.
    assert_eq(reference.0.to_string(), words.0.to_string())
    bin_coeff_sqrt_assert_floor(value_big, bin_coeff_sqrt_big(reference.0))
  } else if bits <= 256 {
    let words = bin_coeff_sqrt_rem_u256_words(value)
    let root = bin_coeff_sqrt_big(words.0)
    bin_coeff_sqrt_assert_pair(value_big, root, bin_coeff_sqrt_big(words.1))
    let reference = bin_coeff_sqrt_rem_u256(value)
    assert_eq(reference.0.to_string(), words.0.to_string())
    bin_coeff_sqrt_assert_floor(value_big, bin_coeff_sqrt_big(reference.0))
  }
}

///|
test "word square roots at every width up to 256 bits" {
  for bits in 1..<=256 {
    for seed in 1..<6 {
      bin_coeff_sqrt_words_check(
        bin_coeff_sqrt_test_value(bits, (seed * 977 + bits).to_uint64()),
      )
    }
    bin_coeff_sqrt_words_check((1N << bits) - 1N)
    bin_coeff_sqrt_words_check(1N << (bits - 1))
    // the neighbours of exact squares, near the largest and smallest roots of
    // the width and around every power of two
    let root = bin_coeff_sqrt_test_value(
      (bits + 1) / 2,
      31UL + bits.to_uint64(),
    )
    let square = root * root
    if square.bit_length() <= 256 {
      bin_coeff_sqrt_words_check(square)
      bin_coeff_sqrt_words_check(square - 1N)
      bin_coeff_sqrt_words_check(square + 1N)
    }
    let high_root = (1N << ((bits + 1) / 2)) - 1N
    let high_square = high_root * high_root
    bin_coeff_sqrt_words_check(high_square)
    bin_coeff_sqrt_words_check(high_square - 1N)
    bin_coeff_sqrt_words_check(high_square + 2N * high_root)
  }
}

///|
test "word square roots of random data and long runs of bits" {
  for index in 0..<4000 {
    let bits = 1 + index * 53 % 256
    bin_coeff_sqrt_words_check(
      bin_coeff_sqrt_test_value(bits, (5000 + index).to_uint64()),
    )
    // a run of ones followed by zeros, and the reverse
    let run = 1 + index * 29 % bits
    bin_coeff_sqrt_words_check(((1N << run) - 1N) << (bits - run).max(0))
    bin_coeff_sqrt_words_check((1N << (bits - 1)) + ((1N << (bits / 2)) - 1N))
  }
}

///|
test "word square root of a word" {
  for
    value in [
      0UL, 1UL, 2UL, 3UL, 4UL, 15UL, 16UL, 17UL, 0xffff_ffffUL, 0x1_0000_0000UL,
      0xffff_ffff_ffff_ffffUL, 0xffff_fffe_0000_0001UL, 0xffff_fffe_0000_0000UL,
      0xffff_ffff_0000_0000UL,
    ] {
    let root = bin_coeff_isqrt64(value)
    bin_coeff_sqrt_assert_floor(
      BigInt::from_uint64(value),
      BigInt::from_uint64(root),
    )
  }
}

///|
test "fixed-width restoring square roots return zero for zero at once" {
  let (root, remainder) = bin_coeff_sqrt_rem_u128(0UL, 0UL)
  assert_true(root.is_zero() && remainder.is_zero())
  let (root256, remainder256) = bin_coeff_sqrt_rem_u256(BinCoeff::zero())
  assert_true(root256.is_zero() && remainder256.is_zero())
}
