///|
// oracle: S
// source: accessors of the context: the default limit 12 is the documented constant of the context (#15),
//   the other values are those passed in; no computed value
// shares: nothing
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
// oracle: A
// source: exp(1), ln(2), log10(2) and 2^0.5 at 12 digits computed with CPython decimal (libmpdec 4.0.0), context
//   prec=12, Emin=-999999, Emax=999999, rounding ROUND_HALF_EVEN, no traps
// shares: nothing
test "try_exp, try_ln, try_log10 and try_power agree with the plain functions" {
  // a bounded context: the elementary functions refuse an exponent range above 999,999 (the old test used the
  // default range, so both sides were NaN)
  let ctx = GdaContext::new(precision=12, e_min=-999999, e_max=999999)
  let one = Decimal::from_int(1)
  let two = Decimal::from_int(2)
  let half = Decimal::from_string("0.5").unwrap()
  inspect(try_exp(one, ctx).unwrap().value(), content="2.71828182846")
  inspect(try_ln(two, ctx).unwrap().value(), content="0.693147180560")
  inspect(try_log10(two, ctx).unwrap().value(), content="0.301029995664")
  inspect(try_power(two, half, ctx).unwrap().value(), content="1.41421356237")
  // the plain functions give the same values
  inspect(exp(one, ctx).value(), content="2.71828182846")
  inspect(ln(two, ctx).value(), content="0.693147180560")
  inspect(log10(two, ctx).value(), content="0.301029995664")
  inspect(power(two, half, ctx).value(), content="1.41421356237")
}

///|
// oracle: A
// source: strings written out from the to-scientific-string and to-engineering-string rules (GDA 1.70, Conversions)
//   123E+5 = 1.23E+7 = 12.3E+6, Infinity and NaN spellings from the specification
// shares: nothing
test "to_sci_string and to_eng_string print a number without a context" {
  let big = Decimal::from_string("123E+5").unwrap()
  inspect(big.to_sci_string(), content="1.23E+7")
  inspect(big.to_eng_string(), content="12.3E+6")
  inspect(Decimal::inf(negative=true).to_sci_string(), content="-Infinity")
  inspect(Decimal::quiet_nan(payload=12N).to_eng_string(), content="NaN12")
  inspect(Decimal::signaling_nan().to_sci_string(), content="sNaN")
}

///|
// oracle: A
// source: decimal64 has precision 16 and decimal128 Emax 6144 (GDA 1.70, decimal interchange formats); the
//   decimal32 hex of 1.234567890 (1.234568, 7 digits, Inexact) decoded by hand: #25F4D2E8, sign 0,
//   combination 01001 (exponent bits 01 and leading digit 1), exponent continuation 011111 (biased 95 for
//   10^-6), coefficient declets 234 and 568; decNumber 3.68 decimal32FromString gives the same bytes
// shares: nothing
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
