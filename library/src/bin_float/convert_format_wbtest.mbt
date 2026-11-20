// BinFloat::convert_format (IEEE Std 754-2019 5.4.2 formatOf-convertFormat, 6.2.3).
//
// 5.4.2: "If the conversion is to a format in a different radix or to a narrower
// precision in the same radix, the result shall be rounded as specified in
// Clause 4. Conversion to a format with the same radix but wider precision and
// range is always exact." and "A formatOf-convertFormat operation with identical
// source and destination formats is a canonicalizing operation that signals the
// invalid operation exception for signaling NaN operands".
// 6.2.3: "Conversion of a quiet NaN from a narrower format to a wider format in
// the same radix, and then back to the same narrower format, should not change
// the quiet NaN payload in any way except to make it canonical."
//
// The independent oracle for finite values and flags is the TestFloat 3e gate
// (all twelve format pairs, five rounding modes, both tininess rules); the rows
// below are the cases a reader can check by hand.

///|
fn cf_value(bits : String, format : BinaryInterchangeFormat) -> BinFloat {
  BinaryInterchange::from_hex(bits, format).unwrap().to_bin_float()
}

///|
fn cf_formats() -> Array[BinaryInterchangeFormat] {
  [
    BinaryInterchangeFormat::Binary16,
    BinaryInterchangeFormat::Binary32,
    BinaryInterchangeFormat::Binary64,
    BinaryInterchangeFormat::Binary128,
  ]
}

///|
test "convert_format: a wider destination is exact and raises nothing" {
  // binary16 1.5 and the smallest binary16 subnormal 2^-24 into every wider format.
  let one_and_half = cf_value("3E00", BinaryInterchangeFormat::Binary16)
  let tiny = cf_value("0001", BinaryInterchangeFormat::Binary16)
  for
    format in [
      BinaryInterchangeFormat::Binary32,
      BinaryInterchangeFormat::Binary64,
      BinaryInterchangeFormat::Binary128,
    ] {
    for mode in e2s_modes() {
      let (a, a_flags) = one_and_half.convert_format(format, rounding=mode)
      assert_eq(a.to_hex(), "0x3p-1")
      assert_eq(a.precision(), format.precision())
      assert_eq(a_flags, BinaryFlags::new())
      let (b, b_flags) = tiny.convert_format(format, rounding=mode)
      assert_eq(b.to_hex(), "0x1p-24")
      assert_eq(b_flags, BinaryFlags::new())
    }
  }
}

///|
test "convert_format: binary64 to binary32 rounds, with inexact" {
  // 0.1 in binary64 is 0x3FB999999999999A; in binary32 it is 13421773p-27 (RNE).
  let tenth = cf_value("3FB999999999999A", BinaryInterchangeFormat::Binary64)
  let (rne, rne_flags) = tenth.convert_format(BinaryInterchangeFormat::Binary32)
  assert_eq(rne.to_hex(), "0xcccccdp-27")
  assert_eq(e2s_flags(rne_flags), "I--")
  let (rtz, _) = tenth.convert_format(
    BinaryInterchangeFormat::Binary32,
    rounding=BinaryRoundingMode::RoundTowardZero,
  )
  assert_eq(rtz.to_hex(), "0x333333p-25")
  let (rtp, _) = tenth.convert_format(
    BinaryInterchangeFormat::Binary32,
    rounding=BinaryRoundingMode::RoundTowardPositive,
  )
  assert_eq(rtp.to_hex(), "0xcccccdp-27")
  let (rtn, _) = tenth
    .neg()
    .convert_format(
      BinaryInterchangeFormat::Binary32,
      rounding=BinaryRoundingMode::RoundTowardNegative,
    )
  assert_eq(rtn.to_hex(), "-0xcccccdp-27")
}

///|
test "convert_format: overflow and underflow of binary32 in every direction" {
  let b32 = BinaryInterchangeFormat::Binary32
  // 2^128 is the first power of two above the largest binary32 number.
  let big = BinFloat::make_coeff(Coeff::one(), 128, 64)
  let (rne, rne_flags) = big.convert_format(b32)
  assert_eq(rne.classify() == FpClass::Infinity, true)
  assert_eq(e2s_flags(rne_flags), "I-O")
  let (rtz, rtz_flags) = big.convert_format(
    b32,
    rounding=BinaryRoundingMode::RoundTowardZero,
  )
  assert_eq(rtz.to_hex(), "0xffffffp104")
  assert_eq(e2s_flags(rtz_flags), "I-O")
  // 2^-150 is half of the smallest binary32 subnormal 2^-149: a tie that goes to zero.
  let small = BinFloat::make_coeff(Coeff::one(), -150, 64)
  let (zero, zero_flags) = small.convert_format(b32)
  assert_eq(zero.is_zero(), true)
  assert_eq(e2s_flags(zero_flags), "IU-")
  let (up, up_flags) = small.convert_format(
    b32,
    rounding=BinaryRoundingMode::RoundTowardPositive,
  )
  assert_eq(up.to_hex(), "0x1p-149")
  assert_eq(e2s_flags(up_flags), "IU-")
  // the smallest subnormal itself is exact
  let (exact, exact_flags) = BinFloat::make_coeff(Coeff::one(), -149, 64).convert_format(
    b32,
  )
  assert_eq(exact.to_hex(), "0x1p-149")
  assert_eq(exact_flags, BinaryFlags::new())
}

