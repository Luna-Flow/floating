///|
/// A right operand taken as it is: no context is applied (`from_decimal` would
/// quiet a signaling NaN and raise `invalid_operation` before the operation).
/// The context of a right pipeline is not used by the operation.
fn lift(value : @decimal.Decimal) -> DecimalChecked {
  DecimalChecked::from_outcome(
    value,
    @decimal.DecimalContext::decimal64(),
    @decimal.DecimalFlags::new(),
  )
}

///|
test "decimal checked preserves IEEE defined results" {
  let context = @decimal.DecimalContext::decimal64()
  let result = DecimalChecked::from_int(1, context).div(
    lift(@decimal.Decimal::zero()),
  )
  assert_true(result.value().is_infinite())
  assert_true(result.raised().division_by_zero())
  assert_true(result.flags().division_by_zero())
}

///|
test "decimal checked accumulates IEEE flags" {
  let context = @decimal.DecimalContext::new(precision=3)
  let parsed = DecimalChecked::parse("1.2345", context)
  let result = parsed.add(lift(@decimal.Decimal::zero()))
  let cleared = result.clear_flags()
  assert_false(cleared.flags().has_error())
}

///|
test "decimal checked parse keeps conversion result and flags" {
  let result = DecimalChecked::parse(
    "not-a-decimal",
    @decimal.DecimalContext::decimal64(),
  )
  assert_true(result.value().is_nan())
  assert_true(result.raised().invalid_operation())
}

///|
test "decimal checked elementary mirrors preserve results" {
  let context = @decimal.DecimalContext::decimal64()
  let result = DecimalChecked::from_int(10, context).exp2()
  assert_true(result.is_ok())
  assert_false(result.is_err())
  assert_eq(result.value().compare(@decimal.Decimal::from_int(1024)), 0)
  match result.result() {
    Ok((value, _)) =>
      assert_eq(value.compare(@decimal.Decimal::from_int(1024)), 0)
    Err(_) => assert_true(false)
  }
}

///|
test "decimal checked pi-scaled and binary mirrors are additive" {
  let context = @decimal.DecimalContext::decimal64()
  let half = @decimal.Decimal::from_string("0.5").unwrap()
  let tangent = DecimalChecked::from_decimal(half, context).tanpi()
  assert_true(tangent.value().is_infinite())
  assert_true(tangent.raised().division_by_zero())
  let hypot = DecimalChecked::from_int(3, context).hypot(
    lift(@decimal.Decimal::from_int(4)),
  )
  assert_eq(hypot.value().compare(@decimal.Decimal::from_int(5)), 0)
}

///|
test "decimal checked atan2 accepts infinite operands" {
  let context = @decimal.DecimalContext::decimal64()
  let result = DecimalChecked::from_decimal(
    @decimal.Decimal::from_string("Inf").unwrap(),
    context,
  ).atan2(lift(@decimal.Decimal::from_string("-Inf").unwrap()))
  inspect(result.value(), content="2.356194490192345")
  assert_false(result.flags().has_error())
}

///|
test "decimal checked exp2m1 exp10m1 log2p1 log10p1 mirror the try forms" {
  // IEEE 754-2019 9.2: the checked methods record the result and the flags of
  // Decimal::try_*_ctx; log2p1(-1) and log10p1(-1) are poles (9.2.1).
  let context = @decimal.DecimalContext::decimal64()
  inspect(DecimalChecked::from_int(4, context).exp2m1().value(), content="15")
  inspect(DecimalChecked::from_int(2, context).exp10m1().value(), content="99")
  inspect(
    DecimalChecked::from_int(1023, context).log2p1().value(),
    content="10",
  )
  inspect(DecimalChecked::from_int(999, context).log10p1().value(), content="3")
  let half = DecimalChecked::from_decimal(
    @decimal.Decimal::from_string("0.5").unwrap(),
    context,
  ).exp2m1()
  inspect(half.value(), content="0.4142135623730950")
  assert_true(half.raised().inexact())
  let pole = DecimalChecked::from_int(-1, context).log2p1()
  assert_true(pole.value().is_infinite())
  assert_true(pole.raised().division_by_zero())
  let ten_pole = DecimalChecked::from_int(-1, context).log10p1()
  assert_true(ten_pole.raised().division_by_zero())
}

