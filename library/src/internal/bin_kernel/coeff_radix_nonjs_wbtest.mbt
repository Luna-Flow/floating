///|
fn radix_test_digits(radix : Int32) -> String {
  "0123456789abcdefghijklmnopqrstuvwxyz"[0:radix].to_owned()
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
        let power = Coeff::parse(power_text, radix~).unwrap()
        assert_eq(power.to_radix_string(radix), power_text)
        // radix^digits - 1: all digits at their maximum
        let max_text = top.repeat(digits)
        let max_value = Coeff::parse(max_text, radix~).unwrap()
        assert_eq(max_value.to_radix_string(radix), max_text)
        assert_eq(
          max_value.add(Coeff::one()).to_radix_string(radix),
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
    assert_true(Coeff::parse(broken, radix=10) is Err(_))
    assert_true(Coeff::parse(text, radix=10) is Ok(_))
  }
  assert_eq(Coeff::parse("0", radix=10).unwrap(), Coeff::zero())
  assert_eq(
    Coeff::parse("0000000000000000000000", radix=10).unwrap(),
    Coeff::zero(),
  )
  assert_eq(
    Coeff::parse("+000000000000000000000012", radix=10).unwrap(),
    Coeff::from_uint64(12UL),
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
