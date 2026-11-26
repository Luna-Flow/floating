///|
// The plain operators `+ - * /` and `sqrt` are the `_ctx` operations in the
// private working context of the larger operand precision (S1, #438): round
// half even, storage range (largest adjusted exponent 2147483646, smallest
// exponent -2147483645), no fold. Regression tests of #548, #549 and #553.

///|
fn plain_d(text : String, precision~ : Int32 = 34) -> Decimal {
  Decimal::from_string(text, precision~).unwrap()
}

///|
// oracle: S
// source: the identities x + 0 = x, 0 + x = x, x - 0 = x and x * 1 = x at and near both ends of the stored exponent range; the operands are the expected values (equality with the operand) and no result is written out
// shares: Decimal::from_string, Decimal::zero, Decimal::one and the plain operators (the code under test)
test "a finite value plus or minus zero is the value at the ends of the exponent range (#548)" {
  let zero = Decimal::zero()
  for
    text in [
      "1E2147483646", "1E-2147483645", "1E2000000001", "1E-2000000001", "7E2147483646",
      "-1E2147483646", "-1E-2147483645",
    ] {
    let x = plain_d(text)
    assert_true((x + zero).is_finite(), msg=text + " + 0")
    assert_true(x + zero == x, msg=text + " + 0")
    assert_true(zero + x == x, msg="0 + " + text)
    assert_true(x - zero == x, msg=text + " - 0")
    assert_true(x * Decimal::one() == x, msg=text + " * 1")
  }
}

///|
// oracle: A, S
// source: IEEE 754-2019 5.4 and 4.3: 1E+2147483646 + 1E-2147483645 rounds to 1E+2147483646 at 34 digits (the addend is below half an ulp), so the sum equals the large operand and the difference with the small one reversed is its negation; the stored range of the operands is the library's working range (level S)
// shares: Decimal::from_string, the local plain_d and the plain operators (they build the operands and are the code under test), to_string; also read through == (Decimal equality) (they read the operands and results, not the code under test)
test "two nonzero values with an exponent gap above 2,000,000,000 add exactly" {
  let a = plain_d("1E2147483646")
  let b = plain_d("1E-2147483645")
  assert_true(a + b == a)
  assert_true(b + a == a)
  assert_true(a - b == a)
  assert_true(b - a == -a)
}

///|
// oracle: A
// source: CPython decimal (re-run 2026-11-26) and IEEE 754-2019 5.2: 1.20 + 3.40 = 4.60, 999.999 + 0.001 = 1000.000 at 7 digits, 6.0 / 2 = 3.0, 1.25 * 2.50 = 3.1250 and 1.20 - 1.20 = 0.00 (the preferred exponents min, min, Q(x) - Q(y), the sum and min again)
// shares: Decimal::from_string, the local plain_d and the plain operators (they build the operands and are the code under test), to_string
test "the exact sum keeps the preferred exponent: 1.20 + 3.40 is 4.60" {
  assert_eq((plain_d("1.20") + plain_d("3.40")).to_string(), "4.60")
  assert_eq(
    (plain_d("999.999", precision=7) + plain_d("0.001", precision=7)).to_string(),
    "1000.000",
  )
  assert_eq((plain_d("6.0") / plain_d("2")).to_string(), "3.0")
  assert_eq((plain_d("1.25") * plain_d("2.50")).to_string(), "3.1250")
  assert_eq((plain_d("1.20") - plain_d("1.20")).to_string(), "0.00")
}

///|
// oracle: A, S
// source: CPython decimal (re-run 2026-11-26) and IEEE 754-2019 5.2: 1/3 at 7 digits is 0.3333333, 1234.567 * 9.876 at 5 digits is 12193 and 12345 + 0.5 at 3 digits is 1.23E+4 (an inexact result keeps all p digits); the precision label 5 of the product is the library's field (level S)
// shares: Decimal::from_string, the local plain_d and the plain operators (they build the operands and are the code under test), to_string; Decimal::precision (reads the precision field of the representation, a library field: the product of two 5-digit operands is labeled 5, level S)
test "an inexact result has the least exponent: p digits, not reduced" {
  let third = Decimal::from_int(1, precision=7) /
    Decimal::from_int(3, precision=7)
  assert_eq(third.to_string(), "0.3333333")
  let product = plain_d("1234.567", precision=5) * plain_d("9.876", precision=5)
  assert_eq(product.to_string(), "12193")
  assert_eq(product.precision(), 5)
  let sum = plain_d("12345", precision=3) + plain_d("0.5", precision=3)
  assert_eq(sum.to_string(), "1.23E+4")
}

///|
// oracle: S
// source: the library's rule that the plain operators work in the private context of the larger precision of the operands (the S1 decision of issue 438): the precision label of the result is the only thing checked and no value is written out
// shares: Decimal::from_string, the local plain_d and the plain operators (they build the operands and are the code under test), to_string, precision
test "the plain result has the larger precision of the operands" {
  let wide = plain_d("1", precision=50)
  let narrow = plain_d("3", precision=7)
  assert_eq((wide + narrow).precision(), 50)
  assert_eq((narrow * wide).precision(), 50)
  assert_eq((narrow / wide).precision(), 50)
  assert_eq(wide.sqrt().precision(), 50)
}

