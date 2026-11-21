///|
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
test "GDA finite extreme-range exp certifies without full decimal expansion" {
  let context = GdaContext::new(precision=7, e_min=-999_999, e_max=999_999)
  let outcome = exp(Decimal::from_int(-1_000_000), context)
  assert_eq(outcome.value().to_string(), "3.296831E-434295")
  assert_true(outcome.raised().contains(GdaSignal::Rounded))
  assert_true(outcome.raised().contains(GdaSignal::Inexact))
  assert_false(outcome.raised().contains(GdaSignal::Underflow))
}

///|
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
/// `ln(0.99999991000000405)` at 17 digits, half-up: the subset corpus
/// (`testdata/decimal_gda/official0/ln0.decTest`, `extended: 0`, row `ln116`,
/// marked there "next is a > 0.5ulp case") expects `-8.9999999999999879E-8`, the
/// 18-digit value ...785 rounded again; the extended corpus (`official/ln.decTest`,
/// `extended: 1`, row `lnx116`) expects the correctly rounded `-8.9999999999999878E-8`
/// (Python `decimal` agrees: -8.99999999999998784999918E-8). Both are upstream rows
/// (level A); the subset result is a documented legacy behavior, not a defect.
/// Half-even in the subset: no corpus row, so the oracle is decNumber 3.68
/// itself (https://speleotrove.com/decimal/decNumber-icu-368.zip, sha256
/// 14ec2cf3...fe25), built with DECSUBSET=1 and run on this operand at precision 17:
/// -8.9999999999999879E-8 in half_up and in half_even, with extended 0 and 1. By
/// reading: `decNumberLn` (decNumber.c:1256) only rounds an over-long operand and
/// rejects a zero in the subset, then calls `decLnOp`, whose header says "rounding
/// mode has no effect" and whose result is cut at line 5795 with the half-even
/// context of the iteration (a double rounding, not tied to the subset). decNumber
/// itself fails lnx116 (the extended row, correctly rounded `...878`).
test "GDA classic subset retains legacy math flags and the legacy double-rounded ln" {
  let subset = GdaContext::new(
    precision=17,
    rounding=GdaRoundingMode::HalfUp,
    e_min=-999_999,
    e_max=999_999,
    extended=false,
  )
  let operand = Decimal::from_string("0.99999991000000405").unwrap()
  // official0/ln0.decTest ln116
  assert_eq(ln(operand, subset).value().to_string(), "-8.9999999999999879E-8")
  // official/ln.decTest lnx116 (extended arithmetic, same operand and context)
  let extended = GdaContext::new(
    precision=17,
    rounding=GdaRoundingMode::HalfUp,
    e_min=-999_999,
    e_max=999_999,
  )
  assert_eq(ln(operand, extended).value().to_string(), "-8.9999999999999878E-8")
  // the subset in half-even: decNumber 3.68 (run, DECSUBSET=1) gives the same value
  let subset_even = GdaContext::new(
    precision=17,
    rounding=GdaRoundingMode::HalfEven,
    e_min=-999_999,
    e_max=999_999,
    extended=false,
  )
  assert_eq(
    ln(operand, subset_even).value().to_string(),
    "-8.9999999999999879E-8",
  )
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
