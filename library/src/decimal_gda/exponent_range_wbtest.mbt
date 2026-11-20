///|
fn exponent_range_flags(flags : GdaFlags) -> String {
  let names = []
  if flags.overflow {
    names.push("Overflow")
  }
  if flags.underflow {
    names.push("Underflow")
  }
  if flags.subnormal {
    names.push("Subnormal")
  }
  if flags.inexact {
    names.push("Inexact")
  }
  if flags.rounded {
    names.push("Rounded")
  }
  if flags.clamped {
    names.push("Clamped")
  }
  if flags.conversion_syntax {
    names.push("ConversionSyntax")
  }
  names.join(",")
}

///|
fn exponent_range_show(outcome : GdaOutcome[Decimal]) -> String {
  outcome.value().to_string() +
  " [" +
  exponent_range_flags(outcome.raised()) +
  "]"
}

///|
/// A text outside the stored range is a domain error naming both limits and the
/// exponent; it is neither saturated nor replaced by a zero or an infinity.
fn assert_outside_stored_range(
  text : String,
  precision~ : Int32 = 34,
) -> Unit raise {
  match Decimal::from_string(text, precision~) {
    Ok(value) => fail("\{text} was accepted as \{value}")
    Err(error) => {
      assert_true(error.is_domain_error())
      assert_true(error.message.contains("gda_implementation_e_tiny"))
      assert_true(error.message.contains("gda_implementation_e_max"))
      assert_true(error.message.contains("-2147483645"))
      assert_true(error.message.contains("2147483646"))
    }
  }
}

///|
test "literal exponents up to the stored range are kept" {
  inspect(
    Decimal::from_string("1e1600000000").unwrap().to_string(),
    content="1E+1600000000",
  )
  inspect(
    Decimal::from_string("1e2147483646").unwrap().to_string(),
    content="1E+2147483646",
  )
  inspect(
    Decimal::from_string("9999999999999999999999999999999999e2147483613").unwrap(),
    content="9.999999999999999999999999999999999E+2147483646",
  )
  // Rounding to the precision can bring the exponent back into range.
  inspect(
    Decimal::from_string("123456789012345678901234567890123456789e2147483600").unwrap(),
    content="1.234567890123456789012345678901235E+2147483638",
  )
  inspect(
    Decimal::from_string("0e-2147483645").unwrap().to_string(),
    content="0E-2147483645",
  )
  inspect(
    Decimal::from_string("1e-2147483645").unwrap().to_string(),
    content="1E-2147483645",
  )
}

///|
test "literals outside the stored range are rejected, not folded" {
  // formerly a signed infinity, a zero of exponent -2^31, or a kept value
  for
    text in [
      "1e2147483647", "12e2147483646", "1e2147483648", "1e3000000000", "-1e3000000000",
      "1e99999999999999999999999999", "0e2147483647", "0e3000000000", "1e-2147483646",
      "1e-2147483648", "-1e-3000000000", "0e-2147483646", "0e-3000000000", "123e-2147483650",
      "15e-2147483649", "5e-2147483649", "10e-2147483649",
    ] {
    assert_outside_stored_range(text)
  }
  // 35 nines at the top round up, and the carry leaves the range
  assert_outside_stored_range("99999999999999999999999999999999999e2147483612")
  // the rounded exponent, not the written one, is below the floor
  assert_outside_stored_range("1249e-2147483650", precision=3)
  assert_outside_stored_range("2500000001e-2147483657", precision=3)
  // the same number is accepted once its rounded exponent is in the range
  inspect(
    Decimal::from_string("1249e-2147483646", precision=3).unwrap(),
    content="1.25E-2147483643",
  )
}

///|
test "context conversion of huge exponents overflows or underflows" {
  assert_true(
    GdaContext::try_new(e_min=-2_000_000_000, e_max=2_000_000_000) is Err(_),
  )
  let floor = GdaContext::new(rounding=GdaRoundingMode::Floor)
  inspect(
    exponent_range_show(to_number("-1e-99999999999999999999999999", floor)),
    content="-1E-1000000032 [Underflow,Subnormal,Inexact,Rounded]",
  )
}

