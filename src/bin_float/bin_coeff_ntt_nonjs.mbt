///|
let bin_coeff_ntt_prime1 = 998244353UL

///|
let bin_coeff_ntt_prime2 = 754974721UL

///|
let bin_coeff_ntt_root1 = 3UL

///|
let bin_coeff_ntt_root2 = 11UL

///|
let bin_coeff_ntt_nprime1 = 998244351UL

///|
let bin_coeff_ntt_nprime2 = 754974719UL

///|
let bin_coeff_ntt_r2_prime1 = 932051910UL

///|
let bin_coeff_ntt_r2_prime2 = 749009521UL

///|
let bin_coeff_ntt_r_prime1 = 301989884UL

///|
let bin_coeff_ntt_r_prime2 = 520093691UL

///|
let bin_coeff_ntt_crt_inverse = 416537774UL

///|
let bin_coeff_ntt_max_length : Int = 1 << 23

///|
fn bin_coeff_ntt_montgomery_mul(
  left : UInt64,
  right : UInt64,
  prime : UInt64,
  nprime : UInt64,
) -> UInt64 {
  let product = left * right
  let multiplier = ((product & 0xffff_ffffUL) * nprime) & 0xffff_ffffUL
  let reduced = (product + multiplier * prime) >> 32
  if reduced >= prime {
    reduced - prime
  } else {
    reduced
  }
}

///|
fn bin_coeff_ntt_to_montgomery(
  value : UInt64,
  prime : UInt64,
  nprime : UInt64,
  r2 : UInt64,
) -> UInt64 {
  bin_coeff_ntt_montgomery_mul(value, r2, prime, nprime)
}

///|
fn bin_coeff_ntt_from_montgomery(
  value : UInt64,
  prime : UInt64,
  nprime : UInt64,
) -> UInt64 {
  bin_coeff_ntt_montgomery_mul(value, 1UL, prime, nprime)
}

///|
fn bin_coeff_ntt_pow_montgomery(
  base : UInt64,
  exponent : UInt64,
  prime : UInt64,
  nprime : UInt64,
  montgomery_one : UInt64,
) -> UInt64 {
  let mut result = montgomery_one
  let mut factor = base
  let mut exponent = exponent
  while exponent != 0UL {
    if (exponent & 1UL) != 0UL {
      result = bin_coeff_ntt_montgomery_mul(result, factor, prime, nprime)
    }
    exponent = exponent >> 1
    if exponent != 0UL {
      factor = bin_coeff_ntt_montgomery_mul(factor, factor, prime, nprime)
    }
  }
  result
}

///|
fn bin_coeff_ntt_pow_normal(
  base : UInt64,
  exponent : UInt64,
  prime : UInt64,
  nprime : UInt64,
  r2 : UInt64,
  montgomery_one : UInt64,
) -> UInt64 {
  bin_coeff_ntt_from_montgomery(
    bin_coeff_ntt_pow_montgomery(
      bin_coeff_ntt_to_montgomery(base, prime, nprime, r2),
      exponent,
      prime,
      nprime,
      montgomery_one,
    ),
    prime,
    nprime,
  )
}

///|
fn bin_coeff_ntt_add(left : UInt64, right : UInt64, prime : UInt64) -> UInt64 {
  let sum = left + right
  if sum >= prime {
    sum - prime
  } else {
    sum
  }
}

///|
fn bin_coeff_ntt_sub(left : UInt64, right : UInt64, prime : UInt64) -> UInt64 {
  if left >= right {
    left - right
  } else {
    left + prime - right
  }
}

