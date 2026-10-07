///|
fn decimal_string_show(source : String, context : BinaryContext) -> String {
  match BinFloat::from_string_ctx(source, context) {
    Ok((value, flags)) => "\{value} flags=\{flags.to_testfloat_bits()}"
    Err(_) => "error"
  }
}

///|
test "decimal strings round correctly at binary64 hard cases" {
  let context = BinaryContext::binary64()
  let lines = StringBuilder()
  for
    source in [
      "9007199254740993", "9007199254740995", "0.1", "-0.1", "1e23", "2.2250738585072011e-308",
      "4.9406564584124654e-324", "2.4703282292062327e-324", "2.4703282292062328e-324",
      "1.7976931348623157e308", "1.7976931348623158e308", "1.7976931348623159e308",
      "1e400", "-1e-400", "0e999999999999", "-0.000", "123.456e-2",
    ] {
    lines.write_string(
      source + " -> " + decimal_string_show(source, context) + "\n",
    )
  }
  inspect(
    lines.to_string(),
    content=(
      #|9007199254740993 -> 1p53 flags=1
      #|9007199254740995 -> 2251799813685249p2 flags=1
      #|0.1 -> 3602879701896397p-55 flags=1
      #|-0.1 -> -3602879701896397p-55 flags=1
      #|1e23 -> 2980232238769531p25 flags=1
      #|2.2250738585072011e-308 -> 4503599627370495p-1074 flags=3
      #|4.9406564584124654e-324 -> 1p-1074 flags=3
      #|2.4703282292062327e-324 -> 0 flags=3
      #|2.4703282292062328e-324 -> 1p-1074 flags=3
      #|1.7976931348623157e308 -> 9007199254740991p971 flags=1
      #|1.7976931348623158e308 -> 9007199254740991p971 flags=1
      #|1.7976931348623159e308 -> inf flags=5
      #|1e400 -> inf flags=5
      #|-1e-400 -> -0 flags=3
      #|0e999999999999 -> 0 flags=0
      #|-0.000 -> -0 flags=0
      #|123.456e-2 -> 694995494495815p-49 flags=1
      #|
    ),
  )
}

///|
test "decimal strings honour every rounding direction" {
  let modes = [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
  ]
  let lines = StringBuilder()
  // 1 + 2^-24 is the binary32 midpoint between 1 and 1 + 2^-23.
  for
    source in [
      "1.000000059604644775390625", "-1.000000059604644775390625", "0.1",
    ] {
    lines.write_string(source + ":")
    for mode in modes {
      lines.write_string(
        " " +
        decimal_string_show(source, BinaryContext::binary32(rounding=mode)),
      )
    }
    lines.write_string("\n")
  }
  inspect(
    lines.to_string(),
    content=(
      #|1.000000059604644775390625: 1p0 flags=1 8388609p-23 flags=1 1p0 flags=1 8388609p-23 flags=1 1p0 flags=1
      #|-1.000000059604644775390625: -1p0 flags=1 -8388609p-23 flags=1 -1p0 flags=1 -1p0 flags=1 -8388609p-23 flags=1
      #|0.1: 13421773p-27 flags=1 13421773p-27 flags=1 3355443p-25 flags=1 13421773p-27 flags=1 3355443p-25 flags=1
      #|
    ),
  )
}

///|
test "decimal strings parse specials and reject malformed input" {
  let context = BinaryContext::binary64()
  let lines = StringBuilder()
  for
    source in [
      "inf", "-Infinity", "NaN", "-snan", " 42 ", "+.5", "5.", "", "1e", "1.2.3",
      "0x10", "e5", "--1",
    ] {
    lines.write_string(
      "'" + source + "' -> " + decimal_string_show(source, context) + "\n",
    )
  }
  inspect(
    lines.to_string(),
    content=(
      #|'inf' -> inf flags=0
      #|'-Infinity' -> -inf flags=0
      #|'NaN' -> nan flags=0
      #|'-snan' -> nan flags=0
      #|' 42 ' -> 21p1 flags=0
      #|'+.5' -> 1p-1 flags=0
      #|'5.' -> 5p0 flags=0
      #|'' -> error
      #|'1e' -> error
      #|'1.2.3' -> error
      #|'0x10' -> error
      #|'e5' -> error
      #|'--1' -> error
      #|
    ),
  )
}

///|
test "decimal strings with huge exponents stay cheap" {
  let unbounded = BinaryContext::unbounded(53)
  inspect(
    decimal_string_show("1e300000000", unbounded),
    content=(
      #|6221607060202725p996578376 flags=1
    ),
  )
  inspect(
    decimal_string_show("1e-300000000", unbounded),
    content=(
      #|1629997636253067p-996578479 flags=1
    ),
  )
  inspect(
    decimal_string_show("1e99999999999999999999", unbounded),
    content=(
      #|inf flags=5
    ),
  )
  // 10^100000 needs about 332,193 bits; the Ziv path rounds it at 53 bits.
  inspect(
    decimal_string_show("1e100000", unbounded),
    content=(
      #|3946482393504543p332141 flags=1
    ),
  )
}

///|
test "decimal strings round-trip the host binary64 shortest form" {
  let context = BinaryContext::binary64()
  let mut state = 0x853C49E6748FEA9BUL
  let mut checked = 0
  for _ in 0..<20000 {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let bits = state
    let number = bits.reinterpret_as_double()
    if number.is_nan() || number.is_inf() {
      continue
    }
    let text = number.to_string()
    let parsed = BinFloat::from_string_ctx(text, context).unwrap().0
    assert_eq(parsed.compare(BinFloat::from_double(number)), 0, msg=text)
    assert_eq(
      parsed.is_negative(),
      number < 0.0 || (number == 0.0 && 1.0 / number < 0.0),
      msg=text,
    )
    checked += 1
  }
  assert_true(checked > 19000)
}

///|
test "arbitrary precision parses agree with exact rational rounding" {
  // 1/3 at 200 bits: the decimal string of many threes approaches 1/3 from
  // below, so it rounds like the binary expansion of 0.333... truncated.
  let context = BinaryContext::unbounded(200)
  let thirds = "0." + "3".repeat(80)
  let parsed = BinFloat::from_string_ctx(thirds, context).unwrap().0
  let exact = BinFloat::one(precision=200).div_ctx(
      BinFloat::from_int(3, precision=200),
      context,
    ).0
  inspect(
    parsed.compare(exact),
    content=(
      #|0
    ),
  )
  inspect(parsed.precision(), content="200")
}
