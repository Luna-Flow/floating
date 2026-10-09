///|
fn exponent_range_show(result : (Decimal, DecimalFlags)) -> String {
  let (value, flags) = result
  let names = []
  if flags.overflow {
    names.push("overflow")
  }
  if flags.underflow {
    names.push("underflow")
  }
  if flags.subnormal {
    names.push("subnormal")
  }
  if flags.inexact {
    names.push("inexact")
  }
  if flags.rounded {
    names.push("rounded")
  }
  if flags.clamped {
    names.push("clamped")
  }
  if flags.conversion_syntax {
    names.push("conversion_syntax")
  }
  value.to_string() + " [" + names.join(",") + "]"
}

///|
test "literal exponents beyond 1.5e9 are not saturated" {
  inspect(
    Decimal::from_string("1e1600000000").unwrap().to_string(),
    content="1E+1600000000",
  )
  let wide = DecimalContext::new(e_min=-2_000_000_000, e_max=2_000_000_000)
  inspect(
    exponent_range_show(Decimal::from_string_ctx("1e1600000000", wide)),
    content="1E+1600000000 []",
  )
  inspect(
    exponent_range_show(Decimal::from_string_ctx("1e2100000000", wide)),
    content="inf [overflow,inexact,rounded]",
  )
  inspect(
    exponent_range_show(Decimal::from_string_ctx("-1e-3000000000", wide)),
    content="-0E-2000000033 [underflow,subnormal,inexact,rounded,clamped]",
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
  let ctx = DecimalContext::new()
  let up = DecimalContext::new(rounding=RoundingMode::AwayFromZero)
  inspect(
    exponent_range_show(big.mul_ctx(big, ctx)),
    content="inf [overflow,inexact,rounded]",
  )
  inspect(
    exponent_range_show(small.mul_ctx(small, up)),
    content="1E-1000000032 [underflow,subnormal,inexact,rounded]",
  )
  inspect(
    exponent_range_show(big.div_ctx(small, ctx)),
    content="inf [overflow,inexact,rounded]",
  )
  inspect(
    exponent_range_show(small.div_ctx(big, ctx)),
    content="0E-1000000032 [underflow,subnormal,inexact,rounded,clamped]",
  )
  inspect(
    exponent_range_show(big.fma_ctx(big, Decimal::one(), ctx)),
    content="inf [overflow,inexact,rounded]",
  )
  inspect(
    exponent_range_show(small.fma_ctx(small, Decimal::one(), up)),
    content="1.000000000000000000000000000000001 [inexact,rounded]",
  )
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
