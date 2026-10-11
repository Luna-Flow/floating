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
  let exponent = d("1E+30")
  let context = DecimalContext::new().unwrap()
  let (negative, negative_flags) = d("-2").power_ctx(exponent, context)
  let (positive, positive_flags) = d("2").power_ctx(exponent, context)
  assert_false(negative.is_nan())
  assert_false(negative_flags.invalid_context)
  assert_false(positive.is_nan())
  assert_false(positive_flags.invalid_context)
  assert_eq(negative, positive)
}
