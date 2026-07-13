///|
test "BID decimal32 and decimal64 canonical vectors" {
  let zero32 = Decimal::from_string("0", precision=7).unwrap()
  assert_eq(
    zero32.to_interchange_hex_with_encoding(Decimal32, BID).0,
    "#32800000",
  )
  assert_eq(
    Decimal::from_interchange_hex_with_encoding("#32800000", Decimal32, BID)
    .unwrap()
    .to_string(),
    "0",
  )
  let max32 = Decimal::from_string("9999999", precision=7).unwrap()
  assert_eq(
    max32.to_interchange_hex_with_encoding(Decimal32, BID).0,
    "#6CB8967F",
  )
  let zero64 = Decimal::from_string("0", precision=16).unwrap()
  assert_eq(
    zero64.to_interchange_hex_with_encoding(Decimal64, BID).0,
    "#31C0000000000000",
  )
  let max64 = Decimal::from_string("9999999999999999", precision=16).unwrap()
  assert_eq(
    max64.to_interchange_hex_with_encoding(Decimal64, BID).0,
    "#6C7386F26FC0FFFF",
  )
}

///|
test "DPD and BID share Decimal semantics across formats" {
  for format in [Decimal32, Decimal64, Decimal128] {
    let value = Decimal::from_string("-12345.6789", precision=34).unwrap()
    let (dpd_bits, dpd_flags) = value.to_interchange_hex_with_encoding(
      format,
      DPD,
    )
    let (bid_bits, bid_flags) = value.to_interchange_hex_with_encoding(
      format,
      BID,
    )
    assert_false(dpd_flags.has_error())
    assert_false(bid_flags.has_error())
    let dpd = Decimal::from_interchange_hex_with_encoding(dpd_bits, format, DPD).unwrap()
    let bid = Decimal::from_interchange_hex_with_encoding(bid_bits, format, BID).unwrap()
    assert_eq(dpd.compare_total(bid), 0)
    assert_eq(dpd.is_negative(), bid.is_negative())
  }
}

///|
test "BID non-canonical finite coefficient decodes as zero" {
  let noncanonical = Decimal::from_interchange_hex_with_encoding(
    "#6CB89680",
    Decimal32,
    BID,
  ).unwrap()
  assert_true(noncanonical.is_zero())
}

///|
test "BID NaN payloads canonicalize and align across formats" {
  let payload32 = Decimal::from_interchange_hex_with_encoding(
    "#7C000100",
    Decimal32,
    BID,
  ).unwrap()
  assert_eq(
    payload32.to_interchange_hex_with_encoding(Decimal128, BID).0,
    "#7C0000033B2E3C9FD0803CE800000000",
  )
  let payload128 = Decimal::from_interchange_hex_with_encoding(
    "#7C0000033B2E3C9FD0803CE800000000",
    Decimal128,
    BID,
  ).unwrap()
  assert_eq(
    payload128.to_interchange_hex_with_encoding(Decimal32, BID).0,
    "#7C000100",
  )
  let noncanonical = Decimal::from_interchange_hex_with_encoding(
    "#7C03FFFFFFFFFFFF",
    Decimal64,
    BID,
  ).unwrap()
  assert_eq(
    noncanonical.to_interchange_hex_with_encoding(Decimal64, BID).0,
    "#7C00000000000000",
  )
}

///|
test "BID signaling NaN payload survives quieting" {
  let value = Decimal::from_interchange_hex_with_encoding(
    "#FF777D7CFFFFDFF7",
    Decimal64,
    BID,
  ).unwrap()
  assert_eq(value.nan_payload().to_string(), "982400754507767")
  let (quiet, flags) = value.apply_ctx(Decimal64.context())
  assert_true(flags.invalid_operation)
  assert_eq(quiet.nan_payload().to_string(), "982400754507767")
  assert_eq(
    quiet.to_interchange_hex_with_encoding(Decimal64, BID).0,
    "#FC037D7CFFFFDFF7",
  )
}

///|
test "IEEE BID NaN propagation uses operand-order payload precedence" {
  let qnan = Decimal::from_interchange_hex_with_encoding(
    "#7C8F423F",
    Decimal32,
    BID,
  ).unwrap()
  let snan = Decimal::from_interchange_hex_with_encoding(
    "#7E100000",
    Decimal32,
    BID,
  ).unwrap()
  let (result, flags) = qnan.add_ctx(snan, Decimal32.context())
  assert_true(flags.invalid_operation)
  assert_eq(
    result.to_interchange_hex_with_encoding(Decimal32, BID).0,
    "#7C0F423F",
  )
}

