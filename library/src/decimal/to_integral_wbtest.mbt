///|
fn to_integral_show(result : (Decimal, DecimalFlags)) -> String {
  let (value, flags) = result
  let names = []
  if flags.invalid_operation {
    names.push("InvalidOperation")
  }
  if flags.inexact {
    names.push("Inexact")
  }
  value.to_string() + " [" + names.join(",") + "]"
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 5.9 and 5.2: an integral value is unchanged whatever the precision of the context (12345, 1.2345E+7 at precision 3, no flag), and within the precision the clamp fold-down still applies: 1E+96 in decimal32 (Etop 90) is 1.000000E+96
// shares: Decimal::from_string reads the operands; to_integral_exact_ctx and to_integral_value_ctx are the code under test; DecimalContext::new and decimal32 build the contexts; to_integral_show prints the value and the flags
test "to_integral returns integers longer than the precision unchanged" {
  let d = (s : String) => Decimal::from_string(s).unwrap()
  let p3 = DecimalContext::new(precision=3)
  inspect(
    to_integral_show(d("12345").to_integral_exact_ctx(p3)),
    content="12345 []",
  )
  inspect(
    to_integral_show(d("12345").to_integral_value_ctx(p3)),
    content="12345 []",
  )
  inspect(
    to_integral_show(d("1.2345E+7").to_integral_exact_ctx(p3)),
    content="1.2345E+7 []",
  )
  // Within the precision the clamp fold-down still applies.
  inspect(
    to_integral_show(
      d("1E+96").to_integral_exact_ctx(DecimalContext::decimal32()),
    ),
    content=(
      #|1.000000E+96 []
    ),
  )
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 5.9: 12345.6 rounds to the integer 12346 in a context of precision 3, inexact in the exact form and without flag in the value form, 12345.0 is 12345 without flag, -99.9 at precision 2 is -100 (inexact)
// shares: Decimal::from_string reads the operands; to_integral_exact_ctx and to_integral_value_ctx are the code under test; DecimalContext::new builds the contexts; to_integral_show prints the value and the flags
test "to_integral keeps integral parts longer than the precision" {
  let d = (s : String) => Decimal::from_string(s).unwrap()
  let p3 = DecimalContext::new(precision=3)
  inspect(
    to_integral_show(d("12345.6").to_integral_exact_ctx(p3)),
    content=(
      #|12346 [Inexact]
    ),
  )
  inspect(
    to_integral_show(d("12345.6").to_integral_value_ctx(p3)),
    content="12346 []",
  )
  inspect(
    to_integral_show(d("12345.0").to_integral_exact_ctx(p3)),
    content=(
      #|12345 []
    ),
  )
  inspect(
    to_integral_show(
      d("-99.9").to_integral_exact_ctx(DecimalContext::new(precision=2)),
    ),
    content=(
      #|-100 [Inexact]
    ),
  )
}
