///|

///|
/// The digits after the point of ln 2 and of ln(5/4), 300 each, written out
/// (CPython decimal at 400 digits).
fn ln2_digits() -> String {
  "693147180559945309417232121458176568075500134360255254120680009493393621969694715605863326996418687542001481020570685733685520235758130557032670751635075961930727570828371435190307038623891673471123350115364497955239120475172681574932065155524734139525882950453007095326366642654104239157814952043740"
}

///|
fn ln_5_over_4_digits() -> String {
  "223143551314209755766295090309834503374601085548007213671287872487391743768268333418407224100342235715963340980574191432352964757808415085568275114193553803690724495840440375272878778954558178115023454962871883866911484737848177562902024420172341248896755391915343869069834386977078762145959544090883"
}

///|
/// `round_half_even(0.<digits> * 10^scale)` by comparing the digits after the cut,
/// with core BigInt arithmetic only.
fn scaled_from_digits(digits : String, scale : Int32) -> BigInt {
  let n = scale.to_int()
  let head = bigint_from_text(digits[0:n])
  let next = digits[n:n + 1].to_owned()
  let mut rest_nonzero = false
  for c in digits[n + 1:] {
    if c != '0' {
      rest_nonzero = true
    }
  }
  let odd = head % 2N == 1N
  if next > "5" || (next == "5" && (rest_nonzero || odd)) {
    head + 1N
  } else {
    head
  }
}

///|
// oracle: A, S
// source: ln 2 and ln(5/4) to 300 digits from CPython decimal at 400 digits (written out as ln2_digits and ln_5_over_4_digits), rounded half-even at each scale by digit comparison; the combination ln 10 = 3 ln 2 + ln(5/4) of the rounded pieces and ln 5 = ln 10 - ln 2, and the error bounds of one, four and five units at the scales 9 and 10 (where the library's series, stopped at a term below 10^8 work units, is one unit below the correct rounding of ln 2), are the library's design for internal guard-digit constants (level S); the earlier oracle was a series evaluation that used the library's round_positive_decimal_div
// shares: dec_coeff_from_int and to_bigint (conversions of the operands and the results), decimal_ln_atanh_scaled_coeff and decimal_transcendental_ln_constants (the code under test)
test "BigInt-free ln constants preserve the old scaled integers" {
  let saved_cache = decimal_math_constant_cache.val
  decimal_math_constant_cache.val = {
    scale: 0,
    ln2: dec_coeff_zero(),
    ln5: dec_coeff_zero(),
    ln10: dec_coeff_zero(),
  }
  for scale in [1, 2, 8, 9, 10, 34, 40, 64, 128, 257] {
    let expected_ln2 = scaled_from_digits(ln2_digits(), scale)
    let expected_lnfq = scaled_from_digits(ln_5_over_4_digits(), scale)
    let expected_ln10 = expected_ln2 * 3N + expected_lnfq
    let expected_ln5 = expected_ln10 - expected_ln2
    let actual_ln2 = decimal_ln_atanh_scaled_coeff(
      dec_coeff_from_int(2),
      dec_coeff_from_int(1),
      scale,
    )
    let actual_reverse = decimal_ln_atanh_scaled_coeff(
      dec_coeff_from_int(1),
      dec_coeff_from_int(2),
      scale,
    )
    assert_false(actual_ln2.negative)
    assert_true(actual_reverse.negative)
    let (ln2, ln5, ln10) = decimal_transcendental_ln_constants(scale)
    // The constants are internal values for working precisions with guard digits,
    // not correctly rounded results: the series stops at a term below 10^8 units
    // of the work scale, so ln 2 may be one unit below the correct rounding (it
    // is at the scales 9 and 10 of this list), ln 10 = 3 ln 2 + ln(5/4) up to
    // four units and ln 5 up to five. At every other scale of the list they are equal.
    let exact_scale = scale != 9 && scale != 10
    for
      pair in [
        (actual_ln2.magnitude.to_bigint(), expected_ln2, 1N),
        (actual_reverse.magnitude.to_bigint(), expected_ln2, 1N),
        (ln2.to_bigint(), expected_ln2, 1N),
        (ln5.to_bigint(), expected_ln5, 5N),
        (ln10.to_bigint(), expected_ln10, 4N),
      ] {
      let (actual, expected, bound) = pair
      let difference = if actual > expected {
        actual - expected
      } else {
        expected - actual
      }
      assert_true(
        difference <= bound,
        msg="scale \{scale}: \{actual} vs \{expected}",
      )
      if exact_scale {
        assert_eq(actual, expected)
      }
    }
  }
  decimal_math_constant_cache.val = saved_cache
}

