///|
// oracle: A
// source: arithmetic: 2^10 = 1024, 10^-2 = 0.01 and sqrt(3^2 + 4^2) = 5 are exact, so IEEE 754-2019 7.6 (inexact is signaled only when the rounded result differs from the exact one) leaves the inexact flag clear; the values are written out
// shares: Decimal::from_int, from_string and compare (they build the operands and compare the results, not the code under test)
test "Decimal elementary extensions preserve exact identities" {
  let context = DecimalContext::decimal64()
  let (power_two, power_two_flags) = Decimal::from_int(10).exp2_ctx(context)
  assert_eq(power_two.compare(Decimal::from_int(1024)), 0)
  assert_false(power_two_flags.inexact)
  let (power_ten, power_ten_flags) = Decimal::from_int(-2).exp10_ctx(context)
  assert_eq(power_ten.compare(Decimal::from_string("0.01").unwrap()), 0)
  assert_false(power_ten_flags.inexact)
  let (hypotenuse, hypot_flags) = Decimal::from_int(3).hypot_ctx(
    Decimal::from_int(4),
    context,
  )
  assert_eq(hypotenuse.compare(Decimal::from_int(5)), 0)
  assert_false(hypot_flags.inexact)
}

///|
// oracle: A
// source: IEEE 754-2019 9.2.1 (read from the PDF text): sinPi(-n) is -0, cosPi(n + 1/2) is +0, tanPi(2n + 1/2) is +infinity with divideByZero; sinPi(1/2) = 1 exactly; the values and flags are written out from that text
// shares: Decimal::from_int and from_string (they build the operands), is_negative_zero, is_zero and is_sign_minus (they read the result)
test "Decimal pi-scaled functions follow IEEE exact special values" {
  let context = DecimalContext::decimal64()
  let (negative_integer_sine, sine_flags) = Decimal::from_int(-1).sinpi_ctx(
    context,
  )
  assert_true(negative_integer_sine.is_negative_zero())
  assert_false(sine_flags.inexact)
  let half = Decimal::from_string("0.5").unwrap()
  let (half_sine, half_sine_flags) = half.sinpi_ctx(context)
  assert_eq(half_sine.compare(Decimal::one()), 0)
  assert_false(half_sine_flags.inexact)
  let (half_cosine, half_cosine_flags) = half.cospi_ctx(context)
  assert_true(half_cosine.is_zero())
  assert_false(half_cosine.is_negative_zero())
  assert_false(half_cosine_flags.inexact)
  let (half_tangent, half_tangent_flags) = half.tanpi_ctx(context)
  assert_true(half_tangent.is_infinite())
  assert_false(half_tangent.is_sign_minus())
  assert_true(half_tangent_flags.division_by_zero)
}

///|
// oracle: A
// source: IEEE 754-2019 9.2.1 (read from the PDF text) and Table 9.1: asin outside [-1, 1] is invalid operation and gives NaN; atan2(-0, +0) is -0 with no exception; written out from that text
// shares: Decimal::from_int, negative_zero and zero (they build the operands), is_nan and is_negative_zero (they read the result)
test "Decimal elementary domains and atan2 signed zeros are explicit" {
  let context = DecimalContext::decimal64()
  let (invalid, invalid_flags) = Decimal::from_int(2).asin_ctx(context)
  assert_true(invalid.is_nan())
  assert_true(invalid_flags.invalid_operation)
  let (negative_axis_zero, zero_flags) = Decimal::negative_zero().atan2_ctx(
    Decimal::zero(),
    context,
  )
  assert_true(negative_axis_zero.is_negative_zero())
  assert_false(zero_flags.has_error())
}

///|
// oracle: A
// source: arithmetic: 9^0.5 = 3 exactly (IEEE 754-2019 9.2 pow, exact result, inexact clear); the Ok shape of the Result is the documented API of try_pow_ctx
// shares: Decimal::from_int and from_string (they build the operands), compare (reads the result)
test "Decimal try power exposes certified evaluation as Result" {
  let context = DecimalContext::decimal64()
  match
    Decimal::from_int(9).try_pow_ctx(
      Decimal::from_string("0.5").unwrap(),
      context,
    ) {
    Ok((value, flags)) => {
      assert_eq(value.compare(Decimal::from_int(3)), 0)
      assert_false(flags.inexact)
    }
    Err(_) => assert_true(false)
  }
}

