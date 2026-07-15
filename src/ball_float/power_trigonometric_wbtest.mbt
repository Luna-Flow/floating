///|
fn elementary_test_interval(lower : Double, upper : Double) -> BallFloat {
  BallFloat::from_bounds(
    @bin_float.BinFloat::from_double(lower, precision=53),
    @bin_float.BinFloat::from_double(upper, precision=53),
    precision=53,
  )
}

///|
fn expected_binary64(source : String) -> @bin_float.BinFloat {
  match @bin_float.BinFloat::from_hex(source, 53) {
    Ok(value) => value
    Err(_) => abort("invalid expected binary64 literal")
  }
}

///|
fn assert_binary64_bounds(
  actual : BallFloat,
  lower : String,
  upper : String,
) -> Unit raise {
  let rounded = actual.apply_ctx(BallContext::binary64()).0
  assert_eq(rounded.lower_bound().compare(expected_binary64(lower)), 0)
  assert_eq(rounded.upper_bound().compare(expected_binary64(upper)), 0)
}

///|
test "IEEE 1788 general power follows the nonnegative real domain" {
  let base = elementary_test_interval(0.1, 0.5)
  let exponent = elementary_test_interval(0.1, 0.1)
  assert_binary64_bounds(
    base.pow_interval(exponent),
    "0x196B230BCDC434p-53",
    "0x1DDB680117AB13p-53",
  )
  let zero = elementary_test_interval(0.0, 0.0)
  assert_true(zero.pow_interval(elementary_test_interval(0.0, 0.0)).is_empty())
  assert_true(
    zero.pow_interval(elementary_test_interval(1.0, 2.0)).set_equal(zero),
  )
  assert_true(
    elementary_test_interval(-2.0, -1.0)
    .pow_interval(elementary_test_interval(2.0, 2.0))
    .is_empty(),
  )
}

///|
test "certified sine and cosine match ITF1788 directed endpoints" {
  let source = elementary_test_interval(-0.7, 0.1)
  assert_binary64_bounds(
    source.sin_interval(),
    "-0x149D6E694619B9p-53",
    "0x198EAECB8BCB2Dp-56",
  )
  assert_binary64_bounds(source.cos_interval(), "0x187996529F9D92p-53", "0x1p0")
  let crossing_peak = elementary_test_interval(1.0, 2.0).sin_interval()
  assert_eq(crossing_peak.upper_bound().compare(expected_binary64("0x1p0")), 0)
  let pi_lower = expected_binary64("0x1921FB54442D18p-51")
  assert_binary64_bounds(
    BallFloat::exact(pi_lower).sin_interval(),
    "0x11A62633145C06p-105",
    "0x11A62633145C07p-105",
  )
  let half_pi_lower = expected_binary64("0x1921FB54442D18p-52")
  assert_binary64_bounds(
    BallFloat::exact(half_pi_lower).cos_interval(),
    "0x11A62633145C06p-106",
    "0x11A62633145C07p-106",
  )
}

///|
test "certified tangent detects poles and matches monotone branches" {
  let source = elementary_test_interval(-0.33333, 0.1)
  assert_binary64_bounds(
    source.tan_interval(),
    "-0x1628F4FD931FEFp-54",
    "0x19AF8877430B81p-56",
  )
  let below = expected_binary64("0x1921FB54442D18p-52")
  let above = expected_binary64("0x1921FB54442D19p-52")
  assert_binary64_bounds(
    BallFloat::exact(below).tan_interval(),
    "0x1D02967C31CDB4p1",
    "0x1D02967C31CDB5p1",
  )
  assert_true(
    BallFloat::from_bounds(below, above, precision=53)
    .tan_interval()
    .is_entire(),
  )
}

///|
test "trigonometric unbounded and extreme arguments degrade conservatively" {
  assert_true(BallFloat::whole(precision=53).tan_interval().is_entire())
  assert_true(
    BallFloat::whole(precision=53)
    .sin_interval()
    .set_equal(elementary_test_interval(-1.0, 1.0)),
  )
  let extreme = BallFloat::exact(
    @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), 70000, 53),
    precision=53,
  )
  assert_true(
    extreme.cos_interval().set_equal(elementary_test_interval(-1.0, 1.0)),
  )
  match extreme.try_cos_interval() {
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
