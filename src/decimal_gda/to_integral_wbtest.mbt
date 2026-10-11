///|
fn to_integral_show(outcome : GdaOutcome[Decimal]) -> String {
  let flags = outcome.raised()
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
  outcome.value().to_string() + " [" + names.join(",") + "]"
}

///|
test "to_integral keeps integral parts longer than the precision" {
  let d = (s : String) => Decimal::from_string(s).unwrap()
  let p3 = GdaContext::new(precision=3, e_min=-999_999, e_max=999_999).unwrap()
  inspect(
    to_integral_show(to_integral_exact(d("12345.6"), p3)),
    content="12346 [Inexact,Rounded]",
  )
  inspect(
    to_integral_show(to_integral_value(d("12345.6"), p3)),
    content="12346 []",
  )
  inspect(
    to_integral_show(to_integral_exact(d("12345.0"), p3)),
    content="12345 [Rounded]",
  )
  inspect(
    to_integral_show(
      to_integral_exact(d("-99.9"), GdaContext::new(precision=2).unwrap()),
    ),
    content="-100 [Inexact,Rounded]",
  )
  // Operands with a non-negative exponent are returned unchanged (#59).
  inspect(
    to_integral_show(to_integral_exact(d("12345"), p3)),
    content="12345 []",
  )
  inspect(
    to_integral_show(to_integral_value(d("12345"), p3)),
    content="12345 []",
  )
  inspect(
    to_integral_show(to_integral_exact(d("1.2345E+7"), p3)),
    content="1.2345E+7 []",
  )
}
