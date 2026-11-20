///|
// Differential test of the schoolbook product against the previous
// implementation (`dec_coeff_limb_at` per multiply-add in the small branch,
// wide accumulators converted afterwards in the large one), kept here as
// private reference code; compared bit for bit, representation included.

///|
let mul_diff_cases : Int32 = 300

///|
let mul_diff_cases_large : Int32 = 300

///|
fn dec_coeff_pack_wide(coeff : DecCoeff) -> Array[UInt64] {
  let wide_len = dec_coeff_unit_len(coeff)
  let packed = Array::make(wide_len, 0UL)
  for wide_index in 0..<wide_len {
    packed[wide_index] = dec_coeff_limb_at(coeff, wide_index).to_uint64()
  }
  packed
}

///|
fn reference_mul_schoolbook(lhs : DecCoeff, rhs : DecCoeff) -> DecCoeff {
  if lhs.is_zero() || rhs.is_zero() {
    return dec_coeff_zero()
  }
  let lhs_len = dec_coeff_unit_len(lhs)
  let rhs_len = dec_coeff_unit_len(rhs)
  let lhs_wide_len = lhs_len
  let rhs_wide_len = rhs_len
  if Int32::min(lhs_wide_len, rhs_wide_len) <= 18 {
    let result = Array::make(lhs_wide_len + rhs_wide_len + 1, 0U)
    let columns = lhs_wide_len + rhs_wide_len - 1
    let mut carry = 0UL
    for column in 0..<columns {
      let lhs_start = Int32::max(0, column - (rhs_wide_len - 1))
      let lhs_end = Int32::min(lhs_wide_len - 1, column)
      let mut current = carry
      for lhs_index in lhs_start..<=lhs_end {
        let rhs_index = column - lhs_index
        current += dec_coeff_limb_at(lhs, lhs_index).to_uint64() *
          dec_coeff_limb_at(rhs, rhs_index).to_uint64()
      }
      dec_coeff_write_wide_unit(result, column, current % dec_coeff_wide_base)
      carry = current / dec_coeff_wide_base
    }
    let mut column = columns
    while carry != 0UL {
      dec_coeff_write_wide_unit(result, column, carry % dec_coeff_wide_base)
      carry = carry / dec_coeff_wide_base
      column += 1
    }
    return dec_coeff_from_unit_accumulator(result, result.length())
  }
  let lhs_wide = dec_coeff_pack_wide(lhs)
  let rhs_wide = dec_coeff_pack_wide(rhs)
  let acc = Array::make(lhs_wide_len + rhs_wide_len + 1, 0UL)
  for rhs_index in 0..<rhs_wide.length() {
    let multiplier = rhs_wide[rhs_index]
    let mut carry = 0UL
    for lhs_index in 0..<lhs_wide.length() {
      let acc_index = lhs_index + rhs_index
      let current = acc[acc_index] + lhs_wide[lhs_index] * multiplier + carry
      acc[acc_index] = current % dec_coeff_wide_base
      carry = current / dec_coeff_wide_base
    }
    let mut acc_index = lhs_wide.length() + rhs_index
    while carry != 0UL {
      let current = acc[acc_index] + carry
      acc[acc_index] = current % dec_coeff_wide_base
      carry = current / dec_coeff_wide_base
      acc_index += 1
    }
  }
  let mut acc_len = acc.length()
  while acc_len > 1 && acc[acc_len - 1] == 0UL {
    acc_len -= 1
  }
  dec_coeff_from_wide_accumulator(acc, acc_len)
}

///|
fn mul_diff_class(
  left_limbs : Int32,
  right_limbs : Int32,
  seed : UInt64,
) -> Unit raise {
  let state = Ref(seed)
  let cases = if left_limbs >= 40 {
    mul_diff_cases_large
  } else {
    mul_diff_cases
  }
  for iteration in 0..<cases {
    let nines = (iteration % 4).to_uint64() * 3UL
    let left = round_diff_value(state, left_limbs, nines)
    let right = round_diff_value(state, right_limbs, nines)
    let actual = dec_coeff_mul_schoolbook(left, right)
    let expected = reference_mul_schoolbook(left, right)
    if !sqrt_diff_same(actual, expected) {
      fail(
        "schoolbook product differs for \{left.to_string()} * \{right.to_string()}",
      )
    }
    let squared = dec_coeff_mul_schoolbook(left, left)
    if !sqrt_diff_same(squared, reference_mul_schoolbook(left, left)) {
      fail("schoolbook square differs for \{left.to_string()}")
    }
  }
}

///|
test "schoolbook product equals the reference, 1 and 2 limbs" {
  mul_diff_class(1, 1, 0x9E3779B97F4A7C15UL)
  mul_diff_class(1, 2, 0xD1B54A32D192ED03UL)
  mul_diff_class(2, 2, 0x2545F4914F6CDD1DUL)
}

///|
test "schoolbook product equals the reference, 3 to 12 limbs" {
  mul_diff_class(3, 3, 0x94D049BB133111EBUL)
  mul_diff_class(4, 4, 0xBF58476D1CE4E5B9UL)
  mul_diff_class(6, 3, 0x6A09E667F3BCC909UL)
  mul_diff_class(12, 12, 0xBB67AE8584CAA73BUL)
}

///|
test "schoolbook product equals the reference around the column limit of 18 limbs" {
  mul_diff_class(17, 17, 0x3C6EF372FE94F82BUL)
  mul_diff_class(18, 18, 0xA54FF53A5F1D36F1UL)
  mul_diff_class(19, 18, 0x510E527FADE682D1UL)
  mul_diff_class(19, 19, 0x9B05688C2B3E6C1FUL)
  mul_diff_class(40, 18, 0x1F83D9ABFB41BD6BUL)
}

///|
test "schoolbook product equals the reference, 56 and 112 limbs" {
  mul_diff_class(56, 56, 0x5BE0CD19137E2179UL)
  mul_diff_class(112, 112, 0xCBBB9D5DC1059ED8UL)
  mul_diff_class(112, 20, 0x629A292A367CD507UL)
}
