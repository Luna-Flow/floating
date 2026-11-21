///|
test "IEEE 1788 rejects infinity singleton bounds" {
  let precision = 32
  let positive_infinity = @binary.Binary::inf(precision~)
  let negative_infinity = @binary.Binary::inf(negative=true, precision~)
  let positive_result = IntervalResult::from_bounds(
    positive_infinity,
    positive_infinity,
    precision~,
  )
  assert_true(positive_result.result() is Err(_))
  assert_true(
    positive_result.result() ==
    @interval.Interval::try_from_bounds(
      positive_infinity,
      positive_infinity,
      precision~,
    ),
  )
  let negative_result = IntervalResult::from_bounds(
    negative_infinity,
    negative_infinity,
    precision~,
  )
  assert_true(negative_result.result() is Err(_))
  assert_true(
    negative_result.result() ==
    @interval.Interval::try_from_bounds(
      negative_infinity,
      negative_infinity,
      precision~,
    ),
  )
}

///|
test "checked exact construction shares Interval validation" {
  let value = @binary.Binary::nan(precision=32)
  let result = IntervalResult::exact(value, precision=32)
  assert_true(result.result() is Err(_))
  assert_true(
    result.result() == @interval.Interval::try_exact(value, precision=32),
  )
}

///|
test "checked elementary mirrors preserve domain errors" {
  let result = IntervalResult::from_int(8).rootn(0)
  assert_true(result.is_err())
  assert_false(result.is_ok())
  assert_true(result.error() is Some(_))
  match result.result() {
    Err(error) => assert_true(error.is_domain_error())
    Ok(_) => assert_true(false)
  }
}

///|
test "checked trigonometric mirrors preserve certification failures" {
  let extreme = IntervalResult::exact(
    @binary.Binary::make(@binary.BinCoeff::one(), 8_100_000, 53),
    precision=53,
  ).cos()
  assert_true(extreme.is_err())
  let detail = extreme.error().unwrap().certification_failure_detail().unwrap()
  assert_eq(detail.operation(), "cos")
  assert_true(detail.reason() == @def.CertificationFailureReason::ResourceLimit)
  assert_eq(detail.refinements(), 0)
}
