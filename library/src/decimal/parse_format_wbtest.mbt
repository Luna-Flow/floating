///|
// oracle: A
// source: IEEE 754-2019 5.12.1 and 3.5.2: a 34-digit coefficient is kept exactly (with leading zeros dropped) at precision 34, no inexact flag; -sNaN0001234567890123456789012345678901 is a negative signaling NaN of payload 1234567890123456789012345678901 (31 digits, at most p - 1 = 33)
// shares: Decimal::from_string and from_string_ctx (the code under test), to_string, the coefficient and payload accessors; also read through == (Decimal equality), exponent10 (they read the operands and results, not the code under test)
test "decimal parsing preserves coefficient-native finite and NaN payloads" {
  let ctx = DecimalContext::new(precision=34)
  let digits = "1234567890123456789012345678901234"
  let (finite, finite_flags) = Decimal::from_string_ctx(
    "000" + digits + "E-12",
    ctx,
  )
  assert_true(finite.class == FpClass::Finite)
  assert_eq(finite.coefficient.to_string(), digits)
  assert_eq(finite.exponent10, -12)
  assert_false(finite_flags.inexact)

  let (nan, nan_flags) = Decimal::from_string_ctx(
    "-sNaN0001234567890123456789012345678901", ctx,
  )
  assert_true(nan.class == FpClass::NaN)
  assert_true(nan.negative)
  assert_true(nan.signaling_nan)
  assert_eq(nan.coefficient.to_string(), "1234567890123456789012345678901")
  assert_false(nan_flags.has_error())
}

///|
// oracle: A
// source: CPython decimal (Context with Emax = e_max, Emin = 1 - e_max, clamp = 1; run 2026-11-26) and IEEE 754-2019 7.4, 7.5: 99999999E+100 at 7 digits overflows to infinity with overflow and inexact, 1E-1000 underflows to zero with inexact and underflow
// shares: Decimal::from_string and from_string_ctx (the code under test), to_string, the coefficient and payload accessors; also read through == (Decimal equality), is_zero (they read the operands and results, not the code under test)
test "decimal parsing coefficient-native boundary paths preserve flags" {
  let ctx = DecimalContext::new(precision=7, e_max=96)
  let (overflow, overflow_flags) = Decimal::from_string_ctx(
    "99999999E+100", ctx,
  )
  assert_true(overflow.class == FpClass::Infinity)
  assert_true(overflow_flags.overflow)
  assert_true(overflow_flags.inexact)

  let (tiny, tiny_flags) = Decimal::from_string_ctx("1E-1000", ctx)
  assert_true(tiny.class == FpClass::Finite)
  assert_true(tiny.coefficient.is_zero())
  assert_true(tiny_flags.inexact)
  assert_true(tiny_flags.underflow)
}

///|
// oracle: A
// source: CPython decimal (Context with Emax = e_max, Emin = 1 - e_max, clamp = 1; run 2026-11-26) (precision 3, nearest even): 1.0001 and 1.000 give 1.00 and 10001 gives 1.00E+4; the cohort has p digits (IEEE 754-2019 5.2, 5.12.1)
// shares: Decimal::from_string and from_string_ctx (the code under test), to_string, the coefficient and payload accessors
test "decimal parse keeps the IEEE preferred cohort at its precision" {
  let p = fn(text : String) {
    Decimal::from_string(text, precision=3).unwrap().to_string()
  }
  inspect(p("1.0001"), content="1.00")
  inspect(p("1.000"), content="1.00")
  inspect(p("10001"), content="1.00E+4")
}

///|
/// IEEE 754 §5.12 converts a literal by one correct rounding to the format; a
/// carry into 10^p advances the exponent by one and the result still has p
/// digits, so its cohort is not reduced.
// oracle: A
// source: CPython decimal (Context with Emax = e_max, Emin = 1 - e_max, clamp = 1; run 2026-11-26) (precision 3 unless stated): 99999 and -99999 give +-1.00E+5, 9.9999 gives 10.0, 999.5 and 9995 (ties to even) give 1.00E+3 and 1.00E+4, 0.0009999 gives 0.00100, 998.5 gives 998 and 9.5 at one digit gives 1E+1; all agree
// shares: Decimal::from_string and from_string_ctx (the code under test), to_string, the coefficient and payload accessors
test "decimal parse keeps p digits when rounding carries into 10^p" {
  let p = fn(text : String) {
    Decimal::from_string(text, precision=3).unwrap().to_string()
  }
  inspect(p("99999"), content="1.00E+5")
  inspect(p("-99999"), content="-1.00E+5")
  inspect(p("9.9999"), content="10.0")
  inspect(p("999.5"), content="1.00E+3")
  inspect(p("9995"), content="1.00E+4")
  inspect(p("0.0009999"), content="0.00100")
  inspect(p("998.5"), content="998")
  inspect(
    Decimal::from_string("9.5", precision=1).unwrap().to_string(),
    content="1E+1",
  )
}
