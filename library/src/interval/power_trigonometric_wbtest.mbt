///|
fn elementary_test_interval(lower : Double, upper : Double) -> Interval {
  Interval::from_bounds(
    @binary.Binary::from_double(lower, precision=53),
    @binary.Binary::from_double(upper, precision=53),
    precision=53,
  )
}

///|
fn expected_binary64(source : String) -> @binary.Binary {
  match @binary.Binary::from_hex(source, 53) {
    Ok(value) => value
    Err(_) => abort("invalid expected binary64 literal")
  }
}

///|
fn assert_binary64_bounds(
  actual : Interval,
  lower : String,
  upper : String,
) -> Unit raise {
  let rounded = actual.apply_ctx(IntervalContext::binary64()).0
  assert_eq(rounded.lower_bound().compare(expected_binary64(lower)), 0)
  assert_eq(rounded.upper_bound().compare(expected_binary64(upper)), 0)
}

///|
// oracle: A
// source: the end values are the directed 53-bit hulls of 0.1^0.1 (RD 0x196B230BCDC434p-53) and 0.5^0.1 (RU 0x1DDB680117AB13p-53), checked with MPFR 4.2.2 (mpfr_pow at RNDD and RNDU of the exact double operands) for this audit and the cases of the ITF1788 power tests; the rest is written out from the domain of the general power (Table 9.1): 0^0 has no value (Empty), 0^[1, 2] = {0}, a negative base with the exponent 2 is outside the domain (Empty)
// shares: elementary_test_interval (Binary::from_double and Interval::from_bounds), expected_binary64 (Binary::from_hex) and assert_binary64_bounds (apply_ctx with IntervalContext::binary64, Binary::compare) build the inputs and compare; the elementary function under test is the code under test
test "IEEE 1788 general power follows the nonnegative real domain" {
  let base = elementary_test_interval(0.1, 0.5)
  let exponent = elementary_test_interval(0.1, 0.1)
  assert_binary64_bounds(
    base.pow(exponent),
    "0x196B230BCDC434p-53",
    "0x1DDB680117AB13p-53",
  )
  let zero = elementary_test_interval(0.0, 0.0)
  assert_true(zero.pow(elementary_test_interval(0.0, 0.0)).is_empty())
  assert_true(zero.pow(elementary_test_interval(1.0, 2.0)).equal(zero))
  assert_true(
    elementary_test_interval(-2.0, -1.0)
    .pow(elementary_test_interval(2.0, 2.0))
    .is_empty(),
  )
}

///|
// oracle: A
// source: written out by hand from the general power over the reals (Table 9.1): [-0, 0.5]^[-1, 0.1] has the lower bound 0 (the point 0 gives 0^0.1 = 0 and the base 0.5 gives 0.5^0.1 below 1) and the upper bound +inf (0^-1 is unbounded); the signed zero is the real 0
// shares: elementary_test_interval (Binary::from_double and Interval::from_bounds), expected_binary64 (Binary::from_hex) and assert_binary64_bounds (apply_ctx with IntervalContext::binary64, Binary::compare) build the inputs and compare; the elementary function under test is the code under test
test "general power treats negative zero as the real interval endpoint zero" {
  let negative_zero = @binary.Binary::negative_zero(precision=53)
  let base = Interval::from_bounds(
    negative_zero,
    @binary.Binary::from_double(0.5, precision=53),
    precision=53,
  )
  let exponent = elementary_test_interval(-1.0, 0.1)
  assert_binary64_bounds(base.pow(exponent), "0x0p0", "inf")
}

