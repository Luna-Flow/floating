///|
fn integral_show(result : (BinFloat, BinaryFlags)) -> String {
  "\{result.0} flags=\{result.1.to_testfloat_bits()}"
}

///|
test "roundToIntegral covers every direction on halfway and fractional values" {
  let modes = [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
    BinaryRoundingMode::RoundAwayFromZero,
  ]
  let lines = StringBuilder()
  for number in [2.5, -2.5, 3.5, 0.3, -0.3, -0.5, 7.0, 1.0e30] {
    let value = BinFloat::from_double(number)
    lines.write_string(number.to_string() + ":")
    for mode in modes {
      let context = BinaryContext::binary64(rounding=mode)
      lines.write_string(
        " " + value.to_integral_value_ctx(context).0.to_string(),
      )
    }
    lines.write_string("\n")
  }
  inspect(
    lines.to_string(),
    content=(
      #|2.5: 1p1 3p0 1p1 3p0 1p1 3p0
      #|-2.5: -1p1 -3p0 -1p1 -1p1 -3p0 -3p0
      #|3.5: 1p2 1p2 3p0 1p2 3p0 1p2
      #|0.3: 0 0 0 1p0 0 1p0
      #|-0.3: -0 -0 -0 -0 -1p0 -1p0
      #|-0.5: -0 -1p0 -0 -0 -1p0 -1p0
      #|7: 7p0 7p0 7p0 7p0 7p0 7p0
      #|1e+30: 3552713678800501p48 3552713678800501p48 3552713678800501p48 3552713678800501p48 3552713678800501p48 3552713678800501p48
      #|
    ),
  )
}

///|
test "roundToIntegralExact raises inexact only when the value changes" {
  let context = BinaryContext::binary64()
  inspect(
    integral_show(BinFloat::from_double(2.5).to_integral_exact_ctx(context)),
    content=(
      #|1p1 flags=1
    ),
  )
  inspect(
    integral_show(BinFloat::from_double(4.0).to_integral_exact_ctx(context)),
    content=(
      #|1p2 flags=0
    ),
  )
  inspect(
    integral_show(BinFloat::from_double(2.5).to_integral_value_ctx(context)),
    content=(
      #|1p1 flags=0
    ),
  )
  inspect(
    integral_show(BinFloat::signaling_nan().to_integral_value_ctx(context)),
    content=(
      #|nan flags=16
    ),
  )
  inspect(
    integral_show(BinFloat::inf(Sign::Negative).to_integral_exact_ctx(context)),
    content=(
      #|-inf flags=0
    ),
  )
}

///|
test "convenience rounding functions" {
  let value = BinFloat::from_double(-1.5)
  inspect(
    "\{value.floor()} \{value.ceil()} \{value.trunc()} \{value.round()} \{value.round_ties_even()}",
    content=(
      #|-1p1 -1p0 -1p0 -1p1 -1p1
    ),
  )
  let tiny = BinFloat::make(BinCoeff::one(), -1000000000, 53)
  inspect(
    "\{tiny.floor()} \{tiny.ceil()} \{tiny.neg().ceil()}",
    content=(
      #|0 1p0 -0
    ),
  )
}
