///|
// The certified exponential `decimal_certified_exp_result` against the rows of
// `certified_exp_rows_wbtest.mbt` (CPython `decimal`, tools/generate_decimal_gda_exp_rows.py).
// The previous loop with the decimal series candidate, which shared the ball
// enclosure and the certifier with the code under test, is not kept.

///|
fn exp_rows_check(group : Int32) -> Unit raise {
  let mut count = 0
  let mut bad = 0
  for row in exp_rows {
    let (
      g,
      precision,
      e_min,
      e_max,
      extended,
      clamp,
      mode,
      argument,
      text,
      flags,
    ) = row
    if g != group {
      continue
    }
    count += 1
    let context = DecimalContext::new(
      precision~,
      decimal_rounding=from_binary_mode(mode),
      e_min~,
      e_max~,
      extended~,
      clamp~,
    )
    let value = Decimal::from_string(argument, precision=argument.length()).unwrap()
    // text "?": subset arithmetic after an overflow or underflow, the value is undefined
    // (GDA 1.70 Appendix A) and the flags s and c are not compared
    let undefined = text == "?"
    let got = match decimal_certified_exp_result(value, context) {
      Ok((result, result_flags)) => {
        let letters = normalization_flags_text(result_flags)
        (if undefined { "?" } else { result.to_string() }) +
        " " +
        (if undefined { letters[0:6].to_owned() + ".." } else { letters })
      }
      Err(_) => "error"
    }
    let want = text +
      " " +
      (if undefined { flags[0:6].to_owned() + ".." } else { flags })
    if got != want {
      bad += 1
      if bad <= 30 {
        println(
          "exp \{argument} p=\{precision} \{mode} [\{e_min},\{e_max}]: got \{got}, expected \{text} \{flags}",
        )
      }
    }
  }
  assert_true(count > 0)
  assert_eq(bad, 0)
}

///|
// oracle: A
// source: the rows of group 0 of certified_exp_rows_wbtest.mbt (see the header of that file): CPython `decimal` exp evaluated 200 digits wider and rounded to the context, value, cohort and flags; random arguments of 1 to 40 digits in precisions 1 to 100
// shares: the argument is parsed by `Decimal::from_string` (input only)
test "binary candidate exp matches CPython decimal on random arguments" {
  exp_rows_check(0)
}

///|
// oracle: A
// source: the rows of group 1 of certified_exp_rows_wbtest.mbt: the argument is ln(m) for a midpoint m between two results, rounded to precision + 60 digits by CPython `decimal`, so exp lies within 10^-(precision + 50) of a rounding boundary; the expected value is CPython exp 200 digits wider rounded half even to the precision
// shares: the argument is parsed by `Decimal::from_string` (input only)
test "binary candidate exp at arguments whose result is near a rounding boundary" {
  exp_rows_check(1)
}

///|
// oracle: A
// source: the rows of group 2 of certified_exp_rows_wbtest.mbt: decimal32, decimal64, decimal128 and odd contexts, subset and extended, every rounding rule, CPython `decimal` exp 200 digits wider rounded by the context (value, cohort, flags); the previous test also compared attempt counts with the previous loop, which is a performance property and is dropped
// shares: nothing (the rounding mode is decoded by a test-local helper)
test "midpoint candidate exp matches CPython decimal in standard contexts" {
  exp_rows_check(2)
}

///|
// oracle: A
// source: the rows of group 3 of certified_exp_rows_wbtest.mbt: arguments from -3.00E+6 to 2999999 on and around the 10^3 bound between the midpoint route and the series, precisions 3, 16, 34, exponent range +-999999, CPython `decimal` exp 200 digits wider rounded to the context; the row -3.00E+6 never finished before the issue found by the random differential run was fixed
// shares: nothing
test "midpoint candidate exp with large arguments in wide exponent contexts" {
  exp_rows_check(3)
}