///|
fn bin_coeff_ntt_forward_dif(
  values : FixedArray[UInt],
  length : Int,
  prime : UInt64,
  primitive_root : UInt64,
  nprime : UInt64,
  r2 : UInt64,
  montgomery_one : UInt64,
) -> Unit {
  let root = bin_coeff_ntt_to_montgomery(primitive_root, prime, nprime, r2)
  let fourth_root = bin_coeff_ntt_pow_montgomery(
    root,
    (prime - 1UL) / 4UL,
    prime,
    nprime,
    montgomery_one,
  )
  let mut stage_length = length
  while stage_length >= 4 {
    let quarter = stage_length / 4
    let root_power = (prime - 1UL) / stage_length.to_uint64()
    let stage_root = bin_coeff_ntt_pow_montgomery(
      root, root_power, prime, nprime, montgomery_one,
    )
    let stage_root2 = bin_coeff_ntt_montgomery_mul(
      stage_root, stage_root, prime, nprime,
    )
    let stage_root3 = bin_coeff_ntt_montgomery_mul(
      stage_root2, stage_root, prime, nprime,
    )
    let mut block = 0
    while block < length {
      let mut twiddle1 = montgomery_one
      let mut twiddle2 = montgomery_one
      let mut twiddle3 = montgomery_one
      for offset in 0..<quarter {
        let index0 = block + offset
        let index1 = index0 + quarter
        let index2 = index1 + quarter
        let index3 = index2 + quarter
        let value0 = values.unsafe_get(index0).to_uint64()
        let value1 = values.unsafe_get(index1).to_uint64()
        let value2 = values.unsafe_get(index2).to_uint64()
        let value3 = values.unsafe_get(index3).to_uint64()
        let sum02 = bin_coeff_ntt_add(value0, value2, prime)
        let difference02 = bin_coeff_ntt_sub(value0, value2, prime)
        let sum13 = bin_coeff_ntt_add(value1, value3, prime)
        let difference13 = bin_coeff_ntt_montgomery_mul(
          bin_coeff_ntt_sub(value1, value3, prime),
          fourth_root,
          prime,
          nprime,
        )
        let output0 = bin_coeff_ntt_add(sum02, sum13, prime)
        let output1 = bin_coeff_ntt_add(difference02, difference13, prime)
        let output2 = bin_coeff_ntt_sub(sum02, sum13, prime)
        let output3 = bin_coeff_ntt_sub(difference02, difference13, prime)
        values.unsafe_set(index0, output0.to_uint())
        if offset == 0 {
          values.unsafe_set(index1, output1.to_uint())
          values.unsafe_set(index2, output2.to_uint())
          values.unsafe_set(index3, output3.to_uint())
        } else {
          values.unsafe_set(
            index1,
            bin_coeff_ntt_montgomery_mul(output1, twiddle1, prime, nprime).to_uint(),
          )
          values.unsafe_set(
            index2,
            bin_coeff_ntt_montgomery_mul(output2, twiddle2, prime, nprime).to_uint(),
          )
          values.unsafe_set(
            index3,
            bin_coeff_ntt_montgomery_mul(output3, twiddle3, prime, nprime).to_uint(),
          )
        }
        twiddle1 = bin_coeff_ntt_montgomery_mul(
          twiddle1, stage_root, prime, nprime,
        )
        twiddle2 = bin_coeff_ntt_montgomery_mul(
          twiddle2, stage_root2, prime, nprime,
        )
        twiddle3 = bin_coeff_ntt_montgomery_mul(
          twiddle3, stage_root3, prime, nprime,
        )
      }
      block += stage_length
    }
    stage_length = quarter
  }
  if stage_length == 2 {
    let mut block = 0
    while block < length {
      let left = values.unsafe_get(block).to_uint64()
      let right = values.unsafe_get(block + 1).to_uint64()
      values.unsafe_set(block, bin_coeff_ntt_add(left, right, prime).to_uint())
      values.unsafe_set(
        block + 1,
        bin_coeff_ntt_sub(left, right, prime).to_uint(),
      )
      block += 2
    }
  }
}

