///|
// oracle: A
// source: library contract, precision outside 1..999,999,999 aborts (decNumber DEC_MAX_DIGITS limit, not a GDA
//   1.70 clause); no computed value
// shares: nothing
test "panic Decimal::zero aborts on precision 0" {
  ignore(Decimal::zero(precision=0))
}

///|
// oracle: A
// source: library contract, precision outside 1..999,999,999 aborts (decNumber DEC_MAX_DIGITS limit, not a GDA
//   1.70 clause); no computed value
// shares: nothing
test "panic Decimal::one aborts on a precision above the limit" {
  ignore(Decimal::one(precision=1_000_000_000))
}

///|
// oracle: A
// source: library contract: precision outside 1..999,999,999 aborts (decNumber DEC_MAX_DIGITS limit adopted by the library, not a GDA 1.70 clause); no computed value
// shares: nothing
test "panic Decimal::nan aborts on a negative precision" {
  ignore(Decimal::nan(precision=-3))
}

///|
// oracle: A
// source: library contract: precision outside 1..999,999,999 aborts (decNumber DEC_MAX_DIGITS limit adopted by the library, not a GDA 1.70 clause); no computed value
// shares: nothing
test "panic Decimal::from_int aborts on precision 0" {
  ignore(Decimal::from_int(7, precision=0))
}

///|
// oracle: A
// source: library contract: precision outside 1..999,999,999 aborts (decNumber DEC_MAX_DIGITS limit adopted by the library, not a GDA 1.70 clause); no computed value
// shares: nothing
test "panic Decimal::make aborts on precision 0" {
  ignore(Decimal::make(12N, 0, 0))
}

///|
// oracle: A
// source: library contract, precision outside 1..999,999,999 aborts (decNumber DEC_MAX_DIGITS limit, not a GDA
//   1.70 clause); no computed value
// shares: nothing
test "panic Decimal::from_double aborts on precision 0" {
  ignore(Decimal::from_double(1.5, precision=0))
}

///|
// oracle: A
// source: library contract: precision outside 1..999,999,999 aborts (decNumber DEC_MAX_DIGITS limit adopted by the
//   library, not a GDA 1.70 clause); no computed value
// shares: nothing
test "panic Decimal::inf aborts on precision 0" {
  ignore(Decimal::inf(precision=0))
}

///|
// oracle: A
// source: library contract: precision outside 1..999,999,999 aborts (decNumber DEC_MAX_DIGITS limit adopted by the library, not a GDA 1.70 clause); no computed value
// shares: nothing
test "panic Decimal::with_precision aborts on precision 0" {
  ignore(Decimal::from_int(5).with_precision(0, GdaRoundingMode::HalfEven))
}

///|
// oracle: A
// source: hand: precision 1 and 999,999,999 accepted
// shares: nothing
test "the limits of the precision are accepted" {
  assert_eq(Decimal::zero(precision=1).precision(), 1)
  assert_eq(Decimal::zero(precision=999_999_999).precision(), 999_999_999)
  assert_true(Decimal::inf(negative=true).is_infinite())
  assert_true(Decimal::inf(negative=true).is_signed())
  assert_false(Decimal::inf().is_signed())
}

///|
/// GDA 1.70, page 11: a payload is no larger than the coefficient less one digit.
// oracle: A
// source: GDA 1.70 page 11 payload rule; hand literals
// shares: Decimal::to_string (printing the result)
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
// oracle: A
// source: GDA p11: payload at most precision-1 digits; 100 has 3 digits at p3
// shares: nothing
test "panic quiet_nan aborts on a payload of precision digits" {
  ignore(Decimal::quiet_nan(payload=100N, precision=3))
}

///|
// oracle: A
// source: GDA p11: at precision 1 no payload digit is allowed
// shares: nothing
test "panic signaling_nan aborts on a payload at precision 1" {
  ignore(Decimal::signaling_nan(payload=1N, precision=1))
}

///|
// oracle: A
// source: contract: payload must be non-negative
// shares: nothing
test "panic quiet_nan aborts on a negative payload" {
  ignore(Decimal::quiet_nan(payload=-5N))
}

///|
// oracle: A
// source: hand: precision limits 1..999,999,999; NaN payload at most precision-1 digits (GDA p11)
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
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
// oracle: A
// source: hand: malformed text is Err, a well-formed 8-digit hex pattern is Ok
// shares: nothing
test "GdaInterchange::from_hex returns Err for text that is not a pattern" {
  assert_true(GdaInterchange::from_hex("#12", Decimal32) is Err(_))
  assert_true(GdaInterchange::from_hex("zzzzzzzz", Decimal32) is Err(_))
  assert_true(GdaInterchange::from_hex("#25F4D2E8", Decimal32) is Ok(_))
}

///|
// oracle: A
// source: CPython: Decimal(0.1) = 0.1000000000000000055511..., rounded to 5 digits Down 0.10000, Up 0.10001, half-
//   even 0.10000; the last assertion pins the precision field of the result to the requested 20 (API
//   contract, written out)
// shares: Decimal::to_string (printing the result)
test "from_binary takes a required precision in digits and a rounding mode" {
  let tenth = @binary.Binary::from_double(0.1, precision=53)
  let down = Decimal::from_binary(
    tenth,
    precision=5,
    mode=GdaRoundingMode::Down,
  )
  let up = Decimal::from_binary(tenth, precision=5, mode=GdaRoundingMode::Up)
  assert_eq(down.to_string(), "0.10000")
  assert_eq(up.to_string(), "0.10001")
  assert_eq(Decimal::from_binary(tenth, precision=5).to_string(), "0.10000")
  // the precision of the binary value is no longer the default: it counts bits
  assert_eq(Decimal::from_binary(tenth, precision=20).precision(), 20)
}