///|
test "decimal checked rsqrt compound powr mirror the try forms" {
  // IEEE 754-2019 9.2: the checked methods record the result and flags of
  // Decimal::try_*_ctx; rSqrt(+-0) and compound(-1, n < 0) are poles (9.2.1).
  let context = @decimal.DecimalContext::decimal64()
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  inspect(
    DecimalChecked::from_decimal(d("0.25"), context).rsqrt().value(),
    content="2",
  )
  inspect(
    DecimalChecked::from_decimal(d("0.1"), context).compound(2).value(),
    content="1.21",
  )
  inspect(
    DecimalChecked::from_int(8, context).powr(lift(d("0.5"))).value(),
    content="2.828427124746190",
  )
  let pole = DecimalChecked::from_int(0, context).rsqrt()
  assert_true(pole.raised().division_by_zero())
  let compound_pole = DecimalChecked::from_int(-1, context).compound(-2)
  assert_true(compound_pole.raised().division_by_zero())
  let invalid = DecimalChecked::from_int(0, context).powr(lift(d("0")))
  assert_true(invalid.raised().invalid_operation())
}

///|
test "decimal checked minimum_number and maximum_number treat a quiet NaN as missing" {
  let context = @decimal.DecimalContext::decimal64()
  let two = @decimal.Decimal::from_int(2)
  let qnan = @decimal.Decimal::quiet_nan(payload=5N)
  let minimum = DecimalChecked::from_decimal(qnan, context).minimum_number(
    lift(two),
  )
  let maximum = DecimalChecked::from_decimal(two, context).maximum_number(
    lift(qnan),
  )
  assert_eq(minimum.value().to_string(), "2")
  assert_eq(maximum.value().to_string(), "2")
  assert_false(minimum.raised().invalid_operation())
  assert_false(maximum.raised().invalid_operation())
  let both = DecimalChecked::from_decimal(qnan, context).maximum_number(
    lift(qnan),
  )
  assert_true(both.value().is_quiet_nan())
}

///|
test "decimal checked minimum_number and maximum_number return the number for a signaling NaN and signal invalid" {
  let context = @decimal.DecimalContext::decimal64()
  let two = @decimal.Decimal::from_int(2)
  let snan = @decimal.Decimal::signaling_nan(payload=7N)
  let minimum = DecimalChecked::from_decimal(two, context).minimum_number(
    lift(snan),
  )
  let maximum = DecimalChecked::from_decimal(two, context).maximum_number(
    lift(snan),
  )
  assert_eq(minimum.value().to_string(), "2")
  assert_eq(maximum.value().to_string(), "2")
  assert_true(minimum.raised().invalid_operation())
  assert_true(maximum.raised().invalid_operation())
  let both = DecimalChecked::from_decimal(
    @decimal.Decimal::quiet_nan(payload=9N),
    context,
  ).minimum_number(lift(snan))
  assert_true(both.value().is_quiet_nan())
  assert_true(both.raised().invalid_operation())
}

///|
test "decimal checked minimum_number and maximum_number order signed zeros and keep a cohort tie numerically equal" {
  let context = @decimal.DecimalContext::decimal64()
  let negative_zero = @decimal.Decimal::negative_zero()
  let positive_zero = @decimal.Decimal::zero()
  let minimum = DecimalChecked::from_decimal(positive_zero, context).minimum_number(
    lift(negative_zero),
  )
  let maximum = DecimalChecked::from_decimal(negative_zero, context).maximum_number(
    lift(positive_zero),
  )
  assert_true(minimum.value().is_negative())
  assert_false(maximum.value().is_negative())
  let one = @decimal.Decimal::from_string("1.0").unwrap()
  let one_more = @decimal.Decimal::from_string("1.00").unwrap()
  let tie_min = DecimalChecked::from_decimal(one, context).minimum_number(
    lift(one_more),
  )
  let tie_max = DecimalChecked::from_decimal(one, context).maximum_number(
    lift(one_more),
  )
  assert_eq(tie_min.value().compare(one), 0)
  assert_eq(tie_max.value().compare(one), 0)
  assert_true(tie_min.is_ok() && tie_max.is_ok())
}

