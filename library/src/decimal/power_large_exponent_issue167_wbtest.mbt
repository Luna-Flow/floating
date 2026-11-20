///|
fn power_issue167_case(result : (Decimal, DecimalFlags)) -> String {
  let (value, flags) = result
  let mut text = value.to_string()
  if flags.inexact {
    text = text + " inexact"
  }
  if flags.rounded {
    text = text + " rounded"
  }
  if flags.underflow {
    text = text + " underflow"
  }
  if flags.overflow {
    text = text + " overflow"
  }
  if flags.division_by_zero {
    text = text + " division_by_zero"
  }
  if flags.invalid_operation {
    text = text + " invalid_operation"
  }
  text
}

///|
/// IEEE 754-2019 §9.2.1 defines integral powers independently of the
/// implementation's bounded integer-power loop.
test "decimal power handles integral exponents beyond the bounded count" {
  let ctx = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  inspect(
    power_issue167_case(d("-2").power_ctx(d("1E+30"), ctx)),
    content=(
      #|inf inexact rounded overflow
    ),
  )
  inspect(
    power_issue167_case(d("-0.5").power_ctx(d("1E+30"), ctx)),
    content=(
      #|0E-398 inexact rounded underflow
    ),
  )
  inspect(
    power_issue167_case(d("-0.5").power_ctx(d("-1E+30"), ctx)),
    content=(
      #|inf inexact rounded overflow
    ),
  )
  inspect(
    power_issue167_case(
      d("-1.000000000000001").power_ctx(d("12345678901234567"), ctx),
    ),
    content=(
      #|-229964.1948529869 inexact rounded
    ),
  )
  inspect(
    power_issue167_case(d("-0").power_ctx(d("-12345678901234567"), ctx)),
    content=(
      #|-inf division_by_zero
    ),
  )
  inspect(
    power_issue167_case(
      d("-1.000000000000001").power_ctx(d("-12345678901234567"), ctx),
    ),
    content=(
      #|-0.000004348503038219871 inexact rounded
    ),
  )
}

///|
/// IEEE 754-2019 §9.2.1 also defines zero and infinite bases for arbitrary
/// integral exponents, including the limits of the Int representation.
test "decimal power handles zero and infinity at large integer exponents" {
  let ctx = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  inspect(
    power_issue167_case(d("0").power_ctx(d("1E+30"), ctx)),
    content=(
      #|0
    ),
  )
  inspect(
    power_issue167_case(d("Inf").power_ctx(d("1E+30"), ctx)),
    content=(
      #|inf
    ),
  )
  inspect(
    power_issue167_case(d("-0").power_ctx(d("12345678901234567"), ctx)),
    content=(
      #|-0
    ),
  )
  inspect(
    power_issue167_case(d("-0").power_ctx(d("-1E+30"), ctx)),
    content=(
      #|inf division_by_zero
    ),
  )
  inspect(
    power_issue167_case(d("-Inf").power_ctx(d("12345678901234567"), ctx)),
    content=(
      #|-inf
    ),
  )
  inspect(
    power_issue167_case(d("-Inf").power_ctx(d("-12345678901234567"), ctx)),
    content=(
      #|-0
    ),
  )
  inspect(
    power_issue167_case(d("0").pown_ctx(2147483647, ctx)),
    content=(
      #|0
    ),
  )
  inspect(
    power_issue167_case(d("-0").pown_ctx(2147483647, ctx)),
    content=(
      #|-0
    ),
  )
  inspect(
    power_issue167_case(d("Inf").pown_ctx(2147483647, ctx)),
    content=(
      #|inf
    ),
  )
  inspect(
    power_issue167_case(d("-Inf").pown_ctx(2147483647, ctx)),
    content=(
      #|-inf
    ),
  )
  inspect(
    power_issue167_case(d("Inf").pown_ctx(-2147483648, ctx)),
    content=(
      #|0
    ),
  )
  inspect(
    power_issue167_case(d("-Inf").pown_ctx(-2147483648, ctx)),
    content=(
      #|0
    ),
  )
}

///|
/// A zero base has a defined result for a tiny positive non-integral exponent;
/// operand range checks must not turn this domain case into Invalid operation.
test "decimal power keeps zero defined for tiny nonintegral exponents" {
  let ctx = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  inspect(
    power_issue167_case(d("0").power_ctx(d("1E-2000000"), ctx)),
    content=(
      #|0
    ),
  )
  inspect(
    power_issue167_case(d("-0").power_ctx(d("1E-2000000"), ctx)),
    content=(
      #|0
    ),
  )
  inspect(
    power_issue167_case(d("0").power_ctx(d("-1E-2000000"), ctx)),
    content=(
      #|inf division_by_zero
    ),
  )
  inspect(
    power_issue167_case(d("-0").power_ctx(d("-1E-2000000"), ctx)),
    content=(
      #|inf division_by_zero
    ),
  )
}