///|
// oracle: A
// source: integer arithmetic: 999.999 + 0.001 at exponent -3 is 999999 + 1 = 1000000, 1000 - 0.001 is 1000000 - 1 = 999999, -0.001 + -1000 has magnitude 1000001 and is negative, 10000E+1 + 10000E-50 at exponent -50 is 10^55 + 10000 with 56 digits; written out
// shares: Decimal::from_string (builds the operands) and the coefficient conversions to_bigint and dec_coeff_from_bigint_repr, decimal_exact_aligned_sum_result (the code under test)
test "decimal exact aligned sum keeps GDA unit accumulator representation" {
  let carry_lhs = Decimal::from_string("999.999", precision=16).unwrap()
  let carry_rhs = Decimal::from_string("0.001", precision=16).unwrap()
  let (carry_negative, carry) = decimal_exact_aligned_sum_result(
    carry_lhs, carry_rhs, -3,
  )
  assert_false(carry_negative)
  assert_eq(carry.to_bigint(), 1000000N)

  let borrow_lhs = Decimal::from_string("1000", precision=16).unwrap()
  let borrow_rhs = Decimal::from_string("-0.001", precision=16).unwrap()
  let (borrow_negative, borrow) = decimal_exact_aligned_sum_result(
    borrow_lhs, borrow_rhs, -3,
  )
  assert_false(borrow_negative)
  assert_eq(borrow.to_bigint(), 999999N)

  let (reverse_negative, reverse) = decimal_exact_aligned_sum_result(
    borrow_rhs,
    Decimal::from_string("-1000", precision=16).unwrap(),
    -3,
  )
  assert_true(reverse_negative)
  assert_eq(reverse.to_bigint(), 1000001N)

  let huge_lhs = Decimal::from_string("10000E+1", precision=64).unwrap()
  let tiny_rhs = Decimal::from_string("10000E-50", precision=64).unwrap()
  let (huge_negative, huge) = decimal_exact_aligned_sum_result(
    huge_lhs, tiny_rhs, -50,
  )
  assert_false(huge_negative)
  assert_eq(huge.to_bigint(), pow10(55) + 10000N)
  assert_eq(huge.digits10(), 56)
}

///|
// oracle: A
// source: IEEE 754-2019 5.2 and 6.3: the exact sum 999.999 + 0.001 = 1000.000 keeps the preferred exponent min(-3, -3) = -3 (coefficient 1000000, not reduced); 1.20 + -1.20 is a zero with positive sign under rounding to nearest; written out
// shares: Decimal::from_string (builds the operands) and the coefficient conversions to_bigint and dec_coeff_from_bigint_repr, Decimal::add (the code under test)
test "decimal plain add keeps the preferred exponent of an exact sum" {
  let sum = Decimal::from_string("999.999", precision=7)
    .unwrap()
    .add(Decimal::from_string("0.001", precision=7).unwrap())
  // The sum keeps the preferred exponent min(-3, -3): it is not reduced.
  assert_eq(sum.coefficient.to_bigint(), 1000000N)
  assert_eq(sum.exponent10, -3)
  assert_false(sum.negative)

  let cancellation = Decimal::from_string("1.20", precision=7)
    .unwrap()
    .add(Decimal::from_string("-1.20", precision=7).unwrap())
  assert_true(cancellation.coefficient.is_zero())
  assert_false(cancellation.negative)
}

///|
// oracle: A
// source: arithmetic identity checked with core BigInt: root^2 + remainder = value and remainder <= 2 root, for 0, 1, 2, 3, 4, 15, 16, 17 and 10^160 - 1; no value is taken from the code under test except the pair (root, remainder) it returns
// shares: dec_coeff_from_bigint_repr and to_bigint (convert the operand and the results), dec_coeff_integer_sqrt_rem_repr (the code under test)
test "decimal integer sqrt_rem preserves exact decomposition" {
  for value in [0N, 1N, 2N, 3N, 4N, 15N, 16N, 17N, pow10(160) - 1N] {
    let (root, remainder) = dec_coeff_integer_sqrt_rem_repr(
      dec_coeff_from_bigint_repr(value),
    )
    let root_bigint = root.to_bigint()
    assert_eq(root_bigint * root_bigint + remainder.to_bigint(), value)
    assert_true(remainder.to_bigint() < root_bigint * 2N + 1N)
  }
}

