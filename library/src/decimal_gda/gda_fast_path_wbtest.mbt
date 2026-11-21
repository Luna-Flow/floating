///|
/// The flags of an outcome as text: inexact, rounded, overflow, underflow, subnormal, clamped, in that order.
fn fast_path_flags_text(flags : GdaFlags) -> String {
  (if flags.inexact() { "x" } else { "-" }) +
  (if flags.rounded() { "r" } else { "-" }) +
  (if flags.overflow() { "o" } else { "-" }) +
  (if flags.underflow() { "u" } else { "-" }) +
  (if flags.subnormal() { "s" } else { "-" }) +
  (if flags.clamped() { "c" } else { "-" })
}

///|
fn assert_gda_outcome(
  outcome : GdaOutcome[Decimal],
  text : String,
  flags : String,
) -> Unit raise {
  assert_eq(outcome.value().to_string(), text)
  assert_eq(fast_path_flags_text(outcome.raised()), flags)
  // the context that comes back carries the flags that were raised
  assert_eq(fast_path_flags_text(outcome.next_context().flags()), flags)
}

///|
// oracle: A
// source: expected values and flags computed with CPython decimal (libmpdec 4.0.0), context prec=40,
//   Emin=-999999, Emax=999999, traps off: 314159265358979328 + 2, - 2, * 2, fma(.., 2, 3) and the
//   conversion of the same text are exact and raise no flag
// shares: nothing
test "GDA exact small wrapper paths match generic finalization" {
  let context = GdaContext::new(precision=40, e_min=-999999, e_max=999999)
  let left = Decimal::from_string("314159265358979328").unwrap()
  let right = Decimal::from_string("2").unwrap()
  let addend = Decimal::from_string("3").unwrap()
  assert_gda_outcome(add(left, right, context), "314159265358979330", "------")
  assert_gda_outcome(
    subtract(left, right, context),
    "314159265358979326",
    "------",
  )
  assert_gda_outcome(
    multiply(left, right, context),
    "628318530717958656",
    "------",
  )
  assert_gda_outcome(
    fma(left, right, addend, context),
    "628318530717958659",
    "------",
  )
  assert_gda_outcome(
    to_number("314159265358979328", context),
    "314159265358979328",
    "------",
  )
}

///|
// oracle: A
// source: expected values and flags computed with CPython decimal (libmpdec 4.0.0): 999999999999999999 + 2 at
//   prec=9, Emin=-2, Emax=2 and the conversion of 314159265358979328 at prec=18, Emin=-2, Emax=2,
//   clamp=1 both overflow to Infinity with Overflow, Inexact and Rounded
// shares: nothing
test "GDA small wrapper paths fall back at semantic boundaries" {
  let tiny_context = GdaContext::new(precision=9, e_min=-2, e_max=2)
  let left = Decimal::from_string("999999999999999999").unwrap()
  let right = Decimal::from_string("2").unwrap()
  assert_gda_outcome(add(left, right, tiny_context), "inf", "xro---")
  let clamped = GdaContext::new(precision=18, e_min=-2, e_max=2, clamp=true)
  assert_gda_outcome(to_number("314159265358979328", clamped), "inf", "xro---")
}