///|
test "products and quotients of extreme exponents do not wrap" {
  let big = Decimal::from_string("1E+1500000000").unwrap()
  let small = Decimal::from_string("1E-1500000000").unwrap()
  let ctx = GdaContext::new()
  let up = GdaContext::new(rounding=GdaRoundingMode::Up)
  let down = GdaContext::new(rounding=GdaRoundingMode::Down)
  inspect(
    exponent_range_show(multiply(big, big, ctx)),
    content="inf [Overflow,Inexact,Rounded]",
  )
  inspect(
    exponent_range_show(multiply(small, small, up)),
    content="1E-1000000032 [Underflow,Subnormal,Inexact,Rounded]",
  )
  inspect(
    exponent_range_show(multiply(small, small, ctx)),
    content="0E-1000000032 [Underflow,Subnormal,Inexact,Rounded,Clamped]",
  )
  inspect(
    exponent_range_show(divide(big, small, ctx)),
    content="inf [Overflow,Inexact,Rounded]",
  )
  inspect(
    exponent_range_show(divide(small, big, up)),
    content="1E-1000000032 [Underflow,Subnormal,Inexact,Rounded]",
  )
  inspect(
    exponent_range_show(fma(big, big, Decimal::one(), ctx)),
    content="inf [Overflow,Inexact,Rounded]",
  )
  inspect(
    exponent_range_show(fma(small, small, Decimal::one(), up)),
    content="1.000000000000000000000000000000001 [Inexact,Rounded]",
  )
  let minus_tiny = Decimal::from_string("-1E-1000000032").unwrap()
  inspect(
    exponent_range_show(fma(small, small, minus_tiny, down)),
    content="-0E-1000000032 [Underflow,Subnormal,Inexact,Rounded,Clamped]",
  )
  // Context-free operators overflow to infinity.
  inspect(big * big, content="inf")
  inspect(-big * big, content="-inf")
  inspect(small * small, content="0E-2147483645")
  inspect(-small * small, content="-0E-2147483645")
  inspect(big / small, content="inf")
  inspect(small / big, content="0E-2147483645")
  inspect(big * small, content="1")
  // The working range of the plain operators ends at Etiny = -2,147,483,645: a
  // result below it is rounded half-even to that exponent (gradual underflow),
  // and here to zero, whose exponent is Etiny.
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  inspect(d("123E-2147483640") * d("1E-10"), content="0E-2147483645")
  inspect(d("10E-2147483640") * d("1E-9"), content="0E-2147483645")
  inspect(d("3E-2147483640") / d("2E+8"), content="0E-2147483645")
  inspect(d("1E-2147483640") / d("3E+7"), content="0E-2147483645")
  inspect(d("-1E-2147483640") / d("3E+9"), content="-0E-2147483645")
  // inside the range the result is rounded to the least exponent
  inspect(d("123E-2147483640") * d("1E-3"), content="1.23E-2147483641")
  inspect(d("5E-2147483640") / d("2E+1"), content="2.5E-2147483641")
  // The working range ends at an adjusted exponent of 2,147,483,646: a sum
  // that rounds up past it overflows.
  let nines = d("9999999999999999999999999999999999E+2147483613")
  inspect(nines + d("5E+2147483612"), content="inf")
  inspect(-nines - d("5E+2147483612"), content="-inf")
  inspect(
    nines + d("4E+2147483612"),
    content="9.999999999999999999999999999999999E+2147483646",
  )
  // Rounding without a context at the top of the stored range follows the GDA
  // Overflow rule of the working range: the carry into the next power of ten
  // is an infinity, or the largest finite value of the width in the modes that
  // round toward zero. It never produces a finite value above the limit.
  let top = d("9999E+2147483643")
  inspect(top.with_precision(2, GdaRoundingMode::Up), content="inf")
  inspect(top.with_precision(2, GdaRoundingMode::Ceiling), content="inf")
  inspect(top.with_precision(2, GdaRoundingMode::HalfEven), content="inf")
  inspect(
    top.with_precision(2, GdaRoundingMode::Down),
    content="9.9E+2147483646",
  )
  inspect(
    top.with_precision(2, GdaRoundingMode::Floor),
    content="9.9E+2147483646",
  )
  inspect((-top).with_precision(2, GdaRoundingMode::Floor), content="-inf")
}