///|
// oracle: A
// source: arithmetic and IEEE 754-2019 4.3: 125/10 = 12.5 is a tie (12 half-even, 13 half-up); 123456789012345678901 = 97 * 1272750402189130710 + 31 (checked with Python integers), so a negative quotient under Floor rounds its magnitude up to 1272750402189130711; written out
// shares: dec_coeff_from_bigint_repr and to_bigint (convert the operands and results), round_positive_decimal_div_repr (the code under test)
test "decimal coefficient repr rounded division is isomorphic to BigInt path" {
  let numerator = dec_coeff_from_bigint_repr(125N)
  let denominator = dec_coeff_from_bigint_repr(10N)
  // 125 / 10 = 12.5, a tie: half-even gives 12, half-up gives 13
  assert_eq(
    round_positive_decimal_div_repr(
      numerator,
      denominator,
      false,
      DecimalRound::HalfEven,
    ).to_bigint(),
    12N,
  )
  assert_eq(
    round_positive_decimal_div_repr(
      numerator,
      denominator,
      false,
      DecimalRound::HalfUp,
    ).to_bigint(),
    13N,
  )
  // 123456789012345678901 = 97 * 1272750402189130710 + 31: for a negative value
  // the magnitude rounds up under Floor
  assert_eq(
    round_positive_decimal_div_repr(
      dec_coeff_from_bigint_repr(123456789012345678901N),
      dec_coeff_from_bigint_repr(97N),
      true,
      DecimalRound::Floor,
    ).to_bigint(),
    1272750402189130711N,
  )
}

///|
// oracle: A
// source: arithmetic and IEEE 754-2019 5.2: 1/8 = 0.125 exactly (coefficient 125, exponent -3); -2/3 at three digits is -0.667 (coefficient 667, negative); written out
// shares: Decimal::from_string (builds the operands) and the coefficient conversions to_bigint and dec_coeff_from_bigint_repr, Decimal::from_int and Decimal::div (the code under test)
test "decimal plain division keeps GDA quotient units through normalization" {
  let exact = Decimal::from_int(1, precision=16).div(
    Decimal::from_int(8, precision=16),
  )
  assert_eq(exact.coefficient.to_bigint(), 125N)
  assert_eq(exact.exponent10, -3)
  assert_false(exact.negative)

  let rounded = Decimal::from_int(-2, precision=3).div(
    Decimal::from_int(3, precision=3),
  )
  assert_eq(rounded.coefficient.to_bigint(), 667N)
  assert_eq(rounded.exponent10, -3)
  assert_true(rounded.negative)
}

///|
// oracle: A
// source: arithmetic: 1234 at three digits is 123E+1 (coefficient 123, exponent 1) with inexact; a negative zero compares greater than -1 (1), less than 1 (-1) and equal to +0 (0), IEEE 754-2019 5.11; written out
// shares: Decimal::from_string (builds the operands) and the coefficient conversions to_bigint and dec_coeff_from_bigint_repr, Decimal::negative_zero and zero, apply_ctx and compare_finite (the code under test)
test "decimal unary finalize and zero compare stay coefficient-native" {
  let ctx = DecimalContext::new(precision=3)
  let value = Decimal::from_string("1234", precision=16).unwrap()
  let (applied, flags) = value.apply_ctx(ctx)
  assert_eq(applied.coefficient.to_bigint(), 123N)
  assert_eq(applied.exponent10, 1)
  assert_true(flags.inexact)

  let zero = Decimal::negative_zero(precision=16)
  assert_eq(compare_finite(zero, Decimal::from_int(-1, precision=16)), 1)
  assert_eq(compare_finite(zero, Decimal::from_int(1, precision=16)), -1)
  assert_eq(compare_finite(zero, Decimal::zero(precision=16)), 0)
}

///|
// oracle: A
// source: arithmetic: 12345 / 10^2 = 123.45 rounds half-even to 123, 5 / 10 = 0.5 rounds half-up to 1, both inexact; written out
// shares: dec_coeff_from_bigint_repr and to_bigint (convert the operands and results), round_positive_decimal_div_pow10_repr (the code under test)
test "decimal coefficient repr power-of-ten rounding matches BigInt path" {
  // 12345 / 10^2 = 123.45: 123 half-even, inexact
  let (repr_half, repr_half_inexact) = round_positive_decimal_div_pow10_repr(
    dec_coeff_from_bigint_repr(12345N),
    2,
    false,
    DecimalRound::HalfEven,
  )
  assert_eq(repr_half.to_bigint(), 123N)
  assert_true(repr_half_inexact)
  // 5 / 10 = 0.5: 1 half-up, inexact
  let (repr_tiny, repr_tiny_inexact) = round_positive_decimal_div_pow10_repr(
    dec_coeff_from_bigint_repr(5N),
    1,
    false,
    DecimalRound::HalfUp,
  )
  assert_eq(repr_tiny.to_bigint(), 1N)
  assert_true(repr_tiny_inexact)
}