///|
/// S4: a case IEEE 754-2019 defines as invalid is a value with `invalid_operation`
/// and no error; a context beyond the kernels is the error (the certification
/// failure kind, not the domain error); an ordinary case has neither.
test "decimal checked elementary: domain case, could-not-compute case and ordinary case" {
  let context = @decimal.DecimalContext::decimal64()
  let domain = DecimalChecked::from_decimal(
    @decimal.Decimal::from_int(-1, precision=16),
    context,
  ).ln()
  assert_true(domain.value().is_nan())
  assert_true(domain.flags().invalid_operation())
  assert_false(domain.flags().not_computed())
  assert_true(domain.error() is None)
  let restricted = DecimalChecked::from_decimal(
    @decimal.Decimal::from_int(2, precision=16),
    @decimal.DecimalContext::new(precision=34, e_max=1_000_000),
  ).exp()
  match restricted.error() {
    Some(error) => {
      assert_true(error.is_certification_failure())
      assert_false(error.is_domain_error())
    }
    None => abort("a context beyond the kernels must be an error")
  }
  let ordinary = DecimalChecked::from_decimal(
    @decimal.Decimal::from_int(1, precision=16),
    context,
  ).exp()
  assert_true(ordinary.error() is None)
  assert_false(
    ordinary.flags().invalid_operation() || ordinary.flags().not_computed(),
  )
}

///|
// oracle: A
// source: written out by hand: 1 / 0 is infinity with division_by_zero (IEEE 754-2019 7.3), so 1 + inf is infinity; 1 + 1.2345 in three digits is 2.23 (the right pipeline is converted at decimal64, the sum is rounded in the left context)
// shares: nothing
test "decimal checked right operand: conditions of the right pipeline join the result (S9)" {
  let context = @decimal.DecimalContext::decimal64()
  // the right pipeline raised division_by_zero (1 / 0 = inf); 1 + inf = inf
  let right = DecimalChecked::from_int(1, context).div(
    DecimalChecked::from_int(0, context),
  )
  assert_true(right.raised().division_by_zero())
  let sum = DecimalChecked::from_int(1, context).add(right)
  assert_true(sum.value().is_infinite())
  assert_true(sum.raised().division_by_zero())
  assert_true(sum.flags().division_by_zero())
  // the result is in the context of the left pipeline
  let narrow = @decimal.DecimalContext::new(precision=3)
  let left = DecimalChecked::from_int(1, narrow)
  let total = left.add(DecimalChecked::parse("1.2345", context))
  assert_eq(total.value().to_string(), "2.23")
  assert_eq(total.context().precision(), 3)
}

///|
// oracle: A
// source: by hand: a pipeline in error keeps its error (left first, else right); the value of the left pipeline is kept when the right one failed
// shares: nothing
test "decimal checked right operand: an error of either pipeline stops the operation (S9)" {
  let context = @decimal.DecimalContext::decimal64()
  // an Err pipeline: an ordinary operand in a context beyond the limit of the
  // elementary functions is not computed
  let wide = @decimal.DecimalContext::new(precision=34, e_max=999_999_999)
  let err = DecimalChecked::from_int(2, wide).exp()
  assert_true(err.is_err())
  let one = DecimalChecked::from_int(1, context)
  let left_failed = err.add(one)
  assert_true(left_failed.is_err())
  let right_failed = one.add(err)
  assert_true(right_failed.is_err())
  assert_eq(right_failed.value().to_string(), "1")
  // the error of the left pipeline comes first
  let both = err.mul(err)
  assert_true(both.is_err())
  // fma takes the first error among its operands
  let fused = one.fma(one, err)
  assert_true(fused.is_err())
  let good = one.fma(
    DecimalChecked::from_int(2, context),
    DecimalChecked::from_int(3, context),
  )
  assert_eq(good.value().to_string(), "5")
}

///|
// oracle: A
// source: written out by hand at three digits, half-even: the exact sum 1.00 + 0.24500001 = 1.24500001 is above the tie 1.245, so it rounds to 1.25; the operand lifted at three digits becomes 0.245 (inexact), and 1.00 + 0.245 = 1.245 is a tie that rounds to the even digit, 1.24
// shares: nothing
test "decimal checked right operand: a wide lift is exact, a narrow lift rounds twice (S9)" {
  let narrow = @decimal.DecimalContext::new(precision=3)
  let wide = @decimal.DecimalContext::decimal128()
  let operand = @decimal.Decimal::from_string("0.24500001").unwrap()
  let left = DecimalChecked::from_decimal(
    @decimal.Decimal::from_string("1.00").unwrap(),
    narrow,
  )
  let exact = left.add(DecimalChecked::from_decimal(operand, wide))
  assert_eq(exact.value().to_string(), "1.25")
  let lifted = DecimalChecked::from_decimal(operand, narrow)
  assert_eq(lifted.value().to_string(), "0.245")
  assert_true(lifted.raised().inexact())
  let twice = left.add(lifted)
  assert_eq(twice.value().to_string(), "1.24")
  assert_true(twice.flags().inexact())
}
