///|
test "GdaContext carries the refinement limit of the elementary functions" {
  let ctx = GdaContext::new(precision=20)
  inspect(ctx.refinement_limit() == Some(12), content="true")
  let wide = ctx.with_refinement_limit(Some(24))
  inspect(wide.refinement_limit() == Some(24), content="true")
  inspect(
    ctx.with_refinement_limit(None).refinement_limit() == None,
    content="true",
  )
  // the original is unchanged and the limit reaches the mathematical copy
  inspect(ctx.refinement_limit() == Some(12), content="true")
  inspect(
    wide.mathematical_decimal_context().refinement_limit() == Some(24),
    content="true",
  )
}

///|
test "try_exp, try_ln, try_log10 and try_power agree with the plain functions" {
  let ctx = GdaContext::new(precision=12)
  let one = Decimal::from_int(1)
  let two = Decimal::from_int(2)
  inspect(
    try_exp(one, ctx).unwrap().value(),
    content=exp(one, ctx).value().to_string(),
  )
  inspect(
    try_ln(two, ctx).unwrap().value(),
    content=ln(two, ctx).value().to_string(),
  )
  inspect(
    try_log10(two, ctx).unwrap().value(),
    content=log10(two, ctx).value().to_string(),
  )
  inspect(
    try_power(two, Decimal::from_string("0.5").unwrap(), ctx).unwrap().value(),
    content=power(two, Decimal::from_string("0.5").unwrap(), ctx)
      .value()
      .to_string(),
  )
}

///|
test "to_sci_string and to_eng_string print a number without a context" {
  let big = Decimal::from_string("123E+5").unwrap()
  inspect(big.to_sci_string(), content="1.23E+7")
  inspect(big.to_eng_string(), content="12.3E+6")
  inspect(Decimal::inf(Sign::Negative).to_sci_string(), content="-Infinity")
  inspect(Decimal::quiet_nan(payload=12N).to_eng_string(), content="NaN12")
  inspect(Decimal::signaling_nan().to_sci_string(), content="sNaN")
}

///|
test "interchange formats expose their extended default context" {
  inspect(GdaInterchangeFormat::Decimal64.context().precision(), content="16")
  inspect(GdaInterchangeFormat::Decimal128.context().e_max(), content="6144")
  let (encoded, flags) = GdaInterchange::from_decimal(
    Decimal::from_string("1.234567890").unwrap(),
    Decimal32,
  )
  inspect(encoded.to_hex(), content="#25F4D2E8")
  inspect(flags.contains(GdaSignal::Inexact), content="true")
}
