///|
let audit_ctx : @arithmetic.ArithmeticContext = @arithmetic.ArithmeticContext::new(
  12,
  rounding=@arithmetic.RoundingMode::TowardPositive,
)

///|
test "def predicates classify finite nan and enclosing zero consistently" {
  let finite = @bin_float.BinFloat::from_int(3, precision=8)
  let nan = @bin_float.BinFloat::nan(precision=8)
  let inf = @decimal.Decimal::inf(@def.Sign::Positive, precision=8)
  let straddle = @ball_float.BallFloat::new(
    @bin_float.BinFloat::zero(precision=8),
    @bin_float.BinFloat::make(1N, -2, 8),
    precision=8,
  )
  assert_true(@def.is_finite(finite))
  assert_true(@def.is_nan(nan))
  assert_true(@def.is_infinite(inf))
  assert_true(@def.is_zero(straddle))
  assert_false(@def.is_zero(nan))
}

///|
test "internal rounding helpers honor tie and directed modes" {
  assert_eq(
    @internal.round_positive_div(
      5N,
      2N,
      false,
      @arithmetic.RoundingMode::ToNearestEven,
    ).to_string(),
    "2",
  )
  assert_eq(
    @internal.round_positive_div(
      7N,
      2N,
      false,
      @arithmetic.RoundingMode::ToNearestEven,
    ).to_string(),
    "4",
  )
  assert_eq(
    @internal.round_positive_div(
      3N,
      2N,
      false,
      @arithmetic.RoundingMode::TowardZero,
    ).to_string(),
    "1",
  )
  assert_eq(
    @internal.round_positive_div(
      3N,
      2N,
      true,
      @arithmetic.RoundingMode::TowardNegative,
    ).to_string(),
    "2",
  )
  assert_eq(
    @internal.round_shift(7N, 1, false, @arithmetic.RoundingMode::AwayFromZero).to_string(),
    "4",
  )
  assert_eq(@internal.compare_abs(-3N, 2N), 1)
}

///|
test "internal decimal parser accepts scientific notation and rejects malformed strings" {
  match @internal.split_decimal_string("12.340e-1") {
    Some((negative, digits, exponent10)) => {
      assert_false(negative)
      assert_eq(digits, "12340")
      assert_eq(exponent10, -4)
    }
    None => fail("expected scientific decimal parse to succeed")
  }
  match @internal.split_decimal_string("-0.05E+3") {
    Some((negative, digits, exponent10)) => {
      assert_true(negative)
      assert_eq(digits, "005")
      assert_eq(exponent10, 1)
    }
    None => fail("expected signed scientific decimal parse to succeed")
  }
  assert_true(@internal.split_decimal_string("1e") is None)
  assert_true(@internal.split_decimal_string("..1") is None)
}

///|
test "context and parse error types are exposed" {
  let ctx = @arithmetic.ArithmeticContext::new(
    7,
    rounding=@arithmetic.RoundingMode::TowardPositive,
  )
  assert_eq(ctx.precision, 7)
  assert_true(ctx.rounding == @arithmetic.RoundingMode::TowardPositive)
  let result = @decimal.Decimal::parse("bad", precision=10)
  match result {
    Ok(_) => fail("expected parse error")
    Err(err) => assert_true(err.is_parse_error())
  }
}

///|
test "bin_float checked compare rejects nan" {
  let result = @bin_float.BinFloat::nan(precision=8).compare_checked(
    @bin_float.BinFloat::zero(precision=8),
  )
  match result {
    Ok(_) => fail("expected unordered compare")
    Err(err) => assert_true(err.is_unordered_comparison())
  }
}

///|
test "bin_float low precision rounding and ulp stay explicit" {
  let x = @bin_float.BinFloat::make(13N, -3, 8)
  let rounded = x.with_precision(2, @arithmetic.RoundingMode::ToNearestEven)
  assert_eq(rounded.to_string(), "3p-1")
  assert_eq(rounded.ulp().to_string(), "1p-1")
  assert_eq(@bin_float.BinFloat::zero(precision=4).ulp().to_string(), "1p-3")
}

///|
test "checked trait helpers are usable through arithmetic boundary" {
  let parsed : Result[@decimal.Decimal, @arithmetic.ArithmeticError] = @arithmetic.ParseChecked::parse_checked(
    "12.5", audit_ctx,
  )
  match parsed {
    Ok(value) => assert_eq(value.to_string(), "12.5")
    Err(_) => fail("expected checked parse to succeed")
  }
  match
    @arithmetic.DivChecked::div_checked(
      @decimal.Decimal::from_int(7, precision=6),
      @decimal.Decimal::from_int(2, precision=6),
      audit_ctx,
    ) {
    Ok(value) => assert_true(value.to_string().has_prefix("3.5"))
    Err(_) => fail("expected checked decimal division to succeed")
  }
}
