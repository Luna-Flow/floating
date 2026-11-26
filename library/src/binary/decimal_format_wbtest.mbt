///|
fn decimal_format_show(result : (String, BinaryFlags)) -> String {
  "\{result.0} flags=\{result.1.to_testfloat_bits()}"
}

///|
// oracle: A
// source: the strings re-derived with Python fractions and decimal (exact rational rounding, library-ran: no); the expected strings were first written from the output of this library and then re-derived independently, and all of them agree: the exact binary64 value of each number rounded to 2 significant digits in the five directions (the exact values 0.125, 2.5 and 0 are ties or exact; 9.995, 1e300 and 5e-324 are the doubles nearest to the decimals), inexact flag 1 unless the digits are exact
// shares: Binary::from_double builds the operands; to_decimal_string_ctx is the code under test; decimal_format_show prints text and flag bits
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
          Binary::from_double(number).to_decimal_string_ctx(
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
// oracle: A, S
// source: A: the 55 digits of the double 0.1, 1.000000000000000055511151231257827021181583404541015625e-1, re-derived with Python decimal (exact conversion of the double, library-ran: no); S: the textual forms -0.00e+0 and snan with flag bits 0 are the library's own output conventions
// shares: Binary::from_double, negative_zero and signaling_nan build the operands; to_decimal_string_ctx is the code under test; decimal_format_show prints text and flag bits
test "fixed-digit output is exact when enough digits are requested" {
  let context = BinaryContext::binary64()
  inspect(
    decimal_format_show(
      Binary::from_double(0.1).to_decimal_string_ctx(55, context),
    ),
    content=(
      #|1.000000000000000055511151231257827021181583404541015625e-1 flags=0
    ),
  )
  inspect(
    decimal_format_show(
      Binary::from_double(-0.0).to_decimal_string_ctx(3, context),
    ),
    content=(
      #|-0.00e+0 flags=0
    ),
  )
  inspect(
    decimal_format_show(
      Binary::signaling_nan().to_decimal_string_ctx(3, context),
    ),
    content=(
      #|snan flags=0
    ),
  )
}

///|
// oracle: A, S
// source: A: Double::to_string of the MoonBit core library (a different implementation of the shortest round-trip text, library-ran: no) on 5000 doubles of a fixed linear congruential sequence and eleven chosen values (0.1, 1e23, 5e-324, the largest and the smallest normal, 1e21, 1e-7 and others); S: the text -0 for negative zero is the library's choice (the host prints 0 for it), asserted as written
// shares: Binary::from_double builds the operands; to_shortest_string_ctx is the code under test; the host formatter is Double::to_string
test "shortest output matches the host binary64 formatter" {
  let mut state = 0xDA3E39CB94B95BDBUL
  let mut checked = 0
  for _ in 0..<5000 {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let number = state.reinterpret_as_double()
    if number.is_nan() || number.is_inf() {
      continue
    }
    let value = Binary::from_double(number)
    assert_eq(
      value.to_shortest_string_ctx(BinaryContext::binary64()).0,
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
      Binary::from_double(number).to_shortest_string_ctx(
        BinaryContext::binary64(),
      ).0,
      number.to_string(),
      msg="\{number}",
    )
  }
  // Unlike ECMAScript, negative zero keeps its sign so that it round-trips.
  inspect(Binary::from_double(-0.0).to_shortest_string(), content="-0")
  assert_true(checked > 4900)
}

///|
// oracle: A, S
// source: A: the strings 0.3333 (11 bits), 0.33333334 (24), 0.3333333333333333333333333333333333 (113) and the 91-digit string at 300 bits re-derived with Python fractions: the shortest decimal inside the rounding interval of the nearest p-bit value of 1/3, closest to the value among the shortest (library-ran: no); S: the round trip through Binary::from_string back to the same value
// shares: Binary::one, from_int and div_ctx build 1/3 at each precision; from_string reads the text back; to_shortest_string is the code under test
test "shortest output round-trips at other precisions" {
  let lines = StringBuilder()
  for precision in [11, 24, 113, 300] {
    let third = Binary::one(precision~).div_ctx(
        Binary::from_int(3, precision~),
        BinaryContext::new(precision~),
      ).0
    let text = third.to_shortest_string()
    let back = Binary::from_string(text, precision~).unwrap()
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
// oracle: A
// source: re-derived with Python decimal at 60 digits (library-ran: no): 2^1000000000 = 4.61297600116906939311611...e+301029995 and 3 * 2^-1000000000 = 6.50339390285080200651361...e-301029996 (the logarithm of 2 times the exponent, split in an integer part and a fraction); the shortest round-trip texts 4.6129760011690694e+301029995 (17 digits: 16 digits are more than half a unit away) and 6.503393902850802e-301029996 and the 20-digit rounding 4.6129760011690693931e+301029995 follow
// shares: Binary::make builds the operands; to_shortest_string and to_decimal_string_ctx are the code under test; decimal_format_show prints text and flag bits
test "huge and tiny exponents format without expanding the value" {
  let huge = Binary::make(BinCoeff::one(), 1000000000, 53)
  let tiny = Binary::make(BinCoeff::from_uint64(3UL), -1000000000, 53)
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
      huge.to_decimal_string_ctx(20, BinaryContext::new(precision=53)),
    ),
    content=(
      #|4.6129760011690693931e+301029995 flags=1
    ),
  )
}