///|
/// Negating a positive result must reverse directed rounding, so negative-base
/// odd powers use the mirrored magnitude context before certification.
test "decimal large negative-base powers mirror directed rounding" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let base = d("-1.000000000000001")
  let exponent = d("12345678901234567")
  let down = DecimalContext::decimal64().with_rounding(
    RoundingMode::TowardNegative,
  )
  let up = DecimalContext::decimal64().with_rounding(
    RoundingMode::TowardPositive,
  )
  assert_eq(
    base.power_ctx(exponent, up).0.to_string(),
    d("1.000000000000001").power_ctx(exponent, down).0.neg().to_string(),
  )
  assert_eq(
    base.power_ctx(exponent, down).0.to_string(),
    d("1.000000000000001").power_ctx(exponent, up).0.neg().to_string(),
  )
}

///|
/// The ordinary context has the full representation exponent range. An
/// integer power remains defined there even when its count exceeds the
/// bounded square-and-multiply helper.
test "decimal large integer powers work in the default context" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let context = DecimalContext::new().unwrap()
  let cases = [
    ("1.0000000000001", "1E+11", "1.010050167084167552517081914852626"),
    ("0.999999", "1000000001", "5.073416477377115719975853397616633E-435"),
    ("-1.000001", "1000000001", "-1.969088294420576654510139814956395E+434"),
    ("2", "1E+9", "4.612976001169069393116119221037316E+301029995"),
    ("1.01", "1E+10", "6.705416252570703534199491376911599E+43213737"),
  ]
  for (base, exponent, expected) in cases {
    let (value, flags) = d(base).power_ctx(d(exponent), context)
    assert_eq(value.to_string(), expected)
    assert_true(flags.inexact)
    assert_true(flags.rounded)
    assert_false(flags.invalid_context)
    assert_false(flags.invalid_operation)
    assert_false(flags.division_by_zero)
    assert_false(flags.overflow)
    assert_false(flags.underflow)
    assert_false(flags.subnormal)
    assert_false(flags.clamped)
  }
}

///|
/// Exponents whose exact coefficient exceeds the bounded materialization
/// budget are never expanded: the magnitude of `y ln|x|` decides overflow or
/// underflow directly (#196), so `2^(1E+9999999)` overflows instead of
/// returning invalid_context, with no expansion of millions of decimal limbs
/// and no unbounded certification loop.
test "decimal large integer powers enforce the expansion budget" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let context = DecimalContext::new().unwrap()
  let (value, flags) = d("2").power_ctx(d("1E+9999999"), context)
  assert_true(value.is_infinite())
  assert_true(flags.overflow && flags.inexact)
  assert_false(flags.invalid_context)
  let (exp2, exp2_flags) = d("1E+9999999").exp2_ctx(context)
  let (exp10, exp10_flags) = d("1E+9999999").exp10_ctx(context)
  // `exp2` and `exp10` reject such arguments before they reach `power_ctx`.
  assert_true(exp2.is_nan())
  assert_true(exp2_flags.invalid_context)
  assert_true(exp10.is_nan())
  assert_true(exp10_flags.invalid_context)
  let (small, small_flags) = d("0.5").power_ctx(d("1E+9999999"), context)
  assert_true(small.is_zero())
  assert_true(small_flags.underflow && small_flags.inexact)
}

///|
/// The expected strings below were generated independently with Python's
/// `decimal` module at precision 34 and the same exponent bounds.  Directed
/// rounding must survive the large integer route, including sign reversal.
test "decimal large integer powers honor all rounding modes" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let context = DecimalContext::new().unwrap()
  let modes = [
    (
      RoundingMode::ToNearestEven,
      "4.612976001169069393116119221037316E+301029995",
    ),
    (
      RoundingMode::AwayFromZero,
      "4.612976001169069393116119221037317E+301029995",
    ),
    (RoundingMode::TowardZero, "4.612976001169069393116119221037316E+301029995"),
    (
      RoundingMode::TowardPositive,
      "4.612976001169069393116119221037317E+301029995",
    ),
    (
      RoundingMode::TowardNegative,
      "4.612976001169069393116119221037316E+301029995",
    ),
  ]
  for (mode, expected) in modes {
    let (value, flags) = d("2").power_ctx(
      d("1E+9"),
      context.with_rounding(mode),
    )
    assert_eq(value.to_string(), expected)
    assert_true(flags.inexact)
    assert_true(flags.rounded)
  }
  let (ceiling, _) = d("-1.000001").power_ctx(
    d("1000000001"),
    context.with_rounding(RoundingMode::TowardPositive),
  )
  let (floor, _) = d("-1.000001").power_ctx(
    d("1000000001"),
    context.with_rounding(RoundingMode::TowardNegative),
  )
  assert_eq(ceiling.to_string(), "-1.969088294420576654510139814956394E+434")
  assert_eq(floor.to_string(), "-1.969088294420576654510139814956395E+434")
}