///|
// oracle: A
// source: CPython decimal at 7000 digits: atan(x) = x - x^3/3 + ... for x = 1E-3000 is 9.99...9E-3001 (34 nines) after rounding toward zero at 34 digits, since the series tail is below one unit at that precision; the value is written out
// shares: Decimal::from_string and to_string (they build the operand and print the result)
test "Decimal atan certifies tiny decimal128 arguments" {
  let context = DecimalContext::decimal128().with_rounding(
    DecimalRoundingMode::RoundTowardZero,
  )
  match Decimal::from_string("1E-3000").unwrap().try_atan_ctx(context) {
    Ok((value, flags)) => {
      assert_eq(value.to_string(), "9.999999999999999999999999999999999E-3001")
      assert_true(flags.inexact)
    }
    Err(_) => assert_true(false)
  }
}

///|
// oracle: A
// source: CPython decimal at 7000 digits: cos and cosh of 1E-3000 at 34 digits to nearest are 1.000...0, hypot(1, 1E-3000) rounded up is 1.000...001, atan2(1, 1E+3000) rounded toward zero is 9.99...9E-3001; the 14 families times five directions check only that the result is a number and inexact is raised (an exact result is impossible for a nonzero tiny argument, IEEE 754-2019 9.2); the values are written out
// shares: Decimal::from_string and to_string (they build the operands and print the results), DecimalContext::with_round and DecimalRound::from_arithmetic (they select the direction)
test "Decimal tiny elementary arguments certify all issue 170 families" {
  let positive = Decimal::from_string("1E-3000").unwrap()
  let negative = Decimal::from_string("-1E-3000").unwrap()
  let below = "9.999999999999999999999999999999999E-3001"
  let modes = [
    RoundingMode::ToNearestEven,
    RoundingMode::TowardZero,
    RoundingMode::TowardPositive,
    RoundingMode::TowardNegative,
    RoundingMode::AwayFromZero,
  ]
  for mode in modes {
    let context = DecimalContext::decimal128().with_round(
      DecimalRound::from_arithmetic(mode),
    )
    for
      (_value, _correction_below, actual) in [
        (positive, true, positive.try_atan_ctx(context)),
        (positive, true, positive.try_sin_ctx(context)),
        (positive, false, positive.try_tan_ctx(context)),
        (positive, false, positive.try_sinh_ctx(context)),
        (positive, true, positive.try_tanh_ctx(context)),
        (positive, true, positive.try_asinh_ctx(context)),
        (positive, false, positive.try_atanh_ctx(context)),
        (negative, false, negative.try_atan_ctx(context)),
        (negative, false, negative.try_sin_ctx(context)),
        (negative, true, negative.try_tan_ctx(context)),
        (negative, true, negative.try_sinh_ctx(context)),
        (negative, false, negative.try_tanh_ctx(context)),
        (negative, false, negative.try_asinh_ctx(context)),
        (negative, true, negative.try_atanh_ctx(context)),
      ] {
      match actual {
        Ok((result, flags)) => {
          assert_true(!result.is_nan())
          assert_true(flags.inexact)
        }
        Err(_) => assert_true(false)
      }
    }
    for
      actual in [positive.try_asin_ctx(context), negative.try_asin_ctx(context)] {
      match actual {
        Ok((result, flags)) => {
          assert_true(!result.is_nan())
          assert_true(flags.inexact)
        }
        Err(_) => assert_true(false)
      }
    }
  }

  let nearest = DecimalContext::decimal128()
  let (cosine, cosine_flags) = positive.cos_ctx(nearest)
  let (hyperbolic_cosine, hyperbolic_cosine_flags) = positive.cosh_ctx(nearest)
  assert_eq(cosine.to_string(), "1.000000000000000000000000000000000")
  assert_eq(
    hyperbolic_cosine.to_string(),
    "1.000000000000000000000000000000000",
  )
  assert_true(cosine_flags.inexact)
  assert_true(hyperbolic_cosine_flags.inexact)

  let ceiling = nearest.with_rounding(DecimalRoundingMode::RoundTowardPositive)
  let (hypotenuse, hypot_flags) = Decimal::one().hypot_ctx(positive, ceiling)
  assert_eq(hypotenuse.to_string(), "1.000000000000000000000000000000001")
  assert_true(hypot_flags.inexact)

  let abscissa = Decimal::from_string("1E+3000").unwrap()
  let toward_zero = nearest.with_rounding(DecimalRoundingMode::RoundTowardZero)
  let (angle, angle_flags) = Decimal::one().atan2_ctx(abscissa, toward_zero)
  assert_eq(angle.to_string(), below)
  assert_true(angle_flags.inexact)
}

