///|
using @arithmetic {
  type ArithmeticContext,
  type ArithmeticError,
  type RoundingMode,
  trait CompareChecked,
  trait Contains,
  trait DefinitelyLe,
  trait DefinitelyLt,
  trait DivChecked,
  trait MaybeEq,
  trait Overlaps,
  trait ParseChecked,
  trait PowIntChecked,
  trait PowNatChecked,
  trait SqrtChecked,
}

///|
using @lg {trait IntegralHomomorphism}

///|
fn[T : SqrtChecked] sqrt_checked_generic(
  x : T,
  ctx : ArithmeticContext,
) -> Result[T, ArithmeticError] {
  SqrtChecked::sqrt_checked(x, ctx)
}

///|
fn[T : DivChecked] div_checked_generic(
  x : T,
  y : T,
  ctx : ArithmeticContext,
) -> Result[T, ArithmeticError] {
  DivChecked::div_checked(x, y, ctx)
}

///|
fn[T : CompareChecked] compare_checked_generic(
  x : T,
  y : T,
) -> Result[Int, ArithmeticError] {
  CompareChecked::compare_checked(x, y)
}

///|
fn[T : IntegralHomomorphism, S : @lg.Integral] from_integral_generic(
  x : S,
) -> T {
  let _ = @lg.Integral::normalize(x)
  IntegralHomomorphism::from_integral(x)
}

///|
fn[T : PowNatChecked] square_checked(
  x : T,
  ctx : ArithmeticContext,
) -> Result[T, ArithmeticError] {
  PowNatChecked::pow_nat_checked(x, 2U, ctx)
}

///|
fn[T : PowIntChecked] reciprocal_power_checked(
  x : T,
  exponent : Int,
  ctx : ArithmeticContext,
) -> Result[T, ArithmeticError] {
  PowIntChecked::pow_int_checked(x, exponent, ctx)
}

///|
fn[T : Contains + Overlaps + DefinitelyLt + DefinitelyLe + MaybeEq] enclosure_summary(
  lhs : T,
  rhs : T,
) -> (Bool, Bool, Bool, Bool, Bool) {
  (
    Contains::contains(lhs, rhs),
    Overlaps::overlaps(lhs, rhs),
    DefinitelyLt::definitely_lt(lhs, rhs),
    DefinitelyLe::definitely_le(lhs, rhs),
    MaybeEq::maybe_eq(lhs, rhs),
  )
}

///|
let checked_ctx : ArithmeticContext = ArithmeticContext::new(
  24,
  rounding=RoundingMode::TowardPositive,
)

///|
test "bin_float normalizes powers of two" {
  let x = @bin_float.BinFloat::make(12N, 0, 16)
  assert_eq(x.significand(), 3N)
  assert_eq(x.exponent2(), 2)
}

///|
test "bin_float basic arithmetic stays exact on small dyadics" {
  let a = @bin_float.BinFloat::make(3N, -1, 16)
  let b = @bin_float.BinFloat::make(5N, -1, 16)
  assert_eq((a + b).to_string(), "1p2")
  assert_eq((a - b).to_string(), "-1p0")
  assert_eq((a * b).to_string(), "15p-2")
}

///|
test "bin_float checked division reports division by zero" {
  let result = @bin_float.BinFloat::from_int(1, precision=16).div_checked(
    @bin_float.BinFloat::zero(precision=16),
  )
  match result {
    Ok(_) => fail("expected division by zero")
    Err(err) => assert_true(err.is_division_by_zero())
  }
}

///|
test "bin_float sqrt and pow_int expose core arithmetic extensions" {
  let root = @bin_float.BinFloat::from_int(4, precision=24).sqrt()
  let power = @bin_float.BinFloat::make(3N, -1, 24).pow_int(3)
  match root {
    Ok(value) => assert_eq(value.to_string(), "1p1")
    Err(_) => fail("expected sqrt to succeed")
  }
  match power {
    Ok(value) => assert_eq(value.to_string(), "27p-3")
    Err(_) => fail("expected pow_int to succeed")
  }
}

