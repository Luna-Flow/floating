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
// oracle: S
// source: the same value -12345.6789 encoded in DPD and in BID and decoded again must compare equal under total order and have the same sign, in each of decimal32, decimal64 and decimal128; the two encodings are compared with each other and no encoding is written out
// shares: Decimal::from_string, to_interchange_hex_with_encoding and from_interchange_hex_with_encoding (the code under test, both encodings)
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
    assert_eq(dpd.total_order_compare(bid), 0)
    assert_eq(dpd.is_sign_minus(), bid.is_sign_minus())
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
test "BID NaN payloads are integers across formats" {
  // IEEE 754-2019 §3.5.2 and §9.7: the payload is the integer value of the
  // trailing significand field, so it is kept, not rescaled, when it fits.
  let payload32 = Decimal::from_interchange_hex_with_encoding(
    "#7C000100",
    Decimal32,
    BID,
  ).unwrap()
  assert_eq(payload32.nan_payload().to_string(), "256")
  assert_eq(
    payload32.to_interchange_hex_with_encoding(Decimal128, BID).0,
    "#7C000000000000000000000000000100",
  )
  let payload128 = Decimal::from_interchange_hex_with_encoding(
    "#7C000000000000000000000000000100",
    Decimal128,
    BID,
  ).unwrap()
  assert_eq(
    payload128.to_interchange_hex_with_encoding(Decimal32, BID).0,
    "#7C000100",
  )
  // A payload longer than p - 1 digits keeps its low digits, as with DPD.
  let wide = Decimal::from_interchange_hex_with_encoding(
    "#7C0000033B2E3C9FD0803CE800000000",
    Decimal128,
    BID,
  ).unwrap()
  assert_eq(wide.nan_payload().to_string(), "256000000000000000000000000000")
  assert_eq(
    wide.to_interchange_hex_with_encoding(Decimal32, BID).0,
    "#7C000000",
  )
  // A non-canonical trailing significand (>= 10^(p-1)) is payload 0.
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
// oracle: A, S
// source: S for the round trips (encode a quiet NaN with payload 123 and a signaling NaN with payload 45 in DPD and BID, decode, compare the payload and the signaling and sign bits); A for the last assertion, the BID encoding of a quiet NaN with payload 123 in decimal64, #7C0000000000007B, written out in the test
// shares: Decimal::quiet_nan, Decimal::signaling_nan, to_interchange_hex_with_encoding and from_interchange_hex_with_encoding (the code under test on both sides of the round trip)
test "BID NaN payloads do not depend on the value precision" {
  for encoding in [DPD, BID] {
    let nan = Decimal::quiet_nan(payload=123N)
    let (hex, _) = nan.to_interchange_hex_with_encoding(Decimal64, encoding)
    let back = Decimal::from_interchange_hex_with_encoding(
      hex,
      Decimal64,
      encoding,
    ).unwrap()
    assert_eq(back.nan_payload().to_string(), "123")
    let snan = Decimal::signaling_nan(payload=45N, negative=true, precision=3)
    let (hex, _) = snan.to_interchange_hex_with_encoding(Decimal128, encoding)
    let back = Decimal::from_interchange_hex_with_encoding(
      hex,
      Decimal128,
      encoding,
    ).unwrap()
    assert_eq(back.nan_payload().to_string(), "45")
    assert_true(back.is_signaling_nan() && back.is_sign_minus())
  }
  let (hex, _) = Decimal::quiet_nan(payload=123N).to_interchange_hex_with_encoding(
    Decimal64,
    BID,
  )
  assert_eq(hex, "#7C0000000000007B")
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
  let (rounded, flags) = value.apply_ctx(Decimal64.context())
  assert_true(flags.inexact)
  assert_true(flags.underflow)
  assert_eq(
    rounded.to_interchange_hex_with_encoding(Decimal64, BID).0,
    "#00038D7EA4C68000",
  )
}

///|
// oracle: A, S
// source: S for decoding each of the 1024 declets to three digits and encoding the digits back (the digits are in 0..9 and the canonical code is a declet); A for the count of the codes that do not come back, 24, the number of non-canonical 10-bit patterns of IEEE 754-2019 3.5.2 (the 24 patterns of the form 01x11x111x, 10x11x111x and 11x11x111x, text read in the extracted standard)
// shares: decimal_dpd_to_digit_triplet and decimal_digit_triplet_to_dpd (the code under test, both directions)
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
    assert_eq(value.total_order_compare(expected), 0)
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
    assert_false(value.is_sign_minus())
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

///|
fn interchange_decode_message(
  src : String,
  format : DecimalInterchangeFormat,
  encoding : DecimalInterchangeEncoding,
) -> String raise {
  let from_value = Decimal::from_interchange_hex_with_encoding(
    src, format, encoding,
  )
  let from_wrapper = DecimalInterchange::from_hex_with_encoding(
    src, format, encoding,
  )
  match (from_value, from_wrapper) {
    (Err(a), Err(b)) => {
      // both decoders refuse with the same reason, and it is a parse error
      assert_true(a.is_parse_error())
      assert_eq(a.message, b.message)
      a.message
    }
    _ => abort("expected both decoders to refuse: " + src)
  }
}

///|
/// A text of the wrong length is refused and the reason gives the length wanted
/// and the length found: too short, too long and empty, in each encoding.
test "interchange decoders refuse a text of the wrong length and say so" {
  for encoding in [DPD, BID] {
    inspect(
      interchange_decode_message("#A23003D", Decimal32, encoding),
      content="interchange hexadecimal text must have exactly 8 digits after the optional '#', got 7: #A23003D",
    )
    inspect(
      interchange_decode_message("A230003D0", Decimal32, encoding),
      content="interchange hexadecimal text must have exactly 8 digits after the optional '#', got 9: A230003D0",
    )
    inspect(
      interchange_decode_message("", Decimal64, encoding),
      content="interchange hexadecimal text must have exactly 16 digits after the optional '#', got 0: ",
    )
    inspect(
      interchange_decode_message("#", Decimal128, encoding),
      content="interchange hexadecimal text must have exactly 32 digits after the optional '#', got 0: #",
    )
  }
}

///|
/// A character that is not a hexadecimal digit is refused and the reason names
/// the character and its place among the digits.
test "interchange decoders refuse a non-hexadecimal character and name it" {
  for encoding in [DPD, BID] {
    inspect(
      interchange_decode_message("#77FFFF3FCFF3FCFG", Decimal64, encoding),
      content="interchange hexadecimal text has a character that is not a hexadecimal digit, 'G' at digit 15: #77FFFF3FCFF3FCFG",
    )
    inspect(
      interchange_decode_message("0x000001", Decimal32, encoding),
      content="interchange hexadecimal text has a character that is not a hexadecimal digit, 'x' at digit 1: 0x000001",
    )
    // the length is checked first: a text with both faults is reported as wrong length
    inspect(
      interchange_decode_message("#G", Decimal32, encoding),
      content="interchange hexadecimal text must have exactly 8 digits after the optional '#', got 1: #G",
    )
  }
}
