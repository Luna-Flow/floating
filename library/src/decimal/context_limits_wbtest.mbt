///|
test "decimal implementation limits have the documented values" {
  assert_eq(decimal_context_e_max_limit, 999_999_999)
  assert_eq(decimal_context_e_min_limit, -999_999_998)
  assert_eq(decimal_precision_max, 999_999_999)
}

///|
test "DecimalContext::try_new accepts the limits and rejects one beyond" {
  match
    DecimalContext::try_new(
      precision=decimal_precision_max,
      e_max=decimal_context_e_max_limit,
    ) {
    Ok(ctx) => {
      assert_eq(ctx.precision(), decimal_precision_max)
      assert_eq(ctx.e_min(), decimal_context_e_min_limit)
      assert_eq(ctx.e_max(), decimal_context_e_max_limit)
    }
    Err(_) => fail("the documented limits must be accepted")
  }
  assert_true(
    DecimalContext::try_new(
      precision=decimal_precision_max + 1,
      e_max=decimal_context_e_max_limit,
    )
    is Err(_),
  )
  assert_true(
    DecimalContext::try_new(e_max=decimal_context_e_max_limit + 1) is Err(_),
  )
  assert_true(DecimalContext::try_new(e_max=0) is Err(_))
  assert_true(DecimalContext::try_new(e_max=1) is Ok(_))
}

///|
test "DecimalContext::try_new messages state the limits" {
  match DecimalContext::try_new(precision=0) {
    Err(error) =>
      assert_eq(error.message, "precision must be within 1..=999999999")
    Ok(_) => fail("precision 0 must be rejected")
  }
  match DecimalContext::try_new(e_max=0) {
    Err(error) => assert_eq(error.message, "e_max must be within 1..=999999999")
    Ok(_) => fail("e_max 0 must be rejected")
  }
}
