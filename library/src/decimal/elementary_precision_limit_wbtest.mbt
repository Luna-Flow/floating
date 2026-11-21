///|
// oracle: A
// source: written out by hand. The getter, the setter, `==` and the builders are the contract of `DecimalContext::with_elementary_precision_limit` (default `Some(999_999)`, `None` removes the limit); contexts that differ only in the limit are different values, as for `refinement_limit`.
// shares: nothing
test "the elementary precision limit is a field of the context" {
  let base = DecimalContext::new(precision=34)
  assert_eq(base.elementary_precision_limit(), Some(999_999))
  let open = base.with_elementary_precision_limit(None)
  assert_eq(open.elementary_precision_limit(), None)
  assert_false(base == open)
  assert_true(base == base.with_elementary_precision_limit(Some(999_999)))
  let low = base.with_elementary_precision_limit(Some(100))
  assert_false(base == low)
  // the builders keep it
  assert_eq(low.with_precision(50).elementary_precision_limit(), Some(100))
  assert_eq(low.with_e_max(500).elementary_precision_limit(), Some(100))
  assert_eq(
    low
    .with_rounding(DecimalRoundingMode::RoundTowardPositive)
    .elementary_precision_limit(),
    Some(100),
  )
}

///|
// oracle: A
// source: written out by hand: 2^3 = 8 is exact, and the operands have one digit, so the exact power costs a few one-digit products whatever the precision of the context (rounding to 1,000,001 digits is the identity on `8`); the default limit refuses a precision above 999,999, `Some(2_000_000)` and `None` serve it, `Some(100)` refuses above 100 digits. The refusal is the certification failure, at once.
// shares: nothing
test "the pow family follows the precision limit of the context" {
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  let wide = DecimalContext::new(precision=1_000_001, e_max=999_999_999)
  assert_true(d("2").try_pow_ctx(d("3"), wide) is Err(_))
  assert_true(d("2").try_pown_ctx(3, wide) is Err(_))
  for limit in [Some(2_000_000), None] {
    let served = wide.with_elementary_precision_limit(limit)
    assert_eq(d("2").pow_ctx(d("3"), served).0.to_string(), "8")
    assert_eq(d("2").pown_ctx(3, served).0.to_string(), "8")
  }
  let low = DecimalContext::new(precision=101).with_elementary_precision_limit(
    Some(100),
  )
  match d("2").try_pow_ctx(d("3"), low) {
    Err(error) => assert_true(error.is_certification_failure())
    Ok(_) => abort("101 digits is above a limit of 100")
  }
  let at = DecimalContext::new(precision=100).with_elementary_precision_limit(
    Some(100),
  )
  assert_eq(d("2").pow_ctx(d("3"), at).0.to_string(), "8")
}

///|
// oracle: A
// source: written out by hand. `exp` of an ordinary operand follows the same limit (the precision part of the restricted-context test); at 100 digits with `Some(100)` it computes (exp(0.5) starts 1.6487212707), at 101 digits it is refused. No million-digit `exp` is run.
// shares: nothing
test "an elementary function follows the same knob" {
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  let default_wide = DecimalContext::new(precision=1_000_000, e_max=999_999_999)
  assert_true((d("0.5").try_exp_ctx(default_wide) is Ok(_)) == false)
  let low = DecimalContext::new(precision=101).with_elementary_precision_limit(
    Some(100),
  )
  assert_true(d("0.5").try_exp_ctx(low) is Err(_))
  let at = DecimalContext::new(precision=100).with_elementary_precision_limit(
    Some(100),
  )
  match d("0.5").try_exp_ctx(at) {
    Ok((value, _)) => assert_true(value.to_string().has_prefix("1.6487212707"))
    Err(_) => abort("exp(0.5) at 100 digits with a limit of 100 must compute")
  }
}

///|
// oracle: A
// source: IEEE 754-2019 9.2.1 written out: exp(+inf) is +inf, ln(1) is +0, pow(x, +-0) is 1 for any x that is not a signaling NaN, pow(+1, y) is 1; these are values whatever the limit
// shares: nothing
test "the listed special cases are values whatever the limit" {
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  for limit in [Some(10), Some(999_999), None] {
    let ctx = DecimalContext::new(precision=101).with_elementary_precision_limit(
      limit,
    )
    assert_eq(d("Infinity").exp_ctx(ctx).0.to_string(), "inf")
    assert_eq(d("1").ln_ctx(ctx).0.to_string(), "0")
    assert_eq(d("7").pow_ctx(d("0"), ctx).0.to_string(), "1")
    assert_eq(d("1").pow_ctx(d("0.5"), ctx).0.to_string(), "1")
  }
}
