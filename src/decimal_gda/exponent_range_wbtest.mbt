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
test "literal exponents beyond 1.5e9 are not saturated" {
  inspect(
    Decimal::from_string("1e1600000000").unwrap().to_string(),
    content="1E+1600000000",
  )
  inspect(
    Decimal::from_string("1e2147483647").unwrap().to_string(),
    content="1E+2147483647",
  )
  // Rounding to the precision can bring the exponent back into range.
  inspect(
    Decimal::from_string("123456789012345678901234567890123456789e2147483600").unwrap(),
    content="1.234567890123456789012345678901235E+2147483638",
  )
  inspect(
    Decimal::from_string("0e-3000000000").unwrap().to_string(),
    content="0E-2147483648",
  )
}

///|
test "context conversion of huge exponents overflows or underflows" {
  assert_true(
    GdaContext::new(e_min=-2_000_000_000, e_max=2_000_000_000) is Err(_),
  )
  let floor = GdaContext::new(rounding=GdaRoundingMode::Floor).unwrap()
  inspect(
    exponent_range_show(parse("-1e-99999999999999999999999999", floor)),
    content="-1E-1000000032 [Underflow,Subnormal,Inexact,Rounded]",
  )
}

///|
test "context-free literals overflow and underflow instead of failing" {
  // A valid numeric string always converts (IEEE 754 §5.12; GDA to-number):
  // beyond the exponent range of a context-free value (adjusted exponent at
  // most 2^31 - 1, stored exponent at least -2^31) it overflows to a signed
  // infinity or rounds half-even to the smallest exponent.
  inspect(Decimal::from_string("1e3000000000").unwrap(), content="inf")
  inspect(Decimal::from_string("-1e3000000000").unwrap(), content="-inf")
  inspect(Decimal::from_string("12e2147483647").unwrap(), content="inf")
  inspect(
    Decimal::from_string("1e99999999999999999999999999").unwrap(),
    content="inf",
  )
  inspect(
    Decimal::from_string("1e-3000000000").unwrap(),
    content="0E-2147483648",
  )
  inspect(
    Decimal::from_string("-1e-3000000000").unwrap(),
    content="-0E-2147483648",
  )
  inspect(
    Decimal::from_string("123e-2147483650").unwrap(),
    content="1E-2147483648",
  )
  inspect(
    Decimal::from_string("15e-2147483649").unwrap(),
    content="2E-2147483648",
  )
  inspect(
    Decimal::from_string("25e-2147483649").unwrap(),
    content="2E-2147483648",
  )
  inspect(
    Decimal::from_string("5e-2147483649").unwrap(),
    content="0E-2147483648",
  )
  inspect(
    Decimal::from_string("10e-2147483649").unwrap(),
    content="1E-2147483648",
  )
  // A longer coefficient is rounded once, not first to the precision.
  inspect(
    Decimal::from_string("1249e-2147483650", precision=3).unwrap(),
    content="1.2E-2147483647",
  )
  inspect(
    Decimal::from_string("12501e-2147483651", precision=3).unwrap(),
    content="1.3E-2147483647",
  )
  inspect(
    Decimal::from_string("2500000001e-2147483657", precision=3).unwrap(),
    content="3E-2147483648",
  )
}

///|
test "products and quotients of extreme exponents do not wrap" {
  let big = Decimal::from_string("1E+1500000000").unwrap()
  let small = Decimal::from_string("1E-1500000000").unwrap()
  let ctx = GdaContext::new().unwrap()
  let up = GdaContext::new(rounding=GdaRoundingMode::Up).unwrap()
  let down = GdaContext::new(rounding=GdaRoundingMode::Down).unwrap()
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
  inspect(small * small, content="0E-2147483648")
  inspect(-small * small, content="-0E-2147483648")
  inspect(big / small, content="inf")
  inspect(small / big, content="0")
  inspect(big * small, content="1")
  // Below the exponent range the result is rounded half-even to the smallest
  // exponent (gradual underflow), not replaced by zero.
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  inspect(d("123E-2147483640") * d("1E-10"), content="1E-2147483648")
  inspect(d("10E-2147483640") * d("1E-9"), content="1E-2147483648")
  inspect(d("3E-2147483640") / d("2E+8"), content="2E-2147483648")
  inspect(d("1E-2147483640") / d("3E+7"), content="3E-2147483648")
  inspect(d("-1E-2147483640") / d("3E+9"), content="-0")
  // A sum that rounds up past the largest exponent overflows.
  let nines = d("9999999999999999999999999999999999E+2147483614")
  inspect(nines + d("5E+2147483613"), content="inf")
  inspect(-nines - d("5E+2147483613"), content="-inf")
  inspect(
    nines + d("4E+2147483613"),
    content="9.999999999999999999999999999999999E+2147483647",
  )
  // Rounding at the top of the range overflows according to the mode.
  let top = d("9999E+2147483644")
  inspect(top.with_precision(2, RoundingMode::AwayFromZero), content="inf")
  inspect(
    top.with_precision(2, RoundingMode::TowardZero),
    content="9.9E+2147483647",
  )
}
