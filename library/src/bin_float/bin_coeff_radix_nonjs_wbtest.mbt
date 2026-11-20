///|
fn ref_small_chunk_string(
  value : UInt64,
  radix : Int32,
  minimum_width : Int32,
) -> String {
  let digits : Array[Char] = []
  let mut value = value
  if value == 0UL {
    digits.push('0')
  } else {
    while value != 0UL {
      digits.push(bin_coeff_digit_char((value % radix.to_uint64()).to_int()))
      value /= radix.to_uint64()
    }
  }
  let builder = StringBuilder()
  for _ in digits.length()..<minimum_width {
    builder.write_char('0')
  }
  let mut index = digits.length() - 1
  while true {
    builder.write_char(digits[index])
    if index == 0 {
      break
    }
    index -= 1
  }
  builder.to_string()
}

///|
/// Test-only reference: the chunk-by-chunk formatting of #324 through
/// `bin_coeff_div_rem_word`.
fn BinCoeff::ref_to_radix_small(self : BinCoeff, radix : Int32) -> String {
  if self.is_zero() {
    return "0"
  }
  let (chunk_width, chunk_power) = bin_coeff_radix_chunk(radix)
  let chunks : Array[UInt64] = []
  let mut remaining = self
  while !remaining.is_zero() {
    let (quotient, remainder) = bin_coeff_div_rem_word(remaining, chunk_power)
    chunks.push(remainder.to_uint64().unwrap())
    remaining = quotient
  }
  let builder = StringBuilder()
  let mut index = chunks.length() - 1
  while true {
    builder.write_string(
      ref_small_chunk_string(
        chunks[index],
        radix,
        if index == chunks.length() - 1 {
          1
        } else {
          chunk_width
        },
      ),
    )
    if index == 0 {
      break
    }
    index -= 1
  }
  builder.to_string()
}

///|
/// Test-only reference: the chunk-by-chunk parsing of #324 through
/// `bin_coeff_mul_small` (digits assumed valid).
fn ref_parse_small(source : String, radix : Int32) -> BinCoeff {
  let (chunk_width, chunk_power) = bin_coeff_radix_chunk(radix)
  let digit_count = source.length()
  let mut width = digit_count % chunk_width
  if width == 0 {
    width = chunk_width
  }
  let mut index = 0
  let mut value = BinCoeff::zero()
  while index < source.length() {
    let end = index + width
    let mut chunk = 0UL
    while index < end {
      let digit = bin_coeff_digit(source.unsafe_get(index).to_int())
      if digit < 0 || digit >= radix {
        abort("bad digit")
      }
      chunk = chunk * radix.to_uint64() + digit.to_uint64()
      index += 1
    }
    value = bin_coeff_mul_small(value, chunk_power).add(
      BinCoeff::from_uint64(chunk),
    )
    width = chunk_width
  }
  value
}

///|
fn radix_test_digits(radix : Int32) -> String {
  "0123456789abcdefghijklmnopqrstuvwxyz"[0:radix].to_owned()
}

///|
test "radix conversion in place equals the chunk-by-chunk reference around the cutoffs" {
  let random = { words_state: 0x6A6A_1F1F_C3C3_5E5EUL, }
  let sizes = [
    1, 2, 3, 5, 8, 9, 10, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129, 190, 191, 192,
    193, 255, 256, 257, 511, 512, 513,
  ]
  for radix in [3, 5, 7, 10, 12, 36] {
    for len in sizes {
      for pattern in [0, 1, 2, 4] {
        let value = bin_coeff_from_words(
          words_test_array(random, len, pattern),
          len,
        )
        let text = value.to_radix_string(radix)
        assert_eq(text, value.ref_to_radix_small(radix))
        assert_eq(BinCoeff::parse(text, radix~).unwrap(), value)
        assert_eq(ref_parse_small(text, radix), value)
      }
    }
  }
}

///|
test "radix conversion of powers of the radix and their neighbours at chunk edges" {
  // chunk widths: 9 digits for radix 10, 20 for radix 3, 6 for radix 36
  for radix in [3, 10, 36] {
    let (chunk_width, _) = bin_coeff_radix_chunk(radix)
    let one_digit = radix_test_digits(radix)
    let top = one_digit[radix - 1:radix].to_owned()
    for chunks in [1, 2, 3, 7, 31, 32, 33, 63, 64, 65, 66, 130] {
      for extra in [-1, 0, 1] {
        let digits = chunks * chunk_width + extra
        if digits <= 0 {
          continue
        }
        // radix^(digits - 1): a one followed by zeros
        let power_text = "1" + "0".repeat(digits - 1)
        let power = BinCoeff::parse(power_text, radix~).unwrap()
        assert_eq(power.to_radix_string(radix), power_text)
        // radix^digits - 1: all digits at their maximum
        let max_text = top.repeat(digits)
        let max_value = BinCoeff::parse(max_text, radix~).unwrap()
        assert_eq(max_value.to_radix_string(radix), max_text)
        assert_eq(
          max_value.add(BinCoeff::one()).to_radix_string(radix),
          "1" + "0".repeat(digits),
        )
      }
    }
  }
}

///|
test "radix parsing rejects a bad digit in any chunk" {
  for position in [0, 1, 8, 9, 10, 17, 18, 19, 500, 575, 576, 577, 700] {
    let text = "7".repeat(701)
    let broken = text[0:position].to_owned() +
      "a" +
      text[position + 1:].to_owned()
    assert_true(BinCoeff::parse(broken, radix=10) is Err(_))
    assert_true(BinCoeff::parse(text, radix=10) is Ok(_))
  }
  assert_eq(BinCoeff::parse("0", radix=10).unwrap(), BinCoeff::zero())
  assert_eq(
    BinCoeff::parse("0000000000000000000000", radix=10).unwrap(),
    BinCoeff::zero(),
  )
  assert_eq(
    BinCoeff::parse("+000000000000000000000012", radix=10).unwrap(),
    BinCoeff::from_uint64(12UL),
  )
}

///|
test "in-place and divide-and-conquer radix conversion agree on both sides of every cutoff" {
  let random = { words_state: 0x3B3B_71F1_0D0D_C5C5UL, }
  // 1 and 2 limbs, one chunk, around the old cutoffs (128 limbs, 64 chunks)
  // and well above them; the new cutoffs are above 65,536 bits
  for radix in [3, 10, 36] {
    let (chunk_width, chunk_power) = bin_coeff_radix_chunk(radix)
    for
      len in [
        1, 2, 3, 4, 5, 63, 64, 65, 66, 127, 128, 129, 255, 256, 257, 700, 1025,
      ] {
      for pattern in [0, 1, 2] {
        let value = bin_coeff_from_words(
          words_test_array(random, len, pattern),
          len,
        )
        let in_place = bin_coeff_to_radix_in_place(
          value, radix, chunk_width, chunk_power,
        )
        let divided = bin_coeff_to_radix_divide_and_conquer(
          value, radix, chunk_width, chunk_power,
        )
        assert_eq(in_place, divided)
        let chunks = bin_coeff_parse_radix_chunks(
          in_place, 0, radix, chunk_width,
        ).unwrap()
        assert_eq(bin_coeff_parse_chunks_in_place(chunks, chunk_power), value)
        assert_eq(
          bin_coeff_parse_chunks_divide_and_conquer(
            chunks,
            0,
            chunks.length(),
            chunk_power,
          ).value,
          value,
        )
      }
    }
  }
}
