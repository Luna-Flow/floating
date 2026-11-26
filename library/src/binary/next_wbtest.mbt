///|
fn next_show(result : (Binary, BinaryFlags)) -> String {
  "\{result.0} flags=\{result.1.to_testfloat_bits()}"
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 5.3.1 (nextUp and nextDown, the least greater and the greatest lesser representable number; nextUp(-0) is the smallest positive subnormal; nextUp(-smallest subnormal) is -0; nextUp(+inf) = +inf and nextDown(+inf) is the largest finite value; a signaling NaN is invalid): 1 up 1 + 2^-52 = 4503599627370497p-52, 1 down 9007199254740991p-53, the largest finite (2^53 - 1) 2^971 up inf and down (2^52 - 1) 2^972
// shares: Binary::make, one, zero, negative_zero and inf build the operands; next_up_ctx and next_down_ctx are the code under test; next_show prints value and flag bits
test "nextUp and nextDown walk the binary64 grid" {
  let context = BinaryContext::binary64()
  let max = Binary::make(
    BinCoeff::from_uint64((1UL << 53) - 1UL),
    1023 - 52,
    53,
  )
  let min_subnormal = Binary::make(BinCoeff::one(), -1074, 53)
  let lines = StringBuilder()
  for
    value in [
      Binary::one(),
      Binary::one().neg(),
      Binary::zero(),
      Binary::negative_zero(),
      max,
      min_subnormal.neg(),
      Binary::inf(),
      Binary::inf(negative=true),
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
    next_show(Binary::signaling_nan().next_up_ctx(context)),
    content=(
      #|nan flags=16
    ),
  )
}

///|
// oracle: S
// source: the successor of the host's own binary64 encoding (the bit pattern plus or minus one, a machine property independent of the library) on six doubles; the operand and the expected value are both built with Binary::from_double, a shared builder without a level A block of its own here, so the level is stated as S
// shares: Binary::from_double on both sides; next_up_ctx is the code under test
test "nextUp agrees with the host double successor" {
  let context = BinaryContext::binary64()
  for number in [0.1, -0.1, 1.0e300, -2.0e-308, 4.9e-324, 123456.789] {
    let up = Binary::from_double(number).next_up_ctx(context).0
    let bits = number.reinterpret_as_uint64()
    let host = (if number > 0.0 { bits + 1UL } else { bits - 1UL }).reinterpret_as_double()
    assert_identical(up, Binary::from_double(host), msg="\{number}")
  }
}

///|
// oracle: A
// source: written out: 1 + 2^-30 is not a binary32 value; the least binary32 value above it is 1 + 2^-23 = 8388609p-23 and the greatest below it is 1 (IEEE Std 754-2019 5.3.1)
// shares: Binary::make builds the operand; next_up_ctx and next_down_ctx are the code under test; next_show prints value and flag bits
test "nextUp of a wider operand is the least greater representable" {
  let context = BinaryContext::binary32()
  // 1 + 2^-30 is not a binary32 value; the next binary32 above it is 1 + 2^-23.
  let wide = Binary::make(BinCoeff::from_uint64((1UL << 30) + 1UL), -30, 64)
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