///|
// oracle: A
// source: arithmetic: 4^0.5 = 2 exactly, so no inexact (IEEE 754-2019 9.2, 7.6); the value is written out
// shares: Decimal::from_int and from_string (they build the operands), to_string
test "Decimal noninteger power preserves IEEE exact result semantics" {
  let ieee_context = DecimalContext::new(
    precision=9,
    e_max=999_999,
    rounding=DecimalRoundingMode::RoundTiesToEven,
  )
  let base = Decimal::from_int(4, precision=32)
  let exponent = Decimal::from_string("0.5", precision=32).unwrap()
  let (ieee_value, ieee_flags) = base.pow_ctx(exponent, ieee_context)
  assert_eq(ieee_value.to_string(), "2")
  assert_false(ieee_flags.inexact)
}

///|
// oracle: A
// source: CPython decimal: e = 2.718281828459045..., so exp(1) at nine digits is 2.71828182 toward negative and 2.71828183 toward positive, inexact (IEEE 754-2019 4.3, 7.6)
// shares: DecimalContext::new and Decimal::one (they build the operands), compare
test "Decimal elementary extensions honor context rounding" {
  let floor_context = DecimalContext::new(
    precision=9,
    e_max=999,
    rounding=DecimalRoundingMode::RoundTowardNegative,
  )
  let ceiling_context = DecimalContext::new(
    precision=9,
    e_max=999,
    rounding=DecimalRoundingMode::RoundTowardPositive,
  )
  let floor_result = Decimal::one().exp_ctx(floor_context)
  let ceiling_result = Decimal::one().exp_ctx(ceiling_context)
  assert_true(floor_result.0.compare(ceiling_result.0) < 0)
  assert_eq(floor_result.0.to_string(), "2.71828182")
  assert_eq(ceiling_result.0.to_string(), "2.71828183")
  assert_true(floor_result.1.inexact)
  assert_true(ceiling_result.1.inexact)
}

