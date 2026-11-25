///|
// oracle: A
// source: IEEE 1788-2015 10.2 (4) requires lower bound < +infinity and upper bound > -infinity, so [inf, inf] and [-inf, -inf] are not intervals, so both calls must be Err; written out, not compared with the plain tier
// shares: Binary::inf builds the inputs; IntervalChecked::from_bounds is the code under test
test "IEEE 1788 rejects infinity singleton bounds" {
  let precision = 32
  let positive_infinity = @binary.Binary::inf(precision~)
  let negative_infinity = @binary.Binary::inf(negative=true, precision~)
  let positive_result = IntervalChecked::from_bounds(
    positive_infinity,
    positive_infinity,
    precision~,
  )
  assert_true(positive_result.result() is Err(_))
  let negative_result = IntervalChecked::from_bounds(
    negative_infinity,
    negative_infinity,
    precision~,
  )
  assert_true(negative_result.result() is Err(_))
}

///|
// oracle: S
// source: only Err is checked: a NaN is not a number, so no interval contains it; the earlier comparison with Interval::try_exact (the function wrapped) is removed
// shares: Binary::nan builds the input; IntervalChecked::exact is the code under test
test "checked exact construction shares Interval validation" {
  let value = @binary.Binary::nan(precision=32)
  let result = IntervalChecked::exact(value, precision=32)
  assert_true(result.result() is Err(_))
}

///|
// oracle: S
// source: only the error kind of rootn(8, 0) is checked: the zeroth root is undefined, a domain error; no numeric value
// shares: IntervalChecked::from_int builds the input; rootn and the error accessors are the code under test
test "checked elementary mirrors preserve domain errors" {
  let result = IntervalChecked::from_int(8).rootn(0)
  assert_true(result.is_err())
  assert_false(result.is_ok())
  assert_true(result.error() is Some(_))
  match result.result() {
    Err(error) => assert_true(error.is_domain_error())
    Ok(_) => assert_true(false)
  }
}

///|
// oracle: S
// source: the detail of a certification failure of cos at 2^8100000 (operation name, resource limit, zero refinements); no numeric value; the cutoff is the implementation limit
// shares: IntervalChecked::exact, Binary::make and BinCoeff::one build the input; cos and the failure detail accessors are the code under test
test "checked trigonometric mirrors preserve certification failures" {
  let extreme = IntervalChecked::exact(
    @binary.Binary::make(@binary.BinCoeff::one(), 8_100_000, 53),
    precision=53,
  ).cos()
  assert_true(extreme.is_err())
  let detail = extreme.error().unwrap().certification_failure_detail().unwrap()
  assert_eq(detail.operation(), "cos")
  assert_true(detail.reason() == @def.CertificationFailureReason::ResourceLimit)
  assert_eq(detail.refinements(), 0)
}