///|
fn bin_coeff_ntt_inverse_dit(
  values : FixedArray[UInt],
  length : Int,
  prime : UInt64,
  primitive_root : UInt64,
  nprime : UInt64,
  r2 : UInt64,
  montgomery_one : UInt64,
) -> Unit {
  let inverse_root_normal = bin_coeff_ntt_pow_normal(
    primitive_root,
    prime - 2UL,
    prime,
    nprime,
    r2,
    montgomery_one,
  )
  let inverse_root = bin_coeff_ntt_to_montgomery(
    inverse_root_normal, prime, nprime, r2,
  )
  let inverse_fourth_root = bin_coeff_ntt_pow_montgomery(
    inverse_root,
    (prime - 1UL) / 4UL,
    prime,
    nprime,
    montgomery_one,
  )
  let mut stage_length = if (length.ctz() & 1) == 0 { 4 } else { 2 }
  if stage_length == 2 {
    let mut block = 0
    while block < length {
      let left = values.unsafe_get(block).to_uint64()
      let right = values.unsafe_get(block + 1).to_uint64()
      values.unsafe_set(block, bin_coeff_ntt_add(left, right, prime).to_uint())
      values.unsafe_set(
        block + 1,
        bin_coeff_ntt_sub(left, right, prime).to_uint(),
      )
      block += 2
    }
    stage_length = 8
  }
  while stage_length <= length {
    let quarter = stage_length / 4
    let root_power = (prime - 1UL) / stage_length.to_uint64()
    let stage_root = bin_coeff_ntt_pow_montgomery(
      inverse_root, root_power, prime, nprime, montgomery_one,
    )
    let stage_root2 = bin_coeff_ntt_montgomery_mul(
      stage_root, stage_root, prime, nprime,
    )
    let stage_root3 = bin_coeff_ntt_montgomery_mul(
      stage_root2, stage_root, prime, nprime,
    )
    let mut block = 0
    while block < length {
      let mut twiddle1 = montgomery_one
      let mut twiddle2 = montgomery_one
      let mut twiddle3 = montgomery_one
      for offset in 0..<quarter {
        let index0 = block + offset
        let index1 = index0 + quarter
        let index2 = index1 + quarter
        let index3 = index2 + quarter
        let value0 = values.unsafe_get(index0).to_uint64()
        let mut value1 = values.unsafe_get(index1).to_uint64()
        let mut value2 = values.unsafe_get(index2).to_uint64()
        let mut value3 = values.unsafe_get(index3).to_uint64()
        if offset != 0 {
          value1 = bin_coeff_ntt_montgomery_mul(value1, twiddle1, prime, nprime)
          value2 = bin_coeff_ntt_montgomery_mul(value2, twiddle2, prime, nprime)
          value3 = bin_coeff_ntt_montgomery_mul(value3, twiddle3, prime, nprime)
        }
        let sum02 = bin_coeff_ntt_add(value0, value2, prime)
        let difference02 = bin_coeff_ntt_sub(value0, value2, prime)
        let sum13 = bin_coeff_ntt_add(value1, value3, prime)
        let difference13 = bin_coeff_ntt_montgomery_mul(
          bin_coeff_ntt_sub(value1, value3, prime),
          inverse_fourth_root,
          prime,
          nprime,
        )
        values.unsafe_set(
          index0,
          bin_coeff_ntt_add(sum02, sum13, prime).to_uint(),
        )
        values.unsafe_set(
          index1,
          bin_coeff_ntt_add(difference02, difference13, prime).to_uint(),
        )
        values.unsafe_set(
          index2,
          bin_coeff_ntt_sub(sum02, sum13, prime).to_uint(),
        )
        values.unsafe_set(
          index3,
          bin_coeff_ntt_sub(difference02, difference13, prime).to_uint(),
        )
        twiddle1 = bin_coeff_ntt_montgomery_mul(
          twiddle1, stage_root, prime, nprime,
        )
        twiddle2 = bin_coeff_ntt_montgomery_mul(
          twiddle2, stage_root2, prime, nprime,
        )
        twiddle3 = bin_coeff_ntt_montgomery_mul(
          twiddle3, stage_root3, prime, nprime,
        )
      }
      block += stage_length
    }
    stage_length *= 4
  }
  let inverse_length_normal = bin_coeff_ntt_pow_normal(
    length.to_uint64(),
    prime - 2UL,
    prime,
    nprime,
    r2,
    montgomery_one,
  )
  let inverse_length = bin_coeff_ntt_to_montgomery(
    inverse_length_normal, prime, nprime, r2,
  )
  for index in 0..<length {
    values.unsafe_set(
      index,
      bin_coeff_ntt_montgomery_mul(
        values.unsafe_get(index).to_uint64(),
        inverse_length,
        prime,
        nprime,
      ).to_uint(),
    )
  }
}

///|
fn bin_coeff_ntt_digit_length(value : BinCoeff) -> Int {
  (value.bit_length() + 15) / 16
}

///|
fn bin_coeff_ntt_transform_length(coefficient_count : Int) -> Int {
  let mut length = 1
  while length < coefficient_count {
    length *= 2
  }
  length
}