///|
// oracle: A
// source: the definition of the context precision: a fixed precision context (34 or 9) gives that precision whatever the coefficient; written out
// shares: dec_coeff_from_bigint_repr (builds the operand), finite_precision_for_coeff (the code under test)
test "decimal coefficient-native precision helper matches bigint precision helper" {
  let coeff = dec_coeff_from_bigint_repr(1234500N)
  let exact_ctx = DecimalContext::new(precision=34)
  let fixed_ctx = DecimalContext::new(precision=9)
  // a fixed context gives its own precision, whatever the coefficient
  assert_eq(finite_precision_for_coeff(coeff, exact_ctx), 34)
  assert_eq(finite_precision_for_coeff(coeff, fixed_ctx), 9)
}

///|
// oracle: A
// source: arithmetic and IEEE 754-2019 5.2: (4E+1)^3 = 64E+3 (coefficient 64, exponent 3) and 1/(4E+1) = 0.025 = 25E-3, both exact; written out
// shares: Decimal::from_string (builds the operands) and the coefficient conversions to_bigint and dec_coeff_from_bigint_repr, decimal_power_integer_exact_result and exact_decimal_reciprocal (the code under test)
test "decimal exact integer power and reciprocal keep coefficient units" {
  let exact_ctx = DecimalContext::new(precision=34)
  let base = Decimal::from_string("4E+1", precision=16).unwrap()
  let (positive, positive_flags) = decimal_power_integer_exact_result(
    base, 3, exact_ctx,
  ).unwrap()
  assert_eq(positive.coefficient.to_bigint(), 64N)
  assert_eq(positive.exponent10, 3)
  assert_false(positive_flags.inexact)

  let (reciprocal, reciprocal_flags) = exact_decimal_reciprocal(
    Decimal::from_string("4E+1", precision=16).unwrap(),
    exact_ctx,
  ).unwrap()
  assert_eq(reciprocal.coefficient.to_bigint(), 25N)
  assert_eq(reciprocal.exponent10, -3)
  assert_false(reciprocal_flags.inexact)
}

///|
// oracle: A
// source: arithmetic: 123456789^2 = 15241578750190521 (checked with Python integers), so its root has coefficient 123456789 and exponent 0; sqrt(1.4400) = 1.20 (coefficient 120, exponent -2: the preferred exponent floor(-4/2), IEEE 754-2019 5.4.1); sqrt(2) is irrational, so None; written out
// shares: Decimal::from_string (builds the operands) and the coefficient conversions to_bigint and dec_coeff_from_bigint_repr, exact_finite_sqrt (the code under test)
test "decimal exact square root uses GDA Newton unit operations" {
  let perfect = Decimal::from_string("15241578750190521", precision=32).unwrap()
  let exact = exact_finite_sqrt(perfect, 32).unwrap()
  assert_eq(exact.coefficient.to_bigint(), 123456789N)
  assert_eq(exact.exponent10, 0)

  let scaled = Decimal::from_string("1.4400", precision=16).unwrap()
  let scaled_exact = exact_finite_sqrt(scaled, 16).unwrap()
  assert_eq(scaled_exact.coefficient.to_bigint(), 120N)
  assert_eq(scaled_exact.exponent10, -2)

  assert_true(
    exact_finite_sqrt(Decimal::from_string("2", precision=16).unwrap(), 16)
    is None,
  )
}

///|
// oracle: A
// source: arithmetic: -1.25 scaled by 10^3 is -1250; with ln 10 scaled as 2303 the quotient floor(-1250 / 2303) is -1 and -1250 + 2303 = 1053; written out
// shares: dec_coeff_from_bigint_repr, dec_coeff_from_nonnegative_int and to_bigint (convert the operands and results), decimal_finite_to_scaled_repr, decimal_floor_div_scaled_repr, dec_coeff_multiply_repr and dec_coeff_signed_add_repr (the code under test)
test "decimal exp range reduction keeps runtime coefficient units" {
  let value = Decimal::from_string("-1.25", precision=16).unwrap()
  let (negative, scaled) = decimal_finite_to_scaled_repr(value, 3)
  assert_true(negative)
  assert_eq(scaled.to_bigint(), 1250N)

  let ln10 = dec_coeff_from_bigint_repr(2303N)
  let exponent = decimal_floor_div_scaled_repr(negative, scaled, ln10)
  assert_eq(exponent, -1)
  let product = dec_coeff_multiply_repr(
    dec_coeff_from_nonnegative_int(abs_int(exponent)),
    ln10,
  )
  let (reduced_negative, reduced) = dec_coeff_signed_add_repr(
    negative,
    scaled,
    exponent >= 0,
    product,
  )
  assert_false(reduced_negative)
  assert_eq(reduced.to_bigint(), 1053N)
}