///|
// oracle: A
// source: hand: 1.125 is the exact tie between 1.0 and 1.25 at 3 bits, so the default ties-to-even gives 1
//   and ties-to-away and toward-positive give 1.25 (and -1.25 for -1.125 to away); the expected strings are
//   literals in the printed form coefficient p exponent (1.25 = 5p-2) written out (the old expected side built them with Binary::from_double, a sibling package)
// shares: Binary::to_string (printing the result) and Decimal::from_string (reading the input)
test "to_binary takes the rounding modes of the radix of the result" {
  // 1.125 is exactly between 1.0 and 1.25 at three bits
  let tie = Decimal::from_string("1.125").unwrap()
  assert_eq(tie.to_binary(precision=3).to_string(), "1p0")
  assert_eq(
    tie
    .to_binary(precision=3, mode=@binary.BinaryRoundingMode::RoundTiesToAway)
    .to_string(),
    "5p-2",
  )
  assert_eq(
    tie
    .to_binary(
      precision=3,
      mode=@binary.BinaryRoundingMode::RoundTowardPositive,
    )
    .to_string(),
    "5p-2",
  )
  let negative_tie = Decimal::from_string("-1.125").unwrap()
  assert_eq(
    negative_tie
    .to_binary(precision=3, mode=@binary.BinaryRoundingMode::RoundTiesToAway)
    .to_string(),
    "-5p-2",
  )
}

///|
// oracle: A
// source: library contract, precision outside 1..999,999,999 aborts (decNumber DEC_MAX_DIGITS limit, not a GDA
//   1.70 clause); no computed value
// shares: nothing
test "panic to_binary aborts on precision 0" {
  ignore(Decimal::from_int(3).to_binary(precision=0))
}

///|
// oracle: A
// source: CPython plus with each mode: 1.23E+4, 1.236E+4, 1.236E+4, 1.234E+4, 1.234E+4, 1.24E+4 all agree
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "make and with_precision take a GDA rounding mode" {
  assert_eq(
    Decimal::make(12345N, 0, 3, mode=GdaRoundingMode::HalfUp).to_string(),
    "1.23E+4",
  )
  assert_eq(
    Decimal::make(12355N, 0, 4, mode=GdaRoundingMode::HalfUp).to_string(),
    "1.236E+4",
  )
  assert_eq(
    Decimal::make(12355N, 0, 4, mode=GdaRoundingMode::HalfEven).to_string(),
    "1.236E+4",
  )
  assert_eq(
    Decimal::make(12345N, 0, 4, mode=GdaRoundingMode::HalfDown).to_string(),
    "1.234E+4",
  )
  assert_eq(
    Decimal::make(12341N, 0, 4, mode=GdaRoundingMode::ZeroFiveUp).to_string(),
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
/// IEEE 754-2019 3.5.2: the payload of a decimal32 NaN is at most 6 digits (the trailing significand field); keeping
/// the low digits of a wider payload is the rule of this library (6.2.3 leaves the diagnostic information to the
/// language), and no flag names the loss.
// oracle: A, S
// source: the payload width of decimal32 (6 digits) is IEEE 754-2019 3.5.2, written out in the expected strings
//   567890 and 123456; which digits a wider payload keeps (the low ones) is the library's own rule, not a clause of
//   the standard, and is pinned here by the literal 567890 (S)
// shares: BigInt::to_string (printing the payload that is read back)
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

///|
/// S7: `make` keeps the exponent it is given when the coefficient fits.
// oracle: A
// source: hand by to-scientific-string (cohort kept, zero exponents); CPython plus agrees on the 1000000 and
//   1234567 rows
// shares: Decimal::to_string (printing the result)
test "make keeps the given exponent and does not reduce a rounded coefficient" {
  assert_eq(Decimal::make(1200N, 0, 34).to_string(), "1200")
  assert_eq(Decimal::make(100N, 0, 5).to_string(), "100")
  assert_eq(Decimal::make(1200N, -2, 34).to_string(), "12.00")
  assert_eq(Decimal::make(-1200N, 3, 34).to_string(), "-1.200E+6")
  assert_eq(Decimal::make(0N, 5, 5).to_string(), "0E+5")
  assert_eq(Decimal::make(0N, -3, 5).to_string(), "0.000")
  // a longer coefficient is rounded once; the rounded coefficient keeps its zeros
  assert_eq(Decimal::make(1000000N, 0, 3).to_string(), "1.00E+6")
  assert_eq(Decimal::make(1000000N, 0, 3).coefficient().to_string(), "100")
  assert_eq(Decimal::make(1000000N, 0, 3).exponent10(), 4)
  assert_eq(Decimal::make(1234567N, 0, 3).to_string(), "1.23E+6")
  // the cohort is explicit: reduce, trim and normalized strip the zeros
  assert_eq(Decimal::make(1200N, 0, 34).normalized().to_string(), "1.2E+3")
}
