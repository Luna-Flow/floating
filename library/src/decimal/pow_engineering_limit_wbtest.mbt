///|
// oracle: S
// source: pins an engineering limit of the implementation, not a value of the standard (issue 700): the `pow` family refuses a context whose precision is above `decimal_elementary_precision_limit` digits (the test reads the constant, so it follows the maintainer's number), at once, with the certification failure. The limit is not computed here.
// shares: nothing
test "pow family refuses a precision beyond the kernel at once (#700)" {
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  for
    digits in [
      decimal_elementary_precision_limit + 1,
      decimal_elementary_precision_limit + 1_000_000,
      999_999_999,
    ] {
    let huge = DecimalContext::new(precision=digits, e_max=999_999_999)
    for
      call in [
        d("2").try_pow_ctx(d("0.5"), huge),
        d("2").try_powr_ctx(d("0.5"), huge),
        d("2").try_pow_ctx(d("1.5"), huge),
        d("2").try_pow_ctx(d("3"), huge),
        d("2").try_pown_ctx(3, huge),
      ] {
      match call {
        Err(error) => assert_true(error.is_certification_failure())
        Ok(_) => abort("an ordinary pow at \{digits} digits must be refused")
      }
    }
    let (value, flags) = d("2").pow_ctx(d("0.5"), huge)
    assert_true(value.is_nan() && flags.not_computed())
  }
}

///|
// oracle: A
// source: written out from IEEE 754-2019 9.2.1 (pow): pow(x, +-0) is 1 if x is not a signaling NaN; pow(+1, y) is 1; pow(+-0, y) is +-inf with divideByZero for an odd negative integer y; pow(x, +inf) is +0 for -1 < x < 1 and +inf for 1 < x; pow(x, -inf) is +inf for -1 < x < 1; pow(-1, n) is -1 for an odd integer n; a signaling NaN gives a quiet NaN with invalid_operation (6.2)
// shares: nothing
test "pow special cases of 9.2.1 stay values beyond the kernel (#700)" {
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  let huge = DecimalContext::new(
    precision=decimal_elementary_precision_limit + 1,
    e_max=999_999_999,
  )
  let show = fn(x : String, y : String) {
    match d(x).try_pow_ctx(d(y), huge) {
      Ok((value, flags)) =>
        "\{value} \{if flags.division_by_zero() { "z" } else if flags.invalid_operation() { "v" } else { "-" }}"
      Err(_) => "refused"
    }
  }
  assert_eq(show("5", "0"), "1 -")
  assert_eq(show("NaN", "0"), "1 -")
  assert_eq(show("1", "0.5"), "1 -")
  assert_eq(show("0", "-1"), "inf z")
  assert_eq(show("-0", "-1"), "-inf z")
  assert_eq(show("2", "Infinity"), "inf -")
  assert_eq(show("0.5", "Infinity"), "0 -")
  assert_eq(show("0.5", "-Infinity"), "inf -")
  assert_eq(show("-1", "3"), "-1 -")
  assert_eq(show("sNaN", "2"), "nan v")
}

///|
// oracle: A
// source: written out by hand: 2^3 = 8 and 4^(1/2) = 2 are exact; at the limit itself (999,999 digits) the `pow` family still computes: the limit refuses only a precision above `decimal_elementary_precision_limit`
// shares: nothing
test "pow family computes at the limit itself (#700)" {
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  let at_limit = DecimalContext::new(
    precision=decimal_elementary_precision_limit,
    e_max=999_999_999,
  )
  assert_eq(d("2").pow_ctx(d("3"), at_limit).0.to_string(), "8")
  assert_eq(d("2").pown_ctx(3, at_limit).0.to_string(), "8")
}
