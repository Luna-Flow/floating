///|
// oracle: A
// source: 4**0.5 at p9: literal 2.00000000, Rounded and Inexact; CPython agrees (2.00000000 Inexact Rounded)
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "GDA noninteger power preserves GDA cohort and flags" {
  let context = GdaContext::new(precision=9, e_min=-999_999, e_max=999_999)
  let base = Decimal::from_int(4, precision=32)
  let exponent = Decimal::from_string("0.5", precision=32).unwrap()
  let outcome = power(base, exponent, context)
  assert_eq(outcome.value().to_string(), "2.00000000")
  assert_true(outcome.raised().contains(GdaSignal::Rounded))
  assert_true(outcome.raised().contains(GdaSignal::Inexact))
}

///|
/// GDA deliberately keeps its specification rules, including 0^0 = NaN.
/// The official powx2015 vector is distinct from decimal's IEEE power rule.
// oracle: A
// source: 0**0 = NaN with InvalidOperation (GDA power rule, powx2015 row named in the title) and 1**12.3 at p3
//   -> 1.00 Rounded Inexact; CPython agrees on both
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "GDA power keeps zero-zero rule and official powx2015 vector" {
  let context = GdaContext::new(precision=3, e_min=-999_999, e_max=999_999)
  let zero_zero = power(Decimal::zero(), Decimal::zero(), context)
  assert_true(zero_zero.value().is_nan())
  assert_true(zero_zero.raised().contains(GdaSignal::InvalidOperation))

  let one_noninteger = power(
    Decimal::one(),
    Decimal::from_string("12.3").unwrap(),
    context,
  )
  assert_eq(one_noninteger.value().to_string(), "1.00")
  assert_true(one_noninteger.raised().contains(GdaSignal::Rounded))
  assert_true(one_noninteger.raised().contains(GdaSignal::Inexact))
}

///|
// oracle: A
// source: GDA 1.70 exp/ln/log10: inexact results are rounded with round-half-even; CPython 3.13 agrees on all
//   values (it also ignores Up for exp); decNumber 3.68 rounds the exp Up row to 1.02 (it honors the context
//   mode), so that row follows the specification text and not decNumber
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "GDA transcendental operations finalize with half even" {
  let half_even = GdaContext::new(precision=3, e_min=-999_999, e_max=999_999)
  let upward = GdaContext::new(
    precision=3,
    rounding=GdaRoundingMode::Up,
    e_min=-999_999,
    e_max=999_999,
  )
  let value = Decimal::from_string("0.01").unwrap()
  let even = exp(value, half_even)
  let directed = exp(value, upward)
  assert_eq(even.value().to_string(), "1.01")
  assert_eq(directed.value().to_string(), "1.01")
  assert_true(even.raised().contains(GdaSignal::Rounded))
  assert_true(even.raised().contains(GdaSignal::Inexact))
  assert_eq(ln(Decimal::from_int(2), half_even).value().to_string(), "0.693")
  assert_eq(log10(Decimal::from_int(2), half_even).value().to_string(), "0.301")
}

///|
// oracle: A
// source: GDA rule 'exp rounded half-even' (spec text), flags hand-derived; CPython exp(-1E8) p7 range
//   -383..384 Up gives 0E-389 with Underflow Subnormal Inexact Rounded Clamped (agrees)
// shares: nothing
test "GDA extreme exp uses HalfEven without endpoint expansion" {
  let context = GdaContext::new(
    precision=7,
    rounding=GdaRoundingMode::Up,
    e_min=-383,
    e_max=384,
    extended=false,
  )
  let outcome = exp(Decimal::from_int(-100_000_000), context)
  assert_true(outcome.value().is_zero())
  assert_true(outcome.raised().contains(GdaSignal::Rounded))
  assert_true(outcome.raised().contains(GdaSignal::Inexact))
  assert_true(outcome.raised().contains(GdaSignal::Underflow))
  assert_true(outcome.raised().contains(GdaSignal::Subnormal))
  assert_true(outcome.raised().contains(GdaSignal::Clamped))
}

///|
// oracle: A
// source: literal 3.296831E-434295; CPython exp(-1E6) at p7 gives 3.296831E-434295 Inexact Rounded, no
//   Underflow (agrees)
// shares: Decimal::to_string (printing the result)
test "GDA finite extreme-range exp certifies without full decimal expansion" {
  let context = GdaContext::new(precision=7, e_min=-999_999, e_max=999_999)
  let outcome = exp(Decimal::from_int(-1_000_000), context)
  assert_eq(outcome.value().to_string(), "3.296831E-434295")
  assert_true(outcome.raised().contains(GdaSignal::Rounded))
  assert_true(outcome.raised().contains(GdaSignal::Inexact))
  assert_false(outcome.raised().contains(GdaSignal::Underflow))
}

///|
// oracle: A
// source: 17**81.27115 down p7 range +-99 -> 9.999973E+99; 81.27116 -> 9.999999E+99 with Overflow;
//   1E-101**1.000001 floor p7 range -95..96 -> 0E-101 with Underflow Subnormal; CPython agrees on all
//   three values and the flags
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "GDA power certifies directed overflow and underflow cells" {
  let down = GdaContext::new(
    precision=7,
    rounding=GdaRoundingMode::Down,
    e_min=-99,
    e_max=99,
  )
  let finite = power(
    Decimal::from_int(17),
    Decimal::from_string("81.27115").unwrap(),
    down,
  )
  assert_eq(finite.value().to_string(), "9.999973E+99")
  let overflow = power(
    Decimal::from_int(17),
    Decimal::from_string("81.27116").unwrap(),
    down,
  )
  assert_eq(overflow.value().to_string(), "9.999999E+99")
  assert_true(overflow.raised().contains(GdaSignal::Overflow))
  let floor = GdaContext::new(
    precision=7,
    rounding=GdaRoundingMode::Floor,
    e_min=-95,
    e_max=96,
  )
  let underflow = power(
    Decimal::from_string("1e-101").unwrap(),
    Decimal::from_string("1.000001").unwrap(),
    floor,
  )
  assert_eq(underflow.value().to_string(), "0E-101")
  assert_true(underflow.raised().contains(GdaSignal::Underflow))
  assert_true(underflow.raised().contains(GdaSignal::Subnormal))
}