///|
fn bin_coeff_ntt_fill(
  destination : FixedArray[UInt],
  value : BinCoeff,
  digit_length : Int,
  prime : UInt64,
  nprime : UInt64,
  r2 : UInt64,
) -> Unit {
  for index in 0..<digit_length {
    let limb = bin_coeff_limb(value, index / 2)
    let digit = if (index & 1) == 0 { limb & 0xffffU } else { limb >> 16 }
    destination.unsafe_set(
      index,
      bin_coeff_ntt_to_montgomery(digit.to_uint64(), prime, nprime, r2).to_uint(),
    )
  }
}

///|
fn bin_coeff_ntt_convolution_mod(
  left : BinCoeff,
  right : BinCoeff,
  square : Bool,
  transform_length : Int,
  coefficient_count : Int,
  prime : UInt64,
  primitive_root : UInt64,
  nprime : UInt64,
  r2 : UInt64,
  montgomery_one : UInt64,
) -> FixedArray[UInt] {
  let left_values = FixedArray::make(transform_length, 0U)
  bin_coeff_ntt_fill(
    left_values,
    left,
    bin_coeff_ntt_digit_length(left),
    prime,
    nprime,
    r2,
  )
  bin_coeff_ntt_forward_dif(
    left_values, transform_length, prime, primitive_root, nprime, r2, montgomery_one,
  )
  if square {
    for index in 0..<transform_length {
      let value = left_values.unsafe_get(index).to_uint64()
      left_values.unsafe_set(
        index,
        bin_coeff_ntt_montgomery_mul(value, value, prime, nprime).to_uint(),
      )
    }
  } else {
    let right_values = FixedArray::make(transform_length, 0U)
    bin_coeff_ntt_fill(
      right_values,
      right,
      bin_coeff_ntt_digit_length(right),
      prime,
      nprime,
      r2,
    )
    bin_coeff_ntt_forward_dif(
      right_values, transform_length, prime, primitive_root, nprime, r2, montgomery_one,
    )
    for index in 0..<transform_length {
      left_values.unsafe_set(
        index,
        bin_coeff_ntt_montgomery_mul(
          left_values.unsafe_get(index).to_uint64(),
          right_values.unsafe_get(index).to_uint64(),
          prime,
          nprime,
        ).to_uint(),
      )
    }
  }
  bin_coeff_ntt_inverse_dit(
    left_values, transform_length, prime, primitive_root, nprime, r2, montgomery_one,
  )
  let result = FixedArray::make(coefficient_count, 0U)
  for index in 0..<coefficient_count {
    result.unsafe_set(
      index,
      bin_coeff_ntt_from_montgomery(
        left_values.unsafe_get(index).to_uint64(),
        prime,
        nprime,
      ).to_uint(),
    )
  }
  result
}

///|
fn bin_coeff_ntt_crt(residue1 : UInt64, residue2 : UInt64) -> UInt64 {
  let residue1_mod_prime2 = if residue1 >= bin_coeff_ntt_prime2 {
    residue1 - bin_coeff_ntt_prime2
  } else {
    residue1
  }
  let difference = if residue2 >= residue1_mod_prime2 {
    residue2 - residue1_mod_prime2
  } else {
    residue2 + bin_coeff_ntt_prime2 - residue1_mod_prime2
  }
  let inverse_montgomery = bin_coeff_ntt_to_montgomery(
    bin_coeff_ntt_crt_inverse, bin_coeff_ntt_prime2, bin_coeff_ntt_nprime2, bin_coeff_ntt_r2_prime2,
  )
  let multiplier = bin_coeff_ntt_from_montgomery(
    bin_coeff_ntt_montgomery_mul(
      bin_coeff_ntt_to_montgomery(
        difference, bin_coeff_ntt_prime2, bin_coeff_ntt_nprime2, bin_coeff_ntt_r2_prime2,
      ),
      inverse_montgomery,
      bin_coeff_ntt_prime2,
      bin_coeff_ntt_nprime2,
    ),
    bin_coeff_ntt_prime2,
    bin_coeff_ntt_nprime2,
  )
  residue1 + bin_coeff_ntt_prime1 * multiplier
}

