///|
test "internal rounding helpers honor tie and directed modes" {
  assert_eq(
    round_positive_div(5N, 2N, false, @lf_arith.RoundingMode::ToNearestEven).to_string(),
    "2",
  )
  assert_eq(
    round_positive_div(7N, 2N, false, @lf_arith.RoundingMode::ToNearestEven).to_string(),
    "4",
  )
  assert_eq(
    round_positive_div(3N, 2N, false, @lf_arith.RoundingMode::TowardZero).to_string(),
    "1",
  )
  assert_eq(
    round_positive_div(3N, 2N, true, @lf_arith.RoundingMode::TowardNegative).to_string(),
    "2",
  )
  assert_eq(
    round_shift(7N, 1, false, @lf_arith.RoundingMode::AwayFromZero).to_string(),
    "4",
  )
  assert_eq(compare_abs(-3N, 2N), 1)
  assert_eq(pow10(0).to_string(), "1")
  assert_eq(pow10(1).to_string(), "10")
  assert_eq(pow10(18).to_string(), "1000000000000000000")
  assert_eq(pow10(19).to_string(), "10000000000000000000")
  assert_eq(pow5(0).to_string(), "1")
  assert_eq(pow5(1).to_string(), "5")
  assert_eq(pow5(18).to_string(), "3814697265625")
  assert_eq(pow5(19).to_string(), "19073486328125")
}

///|
test "internal decimal parser accepts scientific notation and rejects malformed strings" {
  match split_decimal_string("12.340e-1") {
    Some((negative, digits, exponent10)) => {
      assert_false(negative)
      assert_eq(digits, "12340")
      assert_eq(exponent10, -4)
    }
    None => fail("expected scientific decimal parse to succeed")
  }
  match split_decimal_string("-0.05E+3") {
    Some((negative, digits, exponent10)) => {
      assert_true(negative)
      assert_eq(digits, "005")
      assert_eq(exponent10, 1)
    }
    None => fail("expected signed scientific decimal parse to succeed")
  }
  assert_true(split_decimal_string("1e") is None)
  assert_true(split_decimal_string("..1") is None)
}

///|
test "internal digits10 tracks power-of-ten boundaries without string conversion" {
  assert_eq(digits10(0N), 1)
  let exponents = [0, 1, 2, 5, 18, 19, 34, 50, 128, 256, 1024]
  for exponent in exponents {
    let power = pow10(exponent)
    assert_eq(digits10(power), exponent + 1)
    assert_eq(digits10(-power), exponent + 1)
    if exponent > 0 {
      assert_eq(digits10(power - 1N), exponent)
      assert_eq(digits10(-(power - 1N)), exponent)
    }
  }
}

///|
test "internal decNumber-style coefficient trim matches trailing-zero shifts" {
  let (trimmed, exponent) = remove_factor10(123450000N, -7)
  assert_eq(trimmed, 12345N)
  assert_eq(exponent, -3)

  let (limited, limited_exp, dropped) = trim_trailing_decimal_zeros(
    120000N,
    -4,
    max_drop=3,
  )
  assert_eq(limited, 120N)
  assert_eq(limited_exp, -1)
  assert_eq(dropped, 3)
}

///|
test "internal coefficient exact power-of-ten division uses unit shifts" {
  match exact_divide_by_power_of_ten(12345000N, 3) {
    Some(value) => assert_eq(value, 12345N)
    None => fail("expected exact division by 10^3")
  }
  match exact_divide_by_power_of_ten(-5000N, 2) {
    Some(value) => assert_eq(value, -50N)
    None => fail("expected exact division by 10^2")
  }
  assert_true(exact_divide_by_power_of_ten(12345N, 1) is None)
}
