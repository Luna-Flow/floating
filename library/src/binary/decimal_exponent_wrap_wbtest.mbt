// Binary::from_string_ctx with an exponent field of 18 to 21 digits (issue #624, present in
// 0.11.0): the accumulated exponent wrapped in `Int64` when it was between `Int64::MAX / 10` and
// 2^60 before the next digit. The expected results are written out here, not read from another
// reader.

///|
test "from_string_ctx: exponent fields of 18 to 21 digits saturate, they do not wrap" {
  let digits = [
    "922337203685477580", "922337203685477581", "1000000000000000000", "1100000000000000000",
    "1152921504606846975", "1152921504606846976", "1152921504606846977", "9223372036854775807",
    "9223372036854775808", "11000000000000000000", "11529215046068469750", "18446744073709551616",
    "93000000000000000000", "999999999999999999999",
  ]
  let modes = [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
    BinaryRoundingMode::RoundTowardZero,
  ]
  for d in digits {
    for negative_exponent in [false, true] {
      for negative_value in [false, true] {
        for significand in ["1", "1.5", "0.001"] {
          let text = (if negative_value { "-" } else { "" }) +
            significand +
            "e" +
            (if negative_exponent { "-" } else { "" }) +
            d
          for mode_index in 0..<modes.length() {
            let mode = modes[mode_index]
            let context = BinaryContext::new(precision=53, rounding=mode)
            let (value, flags) = Binary::from_string_ctx(text, context).unwrap()
            let label = "\{text} mode \{mode_index}"
            if negative_exponent {
              assert_eq(e2s_flags(flags), "IU-", msg=label)
              let away = match mode {
                RoundTowardPositive => !negative_value
                RoundTowardNegative => negative_value
                _ => false
              }
              assert_eq(value.is_zero(), !away, msg=label)
              assert_eq(value.negative(), negative_value, msg=label)
            } else {
              assert_eq(e2s_flags(flags), "I-O", msg=label)
              let toward = match mode {
                RoundTowardZero => true
                RoundTowardPositive => negative_value
                RoundTowardNegative => !negative_value
                _ => false
              }
              assert_eq(value.is_infinite(), !toward, msg=label)
              assert_eq(value.negative(), negative_value, msg=label)
            }
          }
        }
      }
    }
  }
  // a zero significand is zero for every field
  for d in digits {
    let (value, flags) = Binary::from_string_ctx(
      "0e" + d,
      BinaryContext::binary64(),
    ).unwrap()
    assert_eq(value.is_zero(), true, msg=d)
    assert_eq(flags, BinaryFlags::new(), msg=d)
  }
}
