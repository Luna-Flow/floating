///|
/// Whether a finite `Decimal` is inside the stored range
/// (`gda_value_e_tiny <= exponent`, `exponent + digits - 1 <=
/// gda_value_e_max`); a value that is not finite is outside the
/// question.
fn stored_in_range(x : Decimal) -> Bool {
  if !x.is_finite() {
    return true
  }
  x.exponent10().to_int64() >= gda_value_e_tiny.to_int64() &&
  adjusted_exponent64(x) <= gda_value_e_max.to_int64()
}

///|
/// The stored values of the range tests: every number of digits, every
/// exponent at and near the two limits and in between, both signs, zeros.
fn stored_range_values() -> Array[Decimal] {
  let values = []
  let tiny = gda_value_e_tiny.to_int64()
  let top = gda_value_e_max.to_int64()
  for digits in [1, 2, 3, 34, 35, 100] {
    // 10^(digits-1) * 7 + 3 keeps `digits` digits and is not a power of ten
    let mut coefficient = 7N
    for _ in 1..<digits {
      coefficient = coefficient * 10N + 3N
    }
    let high = top - (digits - 1).to_int64()
    for
      exponent in [
        tiny,
        tiny + 1L,
        tiny + 40L,
        -1000000000L,
        -34L,
        -1L,
        0L,
        1L,
        34L,
        1000000000L,
        high - 40L,
        high - 1L,
        high,
      ] {
      for negative in [false, true] {
        let signed = if negative { -coefficient } else { coefficient }
        values.push(Decimal::make(signed, exponent.to_int(), digits.max(1)))
      }
    }
  }
  for exponent in [gda_value_e_tiny, -1, 0, 1, gda_value_e_max] {
    values.push(Decimal::make(0N, exponent, 34))
  }
  values
}

///|
// oracle: A
// source: e_min = Etiny + precision - 1 with Etiny = Emin - precision + 1 (GDA 1.70, Context), the six rows
//   written out as integers computed with Python; the stored limits -2147483645 and 2147483646 are the
//   documented design range of the library (Int32 minimum + 3, Int32 maximum - 1), not a clause of GDA
// shares: nothing
test "the limits are the range of the working context of the plain operators" {
  // (precision, e_min) written out: e_min = Etiny + precision - 1 with Etiny = -2147483645 (GDA 1.70, Etiny =
  // Emin - precision + 1), computed with Python integers
  let rows : Array[(Int32, Int32)] = [
    (1, -2_147_483_645),
    (2, -2_147_483_644),
    (7, -2_147_483_639),
    (34, -2_147_483_612),
    (100, -2_147_483_546),
    (999_999_999, -1_147_483_647),
  ]
  for row in rows {
    let (precision, e_min) = row
    let context = gda_plain_working_context(precision)
    assert_eq(context.e_max_, 2147483646)
    assert_eq(etiny(context.decimal_), -2147483645)
    assert_eq(context.e_min_, e_min)
  }
  assert_eq(gda_value_e_max, 2147483646)
  assert_eq(gda_value_e_tiny, -2147483645)
}

///|
// oracle: A
// source: expected strings and error substrings written out at the two limits of the stored range (-2147483645
//   and 2147483646, the documented design range); the carry case follows from 35 nines rounding to 10^34
// shares: nothing
test "make and try_make accept the limits and reject one past each" {
  let e_max = gda_value_e_max
  let e_tiny = gda_value_e_tiny
  // accepted: 1, 34 digits and zero, at the exponent floor and at the top
  inspect(Decimal::make(1N, e_tiny, 34), content="1E-2147483645")
  inspect(Decimal::make(0N, e_tiny, 34), content="0E-2147483645")
  inspect(Decimal::make(1N, e_max, 34), content="1E+2147483646")
  inspect(Decimal::make(0N, e_max, 34), content="0E+2147483646")
  inspect(
    Decimal::make(9999999999999999999999999999999999N, e_max - 33, 34),
    content="9.999999999999999999999999999999999E+2147483646",
  )
  for
    entry in [
      (1N, e_tiny - 1, 34),
      (0N, e_tiny - 1, 34),
      (1N, -2147483648, 34),
      (0N, -2147483648, 34),
      (1N, e_max + 1, 34),
      (0N, e_max + 1, 34),
      (12N, e_max, 34),
      (1N, 2147483647, 34),
      // rounding to the precision leaves the exponent below the floor
      (123456N, e_tiny - 4, 3),
      // 35 nines round up to 10^34 and the carry leaves the top
      (99999999999999999999999999999999999N, e_max - 34, 34),
    ] {
    let (coefficient, exponent, precision) = entry
    match Decimal::try_make(coefficient, exponent, precision) {
      Ok(value) =>
        fail("try_make accepted \{coefficient}E\{exponent}: \{value}")
      Err(error) => {
        assert_true(error.is_domain_error())
        assert_true(error.message.contains("-2147483645"))
        assert_true(error.message.contains("2147483646"))
        assert_true(error.message.contains(exponent.to_string()))
      }
    }
  }
  // the rounded exponent is what counts
  inspect(Decimal::make(123456N, e_tiny - 3, 3), content="1.23E-2147483643")
  assert_true(Decimal::try_make(1N, 0, 0) is Err(_))
  // the mode applies as in make
  inspect(
    Decimal::try_make(1259N, 0, 3, mode=GdaRoundingMode::Down).unwrap(),
    content="1.25E+3",
  )
}

