///|
// oracle: A
// source: written out from IEEE Std 754-2019 9.2.1: exp(+0) = 1, ln(1) = +0 and ln(-1) is an invalid operation with a quiet NaN
// shares: Binary::zero, one and from_int build the operands; exp_ctx and ln_ctx are the code under test; assert_identical and the flag accessors read the result
test "Binary certified exp and ln special values" {
  let context = BinaryContext::binary64()
  let (exp_zero, _) = Binary::zero().exp_ctx(context)
  assert_identical(exp_zero, Binary::one())
  let (ln_one, _) = Binary::one().ln_ctx(context)
  assert_identical(ln_one, Binary::zero())
  let (ln_negative, flags) = Binary::from_int(-1).ln_ctx(context)
  assert_true(ln_negative.is_quiet_nan())
  assert_true(flags.invalid_operation())
}

///|
// oracle: S
// source: the round trip ln(exp(1/16)) is within 2^-52 of 1/16; both functions are the code under test, no value is stated from outside
// shares: Binary::from_double and make build the operands; exp and ln are the code under test; sub, abs and the comparison read the result
test "Binary certified exp and ln round-trip small values" {
  let value = Binary::from_double(0.0625, precision=53)
  let round_trip = value.exp().ln()
  let difference = round_trip.sub(value).abs()
  assert_true(difference <= Binary::make(BinCoeff::one(), -52, 53))
}

///|
// oracle: A
// source: written out: e = 2.718... lies strictly between 2 and 3 and 1/e = 0.368 strictly between 0 and 1
// shares: Binary::from_int and zero build the operands; exp is the code under test; classify and the comparison operators read the result
test "Binary certified exp range reduction handles ordinary inputs" {
  let result = Binary::from_int(1).exp()
  assert_true(result.classify() == FpClass::Finite)
  assert_true(result > Binary::from_int(2))
  assert_true(result < Binary::from_int(3))
  let reciprocal = Binary::from_int(-1).exp()
  assert_true(reciprocal > Binary::zero())
  assert_true(reciprocal < Binary::one())
}

