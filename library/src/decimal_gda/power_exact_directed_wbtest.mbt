///|
/// 5^n from the BigInt power of the MoonBit core library (not the cache of this library), with the digit count and
/// the first and last 20 digits checked against CPython integers for the exponents the tests use.
fn five_power(n : Int32) -> BigInt raise {
  let value = BigInt::from_int(5).pow(BigInt::from_int(n))
  let text = value.to_string()
  let (length, head, tail) = match n {
    1024 => (716, "55626846462680034577", "73115634918212890625")
    1200 => (839, "58077137562175031832", "38771152496337890625")
    8193 => (5727, "45840096688871179140", "95656299591064453125")
    _ => abort("five_power: no reference digits for \{n}")
  }
  assert_eq(text.length(), length)
  assert_eq(text[:20].to_owned(), head)
  assert_eq(text[text.length() - 20:].to_owned(), tail)
  value
}

///|
// oracle: A
// source: the five exact results 8.0000, 27.000, 2.0000, 0.12500, 0.12500 are written out by hand (4^1.5 = 8, 9^1.5 = 27,
//   16^0.25 = 2, 0.25^1.5 = 0.125, 4^-1.5 = 0.125) padded to 5 digits; GDA 1.70 power: a non-integral power
//   is Inexact and Rounded and has precision digits. CPython decimal (libmpdec 4.0.0) gives the same value in
//   half-even, half-up and half-down and differs by 1 ulp in the directed modes on some rows (known libmpdec
//   tolerance, see conformance/decimal_gda.md); the expected exact value is the correctly rounded one
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "power decides exact non-integral results in every rounding mode" {
  let modes = [
    GdaRoundingMode::HalfEven,
    GdaRoundingMode::HalfUp,
    GdaRoundingMode::HalfDown,
    GdaRoundingMode::Down,
    GdaRoundingMode::Up,
    GdaRoundingMode::Ceiling,
    GdaRoundingMode::Floor,
    GdaRoundingMode::ZeroFiveUp,
  ]
  let cases = [
    ("4", "1.5", "8.0000"),
    ("9", "1.5", "27.000"),
    ("16", "0.25", "2.0000"),
    ("0.25", "1.5", "0.12500"),
    ("4", "-1.5", "0.12500"),
  ]
  for mode in modes {
    let ctx = GdaContext::new(
      precision=5,
      rounding=mode,
      e_min=-999_999,
      e_max=999_999,
    )
    for entry in cases {
      let (left, right, expected) = entry
      let outcome = power(
        Decimal::from_string(left).unwrap(),
        Decimal::from_string(right).unwrap(),
        ctx,
      )
      assert_eq(outcome.value().to_string(), expected)
      assert_true(outcome.raised().contains(GdaSignal::Inexact))
      assert_true(outcome.raised().contains(GdaSignal::Rounded))
      assert_false(outcome.raised().contains(GdaSignal::InvalidOperation))
    }
  }
}

///|
// oracle: A
// source: hand: 2.25^1.5 = 3.375 exact, rounded by mode (the tie at 3 digits goes to 3.38 half-even and half-up);
//   CPython 3.13 and decNumber 3.68 agree on 6 of the 8 rows and give 3.37 (not 3.38) at precision 3 half-even
//   and half-up, a one-unit difference the specification allows for a non-integral power
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "power rounds an exact result longer than the precision" {
  // 2.25^1.5 = 3.375 is exact. At three digits it is the midpoint of
  // 3.37 and 3.38; at two digits it lies inside the cell (3.3, 3.4).
  let check = (precision : Int32, mode : GdaRoundingMode, expected : String) => {
    let ctx = GdaContext::new(
      precision~,
      rounding=mode,
      e_min=-999_999,
      e_max=999_999,
    )
    let outcome = power(
      Decimal::from_string("2.25").unwrap(),
      Decimal::from_string("1.5").unwrap(),
      ctx,
    )
    assert_eq(outcome.value().to_string(), expected)
    assert_true(outcome.raised().contains(GdaSignal::Inexact))
    assert_true(outcome.raised().contains(GdaSignal::Rounded))
  }
  check(3, GdaRoundingMode::HalfEven, "3.38")
  check(3, GdaRoundingMode::HalfUp, "3.38")
  check(3, GdaRoundingMode::HalfDown, "3.37")
  check(3, GdaRoundingMode::Down, "3.37")
  check(3, GdaRoundingMode::Up, "3.38")
  check(2, GdaRoundingMode::HalfEven, "3.4")
  check(2, GdaRoundingMode::Down, "3.3")
  check(2, GdaRoundingMode::Up, "3.4")
}