///|
test "bin_float implements generic checked arithmetic traits" {
  match
    sqrt_checked_generic(
      @bin_float.BinFloat::from_int(9, precision=24),
      checked_ctx,
    ) {
    Ok(value) => assert_eq(value.to_string(), "3p0")
    Err(_) => fail("expected generic checked sqrt to succeed")
  }
  match
    div_checked_generic(
      @bin_float.BinFloat::from_int(9, precision=24),
      @bin_float.BinFloat::from_int(2, precision=24),
      checked_ctx,
    ) {
    Ok(value) => assert_true(value.to_string() != "0")
    Err(_) => fail("expected generic checked division to succeed")
  }
  match
    compare_checked_generic(
      @bin_float.BinFloat::from_int(1, precision=24),
      @bin_float.BinFloat::from_int(2, precision=24),
    ) {
    Ok(value) => assert_eq(value, -1)
    Err(_) => fail("expected generic checked compare to succeed")
  }
  match square_checked(@bin_float.BinFloat::make(3N, -1, 24), checked_ctx) {
    Ok(value) => assert_eq(value.to_string(), "9p-2")
    Err(_) => fail("expected generic checked nat power to succeed")
  }
  match
    reciprocal_power_checked(
      @bin_float.BinFloat::zero(precision=24),
      -1,
      checked_ctx,
    ) {
    Ok(_) => fail("expected negative power of zero to fail")
    Err(err) => assert_true(err.is_division_by_zero())
  }
}

///|
test "bin_float integral homomorphism normalizes canonical dyadics" {
  let value : @bin_float.BinFloat = from_integral_generic(12N)
  assert_eq(value, @bin_float.BinFloat::from_bigint(12N).normalized())
  assert_eq(value.significand(), 3N)
  assert_eq(value.exponent2(), 2)
}

///|
test "decimal parses and normalizes" {
  let x = @decimal.Decimal::parse("0012.3400", precision=20)
  match x {
    Ok(value) => assert_true(value == @decimal.Decimal::make(1234N, -2, 20))
    Err(_) => fail("expected decimal parse to succeed")
  }
}

///|
test "decimal arithmetic and display stay aligned" {
  let a = @decimal.Decimal::from_string("1.25", precision=20).unwrap()
  let b = @decimal.Decimal::from_string("2.5", precision=20).unwrap()
  assert_eq((a + b).to_string(), "3.75")
  assert_eq((a * b).to_string(), "3.125")
}

///|
test "decimal checked division reports division by zero" {
  let result = @decimal.Decimal::from_int(1, precision=20).div_checked(
    @decimal.Decimal::zero(precision=20),
  )
  match result {
    Ok(_) => fail("expected division by zero")
    Err(err) => assert_true(err.is_division_by_zero())
  }
}

///|
test "decimal conversion preserves dyadics exactly" {
  let d = @decimal.Decimal::from_string("0.375", precision=20).unwrap()
  let x = d.to_bin_float(precision=20)
  assert_eq(x.to_string(), "3p-3")
  assert_eq(
    @decimal.Decimal::from_bin_float(x, precision=20).to_string(),
    "0.375",
  )
}

///|
test "decimal implements generic checked arithmetic traits" {
  let parsed : Result[@decimal.Decimal, ArithmeticError] = ParseChecked::parse_checked(
    "2.25", checked_ctx,
  )
  match parsed {
    Ok(value) => assert_eq(value.to_string(), "2.25")
    Err(_) => fail("expected checked decimal parse to succeed")
  }
  match
    div_checked_generic(
      @decimal.Decimal::from_int(9, precision=24),
      @decimal.Decimal::from_int(4, precision=24),
      checked_ctx,
    ) {
    Ok(value) => assert_true(value.to_string().has_prefix("2.25"))
    Err(_) => fail("expected generic checked decimal division to succeed")
  }
  match
    compare_checked_generic(
      @decimal.Decimal::from_int(1, precision=24),
      @decimal.Decimal::from_int(2, precision=24),
    ) {
    Ok(value) => assert_eq(value, -1)
    Err(_) => fail("expected generic checked decimal compare to succeed")
  }
  match
    square_checked(
      @decimal.Decimal::from_string("1.5", precision=24).unwrap(),
      checked_ctx,
    ) {
    Ok(value) => assert_eq(value.to_string(), "2.25")
    Err(_) => fail("expected generic checked decimal nat power to succeed")
  }
  match
    reciprocal_power_checked(
      @decimal.Decimal::zero(precision=24),
      -1,
      checked_ctx,
    ) {
    Ok(_) => fail("expected negative power of decimal zero to fail")
    Err(err) => assert_true(err.is_division_by_zero())
  }
}

