///|
/// S1: a plain operator is the GDA operation in the working context at the larger
/// precision of its operands, round-half-even, without flags.
test "plain operators return the member of the cohort that GDA names" {
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  // preferred exponents: min for + and -, sum for *, difference for /
  assert_eq((d("1.20") + d("3.40")).to_string(), "4.60")
  assert_eq((d("1.20") - d("3.40")).to_string(), "-2.20")
  assert_eq((d("0.00") + d("0.0")).to_string(), "0.00")
  assert_eq((d("2.50") * d("2")).to_string(), "5.00")
  assert_eq((d("6.0") / d("2")).to_string(), "3.0")
  assert_eq((d("1") / d("4")).to_string(), "0.25")
  assert_eq((d("100") / d("10")).to_string(), "10")
  // an inexact result has the precision's digits at the least exponent
  let third = Decimal::from_int(1, precision=5) /
    Decimal::from_int(3, precision=5)
  assert_eq(third.to_string(), "0.33333")
  assert_eq(third.precision(), 5)
  // a product is rounded to the precision (it used to be kept exact)
  let wide = Decimal::from_string("99999999", precision=4).unwrap()
  assert_eq((wide * wide).to_string(), "1.000E+16")
}

///|
test "plain operators equal the free functions in the working context" {
  let d = fn(s : String) { Decimal::from_string(s, precision=12).unwrap() }
  let ctx = gda_plain_working_context(12)
  for x in ["1.5", "-0", "0.001", "123456789012", "1E+30", "1E-30", "7"] {
    for y in ["2.25", "3", "-0.5", "1E+5", "0E+3", "9.99999999999"] {
      let a = d(x)
      let b = d(y)
      assert_eq((a + b).to_string(), add(a, b, ctx).value().to_string())
      assert_eq((a - b).to_string(), subtract(a, b, ctx).value().to_string())
      assert_eq((a * b).to_string(), multiply(a, b, ctx).value().to_string())
      assert_eq((a / b).to_string(), divide(a, b, ctx).value().to_string())
    }
  }
}

///|
/// The working context is wide enough that adding zero does not change a stored
/// value, down to Etiny = -2,147,483,645.
test "x + 0 is x for stored values" {
  let zero = Decimal::zero()
  for
    text in [
      "1E+2147483640", "123E+999999999", "1E-1000000000", "9.99E-2147483640", "5",
      "-2.50",
    ] {
    let x = Decimal::from_string(text, precision=34).unwrap()
    assert_true(x + zero == x)
    assert_true(x * Decimal::one() == x)
    assert_true(x - zero == x)
  }
}

///|
test "plain sqrt returns the value, NaN outside the domain" {
  assert_eq(Decimal::from_string("4.00").unwrap().sqrt().to_string(), "2.0")
  assert_true(Decimal::from_string("-4").unwrap().sqrt().is_nan())
  assert_eq(
    Decimal::from_int(2, precision=10).sqrt().to_string(),
    "1.414213562",
  )
  assert_eq(Decimal::from_int(0).sqrt().to_string(), "0")
}

///|
test "plain operators on special values and zero divisors" {
  let one = Decimal::one()
  assert_true((one / Decimal::zero()).is_infinite())
  assert_true((Decimal::zero() / Decimal::zero()).is_nan())
  assert_true((Decimal::inf() - Decimal::inf()).is_nan())
  assert_true((Decimal::inf() * Decimal::zero()).is_nan())
  assert_true((Decimal::nan() + one).is_nan())
  assert_true((Decimal::signaling_nan(payload=7N) + one).is_qnan())
}
