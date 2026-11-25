///|
// oracle: A
// source: exp(1), ln(2), sqrt(2) (rootn 2), 3^-2 and 2^0.5 at 7 digits half_even are 2.718282, 0.6931472, 1.414214,
//   0.1111111 and 1.414214 (CPython decimal, libmpdec 4.0.0, in this review); atan(1) = pi/4 = 0.7853982 at 7
//   digits; exp(30) at 3 digits overflows to Infinity (libmpdec agrees); exp(-8E+4) rounded toward positive
//   infinity is the smallest subnormal 1E-10001 with flags x and u (libmpdec returns 0E-10001 here, which is not
//   the rounded up value of a positive number; the row follows from the direction of rounding)
// shares: the hexadecimal and decimal readers and the operations of the library that the executor runs on each row
//   (the code under test); the expected value is read from the row
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
// oracle: A
// source: verdicts written out: the last digit 3 instead of 2, the cohort 2.7182820 against 2.718282, a missing flag x
//   and an extra flag u each differ from exp(1) = 2.718282 Inexact
// shares: the hexadecimal and decimal readers and the operations of the library that the executor runs on each row
//   (the code under test); the expected value is read from the row
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
// oracle: A
// source: written out: each of eleven rows breaks the format (a missing flag field, unknown operation, unknown
//   rounding name, unsupported rounding names up and half_down, precision 0, a non numeric operand, an unknown
//   flag letter, a missing operand for pow, emax 0) and gives one diagnostic
// shares: nothing
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