///|
// oracle: A
// source: IEEE 754-2019 6.3 and 7.3: x / +-0 for finite nonzero x is an infinity with the sign of the exact quotient (the xor of the signs, divideByZero), and 0 / 0 is NaN (invalid operation); written out
// shares: Decimal::from_string, the local plain_d and the plain operators (they build the operands and are the code under test), to_string; also read through neg and unary minus, is_nan (they read the operands and results, not the code under test)
test "division by a zero has the sign of the exact quotient (#549)" {
  let one = plain_d("1")
  let zero = Decimal::zero()
  let negative_zero = Decimal::negative_zero()
  assert_eq((one / zero).to_string(), "inf")
  assert_eq((one / negative_zero).to_string(), "-inf")
  assert_eq((-one / zero).to_string(), "-inf")
  assert_eq((-one / negative_zero).to_string(), "inf")
  assert_true((zero / zero).is_nan())
}

///|
// oracle: A
// source: IEEE 754-2019 6.3: the sign of a zero product is the exclusive or of the signs of the operands, also for -2 * +0 and 2 * -0; written out
// shares: Decimal::from_string, the local plain_d and the plain operators (they build the operands and are the code under test), to_string; also read through neg and unary minus, is_negative_zero (they read the operands and results, not the code under test)
test "the sign of a zero product is the xor of the signs (#553)" {
  let two = plain_d("2")
  let zero = Decimal::zero()
  let negative_zero = Decimal::negative_zero()
  assert_true((-two * zero).is_negative_zero())
  assert_true((two * negative_zero).is_negative_zero())
  assert_false((-two * negative_zero).is_negative_zero())
  assert_false((two * zero).is_negative_zero())
}

///|
// oracle: A, S
// source: IEEE 754-2019 7.4 and 7.5 with the working range of the plain operators, which is the library's (largest adjusted exponent 2147483646, smallest exponent -2147483645, level S): 1E+2147483646 squared overflows to infinity, 1E-2147483645 squared rounds to 0E-2147483645 and 1E+2147483646 + itself is 2E+2147483646 exactly; written out
// shares: Decimal::from_string, the local plain_d and the plain operators (they build the operands and are the code under test), to_string; also read through neg and unary minus (they read the operands and results, not the code under test)
test "a result beyond the working range overflows or underflows like a context result" {
  let big = plain_d("1E2147483646")
  assert_eq((big * big).to_string(), "inf")
  assert_eq((-big * big).to_string(), "-inf")
  let small = plain_d("1E-2147483645")
  assert_eq((small * small).to_string(), "0E-2147483645")
  assert_eq((big + big).to_string(), "2E+2147483646")
}

///|
// oracle: S
// source: the same identities for generated values of 1, 2, 34 and 100 digits at and near both ends of the working range and of the default range of a context given by the precision alone, both signs, with zeros; the operand is the expected value and no result is written out
// shares: Decimal::from_string, Decimal::zero, Decimal::one and the plain operators (the code under test)
test "the identities x + 0 = x, x - 0 = x, x * 1 = x hold over the stored range" {
  // generated values at and near both ends of the working range and of the
  // default range max(999999, 1000 p) of a context given by p alone, with 1, 2,
  // 34 and 100 digits, both signs, and zeros
  let digit_counts : Array[Int32] = [1, 2, 34, 100]
  let mut checked = 0
  for digits in digit_counts {
    let precision = Int32::max(digits, 34)
    let coefficient = "1" + String::make((digits - 1).to_int(), '7')
    let default_e_max = Int32::max(999_999, 1000 * precision)
    let top = 2147483646 - (digits - 1)
    let exponents : Array[Int32] = [
      top,
      top - 1,
      top - 33,
      2147483000,
      1_000_000_000,
      default_e_max - digits + 1,
      default_e_max,
      default_e_max + 1,
      1_000,
      5,
      1,
      0,
      -1,
      -5,
      -1_000,
      1 - default_e_max - precision,
      -default_e_max,
      -1_000_000_000,
      -2147483000,
      -2147483645,
      -2147483644,
      -2147483640,
    ]
    for exponent in exponents {
      for negative in [false, true] {
        let text = (if negative { "-" } else { "" }) +
          coefficient +
          "E" +
          exponent.to_string()
        let values = [
          plain_d(text, precision~),
          Decimal::make(
            bigint_from_text(coefficient) * (if negative { -1N } else { 1N }),
            exponent,
            precision,
          ),
        ]
        for x in values {
          let zero = Decimal::zero(precision~)
          let one = Decimal::one(precision~)
          assert_true((x + zero).is_finite(), msg=text + " + 0")
          assert_true(x + zero == x, msg=text + " + 0")
          assert_true(zero + x == x, msg="0 + " + text)
          assert_true(x - zero == x, msg=text + " - 0")
          assert_true(x * one == x, msg=text + " * 1")
          assert_true(one * x == x, msg="1 * " + text)
          checked += 1
        }
      }
    }
    // zeros at the ends
    for exponent in [2147483646, -2147483645, 0] {
      for negative in [false, true] {
        let z = Decimal::make(0N, exponent, precision)
        let z = if negative { z.neg() } else { z }
        assert_true(z + Decimal::zero(precision~) == z)
        assert_true(z * Decimal::one(precision~) == z)
        checked += 1
      }
    }
  }
  assert_true(checked > 300)
}