///|
test "convert_format: the tininess rule changes underflow at the boundary" {
  // The binary32 value just below 2^-126 that rounds up to 2^-126: tiny before
  // rounding, not tiny after rounding (7.5).
  let b32 = BinaryInterchangeFormat::Binary32
  let value = BinFloat::make_coeff(
    Coeff::one().shift_left(25).sub_checked(Coeff::one()).unwrap(),
    -151,
    64,
  )
  // (2^25 - 1) * 2^-151 = 2^-126 - 2^-151: between 2^-126 - 2^-149 and 2^-126
  let (before, before_flags) = value.convert_format(
    b32,
    tininess=TininessDetection::BeforeRounding,
  )
  let (after, after_flags) = value.convert_format(
    b32,
    tininess=TininessDetection::AfterRounding,
  )
  assert_eq(before.to_hex(), after.to_hex())
  assert_eq(e2s_flags(before_flags), "IU-")
  assert_eq(e2s_flags(after_flags), "I--")
}

///|
test "convert_format: signaling NaN is quieted with invalid, also to the same format" {
  // binary64 sNaN with payload 1 and the sign bit set.
  let snan = cf_value("FFF0000000000001", BinaryInterchangeFormat::Binary64)
  assert_eq(snan.is_signaling_nan(), true)
  for format in cf_formats() {
    let (value, flags) = snan.convert_format(format)
    assert_eq(value.is_quiet_nan(), true)
    assert_eq(value.is_negative(), true)
    assert_eq(flags.invalid_operation(), true)
    assert_eq(e2s_flags(flags), "---")
  }
  // a quiet NaN raises nothing
  let qnan = cf_value("7FF8000000000001", BinaryInterchangeFormat::Binary64)
  let (value, flags) = qnan.convert_format(BinaryInterchangeFormat::Binary32)
  assert_eq(value.is_quiet_nan(), true)
  assert_eq(flags, BinaryFlags::new())
}

///|
test "convert_format: NaN payloads (6.2.3)" {
  // narrower to wider and back keeps the payload.
  let narrow = cf_value("7E01", BinaryInterchangeFormat::Binary16) // qNaN, payload 1
  for
    wider in [
      BinaryInterchangeFormat::Binary32,
      BinaryInterchangeFormat::Binary64,
      BinaryInterchangeFormat::Binary128,
    ] {
    let (up, _) = narrow.convert_format(wider)
    let (back, _) = up.convert_format(BinaryInterchangeFormat::Binary16)
    assert_eq(
      back.nan_payload_coeff().to_radix_string(16),
      narrow.nan_payload_coeff().to_radix_string(16),
    )
    assert_eq(
      BinaryInterchange::from_bin_float(back, BinaryInterchangeFormat::Binary16).0.to_hex(),
      "7E01",
    )
  }
  // a payload that does not fit keeps its low bits and stays a quiet NaN
  let wide = cf_value("7FF8000000FFFFFF", BinaryInterchangeFormat::Binary64)
  let (narrowed, _) = wide.convert_format(BinaryInterchangeFormat::Binary32)
  assert_eq(narrowed.is_quiet_nan(), true)
  assert_eq(
    BinaryInterchange::from_bin_float(
      narrowed,
      BinaryInterchangeFormat::Binary32,
    ).0.to_hex(),
    "7FFFFFFF",
  )
}

///|
test "convert_format returns the value that decoding to_interchange returns" {
  // Every pair of formats, six rounding modes, both tininess rules, a spread of
  // binary128 bit patterns including subnormals, overflow and the specials.
  let patterns = [
    "00000000000000000000000000000001", "3FFF0000000000000000000000000000", "40000000000000000000000000000000",
    "7FFE0000000000000000000000000000", "7FFF0000000000000000000000000000", "FFFF0000000000000000000000000000",
    "7FFF8000000000000000000000000001", "7FFF4000000000000000000000000001", "3F8000000000000000000000000001FF",
    "00007FFFFFFFFFFFFFFFFFFFFFFFFFFF", "3C000000000000000000000000000001", "47FE0000000000000000000000000001",
    "406F1234567890ABCDEF000000000000", "C0010000000000000000000000000000", "80000000000000000000000000000000",
    "3FFEFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
  ]
  let mut count = 0
  for text in patterns {
    let source = cf_value(text, BinaryInterchangeFormat::Binary128)
    for format in cf_formats() {
      for mode in e2s_modes() {
        for
          tininess in [
            TininessDetection::AfterRounding,
            TininessDetection::BeforeRounding,
          ] {
          let (value, flags) = source.convert_format(
            format,
            rounding=mode,
            tininess~,
          )
          let (encoded, encoding_flags) = BinaryInterchange::from_bin_float(
            source,
            format,
            rounding=mode,
            tininess~,
          )
          assert_eq(value.to_hex(), encoded.to_bin_float().to_hex(), msg=text)
          assert_eq(flags, encoding_flags, msg=text)
          count += 1
        }
      }
    }
  }
  assert_eq(count, patterns.length() * 4 * 6 * 2)
}
