///|
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
  assert_false(half_tangent.is_negative())
  assert_true(half_tangent_flags.division_by_zero)
}

///|
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
test "Decimal atan certifies tiny decimal128 arguments" {
  let context = DecimalContext::decimal128().with_rounding(
    DecimalRoundingMode::RoundTowardZero,
  )
  match Decimal::from_string("1E-3000").unwrap().try_atan_ctx(context) {
    Ok((value, flags)) => {
      assert_eq(value.to_string(), "9.999999999999999999999999999999999E-3001")
      assert_true(flags.inexact && flags.rounded)
    }
    Err(_) => assert_true(false)
  }
}

///|
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
          assert_true(flags.inexact && flags.rounded)
        }
        Err(_) => assert_true(false)
      }
    }
    for
      actual in [positive.try_asin_ctx(context), negative.try_asin_ctx(context)] {
      match actual {
        Ok((result, flags)) => {
          assert_true(!result.is_nan())
          assert_true(flags.inexact && flags.rounded)
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
  assert_true(cosine_flags.inexact && cosine_flags.rounded)
  assert_true(
    hyperbolic_cosine_flags.inexact && hyperbolic_cosine_flags.rounded,
  )

  let ceiling = nearest.with_rounding(DecimalRoundingMode::RoundTowardPositive)
  let (hypotenuse, hypot_flags) = Decimal::one().hypot_ctx(positive, ceiling)
  assert_eq(hypotenuse.to_string(), "1.000000000000000000000000000000001")
  assert_true(hypot_flags.inexact && hypot_flags.rounded)

  let abscissa = Decimal::from_string("1E+3000").unwrap()
  let toward_zero = nearest.with_rounding(DecimalRoundingMode::RoundTowardZero)
  let (angle, angle_flags) = Decimal::one().atan2_ctx(abscissa, toward_zero)
  assert_eq(angle.to_string(), below)
  assert_true(angle_flags.inexact && angle_flags.rounded)
}

///|
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
  assert_false(ieee_flags.rounded)
  assert_false(ieee_flags.inexact)
}

///|
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
  assert_true(floor_result.1.inexact)
  assert_true(ceiling_result.1.inexact)
}

///|
/// IEEE 754-2019 §9.2 requires correctly rounded finite `tanh` and `expm1`
/// results, including when their exact values lie arbitrarily close to ±1.
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
    let expected_flags = {
      ..DecimalFlags::new(),
      rounded: true,
      inexact: true,
    }
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
        assert_true(
          flags == { ..DecimalFlags::new(), rounded: true, inexact: true, },
        )
      }
      Err(_) => assert_true(false)
    }
  }
}

///|
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
      assert_true(positive_flags.inexact && positive_flags.rounded)
      assert_true(negative_flags.inexact && negative_flags.rounded)
      assert_true(expm1_flags.inexact && expm1_flags.rounded)
    }
  }
  let before_rounding = DecimalContext::new(precision=7, e_max=1)
  let (below_threshold, below_flags) = Decimal::from_int(20).tanh_ctx(
    before_rounding,
  )
  let (at_threshold, at_flags) = Decimal::from_int(42).tanh_ctx(before_rounding)
  assert_eq(below_threshold.to_string(), "1.000000")
  assert_eq(at_threshold.to_string(), "1.000000")
  assert_true(below_flags.underflow && below_flags.subnormal)
  assert_true(at_flags.underflow && at_flags.subnormal)
  assert_true(below_flags == at_flags)

  // expm1(-20000) = -(1 - 10^-8686) is below 10^e_min = 1 before rounding but
  // rounds to -1 at seven digits. IEEE 754-2019 §7.5 detects tininess before
  // rounding for decimal formats.
  let zero_emin = DecimalContext::new(precision=7, e_max=1)
  let (subnormal_limit, subnormal_flags) = Decimal::from_int(-20000).expm1_ctx(
    zero_emin,
  )
  assert_false(subnormal_limit.is_nan())
  assert_true(subnormal_flags.inexact && subnormal_flags.rounded)
  assert_true(subnormal_flags.underflow && subnormal_flags.subnormal)
  let negative_emin = DecimalContext::new(precision=7, e_max=2)
  let (unit_subnormal, unit_subnormal_flags) = Decimal::from_int(-20000).expm1_ctx(
    negative_emin,
  )
  assert_false(unit_subnormal.is_nan())
  assert_true(unit_subnormal_flags.inexact && unit_subnormal_flags.rounded)
  assert_false(unit_subnormal_flags.underflow || unit_subnormal_flags.subnormal)

  let negative_emax = DecimalContext::new(
    precision=7,
    e_max=11,
    rounding=DecimalRoundingMode::RoundTowardZero,
  )
  let (overflow_edge, overflow_flags) = Decimal::from_int(-20000).expm1_ctx(
    negative_emax,
  )
  assert_eq(overflow_edge.to_string(), "-0.9999999")
  assert_true(overflow_flags.inexact && overflow_flags.rounded)

  let one_digit = DecimalContext::new(precision=1, e_max=1).with_round(
    DecimalRound::ZeroFiveUp,
  )
  let (zero_five_up, zero_five_up_flags) = Decimal::from_int(6).tanh_ctx(
    one_digit,
  )
  assert_eq(zero_five_up.to_string(), "1")
  assert_true(
    zero_five_up_flags ==
    {
      ..DecimalFlags::new(),
      rounded: true,
      inexact: true,
      underflow: true,
      subnormal: true,
    },
  )

  let huge = Decimal::from_string("1E+10").unwrap()
  let (huge_tanh, huge_flags) = huge.tanh_ctx(DecimalContext::decimal64())
  let (huge_negative_tanh, huge_negative_flags) = huge
    .neg()
    .tanh_ctx(DecimalContext::decimal64())
  assert_eq(huge_tanh.to_string(), "1.000000000000000")
  assert_eq(huge_negative_tanh.to_string(), "-1.000000000000000")
  assert_true(huge_flags.inexact && huge_flags.rounded)
  assert_true(huge_negative_flags.inexact && huge_negative_flags.rounded)
}

///|
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
      Ceiling | Up | ZeroFiveUp => {
        assert_eq(value.to_string(), "1E-389")
        assert_false(flags.clamped)
      }
      Down | Floor | HalfEven | HalfUp | HalfDown => {
        assert_true(value.is_zero())
        assert_true(flags.clamped)
      }
    }
    assert_true(flags.rounded)
    assert_true(flags.inexact)
    assert_true(flags.underflow)
    assert_true(flags.subnormal)
  }
}

///|
test "Decimal extreme exp detects tininess before rounding" {
  let input = Decimal::from_int(-1000, precision=16)
  let before = DecimalContext::new(precision=1, e_max=3).with_round(
    DecimalRound::Up,
  )
  let (before_value, before_flags) = input.exp_ctx(before)
  assert_eq(before_value.to_string(), "0.01")
  assert_true(before_flags.rounded && before_flags.inexact)
  // IEEE 754-2019 7.5: before rounding, the exact result 1E-435 is below
  // 10^e_min = 0.01, so the result is tiny although the bounded result is
  // 10^e_min (#333).
  assert_true(before_flags.underflow)
  assert_true(before_flags.subnormal)
}