///|
fn bin_coeff_ntt_reconstruct(
  residues1 : FixedArray[UInt],
  residues2 : FixedArray[UInt],
  coefficient_count : Int,
  maximum_limbs : Int,
) -> BinCoeff {
  let limbs = FixedArray::make(maximum_limbs + 1, 0U)
  let mut carry = 0UL
  let mut digit_index = 0
  for index in 0..<coefficient_count {
    let coefficient = bin_coeff_ntt_crt(
      residues1.unsafe_get(index).to_uint64(),
      residues2.unsafe_get(index).to_uint64(),
    )
    let accumulated = coefficient + carry
    let digit = (accumulated & 0xffffUL).to_uint()
    let limb_index = digit_index / 2
    let shift = (digit_index & 1) * 16
    limbs.unsafe_set(
      limb_index,
      limbs.unsafe_get(limb_index) | (digit << shift),
    )
    digit_index += 1
    carry = accumulated >> 16
  }
  while carry != 0UL {
    let digit = (carry & 0xffffUL).to_uint()
    let limb_index = digit_index / 2
    let shift = (digit_index & 1) * 16
    limbs.unsafe_set(
      limb_index,
      limbs.unsafe_get(limb_index) | (digit << shift),
    )
    digit_index += 1
    carry = carry >> 16
  }
  bin_coeff_from_limbs(limbs, (digit_index + 1) / 2)
}

///|
fn bin_coeff_ntt_fits(left : BinCoeff, right : BinCoeff) -> Bool {
  let coefficient_count = bin_coeff_ntt_digit_length(left) +
    bin_coeff_ntt_digit_length(right) -
    1
  bin_coeff_ntt_transform_length(coefficient_count) <= bin_coeff_ntt_max_length
}

///|
fn bin_coeff_ntt_overlap_possible(shorter : BinCoeff) -> Bool {
  bin_coeff_ntt_digit_length(shorter) <= bin_coeff_ntt_max_length / 2
}

///|
fn bin_coeff_ntt_product(
  left : BinCoeff,
  right : BinCoeff,
  square : Bool,
) -> BinCoeff {
  let coefficient_count = bin_coeff_ntt_digit_length(left) +
    bin_coeff_ntt_digit_length(right) -
    1
  let transform_length = bin_coeff_ntt_transform_length(coefficient_count)
  let residues1 = bin_coeff_ntt_convolution_mod(
    left, right, square, transform_length, coefficient_count, bin_coeff_ntt_prime1,
    bin_coeff_ntt_root1, bin_coeff_ntt_nprime1, bin_coeff_ntt_r2_prime1, bin_coeff_ntt_r_prime1,
  )
  let residues2 = bin_coeff_ntt_convolution_mod(
    left, right, square, transform_length, coefficient_count, bin_coeff_ntt_prime2,
    bin_coeff_ntt_root2, bin_coeff_ntt_nprime2, bin_coeff_ntt_r2_prime2, bin_coeff_ntt_r_prime2,
  )
  bin_coeff_ntt_reconstruct(
    residues1,
    residues2,
    coefficient_count,
    bin_coeff_limb_len(left) + bin_coeff_limb_len(right),
  )
}

///|
fn bin_coeff_mul_ntt(left : BinCoeff, right : BinCoeff) -> BinCoeff {
  bin_coeff_ntt_product(left, right, false)
}

///|
fn bin_coeff_square_ntt(value : BinCoeff) -> BinCoeff {
  bin_coeff_ntt_product(value, value, true)
}

///|
fn bin_coeff_mul_ntt_overlap(shorter : BinCoeff, longer : BinCoeff) -> BinCoeff {
  let shorter_digits = bin_coeff_ntt_digit_length(shorter)
  let block_digits = bin_coeff_ntt_max_length - shorter_digits + 1
  let block_limbs = Int::max(1, block_digits / 2)
  let longer_limbs = bin_coeff_limb_len(longer)
  let output_len = bin_coeff_limb_len(shorter) + longer_limbs
  let result = FixedArray::make(output_len, 0U)
  let mut start = 0
  while start < longer_limbs {
    let block = bin_coeff_slice(longer, start, block_limbs)
    let product = bin_coeff_ntt_product(shorter, block, false)
    bin_coeff_add_shifted_into(result, output_len, product, start)
    start += block_limbs
  }
  bin_coeff_from_limbs(result, output_len)
}
