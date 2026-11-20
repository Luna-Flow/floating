///|
fn decimal_format_show(result : (String, BinaryFlags)) -> String {
  "\{result.0} flags=\{result.1.to_testfloat_bits()}"
}

///|
test "fixed-digit output rounds in every direction" {
  let modes = [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
  ]
  let lines = StringBuilder()
  for number in [0.125, -0.125, 2.5, 0.1, 9.995, 1.0e300, 5.0e-324, 0.0] {
    lines.write_string("\{number}:")
    for mode in modes {
      lines.write_string(
        " " +
        decimal_format_show(
          BinFloat::from_double(number).to_decimal_string_ctx(
            2,
            BinaryContext::binary64(rounding=mode),
          ),
        ),
      )
    }
    lines.write_string("\n")
  }
  inspect(
    lines.to_string(),
    content=(
      #|0.125: 1.2e-1 flags=1 1.3e-1 flags=1 1.2e-1 flags=1 1.3e-1 flags=1 1.2e-1 flags=1
      #|-0.125: -1.2e-1 flags=1 -1.3e-1 flags=1 -1.2e-1 flags=1 -1.2e-1 flags=1 -1.3e-1 flags=1
      #|2.5: 2.5e+0 flags=0 2.5e+0 flags=0 2.5e+0 flags=0 2.5e+0 flags=0 2.5e+0 flags=0
      #|0.1: 1.0e-1 flags=1 1.0e-1 flags=1 1.0e-1 flags=1 1.1e-1 flags=1 1.0e-1 flags=1
      #|9.995: 1.0e+1 flags=1 1.0e+1 flags=1 9.9e+0 flags=1 1.0e+1 flags=1 9.9e+0 flags=1
      #|1e+300: 1.0e+300 flags=1 1.0e+300 flags=1 1.0e+300 flags=1 1.1e+300 flags=1 1.0e+300 flags=1
      #|5e-324: 4.9e-324 flags=1 4.9e-324 flags=1 4.9e-324 flags=1 5.0e-324 flags=1 4.9e-324 flags=1
      #|0: 0.0e+0 flags=0 0.0e+0 flags=0 0.0e+0 flags=0 0.0e+0 flags=0 0.0e+0 flags=0
      #|
    ),
  )
}

///|
test "fixed-digit output is exact when enough digits are requested" {
  let context = BinaryContext::binary64()
  inspect(
    decimal_format_show(
      BinFloat::from_double(0.1).to_decimal_string_ctx(55, context),
    ),
    content=(
      #|1.000000000000000055511151231257827021181583404541015625e-1 flags=0
    ),
  )
  inspect(
    decimal_format_show(
      BinFloat::from_double(-0.0).to_decimal_string_ctx(3, context),
    ),
    content=(
      #|-0.00e+0 flags=0
    ),
  )
  inspect(
    decimal_format_show(
      BinFloat::signaling_nan().to_decimal_string_ctx(3, context),
    ),
    content=(
      #|snan flags=0
    ),
  )
}

///|
test "shortest output matches the host binary64 formatter" {
  let mut state = 0xDA3E39CB94B95BDBUL
  let mut checked = 0
  for _ in 0..<5000 {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let number = state.reinterpret_as_double()
    if number.is_nan() || number.is_inf() {
      continue
    }
    let value = BinFloat::from_double(number)
    assert_eq(
      value.to_shortest_string_ctx(BinaryContext::binary64()),
      number.to_string(),
      msg="\{number}",
    )
    checked += 1
  }
  for
    number in [
      0.1, 0.3, 1.0e23, 5.0e-324, 1.7976931348623157e308, 2.2250738585072014e-308,
      123456789012345680.0, 1.0e21, 1.0e-7, 0.000001, 100.0,
    ] {
    assert_eq(
      BinFloat::from_double(number).to_shortest_string_ctx(
        BinaryContext::binary64(),
      ),
      number.to_string(),
      msg="\{number}",
    )
  }
  // Unlike ECMAScript, negative zero keeps its sign so that it round-trips.
  inspect(BinFloat::from_double(-0.0).to_shortest_string(), content="-0")
  assert_true(checked > 4900)
}

///|
test "shortest output round-trips at other precisions" {
  let lines = StringBuilder()
  for precision in [11, 24, 113, 300] {
    let third = BinFloat::one(precision~).div_ctx(
        BinFloat::from_int(3, precision~),
        BinaryContext::unbounded(precision),
      ).0
    let text = third.to_shortest_string()
    let back = BinFloat::from_string(text, precision~).unwrap()
    assert_eq(back.compare(third), 0, msg=text)
    lines.write_string("\{precision}: \{text}\n")
  }
  inspect(
    lines.to_string(),
    content=(
      #|11: 0.3333
      #|24: 0.33333334
      #|113: 0.3333333333333333333333333333333333
      #|300: 0.3333333333333333333333333333333333333333333333333333333333333333333333333333333333333333334
      #|
    ),
  )
}

///|
test "huge and tiny exponents format without expanding the value" {
  let huge = BinFloat::make(BinCoeff::one(), 1000000000, 53)
  let tiny = BinFloat::make(BinCoeff::from_uint64(3UL), -1000000000, 53)
  inspect(
    huge.to_shortest_string(),
    content=(
      #|4.6129760011690694e+301029995
    ),
  )
  inspect(
    tiny.to_shortest_string(),
    content=(
      #|6.503393902850802e-301029996
    ),
  )
  inspect(
    decimal_format_show(
      huge.to_decimal_string_ctx(20, BinaryContext::unbounded(53)),
    ),
    content=(
      #|4.6129760011690693931e+301029995 flags=1
    ),
  )
}
