///|
/// The ownership rule of the producers (`Coeff::mul` for nonzero operands,
/// `bin_coeff_div_scaled_quotient`, `bin_coeff_div_short_quotient`,
/// `bin_coeff_sqrt_scaled_rounded`): a returned `Heap` coefficient owns an array
/// that no operand and no other value refers to. MoonBit's `physical_equal` on
/// `FixedArray` is the test (a write-and-observe test was not needed).

///|
fn fresh_array_of(value : Coeff) -> FixedArray[UInt64]? {
  match value.0 {
    Heap(words, _) => Some(words)
    _ => None
  }
}

///|
/// Asserts that the heap array of `result` (if any) is none of `others`.
fn fresh_check(result : Coeff, others : Array[Coeff]) -> Unit raise {
  match fresh_array_of(result) {
    None => ()
    Some(words) =>
      for other in others {
        match fresh_array_of(other) {
          Some(operand) => assert_false(physical_equal(words, operand))
          None => ()
        }
      }
  }
}

///|
/// A coefficient of `limbs` limbs from a seed, optionally held in a longer
/// array whose upper limbs are zero (`bin_coeff_from_words` trims the length).
fn fresh_value(limbs : Int32, seed : UInt64, padding : Int32) -> Coeff {
  let words = FixedArray::make(limbs + padding, 0UL)
  let mut state = seed * 6364136223846793005UL + 1442695040888963407UL
  for index in 0..<limbs {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    words.unsafe_set(index, state ^ (state >> 31))
  }
  words.unsafe_set(
    limbs - 1,
    words.unsafe_get(limbs - 1) | 0x8000_0000_0000_0000UL,
  )
  words.unsafe_set(0, words.unsafe_get(0) | 1UL)
  bin_coeff_from_words(words, limbs + padding)
}

///|
// oracle: S
// source: physical_equal on the returned FixedArray against the arrays of the operands (an identity, not a value): a returned heap coefficient owns an array that no operand refers to; the numeric values of these producers are checked in the product, quotient and root blocks (level B)
// shares: the producer under test (Coeff::mul) and the helpers that build operands from limbs
test "mul returns an array that no operand refers to" {
  let mut heap_results = 0
  for left_limbs in [1, 2, 3, 4, 5, 8, 17, 31, 32, 33, 40, 64, 65, 100, 130] {
    for right_limbs in [1, 2, 3, 4, 9, 32, 33, 70, 129] {
      for padding in [0, 5] {
        for seed in 1..<6 {
          let left = fresh_value(left_limbs, seed.to_uint64(), padding)
          let right = fresh_value(right_limbs, (seed * 7).to_uint64(), 0)
          let product = left.mul(right)
          fresh_check(product, [left, right])
          let again = left.mul(right)
          fresh_check(again, [left, right, product])
          // the product of a value with itself, and of equal values
          let square = left.mul(left)
          fresh_check(square, [left])
          let equal = fresh_value(left_limbs, seed.to_uint64(), padding)
          fresh_check(left.mul(equal), [left, equal])
          match fresh_array_of(product) {
            Some(_) => heap_results += 1
            None => ()
          }
        }
      }
    }
  }
  assert_true(heap_results > 1000)
  // a zero operand returns the shared zero, with no array
  let value = fresh_value(40, 3UL, 0)
  assert_true(value.mul(Coeff::zero()).is_zero())
  assert_true(fresh_array_of(Coeff::zero().mul(value)) is None)
}

///|
// oracle: S
// source: physical_equal on the returned FixedArray against the arrays of the operands (an identity, not a value): a returned heap coefficient owns an array that no operand refers to; the numeric values of these producers are checked in the product, quotient and root blocks (level B)
// shares: the producer under test (Coeff::shift_left and Coeff::shift_right) and the helpers that build operands from limbs
test "shifts by zero return the receiver, other shifts a new array" {
  for limbs in [3, 8, 40] {
    let value = fresh_value(limbs, 11UL, 0)
    match (fresh_array_of(value), fresh_array_of(value.shift_left(0))) {
      (Some(first), Some(second)) => assert_true(physical_equal(first, second))
      _ => abort("a wide value must keep its array under a shift by zero")
    }
    match (fresh_array_of(value), fresh_array_of(value.shift_right(0))) {
      (Some(first), Some(second)) => assert_true(physical_equal(first, second))
      _ => abort("a wide value must keep its array under a shift by zero")
    }
    fresh_check(value.shift_left(3), [value])
    fresh_check(value.shift_right(3), [value])
    assert_true(value.shift_right(limbs * 64 + 5).is_zero())
  }
  assert_true(Coeff::zero().shift_left(5).is_zero())
}