///|
// oracle: A
// source: written out: 10^1 = 10 lies strictly between 9 and 11 (the bound is as written, the exact value is 10)
// shares: Binary::from_int builds the operand; exp10 is the code under test; classify and the comparison operators read the result
test "Binary certified exp10 handles ordinary inputs" {
  let result = Binary::from_int(1).exp10()
  assert_true(result.classify() == FpClass::Finite)
  assert_true(result > Binary::from_int(9))
  assert_true(result < Binary::from_int(11))
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 9.2.1 and 7.6 (an exact result raises no inexact): exp2(k) = 2^k for k in -4, -1, 0, 1, 4, exp10(2) = 100, log2(2^9) = 9, log10(1000) = 3, rootn(27/8, 3) = 3/2 and pow(441/256, 1/2) = 21/16, all without inexact in binary64
// shares: Binary::from_int and make build the operands and the expected values; exp2_ctx, exp10_ctx, log2_ctx, log10_ctx, rootn_ctx and pow_ctx are the code under test; assert_identical, compare and the flag accessors read the result
test "Binary exact elementary identities preserve exact flags" {
  let context = BinaryContext::binary64()
  for exponent in [-4, -1, 0, 1, 4] {
    let input = Binary::from_int(exponent, precision=53)
    let (result, flags) = input.exp2_ctx(context)
    assert_true(result.compare(Binary::make(BinCoeff::one(), exponent, 1)) == 0)
    assert_true(!flags.inexact())
  }
  let (hundred, hundred_flags) = Binary::from_int(2).exp10_ctx(context)
  assert_identical(hundred, Binary::from_int(100))
  assert_true(!hundred_flags.inexact())
  let (binary_logarithm, binary_flags) = Binary::make(BinCoeff::one(), 9, 53).log2_ctx(
    context,
  )
  assert_identical(binary_logarithm, Binary::from_int(9))
  assert_true(!binary_flags.inexact())
  let (decimal_logarithm, decimal_flags) = Binary::from_int(1000).log10_ctx(
    context,
  )
  assert_identical(decimal_logarithm, Binary::from_int(3))
  assert_true(!decimal_flags.inexact())
  let (cube_root, cube_root_flags) = Binary::make(
    BinCoeff::from_uint64(27UL),
    -3,
    53,
  ).rootn_ctx(3, context)
  assert_identical(cube_root, Binary::make(BinCoeff::from_uint64(3UL), -1, 53))
  assert_true(!cube_root_flags.inexact())
  let exact_square = Binary::make(BinCoeff::from_uint64(441UL), -8, 53)
  let half = Binary::make(BinCoeff::one(), -1, 53)
  let (power_root, power_root_flags) = exact_square.pow_ctx(half, context)
  assert_identical(
    power_root,
    Binary::make(BinCoeff::from_uint64(21UL), -4, 53),
  )
  assert_true(!power_root_flags.inexact())
}

///|
// oracle: A
// source: written out: ln 8 = 2.079 lies strictly between 2 and 3 and log10(10) = 1 exactly
// shares: Binary::from_int and one build the operands; ln and log10 are the code under test; assert_identical and the comparison operators read the result
test "Binary certified logarithm range reduction handles ordinary inputs" {
  let natural = Binary::from_int(8).ln()
  assert_true(natural > Binary::from_int(2))
  assert_true(natural < Binary::from_int(3))
  let decimal = Binary::from_int(10).log10()
  assert_identical(decimal, Binary::one())
}

///|
// oracle: A
// source: written out: hypot(3, 4) = 5 exactly and hypot(-inf, 0) = +inf (IEEE Std 754-2019 9.2.1 and Table 9.1)
// shares: Binary::from_int, inf and zero build the operands; hypot is the code under test; assert_identical reads the result
test "Binary hypot rounds the exact sum of squares" {
  let result = Binary::from_int(3).hypot(Binary::from_int(4))
  assert_identical(result, Binary::from_int(5))
  assert_identical(
    Binary::inf(negative=true).hypot(Binary::zero()),
    Binary::inf(),
  )
}

///|
// oracle: A
// source: written out: 2^10 = 1024 (IEEE Std 754-2019 9.2.1)
// shares: Binary::from_int builds the operand; pown is the code under test; assert_identical reads the result
test "Binary pown preserves the standard integer-power semantics" {
  assert_identical(Binary::from_int(2).pown(10), Binary::from_int(1024))
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 9.2.1: ln(+0) = -inf with divideByZero and log10(-1) is an invalid operation with a quiet NaN
// shares: Binary::zero and from_int build the operands; ln_ctx and log10_ctx are the code under test; classify, signum and the flag accessors read the result
test "Binary logarithms preserve IEEE zero and domain flags" {
  let context = BinaryContext::binary64()
  let (zero_log, zero_flags) = Binary::zero().ln_ctx(context)
  assert_true(zero_log.classify() == FpClass::Infinity)
  assert_true(zero_log.signum() == Sign::Negative)
  assert_true(zero_flags.division_by_zero())
  let (negative_log, negative_flags) = Binary::from_int(-1).log10_ctx(context)
  assert_true(negative_log.is_quiet_nan())
  assert_true(negative_flags.invalid_operation())
}

///|
// oracle: A, S
// source: A: written out from IEEE Std 754-2019 9.2.1 and Table 9.1: rootn(8, 3) = 2, rootn(-8, 3) = -2, rootn(2, -1) = 1/2 and rootn(-8, 2) is an invalid operation (x < 0 and n even); S: the S4 mapping of the library (a domain case is a value with invalid_operation in the try_ form, never an Err and never not_computed) is asserted as well
// shares: Binary::from_int and make build the operands; rootn and try_rootn_ctx are the code under test; assert_identical, is_nan and the flag accessors read the result
test "Binary rootn uses certified logarithm and exponential bounds" {
  let result = Binary::from_int(8).rootn(3)
  assert_identical(result, Binary::from_int(2))
  let negative = Binary::from_int(-8).rootn(3)
  assert_identical(negative, Binary::from_int(-2))
  assert_identical(
    Binary::from_int(2).rootn(-1),
    Binary::make(BinCoeff::one(), -1, 53),
  )
  let even_domain = Binary::from_int(-8).try_rootn_ctx(
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
// oracle: A, S
// source: A: written out from IEEE Std 754-2019 9.2.1: (-2)^3 = -8, 9^(1/2) = 3 exactly and (-2)^(1/2) is an invalid operation; S: the S4 mapping of the library (a domain case is a value with invalid_operation in the try_ form, never an Err and never not_computed) is asserted as well
// shares: Binary::from_int and make build the operands; pow and try_pow_ctx are the code under test; assert_identical, is_nan and the flag accessors read the result
test "Binary pow separates integer and positive non-integer domains" {
  assert_identical(
    Binary::from_int(-2).pow(Binary::from_int(3)),
    Binary::from_int(-8),
  )
  let square_root = Binary::from_int(9).pow(
    Binary::make(BinCoeff::one(), -1, 53),
  )
  assert_identical(square_root, Binary::from_int(3))
  let invalid = Binary::from_int(-2).try_pow_ctx(
    Binary::make(BinCoeff::one(), -1, 53),
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
// oracle: A, S
// source: A: sinh(0) = 0, cosh(0) = 1, tanh(0) = 0 (IEEE Std 754-2019 9.2.1) and 0 < tanh(1) = 0.762 < 1; S: sinh(-1) = -sinh(1) and cosh(-1) = cosh(1) compare the code under test with itself on the mirrored argument
// shares: Binary::zero and one build the operands; sinh, cosh and tanh are the code under test; assert_identical and the comparison operators read the result
test "Binary certified hyperbolic functions preserve identities" {
  let zero = Binary::zero()
  assert_identical(zero.sinh(), zero)
  assert_identical(zero.cosh(), Binary::one())
  assert_identical(zero.tanh(), zero)
  let one = Binary::one()
  assert_identical(one.sinh().neg(), one.neg().sinh())
  assert_identical(one.cosh(), one.neg().cosh())
  assert_true(one.tanh() > zero)
  assert_true(one.tanh() < one)
}

///|
// oracle: A, S
// source: A: asinh(0) = 0, atanh(0) = 0, acosh(1) = +0, acosh(0) is an invalid operation (x < 1) and atanh(1) = +inf with divideByZero (IEEE Std 754-2019 9.2.1 and Table 9.1); S: asinh(-1) = -asinh(1) compares the code under test with itself, and the S4 mapping of the library (a domain case is a value with invalid_operation in the try_ form, never an Err and never not_computed) is asserted as well
// shares: Binary::zero and one build the operands; asinh, acosh, atanh, try_acosh_ctx and atanh_ctx are the code under test; assert_identical, classify and the flag accessors read the result
test "Binary inverse hyperbolic functions preserve domains and identities" {
  let zero = Binary::zero()
  assert_identical(zero.asinh(), zero)
  assert_identical(zero.atanh(), zero)
  assert_identical(Binary::one().acosh(), zero)
  let one = Binary::one()
  assert_identical(one.asinh().neg(), one.neg().asinh())
  let invalid = Binary::zero().try_acosh_ctx(BinaryContext::binary64())
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
// oracle: A, S
// source: A: atan(0) = 0 and 1/2 < atan(1) = pi/4 = 0.785 < 1; S: atan(-1) = -atan(1) compares the code under test with itself on the mirrored argument
// shares: Binary::zero, one, make and neg build the operands; atan is the code under test; assert_identical and the comparison operators read the result
test "Binary certified atan preserves origin and odd symmetry" {
  let zero = Binary::zero()
  assert_identical(zero.atan(), zero)
  let one = Binary::one()
  let positive = one.atan()
  assert_true(positive > Binary::make(BinCoeff::one(), -1, 53))
  assert_true(positive < one)
  assert_identical(positive.neg(), one.neg().atan())
}

///|
// oracle: A, S
// source: A: asin(0) = 0, acos(1) = +0, 3 < acos(-1) = pi < 4 and asin(2) is an invalid operation (IEEE Std 754-2019 9.2.1 and Table 9.1); S: asin(-1) = -asin(1) compares the code under test with itself, and the S4 mapping of the library (a domain case is a value with invalid_operation in the try_ form, never an Err and never not_computed) is asserted as well
// shares: Binary::zero, one, from_int and neg build the operands; asin, acos and try_asin_ctx are the code under test; assert_identical, the comparison operators and the flag accessors read the result
test "Binary inverse trigonometric functions preserve domains" {
  let zero = Binary::zero()
  let one = Binary::one()
  assert_identical(zero.asin(), zero)
  assert_identical(one.acos(), zero)
  let negative_one_acos = one.neg().acos()
  assert_true(negative_one_acos > Binary::from_int(3))
  assert_true(negative_one_acos < Binary::from_int(4))
  assert_identical(one.asin().neg(), one.neg().asin())
  let invalid = Binary::from_int(2).try_asin_ctx(BinaryContext::binary64())
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
// oracle: A, S
// source: A: IEEE Std 754-2019 9.2.1 and Table 9.1: acos of 2, -2, +inf and -inf is an invalid operation with a quiet NaN, and a quiet NaN gives a NaN without invalid; S: the S4 mapping of the library (a domain case is a value with invalid_operation in the try_ form, never an Err and never not_computed) is asserted as well; the regression that these inputs once recursed until the stack overflowed is a property of the run
// shares: Binary::from_int, inf and nan build the operands; try_acos_ctx and acos are the code under test; is_nan, classify and the flag accessors read the result
test "Binary acos rejects inputs outside its domain instead of recursing" {
  let context = BinaryContext::binary64()
  // Each of these used to recurse through the certified asin bounds until the
  // stack overflowed (SIGSEGV on native, RangeError on wasm-gc).
  for
    value in [
      Binary::from_int(2),
      Binary::from_int(2).neg(),
      Binary::inf(),
      Binary::inf(negative=true),
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
  let quiet = Binary::nan(precision=53)
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
// oracle: S
// source: is_ok only: asin(-17 * 2^-8), atan(4) and atan2(4, 1) in binary32 return Ok; no value is compared
// shares: try_asin_ctx, try_atan_ctx and try_atan2_ctx (the code under test), Binary::make, Binary::from_int
test "Binary inverse trigonometric half-angle reduction reaches its certified series domain" {
  let context = BinaryContext::binary32()
  let small_negative = Binary::make(
    BinCoeff::from_uint64(17UL),
    -8,
    53,
    negative=true,
  )
  assert_true(small_negative.try_asin_ctx(context) is Ok(_))
  assert_true(Binary::from_int(4).try_atan_ctx(context) is Ok(_))
  assert_true(
    Binary::from_int(4).try_atan2_ctx(Binary::one(), context) is Ok(_),
  )
}

///|
// oracle: A
// source: written out: atan2(0, 1) = 0, atan2(1, 0) = pi/2 > 1, atan2(1, 1) = pi/4 > 0, atan2(1, -1) = 3 pi/4 > 1 and atan2(-1, -1) = -3 pi/4 < -1 (IEEE Std 754-2019 9.2.1)
// shares: Binary::zero, one and neg build the operands; atan2 is the code under test; assert_identical and the comparison operators read the result
test "Binary atan2 preserves axes and quadrants" {
  let zero = Binary::zero()
  let one = Binary::one()
  assert_identical(zero.atan2(one), zero)
  assert_true(one.atan2(zero) > one)
  assert_true(one.atan2(one) > zero)
  assert_true(one.atan2(one.neg()) > one)
  assert_true(one.neg().atan2(one.neg()) < one.neg())
}

///|
// oracle: A
// source: written out from IEEE 754-2019 9.2.1: atan2(+-0, +0) and atan2(+-0, x > 0) are +-0 exactly, atan2(+-0, -0) and atan2(+-0, x < 0) are +-pi, a nonzero ordinate over a zero abscissa is +-pi/2; pi and pi/2 at 53 bits are 0x1921fb54442d18 * 2^-51 and 2^-52 (CPython math.pi.hex() is 0x1.921fb54442d18p+1)
// shares: Binary::from_hex_ctx reads the constants exactly (level A through hex_ctx_rows), assert_identical, the flag accessors
test "Binary atan2 follows the IEEE signed-zero special cases" {
  let context = BinaryContext::new(precision=53)
  let pz = Binary::zero()
  let nz = Binary::negative_zero()
  let m1 = Binary::from_int(-1)
  let pinf = Binary::inf()
  let ninf = Binary::inf(negative=true)
  // pi and pi / 2 rounded to nearest at 53 bits, written out: 0x1921fb54442d18 * 2^-51
  // is the double nearest to pi (CPython math.pi.hex() is 0x1.921fb54442d18p+1).
  let pi = Binary::from_hex_ctx("0x1921fb54442d18p-51", context).unwrap().0
  // atan2(±0, +0) and atan2(±0, x > 0) are ±0, exact.
  for abscissa in [pz, Binary::one(), pinf] {
    let (positive, positive_flags) = pz.atan2_ctx(abscissa, context)
    assert_true(positive.is_zero() && !positive.is_sign_minus())
    assert_eq(positive_flags, BinaryFlags::new())
    let (negative, negative_flags) = nz.atan2_ctx(abscissa, context)
    assert_true(negative.is_negative_zero())
    assert_eq(negative_flags, BinaryFlags::new())
  }
  // atan2(±0, -0) and atan2(±0, x < 0) are ±π.
  for abscissa in [nz, m1, ninf] {
    let (positive, positive_flags) = pz.atan2_ctx(abscissa, context)
    assert_identical(positive, pi)
    assert_true(positive_flags.inexact())
    let (negative, _) = nz.atan2_ctx(abscissa, context)
    assert_identical(negative, pi.neg())
  }
  // A nonzero ordinate over a zero abscissa is still ±π/2.
  let half_pi = Binary::from_hex_ctx("0x1921fb54442d18p-52", context).unwrap().0
  assert_identical(Binary::one().atan2_ctx(nz, context).0, half_pi)
  assert_identical(m1.atan2_ctx(pz, context).0, half_pi.neg())
}

///|
// oracle: A
// source: written out: sin(0) = 0, cos(0) = 1, tan(0) = 0 (IEEE Std 754-2019 9.2.1) and 3/4 < sin(1) = 0.841 < 1, 1/2 < cos(1) = 0.540 < 1, tan(1) = 1.557 > 1
// shares: Binary::zero, one, make and from_int build the operands; sin, cos and tan are the code under test; assert_identical and the comparison operators read the result
test "Binary trigonometric functions preserve axis identities" {
  let zero = Binary::zero()
  assert_identical(zero.sin(), zero)
  assert_identical(zero.cos(), Binary::one())
  assert_identical(zero.tan(), zero)
  let one = Binary::one()
  assert_true(one.sin() > Binary::make(BinCoeff::from_uint64(3UL), -2, 53))
  assert_true(one.sin() < one)
  assert_true(one.cos() > Binary::make(BinCoeff::from_uint64(1UL), -1, 53))
  assert_true(one.cos() < one)
  assert_true(one.tan() > Binary::from_int(1))
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 9.2.1 (sinPi(+n) = +0 and sinPi(-n) = -0 for positive integers n, cosPi(n + 1/2) = +0, tanPi(2n + 1) = -0, tanPi(2n - 0.5) = -inf with divideByZero, sinPi(1/2) = 1, cosPi(1) = -1, and the integers beyond 2^53 are even): sinPi(1) = +0, cosPi(1) = -1, tanPi(1) = -0, sinPi(1/2) = 1, cosPi(1/2) = +0, sinPi(-1/2) = -1, tanPi(-1/2) = -inf, sinPi(-1) = -0, and sinPi, cosPi, tanPi of 2^40 are 0, 1, 0
// shares: Binary::one, zero, make, from_int, inf and neg build the operands; sinpi, cospi, tanpi and tanpi_ctx are the code under test; assert_identical, is_negative_zero, is_zero, is_infinite, is_sign_minus and the flag accessor read the result
test "Binary pi-scaled functions preserve exact integer and half-integer identities" {
  let one = Binary::one()
  let half = Binary::make(BinCoeff::one(), -1, 53)
  assert_identical(one.sinpi(), Binary::zero())
  assert_identical(one.cospi(), one.neg())
  assert_true(one.tanpi().is_negative_zero())
  assert_identical(half.sinpi(), one)
  assert_identical(half.cospi(), Binary::zero())
  let negative_half = half.neg()
  assert_identical(negative_half.sinpi(), one.neg())
  assert_identical(negative_half.tanpi(), Binary::inf(negative=true))
  // the poles signal divideByZero (IEEE 754-2019 9.2.1)
  let (pole, pole_flags) = negative_half.tanpi_ctx(BinaryContext::binary64())
  assert_true(pole.is_infinite() && pole.is_sign_minus())
  assert_true(pole_flags.division_by_zero())
  let (upper_pole, upper_pole_flags) = half.tanpi_ctx(BinaryContext::binary64())
  assert_true(upper_pole.is_infinite() && !upper_pole.is_sign_minus())
  assert_true(upper_pole_flags.division_by_zero())
  assert_true(Binary::from_int(-1).sinpi().is_negative_zero())
  let huge_integer = Binary::make(BinCoeff::one(), 40, 53)
  assert_true(huge_integer.sinpi().is_zero())
  assert_identical(huge_integer.cospi(), Binary::one())
  assert_true(huge_integer.tanpi().is_zero())
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 9.2.1 (pdftotext of the PDF: tanPi(2n + 1) = -0, tanPi(2n + 2) = +0, tanPi(2n - 1) = +0, tanPi(2n - 2) = -0, tanPi(2n + 0.5) = +inf, tanPi(2n + 1.5) = -inf) and C23 Annex F: tanPi(n) is -0 for n = 1, 3, -2, -4 and +0 for n = 2, 4, -1, -3, tanPi(+-0) = +-0, 2^60 is an even integer, tanPi(1/2) = +inf and tanPi(3/2) = -inf, with no flag for the zeros
// shares: Binary::from_int, zero, negative_zero, make, one, add and inf build the operands; tanpi_ctx and tanpi are the code under test; is_negative_zero, is_zero, is_sign_minus and assert_identical read the result
test "Binary tanpi at integers takes the sign of sinpi over cospi" {
  let context = BinaryContext::binary64()
  // IEEE 754-2019 §9.2.1 and C23 Annex F: tanPi(n) is +0 for positive even
  // and negative odd n, and -0 for positive odd and negative even n.
  for n in [1, 3, -2, -4] {
    let (tangent, flags) = Binary::from_int(n).tanpi_ctx(context)
    assert_true(tangent.is_negative_zero(), msg="tanpi(" + n.to_string() + ")")
    assert_eq(flags, BinaryFlags::new())
  }
  for n in [2, 4, -1, -3] {
    let (tangent, flags) = Binary::from_int(n).tanpi_ctx(context)
    assert_true(
      tangent.is_zero() && !tangent.is_sign_minus(),
      msg="tanpi(" + n.to_string() + ")",
    )
    assert_eq(flags, BinaryFlags::new())
  }
  assert_true(Binary::zero().tanpi().is_zero())
  assert_true(!Binary::zero().tanpi().is_sign_minus())
  assert_true(Binary::negative_zero().tanpi().is_negative_zero())
  // Every binary64 value with |x| >= 2^53 is an even integer.
  let huge = Binary::make(BinCoeff::one(), 60, 53)
  assert_true(!huge.tanpi().is_sign_minus())
  assert_true(huge.neg().tanpi().is_negative_zero())
  // tanPi(n + 1/2) alternates: +inf for even n, -inf for odd n.
  let half = Binary::make(BinCoeff::one(), -1, 53)
  assert_identical(half.tanpi(), Binary::inf())
  assert_identical(half.add(Binary::one()).tanpi(), Binary::inf(negative=true))
}

///|
// oracle: A, S
// source: tanpi(+-1/4) = +-1 exactly and without the inexact flag, written out; the Ok results of sinpi, cospi and tanpi at 1/4 are an is_ok check (S)
// shares: Binary::from_double builds the argument, Binary::one at the same precision, assert_identical and the inexact flag accessor
test "Binary pi-scaled quarter is certified across release precisions" {
  for precision in [53, 128, 512] {
    let quarter = Binary::from_double(0.25, precision~)
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
    assert_identical(positive_tangent, Binary::one(precision~))
    assert_true(!positive_flags.inexact())
    let (negative_tangent, negative_flags) = quarter.neg().tanpi_ctx(context)
    assert_identical(negative_tangent, Binary::one(precision~).neg())
    assert_true(!negative_flags.inexact())
  }
}

///|
// oracle: A, S
// source: tanpi(1/4) = 1 and tanpi(3/4) = -1 written out (exact); the Ok results of sinpi, cospi and tanpi at the 17 multiples of 1/4 from -2 to 2 are an is_ok check (S)
// shares: Binary::make, Binary::from_int, Binary::mul and Binary::add build the arguments; assert_identical
test "Binary pi-scaled exact quadrant reduction covers every quarter boundary" {
  let context = BinaryContext::binary64()
  let quarter = Binary::make(BinCoeff::one(), -2, 53)
  let half = Binary::make(BinCoeff::one(), -1, 53)
  for offset in -8..<=8 {
    let value = Binary::from_int(offset, precision=53).mul(quarter)
    assert_true(value.try_sinpi_ctx(context) is Ok(_))
    assert_true(value.try_cospi_ctx(context) is Ok(_))
    if offset % 2 != 0 || offset % 4 == 0 {
      assert_true(value.try_tanpi_ctx(context) is Ok(_))
    }
  }
  assert_identical(quarter.tanpi_ctx(context).0, Binary::one())
  assert_identical(quarter.add(half).tanpi_ctx(context).0, Binary::one().neg())
}

///|
// oracle: A, S
// source: A: tanPi(1/4) = 1 exactly with no inexact and sinPi(1/4) = cosPi(1/4) = sqrt(2)/2 (irrational, so inexact) in the five directions at 24 bits; S: the ordering of the five sine results (toward zero equals toward negative, downward <= nearest <= upward) compares the code under test with itself
// shares: Binary::make and one build the operands; sinpi_ctx, cospi_ctx and tanpi_ctx are the code under test; assert_identical, compare and the flag accessors read the result
test "Binary pi-scaled quarter honors every rounding mode" {
  let quarter = Binary::make(BinCoeff::one(), -2, 53)
  let modes = [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
  ]
  let sines : Array[Binary] = []
  for mode in modes {
    let context = BinaryContext::new(precision=24, rounding=mode)
    let (sine, sine_flags) = quarter.sinpi_ctx(context)
    let (cosine, cosine_flags) = quarter.cospi_ctx(context)
    let (tangent, tangent_flags) = quarter.tanpi_ctx(context)
    assert_identical(sine, cosine)
    assert_true(sine_flags.inexact())
    assert_true(cosine_flags.inexact())
    assert_identical(tangent, Binary::one(precision=24))
    assert_true(!tangent_flags.inexact())
    sines.push(sine)
  }
  assert_identical(sines[2], sines[4])
  assert_true(sines[4].compare(sines[0]) <= 0)
  assert_true(sines[0].compare(sines[3]) <= 0)
  assert_true(sines[4].compare(sines[1]) <= 0)
  assert_true(sines[1].compare(sines[3]) <= 0)
}

///|
// oracle: S
// source: sin(2^20) in binary64 is a finite number of magnitude at most 1 (a property of the sine, no value stated)
// shares: Binary::make builds the argument; try_sin_ctx is the code under test; classify, abs and compare read the result
test "Binary trigonometric reduction certifies arguments beyond linear reduction" {
  let value = Binary::make(BinCoeff::one(), 20, 53)
  match value.try_sin_ctx(BinaryContext::binary64()) {
    Ok((result, _)) => {
      assert_true(result.classify() == FpClass::Finite)
      assert_true(result.abs().compare(Binary::one()) <= 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
// oracle: S
// source: the written contract of the certification failure of this library: cos(2^8100000) in binary64 exceeds the resource limit of the range reduction and reports the operation cos, the stage RangeReduction, the reason ResourceLimit, the target precision 53 and a positive work precision; a rule of this library, not of the standard
// shares: Binary::make builds the argument; try_cos_ctx is the code under test; certification_failure_detail and its accessors read the failure
test "Binary trigonometric resource failure retains proof details" {
  let value = Binary::make(BinCoeff::one(), 8_100_000, 53)
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
// oracle: A
// source: written out: for x = 2^-200, expm1(x) = x + x^2/2 and log1p(x) = x - x^2/2 are positive and nonzero, and the mirrored values for -x are nonzero (the result of a nonzero tiny argument is not flushed to zero)
// shares: Binary::make and neg build the operands; expm1 and log1p are the code under test; is_zero and signum read the result
test "Binary expm1 and log1p preserve tiny nonzero inputs" {
  let tiny = Binary::make(BinCoeff::one(), -200, 53)
  let positive_expm1 = tiny.expm1()
  let positive_log1p = tiny.log1p()
  assert_true(!positive_expm1.is_zero())
  assert_true(!positive_log1p.is_zero())
  assert_true(positive_expm1.signum() == Sign::Positive)
  assert_true(positive_log1p.signum() == Sign::Positive)
  assert_true(!tiny.neg().expm1().is_zero())
  assert_true(!tiny.neg().log1p().is_zero())
}

///|
// oracle: A, S
// source: A: written out: 1 and 9/8 at 4 bits rounded to 3 bits in nearest even are both 1 (9/8 is the midpoint of 1 and 5/4, a tie to the even 1) and only the second is inexact; S: the uniqueness verdict false is the written contract of binary_certified_target_rounding (equal values with unequal flags are not a unique target)
// shares: Binary::one and Binary::make with BinCoeff::from_uint64 build the endpoints; binary_certified_target_rounding is the code under test; assert_identical and the flag accessor read the result
test "certified target witness rejects equal values with unequal flags" {
  let context = BinaryContext::new(precision=3)
  let exact = Binary::one(precision=4)
  let midpoint = Binary::make(BinCoeff::from_uint64(9UL), -3, 4)
  let (rounded, unique, flags) = binary_certified_target_rounding(
    exact, midpoint, context,
  )
  assert_identical(rounded, Binary::one(precision=3))
  assert_false(unique)
  assert_true(flags.inexact())
}

///|
fn certified_rounding_endpoint(coefficient : UInt64) -> Binary {
  // coefficient * 2^-4 at precision 8
  Binary::make(BinCoeff::from_uint64(coefficient), -4, 8)
}

///|
// oracle: A
// source: expected values written out from arithmetic on the grid of a 3-bit significand in [1, 2), spacing
//   2^-2 (1, 1.25, 1.5, 1.75); the endpoints are k/16 (17/16 and 18/16 round to 1, 18/16 is the midpoint of
//   1 and 1.25 and ties to even; 19/16 rounds to 1.25); the rule under test is that a witness is unique only
//   if both endpoints round to the same value with the same flags
// shares: nothing (only the call under test and Binary::make for the endpoints)
// (These blocks replace tests of a local copy of the function in interval/certified_rounding_wbtest.mbt,
// which ignored the flags.)
test "certified target rounding accepts one rounded value with equal flags" {
  let context = BinaryContext::new(precision=3)
  // 17/16 and 18/16 both round to 1, both inexact
  let (value, unique, flags) = binary_certified_target_rounding(
    certified_rounding_endpoint(17UL),
    certified_rounding_endpoint(18UL),
    context,
  )
  assert_true(unique)
  assert_identical(value, Binary::one(precision=3))
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
// oracle: A
// source: values written out on the 3-bit grid of the block above: 17/16 and 19/16 lie strictly between 1 and
//   1.25 and are inexact, so downward both give 1 and upward both give 1.25; 16/16 is exact and 17/16 is not, so
//   the flags differ in either direction
// shares: nothing (only the call under test and Binary::make for the endpoints)
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
  assert_identical(down_value, Binary::one(precision=3))
  let (up_value, up_unique, _) = binary_certified_target_rounding(
    low, high, upward,
  )
  assert_true(up_unique)
  assert_identical(up_value, Binary::make(BinCoeff::from_uint64(5UL), -2, 3))
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
// oracle: S
// source: exp(1) at 24 bits in the five directions: round toward zero equals round toward negative for a positive value, and the results are ordered downward <= nearest <= upward, with inexact for the directed ones; the directions compare one function with itself, no value is stated
// shares: Binary::one builds the operand; exp_ctx is the code under test; assert_identical, compare and the flag accessors read the result
test "Binary elementary functions honor every directed rounding mode" {
  let value = Binary::one(precision=53)
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
  assert_identical(toward_zero.0, downward.0)
  assert_true(downward.0.compare(ties_even.0) <= 0)
  assert_true(ties_even.0.compare(upward.0) <= 0)
  assert_true(downward.0.compare(ties_away.0) <= 0)
  assert_true(ties_away.0.compare(upward.0) <= 0)
  assert_true(downward.1.inexact())
  assert_true(upward.1.inexact())
}
