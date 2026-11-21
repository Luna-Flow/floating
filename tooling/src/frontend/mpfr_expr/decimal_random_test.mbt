///|
test "decimal random rows compare value, cohort and flags under a context" {
  let source =
    #|# mpfr-decimal-random-v2
    #|t.1 exp half_even 7 96 1 - 0 2.718282 x
    #|t.2 ln half_even 7 96 2 - 0 0.6931472 x
    #|t.3 exp ceiling 2 10001 -8E+4 - 0 1E-10001 xu
    #|t.4 exp half_even 3 9 30 - 0 Infinity xo
    #|t.5 atan2 half_even 7 96 1 1 0 0.7853982 x
    #|t.6 rootn half_even 7 96 2 - 2 1.414214 x
    #|t.7 pown half_even 7 96 3 - -2 0.1111111 x
    #|t.8 pow half_even 7 96 2 0.5 0 1.414214 x
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
    #|t.1 exp half_even 7 96 1 - 0 2.718283 x
    #|t.2 exp half_even 7 96 1 - 0 2.7182820 x
    #|t.3 exp half_even 7 96 1 - 0 2.718282 -
    #|t.4 exp half_even 7 96 1 - 0 2.718282 xu
  let summary = @mpfr_expr.execute_decimal_random_data(
    @mpfr_expr.parse_decimal_random_data("diff", source).unwrap(),
  )
  assert_eq(summary.results().map(result => result.passed()), [
    false, false, false, false,
  ])
}

///|
// oracle: A
// source: the expected 50-digit logarithm of the 40-digit operand was computed by Python 3 decimal (libmpdec,
//   prec 50, round-half-even): Decimal("1.234567890123456789012345678901234567891").ln(); this library did not
//   produce it; the row passes only if the parser kept all 40 digits (7 digits give 0.2107210)
// shares: nothing
test "decimal random parser keeps every digit of an operand" {
  let digits = "1.234567890123456789012345678901234567891"
  let expected = "0.21072102231565256105500171048862388223893826533084"
  let source = "t.1 ln half_even 50 96 " + digits + " - 0 " + expected + " x"
  let document = @mpfr_expr.parse_decimal_random_data("wide", source).unwrap()
  assert_eq(document.case_count(), 1)
  let summary = @mpfr_expr.execute_decimal_random_data(document)
  assert_eq(summary.results().map(result => result.passed()), [true])
}

///|
test "decimal random parser rejects malformed rows" {
  for
    row in [
      "t exp half_even 7 96 1 - 0 2.7", "t nope half_even 7 96 1 - 0 2.7 x", "t exp sideways 7 96 1 - 0 2.7 x",
      "t exp up 7 96 1 - 0 2.7 x", "t exp half_down 7 96 1 - 0 2.7 x", "t exp half_even 0 96 1 - 0 2.7 x",
      "t exp half_even 7 96 one - 0 2.7 x", "t exp half_even 7 96 1 - 0 2.7 q", "t exp half_even 7 96 1 - 0 2.7 xr",
      "t pow half_even 7 96 1 - 0 2.7 x", "t exp half_even 7 0 1 - 0 2.7 x",
    ] {
    match @mpfr_expr.parse_decimal_random_data("bad", row) {
      Err([_]) => ()
      _ => fail("expected one diagnostic for " + row)
    }
  }
}