///|
/// IEEE 754-2019 §9.2 requires correctly rounded finite `tanh` and `expm1`
/// results, including when their exact values lie arbitrarily close to ±1.
// oracle: A
// source: CPython decimal: tanh(5000) = 1 - 2e^-10000 to 5000 digits, rounded at 16 digits in the eight directions: 1.000000000000000 or 0.9999999999999999 as the test lists, mirrored for -5000; expm1(-20000) is -(1 - 1E-8686) and rounds the same way; the flags are inexact only (IEEE 754-2019 9.2, 7.6)
// shares: DecimalContext::new, with_round and Decimal::from_int (they build the operands), to_string
test "Decimal tanh and expm1 certify saturated finite results" {
  let modes = [
    DecimalRound::HalfEven,
    DecimalRound::HalfUp,
    DecimalRound::HalfDown,
    DecimalRound::Down,
    DecimalRound::Floor,
    DecimalRound::Ceiling,
    DecimalRound::Up,
    DecimalRound::ZeroFiveUp,
  ]
  for mode in modes {
    let context = DecimalContext::new(precision=16, e_max=384).with_round(mode)

    let (positive, positive_flags) = Decimal::from_int(5000).tanh_ctx(context)
    let (negative, negative_flags) = Decimal::from_int(-5000).tanh_ctx(context)
    let (expm1_negative, expm1_flags) = Decimal::from_int(-20000).expm1_ctx(
      context,
    )
    let positive_expected = match mode {
      Down | Floor | ZeroFiveUp => "0.9999999999999999"
      _ => "1.000000000000000"
    }
    let negative_expected = match mode {
      Down | Ceiling | ZeroFiveUp => "-0.9999999999999999"
      _ => "-1.000000000000000"
    }
    let expected_flags = { ..DecimalFlags::new(), inexact: true, }
    assert_eq(positive.to_string(), positive_expected)
    assert_eq(negative.to_string(), negative_expected)
    assert_eq(expm1_negative.to_string(), negative_expected)
    assert_true(positive_flags == expected_flags)
    assert_true(negative_flags == expected_flags)
    assert_true(expm1_flags == expected_flags)
  }
  for mode in modes {
    match
      Decimal::from_int(-20000).try_expm1_ctx(
        DecimalContext::new(precision=16, e_max=384).with_round(mode),
      ) {
      Ok((value, flags)) => {
        let expected = match mode {
          Down | Ceiling | ZeroFiveUp => "-0.9999999999999999"
          _ => "-1.000000000000000"
        }
        assert_eq(value.to_string(), expected)
        assert_true(flags == { ..DecimalFlags::new(), inexact: true, })
      }
      Err(_) => assert_true(false)
    }
  }
}

///|
// oracle: A, S
// source: the values at each threshold are written out from the rounding of 1 - tiny (CPython decimal plus on the exact value, flags inexact and, for e_max 1, underflow before rounding by 7.5); the threshold 6 * precision is the library's own choice of when to skip the evaluation (design, level S)
// shares: DecimalContext::new and Decimal::from_int (they build the operands), compare and to_string
test "Decimal saturation shortcut covers thresholds and narrow contexts" {
  for precision in [1, 2, 7, 16, 34] {
    let context = DecimalContext::new(precision~, e_max=precision + 4)
    for input in [6 * precision - 1, 6 * precision] {
      let (positive, positive_flags) = Decimal::from_int(input).tanh_ctx(
        context,
      )
      let (negative, negative_flags) = Decimal::from_int(-input).tanh_ctx(
        context,
      )
      let (expm1, expm1_flags) = Decimal::from_int(-input).expm1_ctx(context)
      assert_eq(positive.compare(Decimal::one(precision~)), 0)
      assert_eq(negative.compare(Decimal::from_int(-1, precision~)), 0)
      assert_eq(expm1.compare(Decimal::from_int(-1, precision~)), 0)
      assert_true(positive_flags.inexact)
      assert_true(negative_flags.inexact)
      assert_true(expm1_flags.inexact)
    }
  }
  let before_rounding = DecimalContext::new(precision=7, e_max=1)
  let (below_threshold, below_flags) = Decimal::from_int(20).tanh_ctx(
    before_rounding,
  )
  let (at_threshold, at_flags) = Decimal::from_int(42).tanh_ctx(before_rounding)
  assert_eq(below_threshold.to_string(), "1.000000")
  assert_eq(at_threshold.to_string(), "1.000000")
  assert_true(below_flags.underflow)
  assert_true(at_flags.underflow)
  assert_true(below_flags == at_flags)

  // expm1(-20000) = -(1 - 10^-8686) is below 10^e_min = 1 before rounding but
  // rounds to -1 at seven digits. IEEE 754-2019 §7.5 detects tininess before
  // rounding for decimal formats.
  let zero_emin = DecimalContext::new(precision=7, e_max=1)
  let (subnormal_limit, subnormal_flags) = Decimal::from_int(-20000).expm1_ctx(
    zero_emin,
  )
  assert_false(subnormal_limit.is_nan())
  assert_true(subnormal_flags.inexact)
  assert_true(subnormal_flags.underflow)
  let negative_emin = DecimalContext::new(precision=7, e_max=2)
  let (unit_subnormal, unit_subnormal_flags) = Decimal::from_int(-20000).expm1_ctx(
    negative_emin,
  )
  assert_false(unit_subnormal.is_nan())
  assert_true(unit_subnormal_flags.inexact)
  assert_false(unit_subnormal_flags.underflow)

  let negative_emax = DecimalContext::new(
    precision=7,
    e_max=11,
    rounding=DecimalRoundingMode::RoundTowardZero,
  )
  let (overflow_edge, overflow_flags) = Decimal::from_int(-20000).expm1_ctx(
    negative_emax,
  )
  assert_eq(overflow_edge.to_string(), "-0.9999999")
  assert_true(overflow_flags.inexact)

  let one_digit = DecimalContext::new(precision=1, e_max=1).with_round(
    DecimalRound::ZeroFiveUp,
  )
  let (zero_five_up, zero_five_up_flags) = Decimal::from_int(6).tanh_ctx(
    one_digit,
  )
  assert_eq(zero_five_up.to_string(), "1")
  assert_true(
    zero_five_up_flags ==
    { ..DecimalFlags::new(), inexact: true, underflow: true, },
  )

  let huge = Decimal::from_string("1E+10").unwrap()
  let (huge_tanh, huge_flags) = huge.tanh_ctx(DecimalContext::decimal64())
  let (huge_negative_tanh, huge_negative_flags) = huge
    .neg()
    .tanh_ctx(DecimalContext::decimal64())
  assert_eq(huge_tanh.to_string(), "1.000000000000000")
  assert_eq(huge_negative_tanh.to_string(), "-1.000000000000000")
  assert_true(huge_flags.inexact)
  assert_true(huge_negative_flags.inexact)
}

