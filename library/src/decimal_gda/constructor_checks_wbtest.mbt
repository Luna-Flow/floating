///|
test "panic Decimal::zero aborts on precision 0" {
  ignore(Decimal::zero(precision=0))
}

///|
test "panic Decimal::one aborts on a precision above the limit" {
  ignore(Decimal::one(precision=1_000_000_000))
}

///|
test "panic Decimal::nan aborts on a negative precision" {
  ignore(Decimal::nan(precision=-3))
}

///|
test "panic Decimal::from_int aborts on precision 0" {
  ignore(Decimal::from_int(7, precision=0))
}

///|
test "panic Decimal::make aborts on precision 0" {
  ignore(Decimal::make(12N, 0, 0))
}

///|
test "panic Decimal::from_double aborts on precision 0" {
  ignore(Decimal::from_double(1.5, precision=0))
}

///|
test "panic Decimal::inf aborts on precision 0" {
  ignore(Decimal::inf(precision=0))
}

///|
test "panic Decimal::with_precision aborts on precision 0" {
  ignore(Decimal::from_int(5).with_precision(0, GdaRoundingMode::HalfEven))
}

///|
test "the limits of the precision are accepted" {
  assert_eq(Decimal::zero(precision=1).precision(), 1)
  assert_eq(Decimal::zero(precision=999_999_999).precision(), 999_999_999)
  assert_true(Decimal::inf(negative=true).is_infinite())
  assert_true(Decimal::inf(negative=true).is_signed())
  assert_false(Decimal::inf().is_signed())
}

///|
/// GDA 1.70, page 11: a payload is no larger than the coefficient less one digit.
test "a NaN payload has at most precision - 1 digits" {
  assert_eq(Decimal::quiet_nan(payload=99N, precision=3).to_string(), "nan99")
  assert_eq(
    Decimal::signaling_nan(payload=9N, precision=2).to_string(),
    "snan9",
  )
  assert_eq(Decimal::quiet_nan(precision=1).to_string(), "nan")
  assert_eq(Decimal::signaling_nan(precision=1).to_string(), "snan")
}

///|
test "panic quiet_nan aborts on a payload of precision digits" {
  ignore(Decimal::quiet_nan(payload=100N, precision=3))
}

///|
test "panic signaling_nan aborts on a payload at precision 1" {
  ignore(Decimal::signaling_nan(payload=1N, precision=1))
}

///|
test "panic quiet_nan aborts on a negative payload" {
  ignore(Decimal::quiet_nan(payload=-5N))
}

///|
test "from_string returns Err for a precision outside the limits and a wide payload" {
  assert_true(Decimal::from_string("1", precision=0) is Err(_))
  assert_true(Decimal::from_string("1", precision=1_000_000_000) is Err(_))
  assert_true(Decimal::from_string("1.5").unwrap().to_string() == "1.5")
  assert_true(Decimal::from_string("abc") is Err(_))
  assert_eq(
    Decimal::from_string("NaN12", precision=3).unwrap().to_string(),
    "nan12",
  )
  assert_true(Decimal::from_string("NaN123", precision=3) is Err(_))
  assert_true(Decimal::from_string("sNaN12", precision=3).unwrap().is_snan())
  assert_true(Decimal::from_string("sNaN123", precision=3) is Err(_))
  assert_true(Decimal::from_string("NaN1", precision=1) is Err(_))
  assert_true(Decimal::from_string("NaN", precision=1) is Ok(_))
}

///|
test "GdaInterchange::from_hex returns Err for text that is not a pattern" {
  assert_true(GdaInterchange::from_hex("#12", Decimal32) is Err(_))
  assert_true(GdaInterchange::from_hex("zzzzzzzz", Decimal32) is Err(_))
  assert_true(GdaInterchange::from_hex("#25F4D2E8", Decimal32) is Ok(_))
}

