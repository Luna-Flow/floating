///|
/// `limbs += product * 2^(32 * offset)` for a two-limb product (the carry
/// propagates up through `len`).
fn bin_coeff_limb32_add_product_at(
  limbs : FixedArray[UInt32],
  len : Int32,
  offset : Int32,
  product : UInt64,
) -> Unit {
  let low_sum = limbs.unsafe_get(offset).to_uint64() +
    (product & bin_coeff_limb_mask)
  limbs.unsafe_set(offset, (low_sum & bin_coeff_limb_mask).to_uint())
  let high_sum = limbs.unsafe_get(offset + 1).to_uint64() +
    (product >> 32) +
    (low_sum >> 32)
  limbs.unsafe_set(offset + 1, (high_sum & bin_coeff_limb_mask).to_uint())
  let mut carry = high_sum >> 32
  let mut index = offset + 2
  while carry != 0UL && index < len {
    let sum = limbs.unsafe_get(index).to_uint64() + carry
    limbs.unsafe_set(index, (sum & bin_coeff_limb_mask).to_uint())
    carry = sum >> 32
    index += 1
  }
  guard carry == 0UL else { abort("BinCoeff square carry exceeded its output") }
}

///|
/// Square of a heap value by the half-product schoolbook method on 32-bit
/// limbs (the cross products once, doubled, plus the diagonal squares), the
/// Wasm counterpart of `bin_coeff_square_schoolbook`.
fn bin_coeff_square_limb32(value : BinCoeff) -> BinCoeff {
  match value.repr {
    Heap(words, word_len) => {
      let source = bin_coeff_limb32_unpack(words, word_len)
      let source_len = 2 * word_len
      let output_len = 2 * source_len
      let limbs = FixedArray::make(output_len, 0U)
      for left_index in 0..<source_len {
        let left_limb = source.unsafe_get(left_index).to_uint64()
        let mut carry = 0UL
        for right_index in (left_index + 1)..<source_len {
          let offset = left_index + right_index
          let product = limbs.unsafe_get(offset).to_uint64() +
            left_limb * source.unsafe_get(right_index).to_uint64() +
            carry
          limbs.unsafe_set(offset, (product & bin_coeff_limb_mask).to_uint())
          carry = product >> 32
        }
        if carry != 0UL {
          let mut index = left_index + source_len
          let mut running = carry
          while running != 0UL && index < output_len {
            let sum = limbs.unsafe_get(index).to_uint64() + running
            limbs.unsafe_set(index, (sum & bin_coeff_limb_mask).to_uint())
            running = sum >> 32
            index += 1
          }
        }
      }
      let mut double_carry = 0UL
      for index in 0..<output_len {
        let doubled = limbs.unsafe_get(index).to_uint64() * 2UL + double_carry
        limbs.unsafe_set(index, (doubled & bin_coeff_limb_mask).to_uint())
        double_carry = doubled >> 32
      }
      guard double_carry == 0UL else {
        abort("BinCoeff square doubling exceeded its output")
      }
      for index in 0..<source_len {
        let limb = source.unsafe_get(index).to_uint64()
        bin_coeff_limb32_add_product_at(
          limbs,
          output_len,
          index * 2,
          limb * limb,
        )
      }
      bin_coeff_from_limbs(limbs, output_len)
    }
    _ => value.mul(value)
  }
}