///|
// oracle: A
// source: 0.000**0.5 -> 0 with no flags and 1E-20**0.5 at p12 range -9..9 -> 1.0000000000E-10 with Underflow
//   Subnormal Rounded Inexact; CPython agrees on values and flags
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "GDA square-root power preserves zero and tiny-result conditions" {
  let zero = power(
    Decimal::from_string("0.000").unwrap(),
    Decimal::from_string("0.5").unwrap(),
    GdaContext::new(precision=9),
  )
  assert_eq(zero.value().to_string(), "0")
  assert_true(zero.raised() == GdaFlags::new())
  let tiny = power(
    Decimal::from_string("1E-20").unwrap(),
    Decimal::from_string("0.5").unwrap(),
    GdaContext::new(precision=12, e_min=-9, e_max=9),
  )
  assert_eq(tiny.value().to_string(), "1.0000000000E-10")
  assert_true(tiny.raised().contains(GdaSignal::Rounded))
  assert_true(tiny.raised().contains(GdaSignal::Inexact))
  assert_true(tiny.raised().contains(GdaSignal::Underflow))
  assert_true(tiny.raised().contains(GdaSignal::Subnormal))
}

///|
/// `ln(0.99999991000000405)` at 17 digits: the subset arithmetic is correctly rounded
/// like the extended one (GDA 1.70 pages 29-30, `ln`: "rounded using the
/// round-half-even algorithm ... should be correctly rounded, but may be up to 1 ulp
/// in error": the library does not use the tolerance). Exact value (CPython `decimal`,
/// 50 digits): -8.99999999999998784999918E-8, so the correctly rounded 17-digit result
/// is `-8.9999999999999878E-8` in every nearest mode. Upstream rows: the extended
/// corpus `official/ln.decTest` lnx116 expects the correctly rounded value; the
/// subset corpus `official0/ln0.decTest` ln116 expects `-8.9999999999999879E-8`,
/// the value of decNumber's one-ulp tolerance (decNumber 3.68, built with
/// DECSUBSET=1 and run, returns `...879` with extended 0 and 1 in half_up and
/// half_even: `decNumberLn` decNumber.c:1256 calls `decLnOp`, whose result is cut at
/// line 5795; decNumber fails lnx116 and lnx732 itself): ln116 is a recorded
/// deviation of the corpus (`testdata/decimal_gda/deviations.tsv`, issue 649).
// oracle: A
// source: literal -8.9999999999999878E-8: exact value from CPython at 50 digits (-8.99999999999998784999918E-8)
//   rounded to 17 digits; the corpus row ln116 expects ...879 (decNumber tolerance), recorded deviation
//   issue 649; CPython at p17 gives ...878 in half_up and half_even
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "ln of the subset is correctly rounded, as the extended arithmetic (ln116, lnx116)" {
  let operand = Decimal::from_string("0.99999991000000405").unwrap()
  for extended in [false, true] {
    for mode in [GdaRoundingMode::HalfUp, GdaRoundingMode::HalfEven] {
      let context = GdaContext::new(
        precision=17,
        rounding=mode,
        e_min=-999_999,
        e_max=999_999,
        extended~,
      )
      assert_eq(
        ln(operand, context).value().to_string(),
        "-8.9999999999999878E-8",
      )
    }
  }
}

///|
// oracle: A
// source: decNumber 3.68 built with DECSUBSET=1 (tools/decnumber_probe.c, extended=0): exp(-1000) at precision 7,
//   Emin -383, Emax 384 raises Underflow and Clamped (flags xr---usc); power(7, 1000000001) at precision 9 with the
//   exponent range of +-999999999 is NaN with Inexact, Rounded, Invalid context and Lost digits; the
//   InvalidOperation flag follows the Invalid context condition of GDA 1.70 ("occurs and signals invalid-operation")
// shares: nothing
test "GDA classic subset retains legacy math flags" {
  let exp_subset = GdaContext::new(
    precision=7,
    rounding=GdaRoundingMode::HalfUp,
    e_min=-383,
    e_max=384,
    extended=false,
  )
  let tiny_exp = exp(Decimal::from_int(-1000), exp_subset)
  assert_true(tiny_exp.raised().contains(GdaSignal::Underflow))
  assert_true(tiny_exp.raised().contains(GdaSignal::Clamped))
  let power_subset = GdaContext::new(
    precision=9,
    rounding=GdaRoundingMode::HalfUp,
    e_min=-999_999_999,
    e_max=999_999_999,
    extended=false,
  )
  let invalid = power(
    Decimal::from_int(7),
    Decimal::from_int(1_000_000_001),
    power_subset,
  )
  assert_true(invalid.raised().invalid_context())
  assert_true(invalid.raised().contains(GdaSignal::InvalidOperation))
  assert_true(invalid.raised().contains(GdaSignal::Rounded))
  assert_true(invalid.raised().contains(GdaSignal::Inexact))
  assert_true(invalid.raised().contains(GdaSignal::LostDigits))
}