///|
// oracle: A
// source: the end values of sin and cos of [-0.7, 0.1] (-0x149D6E694619B9p-53, 0x198EAECB8BCB2Dp-56 and 0x187996529F9D92p-53, 0x1p0), of sin(RD(pi)) = 0x11A62633145C06p-105 and 0x11A62633145C07p-105 and of cos(RD(pi/2)) at -106 are the directed 53-bit values of the ITF1788 sine and cosine tests, checked with MPFR 4.2.2 (mpfr_sin and mpfr_cos at RNDD and RNDU of the exact operands) for this audit; the upper end 1 of sin [1, 2] is written by hand (the peak pi/2 lies inside)
// shares: elementary_test_interval (Binary::from_double and Interval::from_bounds), expected_binary64 (Binary::from_hex) and assert_binary64_bounds (apply_ctx with IntervalContext::binary64, Binary::compare) build the inputs and compare; the elementary function under test is the code under test
test "certified sine and cosine match ITF1788 directed endpoints" {
  let source = elementary_test_interval(-0.7, 0.1)
  assert_binary64_bounds(
    source.sin(),
    "-0x149D6E694619B9p-53",
    "0x198EAECB8BCB2Dp-56",
  )
  assert_binary64_bounds(source.cos(), "0x187996529F9D92p-53", "0x1p0")
  let crossing_peak = elementary_test_interval(1.0, 2.0).sin()
  assert_eq(crossing_peak.upper_bound().compare(expected_binary64("0x1p0")), 0)
  let pi_lower = expected_binary64("0x1921FB54442D18p-51")
  assert_binary64_bounds(
    Interval::exact(pi_lower).sin(),
    "0x11A62633145C06p-105",
    "0x11A62633145C07p-105",
  )
  let half_pi_lower = expected_binary64("0x1921FB54442D18p-52")
  assert_binary64_bounds(
    Interval::exact(half_pi_lower).cos(),
    "0x11A62633145C06p-106",
    "0x11A62633145C07p-106",
  )
}

///|
// oracle: A
// source: the end values of tan [-0.33333, 0.1] (-0x1628F4FD931FEFp-54, 0x19AF8877430B81p-56) and of tan(RD(pi/2)) (0x1D02967C31CDB4p1, 0x1D02967C31CDB5p1) are the directed 53-bit values of the ITF1788 tangent tests, checked with MPFR 4.2.2 (mpfr_tan at RNDD and RNDU of the exact operands) for this audit; an interval holding both neighbours of pi/2 straddles the pole, so tan is Entire (written out)
// shares: elementary_test_interval (Binary::from_double and Interval::from_bounds), expected_binary64 (Binary::from_hex) and assert_binary64_bounds (apply_ctx with IntervalContext::binary64, Binary::compare) build the inputs and compare; the elementary function under test is the code under test
test "certified tangent detects poles and matches monotone branches" {
  let source = elementary_test_interval(-0.33333, 0.1)
  assert_binary64_bounds(
    source.tan(),
    "-0x1628F4FD931FEFp-54",
    "0x19AF8877430B81p-56",
  )
  let below = expected_binary64("0x1921FB54442D18p-52")
  let above = expected_binary64("0x1921FB54442D19p-52")
  assert_binary64_bounds(
    Interval::exact(below).tan(),
    "0x1D02967C31CDB4p1",
    "0x1D02967C31CDB5p1",
  )
  assert_true(
    Interval::from_bounds(below, above, precision=53).tan().is_entire(),
  )
}

///|
// oracle: A,S
// source: tan of Entire is Entire and sin of Entire is [-1, 1], cos at 2^8,100,000 is [-1, 1] (written out by hand: no range reduction is possible, the whole range is the conservative answer); the failure record of try_cos (operation cos, stage RangeReduction, reason ResourceLimit, refinements 0, work precision above 53) is the implementation's own description and is checked for self-consistency only (level S)
// shares: elementary_test_interval (Binary::from_double and Interval::from_bounds), expected_binary64 (Binary::from_hex) and assert_binary64_bounds (apply_ctx with IntervalContext::binary64, Binary::compare) build the inputs and compare; the elementary function under test is the code under test
test "trigonometric unbounded and extreme arguments degrade conservatively" {
  assert_true(Interval::entire(precision=53).tan().is_entire())
  assert_true(
    Interval::entire(precision=53)
    .sin()
    .equal(elementary_test_interval(-1.0, 1.0)),
  )
  let extreme = Interval::exact(
    @binary.Binary::make(@binary.BinCoeff::one(), 8_100_000, 53),
    precision=53,
  )
  assert_true(extreme.cos().equal(elementary_test_interval(-1.0, 1.0)))
  match extreme.try_cos() {
    Err(error) => {
      let detail = error.certification_failure_detail().unwrap()
      assert_eq(detail.operation(), "cos")
      assert_true(detail.stage() == @def.CertificationStage::RangeReduction)
      assert_true(
        detail.reason() == @def.CertificationFailureReason::ResourceLimit,
      )
      assert_eq(detail.target_precision(), 53)
      assert_true(detail.work_precision() > detail.target_precision())
      assert_eq(detail.refinements(), 0)
    }
    Ok(_) => fail("checked cosine must report the range-reduction limit")
  }
}