///|
test "decimal integral homomorphism preserves canonical decimal form" {
  let value : @decimal.Decimal = from_integral_generic(1200N)
  assert_eq(value, @decimal.Decimal::from_bigint(1200N).normalized())
  assert_eq(value.coefficient(), 12N)
  assert_eq(value.exponent10(), 2)
}

///|
test "ball_float exact containment works" {
  let x = @bin_float.BinFloat::make(3N, -1, 16)
  let ball = @ball_float.BallFloat::exact(x)
  assert_true(ball.contains(x))
  assert_eq(ball.to_string(), "3p-1 +/- 0")
}

///|
test "ball_float constructors accept bigint and float family inputs" {
  let from_big = @ball_float.BallFloat::from_bigint(42N, precision=20)
  let from_double = @ball_float.BallFloat::from_double(0.375, precision=20)
  let from_float = @ball_float.BallFloat::from_float(
    Float::from_double(0.375),
    precision=20,
  )
  assert_true(
    from_big.contains(@bin_float.BinFloat::from_int(42, precision=64)),
  )
  assert_true(
    from_double.contains(@bin_float.BinFloat::from_double(0.375, precision=64)),
  )
  assert_true(
    from_float.contains(@bin_float.BinFloat::from_double(0.375, precision=64)),
  )
}

///|
test "ball_float radius rounds outward at lower precision" {
  let ball = @ball_float.BallFloat::new(
    @bin_float.BinFloat::zero(precision=8),
    @bin_float.BinFloat::make(9N, -4, 8),
    precision=2,
  )
  assert_eq(ball.radius().to_string(), "3p-2")
}

///|
test "ball_float arithmetic keeps exact scalar results enclosed" {
  let a = @ball_float.BallFloat::exact(
    @bin_float.BinFloat::make(3N, -1, 8),
    precision=3,
  )
  let b = @ball_float.BallFloat::exact(
    @bin_float.BinFloat::make(5N, -2, 8),
    precision=3,
  )
  let sum = a + b
  let product = a * b
  let quotient = a / b
  let exact_sum = @bin_float.BinFloat::make(11N, -2, 32)
  let exact_product = @bin_float.BinFloat::make(15N, -3, 32)
  let exact_quotient = @decimal.Decimal::from_string("1.2", precision=40)
    .unwrap()
    .to_bin_float(precision=80)
  assert_true(sum.contains(exact_sum))
  assert_true(product.contains(exact_product))
  assert_true(quotient.contains(exact_quotient))
}

///|
test "ball_float enclosure relations stay partial-order based" {
  let cross = @ball_float.BallFloat::new(
    @bin_float.BinFloat::make(1N, -2, 8),
    @bin_float.BinFloat::make(1N, -1, 8),
    precision=4,
  )
  let right = @ball_float.BallFloat::new(
    @bin_float.BinFloat::from_int(2, precision=8),
    @bin_float.BinFloat::make(1N, -2, 8),
    precision=4,
  )
  assert_true(cross.sign() == @def.Sign::Zero)
  assert_true(cross.definitely_lt(right))
  assert_true(cross.definitely_le(right))
  assert_true(cross.separated_from(right))
  assert_false(cross.maybe_eq(right))
  let (contains_rhs, overlaps_rhs, lt_rhs, le_rhs, maybe_eq_rhs) = enclosure_summary(
    cross, right,
  )
  assert_false(contains_rhs)
  assert_false(overlaps_rhs)
  assert_true(lt_rhs)
  assert_true(le_rhs)
  assert_false(maybe_eq_rhs)
}

