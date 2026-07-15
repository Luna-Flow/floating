///|
test "BinFloat certified exp and ln special values" {
  let context = BinaryContext::binary64()
  let (exp_zero, _) = BinFloat::zero().exp_ctx(context)
  assert_eq(exp_zero, BinFloat::one())
  let (ln_one, _) = BinFloat::one().ln_ctx(context)
  assert_eq(ln_one, BinFloat::zero())
  let (ln_negative, flags) = BinFloat::from_int(-1).ln_ctx(context)
  assert_true(ln_negative.is_quiet_nan())
  assert_true(flags.invalid_operation())
}

///|
test "BinFloat certified exp and ln round-trip small values" {
  let value = BinFloat::from_double(0.0625, precision=53)
  let round_trip = value.exp().ln()
  let difference = round_trip.sub(value).abs()
  assert_true(difference <= BinFloat::make(BinCoeff::one(), -52, 53))
}

///|
test "BinFloat certified exp range reduction handles ordinary inputs" {
  let result = BinFloat::from_int(1).exp()
  assert_true(result.classify() == FpClass::Finite)
  assert_true(result > BinFloat::from_int(2))
  assert_true(result < BinFloat::from_int(3))
  let reciprocal = BinFloat::from_int(-1).exp()
  assert_true(reciprocal > BinFloat::zero())
  assert_true(reciprocal < BinFloat::one())
}

///|
test "BinFloat certified exp10 handles ordinary inputs" {
  let result = BinFloat::from_int(1).exp10()
  assert_true(result.classify() == FpClass::Finite)
  assert_true(result > BinFloat::from_int(9))
  assert_true(result < BinFloat::from_int(11))
}

///|
test "BinFloat exact elementary identities preserve exact flags" {
  let context = BinaryContext::binary64()
  for exponent in [-4, -1, 0, 1, 4] {
    let input = BinFloat::from_int(exponent, precision=53)
    let (result, flags) = input.exp2_ctx(context)
    assert_true(
      result.compare(BinFloat::make(BinCoeff::one(), exponent, 1)) == 0,
    )
    assert_true(!flags.inexact())
  }
  let (hundred, hundred_flags) = BinFloat::from_int(2).exp10_ctx(context)
  assert_eq(hundred, BinFloat::from_int(100))
  assert_true(!hundred_flags.inexact())
  let (binary_logarithm, binary_flags) = BinFloat::make(BinCoeff::one(), 9, 53).log2_ctx(
    context,
  )
  assert_eq(binary_logarithm, BinFloat::from_int(9))
  assert_true(!binary_flags.inexact())
  let (decimal_logarithm, decimal_flags) = BinFloat::from_int(1000).log10_ctx(
    context,
  )
  assert_eq(decimal_logarithm, BinFloat::from_int(3))
  assert_true(!decimal_flags.inexact())
  let (cube_root, cube_root_flags) = BinFloat::make(
    BinCoeff::from_uint64(27UL),
    -3,
    53,
  ).rootn_ctx(3, context)
  assert_eq(cube_root, BinFloat::make(BinCoeff::from_uint64(3UL), -1, 53))
  assert_true(!cube_root_flags.inexact())
  let exact_square = BinFloat::make(BinCoeff::from_uint64(441UL), -8, 53)
  let half = BinFloat::make(BinCoeff::one(), -1, 53)
  let (power_root, power_root_flags) = exact_square.pow_ctx(half, context)
  assert_eq(power_root, BinFloat::make(BinCoeff::from_uint64(21UL), -4, 53))
  assert_true(!power_root_flags.inexact())
}

///|
test "BinFloat certified logarithm range reduction handles ordinary inputs" {
  let natural = BinFloat::from_int(8).ln()
  assert_true(natural > BinFloat::from_int(2))
  assert_true(natural < BinFloat::from_int(3))
  let decimal = BinFloat::from_int(10).log10()
  assert_eq(decimal, BinFloat::one())
}

///|
test "BinFloat hypot rounds the exact sum of squares" {
  let result = BinFloat::from_int(3).hypot(BinFloat::from_int(4))
  assert_eq(result, BinFloat::from_int(5))
  assert_eq(
    BinFloat::inf(Sign::Negative).hypot(BinFloat::zero()),
    BinFloat::inf(Sign::Positive),
  )
}

///|
test "BinFloat pown preserves the standard integer-power semantics" {
  assert_eq(BinFloat::from_int(2).pown(10).unwrap(), BinFloat::from_int(1024))
}