///|
test "IEEE BID FMA propagates NaN before zero times infinity invalid" {
  let zero = Decimal::from_interchange_hex_with_encoding(
    "#0000000000000000",
    Decimal64,
    BID,
  ).unwrap()
  let negative_infinity = Decimal::from_interchange_hex_with_encoding(
    "#FBFDFFDFFDFFF6FF",
    Decimal64,
    BID,
  ).unwrap()
  let snan = Decimal::from_interchange_hex_with_encoding(
    "#FF777D7CFFFFDFF7",
    Decimal64,
    BID,
  ).unwrap()
  let (result, flags) = zero.fma_ctx(
    negative_infinity,
    snan,
    Decimal64.context(),
  )
  assert_true(flags.invalid_operation)
  assert_eq(
    result.to_interchange_hex_with_encoding(Decimal64, BID).0,
    "#FC037D7CFFFFDFF7",
  )
}

///|
test "IEEE BID FMA uses multiplier addend first-operand NaN precedence" {
  let finite = Decimal::from_string_ctx("1.00001", Decimal32.context()).0
  let multiplier = Decimal::from_interchange_hex_with_encoding(
    "#7E100000",
    Decimal32,
    BID,
  ).unwrap()
  let addend = Decimal::from_interchange_hex_with_encoding(
    "#7C8F423F",
    Decimal32,
    BID,
  ).unwrap()
  let (result, flags) = finite.fma_ctx(multiplier, addend, Decimal32.context())
  assert_true(flags.invalid_operation)
  assert_eq(
    result.to_interchange_hex_with_encoding(Decimal32, BID).0,
    "#7C000000",
  )
}

///|
test "IEEE BID format conversion detects tininess before rounding" {
  let value = Decimal::from_interchange_hex_with_encoding(
    "#2CFFED09BEAD87C0378D8E63FFFFFFFF",
    Decimal128,
    BID,
  ).unwrap()
  let (rounded, flags) = value.apply_ctx(
    Decimal64.context().with_tininess(DecimalTininessDetection::BeforeRounding),
  )
  assert_true(flags.inexact)
  assert_true(flags.underflow)
  assert_true(flags.subnormal)
  assert_eq(
    rounded.to_interchange_hex_with_encoding(Decimal64, BID).0,
    "#00038D7EA4C68000",
  )
}

///|
test "IEEE DPD declet corpus exhaustively canonicalizes all 1024 codes" {
  let mut redundant = 0
  for code in 0..<1024 {
    let (lhs, mid, rhs) = decimal_dpd_to_digit_triplet(code)
    assert_true(lhs >= 0 && lhs <= 9)
    assert_true(mid >= 0 && mid <= 9)
    assert_true(rhs >= 0 && rhs <= 9)
    let canonical = decimal_digit_triplet_to_dpd(lhs, mid, rhs)
    assert_true(canonical >= 0 && canonical < 1024)
    if canonical != code {
      redundant += 1
    }
  }
  assert_eq(redundant, 24)
}

///|
test "IEEE DPD decimal32 decimal64 decimal128 fixed witnesses round trip" {
  let formats = [Decimal32, Decimal64, Decimal128]
  let bits = [
    "#A23003D0", "#A2300000000003D0", "#A20780000000000000000000000003D0",
  ]
  let expected = Decimal::from_string("-7.50", precision=64).unwrap()
  for index in 0..<formats.length() {
    let value = Decimal::from_interchange_hex_with_encoding(
      bits[index],
      formats[index],
      DPD,
    ).unwrap()
    assert_eq(value.compare_total(expected), 0)
    assert_eq(
      value.to_interchange_hex_with_encoding(formats[index], DPD).0,
      bits[index],
    )
  }
}

///|
test "IEEE BID decimal32 decimal64 decimal128 zero witnesses round trip" {
  let formats = [Decimal32, Decimal64, Decimal128]
  let bits = [
    "#32800000", "#31C0000000000000", "#30400000000000000000000000000000",
  ]
  for index in 0..<formats.length() {
    let value = Decimal::from_interchange_hex_with_encoding(
      bits[index],
      formats[index],
      BID,
    ).unwrap()
    assert_true(value.is_zero())
    assert_false(value.is_negative())
    assert_eq(
      value.to_interchange_hex_with_encoding(formats[index], BID).0,
      bits[index],
    )
  }
}

///|
test "IEEE DPD and BID special witnesses preserve class sign and canonical bits" {
  let formats = [Decimal32, Decimal64, Decimal128]
  let infinities = [
    "#78000000", "#7800000000000000", "#78000000000000000000000000000000",
  ]
  let nans = [
    "#7C000000", "#7C00000000000000", "#7C000000000000000000000000000000",
  ]
  for index in 0..<formats.length() {
    for encoding in [DPD, BID] {
      let infinity = DecimalInterchange::from_hex_with_encoding(
        infinities[index],
        formats[index],
        encoding,
      ).unwrap()
      assert_true(infinity.to_decimal().is_infinite())
      assert_eq(infinity.canonical().to_hex(), infinities[index])
      let nan = DecimalInterchange::from_hex_with_encoding(
        nans[index],
        formats[index],
        encoding,
      ).unwrap()
      assert_true(nan.to_decimal().is_nan())
      assert_eq(nan.canonical().to_hex(), nans[index])
    }
  }
}
