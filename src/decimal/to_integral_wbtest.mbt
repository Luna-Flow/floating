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
  if flags.rounded {
    names.push("Rounded")
  }
  if flags.lost_digits {
    names.push("LostDigits")
  }
  if flags.clamped {
    names.push("Clamped")
  }
  value.to_string() + " [" + names.join(",") + "]"
}

///|
test "to_integral returns integers longer than the precision unchanged" {
  let d = (s : String) => Decimal::from_string(s).unwrap()
  let p3 = DecimalContext::new(precision=3)
  inspect(
    to_integral_show(d("12345").to_integral_exact(p3)),
    content="12345 []",
  )
  inspect(
    to_integral_show(d("12345").to_integral_value(p3)),
    content="12345 []",
  )
  inspect(
    to_integral_show(d("1.2345E+7").to_integral_exact(p3)),
    content="1.2345E+7 []",
  )
  // Within the precision the clamp fold-down still applies.
  inspect(
    to_integral_show(d("1E+96").to_integral_exact(DecimalContext::decimal32())),
    content="1.000000E+96 [Clamped]",
  )
}

///|
test "to_integral keeps integral parts longer than the precision" {
  let d = (s : String) => Decimal::from_string(s).unwrap()
  let p3 = DecimalContext::new(precision=3)
  inspect(
    to_integral_show(d("12345.6").to_integral_exact(p3)),
    content="12346 [Inexact,Rounded]",
  )
  inspect(
    to_integral_show(d("12345.6").to_integral_value(p3)),
    content="12346 []",
  )
  inspect(
    to_integral_show(d("12345.0").to_integral_exact(p3)),
    content="12345 [Rounded]",
  )
  inspect(
    to_integral_show(
      d("-99.9").to_integral_exact(DecimalContext::new(precision=2)),
    ),
    content="-100 [Inexact,Rounded]",
  )
}

///|
test "to_integral in a subset context rounds the operand first" {
  let d = (s : String) => Decimal::from_string(s).unwrap()
  let p3 = DecimalContext::new(precision=3, extended=false)
  inspect(
    to_integral_show(d("12345.6").to_integral_exact(p3)),
    content="1.23E+4 [Inexact,Rounded,LostDigits]",
  )
  inspect(
    to_integral_show(d("12345.6").to_integral_value(p3)),
    content="1.23E+4 [Inexact,Rounded,LostDigits]",
  )
}
