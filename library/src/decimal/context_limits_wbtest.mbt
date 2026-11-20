///|
test "decimal implementation limits have the documented values" {
  assert_eq(decimal_implementation_e_max, 999_999_999)
  assert_eq(decimal_implementation_e_min, -999_999_998)
  assert_eq(decimal_precision_max, 999_999_999)
}

///|
test "DecimalContext::try_new accepts the limits and rejects one beyond" {
  match
    DecimalContext::try_new(
      precision=decimal_precision_max,
      e_max=decimal_implementation_e_max,
    ) {
    Ok(ctx) => {
      assert_eq(ctx.precision(), decimal_precision_max)
      assert_eq(ctx.e_min(), decimal_implementation_e_min)
      assert_eq(ctx.e_max(), decimal_implementation_e_max)
    }
    Err(_) => fail("the documented limits must be accepted")
  }
  assert_true(
    DecimalContext::try_new(
      precision=decimal_precision_max + 1,
      e_max=decimal_implementation_e_max,
    )
    is Err(_),
  )
  assert_true(
    DecimalContext::try_new(e_max=decimal_implementation_e_max + 1) is Err(_),
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
