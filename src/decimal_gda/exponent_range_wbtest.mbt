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
  // Not representable: the exponent or adjusted exponent leaves `Int`.
  assert_true(Decimal::from_string("1e3000000000") is None)
  assert_true(Decimal::from_string("1e-3000000000") is None)
  assert_true(Decimal::from_string("12e2147483647") is None)
  assert_true(Decimal::from_string("1e99999999999999999999999999") is None)
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
  let wide = GdaContext::new(e_min=-2_000_000_000, e_max=2_000_000_000)
  inspect(
    exponent_range_show(parse("1e1600000000", wide)),
    content="1E+1600000000 []",
  )
  inspect(
    exponent_range_show(parse("1e2100000000", wide)),
    content="inf [Overflow,Inexact,Rounded]",
  )
  inspect(
    exponent_range_show(parse("1e-3000000000", wide)),
    content="0E-2000000033 [Underflow,Subnormal,Inexact,Rounded,Clamped]",
  )
  inspect(
    exponent_range_show(parse("0e+3000000000", wide)),
    content="0E+2000000000 [Clamped]",
  )
  let floor = GdaContext::new(rounding=GdaRoundingMode::Floor)
  inspect(
    exponent_range_show(parse("-1e-99999999999999999999999999", floor)),
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
  // Context-free operators overflow to infinity or underflow to zero.
  inspect(big * big, content="inf")
  inspect(small * small, content="0")
  inspect(big / small, content="inf")
  inspect(small / big, content="0")
  inspect(big * small, content="1")
}
