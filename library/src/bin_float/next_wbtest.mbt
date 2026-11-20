///|
fn next_show(result : (BinFloat, BinaryFlags)) -> String {
  "\{result.0} flags=\{result.1.to_testfloat_bits()}"
}

///|
test "nextUp and nextDown walk the binary64 grid" {
  let context = BinaryContext::binary64()
  let max = BinFloat::make(
    BinCoeff::from_uint64((1UL << 53) - 1UL),
    1023 - 52,
    53,
  )
  let min_subnormal = BinFloat::make(BinCoeff::one(), -1074, 53)
  let lines = StringBuilder()
  for
    value in [
      BinFloat::one(),
      BinFloat::one().neg(),
      BinFloat::zero(),
      BinFloat::negative_zero(),
      max,
      min_subnormal.neg(),
      BinFloat::inf(Sign::Positive),
      BinFloat::inf(Sign::Negative),
    ] {
    lines.write_string(
      "\{value}: up \{next_show(value.next_up_ctx(context))} down \{next_show(value.next_down_ctx(context))}\n",
    )
  }
  inspect(
    lines.to_string(),
    content=(
      #|1p0: up 4503599627370497p-52 flags=0 down 9007199254740991p-53 flags=0
      #|-1p0: up -9007199254740991p-53 flags=0 down -4503599627370497p-52 flags=0
      #|0: up 1p-1074 flags=0 down -1p-1074 flags=0
      #|-0: up 1p-1074 flags=0 down -1p-1074 flags=0
      #|9007199254740991p971: up inf flags=0 down 4503599627370495p972 flags=0
      #|-1p-1074: up -0 flags=0 down -1p-1073 flags=0
      #|inf: up inf flags=0 down 9007199254740991p971 flags=0
      #|-inf: up -9007199254740991p971 flags=0 down -inf flags=0
      #|
    ),
  )
  inspect(
    next_show(BinFloat::signaling_nan().next_up_ctx(context)),
    content=(
      #|nan flags=16
    ),
  )
}

///|
test "nextUp agrees with the host double successor" {
  let context = BinaryContext::binary64()
  for number in [0.1, -0.1, 1.0e300, -2.0e-308, 4.9e-324, 123456.789] {
    let up = BinFloat::from_double(number).next_up_ctx(context).0
    let bits = number.reinterpret_as_uint64()
    let host = (if number > 0.0 { bits + 1UL } else { bits - 1UL }).reinterpret_as_double()
    assert_eq(up, BinFloat::from_double(host), msg="\{number}")
  }
}

///|
test "nextUp of a wider operand is the least greater representable" {
  let context = BinaryContext::binary32()
  // 1 + 2^-30 is not a binary32 value; the next binary32 above it is 1 + 2^-23.
  let wide = BinFloat::make(BinCoeff::from_uint64((1UL << 30) + 1UL), -30, 64)
  inspect(
    next_show(wide.next_up_ctx(context)),
    content=(
      #|8388609p-23 flags=0
    ),
  )
  inspect(
    next_show(wide.next_down_ctx(context)),
    content=(
      #|1p0 flags=0
    ),
  )
}
