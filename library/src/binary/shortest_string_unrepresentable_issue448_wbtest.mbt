// #448: `to_shortest_string_ctx` rounds the operand into the context first
// (round to nearest even) and prints the shortest string of that rounded value;
// it used to panic when the operand was not representable in the context.

///|
// oracle: A, S
// source: A: the text of the double nearest to 1/3, 0.3333333333333333 (CPython repr(1/3), library-ran: no) and of the binary32 value nearest to 1/3, 0.33333334 (the shortest round-trip text, re-derived with Python fractions); S: the line comparing with from_double(1/3).to_shortest_string_ctx is a comparison of the library with itself
// shares: Binary::from_int, div, neg and from_double build the operands; to_shortest_string_ctx is the code under test
test "shortest string of an operand not representable in the context (#448)" {
  let third = Binary::from_int(1, precision=113).div(
    Binary::from_int(3, precision=113),
  )
  let b64 = BinaryContext::binary64()
  assert_eq(third.to_shortest_string_ctx(b64).0, "0.3333333333333333")
  assert_eq(third.neg().to_shortest_string_ctx(b64).0, "-0.3333333333333333")
  // The rounded value is the double nearest 1/3: the same text as the double.
  assert_eq(
    third.to_shortest_string_ctx(b64).0,
    Binary::from_double(1.0 / 3.0).to_shortest_string_ctx(b64).0,
  )
  // binary32: 1/3 rounds to 0.33333334.
  assert_eq(
    third.to_shortest_string_ctx(BinaryContext::binary32()).0,
    "0.33333334",
  )
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 7.4, 7.5 and 4.3: 2^2000 overflows binary64 to inf, 2^-2000 underflows to 0 with the sign of the operand, half of the smallest subnormal ties to even (0) and three quarters of it round up to the smallest subnormal, whose shortest text is 5e-324 (CPython repr(5e-324), library-ran: no)
// shares: Binary::make builds the operands; to_shortest_string_ctx is the code under test
test "shortest string rounds overflow and underflow into the context (#448)" {
  let b64 = BinaryContext::binary64()
  let big = Binary::make(BinCoeff::one(), 2000, 113)
  assert_eq(big.to_shortest_string_ctx(b64).0, "inf")
  assert_eq(big.neg().to_shortest_string_ctx(b64).0, "-inf")
  let tiny = Binary::make(BinCoeff::one(), -2000, 113)
  assert_eq(tiny.to_shortest_string_ctx(b64).0, "0")
  assert_eq(tiny.neg().to_shortest_string_ctx(b64).0, "-0")
  // Half of the smallest subnormal ties to even (zero); a bit more rounds up.
  let half = Binary::make(BinCoeff::one(), -1075, 113)
  assert_eq(half.to_shortest_string_ctx(b64).0, "0")
  let above = Binary::make(BinCoeff::from_uint64(3UL), -1076, 113)
  assert_eq(above.to_shortest_string_ctx(b64).0, "5e-324")
}

///|
// oracle: A, S
// source: A: the shortest round-trip texts of the doubles 0.1, 5e-324 and 1e21 (CPython repr gives 0.1, 5e-324 and 1e+21, library-ran: no); S: the texts -0 and nan are the library's own output conventions
// shares: Binary::from_double and nan build the operands; to_shortest_string_ctx is the code under test
test "representable operands print as before (#448)" {
  let b64 = BinaryContext::binary64()
  assert_eq(Binary::from_double(0.1).to_shortest_string_ctx(b64).0, "0.1")
  assert_eq(
    Binary::from_double(4.9406564584124654e-324).to_shortest_string_ctx(b64).0,
    "5e-324",
  )
  assert_eq(Binary::from_double(-0.0).to_shortest_string_ctx(b64).0, "-0")
  assert_eq(
    Binary::from_double(1000000000000000000000.0).to_shortest_string_ctx(b64).0,
    "1e+21",
  )
  assert_eq(Binary::nan().to_shortest_string_ctx(b64).0, "nan")
}

///|
// oracle: A
// source: written out: 1/3 lies between the doubles 0.3333333333333333 and 0.33333333333333337 (the successor, CPython math.nextafter, library-ran: no), so toward positive infinity gives the upper one and toward negative infinity the lower one, mirrored for -1/3; a directed overflow toward zero stops at the largest finite value 1.7976931348623157e+308 (CPython repr, IEEE Std 754-2019 7.4)
// shares: Binary::from_int, div, neg and make build the operands; to_shortest_string_ctx is the code under test
test "the operand is rounded in the rounding direction of the context (#448)" {
  let third = Binary::from_int(1, precision=113).div(
    Binary::from_int(3, precision=113),
  )
  // The double nearest 1/3 is below it, so toward positive gives the next one.
  assert_eq(
    third.to_shortest_string_ctx(BinaryContext::binary64()).0,
    "0.3333333333333333",
  )
  assert_eq(
    third.to_shortest_string_ctx(
      BinaryContext::binary64(rounding=RoundTowardPositive),
    ).0,
    "0.33333333333333337",
  )
  assert_eq(
    third.to_shortest_string_ctx(
      BinaryContext::binary64(rounding=RoundTowardNegative),
    ).0,
    "0.3333333333333333",
  )
  assert_eq(
    third
    .neg()
    .to_shortest_string_ctx(
      BinaryContext::binary64(rounding=RoundTowardNegative),
    ).0,
    "-0.33333333333333337",
  )
  // A directed overflow stops at the largest finite value instead of inf.
  let big = Binary::make(BinCoeff::one(), 2000, 113)
  assert_eq(
    big.to_shortest_string_ctx(
      BinaryContext::binary64(rounding=RoundTowardZero),
    ).0,
    "1.7976931348623157e+308",
  )
}

///|
// oracle: A
// source: flags written out from IEEE 754-2019 7.4 (overflow, with inexact) and 7.5 (underflow is raised for a tiny inexact result), 5.12; the strings are the 0.11 results of the cases above
// shares: nothing
test "to_shortest_string_ctx returns the flags of the rounding into the context" {
  let b64 = BinaryContext::binary64()
  // A value of the format: no flag.
  let (text, flags) = Binary::from_double(0.1).to_shortest_string_ctx(b64)
  assert_eq(text, "0.1")
  assert_false(flags.inexact() || flags.overflow() || flags.underflow())
  // 1/3 at 113 bits is not a double: inexact only.
  let third = Binary::from_int(1, precision=113).div_ctx(
      Binary::from_int(3, precision=113),
      BinaryContext::new(precision=113),
    ).0
  let (text, flags) = third.to_shortest_string_ctx(b64)
  assert_eq(text, "0.3333333333333333")
  assert_true(flags.inexact())
  assert_false(flags.overflow() || flags.underflow())
  // 2^2000 overflows binary64: inf with overflow and inexact.
  let (text, flags) = Binary::make(BinCoeff::one(), 2000, 113).to_shortest_string_ctx(
    b64,
  )
  assert_eq(text, "inf")
  assert_true(flags.overflow() && flags.inexact())
  // 2^-2000 underflows binary64 to zero: underflow and inexact.
  let (text, flags) = Binary::make(BinCoeff::one(), -2000, 113).to_shortest_string_ctx(
    b64,
  )
  assert_eq(text, "0")
  assert_true(flags.underflow() && flags.inexact())
  // Not-a-number and infinity are exact.
  let (text, flags) = Binary::nan().to_shortest_string_ctx(b64)
  assert_eq(text, "nan")
  assert_false(flags.inexact() || flags.invalid_operation())
}