///|
// oracle: A
// source: CPython decimal plus on exp(-1E8) = 6.4517E-43429449 (computed at 60 digits) in the eight directions at precision 7, e_max 384: 1E-389 for Ceiling, Up and ZeroFiveUp, zero for the other five, flags underflow and inexact; CPython's own exp does not apply the directed modes there, so the plus form is used
// shares: DecimalContext::new, with_round and Decimal::from_int (they build the operands), to_string
test "Decimal extreme exp avoids unbounded dyadic endpoint expansion" {
  let input = Decimal::from_int(-100_000_000, precision=16)
  for
    mode in [
      DecimalRound::HalfEven,
      DecimalRound::HalfUp,
      DecimalRound::HalfDown,
      DecimalRound::Down,
      DecimalRound::Floor,
      DecimalRound::Ceiling,
      DecimalRound::Up,
      DecimalRound::ZeroFiveUp,
    ] {
    let context = DecimalContext::new(precision=7, e_max=384).with_round(mode)
    let (value, flags) = input.exp_ctx(context)
    match mode {
      Ceiling | Up | ZeroFiveUp => assert_eq(value.to_string(), "1E-389")
      Down | Floor | HalfEven | HalfUp | HalfDown =>
        assert_true(value.is_zero())
    }
    assert_true(flags.inexact)
    assert_true(flags.underflow)
  }
}

///|
// oracle: A
// source: CPython decimal plus on exp(-1000) (1E-435) at precision 1, Emin -2, rounding Up: 0.01 with Underflow, Inexact, Subnormal; IEEE 754-2019 7.5 detects tininess before rounding for decimal formats
// shares: Decimal::from_int and DecimalContext::new (they build the operands), to_string
test "Decimal extreme exp detects tininess before rounding" {
  let input = Decimal::from_int(-1000, precision=16)
  let before = DecimalContext::new(precision=1, e_max=3).with_round(
    DecimalRound::Up,
  )
  let (before_value, before_flags) = input.exp_ctx(before)
  assert_eq(before_value.to_string(), "0.01")
  assert_true(before_flags.inexact)
  // IEEE 754-2019 7.5: before rounding, the exact result 1E-435 is below
  // 10^e_min = 0.01, so the result is tiny although the bounded result is
  // 10^e_min (#333).
  assert_true(before_flags.underflow)
}