///|
/// Mirror the independent Python 34-digit oracle for an odd negative-base
/// exponent. These absolute expected values kill a lost-parity or rounding
/// direction regression without comparing the implementation to itself.
test "decimal large integer negative powers match directed oracle values" {
  let base = Decimal::from_string("-1.000001").unwrap()
  let exponent = Decimal::from_string("1000000001").unwrap()
  let context = DecimalContext::new().unwrap()
  let (ceiling, ceiling_flags) = base.power_ctx(
    exponent,
    context.with_rounding(RoundingMode::TowardPositive),
  )
  let (floor, floor_flags) = base.power_ctx(
    exponent,
    context.with_rounding(RoundingMode::TowardNegative),
  )
  assert_eq(ceiling.to_string(), "-1.969088294420576654510139814956394E+434")
  assert_eq(floor.to_string(), "-1.969088294420576654510139814956395E+434")
  assert_true(ceiling_flags.inexact)
  assert_true(ceiling_flags.rounded)
  assert_true(floor_flags.inexact)
  assert_true(floor_flags.rounded)
}

///|
/// Python decimal p=9 oracle strings for the default exponent limits.
test "decimal large integer powers work at precision nine" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let context = DecimalContext::new(precision=9).unwrap()
  let cases = [
    ("1.0000000000001", "1E+11", "1.01005017"),
    ("0.999999", "1000000001", "5.07341648E-435"),
    ("-1.000001", "1000000001", "-1.96908829E+434"),
    ("2", "1E+9", "4.61297600E+301029995"),
    ("1.01", "1E+10", "6.70541625E+43213737"),
  ]
  for (base, exponent, expected) in cases {
    let (value, flags) = d(base).power_ctx(d(exponent), context)
    assert_eq(value.to_string(), expected)
    assert_true(flags.inexact)
    assert_true(flags.rounded)
    assert_false(flags.invalid_context)
  }
}

///|
/// Decimal spellings with trailing zeros must share the same parity and
/// bounded power path as their canonical coefficient form.
test "decimal large integer exponent spellings preserve parity" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let context = DecimalContext::new().unwrap()
  for exponent in ["1.0E+30", "10E+29", "100E+28"] {
    let (value, flags) = d("-2").power_ctx(d(exponent), context)
    assert_eq(value.to_string(), "inf")
    assert_true(flags.overflow)
    assert_false(flags.invalid_context)
  }
  let (value, flags) = d("-1.000000000000001").power_ctx(
    d("12345678901234567E+0"),
    context,
  )
  assert_eq(value.to_string(), "-229964.1948529869209840694937236457")
  assert_true(flags.inexact)
  assert_true(flags.rounded)
  let (even, even_flags) = d("-1.000001").power_ctx(
    d("1234567890123456789012345678900"),
    context,
  )
  let (odd, odd_flags) = d("-1.000001").power_ctx(
    d("1234567890123456789012345678901"),
    context,
  )
  assert_eq(even.to_string(), "inf")
  assert_eq(odd.to_string(), "-inf")
  assert_true(even_flags.overflow)
  assert_true(odd_flags.overflow)
  assert_true(even_flags.inexact)
  assert_true(odd_flags.inexact)
}

///|
/// IEEE special values remain exact even when the exponent itself is beyond
/// the bounded coefficient materialization budget.
test "decimal large integer powers keep signed zero and infinity" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let context = DecimalContext::new().unwrap()
  let (zero, zero_flags) = d("-0").power_ctx(d("1E+9999999"), context)
  let (infinity, infinity_flags) = d("-Inf").power_ctx(
    d("12345678901234567E+0"),
    context,
  )
  assert_eq(zero.to_string(), "0")
  assert_false(zero_flags.invalid_context)
  assert_eq(infinity.to_string(), "-inf")
  assert_false(infinity_flags.invalid_context)
}

///|
/// A subset context still returns the correct finite result when its exponent
/// range admits it; a smaller range uses the IEEE overflow result.
test "decimal large integer powers support extended and subset contexts" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let extended = DecimalContext::new().unwrap()
  let subset = DecimalContext::new(
    precision=34,
    e_min=-999_999_999,
    e_max=384,
    extended=false,
  ).unwrap()
  let (wide, wide_flags) = d("2").power_ctx(d("1E+9"), extended)
  let (narrow, narrow_flags) = d("2").power_ctx(d("1E+9"), subset)
  assert_eq(wide.to_string(), "4.612976001169069393116119221037316E+301029995")
  assert_false(wide_flags.invalid_context)
  assert_eq(narrow.to_string(), "inf")
  assert_true(narrow_flags.overflow)
  assert_false(narrow_flags.invalid_context)
}