///|
// oracle: S
// source: physical_equal on the returned FixedArray against the arrays of the operands (an identity, not a value): a returned heap coefficient owns an array that no operand refers to; the numeric values of these producers are checked in the product, quotient and root blocks (level B)
// shares: the producer under test (bin_coeff_div_scaled_quotient and bin_coeff_div_short_quotient) and the helpers that build operands from limbs
test "scaled and short quotients return arrays that no operand refers to" {
  let mut exact_results = 0
  let mut short_results = 0
  for divisor_limbs in [2, 3, 4, 8, 17, 32, 33, 64, 100] {
    for dividend_extra in [-1, 0, 1, 5] {
      let dividend_limbs = Int32::max(1, divisor_limbs + dividend_extra)
      for padding in [0, 3] {
        for seed in 1..<6 {
          let dividend = fresh_value(dividend_limbs, seed.to_uint64(), padding)
          let divisor = fresh_value(divisor_limbs, (seed * 3).to_uint64(), 0)
          for scale in [0, 7, 64, 130, 200] {
            if bin_coeff_div_scaled_ok(dividend, scale, divisor) {
              let quotient = bin_coeff_div_scaled_quotient(
                dividend, scale, divisor,
              )
              fresh_check(quotient, [dividend, divisor])
              fresh_check(
                bin_coeff_div_scaled_quotient(dividend, scale, divisor),
                [dividend, divisor, quotient],
              )
              match fresh_array_of(quotient) {
                Some(_) => exact_results += 1
                None => ()
              }
            }
            if bin_coeff_div_short_ok(dividend, scale + 32, divisor) {
              let precision = divisor_limbs * 64
              let approximate = bin_coeff_div_short_quotient(
                dividend,
                scale + 32,
                divisor,
                precision,
              )
              fresh_check(approximate, [dividend, divisor])
              match fresh_array_of(approximate) {
                Some(_) => short_results += 1
                None => ()
              }
            }
          }
        }
      }
    }
  }
  assert_true(exact_results > 200)
  assert_true(short_results > 100)
}

///|
// oracle: S
// source: physical_equal on the returned FixedArray against the arrays of the operands (an identity, not a value): a returned heap coefficient owns an array that no operand refers to; the numeric values of these producers are checked in the product, quotient and root blocks (level B)
// shares: the producer under test (bin_coeff_sqrt_scaled_rounded) and the helpers that build operands from limbs
test "scaled root returns an array that the radicand does not refer to" {
  let mut heap_results = 0
  for precision in [130, 200, 257, 300, 512, 1000, 2048] {
    for width_offset in [0, -1, -64, -100] {
      let bits = precision + width_offset
      if bits < 2 {
        continue
      }
      let limbs = (bits + 63) / 64
      for padding in [0, 2] {
        for seed in 1..<6 {
          let value = fresh_value(limbs, seed.to_uint64(), padding)
          let used = value.bit_length()
          let mut scale = Int32::max(0, 2 * precision - 1 - used)
          if scale % 2 != 0 {
            scale += 1
          }
          let packed = bin_coeff_sqrt_scaled_rounded(value, scale, precision)
          fresh_check(packed, [value])
          fresh_check(bin_coeff_sqrt_scaled_rounded(value, scale, precision), [
            value, packed,
          ])
          match fresh_array_of(packed) {
            Some(_) => heap_results += 1
            None => ()
          }
        }
      }
    }
  }
  assert_true(heap_results > 50)
}

///|
// oracle: S
// source: physical_equal on the returned FixedArray against the arrays of the operands (an identity, not a value): a returned heap coefficient owns an array that no operand refers to; the numeric values of these producers are checked in the product, quotient and root blocks (level B)
// shares: the producer under test (bin_coeff_mul_short) and the helpers that build operands from limbs
test "short product returns an array that no operand refers to" {
  let mut heap_results = 0
  for limbs in [13, 14, 17, 32, 33, 50, 63] {
    for padding in [0, 3] {
      for seed in 1..<8 {
        let left = fresh_value(limbs, seed.to_uint64(), padding)
        let right = fresh_value(limbs, (seed * 5).to_uint64(), 0)
        let precision = limbs * 64
        if bin_coeff_mul_short_ok(left, right, precision) {
          let product = bin_coeff_mul_short(left, right, precision)
          fresh_check(product, [left, right])
          fresh_check(bin_coeff_mul_short(left, right, precision), [
            left, right, product,
          ])
          // the product of a value with itself
          fresh_check(bin_coeff_mul_short(left, left, precision), [left])
          match fresh_array_of(product) {
            Some(_) => heap_results += 1
            None => assert_true(product.is_zero())
          }
        }
      }
    }
  }
  assert_true(heap_results > 50)
}