///|
test "BinFloat logarithms preserve IEEE zero and domain flags" {
  let context = BinaryContext::binary64()
  let (zero_log, zero_flags) = BinFloat::zero().ln_ctx(context)
  assert_true(zero_log.classify() == FpClass::Infinity)
  assert_true(zero_log.sign() == Sign::Negative)
  assert_true(zero_flags.division_by_zero())
  let (negative_log, negative_flags) = BinFloat::from_int(-1).log10_ctx(context)
  assert_true(negative_log.is_quiet_nan())
  assert_true(negative_flags.invalid_operation())
}

///|
test "BinFloat rootn uses certified logarithm and exponential bounds" {
  let result = BinFloat::from_int(8).rootn(3)
  assert_eq(result, BinFloat::from_int(2))
  let negative = BinFloat::from_int(-8).rootn(3)
  assert_eq(negative, BinFloat::from_int(-2))
  assert_eq(
    BinFloat::from_int(2).rootn(-1),
    BinFloat::make(BinCoeff::one(), -1, 53),
  )
  let even_domain = BinFloat::from_int(-8).try_rootn_ctx(
    2,
    BinaryContext::binary64(),
  )
  match even_domain {
    Ok(_) => assert_true(false)
    Err(error) => assert_true(error.is_domain_error())
  }
}

///|
test "BinFloat pow separates integer and positive non-integer domains" {
  assert_eq(
    BinFloat::from_int(-2).pow(BinFloat::from_int(3)),
    BinFloat::from_int(-8),
  )
  let square_root = BinFloat::from_int(9).pow(
    BinFloat::make(BinCoeff::one(), -1, 53),
  )
  assert_eq(square_root, BinFloat::from_int(3))
  let invalid = BinFloat::from_int(-2).try_pow_ctx(
    BinFloat::make(BinCoeff::one(), -1, 53),
    BinaryContext::binary64(),
  )
  match invalid {
    Ok(_) => assert_true(false)
    Err(error) => assert_true(error.is_domain_error())
  }
}

///|
test "BinFloat certified hyperbolic functions preserve identities" {
  let zero = BinFloat::zero()
  assert_eq(zero.sinh(), zero)
  assert_eq(zero.cosh(), BinFloat::one())
  assert_eq(zero.tanh(), zero)
  let one = BinFloat::one()
  assert_eq(one.sinh().neg(), one.neg().sinh())
  assert_eq(one.cosh(), one.neg().cosh())
  assert_true(one.tanh() > zero)
  assert_true(one.tanh() < one)
}

///|
test "BinFloat inverse hyperbolic functions preserve domains and identities" {
  let zero = BinFloat::zero()
  assert_eq(zero.asinh(), zero)
  assert_eq(zero.atanh(), zero)
  assert_eq(BinFloat::one().acosh(), zero)
  let one = BinFloat::one()
  assert_eq(one.asinh().neg(), one.neg().asinh())
  let invalid = BinFloat::zero().try_acosh_ctx(BinaryContext::binary64())
  match invalid {
    Ok(_) => assert_true(false)
    Err(error) => assert_true(error.is_domain_error())
  }
  let (pole, flags) = one.atanh_ctx(BinaryContext::binary64())
  assert_true(pole.classify() == FpClass::Infinity)
  assert_true(flags.division_by_zero())
}

///|
test "BinFloat certified atan preserves origin and odd symmetry" {
  let zero = BinFloat::zero()
  assert_eq(zero.atan(), zero)
  let one = BinFloat::one()
  let positive = one.atan()
  assert_true(positive > BinFloat::make(BinCoeff::one(), -1, 53))
  assert_true(positive < one)
  assert_eq(positive.neg(), one.neg().atan())
}

///|
test "BinFloat inverse trigonometric functions preserve domains" {
  let zero = BinFloat::zero()
  let one = BinFloat::one()
  assert_eq(zero.asin(), zero)
  assert_eq(one.acos(), zero)
  let negative_one_acos = one.neg().acos()
  assert_true(negative_one_acos > BinFloat::from_int(3))
  assert_true(negative_one_acos < BinFloat::from_int(4))
  assert_eq(one.asin().neg(), one.neg().asin())
  let invalid = BinFloat::from_int(2).try_asin_ctx(BinaryContext::binary64())
  match invalid {
    Ok(_) => assert_true(false)
    Err(error) => assert_true(error.is_domain_error())
  }
}

///|
test "BinFloat inverse trigonometric half-angle reduction reaches its certified series domain" {
  let context = BinaryContext::binary32()
  let small_negative = BinFloat::make(
    BinCoeff::from_uint64(17UL),
    -8,
    53,
    negative=true,
  )
  assert_true(small_negative.try_asin_ctx(context) is Ok(_))
  assert_true(BinFloat::from_int(4).try_atan_ctx(context) is Ok(_))
  assert_true(
    BinFloat::from_int(4).try_atan2_ctx(BinFloat::one(), context) is Ok(_),
  )
}