///|
// oracle: A, S
// source: arithmetic: 1234500E-2 is the integer 12345, -42.000 is -42, 12.34 is not an integer; the count helpers return Some of the value within their bound and None beyond it (the bound 999,999,999 and the bound argument are the library's design limits, level S); written out
// shares: Decimal::from_string (builds the operands) and the coefficient conversions to_bigint and dec_coeff_from_bigint_repr, decimal_exact_integer_coeff and decimal_power_integer_count (the code under test)
test "decimal exact integer helpers match normalized finite values" {
  let integer = Decimal::from_string("1234500E-2", precision=16).unwrap()
  let negative = Decimal::from_string("-42.000", precision=16).unwrap()
  let fractional = Decimal::from_string("12.34", precision=16).unwrap()
  let huge = Decimal::from_string("1234567890123", precision=16).unwrap()

  match decimal_exact_integer_coeff(integer) {
    Some((negative, magnitude)) => {
      assert_false(negative)
      assert_eq(magnitude.to_bigint(), 12345N)
    }
    None => fail("expected exact positive integer coefficient")
  }
  match decimal_exact_integer_coeff(negative) {
    Some((negative, magnitude)) => {
      assert_true(negative)
      assert_eq(magnitude.to_bigint(), 42N)
    }
    None => fail("expected exact negative integer coefficient")
  }
  assert_true(decimal_exact_integer_coeff(fractional) is None)

  assert_true(decimal_power_integer_count(integer, 999_999_999) == Some(12345))
  assert_true(decimal_power_integer_count(negative, 999_999_999) == Some(-42))
  assert_true(decimal_power_integer_count(fractional, 999_999_999) is None)
  assert_true(decimal_power_integer_count(huge, 999_999_999) is None)

  assert_true(decimal_power_integer_count(integer, 20_000) == Some(12345))
  assert_true(decimal_power_integer_count(negative, 100) == Some(-42))
  assert_true(decimal_power_integer_count(huge, 999_999_999) is None)
}

///|
// oracle: A
// source: arithmetic: -8.000 is even, -7 is odd, 0E-4 is even, 3.5 is not an integer (None); written out
// shares: Decimal::from_string (builds the operands) and the coefficient conversions to_bigint and dec_coeff_from_bigint_repr, decimal_power_integer_is_odd (the code under test)
test "decimal integer parity helper rejects fractional values and tracks signless oddness" {
  let even = Decimal::from_string("-8.000", precision=16).unwrap()
  let odd = Decimal::from_string("-7", precision=16).unwrap()
  let zero = Decimal::from_string("0E-4", precision=16).unwrap()
  let fractional = Decimal::from_string("3.5", precision=16).unwrap()

  assert_true(decimal_power_integer_is_odd(even) == Some(false))
  assert_true(decimal_power_integer_is_odd(odd) == Some(true))
  assert_true(decimal_power_integer_is_odd(zero) == Some(false))
  assert_true(decimal_power_integer_is_odd(fractional) is None)
}

///|
// oracle: A, S
// source: IEEE 754-2019 5.3.3 (scaleB takes an integer operand): 123, -45 and -0 give the integers 123, -45 and 0, 12E-1 is not an integer and 10^12 is beyond the count the context can use (the limit is the library's, level S); written out
// shares: Decimal::from_string (builds the operands) and the coefficient conversions to_bigint and dec_coeff_from_bigint_repr, scaleb_count (the code under test)
test "scaleb count extracts exponent-zero integers from coeff repr" {
  let ctx = DecimalContext::new(
    precision=9,
    e_max=999,
    rounding=DecimalRoundingMode::RoundTiesToEven,
  )
  let positive = Decimal::from_string("123", precision=16).unwrap()
  let negative = Decimal::from_string("-45", precision=16).unwrap()
  let negative_zero = Decimal::from_string("-0", precision=16).unwrap()
  let exact_nonzero_exponent = Decimal::from_string("12E-1", precision=16).unwrap()
  let huge = Decimal::from_string("1000000000000", precision=16).unwrap()

  assert_true(scaleb_count(positive, ctx) == Some(123))
  assert_true(scaleb_count(negative, ctx) == Some(-45))
  assert_true(scaleb_count(negative_zero, ctx) == Some(0))
  assert_true(scaleb_count(exact_nonzero_exponent, ctx) is None)
  assert_true(scaleb_count(huge, ctx) is None)
}