///|
/// `(2^1200 * 10^-1200)^1.5 = 2^1800 * 10^-1800` is exact at precision 1000
/// although `base^3` needs 1084 digits; so is `(5^1200)^-1.5`. Both are
/// decided in every mode instead of failing certification after minutes.
// oracle: B
// source: 2^1800 * 10^-1800 from the BigInt shift of the MoonBit core library and 5^1200 from five_power (the BigInt
//   power of core, checked by digit count and first and last 20 digits against CPython integers); the test
//   does not assert Inexact and Rounded for these exact-in-digits results
// shares: BigInt shift and pow of the MoonBit core library; Decimal::from_string and to_string (reading the inputs, printing the result)
// primitives: core BigInt shift, pow and to_string, checked on these values by digit count and first and last 20
//   digits (CPython integers)
test "power decides exact non-integral results past base^p's size (#138)" {
  let modes = [
    GdaRoundingMode::HalfEven,
    GdaRoundingMode::HalfUp,
    GdaRoundingMode::HalfDown,
    GdaRoundingMode::Down,
    GdaRoundingMode::Up,
    GdaRoundingMode::Ceiling,
    GdaRoundingMode::Floor,
    GdaRoundingMode::ZeroFiveUp,
  ]
  let two_1200 = (BigInt::from_int(1) << 1200).to_string()
  let two_1800 = (BigInt::from_int(1) << 1800).to_string()
  let expected = Decimal::from_string("\{two_1800}E-1800", precision=1000).unwrap()
  let cases = [
    ("\{two_1200}E-1200", "1.5"),
    (five_power(1200).to_string(), "-1.5"),
  ]
  for mode in modes {
    let ctx = GdaContext::new(
      precision=1000,
      rounding=mode,
      e_min=-999_999,
      e_max=999_999,
    )
    for entry in cases {
      let (left, right) = entry
      let outcome = power(
        Decimal::from_string(left, precision=1000).unwrap(),
        Decimal::from_string(right).unwrap(),
        ctx,
      )
      assert_eq(outcome.value().compare(expected), 0)
      assert_false(outcome.raised().contains(GdaSignal::InvalidOperation))
    }
  }
}

///|
// oracle: B
// source: 5^1024^(1/1024) = 5 and 0.25^4096.5 = 2^-8193 = 5^8193 * 10^-8193 by hand; 5^8193 and 5^1024 from five_power
//   (the BigInt power of the MoonBit core library, checked by digit count and first and last 20 digits against
//   CPython integers); CPython Decimal(5**8193) agrees with the expected value in half-even and floor
// shares: BigInt pow of the MoonBit core library; Decimal::from_string and to_string (reading the inputs, printing the result)
// primitives: core BigInt pow and to_string, checked on these values by digit count and first and last 20 digits
//   (CPython integers)
test "power decides exact powers with large reduced exponents" {
  let cases = [
    (five_power(1024).to_string(), "0.0009765625", 720, "5"),
    ("0.25", "4096.5", 5800, "\{five_power(8193)}E-8193"),
  ]
  for entry in cases {
    let (left, right, precision, expected) = entry
    let want = Decimal::from_string(expected, precision~).unwrap()
    for
      mode in [
        GdaRoundingMode::HalfEven,
        GdaRoundingMode::Floor,
        GdaRoundingMode::Up,
      ] {
      let ctx = GdaContext::new(
        precision~,
        rounding=mode,
        e_min=-999_999,
        e_max=999_999,
      )
      let outcome = power(
        Decimal::from_string(left, precision~).unwrap(),
        Decimal::from_string(right).unwrap(),
        ctx,
      )
      assert_eq(outcome.value().compare(want), 0)
      assert_false(outcome.raised().contains(GdaSignal::InvalidOperation))
    }
  }
}
