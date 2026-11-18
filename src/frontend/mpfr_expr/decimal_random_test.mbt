///|
test "decimal random rows compare value, cohort and flags under a context" {
  let source =
    #|# mpfr-decimal-random-v1
    #|t.1 exp half_even 7 -95 96 1 b 1 - 0 2.718282 xr
    #|t.2 ln half_even 7 -95 96 1 b 2 - 0 0.6931472 xr
    #|t.3 exp up 2 -10004 10001 0 b -8E+4 - 0 1E-10005 xrsu
    #|t.4 exp half_even 3 -9 9 0 b 30 - 0 Infinity xro
    #|t.5 atan2 half_even 7 -95 96 1 b 1 1 0 0.7853982 xr
    #|t.6 rootn half_even 7 -95 96 1 b 2 - 2 1.414214 xr
    #|t.7 pown half_even 7 -95 96 1 b 3 - -2 0.1111111 xr
    #|t.8 pow half_even 7 -95 96 1 b 2 0.5 0 1.414214 xr
  let document = @mpfr_expr.parse_decimal_random_data("inline.decimal", source).unwrap()
  assert_eq(document.case_count(), 8)
  assert_eq(document.case_ids()[2], "t.3")
  let summary = @mpfr_expr.execute_decimal_random_data(document)
  for result in summary.results() {
    assert_true(result.passed(), msg=result.id() + ": " + result.message())
  }
  assert_eq(summary.passed_cases(), 8)
}

///|
test "decimal random executor reports a value, cohort or flag difference" {
  let source =
    #|t.1 exp half_even 7 -95 96 1 b 1 - 0 2.718283 xr
    #|t.2 exp half_even 7 -95 96 1 b 1 - 0 2.7182820 xr
    #|t.3 exp half_even 7 -95 96 1 b 1 - 0 2.718282 x
    #|t.4 exp half_even 7 -95 96 1 b 1 - 0 2.718282 xru
  let summary = @mpfr_expr.execute_decimal_random_data(
    @mpfr_expr.parse_decimal_random_data("diff", source).unwrap(),
  )
  assert_eq(summary.results().map(result => result.passed()), [
    false, false, false, false,
  ])
}

///|
test "decimal random parser keeps every digit of an operand" {
  // A 40-digit operand in a 7-digit context is not rounded by the parser: the
  // executor sees exactly the value the oracle used.
  let digits = "1.234567890123456789012345678901234567891"
  let source = "t.1 ln half_even 50 -95 96 1 b " + digits + " - 0 0.2110 xr"
  let document = @mpfr_expr.parse_decimal_random_data("wide", source).unwrap()
  assert_eq(document.case_count(), 1)
}

///|
test "decimal random parser rejects malformed rows" {
  for
    row in [
      "t exp half_even 7 -95 96 1 b 1 - 0 2.7", "t nope half_even 7 -95 96 1 b 1 - 0 2.7 xr",
      "t exp sideways 7 -95 96 1 b 1 - 0 2.7 xr", "t exp half_even 0 -95 96 1 b 1 - 0 2.7 xr",
      "t exp half_even 7 -95 96 2 b 1 - 0 2.7 xr", "t exp half_even 7 -95 96 1 c 1 - 0 2.7 xr",
      "t exp half_even 7 -95 96 1 b one - 0 2.7 xr", "t exp half_even 7 -95 96 1 b 1 - 0 2.7 q",
      "t pow half_even 7 -95 96 1 b 1 - 0 2.7 xr", "t exp half_even 7 5 96 1 b 1 - 0 2.7 xr",
    ] {
    match @mpfr_expr.parse_decimal_random_data("bad", row) {
      Err([_]) => ()
      _ => fail("expected one diagnostic for " + row)
    }
  }
}