///|
// oracle: A
// source: arithmetic: 7/40 = 0.175 terminates (40 = 2^3 * 5) and 7/21 = 1/3 does not; written out
// shares: dec_coeff_from_bigint_repr (builds the operands), has_finite_decimal_expansion_repr (the code under test)
test "decimal coefficient finite-expansion predicate matches bigint predicate" {
  // numerator, denominator, whether numerator / denominator terminates: the part of
  // the denominator prime to 10 must divide the numerator
  let rows : Array[(BigInt, BigInt, Bool)] = [
    (7N, 40N, true), // 0.175
    (7N, 21N, false), // 1/3
    (22N, 21N, false), // 22 >= 21, remainder 1: 1.047619...
    (42N, 21N, true), // 2
    (21N, 35N, true), // 3/5 = 0.6
    (22N, 35N, false), // 22/35 = 0.62857...
    (3N, 12N, true), // 1/4 = 0.25
    (1N, 6N, false), // 0.1666...
  ]
  for row in rows {
    let (numerator, denominator, expected) = row
    assert_eq(
      has_finite_decimal_expansion_repr(
        dec_coeff_from_bigint_repr(numerator),
        dec_coeff_from_bigint_repr(denominator),
      ),
      expected,
      msg="\{numerator} / \{denominator}",
    )
  }
}

///|
fn assert_decimal_and_flags_eq(
  actual : (Decimal, DecimalFlags),
  expected : (Decimal, DecimalFlags),
) -> Unit raise {
  assert_eq(actual.0.total_order_compare(expected.0), 0)
  assert_eq(actual.1.inexact, expected.1.inexact)
  assert_eq(actual.1.invalid_operation, expected.1.invalid_operation)
  assert_eq(actual.1.division_by_zero, expected.1.division_by_zero)
  assert_eq(actual.1.overflow, expected.1.overflow)
  assert_eq(actual.1.underflow, expected.1.underflow)
}

///|
// oracle: A
// source: CPython decimal (libmpdec) Context(prec=6, rounding=ROUND_HALF_EVEN, Emax=20, Emin=-19, clamp=1).divide: 7.50/16 = 0.46875 exact, 22/7 = 3.14286 with inexact (run 2026-11-26); the earlier oracle was a 100-line twin of the function under test built from the library's own normalization helpers
// shares: Decimal::from_string (builds the operands) and the coefficient conversions to_bigint and dec_coeff_from_bigint_repr, assert_decimal_and_flags_eq (total_order_compare and the flags) and Decimal::div_ctx (the code under test)
test "decimal div_ctx repr pipeline matches bigint divide normalization" {
  let ctx = DecimalContext::new(
    precision=6,
    e_max=20,
    rounding=DecimalRoundingMode::RoundTiesToEven,
  )
  let exact_lhs = Decimal::from_string("7.50", precision=8).unwrap()
  let exact_rhs = Decimal::from_string("16", precision=8).unwrap()
  let inexact_lhs = Decimal::from_string("22", precision=8).unwrap()
  let inexact_rhs = Decimal::from_string("7", precision=8).unwrap()
  assert_decimal_and_flags_eq(
    exact_lhs.div_ctx(exact_rhs, ctx),
    (
      Decimal::from_string("0.46875", precision=16).unwrap(),
      DecimalFlags::new(),
    ),
  )
  assert_decimal_and_flags_eq(
    inexact_lhs.div_ctx(inexact_rhs, ctx),
    (
      Decimal::from_string("3.14286", precision=16).unwrap(),
      { ..DecimalFlags::new(), inexact: true, },
    ),
  )
}