///|
test "from_bin_float takes a required precision in digits and a rounding mode" {
  let tenth = @bin_float.BinFloat::from_double(0.1, precision=53)
  let down = Decimal::from_bin_float(
    tenth,
    precision=5,
    rounding=GdaRoundingMode::Down,
  )
  let up = Decimal::from_bin_float(
    tenth,
    precision=5,
    rounding=GdaRoundingMode::Up,
  )
  assert_eq(down.to_string(), "0.10000")
  assert_eq(up.to_string(), "0.10001")
  assert_eq(Decimal::from_bin_float(tenth, precision=5).to_string(), "0.10000")
  // the precision of the binary value is no longer the default: it counts bits
  assert_eq(Decimal::from_bin_float(tenth, precision=20).precision(), 20)
}

///|
test "to_bin_float takes the rounding modes of the radix of the result" {
  // 1.125 is exactly between 1.0 and 1.25 at three bits
  let tie = Decimal::from_string("1.125").unwrap()
  assert_eq(
    tie.to_bin_float(precision=3).to_string(),
    @bin_float.BinFloat::from_double(1.0, precision=3).to_string(),
  )
  assert_eq(
    tie
    .to_bin_float(
      precision=3,
      mode=@bin_float.BinaryRoundingMode::RoundTiesToAway,
    )
    .to_string(),
    @bin_float.BinFloat::from_double(1.25, precision=3).to_string(),
  )
  assert_eq(
    tie
    .to_bin_float(
      precision=3,
      mode=@bin_float.BinaryRoundingMode::RoundTowardPositive,
    )
    .to_string(),
    @bin_float.BinFloat::from_double(1.25, precision=3).to_string(),
  )
  let negative_tie = Decimal::from_string("-1.125").unwrap()
  assert_eq(
    negative_tie
    .to_bin_float(
      precision=3,
      mode=@bin_float.BinaryRoundingMode::RoundTiesToAway,
    )
    .to_string(),
    @bin_float.BinFloat::from_double(-1.25, precision=3).to_string(),
  )
}

///|
test "panic to_bin_float aborts on precision 0" {
  ignore(Decimal::from_int(3).to_bin_float(precision=0))
}

///|
test "make and with_precision take a GDA rounding mode" {
  assert_eq(
    Decimal::make(12345N, 0, 3, rounding=GdaRoundingMode::HalfUp).to_string(),
    "1.23E+4",
  )
  assert_eq(
    Decimal::make(12355N, 0, 4, rounding=GdaRoundingMode::HalfUp).to_string(),
    "1.236E+4",
  )
  assert_eq(
    Decimal::make(12355N, 0, 4, rounding=GdaRoundingMode::HalfEven).to_string(),
    "1.236E+4",
  )
  assert_eq(
    Decimal::make(12345N, 0, 4, rounding=GdaRoundingMode::HalfDown).to_string(),
    "1.234E+4",
  )
  assert_eq(
    Decimal::make(12341N, 0, 4, rounding=GdaRoundingMode::ZeroFiveUp).to_string(),
    "1.234E+4",
  )
  assert_eq(
    Decimal::from_string("12345")
    .unwrap()
    .with_precision(3, GdaRoundingMode::Ceiling)
    .to_string(),
    "1.24E+4",
  )
}

///|
/// IEEE 754-2019 3.5.2 and 6.2.3: a payload wider than the trailing significand
/// field keeps its low digits; no flag names the loss.
test "an interchange NaN keeps the low digits of a payload that is too wide" {
  let wide = Decimal::quiet_nan(payload=12345678901234567890N, negative=true)
  let (encoded, flags) = GdaInterchange::from_decimal(wide, Decimal32)
  assert_true(flags == GdaFlags::new())
  let back = encoded.to_decimal()
  assert_true(back.is_qnan())
  assert_true(back.is_signed())
  assert_eq(back.nan_payload().to_string(), "567890")
  let fitting = Decimal::signaling_nan(payload=123456N)
  let (round, _) = GdaInterchange::from_decimal(fitting, Decimal32)
  assert_true(round.to_decimal().is_snan())
  assert_eq(round.to_decimal().nan_payload().to_string(), "123456")
}
