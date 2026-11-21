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
  assert_eq(BinFloat::from_int(2).pown(10), BinFloat::from_int(1024))
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
    Ok((value, flags)) => {
      assert_true(value.is_nan())
      assert_true(flags.invalid_operation())
      assert_false(flags.not_computed())
    }
    Err(_) => assert_true(false)
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
    Ok((value, flags)) => {
      assert_true(value.is_nan())
      assert_true(flags.invalid_operation())
      assert_false(flags.not_computed())
    }
    Err(_) => assert_true(false)
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
  // S4: a domain case is a value in the try_ form
  match invalid {
    Ok((value, flags)) => {
      assert_true(value.is_nan())
      assert_true(flags.invalid_operation())
      assert_false(flags.not_computed())
    }
    Err(_) => assert_true(false)
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
  // S4: a domain case is a value in the try_ form
  match invalid {
    Ok((value, flags)) => {
      assert_true(value.is_nan())
      assert_true(flags.invalid_operation())
      assert_false(flags.not_computed())
    }
    Err(_) => assert_true(false)
  }
}

///|
test "BinFloat acos rejects inputs outside its domain instead of recursing" {
  let context = BinaryContext::binary64()
  // Each of these used to recurse through the certified asin bounds until the
  // stack overflowed (SIGSEGV on native, RangeError on wasm-gc).
  for
    value in [
      BinFloat::from_int(2),
      BinFloat::from_int(2).neg(),
      BinFloat::inf(Sign::Positive),
      BinFloat::inf(Sign::Negative),
    ] {
    match value.try_acos_ctx(context) {
      Ok((nan, flags)) => {
        assert_true(nan.is_nan())
        assert_true(flags.invalid_operation())
        assert_false(flags.not_computed())
      }
      Err(_) => assert_true(false)
    }
    assert_true(value.acos().classify() == FpClass::NaN)
  }
  let quiet = BinFloat::nan(precision=53)
  assert_true(quiet.acos().classify() == FpClass::NaN)
  match quiet.try_acos_ctx(context) {
    Ok((result, flags)) => {
      assert_true(result.classify() == FpClass::NaN)
      assert_true(flags.invalid_operation() == false)
    }
    Err(_) => assert_true(false)
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
test "BinFloat atan2 follows the IEEE signed-zero special cases" {
  let context = BinaryContext::new(precision=53)
  let pz = BinFloat::zero()
  let nz = BinFloat::negative_zero()
  let m1 = BinFloat::from_int(-1)
  let pinf = BinFloat::inf(Sign::Positive)
  let ninf = BinFloat::inf(Sign::Negative)
  let (pi, _) = m1.acos_ctx(context)
  // atan2(±0, +0) and atan2(±0, x > 0) are ±0, exact.
  for abscissa in [pz, BinFloat::one(), pinf] {
    let (positive, positive_flags) = pz.atan2_ctx(abscissa, context)
    assert_true(positive.is_zero() && !positive.is_negative())
    assert_eq(positive_flags, BinaryFlags::new())
    let (negative, negative_flags) = nz.atan2_ctx(abscissa, context)
    assert_true(negative.is_negative_zero())
    assert_eq(negative_flags, BinaryFlags::new())
  }
  // atan2(±0, -0) and atan2(±0, x < 0) are ±π.
  for abscissa in [nz, m1, ninf] {
    let (positive, positive_flags) = pz.atan2_ctx(abscissa, context)
    assert_eq(positive, pi)
    assert_true(positive_flags.inexact())
    let (negative, _) = nz.atan2_ctx(abscissa, context)
    assert_eq(negative, pi.neg())
  }
  // A nonzero ordinate over a zero abscissa is still ±π/2.
  let (half_pi, _) = pinf.atan_ctx(context)
  assert_eq(BinFloat::one().atan2_ctx(nz, context).0, half_pi)
  assert_eq(m1.atan2_ctx(pz, context).0, half_pi.neg())
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
  assert_true(one.tanpi().is_negative_zero())
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
test "BinFloat tanpi at integers takes the sign of sinpi over cospi" {
  let context = BinaryContext::binary64()
  // IEEE 754-2019 §9.2.1 and C23 Annex F: tanPi(n) is +0 for positive even
  // and negative odd n, and -0 for positive odd and negative even n.
  for n in [1, 3, -2, -4] {
    let (tangent, flags) = BinFloat::from_int(n).tanpi_ctx(context)
    assert_true(tangent.is_negative_zero(), msg="tanpi(" + n.to_string() + ")")
    assert_eq(flags, BinaryFlags::new())
  }
  for n in [2, 4, -1, -3] {
    let (tangent, flags) = BinFloat::from_int(n).tanpi_ctx(context)
    assert_true(
      tangent.is_zero() && !tangent.is_negative(),
      msg="tanpi(" + n.to_string() + ")",
    )
    assert_eq(flags, BinaryFlags::new())
  }
  assert_true(BinFloat::zero().tanpi().is_zero())
  assert_true(!BinFloat::zero().tanpi().is_negative())
  assert_true(BinFloat::negative_zero().tanpi().is_negative_zero())
  // Every binary64 value with |x| >= 2^53 is an even integer.
  let huge = BinFloat::make(BinCoeff::one(), 60, 53)
  assert_true(!huge.tanpi().is_negative())
  assert_true(huge.neg().tanpi().is_negative_zero())
  // tanPi(n + 1/2) alternates: +inf for even n, -inf for odd n.
  let half = BinFloat::make(BinCoeff::one(), -1, 53)
  assert_eq(half.tanpi(), BinFloat::inf(Sign::Positive))
  assert_eq(half.add(BinFloat::one()).tanpi(), BinFloat::inf(Sign::Negative))
}

///|
test "BinFloat pi-scaled quarter is certified across release precisions" {
  for precision in [53, 128, 512] {
    let quarter = BinFloat::from_double(0.25, precision~)
    let context = BinaryContext::new(precision~)
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
  ]
  let sines : Array[BinFloat] = []
  for mode in modes {
    let context = BinaryContext::new(precision=24, rounding=mode)
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
  let value = BinFloat::make(BinCoeff::one(), 8_100_000, 53)
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
  let context = BinaryContext::new(precision=3)
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
fn certified_rounding_endpoint(coefficient : UInt64) -> BinFloat {
  // coefficient * 2^-4 at precision 8
  BinFloat::make(BinCoeff::from_uint64(coefficient), -4, 8)
}

///|
// Oracle (level A): expected values written out from arithmetic on the grid of
// a 3-bit significand in [1, 2), whose spacing is 2^-2: the representable
// numbers there are 1, 1.25, 1.5, 1.75. The endpoints are k/16:
// 16/16 = 1, 17/16 = 1.0625, 18/16 = 1.125 (the midpoint of 1 and 1.25: ties
// to even gives 1), 19/16 = 1.1875. The rule under test is that of
// `binary_certified_target_rounding`: the witness is unique only if both
// endpoints round to the same value with the same flags. Nothing is computed
// by the library except the call under test and the endpoints' `make`.
// (These blocks replace tests of a local copy of the function in
// `ball_float/certified_rounding_wbtest.mbt`, which ignored the flags.)
test "certified target rounding accepts one rounded value with equal flags" {
  let context = BinaryContext::new(precision=3)
  // 17/16 and 18/16 both round to 1, both inexact
  let (value, unique, flags) = binary_certified_target_rounding(
    certified_rounding_endpoint(17UL),
    certified_rounding_endpoint(18UL),
    context,
  )
  assert_true(unique)
  assert_eq(value, BinFloat::one(precision=3))
  assert_true(flags.inexact())
  // 16/16 is exact (value 1, no flags) and 17/16 is inexact (value 1): equal
  // values with unequal flags are not a witness
  let (_, mixed_unique, _) = binary_certified_target_rounding(
    certified_rounding_endpoint(16UL),
    certified_rounding_endpoint(17UL),
    context,
  )
  assert_false(mixed_unique)
  // 16/16 and 19/16 round to 1 and 1.25
  let (_, split_unique, _) = binary_certified_target_rounding(
    certified_rounding_endpoint(16UL),
    certified_rounding_endpoint(19UL),
    context,
  )
  assert_false(split_unique)
}

///|
test "certified target rounding respects directed modes" {
  let downward = BinaryContext::new(
    precision=3,
    rounding=BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = BinaryContext::new(
    precision=3,
    rounding=BinaryRoundingMode::RoundTowardPositive,
  )
  let low = certified_rounding_endpoint(17UL)
  let high = certified_rounding_endpoint(19UL)
  // 17/16 and 19/16 are both strictly between 1 and 1.25, both inexact:
  // downward both give 1, upward both give 1.25
  let (down_value, down_unique, _) = binary_certified_target_rounding(
    low, high, downward,
  )
  assert_true(down_unique)
  assert_eq(down_value, BinFloat::one(precision=3))
  let (up_value, up_unique, _) = binary_certified_target_rounding(
    low, high, upward,
  )
  assert_true(up_unique)
  assert_eq(up_value, BinFloat::make(BinCoeff::from_uint64(5UL), -2, 3))
  // 16/16 is exact and 17/16 is not: the flags differ in either direction,
  // and upward the values (1 and 1.25) differ as well
  let exact = certified_rounding_endpoint(16UL)
  let (_, down_mixed, _) = binary_certified_target_rounding(
    exact, low, downward,
  )
  let (_, up_mixed, _) = binary_certified_target_rounding(exact, low, upward)
  assert_false(down_mixed)
  assert_false(up_mixed)
}

///|
test "BinFloat elementary functions honor every directed rounding mode" {
  let value = BinFloat::one(precision=53)
  let downward = value.exp_ctx(
    BinaryContext::new(
      precision=24,
      rounding=BinaryRoundingMode::RoundTowardNegative,
    ),
  )
  let upward = value.exp_ctx(
    BinaryContext::new(
      precision=24,
      rounding=BinaryRoundingMode::RoundTowardPositive,
    ),
  )
  let toward_zero = value.exp_ctx(
    BinaryContext::new(
      precision=24,
      rounding=BinaryRoundingMode::RoundTowardZero,
    ),
  )
  let ties_even = value.exp_ctx(
    BinaryContext::new(
      precision=24,
      rounding=BinaryRoundingMode::RoundTiesToEven,
    ),
  )
  let ties_away = value.exp_ctx(
    BinaryContext::new(
      precision=24,
      rounding=BinaryRoundingMode::RoundTiesToAway,
    ),
  )
  assert_eq(toward_zero.0, downward.0)
  assert_true(downward.0.compare(ties_even.0) <= 0)
  assert_true(ties_even.0.compare(upward.0) <= 0)
  assert_true(downward.0.compare(ties_away.0) <= 0)
  assert_true(ties_away.0.compare(upward.0) <= 0)
  assert_true(downward.1.inexact())
  assert_true(upward.1.inexact())
}
