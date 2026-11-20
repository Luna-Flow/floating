///|
// Values of `decimal` (#438: S5 precision label, S6 NaN payload, S7 make, N4
// inf, S2 sqrt, `identical`).

///|
test "panic Decimal::zero aborts on precision 0" {
  ignore(Decimal::zero(precision=0))
}

///|
test "panic Decimal::from_int aborts on a precision beyond the limit" {
  ignore(Decimal::from_int(3, precision=2_000_000_000))
}

///|
test "panic Decimal::make aborts on a negative precision" {
  ignore(Decimal::make(1N, 0, -1))
}

///|
test "panic Decimal::inf aborts on precision 0" {
  ignore(Decimal::inf(precision=0))
}

///|
test "panic Decimal::with_precision aborts on precision 0" {
  ignore(
    Decimal::from_int(1).with_precision(0, DecimalRoundingMode::RoundTiesToEven),
  )
}

///|
test "panic Decimal::quiet_nan aborts on a payload wider than precision - 1" {
  ignore(Decimal::quiet_nan(payload=100N, precision=3))
}

///|
test "panic Decimal::signaling_nan aborts on a negative payload" {
  ignore(Decimal::signaling_nan(payload=-1N, precision=7))
}

///|
test "the limits of a payload are the p - 1 trailing digits" {
  let widest = Decimal::quiet_nan(payload=99N, precision=3)
  assert_eq(widest.nan_payload(), 99N)
  let none = Decimal::signaling_nan(precision=1)
  assert_true(none.is_signaling_nan())
  assert_eq(none.nan_payload(), 0N)
}

///|
test "a conversion to a narrower format keeps the low digits of a payload" {
  let wide = @bin_float.BinFloat::quiet_nan(
    payload=@bin_float.BinCoeff::from_uint64(123456789012345678UL),
    precision=64,
  )
  let (value, _) = Decimal::from_bin_float_ctx(
    wide,
    DecimalContext::decimal32(),
  )
  assert_true(value.is_nan())
  assert_true(coeff_digits(value.coefficient) <= 6)
}

///|
test "make keeps the exponent of a coefficient that fits (S7)" {
  assert_eq(Decimal::make(100N, 0, 5).to_string(), "100")
  assert_eq(Decimal::make(0N, 5, 5).to_string(), "0E+5")
  assert_eq(Decimal::make(1200N, -2, 6).to_string(), "12.00")
  // a longer coefficient is rounded to p digits and not reduced
  let rounded = Decimal::make(1000000N, 0, 3)
  assert_eq(rounded.coefficient().to_string(), "100")
  assert_eq(rounded.exponent10(), 4)
  let carried = Decimal::make(99950N, 0, 3)
  assert_eq(carried.coefficient().to_string(), "100")
  assert_eq(carried.exponent10(), 3)
  assert_eq(Decimal::make(-12345N, 3, 3).to_string(), "-1.23E+7")
}

///|
test "make rounds with the given direction" {
  let down = Decimal::make(
    12399N,
    0,
    3,
    mode=DecimalRoundingMode::RoundTowardZero,
  )
  assert_eq(down.to_string(), "1.23E+4")
  let up = Decimal::make(
    12301N,
    0,
    3,
    mode=DecimalRoundingMode::RoundTowardPositive,
  )
  assert_eq(up.to_string(), "1.24E+4")
}

///|
test "identical compares every field of the representation" {
  let a = Decimal::from_string("1.20").unwrap()
  assert_true(a.identical(Decimal::from_string("1.20").unwrap()))
  assert_false(a.identical(Decimal::from_string("1.2").unwrap()))
  assert_false(a.identical(Decimal::from_string("1.20", precision=40).unwrap()))
  assert_false(Decimal::zero().identical(Decimal::negative_zero()))
  assert_false(
    Decimal::quiet_nan(payload=1N).identical(Decimal::quiet_nan(payload=2N)),
  )
  assert_false(Decimal::quiet_nan().identical(Decimal::signaling_nan()))
  assert_true(Decimal::inf().identical(Decimal::inf()))
  assert_false(Decimal::inf().identical(Decimal::inf(negative=true)))
  assert_true(a == Decimal::from_string("1.2").unwrap())
}

///|
test "inf takes the sign as a flag" {
  assert_false(Decimal::inf().is_negative())
  assert_true(Decimal::inf(negative=true, precision=7).is_negative())
  assert_eq(Decimal::inf(negative=true).to_string(), "-inf")
}

///|
test "sqrt returns a Decimal: NaN for a negative operand" {
  assert_eq(Decimal::from_int(4).sqrt().to_string(), "2")
  assert_true(Decimal::from_int(-4).sqrt().is_nan())
  assert_eq(Decimal::from_string("0.0400").unwrap().sqrt().to_string(), "0.20")
}
