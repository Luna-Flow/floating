// #448: `to_shortest_string_ctx` rounds the operand into the context first
// (round to nearest even) and prints the shortest string of that rounded value;
// it used to panic when the operand was not representable in the context.

///|
test "shortest string of an operand not representable in the context (#448)" {
  let third = BinFloat::from_int(1, precision=113).div(
    BinFloat::from_int(3, precision=113),
  )
  let b64 = BinaryContext::binary64()
  assert_eq(third.to_shortest_string_ctx(b64), "0.3333333333333333")
  assert_eq(third.neg().to_shortest_string_ctx(b64), "-0.3333333333333333")
  // The rounded value is the double nearest 1/3: the same text as the double.
  assert_eq(
    third.to_shortest_string_ctx(b64),
    BinFloat::from_double(1.0 / 3.0).to_shortest_string_ctx(b64),
  )
  // binary32: 1/3 rounds to 0.33333334.
  assert_eq(
    third.to_shortest_string_ctx(BinaryContext::binary32()),
    "0.33333334",
  )
}

///|
test "shortest string rounds overflow and underflow into the context (#448)" {
  let b64 = BinaryContext::binary64()
  let big = BinFloat::make(BinCoeff::one(), 2000, 113)
  assert_eq(big.to_shortest_string_ctx(b64), "inf")
  assert_eq(big.neg().to_shortest_string_ctx(b64), "-inf")
  let tiny = BinFloat::make(BinCoeff::one(), -2000, 113)
  assert_eq(tiny.to_shortest_string_ctx(b64), "0")
  assert_eq(tiny.neg().to_shortest_string_ctx(b64), "-0")
  // Half of the smallest subnormal ties to even (zero); a bit more rounds up.
  let half = BinFloat::make(BinCoeff::one(), -1075, 113)
  assert_eq(half.to_shortest_string_ctx(b64), "0")
  let above = BinFloat::make(BinCoeff::from_uint64(3UL), -1076, 113)
  assert_eq(above.to_shortest_string_ctx(b64), "5e-324")
}

///|
test "representable operands print as before (#448)" {
  let b64 = BinaryContext::binary64()
  assert_eq(BinFloat::from_double(0.1).to_shortest_string_ctx(b64), "0.1")
  assert_eq(
    BinFloat::from_double(4.9406564584124654e-324).to_shortest_string_ctx(b64),
    "5e-324",
  )
  assert_eq(BinFloat::from_double(-0.0).to_shortest_string_ctx(b64), "-0")
  assert_eq(
    BinFloat::from_double(1000000000000000000000.0).to_shortest_string_ctx(b64),
    "1e+21",
  )
  assert_eq(BinFloat::nan().to_shortest_string_ctx(b64), "nan")
}

///|
test "the operand is rounded in the rounding direction of the context (#448)" {
  let third = BinFloat::from_int(1, precision=113).div(
    BinFloat::from_int(3, precision=113),
  )
  // The double nearest 1/3 is below it, so toward positive gives the next one.
  assert_eq(
    third.to_shortest_string_ctx(BinaryContext::binary64()),
    "0.3333333333333333",
  )
  assert_eq(
    third.to_shortest_string_ctx(
      BinaryContext::binary64(rounding=RoundTowardPositive),
    ),
    "0.33333333333333337",
  )
  assert_eq(
    third.to_shortest_string_ctx(
      BinaryContext::binary64(rounding=RoundTowardNegative),
    ),
    "0.3333333333333333",
  )
  assert_eq(
    third
    .neg()
    .to_shortest_string_ctx(
      BinaryContext::binary64(rounding=RoundTowardNegative),
    ),
    "-0.33333333333333337",
  )
  // A directed overflow stops at the largest finite value instead of inf.
  let big = BinFloat::make(BinCoeff::one(), 2000, 113)
  assert_eq(
    big.to_shortest_string_ctx(
      BinaryContext::binary64(rounding=RoundTowardZero),
    ),
    "1.7976931348623157e+308",
  )
}
