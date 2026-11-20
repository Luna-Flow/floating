///|
/// Radix conversion kernels (issue #19, stage 4): the chunk loops of
/// `BinCoeff::parse` and `BinCoeff::to_radix_string` below the divide-and-conquer
/// cutoffs work in place on one 64-bit limb array, two 32-bit halves per limb
/// and one 64 by 32 bit division or multiplication per half, instead of
/// allocating a `BinCoeff` for every chunk through the 32-bit accessors.

///|
/// `words[0 ..< len] /= divisor` in place for `0 < divisor < 2^32`; the
/// remainder.
fn bin_coeff_words_div_small_in_place(
  words : FixedArray[UInt64],
  len : Int32,
  divisor : UInt64,
) -> UInt64 {
  let mut remainder = 0UL
  let mut index = len - 1
  while index >= 0 {
    let word = words.unsafe_get(index)
    let high = (remainder << 32) | (word >> 32)
    let high_quotient = high / divisor
    remainder = high - high_quotient * divisor
    let low = (remainder << 32) | (word & bin_coeff_limb_mask)
    let low_quotient = low / divisor
    remainder = low - low_quotient * divisor
    words.unsafe_set(index, (high_quotient << 32) | low_quotient)
    index -= 1
  }
  remainder
}

///|
/// `words[0 ..< len] = words[0 ..< len] * multiplier + addend` in place for
/// `multiplier < 2^32` and `addend < 2^32`; the new length (the array has room
/// for one more limb).
fn bin_coeff_words_mul_add_small_in_place(
  words : FixedArray[UInt64],
  len : Int32,
  multiplier : UInt64,
  addend : UInt64,
) -> Int32 {
  let mut carry = addend
  for index in 0..<len {
    let word = words.unsafe_get(index)
    let low = (word & bin_coeff_limb_mask) * multiplier + carry
    let high = (word >> 32) * multiplier + (low >> 32)
    words.unsafe_set(index, (high << 32) | (low & bin_coeff_limb_mask))
    carry = high >> 32
  }
  if carry != 0UL {
    words.unsafe_set(len, carry)
    len + 1
  } else {
    len
  }
}

///|
/// Writes `value` (below `radix^width`) in `radix`: `width` digits when
/// `padded`, no leading zeros otherwise (and `0` for zero). `digits` is a
/// scratch array of `width` entries.
fn bin_coeff_write_chunk(
  builder : StringBuilder,
  value : UInt64,
  radix : Int32,
  width : Int32,
  padded : Bool,
  digits : FixedArray[Int32],
) -> Unit {
  let radix64 = radix.to_uint64()
  let mut position = width
  let mut rest = value
  while rest != 0UL {
    position -= 1
    let quotient = rest / radix64
    digits.unsafe_set(position, (rest - quotient * radix64).to_int())
    rest = quotient
  }
  let mut start = if padded { 0 } else { position }
  if !padded && position == width {
    // zero without padding is one digit
    start = width - 1
    digits.unsafe_set(start, 0)
  }
  for index in start..<width {
    if index < position {
      builder.write_char('0')
    } else {
      builder.write_char(bin_coeff_digit_char(digits.unsafe_get(index)))
    }
  }
}

///|
/// The digits of `source[start ..]` as chunks of `chunk_width` digits (the
/// first one shorter when the count is not a multiple), most significant
/// first, each below `radix^chunk_width` < 2^32.
fn bin_coeff_parse_radix_chunks(
  source : String,
  start : Int32,
  radix : Int32,
  chunk_width : Int32,
) -> Result[FixedArray[UInt32], String] {
  let digit_count = source.length() - start
  let chunk_count = (digit_count + chunk_width - 1) / chunk_width
  let chunks = FixedArray::make(chunk_count, 0U)
  let mut width = digit_count % chunk_width
  if width == 0 {
    width = chunk_width
  }
  let mut index = start
  for chunk_index in 0..<chunk_count {
    let end = index + width
    let mut chunk = 0UL
    while index < end {
      let digit = bin_coeff_digit(source.unsafe_get(index).to_int())
      if digit < 0 || digit >= radix {
        return Err("BinCoeff contains a digit outside the selected radix")
      }
      chunk = chunk * radix.to_uint64() + digit.to_uint64()
      index += 1
    }
    chunks.unsafe_set(chunk_index, chunk.to_uint())
    width = chunk_width
  }
  Ok(chunks)
}

///|
/// The value of the chunks (most significant first) by accumulating
/// `value * chunk_power + chunk` in place on one limb array.
fn bin_coeff_parse_chunks_in_place(
  chunks : FixedArray[UInt32],
  chunk_power : UInt32,
) -> BinCoeff {
  // each chunk adds at most 32 bits
  let words = FixedArray::make(chunks.length() / 2 + 2, 0UL)
  let mut len = 0
  for index in 0..<chunks.length() {
    len = bin_coeff_words_mul_add_small_in_place(
      words,
      len,
      chunk_power.to_uint64(),
      chunks.unsafe_get(index).to_uint64(),
    )
  }
  bin_coeff_from_words(words, Int32::max(len, 1))
}

///|
/// `value` in `radix` (not a power of two) by dividing a copy of its limbs by
/// the chunk power in place, one chunk of digits per pass.
fn bin_coeff_to_radix_in_place(
  value : BinCoeff,
  radix : Int32,
  chunk_width : Int32,
  chunk_power : UInt32,
) -> String {
  let word_len = bin_coeff_word_len(value)
  let words = FixedArray::make(word_len, 0UL)
  for index in 0..<word_len {
    words.unsafe_set(index, bin_coeff_word(value, index))
  }
  let chunks : Array[UInt32] = []
  let mut len = word_len
  while len > 0 {
    let remainder = bin_coeff_words_div_small_in_place(
      words,
      len,
      chunk_power.to_uint64(),
    )
    chunks.push(remainder.to_uint())
    while len > 0 && words.unsafe_get(len - 1) == 0UL {
      len -= 1
    }
  }
  let builder = StringBuilder()
  let digits = FixedArray::make(chunk_width, 0)
  let mut index = chunks.length() - 1
  while index >= 0 {
    bin_coeff_write_chunk(
      builder,
      chunks[index].to_uint64(),
      radix,
      chunk_width,
      index != chunks.length() - 1,
      digits,
    )
    index -= 1
  }
  builder.to_string()
}

///|
/// `value` in `radix` (not a power of two) by divide and conquer on the
/// squares of the chunk power.
fn bin_coeff_to_radix_divide_and_conquer(
  value : BinCoeff,
  radix : Int32,
  chunk_width : Int32,
  chunk_power : UInt32,
) -> String {
  let powers : Array[BinCoeff] = [
    BinCoeff::from_uint64(chunk_power.to_uint64()),
  ]
  while value.compare(powers[powers.length() - 1]) >= 0 {
    powers.push(powers[powers.length() - 1].square())
  }
  let chunks : Array[UInt64] = []
  bin_coeff_format_chunks_divide_and_conquer(
    value,
    powers,
    powers.length() - 1,
    false,
    chunks,
  )
  let builder = StringBuilder()
  let digits = FixedArray::make(chunk_width, 0)
  for index in 0..<chunks.length() {
    bin_coeff_write_chunk(
      builder,
      chunks[index],
      radix,
      chunk_width,
      index != 0,
      digits,
    )
  }
  builder.to_string()
}