///|
test "BinFloat atan2 preserves axes and quadrants" {
  let zero = BinFloat::zero()
  let one = BinFloat::one()
  assert_eq(zero.atan2(one), zero)
  assert_true(one.atan2(zero) > one)
  assert_true(one.atan2(one) > zero)
  assert_true(one.atan2(one.neg()) > one)
  assert_true(one.neg().atan2(one.neg()) < one.neg())
}

///|
test "BinFloat trigonometric functions preserve axis identities" {
  let zero = BinFloat::zero()
  assert_eq(zero.sin(), zero)
  assert_eq(zero.cos(), BinFloat::one())
  assert_eq(zero.tan(), zero)
  let one = BinFloat::one()
  assert_true(one.sin() > BinFloat::make(BinCoeff::from_uint64(3UL), -2, 53))
  assert_true(one.sin() < one)
  assert_true(one.cos() > BinFloat::make(BinCoeff::from_uint64(1UL), -1, 53))
  assert_true(one.cos() < one)
  assert_true(one.tan() > BinFloat::from_int(1))
}

///|
test "BinFloat pi-scaled functions preserve exact integer and half-integer identities" {
  let one = BinFloat::one()
  let half = BinFloat::make(BinCoeff::one(), -1, 53)
  assert_eq(one.sinpi(), BinFloat::zero())
  assert_eq(one.cospi(), one.neg())
  assert_eq(one.tanpi(), BinFloat::zero())
  assert_eq(half.sinpi(), one)
  assert_eq(half.cospi(), BinFloat::zero())
  let negative_half = half.neg()
  assert_eq(negative_half.sinpi(), one.neg())
  assert_eq(negative_half.tanpi(), BinFloat::inf(Sign::Negative))
  assert_true(BinFloat::from_int(-1).sinpi().is_negative_zero())
  let huge_integer = BinFloat::make(BinCoeff::one(), 40, 53)
  assert_true(huge_integer.sinpi().is_zero())
  assert_eq(huge_integer.cospi(), BinFloat::one())
  assert_true(huge_integer.tanpi().is_zero())
}

///|
test "BinFloat pi-scaled quarter is certified across release precisions" {
  for precision in [53, 128, 512] {
    let quarter = BinFloat::from_double(0.25, precision~)
    let context = BinaryContext::unbounded(precision)
    assert_true(
      quarter.try_sinpi_ctx(context) is Ok(_),
      msg="sinpi quarter at " + precision.to_string() + " bits",
    )
    assert_true(
      quarter.try_cospi_ctx(context) is Ok(_),
      msg="cospi quarter at " + precision.to_string() + " bits",
    )
    assert_true(
      quarter.try_tanpi_ctx(context) is Ok(_),
      msg="tanpi quarter at " + precision.to_string() + " bits",
    )
    let (positive_tangent, positive_flags) = quarter.tanpi_ctx(context)
    assert_eq(positive_tangent, BinFloat::one(precision~))
    assert_true(!positive_flags.inexact())
    let (negative_tangent, negative_flags) = quarter.neg().tanpi_ctx(context)
    assert_eq(negative_tangent, BinFloat::one(precision~).neg())
    assert_true(!negative_flags.inexact())
  }
}

///|
test "BinFloat pi-scaled exact quadrant reduction covers every quarter boundary" {
  let context = BinaryContext::binary64()
  let quarter = BinFloat::make(BinCoeff::one(), -2, 53)
  let half = BinFloat::make(BinCoeff::one(), -1, 53)
  for offset in -8..<=8 {
    let value = BinFloat::from_int(offset, precision=53).mul(quarter)
    assert_true(value.try_sinpi_ctx(context) is Ok(_))
    assert_true(value.try_cospi_ctx(context) is Ok(_))
    if offset % 2 != 0 || offset % 4 == 0 {
      assert_true(value.try_tanpi_ctx(context) is Ok(_))
    }
  }
  assert_eq(quarter.tanpi_ctx(context).0, BinFloat::one())
  assert_eq(quarter.add(half).tanpi_ctx(context).0, BinFloat::one().neg())
}