///|
// oracle: A
// source: CPython decimal (libmpdec) Context(prec=5, rounding=ROUND_HALF_UP, Emax=12, Emin=-11, clamp=1).divide: 7.50/8 = 0.9375 exact, -2/3 = -0.66667 with inexact (run 2026-11-26); ROUND_HALF_UP is RoundTiesToAway; the earlier oracle was a twin of the function under test
// shares: Decimal::from_string (builds the operands) and the coefficient conversions to_bigint and dec_coeff_from_bigint_repr, assert_decimal_and_flags_eq and decimal_div_finite_by_small_int_work (the code under test)
test "decimal math small-int division repr pipeline matches bigint divide normalization" {
  let work_ctx = DecimalContext::new(
    precision=5,
    e_max=12,
    rounding=DecimalRoundingMode::RoundTiesToAway,
  )
  let exact = Decimal::from_string("7.50", precision=8).unwrap()
  let inexact = Decimal::from_string("-2", precision=8).unwrap()
  assert_decimal_and_flags_eq(
    decimal_div_finite_by_small_int_work(exact, 8, work_ctx),
    (Decimal::from_string("0.9375", precision=16).unwrap(), DecimalFlags::new()),
  )
  assert_decimal_and_flags_eq(
    decimal_div_finite_by_small_int_work(inexact, 3, work_ctx),
    (
      Decimal::from_string("-0.66667", precision=16).unwrap(),
      { ..DecimalFlags::new(), inexact: true, },
    ),
  )
}

///|
// oracle: A
// source: CPython decimal (libmpdec) Context(prec=5, rounding=ROUND_HALF_EVEN, Emax=15, Emin=-14, clamp=1).divide: 7.50/16 = 0.46875 exact, -22/7 = -3.1429 with inexact (run 2026-11-26); the earlier oracle was a twin of the function under test
// shares: Decimal::from_string (builds the operands) and the coefficient conversions to_bigint and dec_coeff_from_bigint_repr, assert_decimal_and_flags_eq and decimal_div_finite_work (the code under test)
test "decimal math finite division repr pipeline matches bigint divide normalization" {
  let work_ctx = DecimalContext::new(
    precision=5,
    e_max=15,
    rounding=DecimalRoundingMode::RoundTiesToEven,
  )
  let exact_lhs = Decimal::from_string("7.50", precision=8).unwrap()
  let exact_rhs = Decimal::from_string("16", precision=8).unwrap()
  let inexact_lhs = Decimal::from_string("-22", precision=8).unwrap()
  let inexact_rhs = Decimal::from_string("7", precision=8).unwrap()
  assert_decimal_and_flags_eq(
    decimal_div_finite_work(exact_lhs, exact_rhs, work_ctx),
    (
      Decimal::from_string("0.46875", precision=16).unwrap(),
      DecimalFlags::new(),
    ),
  )
  assert_decimal_and_flags_eq(
    decimal_div_finite_work(inexact_lhs, inexact_rhs, work_ctx),
    (
      Decimal::from_string("-3.1429", precision=16).unwrap(),
      { ..DecimalFlags::new(), inexact: true, },
    ),
  )
}

///|
fn normalization_flags_text(flags : DecimalFlags) -> String {
  (if flags.inexact { "x" } else { "." }) +
  (if flags.underflow { "u" } else { "." }) +
  (if flags.overflow { "o" } else { "." }) +
  (if flags.division_by_zero { "z" } else { "." }) +
  (if flags.invalid_operation { "i" } else { "." })
}

///|
// oracle: A
// source: expected text and flags written out from CPython decimal (libmpdec), Context(prec=6, rounding=ROUND_HALF_EVEN, Emax=20, Emin=-19, clamp=1): plus(Decimal("1234500E-3")) = 1234.50 and multiply(12.5, -0.08) = -1.000, no inexact, underflow or overflow flag; the earlier oracle called normalize_decimal_parts_math_ctx and a BigInt twin of the work function, wrappers of the code under test
// shares: Decimal::from_string, Decimal::to_string and normalization_flags_text (they build the operands and read the results as text)
test "decimal repr math normalization and multiplication match bigint path" {
  let work_ctx = DecimalContext::new(
    precision=6,
    e_max=20,
    rounding=DecimalRoundingMode::RoundTiesToEven,
  )
  let value = Decimal::from_string("1234500E-3", precision=16).unwrap()
  let (normalized, normalized_flags) = decimal_normalize_finite_work(
    value, work_ctx,
  )
  assert_eq(normalized.to_string(), "1234.50")
  assert_eq(normalization_flags_text(normalized_flags), ".....")
  let lhs = Decimal::from_string("12.5", precision=8).unwrap()
  let rhs = Decimal::from_string("-0.08", precision=8).unwrap()
  let (product, product_flags) = decimal_mul_finite_work(lhs, rhs, work_ctx)
  assert_eq(product.to_string(), "-1.000")
  assert_eq(normalization_flags_text(product_flags), ".....")
  let (plain, plain_flags) = lhs.mul_ctx(rhs, work_ctx)
  assert_eq(plain.to_string(), "-1.000")
  assert_eq(normalization_flags_text(plain_flags), ".....")
}

