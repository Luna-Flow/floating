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
  assert_true(Decimal::from_string("1e3000000000") is None)
  assert_true(Decimal::from_string("1e-3000000000") is None)
  assert_true(Decimal::parse("12e2147483647") is Err(_))
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
  inspect(small * small, content="0")
  inspect(big / small, content="inf")
  inspect(small / big, content="0")
  inspect(big * small, content="1")
}
