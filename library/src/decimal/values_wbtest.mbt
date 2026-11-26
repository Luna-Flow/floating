///|
// Values of `decimal` (#438: S5 precision label, S6 NaN payload, S7 make, N4
// inf, S2 sqrt, `identical`).

///|
// oracle: S
// source: the documented precondition of the constructor (precision at least 1): an abort is the library's contract for a precision outside the format range, the test is the panic itself; no value is written out
// shares: Decimal::zero (the code under test)
test "panic Decimal::zero aborts on precision 0" {
  ignore(Decimal::zero(precision=0))
}

///|
// oracle: S
// source: the documented precondition of the constructor (precision at most the limit of the representation): the abort is the library's contract, the test is the panic itself
// shares: Decimal::from_int (the code under test)
test "panic Decimal::from_int aborts on a precision beyond the limit" {
  ignore(Decimal::from_int(3, precision=2_000_000_000))
}

///|
// oracle: S
// source: the documented precondition of the constructor (precision at least 1): the abort is the library's contract, the test is the panic itself
// shares: Decimal::make (the code under test)
test "panic Decimal::make aborts on a negative precision" {
  ignore(Decimal::make(1N, 0, -1))
}

///|
// oracle: S
// source: the documented precondition of the constructor (precision at least 1): the abort is the library's contract, the test is the panic itself
// shares: Decimal::inf (the code under test)
test "panic Decimal::inf aborts on precision 0" {
  ignore(Decimal::inf(precision=0))
}

///|
// oracle: S
// source: the documented precondition of the method (precision at least 1): the abort is the library's contract, the test is the panic itself
// shares: Decimal::with_precision (the code under test)
test "panic Decimal::with_precision aborts on precision 0" {
  ignore(
    Decimal::from_int(1).with_precision(0, DecimalRoundingMode::RoundTiesToEven),
  )
}

///|
// oracle: A, S
// source: IEEE 754-2019 3.5.2 a): the payload of a NaN has at most p - 1 digits (here p = 3 and the payload 100 has 3); that the constructor aborts instead of reducing the payload is the library's contract (level S)
// shares: Decimal::quiet_nan (the code under test)
test "panic Decimal::quiet_nan aborts on a payload wider than precision - 1" {
  ignore(Decimal::quiet_nan(payload=100N, precision=3))
}

///|
// oracle: S
// source: the documented precondition of the constructor (a payload is a non-negative integer, IEEE 754-2019 3.5.2): the abort is the library's contract, the test is the panic itself
// shares: Decimal::signaling_nan (the code under test)
test "panic Decimal::signaling_nan aborts on a negative payload" {
  ignore(Decimal::signaling_nan(payload=-1N, precision=7))
}

///|
// oracle: A
// source: IEEE 754-2019 3.5.2 a): a NaN payload is an integer of at most p - 1 digits: 99 is the widest at p = 3, and a signaling NaN of precision 1 has the only payload 0; written out
// shares: Decimal::quiet_nan, signaling_nan, nan_payload and is_signaling_nan (the code under test)
test "the limits of a payload are the p - 1 trailing digits" {
  let widest = Decimal::quiet_nan(payload=99N, precision=3)
  assert_eq(widest.nan_payload(), 99N)
  let none = Decimal::signaling_nan(precision=1)
  assert_true(none.is_signaling_nan())
  assert_eq(none.nan_payload(), 0N)
}

///|
// oracle: A, S
// source: arithmetic: 123456789012345678 modulo 10^6 is 345678 and 999999 is kept whole in decimal32 (6 payload digits, 3.5.2); keeping the low digits of a payload that does not fit is the library's convention, 6.2.3 only says 'if representable' (level S); written out
// shares: Binary::quiet_nan and BinCoeff::from_uint64 (build the operands), from_binary_ctx and nan_payload (the code under test)
test "a conversion to a narrower format keeps the low digits of a payload" {
  let wide = @binary.Binary::quiet_nan(
    payload=@binary.BinCoeff::from_uint64(123456789012345678UL),
    precision=64,
  )
  let (value, _) = Decimal::from_binary_ctx(wide, DecimalContext::decimal32())
  assert_true(value.is_nan())
  // the payload 123456789012345678 modulo 10^6 (the 6 digits decimal32 holds):
  // IEEE 754-2019 3.5.2 / 6.2.3, the low-order digits are kept (value written out)
  assert_eq(value.nan_payload(), 345678N)
  // a payload that fits is kept whole
  let fits = @binary.Binary::quiet_nan(
    payload=@binary.BinCoeff::from_uint64(999999UL),
    precision=64,
  )
  let (kept, _) = Decimal::from_binary_ctx(fits, DecimalContext::decimal32())
  assert_eq(kept.nan_payload(), 999999N)
}

///|
// oracle: A
// source: arithmetic and IEEE 754-2019 5.2: 100 at precision 5 is 100, 0 with exponent 5 prints 0E+5, 1200E-2 is 12.00; 1000000 at three digits is 100E+4 (coefficient 100, exponent 4), 99950 at three digits rounds half-even to 1000 = 100E+3 (coefficient 100, exponent 3) and -12345E+3 to -123E+5 = -1.23E+7; written out
// shares: Decimal::from_string, to_string and the accessors (they build the operands and read the results)
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
// oracle: A
// source: arithmetic and IEEE 754-2019 4.3: 12399 at three digits is 123E+2 toward zero (1.23E+4) and 12301 is 124E+2 toward positive (1.24E+4); written out
// shares: Decimal::from_string, to_string and the accessors (they build the operands and read the results)
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
// oracle: A, S
// source: IEEE 754-2019 3.4 and 5.2: 1.20 and 1.2 are the same value in different cohorts, +0 and -0 differ in sign, two NaNs differ in payload, a quiet and a signaling NaN differ in class, and infinities by sign; what identical compares (including the precision label, 1.20 at precision 40) is the library's definition of an identical representation (level S for the precision field); written out
// shares: Decimal::from_string, to_string and the accessors (they build the operands and read the results)
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
// oracle: A, S
// source: IEEE 754-2019 3.4: an infinity has a sign; the text -inf for the negative infinity is the library's formatting (level S); written out
// shares: Decimal::from_string, to_string and the accessors (they build the operands and read the results)
test "inf takes the sign as a flag" {
  assert_false(Decimal::inf().is_sign_minus())
  assert_true(Decimal::inf(negative=true, precision=7).is_sign_minus())
  assert_eq(Decimal::inf(negative=true).to_string(), "-inf")
}

///|
// oracle: A
// source: IEEE 754-2019 5.4.1 and 9.2: sqrt(4) = 2, sqrt(-4) is a quiet NaN (invalid operation) and the preferred exponent of sqrt(0.0400) is floor(-4/2) = -2, so 0.20; written out
// shares: Decimal::from_string, to_string and the accessors (they build the operands and read the results)
test "sqrt returns a Decimal: NaN for a negative operand" {
  assert_eq(Decimal::from_int(4).sqrt().to_string(), "2")
  assert_true(Decimal::from_int(-4).sqrt().is_nan())
  assert_eq(Decimal::from_string("0.0400").unwrap().sqrt().to_string(), "0.20")
}