///|
// oracle: A, S
// source: the edge rows are expected strings written out at the two limits of the stored range (x + 0, x - 0
//   and x * 1 keep the operand, GDA 1.70 add and multiply); the loop over stored_range_values is an
//   identity (S) whose expected value is the operand itself
// shares: stored_in_range (the range predicate, checked by the make and try_make block)
test "x + 0, x * 1 and x - 0 equal x for every stored finite value" {
  let zero = Decimal::zero()
  let one = Decimal::one()
  let values = stored_range_values()
  assert_true(values.length() > 150)
  let lowest = Decimal::make(1N, gda_value_e_tiny, 34)
  inspect(lowest + zero, content="1E-2147483645")
  inspect(lowest - zero, content="1E-2147483645")
  inspect(lowest * one, content="1E-2147483645")
  let highest = Decimal::make(1N, gda_value_e_max, 34)
  // the zero has exponent 0, so the exact sum has 2147483647 digits and rounds to 34 (GDA 1.70, add)
  inspect(
    highest + zero,
    content="1.000000000000000000000000000000000E+2147483646",
  )
  inspect(
    highest - zero,
    content="1.000000000000000000000000000000000E+2147483646",
  )
  inspect(highest * one, content="1E+2147483646")
  for x in values {
    assert_true(stored_in_range(x))
    assert_true(x + zero == x, msg="x + 0 for \{x}")
    assert_true(x - zero == x, msg="x - 0 for \{x}")
    assert_true(x * one == x, msg="x * 1 for \{x}")
  }
}

///|
/// Every public function of the package that returns a `Decimal` and takes no
/// context returns, for stored values, a value that is not finite or one inside
/// the stored range. The functions are listed by name: a new one has to be added
/// here. (`Decimal::from_*`, `make`, `zero`, `one` and the other constructors
/// take no `Decimal`; the last test of this file covers them.)
// oracle: S
// source: the invariant that a result is not finite or inside the stored range, checked by stored_in_range; no
//   expected value is computed
// shares: stored_in_range
test "no function without a context leaves the stored range" {
  let values = stored_range_values()
  let modes = [
    GdaRoundingMode::HalfEven,
    GdaRoundingMode::HalfUp,
    GdaRoundingMode::HalfDown,
    GdaRoundingMode::Down,
    GdaRoundingMode::Ceiling,
    GdaRoundingMode::Floor,
    GdaRoundingMode::Up,
    GdaRoundingMode::ZeroFiveUp,
  ]
  let mut checked = 0
  let check = fn(name : String, result : Decimal) raise {
    checked += 1
    assert_true(
      stored_in_range(result),
      msg=name + " gave " + result.to_string(),
    )
  }
  for x in values {
    check("Decimal::abs", x.abs())
    check("Decimal::neg", -x)
    check("Decimal::copy", x.copy())
    check("Decimal::copy_abs", x.copy_abs())
    check("Decimal::copy_negate", x.copy_negate())
    check("Decimal::trim", x.trim())
    check("Decimal::normalized", x.normalized())
    check("Decimal::sqrt", x.sqrt())
    for precision in [1, 2, 3, 34] {
      for mode in modes {
        check("Decimal::with_precision", x.with_precision(precision, mode))
      }
    }
  }
  // the binary functions on pairs: every value with a sample of the others
  let step = 7
  for i, x in values {
    let y = values[(i * step + 3) % values.length()]
    check("Decimal::add", x + y)
    check("Decimal::sub", x - y)
    check("Decimal::mul", x * y)
    check("Decimal::div", x / y)
    check("Decimal::copy_sign", x.copy_sign(y))
    let low = if x < y { x } else { y }
    let high = if x < y { y } else { x }
    check("Decimal::clamp", x.clamp(min=low, max=high))
  }
  assert_true(checked > 4000)
}

///|
/// The constructors that take no `Decimal` and could, in principle, leave the
/// range: only `make`, `try_make` and `from_string` take an exponent, the others
/// build exponent 0 or are bounded by their argument type.
// oracle: S
// source: the invariant that a constructed value is inside the stored range, checked by stored_in_range
// shares: stored_in_range
test "constructors without an exponent stay inside the stored range" {
  for n in [0, 1, -1, 2147483647, -2147483647 - 1] {
    assert_true(stored_in_range(Decimal::from_int(n)))
  }
  assert_true(stored_in_range(Decimal::from_bigint(10N.pow(1000))))
  for x in [1.0e308, 5.0e-324, -1.7976931348623157e308, 0.0, 0.1] {
    assert_true(stored_in_range(Decimal::from_double(x)))
  }
  for x in [Float::from_double(1.0e38), Float::from_double(1.0e-45)] {
    assert_true(stored_in_range(Decimal::from_float(x)))
  }
  for x in [Decimal::zero(), Decimal::one(), Decimal::negative_zero()] {
    assert_true(stored_in_range(x))
  }
}
