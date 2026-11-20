///|
fn atan2_zero_show(y : String, x : String, ctx : DecimalContext) -> String {
  let (value, flags) = Decimal::from_string(y)
    .unwrap()
    .atan2_ctx(Decimal::from_string(x).unwrap(), ctx)
  let names = []
  if flags.inexact {
    names.push("inexact")
  }
  if flags.rounded {
    names.push("rounded")
  }
  if flags.underflow {
    names.push("underflow")
  }
  if flags.subnormal {
    names.push("subnormal")
  }
  if flags.clamped {
    names.push("clamped")
  }
  value.to_string() + " [" + names.join(",") + "]"
}

///|
/// IEEE 754-2019 §5.2: for an inexact result "the cohort member of least
/// possible exponent is used". A result that underflows to zero is inexact, so
/// the zero carries the exponent `etiny = e_min - p + 1`, as it does for every
/// other function (`expm1`, `atan`, `asin`, ...). `atan2` returned the exponent
/// 0 for a ratio that is not an exact decimal (#332).
test "atan2 underflowing to zero keeps the least exponent (#332)" {
  let ctx = DecimalContext::decimal64()
  // The ratio 1E-500 / 9 is not a decimal: the certified path decides it.
  inspect(
    atan2_zero_show("1E-500", "9", ctx),
    content="0E-398 [inexact,rounded,underflow,subnormal,clamped]",
  )
  inspect(
    atan2_zero_show("-1E-500", "9", ctx),
    content="-0E-398 [inexact,rounded,underflow,subnormal,clamped]",
  )
  // An exact ratio takes the anchored path and already had the exponent.
  inspect(
    atan2_zero_show("1E-500", "8", ctx),
    content="0E-398 [inexact,rounded,underflow,subnormal,clamped]",
  )
  // The same function family: the other odd functions agree.
  let (atan, _) = Decimal::from_string("1E-500").unwrap().atan_ctx(ctx)
  assert_eq(atan.to_string(), "0E-398")
}

///|
test "atan2 zero exponent follows the context, not 0 (#332)" {
  // Row m20261118.atan2.349 of the MPFR decimal oracle: precision 2,
  // e_min = -17 so etiny = -18.
  let ctx = DecimalContext::new(
    precision=2,
    e_max=18,
    rounding=DecimalRoundingMode::RoundTiesToAway,
  )
  inspect(
    atan2_zero_show("-3.4E-16", "7E+5", ctx),
    content="-0E-18 [inexact,rounded,underflow,subnormal,clamped]",
  )
  // Precision 5, e_min = -3: etiny = -7.
  let wide = DecimalContext::new(
    precision=5,
    e_max=4,
    rounding=DecimalRoundingMode::RoundTowardZero,
  )
  inspect(
    atan2_zero_show("1E-20", "7", wide),
    content="0E-7 [inexact,rounded,underflow,subnormal,clamped]",
  )
}

///|
test "atan2 rounding away from zero is not a zero (#332)" {
  // Directed rounding away from zero gives the smallest subnormal, whose
  // exponent was never affected.
  let ctx = DecimalContext::new(precision=16, e_max=384).with_round(
    DecimalRound::Up,
  )
  inspect(
    atan2_zero_show("1E-500", "9", ctx),
    content="1E-398 [inexact,rounded,underflow,subnormal]",
  )
  let floor = DecimalContext::new(
    precision=16,
    e_max=384,
    rounding=DecimalRoundingMode::RoundTowardNegative,
  )
  inspect(
    atan2_zero_show("-1E-500", "9", floor),
    content="-1E-398 [inexact,rounded,underflow,subnormal]",
  )
  inspect(
    atan2_zero_show("1E-500", "9", floor),
    content="0E-398 [inexact,rounded,underflow,subnormal,clamped]",
  )
}