///|
test "ball_float division by a divisor containing zero returns whole real enclosure" {
  let numerator = @ball_float.BallFloat::exact(
    @bin_float.BinFloat::from_int(1, precision=16),
    precision=8,
  )
  let divisor = @ball_float.BallFloat::new(
    @bin_float.BinFloat::zero(precision=16),
    @bin_float.BinFloat::one(precision=16),
    precision=8,
  )
  let quotient = numerator / divisor
  assert_true(quotient.is_entire())
}

///|
test "ball_float integral homomorphism keeps exact bounded interval" {
  let value : @ball_float.BallFloat = from_integral_generic(12N)
  assert_eq(value, @ball_float.BallFloat::from_bigint(12N).normalized())
  assert_true(value.is_bounded())
  assert_eq(value.lower_bound(), value.upper_bound())
}

///|
test "ball_float implements checked enclosure-preserving power and division" {
  let unit_ball = @ball_float.BallFloat::exact(
    @bin_float.BinFloat::make(3N, -1, 24),
    precision=12,
  )
  match square_checked(unit_ball, checked_ctx) {
    Ok(value) =>
      assert_true(value.contains(@bin_float.BinFloat::make(9N, -2, 48)))
    Err(_) => fail("expected ball checked nat power to succeed")
  }
  let zero_crossing = @ball_float.BallFloat::new(
    @bin_float.BinFloat::zero(precision=24),
    @bin_float.BinFloat::one(precision=24),
    precision=12,
  )
  match reciprocal_power_checked(zero_crossing, -1, checked_ctx) {
    Ok(value) => assert_true(value.is_entire())
    Err(_) => fail("expected whole-real fallback for zero-containing inverse")
  }
  match div_checked_generic(unit_ball, zero_crossing, checked_ctx) {
    Ok(value) => assert_true(value.is_entire())
    Err(_) => fail("expected whole-real checked division fallback")
  }
}

///|
test "bin_float_result keeps arithmetic closed and propagates errors" {
  let one = @bin_float_result.BinFloatResult::from_int(1, precision=16)
  let two = @bin_float_result.BinFloatResult::from_int(2, precision=16)
  match ((one + two).pow_nat(2U) * two).sqrt().result() {
    Ok(value) =>
      assert_true(value.compare(@bin_float.BinFloat::zero(precision=16)) > 0)
    Err(_) => fail("expected closed bin float result pipeline to succeed")
  }
  let zero = @bin_float_result.BinFloatResult::from_int(0, precision=16)
  match (one / zero).abs().result() {
    Ok(_) => fail("expected division by zero to remain an error")
    Err(err) => assert_true(err.is_division_by_zero())
  }
}

///|
test "decimal_result maps parse and checked operations inside the wrapper" {
  let parsed = @decimal_result.DecimalResult::parse("9.0", precision=20)
  let three = @decimal_result.DecimalResult::from_int(3, precision=20)
  match (parsed.sqrt().pow_int(1) / three).normalized().result() {
    Ok(value) => assert_eq(value, @decimal.Decimal::one(precision=20))
    Err(_) => fail("expected decimal result pipeline to succeed")
  }
  match
    @decimal_result.DecimalResult::parse("bad", precision=20).sqrt().result() {
    Ok(_) => fail("expected parse error to short-circuit")
    Err(err) => assert_true(err.is_parse_error())
  }
}

///|
test "ball_float_result keeps interval operations in one result category" {
  let one = @ball_float_result.BallFloatResult::from_int(1, precision=12)
  let zero_crossing = @ball_float_result.BallFloatResult::from_bounds(
    @bin_float.BinFloat::make(-1N, 0, 16),
    @bin_float.BinFloat::one(precision=16),
    precision=12,
  )
  match (one.pow_nat(2U) / zero_crossing).pow_int(-1).result() {
    Ok(value) => assert_true(value.is_entire())
    Err(_) => fail("expected ball result whole-real fallback to succeed")
  }
  let invalid = @ball_float_result.BallFloatResult::from_double(
    0.0 / 0.0,
    precision=12,
  )
  match (invalid + one).result() {
    Ok(_) => fail("expected invalid ball source to short-circuit")
    Err(err) => assert_true(err.is_domain_error())
  }
}