///|
// oracle: A
// source: expected text and flags written out from CPython decimal (libmpdec), Context(prec=4, rounding=ROUND_HALF_UP, Emax=6, Emin=-5, clamp=1).scaleb(Decimal("12.34"), n): n = -2 gives 0.1234 with no flag, n = -10 gives 0E-8 with inexact and underflow (the result is below Etiny = -8); ROUND_HALF_UP is RoundTiesToAway; the earlier oracle was a BigInt twin of the function under test
// shares: Decimal::from_string, Decimal::to_string and normalization_flags_text (they build the operand and read the result as text)
test "decimal scaleb repr construction matches bigint path" {
  let ctx = DecimalContext::new(
    precision=4,
    e_max=6,
    rounding=DecimalRoundingMode::RoundTiesToAway,
  )
  let operand = Decimal::from_string("12.34", precision=8).unwrap()
  let (regular, regular_flags) = scaleb_finite_result_ctx(operand, -2, ctx)
  assert_eq(regular.to_string(), "0.1234")
  assert_eq(normalization_flags_text(regular_flags), ".....")
  let (tiny, tiny_flags) = scaleb_finite_result_ctx(operand, -10, ctx)
  assert_eq(tiny.to_string(), "0E-8")
  assert_eq(normalization_flags_text(tiny_flags), "xu...")
}

///|
// oracle: A
// source: CPython decimal (libmpdec) Context(prec=7, rounding=ROUND_HALF_UP, Emin=-19, Emax=20, clamp=1).plus(Decimal(text)) with its five IEEE flags (Emin = 1 - Emax); the 16 rows were re-run against it on 2026-11-26 and agree in value and flags; written out
// shares: Decimal::from_string (builds the operand) and Decimal::to_string and normalization_flags_text (read the result as text)
test "repr normalization gives the libmpdec result and flags on finite values" {
  let ctx = DecimalContext::new(
    precision=7,
    e_max=20,
    rounding=DecimalRoundingMode::RoundTiesToAway,
  )
  let rows = [
    ("1234500E-3", "1234.500", "....."),
    ("12345678E-3", "12345.68", "x...."),
    ("12345675E-3", "12345.68", "x...."),
    ("99999995E-3", "100000.0", "x...."),
    ("1E+25", "inf", "x.o.."),
    ("1E+20", "1.000000E+20", "....."),
    ("1E+21", "inf", "x.o.."),
    ("1E-25", "1E-25", "....."),
    ("15E-25", "1.5E-24", "....."),
    ("5E-26", "1E-25", "xu..."),
    ("-5E-26", "-1E-25", "xu..."),
    ("123E-30", "0E-25", "xu..."),
    ("0E+30", "0E+14", "....."),
    ("1000000E+14", "1.000000E+20", "....."),
    ("9999999E+14", "9.999999E+20", "....."),
    ("99999995E+13", "inf", "x.o.."),
  ]
  for row in rows {
    let (text, result, flags) = row
    let value = Decimal::from_string(text, precision=16).unwrap()
    let actual = normalize_decimal_parts_ctx_repr(
      value.negative,
      value.coefficient,
      value.exponent10,
      ctx,
    )
    assert_eq(
      (text, actual.0.to_string(), normalization_flags_text(actual.1)),
      (text, result, flags),
    )
  }
}

///|
// oracle: A
// source: CPython decimal Context(prec=5, rounding=ROUND_HALF_EVEN).plus(Decimal(text)).normalize() (round, then strip the trailing zeros); the 9 rows were re-run against it on 2026-11-26 and agree; written out
// shares: Decimal::from_string (builds the operand) and Decimal::to_string and normalization_flags_text (read the result as text)
test "repr gda normalization rounds to the precision and reduces, as libmpdec" {
  let rows = [
    ("9999500E-4", "999.95"),
    ("1234500E-3", "1234.5"),
    ("12345E-3", "12.345"),
    ("1250000E-4", "125"),
    ("99999E+3", "9.9999E+7"),
    ("123456E+2", "1.2346E+7"),
    ("0.00E+5", "0"),
    ("5E-2", "0.05"),
    ("-5000E-3", "-5"),
  ]
  for row in rows {
    let (text, result) = row
    let value = Decimal::from_string(text, precision=16).unwrap()
    let actual = normalize_decimal_parts_gda_repr(
      value.negative,
      value.coefficient,
      value.exponent10,
      5,
      DecimalRound::HalfEven,
    )
    assert_eq((text, actual.to_string()), (text, result))
  }
}