///|
test "BinFloat pi-scaled quarter honors every rounding mode" {
  let quarter = BinFloat::make(BinCoeff::one(), -2, 53)
  let modes = [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
    BinaryRoundingMode::RoundAwayFromZero,
  ]
  let sines : Array[BinFloat] = []
  for mode in modes {
    let context = BinaryContext::unbounded(24, rounding=mode)
    let (sine, sine_flags) = quarter.sinpi_ctx(context)
    let (cosine, cosine_flags) = quarter.cospi_ctx(context)
    let (tangent, tangent_flags) = quarter.tanpi_ctx(context)
    assert_eq(sine, cosine)
    assert_true(sine_flags.inexact())
    assert_true(cosine_flags.inexact())
    assert_eq(tangent, BinFloat::one(precision=24))
    assert_true(!tangent_flags.inexact())
    sines.push(sine)
  }
  assert_eq(sines[2], sines[4])
  assert_eq(sines[3], sines[5])
  assert_true(sines[4].compare(sines[0]) <= 0)
  assert_true(sines[0].compare(sines[3]) <= 0)
  assert_true(sines[4].compare(sines[1]) <= 0)
  assert_true(sines[1].compare(sines[3]) <= 0)
}

///|
test "BinFloat trigonometric reduction certifies arguments beyond linear reduction" {
  let value = BinFloat::make(BinCoeff::one(), 20, 53)
  match value.try_sin_ctx(BinaryContext::binary64()) {
    Ok((result, _)) => {
      assert_true(result.classify() == FpClass::Finite)
      assert_true(result.abs().compare(BinFloat::one()) <= 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "BinFloat trigonometric resource failure retains proof details" {
  let value = BinFloat::make(BinCoeff::one(), 1_100_000, 53)
  match value.try_cos_ctx(BinaryContext::binary64()) {
    Ok(_) => assert_true(false)
    Err(error) =>
      match error.certification_failure_detail() {
        Some(detail) => {
          assert_eq(detail.operation(), "cos")
          assert_true(detail.stage() == @def.CertificationStage::RangeReduction)
          assert_true(
            detail.reason() == @def.CertificationFailureReason::ResourceLimit,
          )
          assert_eq(detail.target_precision(), 53)
          assert_true(detail.work_precision() > 0)
        }
        None => assert_true(false)
      }
  }
}

///|
test "BinFloat fused exp-ln rounds only once" {
  let context = BinaryContext::binary64()
  let value = BinFloat::from_double(0.0625, precision=53)
  let (fused, flags) = value.exp_ln_ctx(context)
  assert_eq(fused, value)
  assert_false(flags.inexact())
}

///|
test "BinFloat expm1 and log1p preserve tiny nonzero inputs" {
  let tiny = BinFloat::make(BinCoeff::one(), -200, 53)
  let positive_expm1 = tiny.expm1()
  let positive_log1p = tiny.log1p()
  assert_true(!positive_expm1.is_zero())
  assert_true(!positive_log1p.is_zero())
  assert_true(positive_expm1.sign() == Sign::Positive)
  assert_true(positive_log1p.sign() == Sign::Positive)
  assert_true(!tiny.neg().expm1().is_zero())
  assert_true(!tiny.neg().log1p().is_zero())
}

///|
test "certified target witness rejects equal values with unequal flags" {
  let context = BinaryContext::unbounded(3)
  let exact = BinFloat::one(precision=4)
  let midpoint = BinFloat::make(BinCoeff::from_uint64(9UL), -3, 4)
  let (rounded, unique, flags) = binary_certified_target_rounding(
    exact, midpoint, context,
  )
  assert_eq(rounded, BinFloat::one(precision=3))
  assert_false(unique)
  assert_true(flags.inexact())
}

///|
test "BinFloat elementary functions honor every directed rounding mode" {
  let value = BinFloat::one(precision=53)
  let downward = value.exp_ctx(
    BinaryContext::unbounded(
      24,
      rounding=BinaryRoundingMode::RoundTowardNegative,
    ),
  )
  let upward = value.exp_ctx(
    BinaryContext::unbounded(
      24,
      rounding=BinaryRoundingMode::RoundTowardPositive,
    ),
  )
  let toward_zero = value.exp_ctx(
    BinaryContext::unbounded(24, rounding=BinaryRoundingMode::RoundTowardZero),
  )
  let away = value.exp_ctx(
    BinaryContext::unbounded(24, rounding=BinaryRoundingMode::RoundAwayFromZero),
  )
  let ties_even = value.exp_ctx(
    BinaryContext::unbounded(24, rounding=BinaryRoundingMode::RoundTiesToEven),
  )
  let ties_away = value.exp_ctx(
    BinaryContext::unbounded(24, rounding=BinaryRoundingMode::RoundTiesToAway),
  )
  assert_eq(toward_zero.0, downward.0)
  assert_eq(away.0, upward.0)
  assert_true(downward.0.compare(ties_even.0) <= 0)
  assert_true(ties_even.0.compare(upward.0) <= 0)
  assert_true(downward.0.compare(ties_away.0) <= 0)
  assert_true(ties_away.0.compare(upward.0) <= 0)
  assert_true(downward.1.inexact())
  assert_true(upward.1.inexact())
}
