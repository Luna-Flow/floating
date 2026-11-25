///|
/// S1: a plain operator is the GDA operation in the working context at the larger
/// precision of its operands, round-half-even, without flags.
// oracle: A
// source: written out from the preferred exponents of GDA 1.70: the minimum for + and -, the sum for *, the difference for /: 1.20 + 3.40 = 4.60, 1.20 - 3.40 = -2.20, 0.00 + 0.0 = 0.00, 2.50 * 2 = 5.00, 6.0 / 2 = 3.0, 1 / 4 = 0.25
// shares: Decimal::from_string (reads the operands), Decimal::to_string (prints the result)
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
/// The working context is wide enough that adding zero does not change a stored
/// value, down to Etiny = -2,147,483,645.
// oracle: A
// source: the operand itself: x + 0 equals x as a number for stored values down to Etiny = -2,147,483,645, because the working context is wide enough that no rounding occurs (GDA 1.70 add); the comparison is the numeric `==`
// shares: Decimal `==` (numeric equality)
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
// oracle: A
// source: written out: sqrt(4.00) = 2.0 (ideal exponent), sqrt of a negative operand is NaN (Invalid operation), sqrt(2) at precision 10 = 1.414213562, sqrt(0) = 0 (CPython agrees)
// shares: Decimal::from_string (reads the operands), Decimal::to_string (prints the result)
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
// oracle: A
// source: written out from GDA 1.70: 1 / 0 is Infinity, 0 / 0 and inf - inf and inf * 0 are NaN (Invalid operation), a NaN operand gives NaN, a signaling NaN operand gives a quiet NaN
// shares: nothing
test "plain operators on special values and zero divisors" {
  let one = Decimal::one()
  assert_true((one / Decimal::zero()).is_infinite())
  assert_true((Decimal::zero() / Decimal::zero()).is_nan())
  assert_true((Decimal::inf() - Decimal::inf()).is_nan())
  assert_true((Decimal::inf() * Decimal::zero()).is_nan())
  assert_true((Decimal::nan() + one).is_nan())
  assert_true((Decimal::signaling_nan(payload=7N) + one).is_qnan())
}

///|
/// An exponent difference below `Int` with a dividend longer than the divisor:
/// the quotient lies in the range, so it is rounded, not lost to infinity.
// oracle: A
// source: written out: the quotient 1.2345E-2147483646 is below Etiny = -2147483645 and rounds to 0E-2147483645, 9.9999E-2147483646 rounds up to one unit 1E-2147483645 (GDA 1.70 underflow, half even), both signs
// shares: nothing
test "plain division with an exponent difference below Int" {
  // the operands are beyond the stored range: no public constructor makes them,
  // the engine must still not wrap
  let d = fn(text : String) { decimal_text_unchecked(text) }
  // 1.2345E-2147483646 is below Etiny = -2147483645: rounds to zero
  inspect(d("12345E-2147483648") / d("1E+2"), content="0E-2147483645")
  // 9.9999E-2147483646 rounds up to one unit of Etiny
  inspect(d("99999E-2147483648") / d("1E+2"), content="1E-2147483645")
  inspect(d("-99999E-2147483648") / d("1E+2"), content="-1E-2147483645")
  // exactly representable at Etiny: kept
  inspect(d("12300000E-2147483648") / d("1E+2"), content="1.23E-2147483643")
  // subnormal: limited to the digits down to Etiny
  inspect(
    d("123456789012345678901234567890123456789E-2147483648") / d("1E+9"),
    content="1.23456789012345678901234568E-2147483619",
  )
  // an inexact quotient with the guard cut by the floor, rounded at Etiny
  inspect(d("5E-2147483640") / d("3E+1"), content="1.6667E-2147483641")
}

///|
/// Oracle (level A): Python `decimal` (libmpdec, correctly rounded for add,
/// subtract, multiply, divide and sqrt) in the context of the plain operators:
/// precision P, half-even, no clamp, no traps, Emax 2,147,483,646, Emin
/// -2,147,483,645 + P - 1 (`tools/generate_decimal_gda_plain_rows.py`; no model of
/// this library's algorithm). 14 operands (zeros, cohort members, long coefficients,
/// the largest and smallest of the stored range, infinity, NaN) in all pairs at
/// 3, 16 and 34 digits. The table replaces two tests that compared the operators
/// with the free functions they call.
// oracle: A
// source: the table plain_operator_rows of plain_operator_rows_wbtest.mbt (see its header and tools/generate_decimal_gda_plain_rows.py): CPython decimal, libmpdec
// shares: Decimal::from_string (reads the operands), Decimal::to_string (prints the result)
test "plain operators equal the libmpdec results of the working context" {
  assert_eq(plain_operator_rows.length(), 2394)
  for row in plain_operator_rows {
    let (op, precision, a_text, b_text, expected) = row
    let a = Decimal::from_string(a_text, precision~).unwrap()
    let label = "\{op} p=\{precision} \{a_text} \{b_text}"
    let actual = match op {
      "sqrt" => a.sqrt()
      _ => {
        let b = Decimal::from_string(b_text, precision~).unwrap()
        match op {
          "add" => a + b
          "sub" => a - b
          "mul" => a * b
          "div" => a / b
          _ => abort("unknown operation " + op)
        }
      }
    }
    if expected == "nan" {
      assert_true(
        actual.is_nan(),
        msg=label + " want nan, got " + actual.to_string(),
      )
    } else {
      assert_eq((label, actual.to_string()), (label, expected))
    }
  }
}
