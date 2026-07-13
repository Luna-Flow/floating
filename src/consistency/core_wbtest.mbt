///|
using @lf_arith {
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
using @lf_alg {
  trait IntegralHomomorphism,
  trait One,
  trait Semiring,
  trait Zero,
}

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
fn[T : IntegralHomomorphism, S : @lf_alg.Integral] from_integral_generic(
  x : S,
) -> T {
  let _ = @lf_alg.Integral::normalize(x)
  IntegralHomomorphism::from_integral(x)
}

///|
fn[T : Semiring] quadratic_semiring(x : T) -> T {
  x * x + x + One::one()
}

///|
fn[T : Zero + Add] add_zero_generic(x : T) -> T {
  x + Zero::zero()
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
fn decimal_coeff_signed(x : @decimal.Decimal) -> BigInt {
  let magnitude = x.coefficient()
  if x.is_negative() && !x.coefficient().is_zero() {
    -magnitude
  } else {
    magnitude
  }
}

///|
fn decimal_coeff_magnitude(x : @decimal.Decimal) -> BigInt {
  x.coefficient()
}

///|
test "internal digits10 tracks power-of-ten boundaries without string conversion" {
  assert_eq(@internal.digits10(0N), 1)
  let exponents = [0, 1, 2, 5, 18, 19, 34, 50, 128, 256, 1024]
  for exponent in exponents {
    let power = @internal.pow10(exponent)
    assert_eq(@internal.digits10(power), exponent + 1)
    assert_eq(@internal.digits10(-power), exponent + 1)
    if exponent > 0 {
      assert_eq(@internal.digits10(power - 1N), exponent)
      assert_eq(@internal.digits10(-(power - 1N)), exponent)
    }
  }
}

///|
test "internal decNumber-style coefficient trim matches trailing-zero shifts" {
  let (trimmed, exponent) = @internal.remove_factor10(123450000N, -7)
  assert_eq(trimmed, 12345N)
  assert_eq(exponent, -3)

  let (limited, limited_exp, dropped) = @internal.trim_trailing_decimal_zeros(
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
  match @internal.exact_divide_by_power_of_ten(12345000N, 3) {
    Some(value) => assert_eq(value, 12345N)
    None => fail("expected exact division by 10^3")
  }
  match @internal.exact_divide_by_power_of_ten(-5000N, 2) {
    Some(value) => assert_eq(value, -50N)
    None => fail("expected exact division by 10^2")
  }
  assert_true(@internal.exact_divide_by_power_of_ten(12345N, 1) is None)
}

///|
test "decimal multiply exact paths can use coefficient kernel" {
  let lhs = decimal_test_operand("1234567890123")
  let rhs = decimal_test_operand("987654321")
  let plain = lhs * rhs
  let ctx = @decimal.DecimalContext::new(precision=40)
  let (ctx_value, ctx_flags) = lhs.mul_ctx(rhs, ctx)
  let expected = decimal_test_operand("1219326311247834171483")
  assert_eq(plain.compare_total(expected), 0)
  assert_eq(ctx_value.compare_total(expected), 0)
  assert_false(ctx_flags.inexact)
  assert_false(ctx_flags.rounded)
}

///|
test "decimal add/sub exact alignment can follow coefficient kernel shifts" {
  let ctx = @decimal.DecimalContext::new(precision=40)

  let lhs = decimal_test_operand("12345678901234567890E+7")
  let rhs = decimal_test_operand("987654321E-5")
  let (sum, sum_flags) = lhs.add_ctx(rhs, ctx)
  let expected_sum = decimal_test_operand("123456789012345678900009876.54321")
  assert_eq(sum.compare_total(expected_sum), 0)
  assert_false(sum_flags.inexact)
  assert_false(sum_flags.rounded)

  let minuend = decimal_test_operand("1.00000000000000000000E+12")
  let subtrahend = decimal_test_operand("999999999999.9999999999")
  let (difference, difference_flags) = minuend.sub_ctx(subtrahend, ctx)
  let expected_difference = decimal_test_operand("0.0000000001")
  assert_eq(difference.compare_total(expected_difference), 0)
  assert_false(difference_flags.inexact)
  assert_false(difference_flags.rounded)
}

///|
enum DecimalConformanceOp {
  Add
  Subtract
  Multiply
  Sqrt
  Power
  Divide
  DivideInteger
  Remainder
  Quantize
  Fma
  ToIntegralExact
  Reduce
} derive(Eq)

///|
fn decimal_conformance_operand(
  id : String,
  src : String,
) -> @decimal.Decimal raise {
  let normalized = @decimal.Decimal::parse(src, precision=64)
  match normalized {
    Ok(value) => return value
    Err(_) => ()
  }
  let trimmed = src.trim()
  let mut negative = false
  let mut body = trimmed
  if trimmed.length() > 0 && trimmed[0] == '-' {
    negative = true
    body = trimmed[1:].to_owned()
  } else if trimmed.length() > 0 && trimmed[0] == '+' {
    body = trimmed[1:].to_owned()
  }
  if body == "nan" || body == "NaN" {
    return @decimal.Decimal::quiet_nan(negative~, precision=64)
  }
  if body == "snan" || body == "sNaN" || body == "SNAN" {
    return @decimal.Decimal::signaling_nan(negative~, precision=64)
  }
  if body == "inf" || body == "Inf" || body == "infinity" || body == "Infinity" {
    return @decimal.Decimal::inf(
      if negative {
        @def.Sign::Negative
      } else {
        @def.Sign::Positive
      },
      precision=64,
    )
  }
  match @decimal.Decimal::from_string(src, precision=64) {
    Some(value) => value
    None => fail("invalid decimal conformance operand: " + id + " " + src)
  }
}

///|
fn assert_decimal_conformance_value(
  id : String,
  actual : @decimal.Decimal,
  expected_src : String,
) -> Unit raise {
  let expected = decimal_conformance_operand(id, expected_src)
  assert_eq(actual.compare_total(expected), 0, msg=id + " result")
}

///|
fn assert_decimal_conformance_flags(
  id : String,
  flags : @decimal.DecimalFlags,
  rounded? : Bool = false,
  inexact? : Bool = false,
  lost_digits? : Bool = false,
  invalid_operation? : Bool = false,
  division_by_zero? : Bool = false,
  overflow? : Bool = false,
  underflow? : Bool = false,
  subnormal? : Bool = false,
  clamped? : Bool = false,
  division_impossible? : Bool = false,
  division_undefined? : Bool = false,
) -> Unit raise {
  assert_eq(flags.rounded.to_string(), rounded.to_string(), msg=id + " rounded")
  assert_eq(flags.inexact.to_string(), inexact.to_string(), msg=id + " inexact")
  assert_eq(
    flags.lost_digits.to_string(),
    lost_digits.to_string(),
    msg=id + " lost_digits",
  )
  assert_eq(
    flags.invalid_operation.to_string(),
    invalid_operation.to_string(),
    msg=id + " invalid_operation",
  )
  assert_eq(
    flags.division_by_zero.to_string(),
    division_by_zero.to_string(),
    msg=id + " division_by_zero",
  )
  assert_eq(
    flags.overflow.to_string(),
    overflow.to_string(),
    msg=id + " overflow",
  )
  assert_eq(
    flags.underflow.to_string(),
    underflow.to_string(),
    msg=id + " underflow",
  )
  assert_eq(
    flags.subnormal.to_string(),
    subnormal.to_string(),
    msg=id + " subnormal",
  )
  assert_eq(flags.clamped.to_string(), clamped.to_string(), msg=id + " clamped")
  assert_eq(
    flags.division_impossible.to_string(),
    division_impossible.to_string(),
    msg=id + " division_impossible",
  )
  assert_eq(
    flags.division_undefined.to_string(),
    division_undefined.to_string(),
    msg=id + " division_undefined",
  )
}

///|
fn run_decimal_binary_conformance_case(
  id : String,
  op : DecimalConformanceOp,
  lhs_src : String,
  rhs_src : String,
  expected : String,
  ctx : @decimal.DecimalContext,
  rounded? : Bool = false,
  inexact? : Bool = false,
  invalid_operation? : Bool = false,
  division_by_zero? : Bool = false,
  overflow? : Bool = false,
  underflow? : Bool = false,
  subnormal? : Bool = false,
  clamped? : Bool = false,
  division_impossible? : Bool = false,
  division_undefined? : Bool = false,
) -> Unit raise {
  let lhs = decimal_conformance_operand(id, lhs_src)
  let rhs = decimal_conformance_operand(id, rhs_src)
  let (actual, flags) = match op {
    Add => lhs.add_ctx(rhs, ctx)
    Subtract => lhs.sub_ctx(rhs, ctx)
    Multiply => lhs.mul_ctx(rhs, ctx)
    Sqrt => fail("binary runner cannot execute unary case: " + id)
    Power => lhs.power_ctx(rhs, ctx)
    Divide => lhs.div_ctx(rhs, ctx)
    DivideInteger => lhs.divide_integer(rhs, ctx)
    Remainder => lhs.remainder(rhs, ctx)
    Quantize => lhs.quantize(rhs, ctx)
    Fma | ToIntegralExact | Reduce =>
      fail("binary runner cannot execute unary/ternary case: " + id)
  }
  assert_decimal_conformance_value(id, actual, expected)
  assert_decimal_conformance_flags(
    id,
    flags,
    rounded~,
    inexact~,
    invalid_operation~,
    division_by_zero~,
    overflow~,
    underflow~,
    subnormal~,
    clamped~,
    division_impossible~,
    division_undefined~,
  )
}

///|
fn run_decimal_ternary_conformance_case(
  id : String,
  op : DecimalConformanceOp,
  lhs_src : String,
  rhs_src : String,
  third_src : String,
  expected : String,
  ctx : @decimal.DecimalContext,
  rounded? : Bool = false,
  inexact? : Bool = false,
) -> Unit raise {
  let lhs = decimal_conformance_operand(id, lhs_src)
  let rhs = decimal_conformance_operand(id, rhs_src)
  let third = decimal_conformance_operand(id, third_src)
  let (actual, flags) = match op {
    Fma => lhs.fma_ctx(rhs, third, ctx)
    Add
    | Subtract
    | Multiply
    | Sqrt
    | Power
    | Divide
    | DivideInteger
    | Remainder
    | Quantize
    | ToIntegralExact
    | Reduce => fail("ternary runner cannot execute non-fma case: " + id)
  }
  assert_decimal_conformance_value(id, actual, expected)
  assert_decimal_conformance_flags(id, flags, rounded~, inexact~)
}

///|
fn run_decimal_unary_conformance_case(
  id : String,
  op : DecimalConformanceOp,
  operand_src : String,
  expected : String,
  ctx : @decimal.DecimalContext,
  rounded? : Bool = false,
  inexact? : Bool = false,
  invalid_operation? : Bool = false,
  division_by_zero? : Bool = false,
  overflow? : Bool = false,
  underflow? : Bool = false,
  subnormal? : Bool = false,
  clamped? : Bool = false,
  division_impossible? : Bool = false,
  division_undefined? : Bool = false,
) -> Unit raise {
  let operand = decimal_conformance_operand(id, operand_src)
  let (actual, flags) = match op {
    Sqrt => operand.sqrt_ctx(ctx)
    ToIntegralExact => operand.to_integral_exact(ctx)
    Reduce => operand.reduce_ctx(ctx)
    Add
    | Subtract
    | Multiply
    | Power
    | Divide
    | DivideInteger
    | Remainder
    | Quantize
    | Fma => fail("unary runner cannot execute binary case: " + id)
  }
  assert_decimal_conformance_value(id, actual, expected)
  assert_decimal_conformance_flags(
    id,
    flags,
    rounded~,
    inexact~,
    invalid_operation~,
    division_by_zero~,
    overflow~,
    underflow~,
    subnormal~,
    clamped~,
    division_impossible~,
    division_undefined~,
  )
}

///|
test "bin_float normalizes powers of two" {
  let x = binary_test_make(12N, 0, 16)
  assert_eq(binary_test_signed_bigint(x), 3N)
  assert_eq(x.exponent2(), 2)
}

///|
test "bin_float basic arithmetic stays exact on small dyadics" {
  let a = binary_test_make(3N, -1, 16)
  let b = binary_test_make(5N, -1, 16)
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
  let power = binary_test_make(3N, -1, 24).pow_int(3)
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
  match square_checked(binary_test_make(3N, -1, 24), checked_ctx) {
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
test "bin_float coefficient constructor normalizes canonical dyadics" {
  let value = @bin_float.BinFloat::from_coefficient(
    @bin_float.BinCoeff::from_uint64(12UL),
  )
  assert_eq(value, binary_test_make(12N, 0, 53).normalized())
  assert_eq(binary_test_signed_bigint(value), 3N)
  assert_eq(value.exponent2(), 2)
}

///|
test "decimal parses and normalizes" {
  let x = @decimal.Decimal::parse("0012.3400", precision=20)
  match x {
    Ok(value) => {
      assert_true(value == @decimal.Decimal::make(1234N, -2, 20))
      assert_eq(value.to_string(), "12.3400")
      assert_eq(value.exponent10(), -4)
    }
    Err(_) => fail("expected decimal parse to succeed")
  }
}

///|
test "decimal parse accepts special values and rejects malformed special payloads" {
  match @decimal.Decimal::parse("-Infinity", precision=12) {
    Ok(value) => {
      assert_true(value.classify() == @lf_arith.FpClass::Infinity)
      assert_true(value.is_negative())
    }
    Err(_) => fail("expected infinity parse to succeed")
  }

  match @decimal.Decimal::parse("NaN0012", precision=4) {
    Ok(value) => {
      assert_true(value.is_qnan())
      assert_eq(value.nan_payload(), 12N)
    }
    Err(_) => fail("expected quiet NaN parse to succeed")
  }

  match @decimal.Decimal::parse("-sNaN9", precision=8) {
    Ok(value) => {
      assert_true(value.is_snan())
      assert_true(value.is_negative())
      assert_eq(value.nan_payload(), 9N)
    }
    Err(_) => fail("expected signaling NaN parse to succeed")
  }

  match @decimal.Decimal::parse("sNaN12x", precision=8) {
    Ok(_) => fail("expected malformed signaling NaN payload to fail")
    Err(err) => assert_true(err.is_parse_error())
  }

  match @decimal.Decimal::parse("NaN12345", precision=4) {
    Ok(_) => fail("expected quiet NaN payload beyond precision to fail")
    Err(err) => assert_true(err.is_parse_error())
  }

  match @decimal.Decimal::parse("-sNaN12345", precision=4) {
    Ok(_) => fail("expected signaling NaN payload beyond precision to fail")
    Err(err) => assert_true(err.is_parse_error())
  }
}

///|
test "decimal preserves signed zero through GDA-ready observers" {
  let pos = @decimal.Decimal::from_string("0.00", precision=12).unwrap()
  let neg = @decimal.Decimal::from_string("-0.00", precision=12).unwrap()
  assert_true(pos.is_zero())
  assert_true(neg.is_zero())
  assert_false(pos.is_negative_zero())
  assert_true(neg.is_negative_zero())
  assert_false(pos.is_negative())
  assert_true(neg.is_negative())
  assert_eq(pos.to_string(), "0.00")
  assert_eq(neg.to_string(), "-0.00")
  assert_true(pos == neg)
  assert_true(
    neg.with_precision(4, RoundingMode::ToNearestEven).is_negative_zero(),
  )
  assert_true(neg.normalized().is_negative_zero())
  assert_eq(neg.normalized().to_string(), "-0")
  assert_false(neg.abs().is_negative_zero())
  assert_true(pos.neg().is_negative_zero())
}

///|
test "decimal unary plus and minus canonicalize zero in subset contexts" {
  let subset_ctx = @decimal.DecimalContext::new(
    precision=9,
    e_min=-999,
    e_max=999,
    extended=false,
  )
  let pos_zero = @decimal.Decimal::from_string("0.00", precision=12).unwrap()
  let neg_zero = @decimal.Decimal::from_string("-0.00", precision=12).unwrap()
  let (plus_pos, plus_pos_flags) = pos_zero.plus_ctx(subset_ctx)
  let (plus_neg, plus_neg_flags) = neg_zero.plus_ctx(subset_ctx)
  let (minus_pos, minus_pos_flags) = pos_zero.minus_ctx(subset_ctx)
  let (minus_neg, minus_neg_flags) = neg_zero.minus_ctx(subset_ctx)
  assert_eq(plus_pos.to_string(), "0")
  assert_false(plus_pos.is_negative_zero())
  assert_false(plus_pos_flags.has_error())
  assert_eq(plus_neg.to_string(), "0")
  assert_false(plus_neg.is_negative_zero())
  assert_false(plus_neg_flags.has_error())
  assert_eq(minus_pos.to_string(), "0")
  assert_false(minus_pos.is_negative_zero())
  assert_false(minus_pos_flags.has_error())
  assert_eq(minus_neg.to_string(), "0")
  assert_false(minus_neg.is_negative_zero())
  assert_false(minus_neg_flags.has_error())
}

///|
test "decimal unary plus and minus canonicalize zero sign in extended contexts" {
  let ctx = @decimal.DecimalContext::new(
    precision=16,
    e_min=-383,
    e_max=384,
    clamp=true,
    extended=true,
  )
  let neg_zero = @decimal.Decimal::from_string("-0.0000", precision=20).unwrap()
  let (plus_value, plus_flags) = neg_zero.plus_ctx(ctx)
  let (minus_value, minus_flags) = neg_zero.minus_ctx(ctx)
  assert_eq(plus_value.to_string(), "0.0000")
  assert_false(plus_value.is_negative_zero())
  assert_false(plus_flags.has_error())
  assert_eq(minus_value.to_string(), "0.0000")
  assert_false(minus_value.is_negative_zero())
  assert_false(minus_flags.has_error())
}

///|
test "decimal observers distinguish sign from signedness on specials" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let neg_zero = @decimal.Decimal::negative_zero(precision=8)
  let pos_inf = @decimal.Decimal::inf(@def.Sign::Positive, precision=8)
  let neg_inf = @decimal.Decimal::inf(@def.Sign::Negative, precision=8)
  let qnan = @decimal.Decimal::quiet_nan(payload=7N, negative=true, precision=8)
  let snan = @decimal.Decimal::signaling_nan(
    payload=9N,
    negative=true,
    precision=8,
  )
  assert_true(neg_zero.sign() == @def.Sign::Zero)
  assert_true(pos_inf.sign() == @def.Sign::Positive)
  assert_true(neg_inf.sign() == @def.Sign::Negative)
  assert_true(qnan.sign() == @def.Sign::Zero)
  assert_true(snan.sign() == @def.Sign::Zero)
  assert_true(qnan.is_signed())
  assert_true(snan.is_signed())
  assert_eq(qnan.class_name(ctx), "NaN")
  assert_eq(snan.class_name(ctx), "sNaN")
}

///|
test "decimal zero arithmetic preserves meaningful result signs" {
  let pos = @decimal.Decimal::zero(precision=12)
  let neg = @decimal.Decimal::negative_zero(precision=12)
  let two = @decimal.Decimal::from_int(2, precision=12)
  let neg_two = @decimal.Decimal::from_int(-2, precision=12)
  assert_true((neg + neg).is_negative_zero())
  assert_false((pos + neg).is_negative_zero())
  assert_true((neg * two).is_negative_zero())
  assert_true((two * neg).is_negative_zero())
  assert_false((neg_two * pos).is_negative_zero())
  assert_true((neg / two).is_negative_zero())
}

///|
test "decimal context zero addition canonicalizes ordinary zero results" {
  let ctx = @decimal.DecimalContext::new(precision=9)
  let cents_zero = @decimal.Decimal::from_string("0.00", precision=12).unwrap()
  let unit_zero = @decimal.Decimal::zero(precision=12)
  let (sum, flags) = cents_zero.add_ctx(unit_zero, ctx)
  assert_eq(sum.to_string(), "0.00")
  assert_false(flags.rounded)
  assert_false(flags.inexact)
  let neg_tenth = @decimal.Decimal::from_string("-0.0", precision=12).unwrap()
  let (mixed, _) = neg_tenth.add_ctx(cents_zero, ctx)
  assert_false(mixed.is_negative_zero())
  assert_eq(mixed.to_string(), "0.00")
}

///|
test "decimal context nonzero plus zero keeps nonzero cohort" {
  let ctx = @decimal.DecimalContext::new(precision=9)
  let one = @decimal.Decimal::one(precision=12)
  let tenth_zero = @decimal.Decimal::from_string("0.0", precision=12).unwrap()
  let medium = @decimal.Decimal::from_string("-5E8", precision=12).unwrap()
  let huge = @decimal.Decimal::from_string("-5E9", precision=12).unwrap()
  let unit_zero = @decimal.Decimal::zero(precision=12)
  let (lhs_sum, lhs_flags) = one.add_ctx(tenth_zero, ctx)
  let (rhs_sum, rhs_flags) = tenth_zero.add_ctx(one, ctx)
  let (medium_sum, medium_flags) = medium.add_ctx(unit_zero, ctx)
  let (huge_sum, huge_flags) = huge.add_ctx(unit_zero, ctx)
  assert_eq(lhs_sum.to_string(), "1.0")
  assert_eq(rhs_sum.to_string(), "1.0")
  assert_eq(medium_sum.to_string(), "-500000000")
  assert_eq(huge_sum.to_string(), "-5.00000000E+9")
  assert_false(lhs_flags.rounded)
  assert_false(rhs_flags.rounded)
  assert_false(medium_flags.rounded)
  assert_true(huge_flags.rounded)
}

///|
test "decimal subset plus_ctx follows official positive-exponent cohorts" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
    extended=false,
  )
  let lhs = @decimal.Decimal::from_string("56267E+1", precision=16).unwrap()
  let rhs = @decimal.Decimal::from_string("-56267E+4", precision=16).unwrap()
  let (plus_lhs, plus_lhs_flags) = lhs.plus_ctx(ctx)
  let (plus_rhs, plus_rhs_flags) = rhs.plus_ctx(ctx)
  assert_eq(
    plus_lhs.compare_total(
      @decimal.Decimal::from_string("562670", precision=64).unwrap(),
    ),
    0,
  )
  assert_eq(
    plus_rhs.compare_total(
      @decimal.Decimal::from_string("-562670000", precision=64).unwrap(),
    ),
    0,
  )
  assert_false(plus_lhs_flags.rounded)
  assert_false(plus_rhs_flags.rounded)
}

///|
test "decimal unary plus/minus official positive exponent cohort rows keep arithmetic value" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
  ).gda()
  let (plux067, plux067_flags) = @decimal.Decimal::from_string(
      "56267E+1",
      precision=64,
    )
    .unwrap()
    .plus_ctx(ctx)
  let (plux087, plux087_flags) = @decimal.Decimal::from_string(
      "-56267E+1",
      precision=64,
    )
    .unwrap()
    .plus_ctx(ctx)
  let (minx030, minx030_flags) = @decimal.Decimal::from_string(
      "-5E3",
      precision=64,
    )
    .unwrap()
    .minus_ctx(ctx)
  let (minx034, minx034_flags) = @decimal.Decimal::from_string(
      "+5E3",
      precision=64,
    )
    .unwrap()
    .minus_ctx(ctx)
  assert_eq(
    plux067.compare_total(
      @decimal.Decimal::from_string("5.6267E+5", precision=64).unwrap(),
    ),
    0,
  )
  assert_eq(
    plux087.compare_total(
      @decimal.Decimal::from_string("-5.6267E+5", precision=64).unwrap(),
    ),
    0,
  )
  assert_eq(
    minx030.compare_total(
      @decimal.Decimal::from_string("5E+3", precision=64).unwrap(),
    ),
    0,
  )
  assert_eq(
    minx034.compare_total(
      @decimal.Decimal::from_string("-5E+3", precision=64).unwrap(),
    ),
    0,
  )
  assert_false(plux067_flags.rounded)
  assert_false(plux067_flags.inexact)
  assert_false(plux087_flags.rounded)
  assert_false(plux087_flags.inexact)
  assert_false(minx030_flags.rounded)
  assert_false(minx030_flags.inexact)
  assert_false(minx034_flags.rounded)
  assert_false(minx034_flags.inexact)
}

///|
test "decimal add matches official zero and positive-exponent cohort cases" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
    extended=false,
  )
  run_decimal_binary_conformance_case("add055", Add, "1.3", "-1.30", "0", ctx)
  run_decimal_binary_conformance_case("add072", Add, "1", "0.0", "1", ctx)
  run_decimal_binary_conformance_case("add073", Add, "1", "0.0", "1", ctx)
  run_decimal_binary_conformance_case("add074", Add, "1", "0.00", "1", ctx)
  run_decimal_binary_conformance_case("add077", Add, "0.0", "1", "1", ctx)
  run_decimal_binary_conformance_case("add078", Add, "0.0", "1", "1", ctx)
  run_decimal_binary_conformance_case("add079", Add, "0.00", "1", "1", ctx)
  run_decimal_binary_conformance_case("add105", Add, "-5E1", "0", "-50", ctx)
  run_decimal_binary_conformance_case(
    "add106",
    Add,
    "-5E5",
    "0",
    "-500000",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "add107",
    Add,
    "-5E8",
    "0",
    "-500000000",
    ctx,
  )
  run_decimal_binary_conformance_case("add130", Add, "0", "-5E1", "-50", ctx)
  run_decimal_binary_conformance_case(
    "add131",
    Add,
    "0",
    "-5E5",
    "-500000",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "add132",
    Add,
    "0",
    "-5E8",
    "-500000000",
    ctx,
  )
  let ext_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
  )
  run_decimal_binary_conformance_case(
    "add137",
    Add,
    "1",
    "0E-12",
    "1.00000000",
    ext_ctx,
    rounded=true,
  )
  run_decimal_binary_conformance_case(
    "add138",
    Add,
    "-1",
    "0E-12",
    "-1.00000000",
    ext_ctx,
    rounded=true,
  )
  run_decimal_binary_conformance_case(
    "add139",
    Add,
    "0E-12",
    "1",
    "1.00000000",
    ext_ctx,
    rounded=true,
  )
  run_decimal_binary_conformance_case(
    "add140",
    Add,
    "0E-12",
    "-1",
    "-1.00000000",
    ext_ctx,
    rounded=true,
  )
  run_decimal_binary_conformance_case(
    "add146",
    Add,
    "00.0",
    "0",
    "0.0",
    ext_ctx,
  )
  run_decimal_binary_conformance_case(
    "add147",
    Add,
    "0.00",
    "0",
    "0.00",
    ext_ctx,
  )
  run_decimal_binary_conformance_case(
    "add148",
    Add,
    "0",
    "0.00",
    "0.00",
    ext_ctx,
  )
  run_decimal_binary_conformance_case(
    "add149",
    Add,
    "0",
    "00.0",
    "0.0",
    ext_ctx,
  )
  run_decimal_binary_conformance_case(
    "add150",
    Add,
    "00.0",
    "0.00",
    "0.00",
    ext_ctx,
  )
  run_decimal_binary_conformance_case(
    "add151",
    Add,
    "0.00",
    "00.0",
    "0.00",
    ext_ctx,
  )
  run_decimal_binary_conformance_case(
    "add159",
    Add,
    "0.3",
    "-0.3",
    "0.0",
    ext_ctx,
  )
  run_decimal_binary_conformance_case(
    "add160",
    Add,
    "0.03",
    "-0.03",
    "0.00",
    ext_ctx,
  )
  run_decimal_binary_conformance_case(
    "add321",
    Add,
    "-0.01",
    "0.01",
    "0.00",
    ext_ctx,
  )
  run_decimal_binary_conformance_case(
    "add331",
    Add,
    "0.01",
    "-0.01",
    "0.00",
    ext_ctx,
  )
  run_decimal_binary_conformance_case(
    "add340",
    Add,
    "1E+3",
    "0",
    "1000",
    ext_ctx,
  )
  run_decimal_binary_conformance_case(
    "add341",
    Add,
    "1E+8",
    "0",
    "100000000",
    ext_ctx,
  )
  run_decimal_binary_conformance_case(
    "add342",
    Add,
    "1E+9",
    "0",
    "1.00000000E+9",
    ext_ctx,
    rounded=true,
  )
  run_decimal_binary_conformance_case(
    "add343",
    Add,
    "1E+10",
    "0",
    "1.00000000E+10",
    ext_ctx,
    rounded=true,
  )
  run_decimal_binary_conformance_case(
    "add1500",
    Add,
    "0",
    "0E-19",
    "0E-19",
    ext_ctx,
  )
  run_decimal_binary_conformance_case(
    "add1501",
    Add,
    "-0",
    "0E-19",
    "0E-19",
    ext_ctx,
  )
  run_decimal_binary_conformance_case(
    "add1502",
    Add,
    "0",
    "-0E-19",
    "0E-19",
    ext_ctx,
  )
  run_decimal_binary_conformance_case(
    "add1503",
    Add,
    "-0",
    "-0E-19",
    "-0E-19",
    ext_ctx,
  )
}

///|
test "decimal add matches official tryzeros cohort cases" {
  let ctx = @decimal.DecimalContext::new(
    precision=7,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-92,
    e_max=92,
  )
  run_decimal_binary_conformance_case(
    "add361",
    Add,
    "0E+50",
    "10000E+1",
    "1.0000E+5",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "add362",
    Add,
    "10000E+1",
    "0E-50",
    "100000.0",
    ctx,
    rounded=true,
  )
  run_decimal_binary_conformance_case(
    "add363",
    Add,
    "10000E+1",
    "10000E-50",
    "100000.0",
    ctx,
    rounded=true,
    inexact=true,
  )
  run_decimal_binary_conformance_case(
    "add364",
    Add,
    "9.999999E+92",
    "-9.999999E+92",
    "0E+86",
    ctx,
  )
}

///|
test "decimal multiply preserves official zero sign and cohort cases" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-383,
    e_max=384,
  )
  run_decimal_binary_conformance_case("mul021", Multiply, "0", "0", "0", ctx)
  run_decimal_binary_conformance_case("mul022", Multiply, "0", "-0", "-0", ctx)
  run_decimal_binary_conformance_case("mul023", Multiply, "-0", "0", "-0", ctx)
  run_decimal_binary_conformance_case("mul024", Multiply, "-0", "-0", "0", ctx)
  run_decimal_binary_conformance_case(
    "mul031",
    Multiply,
    "00.00",
    "0.000",
    "0.00000",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "mul032",
    Multiply,
    "00.00",
    "0E-3",
    "0.00000",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "mul033",
    Multiply,
    "0E-3",
    "00.00",
    "0.00000",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "mul035",
    Multiply,
    "-00.00",
    "0.000",
    "-0.00000",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "mul036",
    Multiply,
    "-00.00",
    "0E-3",
    "-0.00000",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "mul037",
    Multiply,
    "-0E-3",
    "00.00",
    "-0.00000",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "mul039",
    Multiply,
    "00.00",
    "-0.000",
    "-0.00000",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "mul040",
    Multiply,
    "00.00",
    "-0E-3",
    "-0.00000",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "mul041",
    Multiply,
    "0E-3",
    "-00.00",
    "-0.00000",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "mul043",
    Multiply,
    "-00.00",
    "-0.000",
    "0.00000",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "mul044",
    Multiply,
    "-00.00",
    "-0E-3",
    "0.00000",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "mul045",
    Multiply,
    "-0E-3",
    "-00.00",
    "0.00000",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "mul053",
    Multiply,
    "0.9",
    "-0",
    "-0.0",
    ctx,
  )
}

///|
test "decimal sqrt preserves official zero sign and cohort cases" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-383,
    e_max=384,
  )
  run_decimal_unary_conformance_case("sqrt005", Sqrt, "0", "0", ctx)
  run_decimal_unary_conformance_case("sqrt006", Sqrt, "00.0", "0.0", ctx)
  run_decimal_unary_conformance_case("sqrt007", Sqrt, "0.00", "0.0", ctx)
  run_decimal_unary_conformance_case("sqrt008", Sqrt, "00.00", "0.0", ctx)
  run_decimal_unary_conformance_case("sqrt009", Sqrt, "00.000", "0.00", ctx)
  run_decimal_unary_conformance_case("sqrt010", Sqrt, "00.0000", "0.00", ctx)
  run_decimal_unary_conformance_case("sqrt016", Sqrt, "-0", "-0", ctx)
  run_decimal_unary_conformance_case("sqrt017", Sqrt, "-0.0", "-0.0", ctx)
  run_decimal_unary_conformance_case("sqrt018", Sqrt, "-00.00", "-0.0", ctx)
  run_decimal_unary_conformance_case("sqrt019", Sqrt, "-00.000", "-0.00", ctx)
  run_decimal_unary_conformance_case("sqrt020", Sqrt, "-0.0000", "-0.00", ctx)
  run_decimal_unary_conformance_case("sqrt021", Sqrt, "-0E+9", "-0E+4", ctx)
  run_decimal_unary_conformance_case("sqrt022", Sqrt, "-0E+10", "-0E+5", ctx)
  run_decimal_unary_conformance_case("sqrt023", Sqrt, "-0E+11", "-0E+5", ctx)
  run_decimal_unary_conformance_case("sqrt024", Sqrt, "-0E+12", "-0E+6", ctx)
  run_decimal_unary_conformance_case("sqrt025", Sqrt, "-00", "-0", ctx)
  run_decimal_unary_conformance_case("sqrt026", Sqrt, "0E+5", "0E+2", ctx)
  run_decimal_unary_conformance_case("sqrt078", Sqrt, "1.000", "1.00", ctx)
  run_decimal_unary_conformance_case("sqrt079", Sqrt, "1.0000", "1.00", ctx)
}

///|
test "decimal divide preserves official zero cohort cases" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-383,
    e_max=384,
  )
  run_decimal_binary_conformance_case("div090", Divide, "0.", "1", "0", ctx)
  run_decimal_binary_conformance_case("div091", Divide, "0.0", "1", "0.0", ctx)
  run_decimal_binary_conformance_case(
    "div092",
    Divide,
    "0.00",
    "1",
    "0.00",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "div093",
    Divide,
    "0.00E+9",
    "1",
    "0E+7",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "div094",
    Divide,
    "0.0000E-50",
    "1",
    "0E-54",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "div302",
    Divide,
    "0",
    "7E-5",
    "0E+5",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "div303",
    Divide,
    "0",
    "7E-1",
    "0E+1",
    ctx,
  )
  run_decimal_binary_conformance_case("div304", Divide, "0", "7E+1", "0.0", ctx)
  run_decimal_binary_conformance_case(
    "div305",
    Divide,
    "0",
    "7E+5",
    "0.00000",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "div306",
    Divide,
    "0",
    "7E+6",
    "0.000000",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "div307",
    Divide,
    "0",
    "7E+7",
    "0E-7",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "div322",
    Divide,
    "0",
    "700E+77",
    "0E-77",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "div331",
    Divide,
    "0E-3",
    "7E-5",
    "0E+2",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "div332",
    Divide,
    "0E-3",
    "7E-1",
    "0.00",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "div333",
    Divide,
    "0E-3",
    "7E+1",
    "0.0000",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "div334",
    Divide,
    "0E-3",
    "7E+5",
    "0E-8",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "div339",
    Divide,
    "0E+1",
    "7E-5",
    "0E+6",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "div340",
    Divide,
    "0E+1",
    "7E-1",
    "0E+2",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "div341",
    Divide,
    "0E+1",
    "7E+1",
    "0",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "div342",
    Divide,
    "0E+1",
    "7E+5",
    "0.0000",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "div343",
    Divide,
    "0E+3",
    "7E-5",
    "0E+8",
    ctx,
  )
}

///|
test "decimal divide preserves exact quotient cohort representatives" {
  let ctx = @decimal.DecimalContext::new(
    precision=16,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-383,
    e_max=384,
    clamp=true,
  )
  run_decimal_binary_conformance_case(
    "dddiv014",
    Divide,
    "2.40",
    "1",
    "2.40",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "dddiv015",
    Divide,
    "2.400",
    "1",
    "2.400",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "dddiv017",
    Divide,
    "2.400",
    "2",
    "1.200",
    ctx,
  )
}

///|
test "decimal divide preserves exact positive-exponent representatives" {
  let ctx = @decimal.DecimalContext::new(
    precision=16,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-383,
    e_max=384,
    clamp=true,
  )
  run_decimal_binary_conformance_case(
    "dddiv095",
    Divide,
    "1",
    "1E-8",
    "1E+8",
    ctx,
  )
}

///|
test "decimal divide preserves inexact subnormal cohort at etiny" {
  let ctx = @decimal.DecimalContext::new(
    precision=16,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-383,
    e_max=384,
    clamp=true,
  )
  run_decimal_binary_conformance_case(
    "dddiv272",
    Divide,
    "1",
    "0.99e384",
    "1.01010101010101E-384",
    ctx,
    rounded=true,
    inexact=true,
    underflow=true,
    subnormal=true,
  )
  run_decimal_binary_conformance_case(
    "dddiv273",
    Divide,
    "1",
    "0.9999999999999999e384",
    "1.00000000000000E-384",
    ctx,
    rounded=true,
    inexact=true,
    underflow=true,
    subnormal=true,
  )
}

///|
test "decimal divide keeps enough working digits for rounded reciprocals" {
  let ctx = @decimal.DecimalContext::new(
    precision=16,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-383,
    e_max=384,
    clamp=true,
  )
  run_decimal_binary_conformance_case(
    "dddiv442",
    Divide,
    "1",
    "12345678000",
    "8.100000664200054E-11",
    ctx,
    rounded=true,
    inexact=true,
  )
  run_decimal_binary_conformance_case(
    "dddiv444",
    Divide,
    "1",
    "1234567800",
    "8.100000664200054E-10",
    ctx,
    rounded=true,
    inexact=true,
  )
}

///|
test "decimal subtract preserves rhs nan sign while canonicalizing payload" {
  let interchange = @decimal.DecimalInterchange::from_hex(
    "#7c03ff3fcff3fcff",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  assert_eq(interchange.canonical().to_hex(), "#7C00FF3FCFF3FCFF")
  let decimal = interchange.to_decimal()
  let zero = @decimal.Decimal::zero(precision=16)
  let ctx = @decimal.DecimalInterchangeFormat::Decimal64.context()
  let (subtracted, flags) = zero.sub_ctx(decimal, ctx)
  let (sub_hex, _) = subtracted.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  assert_eq(sub_hex, "#7C00FF3FCFF3FCFF")
  assert_false(flags.invalid_operation)
}

///|
test "decimal divide preserves rounded exact cohorts across normal and subnormal cases" {
  let ctx9 = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-383,
    e_max=384,
    extended=true,
  )
  let ctx6 = @decimal.DecimalContext::new(
    precision=6,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-383,
    e_max=384,
    extended=true,
  )
  let (v71, f71) = @decimal.Decimal::from_string("999999999.4", precision=20)
    .unwrap()
    .div_ctx(@decimal.Decimal::from_string("1", precision=20).unwrap(), ctx9)
  assert_eq(v71.to_string(), "999999999")
  assert_true(f71.rounded)
  assert_true(f71.inexact)

  let (v401, f401) = @decimal.Decimal::from_string("12345678000", precision=20)
    .unwrap()
    .div_ctx(@decimal.Decimal::from_string("1", precision=20).unwrap(), ctx9)
  assert_eq(v401.coefficient().to_string(), "123456780")
  assert_eq(v401.exponent10().to_string(), "2")
  assert_true(f401.rounded)
  assert_false(f401.inexact)

  let (v80, f80) = @decimal.Decimal::from_string("999999999", precision=20)
    .unwrap()
    .div_ctx(@decimal.Decimal::from_string("1", precision=20).unwrap(), ctx6)
  assert_eq(v80.coefficient().to_string(), "100000")
  assert_eq(v80.exponent10().to_string(), "4")
  assert_true(f80.rounded)
  assert_true(f80.inexact)

  let ctx5 = @decimal.DecimalContext::new(
    precision=5,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-79,
    e_max=79,
    extended=true,
  )
  let (v1002, f1002) = @decimal.Decimal::from_string(
      "1.52445E-80",
      precision=20,
    )
    .unwrap()
    .div_ctx(@decimal.Decimal::from_string("1", precision=20).unwrap(), ctx5)
  assert_eq(v1002.coefficient().to_string(), "1524")
  assert_eq(v1002.exponent10().to_string(), "-83")
  assert_true(f1002.rounded)
  assert_true(f1002.inexact)
  assert_true(f1002.subnormal)
  assert_true(f1002.underflow)
}

///|
test "decimal absorbed subtract half-up ties keep away-from-zero representative" {
  let dd_ctx = @decimal.DecimalContext::new(
    precision=16,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-383,
    e_max=384,
    clamp=true,
    extended=true,
  )
  run_decimal_binary_conformance_case(
    "ddsub508",
    Subtract,
    "1231234567456789",
    "0.5",
    "1231234567456789",
    dd_ctx,
    rounded=true,
    inexact=true,
  )
  run_decimal_binary_conformance_case(
    "ddsub608",
    Subtract,
    "0.5",
    "1231234567456789",
    "-1231234567456789",
    dd_ctx,
    rounded=true,
    inexact=true,
  )
}

///|
test "decimal context exact zero result clamps below etiny" {
  let ctx = @decimal.DecimalContext::new(precision=3, e_min=-999, e_max=999)
  let lhs = @decimal.Decimal::from_string("0.100E-999", precision=64).unwrap()
  let rhs = @decimal.Decimal::from_string("-0.1E-999", precision=64).unwrap()
  let (sum, flags) = lhs.add_ctx(rhs, ctx)
  let expected = @decimal.Decimal::from_string("0E-1001", precision=64).unwrap()
  assert_eq(sum.compare_total(expected).to_string(), "0")
  assert_true(flags.clamped)
  assert_false(flags.inexact)
  assert_false(flags.underflow)
}

///|
test "decimal context clamps zero exponent at upper cohort bound" {
  let ctx = @decimal.DecimalContext::new(
    precision=16,
    e_min=-383,
    e_max=384,
    clamp=true,
  )
  let pos = @decimal.Decimal::from_string("0E+500", precision=32).unwrap()
  let neg = @decimal.Decimal::from_string("-0E+500", precision=32).unwrap()
  let (pos_value, pos_flags) = pos.apply_ctx(ctx)
  let (neg_value, neg_flags) = neg.apply_ctx(ctx)
  assert_eq(
    pos_value
    .compare_total(
      @decimal.Decimal::from_string("0E+369", precision=32).unwrap(),
    )
    .to_string(),
    "0",
  )
  assert_eq(
    neg_value
    .compare_total(
      @decimal.Decimal::from_string("-0E+369", precision=32).unwrap(),
    )
    .to_string(),
    "0",
  )
  assert_true(pos_flags.clamped)
  assert_true(neg_flags.clamped)
}

///|
test "decimal apply_ctx clamps finite fold-down without rounded flag" {
  let ctx = @decimal.DecimalContext::new(
    precision=16,
    e_min=-383,
    e_max=384,
    clamp=true,
  )
  let pos = @decimal.Decimal::from_string("1.23E+384", precision=32).unwrap()
  let neg_zero = @decimal.Decimal::from_string("-0E+500", precision=32).unwrap()
  let (pos_value, pos_flags) = pos.apply_ctx(ctx)
  let (neg_zero_value, neg_zero_flags) = neg_zero.apply_ctx(ctx)
  assert_eq(
    pos_value
    .compare_total(
      @decimal.Decimal::from_string("1.230000000000000E+384", precision=32).unwrap(),
    )
    .to_string(),
    "0",
  )
  assert_true(pos_flags.clamped)
  assert_false(pos_flags.rounded)
  assert_eq(
    neg_zero_value
    .compare_total(
      @decimal.Decimal::from_string("-0E+369", precision=32).unwrap(),
    )
    .to_string(),
    "0",
  )
  assert_true(neg_zero_flags.clamped)
}

///|
test "decimal qnan snan and payload stay observable" {
  let quiet = @decimal.Decimal::quiet_nan(
    payload=42N,
    negative=true,
    precision=9,
  )
  let signaling = @decimal.Decimal::signaling_nan(payload=7N, precision=9)
  assert_true(quiet.is_quiet_nan())
  assert_false(quiet.is_signaling_nan())
  assert_true(quiet.is_negative())
  assert_eq(quiet.nan_payload(), 42N)
  assert_eq(quiet.to_string(), "-nan42")
  assert_true(signaling.is_signaling_nan())
  assert_false(signaling.is_quiet_nan())
  assert_eq(signaling.nan_payload(), 7N)
  assert_eq(signaling.to_string(), "snan7")
  assert_true(quiet == signaling)
  assert_true(
    signaling.with_precision(3, RoundingMode::ToNearestEven).is_signaling_nan(),
  )
}

///|
test "decimal apply_ctx quiets snan and preserves nan diagnostics" {
  let ctx = @decimal.DecimalContext::new(precision=3)
  let quiet = @decimal.Decimal::quiet_nan(
    payload=12345N,
    negative=true,
    precision=8,
  )
  let signaling = @decimal.Decimal::signaling_nan(
    payload=98765N,
    negative=true,
    precision=8,
  )
  let (quiet_applied, quiet_flags) = quiet.apply_ctx(ctx)
  let (signal_applied, signal_flags) = signaling.apply_ctx(ctx)
  assert_eq(quiet_applied.to_string(), "-nan345")
  assert_true(quiet_applied.is_quiet_nan())
  assert_true(quiet_applied.is_negative())
  assert_eq(quiet_applied.nan_payload(), 345N)
  assert_false(quiet_flags.invalid_operation)
  assert_eq(signal_applied.to_string(), "-nan765")
  assert_true(signal_applied.is_quiet_nan())
  assert_false(signal_applied.is_signaling_nan())
  assert_true(signal_applied.is_negative())
  assert_eq(signal_applied.nan_payload(), 765N)
  assert_true(signal_flags.invalid_operation)
}

///|
test "decimal addition propagates nan payloads" {
  let ctx = @decimal.DecimalContext::new(precision=9)
  let quiet = @decimal.Decimal::quiet_nan(payload=17N, precision=12)
  let (quiet_sum, quiet_flags) = quiet.add_ctx(
    @decimal.Decimal::inf(@def.Sign::Negative),
    ctx,
  )
  assert_eq(
    quiet_sum
    .compare_total(@decimal.Decimal::quiet_nan(payload=17N, precision=9))
    .to_string(),
    "0",
  )
  assert_false(quiet_flags.invalid_operation)
  let signaling = @decimal.Decimal::signaling_nan(payload=23N, precision=12)
  let (signaled, signal_flags) = @decimal.Decimal::one().add_ctx(signaling, ctx)
  assert_eq(
    signaled
    .compare_total(@decimal.Decimal::quiet_nan(payload=23N, precision=9))
    .to_string(),
    "0",
  )
  assert_true(signal_flags.invalid_operation)
}

///|
test "decimal multiplication propagates nan payloads" {
  let ctx = @decimal.DecimalContext::new(precision=9)
  let quiet = @decimal.Decimal::quiet_nan(
    payload=12345N,
    negative=true,
    precision=12,
  )
  let signaling = @decimal.Decimal::signaling_nan(payload=23N, precision=12)
  let (quiet_product, quiet_flags) = quiet.mul_ctx(
    @decimal.Decimal::from_int(2),
    ctx,
  )
  let (signaled, signal_flags) = @decimal.Decimal::one().mul_ctx(signaling, ctx)
  assert_eq(quiet_product.to_string(), "-nan12345")
  assert_true(quiet_product.is_quiet_nan())
  assert_true(quiet_product.is_negative())
  assert_eq(quiet_product.nan_payload(), 12345N)
  assert_false(quiet_flags.invalid_operation)
  assert_eq(signaled.to_string(), "nan23")
  assert_true(signaled.is_quiet_nan())
  assert_false(signaled.is_signaling_nan())
  assert_eq(signaled.nan_payload(), 23N)
  assert_true(signal_flags.invalid_operation)
}

///|
test "decimal multiply official0 subnormal underflow rows set full gda flags" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999999999,
    e_max=999999999,
    extended=false,
  )
  let (mul232, mul232_flags) = @decimal.Decimal::from_string(
      "+0.100",
      precision=64,
    )
    .unwrap()
    .mul_ctx(
      @decimal.Decimal::from_string("9E-999999999", precision=64).unwrap(),
      ctx,
    )
  let (mul233, mul233_flags) = @decimal.Decimal::from_string(
      "9E-999999999",
      precision=64,
    )
    .unwrap()
    .mul_ctx(
      @decimal.Decimal::from_string("+0.100", precision=64).unwrap(),
      ctx,
    )
  let (mul237, mul237_flags) = @decimal.Decimal::from_string(
      "-0.100",
      precision=64,
    )
    .unwrap()
    .mul_ctx(
      @decimal.Decimal::from_string("9E-999999999", precision=64).unwrap(),
      ctx,
    )
  let (mul238, mul238_flags) = @decimal.Decimal::from_string(
      "9E-999999999",
      precision=64,
    )
    .unwrap()
    .mul_ctx(
      @decimal.Decimal::from_string("-0.100", precision=64).unwrap(),
      ctx,
    )
  assert_true(mul232.is_finite(), msg="mul232 finite")
  assert_true(mul233.is_finite(), msg="mul233 finite")
  assert_true(mul237.is_finite(), msg="mul237 finite")
  assert_true(mul238.is_finite(), msg="mul238 finite")
  assert_true(mul232_flags.underflow, msg="mul232 underflow")
  assert_true(mul232_flags.subnormal, msg="mul232 subnormal")
  assert_true(mul232_flags.inexact, msg="mul232 inexact")
  assert_true(mul232_flags.rounded, msg="mul232 rounded")
  assert_true(mul233_flags.underflow, msg="mul233 underflow")
  assert_true(mul233_flags.subnormal, msg="mul233 subnormal")
  assert_true(mul233_flags.inexact, msg="mul233 inexact")
  assert_true(mul233_flags.rounded, msg="mul233 rounded")
  assert_true(mul237_flags.underflow, msg="mul237 underflow")
  assert_true(mul237_flags.subnormal, msg="mul237 subnormal")
  assert_true(mul237_flags.inexact, msg="mul237 inexact")
  assert_true(mul237_flags.rounded, msg="mul237 rounded")
  assert_true(mul238_flags.underflow, msg="mul238 underflow")
  assert_true(mul238_flags.subnormal, msg="mul238 subnormal")
  assert_true(mul238_flags.inexact, msg="mul238 inexact")
  assert_true(mul238_flags.rounded, msg="mul238 rounded")
}

///|
test "decimal multiply official0 extended underflow rows keep subset flags on larger exponents" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999999999,
    e_max=999999999,
    extended=false,
  )
  let (mul239, mul239_flags) = @decimal.Decimal::from_string(
      "1E-599999999",
      precision=64,
    )
    .unwrap()
    .mul_ctx(
      @decimal.Decimal::from_string("1E-400000001", precision=64).unwrap(),
      ctx,
    )
  let (mul241, mul241_flags) = @decimal.Decimal::from_string(
      "1E-600000000",
      precision=64,
    )
    .unwrap()
    .mul_ctx(
      @decimal.Decimal::from_string("1E-400000000", precision=64).unwrap(),
      ctx,
    )
  let (mul242, mul242_flags) = @decimal.Decimal::from_string(
      "9E-999999998",
      precision=64,
    )
    .unwrap()
    .mul_ctx(@decimal.Decimal::from_string("0.01", precision=64).unwrap(), ctx)
  let (mul244, mul244_flags) = @decimal.Decimal::from_string(
      "0.01",
      precision=64,
    )
    .unwrap()
    .mul_ctx(
      @decimal.Decimal::from_string("9E-999999998", precision=64).unwrap(),
      ctx,
    )
  assert_true(mul239.is_finite(), msg="mul239 finite")
  assert_true(mul241.is_finite(), msg="mul241 finite")
  assert_true(mul242.is_finite(), msg="mul242 finite")
  assert_true(mul244.is_finite(), msg="mul244 finite")
  assert_true(mul239_flags.underflow, msg="mul239 underflow")
  assert_true(mul239_flags.subnormal, msg="mul239 subnormal")
  assert_true(mul239_flags.inexact, msg="mul239 inexact")
  assert_true(mul239_flags.rounded, msg="mul239 rounded")
  assert_true(mul241_flags.underflow, msg="mul241 underflow")
  assert_true(mul241_flags.subnormal, msg="mul241 subnormal")
  assert_true(mul241_flags.inexact, msg="mul241 inexact")
  assert_true(mul241_flags.rounded, msg="mul241 rounded")
  assert_true(mul242_flags.underflow, msg="mul242 underflow")
  assert_true(mul242_flags.subnormal, msg="mul242 subnormal")
  assert_true(mul242_flags.inexact, msg="mul242 inexact")
  assert_true(mul242_flags.rounded, msg="mul242 rounded")
  assert_true(mul244_flags.underflow, msg="mul244 underflow")
  assert_true(mul244_flags.subnormal, msg="mul244 subnormal")
  assert_true(mul244_flags.inexact, msg="mul244 inexact")
  assert_true(mul244_flags.rounded, msg="mul244 rounded")
}

///|
test "decimal multiply official0 deepest underflow rows keep subset flags" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999999999,
    e_max=999999999,
    extended=false,
  )
  let rhs_cases = [
    "1E-400000001", "1E-400000002", "1E-400000003", "1E-400000004", "1E-400000005",
    "1E-400000006", "1E-400000007", "1E-400000008", "1E-400000009", "1E-400000010",
  ]
  let lhs = @decimal.Decimal::from_string("1E-600000000", precision=64).unwrap()
  for rhs_src in rhs_cases {
    let rhs = @decimal.Decimal::from_string(rhs_src, precision=64).unwrap()
    let (actual, flags) = lhs.mul_ctx(rhs, ctx)
    assert_true(actual.is_finite(), msg=rhs_src + " finite")
    assert_true(flags.underflow, msg=rhs_src + " underflow")
    assert_true(flags.subnormal, msg=rhs_src + " subnormal")
    assert_true(flags.inexact, msg=rhs_src + " inexact")
    assert_true(flags.rounded, msg=rhs_src + " rounded")
    assert_false(flags.clamped, msg=rhs_src + " clamped")
  }
}

///|
test "decimal multiply official0 deepest overflow rows keep subset flags" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999999999,
    e_max=999999999,
    extended=false,
  )
  let lhs = @decimal.Decimal::from_string("1E+600000000", precision=64).unwrap()
  let rhs_cases = [
    "1E+400000001", "1E+400000002", "1E+400000003", "1E+400000004", "1E+400000005",
    "1E+400000006", "1E+400000007", "1E+400000008", "1E+400000009", "1E+400000010",
  ]
  for rhs_src in rhs_cases {
    let rhs = @decimal.Decimal::from_string(rhs_src, precision=64).unwrap()
    let (actual, flags) = lhs.mul_ctx(rhs, ctx)
    assert_true(actual.is_infinite(), msg=rhs_src + " overflow result")
    assert_true(flags.overflow, msg=rhs_src + " overflow")
    assert_true(flags.inexact, msg=rhs_src + " inexact")
    assert_true(flags.rounded, msg=rhs_src + " rounded")
  }
}

///|
test "decimal division propagates nan payloads" {
  let ctx = @decimal.DecimalContext::new(precision=9)
  let quiet = @decimal.Decimal::quiet_nan(
    payload=95N,
    negative=true,
    precision=12,
  )
  let signaling = @decimal.Decimal::signaling_nan(payload=93N, precision=12)
  let (quiet_quotient, quiet_flags) = quiet.div_ctx(
    @decimal.Decimal::from_int(2),
    ctx,
  )
  let (signaled, signal_flags) = @decimal.Decimal::one().div_ctx(signaling, ctx)
  assert_eq(quiet_quotient.to_string(), "-nan95")
  assert_true(quiet_quotient.is_quiet_nan())
  assert_true(quiet_quotient.is_negative())
  assert_eq(quiet_quotient.nan_payload(), 95N)
  assert_false(quiet_flags.invalid_operation)
  assert_eq(signaled.to_string(), "nan93")
  assert_true(signaled.is_quiet_nan())
  assert_false(signaled.is_signaling_nan())
  assert_eq(signaled.nan_payload(), 93N)
  assert_true(signal_flags.invalid_operation)
}

///|
test "decimal division follows official nan priority cases" {
  let ctx = @decimal.DecimalContext::new(precision=9).gda()
  run_decimal_binary_conformance_case(
    "divx861",
    DecimalConformanceOp::Divide,
    "NaN9",
    "-Inf",
    "NaN9",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "divx875",
    DecimalConformanceOp::Divide,
    "NaN95",
    "sNaN93",
    "NaN93",
    ctx,
    invalid_operation=true,
  )
  run_decimal_binary_conformance_case(
    "divx899",
    DecimalConformanceOp::Divide,
    "-NaN",
    "-sNaN89",
    "-NaN89",
    ctx,
    invalid_operation=true,
  )
}

///|
test "plain decimal arithmetic preserves nan payloads and quiets snans" {
  let qnan = @decimal.Decimal::quiet_nan(
    payload=17N,
    negative=true,
    precision=12,
  )
  let snan = @decimal.Decimal::signaling_nan(payload=23N, precision=12)
  let add_result = qnan + @decimal.Decimal::one()
  let mul_result = @decimal.Decimal::from_int(2) * snan
  let div_result = @decimal.Decimal::from_int(1) / qnan
  assert_eq(add_result.to_string(), "-nan17")
  assert_true(add_result.is_quiet_nan())
  assert_true(add_result.is_negative())
  assert_eq(add_result.nan_payload(), 17N)
  assert_eq(mul_result.to_string(), "nan23")
  assert_true(mul_result.is_quiet_nan())
  assert_false(mul_result.is_signaling_nan())
  assert_eq(mul_result.nan_payload(), 23N)
  assert_eq(div_result.to_string(), "-nan17")
  assert_true(div_result.is_quiet_nan())
  assert_true(div_result.is_negative())
  assert_eq(div_result.nan_payload(), 17N)
}

///|
test "decimal fma propagates highest-priority nan payloads" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    e_min=-999999,
    e_max=999999,
  ).gda()
  let qnan = @decimal.Decimal::quiet_nan(payload=7N, precision=12)
  let qnan2 = @decimal.Decimal::quiet_nan(
    payload=5N,
    negative=true,
    precision=12,
  )
  let snan = @decimal.Decimal::signaling_nan(payload=19N, precision=12)
  let snan2 = @decimal.Decimal::signaling_nan(
    payload=23N,
    negative=true,
    precision=12,
  )
  let (quiet_result, quiet_flags) = @decimal.Decimal::zero().fma_ctx(
    qnan, qnan2, ctx,
  )
  let (signal_result, signal_flags) = @decimal.Decimal::one().fma_ctx(
    qnan, snan, ctx,
  )
  let (negative_signal_result, negative_signal_flags) = @decimal.Decimal::one().fma_ctx(
    @decimal.Decimal::from_int(1000),
    snan2,
    ctx,
  )
  assert_eq(quiet_result.to_string(), "nan7")
  assert_eq(quiet_result.nan_payload(), 7N)
  assert_false(quiet_flags.invalid_operation)
  assert_eq(signal_result.to_string(), "nan19")
  assert_eq(signal_result.nan_payload(), 19N)
  assert_true(signal_flags.invalid_operation)
  assert_eq(negative_signal_result.to_string(), "-nan23")
  assert_true(negative_signal_result.is_negative())
  assert_eq(negative_signal_result.nan_payload(), 23N)
  assert_true(negative_signal_flags.invalid_operation)
}

///|
test "decimal fma is invalid in subset context" {
  let subset_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-383,
    e_max=384,
    extended=false,
  )
  let huge_zero = @decimal.Decimal::from_string("0E+999999", precision=32).unwrap()
  let (zero_case, zero_flags) = @decimal.Decimal::zero(precision=16).fma_ctx(
    @decimal.Decimal::zero(precision=16),
    huge_zero,
    subset_ctx,
  )
  let (finite_case, finite_flags) = @decimal.Decimal::from_string(
      "0.9",
      precision=16,
    )
    .unwrap()
    .fma_ctx(
      @decimal.Decimal::from_string("0.8", precision=16).unwrap(),
      huge_zero,
      subset_ctx,
    )
  assert_true(zero_case.is_nan())
  assert_true(zero_flags.invalid_operation)
  assert_true(finite_case.is_nan())
  assert_true(finite_flags.invalid_operation)
}

///|
test "decimal fma handles infinite addends with direct infinity semantics" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    e_min=-999999,
    e_max=999999,
  )
  let pos_inf = @decimal.Decimal::inf(@def.Sign::Positive, precision=16)
  let neg_inf = @decimal.Decimal::inf(@def.Sign::Negative, precision=16)
  let one = @decimal.Decimal::one(precision=16)
  let two = @decimal.Decimal::from_int(2, precision=16)
  let minus_one = @decimal.Decimal::from_int(-1, precision=16)

  let (finite_plus_inf, finite_plus_inf_flags) = one.fma_ctx(two, pos_inf, ctx)
  let (matching_inf, matching_inf_flags) = pos_inf.fma_ctx(two, pos_inf, ctx)
  let (opposite_inf, opposite_inf_flags) = one.fma_ctx(neg_inf, pos_inf, ctx)
  let (negative_finite_plus_inf, negative_finite_plus_inf_flags) = minus_one.fma_ctx(
    two, pos_inf, ctx,
  )

  assert_true(finite_plus_inf.is_infinite())
  assert_false(finite_plus_inf.is_negative())
  assert_false(finite_plus_inf_flags.invalid_operation)
  assert_true(matching_inf.is_infinite())
  assert_false(matching_inf.is_negative())
  assert_false(matching_inf_flags.invalid_operation)
  assert_true(negative_finite_plus_inf.is_infinite())
  assert_false(negative_finite_plus_inf.is_negative())
  assert_false(negative_finite_plus_inf_flags.invalid_operation)
  assert_true(opposite_inf.is_nan())
  assert_true(opposite_inf_flags.invalid_operation)
}

///|
test "decimal fma preserves directed overflow when tiny addend cannot affect result" {
  let ctx = @decimal.DecimalContext::new(
    precision=34,
    decimal_rounding=@decimal.DecimalRoundingMode::Up,
    e_min=-6143,
    e_max=6144,
    clamp=true,
    extended=true,
  )
  let lhs = @decimal.Decimal::from_string("-9E6144", precision=64).unwrap()
  let positive_lhs = @decimal.Decimal::from_string("9E6144", precision=64).unwrap()
  let rhs = @decimal.Decimal::from_string("10", precision=64).unwrap()
  let third = @decimal.Decimal::from_string("1", precision=64).unwrap()
  let (positive, positive_flags) = positive_lhs.fma_ctx(rhs, third, ctx)
  let (negative, negative_flags) = lhs.fma_ctx(rhs, third, ctx)
  assert_true(positive.is_infinite())
  assert_false(positive.is_negative())
  assert_true(positive_flags.overflow)
  assert_true(positive_flags.inexact)
  assert_true(positive_flags.rounded)
  assert_true(negative.is_infinite())
  assert_true(negative.is_negative())
  assert_true(negative_flags.overflow)
  assert_true(negative_flags.inexact)
  assert_true(negative_flags.rounded)
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
test "decimal checked division maps zero-zero and signaling nan to domain errors" {
  let zero = @decimal.Decimal::zero(precision=20)
  let snan = @decimal.Decimal::signaling_nan(payload=7N, precision=20)
  match zero.div_checked(zero) {
    Ok(_) => fail("expected zero divided by zero to be a domain error")
    Err(err) => assert_true(err.is_domain_error())
  }
  match @decimal.Decimal::one(precision=20).div_checked(snan) {
    Ok(_) => fail("expected signaling NaN division to be a domain error")
    Err(err) => assert_true(err.is_domain_error())
  }
}

///|
test "decimal generic checked division projects context flags to arithmetic errors" {
  let zero = @decimal.Decimal::zero(precision=20)
  match div_checked_generic(zero, zero, checked_ctx) {
    Ok(_) => fail("expected zero divided by zero to fail")
    Err(err) => assert_true(err.is_domain_error())
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
test "decimal from_double and from_float preserve negative zero" {
  let from_double = @decimal.Decimal::from_double(-0.0, precision=20)
  let from_float = @decimal.Decimal::from_float(
    Float::from_double(-0.0),
    precision=20,
  )
  assert_true(from_double.is_negative_zero())
  assert_eq(from_double.to_string(), "-0")
  assert_true(from_float.is_negative_zero())
  assert_eq(from_float.to_string(), "-0")
}

///|
test "decimal from_double and from_float preserve nan sign bit" {
  let positive_nan = 0x7ff8_0000_0000_0000UL.reinterpret_as_double()
  let negative_nan = 0xfff8_0000_0000_0000UL.reinterpret_as_double()
  let from_double_pos = @decimal.Decimal::from_double(
    positive_nan,
    precision=20,
  )
  let from_double_neg = @decimal.Decimal::from_double(
    negative_nan,
    precision=20,
  )
  let from_float_neg = @decimal.Decimal::from_float(
    Float::from_double(negative_nan),
    precision=20,
  )
  assert_true(from_double_pos.is_qnan())
  assert_false(from_double_pos.is_negative())
  assert_true(from_double_neg.is_qnan())
  assert_true(from_double_neg.is_negative())
  assert_true(from_float_neg.is_qnan())
  assert_true(from_float_neg.is_negative())
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
  match
    square_checked(
      @decimal.Decimal::quiet_nan(payload=7N, precision=24),
      checked_ctx,
    ) {
    Ok(value) => {
      assert_true(value.is_quiet_nan())
      assert_eq(value.nan_payload(), 7N)
    }
    Err(_) => fail("expected checked decimal quiet NaN power to succeed")
  }
  match
    square_checked(
      @decimal.Decimal::signaling_nan(payload=9N, precision=24),
      checked_ctx,
    ) {
    Ok(_) => fail("expected checked decimal signaling NaN power to fail")
    Err(err) => assert_true(err.is_domain_error())
  }
  match
    reciprocal_power_checked(
      @decimal.Decimal::signaling_nan(payload=11N, precision=24),
      -1,
      checked_ctx,
    ) {
    Ok(_) =>
      fail("expected checked decimal signaling NaN reciprocal power to fail")
    Err(err) => assert_true(err.is_domain_error())
  }
}

///|
test "decimal integral homomorphism preserves canonical decimal form" {
  let value : @decimal.Decimal = from_integral_generic(1200N)
  assert_eq(value, @decimal.Decimal::from_bigint(1200N).normalized())
  assert_eq(decimal_coeff_signed(value), 12N)
  assert_eq(value.exponent10(), 2)
}

///|
test "decimal interchange decodes official finite encodings" {
  let ds = @decimal.Decimal::from_interchange_hex(
    "#A23003D0",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let dd = @decimal.Decimal::from_interchange_hex(
    "#A2300000000003D0",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let dq = @decimal.Decimal::from_interchange_hex(
    "#A20780000000000000000000000003D0",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let expected = @decimal.Decimal::from_string("-7.50", precision=64).unwrap()
  assert_eq(ds.compare_total(expected).to_string(), "0")
  assert_eq(dd.compare_total(expected).to_string(), "0")
  assert_eq(dq.compare_total(expected).to_string(), "0")

  let canonical32 = @decimal.Decimal::from_interchange_hex(
    "#77F3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let noncanonical128 = @decimal.Decimal::from_interchange_hex(
    "#77FFFFF3FCFF3FCFF3FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  assert_eq(
    canonical32
    .compare_total(
      @decimal.Decimal::from_string("9.999999E+96", precision=64).unwrap(),
    )
    .to_string(),
    "0",
  )
  assert_eq(
    noncanonical128
    .compare_total(
      @decimal.Decimal::from_string(
        "9.999999999999999999999999999999999E+6144",
        precision=64,
      ).unwrap(),
    )
    .to_string(),
    "0",
  )
}

///|
test "decimal interchange formats expose the expected preset contexts" {
  let decimal32 = @decimal.DecimalInterchangeFormat::Decimal32.context()
  let decimal64 = @decimal.DecimalInterchangeFormat::Decimal64.context()
  let decimal128 = @decimal.DecimalInterchangeFormat::Decimal128.context()
  assert_true(decimal32 == @decimal.DecimalContext::decimal32().ieee754())
  assert_true(decimal64 == @decimal.DecimalContext::decimal64().ieee754())
  assert_true(decimal128 == @decimal.DecimalContext::decimal128().ieee754())
}

///|
test "decimal interchange input accepts trim optional hash and lowercase" {
  let plain32 = @decimal.Decimal::from_interchange_hex(
    "a23003d0",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let plain = @decimal.Decimal::from_interchange_hex(
    "a2300000000003d0",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let plain128 = @decimal.Decimal::from_interchange_hex(
    "a20780000000000000000000000003d0",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let spaced = @decimal.Decimal::from_interchange_hex(
    "  #a2300000000003d0  ",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let spaced32 = @decimal.Decimal::from_interchange_hex(
    " \t#a23003d0\r",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let tabbed = @decimal.Decimal::from_interchange_hex(
    "\t#a2300000000003d0\n",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let tabbed128 = @decimal.Decimal::from_interchange_hex(
    "\t#a20780000000000000000000000003d0\n",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let expected = @decimal.Decimal::from_string("-7.50", precision=64).unwrap()
  assert_eq(plain32.compare_total(expected).to_string(), "0")
  assert_eq(plain.compare_total(expected).to_string(), "0")
  assert_eq(plain128.compare_total(expected).to_string(), "0")
  assert_eq(spaced32.compare_total(expected).to_string(), "0")
  assert_eq(spaced.compare_total(expected).to_string(), "0")
  assert_eq(tabbed.compare_total(expected).to_string(), "0")
  assert_eq(tabbed128.compare_total(expected).to_string(), "0")

  let raw = @decimal.DecimalInterchange::from_hex(
    "  77ffff3fcff3fcff  ",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let raw32 = @decimal.DecimalInterchange::from_hex(
    " \t#a23003d0\r",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let raw_hashed = @decimal.DecimalInterchange::from_hex(
    "#77ffff3fcff3fcff",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let raw_tabbed = @decimal.DecimalInterchange::from_hex(
    "\t77ffff3fcff3fcff\r",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let raw128 = @decimal.DecimalInterchange::from_hex(
    "\t#a20780000000000000000000000003d0\n",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  assert_eq(raw32.to_hex(), "#A23003D0")
  assert_eq(raw.to_hex(), "#77FFFF3FCFF3FCFF")
  assert_eq(raw_hashed.to_hex(), "#77FFFF3FCFF3FCFF")
  assert_eq(raw_tabbed.to_hex(), "#77FFFF3FCFF3FCFF")
  assert_eq(raw128.to_hex(), "#A20780000000000000000000000003D0")

  let bad_length = @decimal.Decimal::from_interchange_hex(
    "#A23003D",
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  assert_true(bad_length == None)
  assert_true(
    @decimal.DecimalInterchange::from_hex(
      "#A23003D",
      @decimal.DecimalInterchangeFormat::Decimal32,
    )
    is None,
  )

  let bad_digit = @decimal.DecimalInterchange::from_hex(
    "#77FFFF3FCFF3FCFG",
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  assert_true(
    @decimal.Decimal::from_interchange_hex(
      "#77FFFF3FCFF3FCFG",
      @decimal.DecimalInterchangeFormat::Decimal64,
    )
    is None,
  )
  match bad_digit {
    None => ()
    Some(_) => fail("expected invalid interchange digit to be rejected")
  }
}

///|
test "decimal interchange to_hex preserves fixed width and uppercase" {
  let raw32 = @decimal.DecimalInterchange::from_hex(
    "00000001",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let raw64 = @decimal.DecimalInterchange::from_hex(
    "00000000000000ff",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let raw128 = @decimal.DecimalInterchange::from_hex(
    "000000000000000000000000000000ff",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  assert_eq(raw32.to_hex(), "#00000001")
  assert_eq(raw64.to_hex(), "#00000000000000FF")
  assert_eq(raw128.to_hex(), "#000000000000000000000000000000FF")
}

///|
test "decimal interchange encodes official clamped finite values" {
  let value32 = @decimal.Decimal::from_string("1.23E+96", precision=64).unwrap()
  let value64 = @decimal.Decimal::from_string("1.23E+384", precision=64).unwrap()
  let value128 = @decimal.Decimal::from_string("1.23E+6144", precision=64).unwrap()
  let (encoded32, flags32) = value32.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  let (encoded64, flags64) = value64.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (encoded128, flags128) = value128.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  assert_eq(encoded32, "#47F4C000")
  assert_eq(encoded64, "#47FD300000000000")
  assert_eq(encoded128, "#47FFD300000000000000000000000000")
  assert_true(flags32.clamped)
  assert_true(flags64.clamped)
  assert_true(flags128.clamped)
}

///|
test "decimal interchange from_decimal matches encode result and flags" {
  let value32 = @decimal.Decimal::from_string("1.23E+96", precision=64).unwrap()
  let value = @decimal.Decimal::from_string("1.23E+384", precision=64).unwrap()
  let value128 = @decimal.Decimal::from_string("1.23E+6144", precision=64).unwrap()

  let (encoded32, flags32) = value32.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  let (interchange32, wrapped32_flags) = @decimal.DecimalInterchange::from_decimal(
    value32,
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  assert_eq(interchange32.to_hex(), encoded32)
  assert_true(
    interchange32.format() == @decimal.DecimalInterchangeFormat::Decimal32,
  )
  assert_true(flags32 == wrapped32_flags)
  assert_true(wrapped32_flags.clamped)

  let (encoded, flags) = value.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (interchange, wrapped_flags) = @decimal.DecimalInterchange::from_decimal(
    value,
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  assert_eq(interchange.to_hex(), encoded)
  assert_true(
    interchange.format() == @decimal.DecimalInterchangeFormat::Decimal64,
  )
  assert_true(flags == wrapped_flags)
  assert_true(wrapped_flags.clamped)

  let (encoded128, flags128) = value128.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  let (interchange128, wrapped128_flags) = @decimal.DecimalInterchange::from_decimal(
    value128,
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  assert_eq(interchange128.to_hex(), encoded128)
  assert_true(
    interchange128.format() == @decimal.DecimalInterchangeFormat::Decimal128,
  )
  assert_true(flags128 == wrapped128_flags)
  assert_true(wrapped128_flags.clamped)
}

///|
test "decimal interchange from_decimal matches special encode results and flags" {
  let inf = @decimal.Decimal::inf(@def.Sign::Negative, precision=32)
  let qnan = @decimal.Decimal::quiet_nan(
    payload=12345N,
    negative=true,
    precision=32,
  )
  let snan = @decimal.Decimal::signaling_nan(
    payload=54321N,
    negative=true,
    precision=32,
  )

  let (inf_bits, inf_flags) = inf.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (inf_interchange, inf_wrapped_flags) = @decimal.DecimalInterchange::from_decimal(
    inf,
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  assert_eq(inf_interchange.to_hex(), inf_bits)
  assert_true(
    inf_interchange.format() == @decimal.DecimalInterchangeFormat::Decimal64,
  )
  assert_true(inf_wrapped_flags == inf_flags)
  assert_false(inf_wrapped_flags.has_error())

  let (qnan_bits, qnan_flags) = qnan.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (qnan_interchange, qnan_wrapped_flags) = @decimal.DecimalInterchange::from_decimal(
    qnan,
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  assert_eq(qnan_interchange.to_hex(), qnan_bits)
  assert_true(
    qnan_interchange.format() == @decimal.DecimalInterchangeFormat::Decimal64,
  )
  assert_true(qnan_wrapped_flags == qnan_flags)
  assert_false(qnan_wrapped_flags.has_error())

  let (snan_bits, snan_flags) = snan.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (snan_interchange, snan_wrapped_flags) = @decimal.DecimalInterchange::from_decimal(
    snan,
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  assert_eq(snan_interchange.to_hex(), snan_bits)
  assert_true(
    snan_interchange.format() == @decimal.DecimalInterchangeFormat::Decimal64,
  )
  assert_true(snan_wrapped_flags == snan_flags)
  assert_false(snan_wrapped_flags.has_error())

  let (inf32, inf32_flags) = @decimal.DecimalInterchange::from_decimal(
    inf,
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  let (inf32_expected_bits, inf32_expected_flags) = inf.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  assert_eq(inf32.to_hex(), inf32_expected_bits)
  assert_true(inf32.format() == @decimal.DecimalInterchangeFormat::Decimal32)
  assert_true(inf32_flags == inf32_expected_flags)

  let (qnan128, qnan128_flags) = @decimal.DecimalInterchange::from_decimal(
    qnan,
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  let (qnan128_expected_bits, qnan128_expected_flags) = qnan.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  assert_eq(qnan128.to_hex(), qnan128_expected_bits)
  assert_true(qnan128.format() == @decimal.DecimalInterchangeFormat::Decimal128)
  assert_true(qnan128_flags == qnan128_expected_flags)

  let (snan32, snan32_flags) = @decimal.DecimalInterchange::from_decimal(
    snan,
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  let (snan32_expected_bits, snan32_expected_flags) = snan.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  assert_eq(snan32.to_hex(), snan32_expected_bits)
  assert_true(snan32.format() == @decimal.DecimalInterchangeFormat::Decimal32)
  assert_true(snan32_flags == snan32_expected_flags)
}

///|
test "decimal interchange canonicalizes specials and preserves payloads" {
  let inf = @decimal.Decimal::from_interchange_hex(
    "#7800000000000000",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  assert_true(inf.is_infinite())
  assert_false(inf.is_negative())
  let snan = @decimal.Decimal::from_interchange_hex(
    "#7FFFFFFFFFFFFFFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  assert_true(snan.is_signaling_nan())
  assert_eq(snan.nan_payload(), 999999999999999N)
  let (canonical, flags) = snan.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  assert_eq(canonical, "#7E00FF3FCFF3FCFF")
  assert_false(flags.invalid_operation)
  let quiet = @decimal.Decimal::quiet_nan(
    payload=12345N,
    negative=true,
    precision=16,
  )
  let (quiet_bits, quiet_flags) = quiet.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  assert_eq(quiet_bits, "#FC000000000049C5")
  assert_false(quiet_flags.invalid_operation)

  let raw_snan128 = @decimal.DecimalInterchange::from_hex(
    "#FE020000000000000000000000003039",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let raw_qnan32 = @decimal.DecimalInterchange::from_hex(
    "#7C00016E",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  assert_eq(raw_qnan32.canonical().to_hex(), "#7C00006E")
  assert_eq(
    raw_snan128.canonical().to_hex(),
    "#FE000000000000000000000000003039",
  )
}

///|
test "decimal interchange decodes multi-format special encodings directly" {
  let qnan32 = @decimal.Decimal::from_interchange_hex(
    "#7C0049C5",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let neg_qnan32 = @decimal.Decimal::from_interchange_hex(
    "#FC0049C5",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let snan128 = @decimal.Decimal::from_interchange_hex(
    "#7E0000000000000000000000000049C5",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let neg_snan128 = @decimal.Decimal::from_interchange_hex(
    "#FE0000000000000000000000000049C5",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  assert_true(qnan32.is_qnan())
  assert_false(qnan32.is_negative())
  assert_eq(qnan32.nan_payload(), 12345N)
  assert_true(neg_qnan32.is_qnan())
  assert_true(neg_qnan32.is_negative())
  assert_eq(neg_qnan32.nan_payload(), 12345N)
  assert_true(snan128.is_snan())
  assert_false(snan128.is_negative())
  assert_eq(snan128.nan_payload(), 12345N)
  assert_true(neg_snan128.is_snan())
  assert_true(neg_snan128.is_negative())
  assert_eq(neg_snan128.nan_payload(), 12345N)
}

///|
test "decimal interchange special roundtrips preserve class sign and payload across formats" {
  let neg_inf = @decimal.Decimal::inf(@def.Sign::Negative, precision=32)
  let neg_qnan = @decimal.Decimal::quiet_nan(
    payload=12345N,
    negative=true,
    precision=32,
  )
  let neg_snan = @decimal.Decimal::signaling_nan(
    payload=12345N,
    negative=true,
    precision=32,
  )

  let (inf32_bits, _) = neg_inf.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  let (inf64_bits, _) = neg_inf.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (inf128_bits, _) = neg_inf.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  let inf32 = @decimal.Decimal::from_interchange_hex(
    inf32_bits,
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let inf64 = @decimal.Decimal::from_interchange_hex(
    inf64_bits,
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let inf128 = @decimal.Decimal::from_interchange_hex(
    inf128_bits,
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  assert_true(inf32.is_infinite())
  assert_true(inf64.is_infinite())
  assert_true(inf128.is_infinite())
  assert_true(inf32.is_negative())
  assert_true(inf64.is_negative())
  assert_true(inf128.is_negative())

  let (qnan32_bits, _) = neg_qnan.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  let (qnan64_bits, _) = neg_qnan.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (qnan128_bits, _) = neg_qnan.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  let qnan32 = @decimal.Decimal::from_interchange_hex(
    qnan32_bits,
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let qnan64 = @decimal.Decimal::from_interchange_hex(
    qnan64_bits,
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let qnan128 = @decimal.Decimal::from_interchange_hex(
    qnan128_bits,
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  assert_true(qnan32.is_qnan())
  assert_true(qnan64.is_qnan())
  assert_true(qnan128.is_qnan())
  assert_true(qnan32.is_negative())
  assert_true(qnan64.is_negative())
  assert_true(qnan128.is_negative())
  assert_eq(qnan32.nan_payload(), 12345N)
  assert_eq(qnan64.nan_payload(), 12345N)
  assert_eq(qnan128.nan_payload(), 12345N)

  let (snan32_bits, _) = neg_snan.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  let (snan64_bits, _) = neg_snan.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (snan128_bits, _) = neg_snan.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  let snan32 = @decimal.Decimal::from_interchange_hex(
    snan32_bits,
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let snan64 = @decimal.Decimal::from_interchange_hex(
    snan64_bits,
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let snan128 = @decimal.Decimal::from_interchange_hex(
    snan128_bits,
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  assert_true(snan32.is_snan())
  assert_true(snan64.is_snan())
  assert_true(snan128.is_snan())
  assert_true(snan32.is_negative())
  assert_true(snan64.is_negative())
  assert_true(snan128.is_negative())
  assert_eq(snan32.nan_payload(), 12345N)
  assert_eq(snan64.nan_payload(), 12345N)
  assert_eq(snan128.nan_payload(), 12345N)
}

///|
test "decimal canonical multiply quiets interchange nan operands with canonical payloads" {
  let dd_qnan = @decimal.Decimal::from_interchange_hex(
    "#7C03FF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let dd_snan = @decimal.Decimal::from_interchange_hex(
    "#7E00FFFFCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let dq_qnan = @decimal.Decimal::from_interchange_hex(
    "#7C03FF3FCFF3FCFF0000000000000000",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let dq_snan = @decimal.Decimal::from_interchange_hex(
    "#7E00FFFFCFF3FCFF0000000000000000",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let one = @decimal.Decimal::one(precision=34)
  let (dd_quiet_product, dd_quiet_flags) = dd_qnan.mul_ctx(
    one,
    @decimal.DecimalContext::new(precision=34),
  )
  let (dd_signal_product, dd_signal_flags) = one.mul_ctx(
    dd_snan,
    @decimal.DecimalContext::new(precision=34),
  )
  let (dq_quiet_product, dq_quiet_flags) = dq_qnan.mul_ctx(
    one,
    @decimal.DecimalContext::new(precision=34),
  )
  let (dq_signal_product, dq_signal_flags) = one.mul_ctx(
    dq_snan,
    @decimal.DecimalContext::new(precision=34),
  )
  let (dd_quiet_bits, _dd_quiet_encode_flags) = dd_quiet_product.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (dd_signal_bits, _dd_signal_encode_flags) = dd_signal_product.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (dq_quiet_bits, _dq_quiet_encode_flags) = dq_quiet_product.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  let (dq_signal_bits, _dq_signal_encode_flags) = dq_signal_product.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  assert_eq(dd_quiet_bits, "#7C00FF3FCFF3FCFF")
  assert_false(dd_quiet_flags.invalid_operation)
  assert_eq(dd_signal_bits, "#7C00FF3FCFF3FCFF")
  assert_true(dd_signal_flags.invalid_operation)
  assert_eq(dq_quiet_bits, "#7C003F3FCFF3FCFF0000000000000000")
  assert_false(dq_quiet_flags.invalid_operation)
  assert_eq(dq_signal_bits, "#7C000FFFCFF3FCFF0000000000000000")
  assert_true(dq_signal_flags.invalid_operation)
}

///|
test "decimal interchange wrapper preserves raw bits and canonicalizes on demand" {
  let raw = @decimal.DecimalInterchange::from_hex(
    "#77FFFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  assert_eq(raw.to_hex(), "#77FFFF3FCFF3FCFF")
  let expected = @decimal.Decimal::from_string(
    "9.999999999999999E+384",
    precision=64,
  ).unwrap()
  assert_eq(raw.to_decimal().compare_total(expected).to_string(), "0")
  assert_eq(raw.canonical().to_hex(), "#77FCFF3FCFF3FCFF")
  assert_true(
    raw.canonical().format() == @decimal.DecimalInterchangeFormat::Decimal64,
  )
  assert_eq(raw.canonical().canonical().to_hex(), "#77FCFF3FCFF3FCFF")

  let raw128 = @decimal.DecimalInterchange::from_hex(
    "#77FFFFF3FCFF3FCFF3FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let expected128 = @decimal.Decimal::from_string(
    "9.999999999999999999999999999999999E+6144",
    precision=64,
  ).unwrap()
  assert_eq(raw128.to_decimal().compare_total(expected128).to_string(), "0")
  assert_eq(raw128.canonical().to_hex(), "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_true(
    raw128.canonical().format() == @decimal.DecimalInterchangeFormat::Decimal128,
  )
  assert_eq(
    raw128.canonical().canonical().to_hex(),
    "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF",
  )
}

///|
test "decimal32 non-canonical finite witness reencodes through current canonical path" {
  let raw32 = @decimal.DecimalInterchange::from_hex(
    "#77FFFF3F",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let decoded32 = raw32.to_decimal()
  let (reencoded32, reencoded_flags32) = decoded32.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal32,
  )

  assert_eq(raw32.to_hex(), "#77FFFF3F")
  assert_eq(raw32.canonical().to_hex(), "#77F3FF3F")
  assert_eq(reencoded32, "#77F3FF3F")
  assert_eq(raw32.canonical().to_hex(), reencoded32)
  assert_false(reencoded_flags32.invalid_operation)
  assert_false(reencoded_flags32.overflow)
  assert_false(reencoded_flags32.underflow)
  assert_false(reencoded_flags32.inexact)
  assert_false(reencoded_flags32.rounded)
  assert_true(raw32.canonical().to_hex() != "#77F3FCFF")
}

///|
test "decimal32 raw witness #77FFFF3F decodes to its own canonical finite value" {
  let raw32 = @decimal.DecimalInterchange::from_hex(
    "#77FFFF3F",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let neg_raw32 = @decimal.DecimalInterchange::from_hex(
    "#F7FFFF3F",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let expected32 = @decimal.Decimal::from_string("9.999879E+96", precision=64).unwrap()
  let expected32_negative = @decimal.Decimal::from_string(
    "-9.999879E+96",
    precision=64,
  ).unwrap()
  let (expected32_bits, expected32_flags) = expected32.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  let (expected32_negative_bits, expected32_negative_flags) = expected32_negative.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal32,
  )

  assert_eq(raw32.to_decimal().compare_total(expected32).to_string(), "0")
  assert_eq(
    neg_raw32.to_decimal().compare_total(expected32_negative).to_string(),
    "0",
  )
  assert_eq(raw32.canonical().to_hex(), "#77F3FF3F")
  assert_eq(neg_raw32.canonical().to_hex(), "#F7F3FF3F")
  assert_eq(expected32_bits, "#77F3FF3F")
  assert_eq(expected32_negative_bits, "#F7F3FF3F")
  assert_false(expected32_flags.invalid_operation)
  assert_false(expected32_flags.inexact)
  assert_false(expected32_negative_flags.invalid_operation)
  assert_false(expected32_negative_flags.inexact)
}

///|
test "decimal32 extra-declet non-canonical witnesses collapse to official canonical finite representative" {
  let low_extra = @decimal.DecimalInterchange::from_hex(
    "#77F3FFFF",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let high_extra = @decimal.DecimalInterchange::from_hex(
    "#77FFFCFF",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let both_extra = @decimal.DecimalInterchange::from_hex(
    "#77FFFFFF",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let expected32 = @decimal.Decimal::from_string("9.999999E+96", precision=64).unwrap()

  assert_eq(low_extra.to_decimal().compare_total(expected32).to_string(), "0")
  assert_eq(high_extra.to_decimal().compare_total(expected32).to_string(), "0")
  assert_eq(both_extra.to_decimal().compare_total(expected32).to_string(), "0")
  assert_eq(low_extra.canonical().to_hex(), "#77F3FCFF")
  assert_eq(high_extra.canonical().to_hex(), "#77F3FCFF")
  assert_eq(both_extra.canonical().to_hex(), "#77F3FCFF")
}

///|
test "decimal interchange wrapper decodes special values through to_decimal" {
  let raw_qnan = @decimal.DecimalInterchange::from_hex(
    "#FC03FF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let raw_snan = @decimal.DecimalInterchange::from_hex(
    "#FE00FFFFCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let qnan = raw_qnan.to_decimal()
  let snan = raw_snan.to_decimal()
  assert_true(qnan.is_qnan())
  assert_true(qnan.is_negative())
  assert_eq(qnan.nan_payload(), 999999999999999N)
  assert_true(snan.is_snan())
  assert_true(snan.is_negative())
  assert_eq(snan.nan_payload(), 999999999999999N)

  let raw_qnan32 = @decimal.DecimalInterchange::from_hex(
    "#FC0049C5",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let raw_snan32 = @decimal.DecimalInterchange::from_hex(
    "#FE0049C5",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let raw_qnan128 = @decimal.DecimalInterchange::from_hex(
    "#FC0000000000000000000000000049C5",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let raw_snan128 = @decimal.DecimalInterchange::from_hex(
    "#FE0000000000000000000000000049C5",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let qnan32 = raw_qnan32.to_decimal()
  let snan32 = raw_snan32.to_decimal()
  let qnan128 = raw_qnan128.to_decimal()
  let snan128 = raw_snan128.to_decimal()
  assert_true(qnan32.is_qnan())
  assert_true(qnan32.is_negative())
  assert_eq(qnan32.nan_payload(), 12345N)
  assert_true(snan32.is_snan())
  assert_true(snan32.is_negative())
  assert_eq(snan32.nan_payload(), 12345N)
  assert_true(qnan128.is_qnan())
  assert_true(qnan128.is_negative())
  assert_eq(qnan128.nan_payload(), 12345N)
  assert_true(snan128.is_snan())
  assert_true(snan128.is_negative())
  assert_eq(snan128.nan_payload(), 12345N)
}

///|
test "decimal interchange wrapper sign-copy operations preserve representation bits" {
  let finite = @decimal.DecimalInterchange::from_hex(
    "#77FFFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let neg_finite = @decimal.DecimalInterchange::from_hex(
    "#F7FFFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let qnan = @decimal.DecimalInterchange::from_hex(
    "#FC03FF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  assert_eq(finite.copy_abs().to_hex(), "#77FFFF3FCFF3FCFF")
  assert_eq(neg_finite.copy_abs().to_hex(), "#77FFFF3FCFF3FCFF")
  assert_eq(finite.copy_negate().to_hex(), "#F7FFFF3FCFF3FCFF")
  assert_eq(qnan.copy_negate().to_hex(), "#7C03FF3FCFF3FCFF")
  assert_eq(finite.copy_sign(qnan).to_hex(), "#F7FFFF3FCFF3FCFF")
  assert_false(finite.is_canonical())
  assert_true(finite.canonical().is_canonical())
}

///|
test "decimal interchange sign transforms preserve special payload bits" {
  let neg_qnan = @decimal.DecimalInterchange::from_hex(
    "#FC03FF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let pos_inf = @decimal.DecimalInterchange::from_hex(
    "#7800000000000000",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  assert_eq(neg_qnan.copy_abs().to_hex(), "#7C03FF3FCFF3FCFF")
  assert_eq(pos_inf.copy_negate().to_hex(), "#F800000000000000")
  assert_eq(neg_qnan.copy_sign(pos_inf).to_hex(), "#7C03FF3FCFF3FCFF")

  let neg_qnan32 = @decimal.DecimalInterchange::from_hex(
    "#FC0049C5",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let qnan32_abs = neg_qnan32.copy_abs().to_decimal()
  assert_true(qnan32_abs.is_qnan())
  assert_false(qnan32_abs.is_negative())
  assert_eq(qnan32_abs.nan_payload(), 12345N)

  let neg_snan128 = @decimal.DecimalInterchange::from_hex(
    "#FE0000000000000000000000000049C5",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let pos_inf128 = @decimal.DecimalInterchange::from_hex(
    "#78000000000000000000000000000000",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let snan128_signed = neg_snan128.copy_sign(pos_inf128).to_decimal()
  assert_true(snan128_signed.is_snan())
  assert_false(snan128_signed.is_negative())
  assert_eq(snan128_signed.nan_payload(), 12345N)
}

///|
test "decimal interchange sign transforms preserve bits across decimal32 and decimal128" {
  let finite32 = @decimal.DecimalInterchange::from_hex(
    "#77F3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let qnan32 = @decimal.DecimalInterchange::from_hex(
    "#FC0049C5",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let pos_inf32 = @decimal.DecimalInterchange::from_hex(
    "#78000000",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let neg_inf32 = @decimal.DecimalInterchange::from_hex(
    "#F8000000",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  assert_eq(qnan32.copy_abs().to_hex(), "#7C0049C5")
  assert_eq(pos_inf32.copy_negate().to_hex(), "#F8000000")
  assert_eq(neg_inf32.copy_abs().to_hex(), "#78000000")
  assert_eq(qnan32.copy_sign(pos_inf32).to_hex(), "#7C0049C5")
  let finite32_negative = finite32.copy_negate().to_decimal()
  let qnan32_positive = qnan32.copy_abs().to_decimal()
  let inf32_negative = pos_inf32.copy_negate().to_decimal()
  let expected32_negative = @decimal.Decimal::from_string(
    "-9.999999E+96",
    precision=64,
  ).unwrap()
  assert_eq(finite32.copy_negate().to_hex(), "#F7F3FCFF")
  assert_eq(
    finite32_negative.compare_total(expected32_negative).to_string(),
    "0",
  )
  assert_true(qnan32_positive.is_qnan())
  assert_false(qnan32_positive.is_negative())
  assert_eq(qnan32_positive.nan_payload(), 12345N)
  assert_true(inf32_negative.is_infinite())
  assert_true(inf32_negative.is_negative())

  let finite128 = @decimal.DecimalInterchange::from_hex(
    "#77FFFFF3FCFF3FCFF3FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let qnan128 = @decimal.DecimalInterchange::from_hex(
    "#FC0000000000000000000000000049C5",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let pos_inf128 = @decimal.DecimalInterchange::from_hex(
    "#78000000000000000000000000000000",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let neg_inf128 = @decimal.DecimalInterchange::from_hex(
    "#F8000000000000000000000000000000",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  assert_eq(qnan128.copy_abs().to_hex(), "#7C0000000000000000000000000049C5")
  assert_eq(
    pos_inf128.copy_negate().to_hex(),
    "#F8000000000000000000000000000000",
  )
  assert_eq(neg_inf128.copy_abs().to_hex(), "#78000000000000000000000000000000")
  assert_eq(
    qnan128.copy_sign(pos_inf128).to_hex(),
    "#7C0000000000000000000000000049C5",
  )
  let finite128_negative = finite128.copy_negate().to_decimal()
  let qnan128_positive = qnan128.copy_abs().to_decimal()
  let inf128_negative = pos_inf128.copy_negate().to_decimal()
  let expected128_negative = @decimal.Decimal::from_string(
    "-9.999999999999999999999999999999999E+6144",
    precision=64,
  ).unwrap()
  assert_eq(
    finite128_negative.compare_total(expected128_negative).to_string(),
    "0",
  )
  assert_true(qnan128_positive.is_qnan())
  assert_false(qnan128_positive.is_negative())
  assert_eq(qnan128_positive.nan_payload(), 12345N)
  assert_true(inf128_negative.is_infinite())
  assert_true(inf128_negative.is_negative())
}

///|
test "decimal interchange wrapper canonical predicate covers special values" {
  let raw_qnan = @decimal.DecimalInterchange::from_hex(
    "#7C03FF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let canonical_qnan = @decimal.DecimalInterchange::from_hex(
    "#7C00FF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  assert_false(raw_qnan.is_canonical())
  assert_true(canonical_qnan.is_canonical())
  assert_eq(raw_qnan.canonical().to_hex(), "#7C00FF3FCFF3FCFF")

  let raw_qnan32 = @decimal.DecimalInterchange::from_hex(
    "#7C00016E",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let canonical_qnan32 = @decimal.DecimalInterchange::from_hex(
    "#7C00006E",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  assert_false(raw_qnan32.is_canonical())
  assert_true(canonical_qnan32.is_canonical())
  assert_eq(raw_qnan32.canonical().to_hex(), "#7C00006E")

  let raw_snan128 = @decimal.DecimalInterchange::from_hex(
    "#FE020000000000000000000000003039",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let canonical_snan128 = @decimal.DecimalInterchange::from_hex(
    "#FE000000000000000000000000003039",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  assert_false(raw_snan128.is_canonical())
  assert_true(canonical_snan128.is_canonical())
  assert_eq(
    raw_snan128.canonical().to_hex(),
    "#FE000000000000000000000000003039",
  )
}

///|
test "scalar decimal canonical predicate ignores non-canonical interchange encodings" {
  let raw = @decimal.DecimalInterchange::from_hex(
    "#77FFFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let scalar = raw.to_decimal()
  let expected = @decimal.Decimal::from_string(
    "9.999999999999999E+384",
    precision=64,
  ).unwrap()
  assert_false(raw.is_canonical())
  assert_true(scalar.is_canonical())
  assert_eq(scalar.compare_total(expected).to_string(), "0")
}

///|
test "decimal interchange wrapper copy preserves raw bits and format" {
  let raw = @decimal.DecimalInterchange::from_hex(
    "#7E00FFFFCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let copied = raw.copy()
  assert_eq(copied.to_hex(), "#7E00FFFFCFF3FCFF")
  assert_true(copied.format() == @decimal.DecimalInterchangeFormat::Decimal64)
  assert_true(copied.to_decimal().is_signaling_nan())

  let raw32 = @decimal.DecimalInterchange::from_hex(
    "#7C00016E",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let copied32 = raw32.copy()
  assert_eq(copied32.to_hex(), "#7C00016E")
  assert_true(copied32.format() == @decimal.DecimalInterchangeFormat::Decimal32)
  assert_true(copied32.to_decimal().is_qnan())

  let finite32 = @decimal.DecimalInterchange::from_hex(
    "#77FFFF3F",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let finite32_copy = finite32.copy()
  assert_eq(finite32_copy.to_hex(), "#77FFFF3F")
  assert_true(
    finite32_copy.format() == @decimal.DecimalInterchangeFormat::Decimal32,
  )

  let raw128 = @decimal.DecimalInterchange::from_hex(
    "#7E000000000000000000000000003039",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let copied128 = raw128.copy()
  assert_eq(copied128.to_hex(), "#7E000000000000000000000000003039")
  assert_true(
    copied128.format() == @decimal.DecimalInterchangeFormat::Decimal128,
  )
  assert_true(copied128.to_decimal().is_snan())

  let finite128 = @decimal.DecimalInterchange::from_hex(
    "#77FFFFF3FCFF3FCFF3FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let finite128_copy = finite128.copy()
  assert_eq(finite128_copy.to_hex(), "#77FFFFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_true(
    finite128_copy.format() == @decimal.DecimalInterchangeFormat::Decimal128,
  )
}

///|
test "decimal participates in luna generic semiring algorithms" {
  let x = @decimal.Decimal::from_string("2.5", precision=20).unwrap()
  let y : @decimal.Decimal = quadratic_semiring(x)
  let z : @decimal.Decimal = add_zero_generic(y)
  assert_eq(y.to_string(), "9.75")
  assert_eq(z.to_string(), "9.75")
}

///|
test "decimal context flags distinguish exact in-range and rounded addition" {
  let ctx = @decimal.DecimalContext::new(precision=3)
  let exact_source = @decimal.Decimal::from_string("123", precision=10).unwrap()
  let (exact, exact_flags) = exact_source.add_ctx(
    @decimal.Decimal::zero(precision=10),
    ctx,
  )
  assert_eq(exact.to_string(), "123")
  assert_false(exact_flags.rounded)
  assert_false(exact_flags.inexact)
  let rounded_source = @decimal.Decimal::from_string("1234", precision=10).unwrap()
  let (rounded, rounded_flags) = rounded_source.add_ctx(
    @decimal.Decimal::zero(precision=10),
    ctx,
  )
  assert_eq(rounded.to_string(), "1.23E+3")
  assert_true(rounded_flags.rounded)
  assert_true(rounded_flags.inexact)
}

///|
test "decimal context reports rounded for discarded trailing zeros" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
  )
  let lhs = @decimal.Decimal::from_string("10000e+9", precision=64).unwrap()
  let rhs = @decimal.Decimal::from_string("700000", precision=64).unwrap()
  let (sum, sum_flags) = lhs.add_ctx(rhs, ctx)
  assert_eq(
    sum
    .compare_total(
      @decimal.Decimal::from_string("1.00000007E+13", precision=64).unwrap(),
    )
    .to_string(),
    "0",
  )
  assert_true(sum_flags.rounded)
  assert_false(sum_flags.inexact)
  let (applied, apply_flags) = @decimal.Decimal::from_string(
      "10000000700000",
      precision=64,
    )
    .unwrap()
    .apply_ctx(ctx)
  assert_eq(
    applied
    .compare_total(
      @decimal.Decimal::from_string("1.00000007E+13", precision=64).unwrap(),
    )
    .to_string(),
    "0",
  )
  assert_true(apply_flags.rounded)
  assert_false(apply_flags.inexact)
}

///|
test "decimal add official0 subnormal underflow rows set full gda flags" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999999999,
    e_max=999999999,
    extended=false,
  )
  let (add332, add332_flags) = @decimal.Decimal::from_string(
      "-1.1E-999999999",
      precision=64,
    )
    .unwrap()
    .add_ctx(
      @decimal.Decimal::from_string("1E-999999999", precision=64).unwrap(),
      ctx,
    )
  let (add333, add333_flags) = @decimal.Decimal::from_string(
      "1E-999999999",
      precision=64,
    )
    .unwrap()
    .add_ctx(
      @decimal.Decimal::from_string("-1.1E-999999999", precision=64).unwrap(),
      ctx,
    )
  let (add336, add336_flags) = @decimal.Decimal::from_string(
      "+1.1E-999999999",
      precision=64,
    )
    .unwrap()
    .add_ctx(
      @decimal.Decimal::from_string("-1E-999999999", precision=64).unwrap(),
      ctx,
    )
  let (add337, add337_flags) = @decimal.Decimal::from_string(
      "-1E-999999999",
      precision=64,
    )
    .unwrap()
    .add_ctx(
      @decimal.Decimal::from_string("+1.1E-999999999", precision=64).unwrap(),
      ctx,
    )
  assert_true(add332.is_finite(), msg="add332 finite")
  assert_true(add333.is_finite(), msg="add333 finite")
  assert_true(add336.is_finite(), msg="add336 finite")
  assert_true(add337.is_finite(), msg="add337 finite")
  assert_true(add332_flags.underflow, msg="add332 underflow")
  assert_true(add332_flags.subnormal, msg="add332 subnormal")
  assert_true(add332_flags.inexact, msg="add332 inexact")
  assert_true(add332_flags.rounded, msg="add332 rounded")
  assert_true(add333_flags.underflow, msg="add333 underflow")
  assert_true(add333_flags.subnormal, msg="add333 subnormal")
  assert_true(add333_flags.inexact, msg="add333 inexact")
  assert_true(add333_flags.rounded, msg="add333 rounded")
  assert_true(add336_flags.underflow, msg="add336 underflow")
  assert_true(add336_flags.subnormal, msg="add336 subnormal")
  assert_true(add336_flags.inexact, msg="add336 inexact")
  assert_true(add336_flags.rounded, msg="add336 rounded")
  assert_true(add337_flags.underflow, msg="add337 underflow")
  assert_true(add337_flags.subnormal, msg="add337 subnormal")
  assert_true(add337_flags.inexact, msg="add337 inexact")
  assert_true(add337_flags.rounded, msg="add337 rounded")
}

///|
test "decimal subtract official0 subnormal underflow rows set full gda flags" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999999999,
    e_max=999999999,
    extended=false,
  )
  let (sub732, sub732_flags) = @decimal.Decimal::from_string(
      "-1.1E-999999999",
      precision=64,
    )
    .unwrap()
    .sub_ctx(
      @decimal.Decimal::from_string("-1E-999999999", precision=64).unwrap(),
      ctx,
    )
  let (sub733, sub733_flags) = @decimal.Decimal::from_string(
      "1E-999999999",
      precision=64,
    )
    .unwrap()
    .sub_ctx(
      @decimal.Decimal::from_string("1.1E-999999999", precision=64).unwrap(),
      ctx,
    )
  let (sub736, sub736_flags) = @decimal.Decimal::from_string(
      "1.1E-999999999",
      precision=64,
    )
    .unwrap()
    .sub_ctx(
      @decimal.Decimal::from_string("1E-999999999", precision=64).unwrap(),
      ctx,
    )
  let (sub737, sub737_flags) = @decimal.Decimal::from_string(
      "-1E-999999999",
      precision=64,
    )
    .unwrap()
    .sub_ctx(
      @decimal.Decimal::from_string("-1.1E-999999999", precision=64).unwrap(),
      ctx,
    )
  assert_true(sub732.is_finite(), msg="sub732 finite")
  assert_true(sub733.is_finite(), msg="sub733 finite")
  assert_true(sub736.is_finite(), msg="sub736 finite")
  assert_true(sub737.is_finite(), msg="sub737 finite")
  assert_true(sub732_flags.underflow, msg="sub732 underflow")
  assert_true(sub732_flags.subnormal, msg="sub732 subnormal")
  assert_true(sub732_flags.inexact, msg="sub732 inexact")
  assert_true(sub732_flags.rounded, msg="sub732 rounded")
  assert_true(sub733_flags.underflow, msg="sub733 underflow")
  assert_true(sub733_flags.subnormal, msg="sub733 subnormal")
  assert_true(sub733_flags.inexact, msg="sub733 inexact")
  assert_true(sub733_flags.rounded, msg="sub733 rounded")
  assert_true(sub736_flags.underflow, msg="sub736 underflow")
  assert_true(sub736_flags.subnormal, msg="sub736 subnormal")
  assert_true(sub736_flags.inexact, msg="sub736 inexact")
  assert_true(sub736_flags.rounded, msg="sub736 rounded")
  assert_true(sub737_flags.underflow, msg="sub737 underflow")
  assert_true(sub737_flags.subnormal, msg="sub737 subnormal")
  assert_true(sub737_flags.inexact, msg="sub737 inexact")
  assert_true(sub737_flags.rounded, msg="sub737 rounded")
}

///|
test "decimal unary plus/minus official subnormal rows keep finalize flags" {
  let ctx = @decimal.DecimalContext::new(
    precision=3,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
  ).gda()
  let (plux213, plux213_flags) = @decimal.Decimal::from_string(
      "0.100E-999",
      precision=64,
    )
    .unwrap()
    .plus_ctx(ctx)
  let (plux215, plux215_flags) = @decimal.Decimal::from_string(
      "0.999E-999",
      precision=64,
    )
    .unwrap()
    .plus_ctx(ctx)
  let (plux218, plux218_flags) = @decimal.Decimal::from_string(
      "0.001E-999",
      precision=64,
    )
    .unwrap()
    .plus_ctx(ctx)
  let (minx113, minx113_flags) = @decimal.Decimal::from_string(
      "0.100E-999",
      precision=64,
    )
    .unwrap()
    .minus_ctx(ctx)
  let (minx115, minx115_flags) = @decimal.Decimal::from_string(
      "0.999E-999",
      precision=64,
    )
    .unwrap()
    .minus_ctx(ctx)
  let (minx118, minx118_flags) = @decimal.Decimal::from_string(
      "0.001E-999",
      precision=64,
    )
    .unwrap()
    .minus_ctx(ctx)
  assert_eq(
    plux213.compare_total(
      @decimal.Decimal::from_string("1.0E-1000", precision=64).unwrap(),
    ),
    0,
  )
  assert_true(plux213_flags.subnormal, msg="plux213 subnormal")
  assert_true(plux213_flags.rounded, msg="plux213 rounded")
  assert_false(plux213_flags.inexact, msg="plux213 inexact")
  assert_eq(
    plux215.compare_total(
      @decimal.Decimal::from_string("1.00E-999", precision=64).unwrap(),
    ),
    0,
  )
  assert_true(plux215_flags.subnormal, msg="plux215 subnormal")
  assert_true(plux215_flags.underflow, msg="plux215 underflow")
  assert_true(plux215_flags.inexact, msg="plux215 inexact")
  assert_true(plux215_flags.rounded, msg="plux215 rounded")
  assert_eq(
    plux218.compare_total(
      @decimal.Decimal::from_string("0E-1001", precision=64).unwrap(),
    ),
    0,
  )
  assert_true(plux218_flags.subnormal, msg="plux218 subnormal")
  assert_true(plux218_flags.underflow, msg="plux218 underflow")
  assert_true(plux218_flags.inexact, msg="plux218 inexact")
  assert_true(plux218_flags.rounded, msg="plux218 rounded")
  assert_true(plux218_flags.clamped, msg="plux218 clamped")
  assert_eq(
    minx113.compare_total(
      @decimal.Decimal::from_string("-1.0E-1000", precision=64).unwrap(),
    ),
    0,
  )
  assert_true(minx113_flags.subnormal, msg="minx113 subnormal")
  assert_true(minx113_flags.rounded, msg="minx113 rounded")
  assert_false(minx113_flags.inexact, msg="minx113 inexact")
  assert_eq(
    minx115.compare_total(
      @decimal.Decimal::from_string("-1.00E-999", precision=64).unwrap(),
    ),
    0,
  )
  assert_true(minx115_flags.subnormal, msg="minx115 subnormal")
  assert_true(minx115_flags.underflow, msg="minx115 underflow")
  assert_true(minx115_flags.inexact, msg="minx115 inexact")
  assert_true(minx115_flags.rounded, msg="minx115 rounded")
  assert_eq(
    minx118.compare_total(
      @decimal.Decimal::from_string("-0E-1001", precision=64).unwrap(),
    ),
    0,
  )
  assert_true(minx118_flags.subnormal, msg="minx118 subnormal")
  assert_true(minx118_flags.underflow, msg="minx118 underflow")
  assert_true(minx118_flags.inexact, msg="minx118 inexact")
  assert_true(minx118_flags.rounded, msg="minx118 rounded")
  assert_true(minx118_flags.clamped, msg="minx118 clamped")
}

///|
test "decimal context addition absorbs far smaller operand as sticky" {
  let ctx = @decimal.DecimalContext::new(precision=9)
  let lhs = @decimal.Decimal::from_string("1", precision=64).unwrap()
  let rhs = @decimal.Decimal::from_string("-77e-999", precision=64).unwrap()
  let (sum, flags) = lhs.add_ctx(rhs, ctx)
  let expected = @decimal.Decimal::from_string("1.00000000", precision=64).unwrap()
  assert_eq(sum.compare_total(expected).to_string(), "0")
  assert_true(flags.rounded)
  assert_true(flags.inexact)
}

///|
test "decimal context addition rounds exact dominant operand with sub-ulp addend" {
  let lhs = @decimal.Decimal::from_string("1", precision=64).unwrap()
  let non_boundary = @decimal.Decimal::from_string("1.23456789", precision=64).unwrap()
  let below_half = @decimal.Decimal::from_string("4.99999E-9", precision=64).unwrap()
  let above_half = @decimal.Decimal::from_string("5.00001E-9", precision=64).unwrap()
  let half_up_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
  )
  let up_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::Up,
  )
  let down_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::Down,
  )
  let (half_up_below, half_up_below_flags) = lhs.add_ctx(
    below_half, half_up_ctx,
  )
  let (half_up_above, half_up_above_flags) = lhs.add_ctx(
    above_half, half_up_ctx,
  )
  let (up_positive, up_positive_flags) = lhs.add_ctx(below_half, up_ctx)
  let (down_negative, down_negative_flags) = non_boundary.add_ctx(
    above_half.neg(),
    down_ctx,
  )
  assert_eq(
    half_up_below.compare_total(
      @decimal.Decimal::from_string("1.00000000", precision=64).unwrap(),
    ),
    0,
  )
  assert_true(half_up_below_flags.rounded)
  assert_true(half_up_below_flags.inexact)
  assert_eq(
    half_up_above.compare_total(
      @decimal.Decimal::from_string("1.00000001", precision=64).unwrap(),
    ),
    0,
  )
  assert_true(half_up_above_flags.rounded)
  assert_true(half_up_above_flags.inexact)
  assert_eq(
    up_positive.compare_total(
      @decimal.Decimal::from_string("1.00000001", precision=64).unwrap(),
    ),
    0,
  )
  assert_true(up_positive_flags.rounded)
  assert_true(up_positive_flags.inexact)
  assert_eq(
    down_negative.compare_total(
      @decimal.Decimal::from_string("1.23456788", precision=64).unwrap(),
    ),
    0,
  )
  assert_true(down_negative_flags.rounded)
  assert_true(down_negative_flags.inexact)
}

///|
test "decimal context addition skips huge scaling for zero operand" {
  let ctx = @decimal.DecimalContext::new(precision=3, e_min=-999, e_max=999)
  let tiny = @decimal.Decimal::from_string("0.009E-999", precision=64).unwrap()
  let (sum, flags) = tiny.add_ctx(@decimal.Decimal::zero(precision=64), ctx)
  let expected = @decimal.Decimal::from_string("1E-1001", precision=64).unwrap()
  assert_eq(sum.compare_total(expected).to_string(), "0")
  assert_true(flags.underflow)
  assert_true(flags.subnormal)
  assert_true(flags.rounded)
  assert_true(flags.inexact)
}

///|
test "decimal context reports underflow when tiny exact result rounds normal" {
  let ctx = @decimal.DecimalContext::new(precision=16, e_min=-383, e_max=384)
  let lhs = @decimal.Decimal::from_string("1E-383", precision=64).unwrap()
  let rhs = @decimal.Decimal::from_string("1E-400", precision=64).unwrap()
  let (difference, flags) = lhs.sub_ctx(rhs, ctx)
  let expected = @decimal.Decimal::from_string(
    "1.000000000000000E-383",
    precision=64,
  ).unwrap()
  assert_eq(difference.compare_total(expected).to_string(), "0")
  assert_true(flags.subnormal)
  assert_true(flags.underflow)
  assert_true(flags.rounded)
  assert_true(flags.inexact)
}

///|
test "decimal make currently normalizes zero cohort exponent to plain zero" {
  let dd_tiny_zero = @decimal.Decimal::make(0N, -398, 64)
  let dq_tiny_zero = @decimal.Decimal::make(0N, -6176, 64)
  assert_eq(dd_tiny_zero.to_string(), "0")
  assert_eq(dq_tiny_zero.to_string(), "0")
  assert_eq(dd_tiny_zero.exponent10(), 0)
  assert_eq(dq_tiny_zero.exponent10(), 0)
}

///|
test "decimal canonical tiny-zero add rows preserve canonical finite result and rounded flag" {
  let dd_ctx = @decimal.DecimalContext::decimal64()
  let dq_ctx = @decimal.DecimalContext::decimal128()
  let dd_tiny_zero = @decimal.Decimal::make(0N, -398, 64)
  let dq_tiny_zero = @decimal.Decimal::make(0N, -6176, 64)
  let dd_lhs = @decimal.Decimal::from_interchange_hex(
    "#77FFFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let dd_rhs = @decimal.Decimal::from_interchange_hex(
    "#77FCFFFFCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let dq_lhs = @decimal.Decimal::from_interchange_hex(
    "#77FFCFF3FFFF3FCFF3FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let dq_rhs = @decimal.Decimal::from_interchange_hex(
    "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FFFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let dd_expected = @decimal.Decimal::from_interchange_hex(
    "#77FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let dq_expected = @decimal.Decimal::from_interchange_hex(
    "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let (dd_sum_lhs, dd_sum_lhs_flags) = dd_tiny_zero.add_ctx(dd_lhs, dd_ctx)
  let (dd_sum_rhs, dd_sum_rhs_flags) = dd_rhs.add_ctx(dd_tiny_zero, dd_ctx)
  let (dq_sum_lhs, dq_sum_lhs_flags) = dq_tiny_zero.add_ctx(dq_lhs, dq_ctx)
  let (dq_sum_rhs, dq_sum_rhs_flags) = dq_rhs.add_ctx(dq_tiny_zero, dq_ctx)
  let (dd_sum_lhs_bits, _dd_sum_lhs_encode_flags) = dd_sum_lhs.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (dd_sum_rhs_bits, _dd_sum_rhs_encode_flags) = dd_sum_rhs.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (dq_sum_lhs_bits, _dq_sum_lhs_encode_flags) = dq_sum_lhs.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  let (dq_sum_rhs_bits, _dq_sum_rhs_encode_flags) = dq_sum_rhs.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  assert_eq(dd_sum_lhs.compare_total(dd_expected).to_string(), "0")
  assert_eq(dd_sum_rhs.compare_total(dd_expected).to_string(), "0")
  assert_eq(dq_sum_lhs.compare_total(dq_expected).to_string(), "0")
  assert_eq(dq_sum_rhs.compare_total(dq_expected).to_string(), "0")
  assert_eq(dd_sum_lhs_bits, "#77FCFF3FCFF3FCFF")
  assert_eq(dd_sum_rhs_bits, "#77FCFF3FCFF3FCFF")
  assert_eq(dq_sum_lhs_bits, "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_eq(dq_sum_rhs_bits, "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_true(dd_sum_lhs_flags.rounded)
  assert_false(dd_sum_lhs_flags.inexact)
  assert_true(dd_sum_rhs_flags.rounded)
  assert_false(dd_sum_rhs_flags.inexact)
  assert_true(dq_sum_lhs_flags.rounded)
  assert_false(dq_sum_lhs_flags.inexact)
  assert_true(dq_sum_rhs_flags.rounded)
  assert_false(dq_sum_rhs_flags.inexact)
}

///|
test "decimal canonical tiny-zero subtract rows preserve canonical finite result and rounded flag" {
  let dd_ctx = @decimal.DecimalContext::decimal64()
  let dq_ctx = @decimal.DecimalContext::decimal128()
  let dd_tiny_zero = @decimal.Decimal::make(0N, -398, 64)
  let dq_tiny_zero = @decimal.Decimal::make(0N, -6176, 64)
  let dd_lhs = @decimal.Decimal::from_interchange_hex(
    "#77FFFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let dd_rhs = @decimal.Decimal::from_interchange_hex(
    "#77FCFFFFCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let dq_lhs = @decimal.Decimal::from_interchange_hex(
    "#77FFCFF3FFFF3FCFF3FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let dq_rhs = @decimal.Decimal::from_interchange_hex(
    "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FFFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let dd_expected_neg = @decimal.Decimal::from_interchange_hex(
    "#F7FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let dd_expected_pos = @decimal.Decimal::from_interchange_hex(
    "#77FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let dq_expected_neg = @decimal.Decimal::from_interchange_hex(
    "#F7FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let dq_expected_pos = @decimal.Decimal::from_interchange_hex(
    "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let (dd_diff_lhs, dd_diff_lhs_flags) = dd_tiny_zero.sub_ctx(dd_lhs, dd_ctx)
  let (dd_diff_rhs, dd_diff_rhs_flags) = dd_rhs.sub_ctx(dd_tiny_zero, dd_ctx)
  let (dq_diff_lhs, dq_diff_lhs_flags) = dq_tiny_zero.sub_ctx(dq_lhs, dq_ctx)
  let (dq_diff_rhs, dq_diff_rhs_flags) = dq_rhs.sub_ctx(dq_tiny_zero, dq_ctx)
  let (dd_diff_lhs_bits, _dd_diff_lhs_encode_flags) = dd_diff_lhs.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (dd_diff_rhs_bits, _dd_diff_rhs_encode_flags) = dd_diff_rhs.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (dq_diff_lhs_bits, _dq_diff_lhs_encode_flags) = dq_diff_lhs.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  let (dq_diff_rhs_bits, _dq_diff_rhs_encode_flags) = dq_diff_rhs.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  assert_eq(dd_diff_lhs.compare_total(dd_expected_neg).to_string(), "0")
  assert_eq(dd_diff_rhs.compare_total(dd_expected_pos).to_string(), "0")
  assert_eq(dq_diff_lhs.compare_total(dq_expected_neg).to_string(), "0")
  assert_eq(dq_diff_rhs.compare_total(dq_expected_pos).to_string(), "0")
  assert_eq(dd_diff_lhs_bits, "#F7FCFF3FCFF3FCFF")
  assert_eq(dd_diff_rhs_bits, "#77FCFF3FCFF3FCFF")
  assert_eq(dq_diff_lhs_bits, "#F7FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_eq(dq_diff_rhs_bits, "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_true(dd_diff_lhs_flags.rounded)
  assert_false(dd_diff_lhs_flags.inexact)
  assert_true(dd_diff_rhs_flags.rounded)
  assert_false(dd_diff_rhs_flags.inexact)
  assert_true(dq_diff_lhs_flags.rounded)
  assert_false(dq_diff_lhs_flags.inexact)
  assert_true(dq_diff_rhs_flags.rounded)
  assert_false(dq_diff_rhs_flags.inexact)
}

///|
test "decimal canonical tiny-nonzero add rows preserve canonical finite result and inexact rounded flags" {
  let dd_ctx = @decimal.DecimalContext::decimal64()
  let dq_ctx = @decimal.DecimalContext::decimal128()
  let dd_tiny = @decimal.Decimal::from_string("-1E-398", precision=64).unwrap()
  let dq_tiny = @decimal.Decimal::from_string("-1E-6176", precision=64).unwrap()
  let dd_lhs = @decimal.Decimal::from_interchange_hex(
    "#77FFFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let dq_lhs = @decimal.Decimal::from_interchange_hex(
    "#77FFCFF3FFFF3FCFF3FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let dd_expected = @decimal.Decimal::from_interchange_hex(
    "#77FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let dq_expected = @decimal.Decimal::from_interchange_hex(
    "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let (dd_sum_lhs, dd_sum_lhs_flags) = dd_tiny.add_ctx(dd_lhs, dd_ctx)
  let (dd_sum_rhs, dd_sum_rhs_flags) = dd_lhs.add_ctx(dd_tiny, dd_ctx)
  let (dq_sum_lhs, dq_sum_lhs_flags) = dq_tiny.add_ctx(dq_lhs, dq_ctx)
  let (dq_sum_rhs, dq_sum_rhs_flags) = dq_lhs.add_ctx(dq_tiny, dq_ctx)
  let (dd_sum_lhs_bits, _) = dd_sum_lhs.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (dd_sum_rhs_bits, _) = dd_sum_rhs.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (dq_sum_lhs_bits, _) = dq_sum_lhs.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  let (dq_sum_rhs_bits, _) = dq_sum_rhs.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  assert_eq(dd_sum_lhs.compare_total(dd_expected).to_string(), "0")
  assert_eq(dd_sum_rhs.compare_total(dd_expected).to_string(), "0")
  assert_eq(dq_sum_lhs.compare_total(dq_expected).to_string(), "0")
  assert_eq(dq_sum_rhs.compare_total(dq_expected).to_string(), "0")
  assert_eq(dd_sum_lhs_bits, "#77FCFF3FCFF3FCFF")
  assert_eq(dd_sum_rhs_bits, "#77FCFF3FCFF3FCFF")
  assert_eq(dq_sum_lhs_bits, "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_eq(dq_sum_rhs_bits, "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_true(dd_sum_lhs_flags.rounded)
  assert_true(dd_sum_lhs_flags.inexact)
  assert_true(dd_sum_rhs_flags.rounded)
  assert_true(dd_sum_rhs_flags.inexact)
  assert_true(dq_sum_lhs_flags.rounded)
  assert_true(dq_sum_lhs_flags.inexact)
  assert_true(dq_sum_rhs_flags.rounded)
  assert_true(dq_sum_rhs_flags.inexact)
}

///|
test "decimal canonical tiny-nonzero subtract rows preserve canonical finite result and inexact rounded flags" {
  let dd_ctx = @decimal.DecimalContext::decimal64()
  let dq_ctx = @decimal.DecimalContext::decimal128()
  let dd_tiny = @decimal.Decimal::from_string("-1E-398", precision=64).unwrap()
  let dq_tiny = @decimal.Decimal::from_string("-1E-6176", precision=64).unwrap()
  let dd_lhs = @decimal.Decimal::from_interchange_hex(
    "#77FFFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let dq_lhs = @decimal.Decimal::from_interchange_hex(
    "#77FFCFF3FFFF3FCFF3FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let dd_expected_neg = @decimal.Decimal::from_interchange_hex(
    "#F7FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let dd_expected_pos = @decimal.Decimal::from_interchange_hex(
    "#77FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let dq_expected_neg = @decimal.Decimal::from_interchange_hex(
    "#F7FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let dq_expected_pos = @decimal.Decimal::from_interchange_hex(
    "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let (dd_diff_lhs, dd_diff_lhs_flags) = dd_tiny.sub_ctx(dd_lhs, dd_ctx)
  let (dd_diff_rhs, dd_diff_rhs_flags) = dd_lhs.sub_ctx(dd_tiny, dd_ctx)
  let (dq_diff_lhs, dq_diff_lhs_flags) = dq_tiny.sub_ctx(dq_lhs, dq_ctx)
  let (dq_diff_rhs, dq_diff_rhs_flags) = dq_lhs.sub_ctx(dq_tiny, dq_ctx)
  let (dd_diff_lhs_bits, _) = dd_diff_lhs.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (dd_diff_rhs_bits, _) = dd_diff_rhs.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (dq_diff_lhs_bits, _) = dq_diff_lhs.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  let (dq_diff_rhs_bits, _) = dq_diff_rhs.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  assert_eq(dd_diff_lhs.compare_total(dd_expected_neg).to_string(), "0")
  assert_eq(dd_diff_rhs.compare_total(dd_expected_pos).to_string(), "0")
  assert_eq(dq_diff_lhs.compare_total(dq_expected_neg).to_string(), "0")
  assert_eq(dq_diff_rhs.compare_total(dq_expected_pos).to_string(), "0")
  assert_eq(dd_diff_lhs_bits, "#F7FCFF3FCFF3FCFF")
  assert_eq(dd_diff_rhs_bits, "#77FCFF3FCFF3FCFF")
  assert_eq(dq_diff_lhs_bits, "#F7FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_eq(dq_diff_rhs_bits, "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_true(dd_diff_lhs_flags.rounded)
  assert_true(dd_diff_lhs_flags.inexact)
  assert_true(dd_diff_rhs_flags.rounded)
  assert_true(dd_diff_rhs_flags.inexact)
  assert_true(dq_diff_lhs_flags.rounded)
  assert_true(dq_diff_lhs_flags.inexact)
  assert_true(dq_diff_rhs_flags.rounded)
  assert_true(dq_diff_rhs_flags.inexact)
}

///|
test "decimal context zero plus huge finite overflows without scaling zero" {
  let ctx = @decimal.DecimalContext::new(
    precision=3,
    e_min=-999999999,
    e_max=999999999,
  )
  let huge = @decimal.Decimal::from_string("-9.999E+999999999", precision=64).unwrap()
  let (sum, flags) = @decimal.Decimal::zero(precision=64).add_ctx(huge, ctx)
  assert_true(sum.classify() == @lf_arith.FpClass::Infinity)
  assert_true(sum.is_negative())
  assert_true(flags.overflow)
  assert_true(flags.rounded)
  assert_true(flags.inexact)
}

///|
test "decimal quotient and remainder avoid huge scaling when quotient is zero" {
  let ctx = @decimal.DecimalContext::new(
    precision=16,
    e_min=-999999999,
    e_max=999999999,
  )
  let tiny = @decimal.Decimal::from_string("0.100", precision=64).unwrap()
  let huge = @decimal.Decimal::from_string("9E+999999999", precision=64).unwrap()
  let (quotient, quotient_flags) = tiny.divide_integer(huge, ctx)
  let (remainder, remainder_flags) = tiny.remainder(huge, ctx)
  let (near_remainder, near_remainder_flags) = tiny.remainder_near(huge, ctx)
  assert_eq(quotient.compare_total(@decimal.Decimal::zero(precision=16)), 0)
  assert_false(quotient_flags.has_error())
  assert_eq(remainder.compare_total(tiny), 0)
  assert_false(remainder_flags.has_error())
  assert_eq(near_remainder.compare_total(tiny), 0)
  assert_false(near_remainder_flags.has_error())
  let negative_tiny = @decimal.Decimal::from_string("-0.100", precision=64).unwrap()
  let (negative_quotient, negative_quotient_flags) = negative_tiny.divide_integer(
    huge, ctx,
  )
  let (tiny_remainder, tiny_remainder_flags) = @decimal.Decimal::from_string(
      "9E-999999999",
      precision=64,
    )
    .unwrap()
    .remainder(
      @decimal.Decimal::from_string("9.100", precision=64).unwrap(),
      ctx,
    )
  let (tiny_near_remainder, tiny_near_remainder_flags) = @decimal.Decimal::from_string(
      "9E-999999999",
      precision=64,
    )
    .unwrap()
    .remainder_near(
      @decimal.Decimal::from_string("9.100", precision=64).unwrap(),
      ctx,
    )
  assert_eq(
    negative_quotient.compare_total(
      @decimal.Decimal::negative_zero(precision=16),
    ),
    0,
  )
  assert_false(negative_quotient_flags.has_error())
  assert_eq(
    tiny_remainder.compare_total(
      @decimal.Decimal::from_string("9E-999999999", precision=64).unwrap(),
    ),
    0,
  )
  assert_false(tiny_remainder_flags.has_error())
  assert_eq(
    tiny_near_remainder.compare_total(
      @decimal.Decimal::from_string("9E-999999999", precision=64).unwrap(),
    ),
    0,
  )
  assert_false(tiny_near_remainder_flags.has_error())
}

///|
test "decimal divide_integer by zero returns signed infinity or division undefined" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let positive = @decimal.Decimal::from_string("0.0001", precision=16).unwrap()
  let negative = @decimal.Decimal::from_string("-0.0001", precision=16).unwrap()
  let zero = @decimal.Decimal::zero(precision=16)
  let neg_zero = @decimal.Decimal::negative_zero(precision=16)
  let (positive_inf, positive_flags) = positive.divide_integer(zero, ctx)
  let (negative_inf, negative_flags) = negative.divide_integer(zero, ctx)
  let (flipped_inf, flipped_flags) = positive.divide_integer(neg_zero, ctx)
  let (undefined_result, undefined_flags) = zero.divide_integer(zero, ctx)
  assert_true(positive_inf.is_infinite())
  assert_false(positive_inf.is_negative())
  assert_true(negative_inf.is_infinite())
  assert_true(negative_inf.is_negative())
  assert_true(flipped_inf.is_infinite())
  assert_true(flipped_inf.is_negative())
  assert_true(positive_flags.division_by_zero)
  assert_true(negative_flags.division_by_zero)
  assert_true(flipped_flags.division_by_zero)
  assert_false(positive_flags.invalid_operation)
  assert_true(undefined_result.is_qnan())
  assert_true(undefined_flags.invalid_operation)
  assert_true(undefined_flags.division_undefined)
}

///|
test "decimal divide_integer handles huge exponent boundaries without overflow" {
  let ctx = @decimal.DecimalContext::new(
    precision=8,
    e_min=-999999999,
    e_max=999999999,
  )
  let one = @decimal.Decimal::one(precision=32)
  let huge_divisor = @decimal.Decimal::from_string(
    "0.99e999999999",
    precision=32,
  ).unwrap()
  let huge_dividend = @decimal.Decimal::from_string("9e999999999", precision=32).unwrap()
  let tiny_divisor = @decimal.Decimal::from_string("9e-999999999", precision=32).unwrap()
  let tenth = @decimal.Decimal::from_string("0.1", precision=32).unwrap()
  let (under_one, under_one_flags) = one.divide_integer(huge_divisor, ctx)
  let (too_wide, too_wide_flags) = huge_dividend.divide_integer(one, ctx)
  let (tiny_scale, tiny_scale_flags) = tenth.divide_integer(tiny_divisor, ctx)
  assert_eq(under_one.compare_total(@decimal.Decimal::zero(precision=8)), 0)
  assert_false(under_one_flags.has_error())
  assert_true(too_wide.is_qnan())
  assert_true(too_wide_flags.invalid_operation)
  assert_true(too_wide_flags.division_impossible)
  assert_true(tiny_scale.is_qnan())
  assert_true(tiny_scale_flags.invalid_operation)
  assert_true(tiny_scale_flags.division_impossible)
}

///|
test "decimal subset divide_integer canonicalizes zero quotients" {
  let subset_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
    extended=false,
  )
  let neg_one = @decimal.Decimal::from_string("-1", precision=16).unwrap()
  let two = @decimal.Decimal::from_int(2, precision=16)
  let neg_inf = @decimal.Decimal::inf(@def.Sign::Negative, precision=16)
  let (finite_zero, finite_zero_flags) = neg_one.divide_integer(two, subset_ctx)
  let (inf_zero, inf_zero_flags) = neg_one.divide_integer(neg_inf, subset_ctx)
  assert_eq(finite_zero.to_string(), "0")
  assert_false(finite_zero.is_negative_zero())
  assert_false(finite_zero_flags.has_error())
  assert_eq(inf_zero.to_string(), "0")
  assert_false(inf_zero.is_negative_zero())
  assert_false(inf_zero_flags.has_error())
}

///|
test "decimal divide_integer zero quotient preserves rounded-only flags" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
    extended=false,
  )
  let (rounded_zero, rounded_zero_flags) = @decimal.Decimal::one(precision=32).divide_integer(
    @decimal.Decimal::from_string("12345678000", precision=32).unwrap(),
    ctx,
  )
  assert_eq(decimal_coeff_signed(rounded_zero), 0N)
  assert_false(rounded_zero.is_negative_zero())
  assert_true(rounded_zero_flags.rounded)
  assert_false(rounded_zero_flags.inexact)
}

///|
test "decimal divide_integer zero quotient preserves rounded and inexact flags" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
    extended=false,
  )
  let (inexact_zero, inexact_zero_flags) = @decimal.Decimal::one(precision=32).divide_integer(
    @decimal.Decimal::from_string("1234567891", precision=32).unwrap(),
    ctx,
  )
  assert_eq(decimal_coeff_signed(inexact_zero), 0N)
  assert_false(inexact_zero.is_negative_zero())
  assert_true(inexact_zero_flags.rounded)
  assert_true(inexact_zero_flags.inexact)
}

///|
test "decimal divide_integer truncates sub-unit quotients above one half" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
    extended=false,
  )
  let (value, flags) = @decimal.Decimal::from_string("0.9", precision=32)
    .unwrap()
    .divide_integer(@decimal.Decimal::one(precision=32), ctx)
  assert_eq(decimal_coeff_signed(value), 0N)
  assert_false(value.is_negative_zero())
  assert_false(flags.has_error())
}

///|
test "decimal divide_integer huge zero quotient matches full official representative" {
  let wide_ctx = @decimal.DecimalContext::new(
    precision=16,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999999999,
    e_max=999999999,
    extended=false,
  )
  let (huge_zero, huge_zero_flags) = @decimal.Decimal::from_string(
      "1.23456789012345E-0",
      precision=64,
    )
    .unwrap()
    .divide_integer(
      @decimal.Decimal::from_string("9E+999999999", precision=64).unwrap(),
      wide_ctx,
    )
  assert_eq(decimal_coeff_signed(huge_zero), 0N)
  assert_false(huge_zero.is_negative_zero())
  assert_false(huge_zero_flags.has_error())
}

///|
test "decimal divide_integer extended zero quotient preserves official dd representatives" {
  let ctx = @decimal.DecimalContext::new(
    precision=16,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-383,
    e_max=384,
    clamp=true,
  )
  run_decimal_binary_conformance_case(
    "dddvi270",
    DivideInteger,
    "1",
    "1e384",
    "0",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "dddvi271",
    DivideInteger,
    "1",
    "0.9e384",
    "0",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "dddvi272",
    DivideInteger,
    "1",
    "0.99e384",
    "0",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "dddvi1119",
    DivideInteger,
    "3E-394",
    "-1e+5",
    "-0",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "dddvi1124",
    DivideInteger,
    "1E-394",
    "-1e+4",
    "-0",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "dddvi1130",
    DivideInteger,
    "3.0E-394",
    "-1e+5",
    "-0",
    ctx,
  )
}

///|
test "decimal divide_integer matches official0 huge lost-digits representative" {
  let huge_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999999999,
    e_max=999999999,
    extended=false,
  ).gda()
  let (huge_zero, huge_zero_flags) = @decimal.Decimal::from_string(
      "1.23456789012345E-0",
      precision=64,
    )
    .unwrap()
    .divide_integer(
      @decimal.Decimal::from_string("9E+999999999", precision=64).unwrap(),
      huge_ctx,
    )
  assert_eq(decimal_coeff_signed(huge_zero), 0N)
  assert_false(huge_zero.is_negative_zero())
  assert_true(huge_zero_flags.rounded)
  assert_true(huge_zero_flags.inexact)
}

///|
test "decimal divide_integer matches official0 huge impossible representative" {
  let huge_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999999999,
    e_max=999999999,
    extended=false,
  ).gda()
  let (too_wide, too_wide_flags) = @decimal.Decimal::from_string(
      "9E+999999999",
      precision=64,
    )
    .unwrap()
    .divide_integer(
      @decimal.Decimal::from_string("0.23456789012345", precision=64).unwrap(),
      huge_ctx,
    )
  assert_true(too_wide.is_qnan())
  assert_true(too_wide_flags.invalid_operation)
  assert_true(too_wide_flags.division_impossible)
}

///|
test "decimal divide_integer matches official0 lost-digits zero-quotient representative" {
  let lostdigits_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
    extended=false,
  )
  let (rounded_zero, rounded_zero_flags) = @decimal.Decimal::one(precision=32).divide_integer(
    @decimal.Decimal::from_string("1234567891", precision=32).unwrap(),
    lostdigits_ctx,
  )
  assert_eq(decimal_coeff_signed(rounded_zero), 0N)
  assert_false(rounded_zero.is_negative_zero())
  assert_true(rounded_zero_flags.rounded)
  assert_true(rounded_zero_flags.inexact)
}

///|
test "decimal remainder zero-divisor flags follow gda classification" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let nonzero = @decimal.Decimal::from_string("0.0001", precision=16).unwrap()
  let zero = @decimal.Decimal::zero(precision=16)
  let neg_zero = @decimal.Decimal::negative_zero(precision=16)
  let (remainder_invalid, remainder_invalid_flags) = nonzero.remainder(
    zero, ctx,
  )
  let (remainder_undefined, remainder_undefined_flags) = zero.remainder(
    zero, ctx,
  )
  let (near_invalid, near_invalid_flags) = nonzero.remainder_near(neg_zero, ctx)
  let (near_undefined, near_undefined_flags) = zero.remainder_near(
    neg_zero, ctx,
  )
  assert_true(remainder_invalid.is_qnan())
  assert_true(remainder_invalid_flags.invalid_operation)
  assert_false(remainder_invalid_flags.division_by_zero)
  assert_false(remainder_invalid_flags.division_undefined)
  assert_true(remainder_undefined.is_qnan())
  assert_true(remainder_undefined_flags.invalid_operation)
  assert_true(remainder_undefined_flags.division_undefined)
  assert_true(near_invalid.is_qnan())
  assert_true(near_invalid_flags.invalid_operation)
  assert_false(near_invalid_flags.division_by_zero)
  assert_false(near_invalid_flags.division_undefined)
  assert_true(near_undefined.is_qnan())
  assert_true(near_undefined_flags.invalid_operation)
  assert_true(near_undefined_flags.division_undefined)
}

///|
test "decimal remainder preserves preferred exponent when quotient is zero" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let value = @decimal.Decimal::from_string("0.5", precision=8).unwrap()
  let cents = @decimal.Decimal::from_string("2.01", precision=8).unwrap()
  let mills = @decimal.Decimal::from_string("2.001", precision=8).unwrap()
  let (remainder_cents, remainder_cents_flags) = value.remainder(cents, ctx)
  let (remainder_mills, remainder_mills_flags) = value.remainder(mills, ctx)
  let (near_cents, near_cents_flags) = value.remainder_near(cents, ctx)
  let (near_mills, near_mills_flags) = value.remainder_near(mills, ctx)
  assert_eq(remainder_cents.to_string(), "0.50")
  assert_eq(remainder_mills.to_string(), "0.500")
  assert_eq(near_cents.to_string(), "0.50")
  assert_eq(near_mills.to_string(), "0.500")
  assert_false(remainder_cents_flags.has_error())
  assert_false(remainder_mills_flags.has_error())
  assert_false(near_cents_flags.has_error())
  assert_false(near_mills_flags.has_error())
}

///|
test "decimal subset remainder zero-quotient preserves nonzero sign" {
  let subset_ctx = @decimal.DecimalContext::new(
    precision=8,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-999,
    e_max=999,
    extended=false,
  )
  let negative = @decimal.Decimal::from_string("-0.5", precision=16).unwrap()
  let divisor = @decimal.Decimal::from_string("2.01", precision=16).unwrap()
  let (remainder, remainder_flags) = negative.remainder(divisor, subset_ctx)
  let (near, near_flags) = negative.remainder_near(divisor, subset_ctx)
  assert_eq(remainder.to_string(), "-0.50")
  assert_eq(near.to_string(), "-0.50")
  assert_false(remainder_flags.has_error())
  assert_false(near_flags.has_error())
}

///|
test "decimal remainder preserves preferred exponent with nonzero quotient" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let five = @decimal.Decimal::from_string("5", precision=16).unwrap()
  let divisor = @decimal.Decimal::from_string("2.000", precision=16).unwrap()
  let (remainder, remainder_flags) = five.remainder(divisor, ctx)
  let (near, near_flags) = five.remainder_near(divisor, ctx)
  assert_eq(remainder.to_string(), "1.000")
  assert_eq(near.to_string(), "1.000")
  assert_false(remainder_flags.has_error())
  assert_false(near_flags.has_error())
}

///|
test "decimal subset remainder canonicalizes negative zero zero-quotient results" {
  let subset_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
    extended=false,
  )
  let neg_zero = @decimal.Decimal::from_string("-0.00", precision=16).unwrap()
  let one = @decimal.Decimal::one(precision=16)
  let (remainder, remainder_flags) = neg_zero.remainder(one, subset_ctx)
  let (near, near_flags) = neg_zero.remainder_near(one, subset_ctx)
  assert_eq(remainder.to_string(), "0")
  assert_false(remainder.is_negative_zero())
  assert_false(remainder_flags.has_error())
  assert_eq(near.to_string(), "0")
  assert_false(near.is_negative_zero())
  assert_false(near_flags.has_error())
}

///|
test "decimal remainder_near respects special values and context-rounded zero quotient" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let huge = @decimal.Decimal::from_string("9E+999999999", precision=32).unwrap()
  let exact = @decimal.Decimal::from_string("1.23456789012345", precision=32).unwrap()
  let inf = @decimal.Decimal::inf(@def.Sign::Positive, precision=32)
  let snan = @decimal.Decimal::signaling_nan(payload=91N, precision=32)
  let (finite_over_inf, finite_over_inf_flags) = exact.remainder_near(inf, ctx)
  let (inf_over_finite, inf_over_finite_flags) = inf.remainder_near(exact, ctx)
  let (snan_result, snan_flags) = inf.remainder_near(snan, ctx)
  assert_eq(
    finite_over_inf.compare_total(
      @decimal.Decimal::from_string("1.2345679", precision=32).unwrap(),
    ),
    0,
  )
  assert_true(finite_over_inf_flags.rounded)
  assert_true(finite_over_inf_flags.inexact)
  assert_true(inf_over_finite.is_qnan())
  assert_true(inf_over_finite_flags.invalid_operation)
  assert_true(snan_result.is_qnan())
  assert_eq(snan_result.nan_payload(), 91N)
  assert_true(snan_flags.invalid_operation)
  let (tiny_over_huge, tiny_over_huge_flags) = @decimal.Decimal::from_string(
      "9E-999999999",
      precision=32,
    )
    .unwrap()
    .remainder_near(huge, ctx)
  assert_eq(
    tiny_over_huge.compare_total(
      @decimal.Decimal::from_string("9E-999999999", precision=32).unwrap(),
    ),
    0,
  )
  assert_false(tiny_over_huge_flags.has_error())
}

///|
test "decimal remainder matches official0 huge lost-digits representative" {
  let huge_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999999999,
    e_max=999999999,
    extended=false,
  ).gda()
  let huge_divisor = @decimal.Decimal::from_string("9E+999999999", precision=64).unwrap()
  let (huge_remainder, huge_remainder_flags) = @decimal.Decimal::from_string(
      "1.23456789012345E-0",
      precision=64,
    )
    .unwrap()
    .remainder(huge_divisor, huge_ctx)
  assert_eq(huge_remainder.to_string(), "1.23456789")
  assert_true(huge_remainder_flags.rounded)
  assert_true(huge_remainder_flags.inexact)
}

///|
test "decimal remainder_near matches official0 huge lost-digits representative" {
  let huge_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999999999,
    e_max=999999999,
    extended=false,
  ).gda()
  let huge_divisor = @decimal.Decimal::from_string("9E+999999999", precision=64).unwrap()
  let (huge_near, huge_near_flags) = @decimal.Decimal::from_string(
      "1.23456789012345E-0",
      precision=64,
    )
    .unwrap()
    .remainder_near(huge_divisor, huge_ctx)
  assert_eq(huge_near.to_string(), "1.23456789")
  assert_true(huge_near_flags.rounded)
  assert_true(huge_near_flags.inexact)
}

///|
test "decimal remainder huge impossible representatives match official0" {
  let huge_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999999999,
    e_max=999999999,
    extended=false,
  ).gda()
  let huge = @decimal.Decimal::from_string("9E+999999999", precision=64).unwrap()
  let positive_small = @decimal.Decimal::from_string(
    "0.23456789012345",
    precision=64,
  ).unwrap()
  let negative_small = @decimal.Decimal::from_string(
    "-0.83456789012345",
    precision=64,
  ).unwrap()
  let (remainder_positive, remainder_positive_flags) = huge.remainder(
    positive_small, huge_ctx,
  )
  let (remainder_negative, remainder_negative_flags) = huge.remainder(
    negative_small, huge_ctx,
  )
  let (near_positive, near_positive_flags) = huge.remainder_near(
    positive_small, huge_ctx,
  )
  let (near_negative, near_negative_flags) = huge.remainder_near(
    negative_small, huge_ctx,
  )
  assert_true(remainder_positive.is_qnan())
  assert_true(remainder_positive_flags.invalid_operation)
  assert_true(remainder_positive_flags.division_impossible)
  assert_true(remainder_negative.is_qnan())
  assert_true(remainder_negative_flags.invalid_operation)
  assert_true(remainder_negative_flags.division_impossible)
  assert_true(near_positive.is_qnan())
  assert_true(near_positive_flags.invalid_operation)
  assert_true(near_positive_flags.division_impossible)
  assert_true(near_negative.is_qnan())
  assert_true(near_negative_flags.invalid_operation)
  assert_true(near_negative_flags.division_impossible)
}

///|
test "decimal remainder matches official0 lost-digits zero representatives" {
  let lostdigits_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
    extended=false,
  )
  let ten = @decimal.Decimal::from_int(10, precision=32)
  let (lost_remainder, lost_remainder_flags) = @decimal.Decimal::from_string(
      "1234567891",
      precision=32,
    )
    .unwrap()
    .remainder(ten, lostdigits_ctx)
  let (lost_near, lost_near_flags) = @decimal.Decimal::from_string(
      "1234567891",
      precision=32,
    )
    .unwrap()
    .remainder_near(ten, lostdigits_ctx)
  assert_eq(decimal_coeff_signed(lost_remainder), 0N)
  assert_true(lost_remainder_flags.rounded)
  assert_true(lost_remainder_flags.inexact)
  assert_eq(decimal_coeff_signed(lost_near), 0N)
  assert_true(lost_near_flags.rounded)
  assert_true(lost_near_flags.inexact)
}

///|
test "decimal context supports gda-only rounding modes" {
  let source = @decimal.Decimal::from_string("1.25", precision=12).unwrap()
  let zero = @decimal.Decimal::zero(precision=12)
  let half_up_ctx = @decimal.DecimalContext::new(
    precision=2,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
  )
  let half_down_ctx = @decimal.DecimalContext::new(
    precision=2,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfDown,
  )
  let (half_up, half_up_flags) = source.add_ctx(zero, half_up_ctx)
  let (half_down, half_down_flags) = source.add_ctx(zero, half_down_ctx)
  assert_eq(half_up.to_string(), "1.3")
  assert_true(half_up_flags.rounded)
  assert_true(half_up_flags.inexact)
  assert_eq(half_down.to_string(), "1.2")
  assert_true(half_down_flags.rounded)
  assert_true(half_down_flags.inexact)
  let zero_five_ctx = @decimal.DecimalContext::new(
    precision=2,
    decimal_rounding=@decimal.DecimalRoundingMode::ZeroFiveUp,
  )
  let (zero_five_up, _) = @decimal.Decimal::from_string("1.051", precision=12)
    .unwrap()
    .plus_ctx(zero_five_ctx)
  let (zero_five_down, _) = @decimal.Decimal::from_string("1.251", precision=12)
    .unwrap()
    .plus_ctx(zero_five_ctx)
  assert_eq(zero_five_up.to_string(), "1.1")
  assert_eq(zero_five_down.to_string(), "1.2")
  assert_true(@decimal.DecimalRoundingMode::HalfUp.to_arithmetic() is None)
  assert_true(@decimal.DecimalRoundingMode::HalfDown.to_arithmetic() is None)
  assert_true(@decimal.DecimalRoundingMode::ZeroFiveUp.to_arithmetic() is None)
}

///|
test "decimal context division reports inexact and exceptional flags" {
  let ctx = @decimal.DecimalContext::new(precision=6)
  let one = @decimal.Decimal::one(precision=12)
  let three = @decimal.Decimal::from_int(3, precision=12)
  let four = @decimal.Decimal::from_int(4, precision=12)
  let zero = @decimal.Decimal::zero(precision=12)
  let (quarter, quarter_flags) = one.div_ctx(four, ctx)
  assert_eq(quarter.to_string(), "0.25")
  assert_false(quarter_flags.rounded)
  assert_false(quarter_flags.inexact)
  let (third, third_flags) = one.div_ctx(three, ctx)
  assert_true(third.to_string().has_prefix("0.333333"))
  assert_true(third_flags.rounded)
  assert_true(third_flags.inexact)
  let (inf, div_zero_flags) = one.div_ctx(zero, ctx)
  assert_true(inf.classify() == @lf_arith.FpClass::Infinity)
  assert_true(div_zero_flags.division_by_zero)
  assert_false(div_zero_flags.division_undefined)
  let (nan, undefined_flags) = zero.div_ctx(zero, ctx)
  assert_true(nan.classify() == @lf_arith.FpClass::NaN)
  assert_true(undefined_flags.invalid_operation)
  assert_true(undefined_flags.division_undefined)
}

///|
test "decimal exact division preserves preferred integer cohort when it fits precision" {
  let ctx = @decimal.DecimalContext::new(precision=9)
  let one = @decimal.Decimal::one(precision=12)
  let ten = @decimal.Decimal::from_int(10, precision=12)
  let hundred = @decimal.Decimal::from_int(100, precision=12)
  let thousand = @decimal.Decimal::from_int(1000, precision=12)
  let tiny = @decimal.Decimal::from_string("1E-8", precision=12).unwrap()
  let tinier = @decimal.Decimal::from_string("1E-9", precision=12).unwrap()
  let (ten_over_one, flags1) = ten.div_ctx(one, ctx)
  let (thousand_over_hundred, flags2) = thousand.div_ctx(hundred, ctx)
  let (plain_power, flags3) = one.div_ctx(tiny, ctx)
  let (scientific_power, flags4) = one.div_ctx(tinier, ctx)
  assert_eq(ten_over_one.to_string(), "1E+1")
  assert_eq(thousand_over_hundred.to_string(), "1E+1")
  assert_eq(plain_power.to_string(), "1E+8")
  assert_eq(
    scientific_power.compare_total(
      @decimal.Decimal::from_string("1E+9", precision=12).unwrap(),
    ),
    0,
  )
  assert_false(flags1.rounded)
  assert_false(flags2.rounded)
  assert_false(flags3.rounded)
  assert_false(flags4.rounded)
}

///|
test "decimal inexact division matches official rounded quotients" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
  )
  let lhs = @decimal.Decimal::from_int(12345, precision=16)
  let rhs1 = @decimal.Decimal::from_string("4.999", precision=16).unwrap()
  let rhs2 = @decimal.Decimal::from_string("4.99", precision=16).unwrap()
  let rhs3 = @decimal.Decimal::from_string("5.001", precision=16).unwrap()
  let (q1, f1) = lhs.div_ctx(rhs1, ctx)
  let (q2, f2) = lhs.div_ctx(rhs2, ctx)
  let (q3, f3) = lhs.div_ctx(rhs3, ctx)
  assert_eq(q1.to_string(), "2469.49390")
  assert_eq(q2.to_string(), "2473.94790")
  assert_eq(q3.to_string(), "2468.50630")
  assert_true(f1.rounded)
  assert_true(f1.inexact)
  assert_true(f2.rounded)
  assert_true(f2.inexact)
  assert_true(f3.rounded)
  assert_true(f3.inexact)
}

///|
test "decimal sqrt context reports exact inexact and invalid cases" {
  let ctx = @decimal.DecimalContext::new(precision=3)
  let (exact, exact_flags) = @decimal.Decimal::from_int(4, precision=12).sqrt_ctx(
    ctx,
  )
  assert_eq(exact.to_string(), "2")
  assert_false(exact_flags.rounded)
  assert_false(exact_flags.inexact)
  let (rounded, rounded_flags) = @decimal.Decimal::from_int(2, precision=12).sqrt_ctx(
    ctx,
  )
  assert_eq(rounded.to_string(), "1.41")
  assert_true(rounded_flags.rounded)
  assert_true(rounded_flags.inexact)
  let (nan, invalid_flags) = @decimal.Decimal::from_int(-1, precision=12).sqrt_ctx(
    ctx,
  )
  assert_true(nan.classify() == @lf_arith.FpClass::NaN)
  assert_true(invalid_flags.invalid_operation)
  let (negative_zero, zero_flags) = @decimal.Decimal::from_string(
      "-0.00",
      precision=12,
    )
    .unwrap()
    .sqrt_ctx(ctx)
  assert_eq(negative_zero.to_string(), "-0.0")
  assert_false(zero_flags.invalid_operation)
}

///|
test "decimal sqrt propagates nan payloads with quieting semantics" {
  let ctx = @decimal.DecimalContext::new(precision=5)
  let qnan = @decimal.Decimal::quiet_nan(
    payload=456N,
    negative=true,
    precision=8,
  )
  let snan = @decimal.Decimal::signaling_nan(
    payload=1234567890N,
    negative=true,
    precision=8,
  )
  let (quiet_result, quiet_flags) = qnan.sqrt_ctx(ctx)
  let (signal_result, signal_flags) = snan.sqrt_ctx(ctx)
  assert_eq(quiet_result.to_string(), "-nan456")
  assert_true(quiet_result.is_quiet_nan())
  assert_true(quiet_result.is_negative())
  assert_eq(quiet_result.nan_payload(), 456N)
  assert_false(quiet_flags.invalid_operation)
  assert_eq(signal_result.to_string(), "-nan67890")
  assert_true(signal_result.is_quiet_nan())
  assert_true(signal_result.is_negative())
  assert_false(signal_result.is_signaling_nan())
  assert_eq(signal_result.nan_payload(), 67890N)
  assert_true(signal_flags.invalid_operation)
}

///|
test "decimal sqrt exact results preserve cohort-only input rounding" {
  let ctx = @decimal.DecimalContext::new(
    precision=2,
    rounding=RoundingMode::ToNearestEven,
    e_min=-999,
    e_max=999,
  )
  let (cohort_exact, cohort_flags) = @decimal.Decimal::from_string(
      "9.00E-2",
      precision=12,
    )
    .unwrap()
    .sqrt_ctx(ctx)
  assert_eq(cohort_exact.to_string(), "0.30")
  assert_false(cohort_flags.rounded)
  assert_false(cohort_flags.inexact)
  let (unit_exact, unit_flags) = @decimal.Decimal::from_string(
      "10.0E-1",
      precision=12,
    )
    .unwrap()
    .sqrt_ctx(ctx)
  assert_eq(unit_exact.to_string(), "1.0")
  assert_false(unit_flags.rounded)
  assert_false(unit_flags.inexact)
}

///|
test "decimal context flags signaling nan as invalid operation" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let snan = @decimal.Decimal::signaling_nan(payload=9N, precision=8)
  let one = @decimal.Decimal::one(precision=8)
  let (value, flags) = snan.add_ctx(one, ctx)
  assert_true(value.classify() == @lf_arith.FpClass::NaN)
  assert_true(flags.invalid_operation)
}

///|
test "decimal context clamps finite exponent by padding coefficient" {
  let ctx = @decimal.DecimalContext::new(
    precision=3,
    e_max=9,
    e_min=-9,
    clamp=true,
  )
  let value = @decimal.Decimal::from_string("1e9", precision=10).unwrap()
  let (clamped, flags) = value.add_ctx(
    @decimal.Decimal::zero(precision=10),
    ctx,
  )
  assert_eq(clamped.to_string(), "1.00E+9")
  assert_eq(decimal_coeff_magnitude(clamped), 100N)
  assert_eq(clamped.exponent10(), 7)
  assert_true(flags.clamped)
  assert_true(flags.rounded)
  assert_false(flags.inexact)
}

///|
test "decimal context overflows finite results above emax" {
  let ctx = @decimal.DecimalContext::new(precision=3, e_max=3, e_min=-9)
  let value = @decimal.Decimal::from_string("1e4", precision=10).unwrap()
  let (overflowed, flags) = value.add_ctx(
    @decimal.Decimal::zero(precision=10),
    ctx,
  )
  assert_true(overflowed.classify() == @lf_arith.FpClass::Infinity)
  assert_true(flags.overflow)
  assert_true(flags.rounded)
  assert_true(flags.inexact)
}

///|
test "decimal context directed overflow follows gda rounding result selection" {
  let positive = @decimal.Decimal::from_string(
    "9999999999999999E+369",
    precision=32,
  ).unwrap()
  let positive_rhs = @decimal.Decimal::from_string("9E+369", precision=32).unwrap()
  let negative = @decimal.Decimal::from_string(
    "-9999999999999999E+369",
    precision=32,
  ).unwrap()
  let negative_rhs = @decimal.Decimal::from_string("-9E+369", precision=32).unwrap()
  let down_ctx = @decimal.DecimalContext::new(
    precision=16,
    decimal_rounding=@decimal.DecimalRoundingMode::Down,
    e_min=-383,
    e_max=384,
    extended=false,
  )
  let ceiling_ctx = @decimal.DecimalContext::new(
    precision=16,
    decimal_rounding=@decimal.DecimalRoundingMode::Ceiling,
    e_min=-383,
    e_max=384,
    extended=false,
  )
  let floor_ctx = @decimal.DecimalContext::new(
    precision=16,
    decimal_rounding=@decimal.DecimalRoundingMode::Floor,
    e_min=-383,
    e_max=384,
    extended=false,
  )
  let zero_five_up_ctx = @decimal.DecimalContext::new(
    precision=16,
    decimal_rounding=@decimal.DecimalRoundingMode::ZeroFiveUp,
    e_min=-383,
    e_max=384,
    extended=false,
  )
  let expected_positive = @decimal.Decimal::from_string(
    "9.999999999999999E+384",
    precision=32,
  ).unwrap()
  let expected_negative = @decimal.Decimal::from_string(
    "-9.999999999999999E+384",
    precision=32,
  ).unwrap()
  let (down_positive_sci, _) = @decimal.Decimal::to_sci_string(
    "9.999999999999999E+384", down_ctx,
  )
  let (down_negative_sci, _) = @decimal.Decimal::to_sci_string(
    "-9.999999999999999E+384", down_ctx,
  )

  let (down_positive, down_positive_flags) = positive.add_ctx(
    positive_rhs, down_ctx,
  )
  assert_eq(down_positive.compare_total(expected_positive).to_string(), "0")
  assert_eq(down_positive_sci, "9.999999999999999E+384")
  assert_true(down_positive_flags.overflow)
  assert_true(down_positive_flags.rounded)
  assert_true(down_positive_flags.inexact)
  let (down_negative, down_negative_flags) = negative.add_ctx(
    negative_rhs, down_ctx,
  )
  assert_eq(down_negative.compare_total(expected_negative).to_string(), "0")
  assert_eq(down_negative_sci, "-9.999999999999999E+384")
  assert_true(down_negative_flags.overflow)
  assert_true(down_negative_flags.rounded)
  assert_true(down_negative_flags.inexact)

  let (ceiling_negative, ceiling_negative_flags) = negative.add_ctx(
    negative_rhs, ceiling_ctx,
  )
  assert_eq(ceiling_negative.compare_total(expected_negative).to_string(), "0")
  assert_true(ceiling_negative_flags.overflow)
  assert_true(ceiling_negative_flags.rounded)
  assert_true(ceiling_negative_flags.inexact)

  let (floor_positive, floor_positive_flags) = positive.add_ctx(
    positive_rhs, floor_ctx,
  )
  assert_eq(floor_positive.compare_total(expected_positive).to_string(), "0")
  assert_true(floor_positive_flags.overflow)
  assert_true(floor_positive_flags.rounded)
  assert_true(floor_positive_flags.inexact)

  let (zero_five_up_positive, zero_five_up_positive_flags) = positive.add_ctx(
    positive_rhs, zero_five_up_ctx,
  )
  assert_eq(
    zero_five_up_positive.compare_total(expected_positive).to_string(),
    "0",
  )
  assert_true(zero_five_up_positive_flags.overflow)
  assert_true(zero_five_up_positive_flags.rounded)
  assert_true(zero_five_up_positive_flags.inexact)
  let (zero_five_up_negative, zero_five_up_negative_flags) = negative.add_ctx(
    negative_rhs, zero_five_up_ctx,
  )
  assert_eq(
    zero_five_up_negative.compare_total(expected_negative).to_string(),
    "0",
  )
  assert_true(zero_five_up_negative_flags.overflow)
  assert_true(zero_five_up_negative_flags.rounded)
  assert_true(zero_five_up_negative_flags.inexact)
}

///|
test "decimal context distinguishes subnormal from underflow" {
  let ctx = @decimal.DecimalContext::new(precision=3, e_max=9, e_min=-2)
  let exact = @decimal.Decimal::from_string("0.001", precision=10).unwrap()
  let inexact = @decimal.Decimal::from_string("0.001234", precision=10).unwrap()
  let (exact_subnormal, exact_flags) = exact.add_ctx(
    @decimal.Decimal::zero(precision=10),
    ctx,
  )
  assert_eq(exact_subnormal.to_string(), "0.001")
  assert_true(exact_flags.subnormal)
  assert_false(exact_flags.underflow)
  assert_false(exact_flags.inexact)
  let (underflowed, underflow_flags) = inexact.add_ctx(
    @decimal.Decimal::zero(precision=10),
    ctx,
  )
  assert_eq(underflowed.to_string(), "0.0012")
  assert_true(underflow_flags.subnormal)
  assert_true(underflow_flags.underflow)
  assert_true(underflow_flags.inexact)
}

///|
test "decimal dectest-style runner covers context operations and flags" {
  let ctx = @decimal.DecimalContext::new(
    precision=3,
    rounding=RoundingMode::ToNearestEven,
    e_min=-2,
    e_max=9,
    clamp=true,
  )
  run_decimal_binary_conformance_case(
    "lfadd001",
    Add,
    "1.20",
    "3.40",
    "4.60",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "lfadd002",
    Add,
    "1.234",
    "0",
    "1.23",
    ctx,
    rounded=true,
    inexact=true,
  )
  run_decimal_binary_conformance_case(
    "lfsub001",
    Subtract,
    "1.20",
    "1.20",
    "0.00",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "lfmul001",
    Multiply,
    "9.99",
    "9.99",
    "99.8",
    ctx,
    rounded=true,
    inexact=true,
  )
  run_decimal_binary_conformance_case(
    "lfdiv001",
    Divide,
    "1",
    "3",
    "0.333",
    ctx,
    rounded=true,
    inexact=true,
  )
  run_decimal_binary_conformance_case(
    "lfdiv002",
    Divide,
    "1",
    "0",
    "inf",
    ctx,
    division_by_zero=true,
  )
  run_decimal_binary_conformance_case(
    "lfquant001",
    Quantize,
    "1.235",
    "0.01",
    "1.24",
    ctx,
    rounded=true,
    inexact=true,
  )
  run_decimal_unary_conformance_case(
    "lftoi001",
    ToIntegralExact,
    "2.500",
    "2",
    ctx,
    rounded=true,
    inexact=true,
  )
  run_decimal_unary_conformance_case(
    "lfreduce001",
    Reduce,
    "1.2300",
    "1.23",
    ctx,
    rounded=true,
  )
  run_decimal_unary_conformance_case("lfreduce002", Reduce, "-0.00", "-0", ctx)
  run_decimal_unary_conformance_case(
    "lfreduce003",
    Reduce,
    "1.234",
    "1.23",
    ctx,
    rounded=true,
    inexact=true,
  )
  run_decimal_binary_conformance_case(
    "lfclamp001",
    Add,
    "1e9",
    "0",
    "1.00E+9",
    ctx,
    clamped=true,
    rounded=true,
  )
  run_decimal_binary_conformance_case(
    "lfunder001",
    Add,
    "0.001234",
    "0",
    "0.0012",
    ctx,
    rounded=true,
    inexact=true,
    underflow=true,
    subnormal=true,
  )
}

///|
test "decimal gda core operations cover fma integer division and remainder" {
  let ctx = @decimal.DecimalContext::new(
    precision=3,
    rounding=RoundingMode::ToNearestEven,
    e_min=-9,
    e_max=9,
  )
  run_decimal_ternary_conformance_case(
    "lffma001",
    Fma,
    "9.99",
    "9.99",
    "-99.7",
    "0.100",
    ctx,
    rounded=true,
    inexact=true,
  )
  run_decimal_binary_conformance_case(
    "lfdivint001",
    DivideInteger,
    "10",
    "3",
    "3",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "lfdivint002",
    DivideInteger,
    "12345",
    "1",
    "nan",
    ctx,
    invalid_operation=true,
    division_impossible=true,
  )
  run_decimal_binary_conformance_case(
    "lfrem001",
    Remainder,
    "10",
    "3",
    "1",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "lfrem002",
    Remainder,
    "-10",
    "3",
    "-1",
    ctx,
  )
  let wide_ctx = @decimal.DecimalContext::new(
    precision=16,
    rounding=RoundingMode::ToNearestEven,
    e_min=-999999999,
    e_max=999999999,
  )
  run_decimal_binary_conformance_case(
    "lfdivint003",
    DivideInteger,
    "1.23456789012345E-0",
    "9E+999999999",
    "0",
    wide_ctx,
  )
  run_decimal_binary_conformance_case(
    "lfdivint004",
    DivideInteger,
    "0.100",
    "9E+999999999",
    "0",
    wide_ctx,
  )
  run_decimal_binary_conformance_case(
    "lfdivint005",
    DivideInteger,
    "1",
    "12345678000",
    "0",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "lfdivint006",
    DivideInteger,
    "1",
    "1234567891",
    "0",
    ctx,
  )
  run_decimal_binary_conformance_case(
    "lfrem003",
    Remainder,
    "0.100",
    "9E+999999999",
    "0.100",
    wide_ctx,
  )
  run_decimal_binary_conformance_case(
    "lfrem004",
    Remainder,
    "9E-999999999",
    "9.100",
    "9E-999999999",
    wide_ctx,
  )
}

///|
test "decimal power handles million-scale integer exponents with rounded gda results" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    rounding=RoundingMode::ToNearestEven,
    e_min=-999999,
    e_max=999999,
  )
  run_decimal_binary_conformance_case(
    "powx183",
    Power,
    "7",
    "1000000",
    "1.09651419E+845098",
    ctx,
    rounded=true,
    inexact=true,
  )
  run_decimal_binary_conformance_case(
    "powx184",
    Power,
    "7",
    "1000001",
    "7.67559934E+845098",
    ctx,
    rounded=true,
    inexact=true,
  )
  run_decimal_binary_conformance_case(
    "powx186",
    Power,
    "7",
    "-1000001",
    "1.30282986E-845099",
    ctx,
    rounded=true,
    inexact=true,
  )
}

///|
test "decimal power preserves exact cohort zeros for integer powers" {
  let wide_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-999_999,
    e_max=999_999,
  )
  run_decimal_binary_conformance_case(
    "powx075",
    Power,
    "6.0",
    "1",
    "6.0",
    wide_ctx,
  )
  run_decimal_binary_conformance_case(
    "powx076",
    Power,
    "6.0",
    "2",
    "36.00",
    wide_ctx,
  )

  let subnormal_ctx = @decimal.DecimalContext::new(
    precision=5,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-999,
    e_max=999,
  )
  run_decimal_binary_conformance_case(
    "powx404",
    Power,
    "10E-501",
    "2",
    "1.00E-1000",
    subnormal_ctx,
    subnormal=true,
  )
  run_decimal_binary_conformance_case(
    "powx416",
    Power,
    "10E-334",
    "3",
    "1.000E-999",
    subnormal_ctx,
  )
}

///|
test "decimal power integer shortcuts stay conservative near subnormal and reciprocal edges" {
  let subnormal_ctx = @decimal.DecimalContext::new(
    precision=15,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-999,
    e_max=999,
  )
  run_decimal_binary_conformance_case(
    "powx392",
    Power,
    "0.099",
    "999",
    "4.360732062E-1004",
    subnormal_ctx,
    underflow=true,
    subnormal=true,
    inexact=true,
    rounded=true,
  )

  let reciprocal_ctx = @decimal.DecimalContext::new(
    precision=5,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-999,
    e_max=999,
  )
  run_decimal_binary_conformance_case(
    "powx422",
    Power,
    "2.5E-500",
    "-2",
    "1.6E+999",
    reciprocal_ctx,
  )
}

///|
test "decimal power with exponent one matches official rounding and representation cases" {
  let rounded_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-999,
    e_max=999,
  )
  run_decimal_binary_conformance_case(
    "powx701",
    Power,
    "12345678000",
    "1",
    "1.23456780E+10",
    rounded_ctx,
    rounded=true,
  )

  let exact_ctx = @decimal.DecimalContext::new(
    precision=15,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-999,
    e_max=999,
  )
  run_decimal_binary_conformance_case(
    "powx742",
    Power,
    "1234567800",
    "1",
    "1234567800",
    exact_ctx,
  )
}

///|
test "decimal total comparison orders representations without signaling unordered" {
  let one = @decimal.Decimal::from_string("1", precision=8).unwrap()
  let one_point_zero = @decimal.Decimal::from_string("1.0", precision=8).unwrap()
  let neg_zero = @decimal.Decimal::from_string("-0.00", precision=8).unwrap()
  let pos_zero = @decimal.Decimal::from_string("0.00", precision=8).unwrap()
  let quiet = @decimal.Decimal::quiet_nan(payload=2N, precision=8)
  let signaling = @decimal.Decimal::signaling_nan(payload=1N, precision=8)
  assert_true(one == one_point_zero)
  assert_true(one.compare_total(one_point_zero) > 0)
  assert_true(neg_zero.compare_total(pos_zero) < 0)
  assert_true(signaling.compare_total(quiet) < 0)
  assert_true(one.compare_total(quiet) < 0)
  assert_true(quiet.compare_total_magnitude(signaling) > 0)
}

///|
test "decimal finite comparison avoids huge exponent expansion" {
  let huge = @decimal.Decimal::from_string(
    "9.99999999E+999999999",
    precision=64,
  ).unwrap()
  let negative_huge = @decimal.Decimal::from_string(
    "-9.99999999E+999999999",
    precision=64,
  ).unwrap()
  let small = @decimal.Decimal::from_string("1E-999999999", precision=64).unwrap()
  let one = @decimal.Decimal::from_string("1", precision=64).unwrap()
  let milli = @decimal.Decimal::from_string("1E-3", precision=64).unwrap()
  assert_eq(huge.compare_total_magnitude(negative_huge), 0)
  assert_eq(huge.compare_total_magnitude(one), 1)
  assert_eq(small.compare_total_magnitude(one), -1)
  assert_eq(one.compare_total_magnitude(milli), 1)
  let trailing_zeros = @decimal.Decimal::from_string(
    "123.4560000000000000E789",
    precision=64,
  ).unwrap()
  let canonical = @decimal.Decimal::from_string("123.456E789", precision=64).unwrap()
  let zero_small = @decimal.Decimal::from_string("0E-383", precision=64).unwrap()
  let zero_large = @decimal.Decimal::from_string("0E+384", precision=64).unwrap()
  assert_eq(trailing_zeros.compare_total_magnitude(canonical), -1)
  assert_eq(canonical.compare_total_magnitude(trailing_zeros), 1)
  assert_eq(zero_small.compare_total_magnitude(zero_large), -1)
  assert_eq(zero_large.compare_total_magnitude(zero_small), 1)
}

///|
test "decimal finite compare handles same-adjusted decade boundaries" {
  let thousand = @decimal.Decimal::from_string("1000", precision=32).unwrap()
  let nine_nine_nine = @decimal.Decimal::from_string("999", precision=32).unwrap()
  let one_e_1000 = @decimal.Decimal::from_string("1E+1000", precision=32).unwrap()
  let nine_nine_nine_e_999 = @decimal.Decimal::from_string(
    "9.99E+999",
    precision=32,
  ).unwrap()
  let neg_thousand = @decimal.Decimal::from_string("-1000", precision=32).unwrap()
  let neg_nine_nine_nine = @decimal.Decimal::from_string("-999", precision=32).unwrap()
  assert_true(thousand.compare(nine_nine_nine) > 0)
  assert_true(nine_nine_nine.compare(thousand) < 0)
  assert_true(one_e_1000.compare(nine_nine_nine_e_999) > 0)
  assert_true(nine_nine_nine_e_999.compare(one_e_1000) < 0)
  assert_true(neg_thousand.compare(neg_nine_nine_nine) < 0)
  assert_true(neg_nine_nine_nine.compare(neg_thousand) > 0)
}

///|
test "decimal gda compare operations return decimal result and flags" {
  let ctx = @decimal.DecimalContext::new(precision=3)
  let one = @decimal.Decimal::one(precision=8)
  let one_point_zero = @decimal.Decimal::from_string("1.0", precision=8).unwrap()
  let two = @decimal.Decimal::from_int(2, precision=8)
  let quiet = @decimal.Decimal::quiet_nan(payload=2N, precision=8)
  let signaling = @decimal.Decimal::signaling_nan(payload=7N, precision=8)
  let (equal, equal_flags) = one.compare_ctx(one_point_zero, ctx)
  let (less, less_flags) = one.compare_signal_ctx(two, ctx)
  let (quiet_compare, quiet_compare_flags) = quiet.compare_ctx(one, ctx)
  let (quiet_signal, quiet_signal_flags) = quiet.compare_signal_ctx(one, ctx)
  let (snan_compare, snan_compare_flags) = signaling.compare_ctx(one, ctx)
  let subset_ctx = @decimal.DecimalContext::new(precision=3, extended=false)
  let oversized = @decimal.Decimal::from_int(12345, precision=8)
  let (subset_signal, subset_signal_flags) = oversized.compare_signal_ctx(
    one, subset_ctx,
  )
  assert_eq(equal.to_string(), "0")
  assert_false(equal_flags.invalid_operation)
  assert_eq(less.to_string(), "-1")
  assert_false(less_flags.invalid_operation)
  assert_eq(quiet_compare.to_string(), "nan2")
  assert_false(quiet_compare_flags.invalid_operation)
  assert_eq(quiet_signal.to_string(), "nan2")
  assert_true(quiet_signal_flags.invalid_operation)
  assert_eq(snan_compare.to_string(), "nan7")
  assert_true(snan_compare_flags.invalid_operation)
  assert_eq(subset_signal.to_string(), "1")
  assert_true(subset_signal_flags.rounded)
  assert_true(subset_signal_flags.inexact)
  assert_true(subset_signal_flags.lost_digits)
}

///|
test "decimal minmax preserves preferred nan diagnostics" {
  let ctx = @decimal.DecimalContext::new(precision=4)
  let finite = @decimal.Decimal::from_int(2, precision=8)
  let left_qnan = @decimal.Decimal::quiet_nan(payload=11N, precision=8)
  let right_qnan = @decimal.Decimal::quiet_nan(
    payload=54N,
    negative=true,
    precision=8,
  )
  let left_snan = @decimal.Decimal::signaling_nan(payload=7N, precision=8)
  let right_snan = @decimal.Decimal::signaling_nan(
    payload=93N,
    negative=true,
    precision=8,
  )
  let (max_snan, max_snan_flags) = left_snan.max_ctx(finite, ctx)
  let (min_two_nan, min_two_nan_flags) = left_qnan.min_ctx(right_qnan, ctx)
  let (max_qnan_snan, max_qnan_snan_flags) = left_qnan.max_ctx(right_snan, ctx)
  assert_eq(max_snan.to_string(), "nan7")
  assert_eq(max_snan.nan_payload(), 7N)
  assert_true(max_snan_flags.invalid_operation)
  assert_eq(min_two_nan.to_string(), "nan11")
  assert_eq(min_two_nan.nan_payload(), 11N)
  assert_false(min_two_nan_flags.invalid_operation)
  assert_eq(max_qnan_snan.to_string(), "-nan93")
  assert_true(max_qnan_snan.is_negative())
  assert_eq(max_qnan_snan.nan_payload(), 93N)
  assert_true(max_qnan_snan_flags.invalid_operation)
}

///|
test "plain decimal minmax follows IEEE operand-order nan propagation" {
  let finite = @decimal.Decimal::from_int(9, precision=8)
  let qnan_left = @decimal.Decimal::quiet_nan(
    payload=1N,
    negative=true,
    precision=8,
  )
  let qnan_right = @decimal.Decimal::quiet_nan(payload=11N, precision=8)
  let snan = @decimal.Decimal::signaling_nan(payload=93N, precision=8)
  assert_eq(qnan_left.max(qnan_right).to_string(), "-nan1")
  assert_eq(qnan_left.max(qnan_right).nan_payload(), 1N)
  assert_eq(qnan_right.min(qnan_left).to_string(), "nan11")
  assert_eq(qnan_right.min(qnan_left).nan_payload(), 11N)
  assert_eq(qnan_right.max(finite).to_string(), "9")
  assert_eq(finite.min(qnan_left).to_string(), "9")
  assert_eq(qnan_right.max(snan).to_string(), "nan11")
  assert_eq(qnan_right.max(snan).nan_payload(), 11N)
  assert_eq(finite.min(snan).to_string(), "nan93")
  assert_eq(finite.min(snan).nan_payload(), 93N)
}

///|
test "decimal logical operations require logical operands" {
  let ctx = @decimal.DecimalContext::new(precision=3)
  let lhs = @decimal.Decimal::from_string("1010", precision=8).unwrap()
  let rhs = @decimal.Decimal::from_string("1100", precision=8).unwrap()
  let zero = @decimal.Decimal::zero(precision=8)
  let bad_digit = @decimal.Decimal::from_string("102", precision=8).unwrap()
  let bad_sign = @decimal.Decimal::from_string("-101", precision=8).unwrap()
  let bad_exponent = @decimal.Decimal::from_string("10.0", precision=8).unwrap()
  let (and_value, and_flags) = lhs.logical_and(rhs, ctx)
  let (or_value, or_flags) = lhs.logical_or(rhs, ctx)
  let (xor_value, xor_flags) = lhs.logical_xor(rhs, ctx)
  let (invert_value, invert_flags) = zero.logical_invert(ctx)
  let (bad_digit_value, bad_digit_flags) = bad_digit.logical_and(rhs, ctx)
  let (bad_sign_value, bad_sign_flags) = bad_sign.logical_or(rhs, ctx)
  let (bad_exponent_value, bad_exponent_flags) = bad_exponent.logical_xor(
    rhs, ctx,
  )
  assert_eq(and_value.to_string(), "0")
  assert_false(and_flags.invalid_operation)
  assert_eq(or_value.to_string(), "110")
  assert_false(or_flags.invalid_operation)
  assert_eq(xor_value.to_string(), "110")
  assert_false(xor_flags.invalid_operation)
  assert_eq(invert_value.to_string(), "111")
  assert_false(invert_flags.invalid_operation)
  assert_eq(bad_digit_value.to_string(), "nan")
  assert_true(bad_digit_flags.invalid_operation)
  assert_eq(bad_sign_value.to_string(), "nan")
  assert_true(bad_sign_flags.invalid_operation)
  assert_eq(bad_exponent_value.to_string(), "nan")
  assert_true(bad_exponent_flags.invalid_operation)
}

///|
test "decimal logical operations use context precision width" {
  let ctx = @decimal.DecimalContext::new(precision=9)
  let lhs = @decimal.Decimal::from_string("111111111111", precision=16).unwrap()
  let rhs = @decimal.Decimal::from_string("1111111111", precision=16).unwrap()
  let (and_value, and_flags) = lhs.logical_and(rhs, ctx)
  assert_eq(and_value.to_string(), "111111111")
  assert_false(and_flags.rounded)
  assert_false(and_flags.inexact)
}

///|
test "decimal quantize preserves requested quantum exponent" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let value = @decimal.Decimal::from_string("1.2", precision=8).unwrap()
  let quantum = @decimal.Decimal::from_string("0.01", precision=8).unwrap()
  let (fixed, flags) = value.quantize(quantum, ctx)
  assert_eq(fixed.to_string(), "1.20")
  assert_eq(fixed.exponent10(), -2)
  assert_true(fixed.same_quantum(quantum))
  assert_false(flags.rounded)
  assert_false(flags.inexact)
}

///|
test "decimal quantize distinguishes rounded from inexact" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let quantum = @decimal.Decimal::from_string("0.01", precision=8).unwrap()
  let exact = @decimal.Decimal::from_string("1.230", precision=8).unwrap()
  let inexact = @decimal.Decimal::from_string("1.235", precision=8).unwrap()
  let (exact_fixed, exact_flags) = exact.quantize(quantum, ctx)
  let (inexact_fixed, inexact_flags) = inexact.quantize(quantum, ctx)
  assert_eq(exact_fixed.to_string(), "1.23")
  assert_true(exact_flags.rounded)
  assert_false(exact_flags.inexact)
  assert_eq(inexact_fixed.to_string(), "1.24")
  assert_true(inexact_flags.rounded)
  assert_true(inexact_flags.inexact)
}

///|
test "decimal quantize rejects coefficients beyond context precision" {
  let ctx = @decimal.DecimalContext::new(precision=3)
  let value = @decimal.Decimal::from_string("1234", precision=8).unwrap()
  let quantum = @decimal.Decimal::one(precision=8)
  let (result, flags) = value.quantize(quantum, ctx)
  assert_true(result.classify() == @lf_arith.FpClass::NaN)
  assert_true(flags.invalid_operation)
  assert_false(flags.rounded)
  assert_false(flags.inexact)
}

///|
test "decimal quantize invalid precision overflow suppresses rounded flags" {
  let ctx = @decimal.DecimalContext::new(
    precision=3,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
  )
  let tiny = @decimal.Decimal::from_string("9.999E-15", precision=16).unwrap()
  let fung = @decimal.Decimal::from_string("0.9998", precision=16).unwrap()
  let quantum_tiny = @decimal.Decimal::from_string("1e-17", precision=16).unwrap()
  let mills = @decimal.Decimal::from_string("0.001", precision=16).unwrap()
  let (tiny_result, tiny_flags) = tiny.quantize(quantum_tiny, ctx)
  let (fung_result, fung_flags) = fung.quantize(mills, ctx)
  assert_true(tiny_result.classify() == @lf_arith.FpClass::NaN)
  assert_true(fung_result.classify() == @lf_arith.FpClass::NaN)
  assert_true(tiny_flags.invalid_operation)
  assert_true(fung_flags.invalid_operation)
  assert_false(tiny_flags.rounded)
  assert_false(tiny_flags.inexact)
  assert_false(fung_flags.rounded)
  assert_false(fung_flags.inexact)
}

///|
test "decimal quantize propagates special operands with quieting semantics" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let finite = @decimal.Decimal::one(precision=16)
  let qnan = @decimal.Decimal::quiet_nan(
    payload=2345N,
    negative=true,
    precision=16,
  )
  let snan = @decimal.Decimal::signaling_nan(
    payload=67890N,
    negative=true,
    precision=16,
  )
  let pos_inf = @decimal.Decimal::inf(@def.Sign::Positive, precision=16)
  let neg_inf = @decimal.Decimal::inf(@def.Sign::Negative, precision=16)
  let (qnan_result, qnan_flags) = finite.quantize(qnan, ctx)
  let (snan_result, snan_flags) = finite.quantize(snan, ctx)
  let (inf_result, inf_flags) = pos_inf.quantize(pos_inf, ctx)
  let (neg_quantum_inf, neg_quantum_inf_flags) = pos_inf.quantize(neg_inf, ctx)
  assert_true(qnan_result.is_qnan())
  assert_true(qnan_result.is_negative())
  assert_eq(qnan_result.nan_payload(), 2345N)
  assert_false(qnan_flags.invalid_operation)
  assert_true(snan_result.is_qnan())
  assert_true(snan_result.is_negative())
  assert_eq(snan_result.nan_payload(), 67890N)
  assert_true(snan_flags.invalid_operation)
  assert_true(inf_result.is_infinite())
  assert_false(inf_result.is_negative())
  assert_false(inf_flags.has_error())
  assert_true(neg_quantum_inf.is_infinite())
  assert_false(neg_quantum_inf.is_negative())
  assert_false(neg_quantum_inf_flags.has_error())
}

///|
test "decimal subset quantize canonicalizes zero results to positive zero" {
  let subset_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
    extended=false,
  )
  let neg_zero = @decimal.Decimal::from_string("-0", precision=16).unwrap()
  let neg_tenth = @decimal.Decimal::from_string("-0.1", precision=16).unwrap()
  let units = @decimal.Decimal::one(precision=16)
  let hundreds = @decimal.Decimal::from_string("1E+2", precision=16).unwrap()
  let (zero_units, zero_units_flags) = neg_zero.quantize(units, subset_ctx)
  let (rounded_hundreds, rounded_hundreds_flags) = neg_tenth.quantize(
    hundreds, subset_ctx,
  )
  assert_eq(zero_units.to_string(), "0")
  assert_false(zero_units.is_negative_zero())
  assert_false(zero_units_flags.has_error())
  assert_true(rounded_hundreds.is_zero())
  assert_eq(rounded_hundreds.exponent10(), 2)
  assert_false(rounded_hundreds.is_negative_zero())
  assert_true(rounded_hundreds_flags.rounded)
  assert_true(rounded_hundreds_flags.inexact)
}

///|
test "decimal rescale interprets rhs as target exponent count" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
  )
  let tenth = @decimal.Decimal::from_string("0.1", precision=16).unwrap()
  let two_point_seventeen = @decimal.Decimal::from_string("2.17", precision=16).unwrap()
  let plus_two = @decimal.Decimal::from_int(2, precision=16)
  let minus_two = @decimal.Decimal::from_int(-2, precision=16)
  let plus_two_exact = @decimal.Decimal::from_string("2.00000000", precision=16).unwrap()
  let plus_two_trailing_zero = @decimal.Decimal::from_string(
    "2.0",
    precision=16,
  ).unwrap()
  let plus_two_scientific = @decimal.Decimal::from_string(
    "0.02E+2",
    precision=16,
  ).unwrap()
  let (upscaled, upscaled_flags) = tenth.rescale(plus_two, ctx)
  let (fixed, fixed_flags) = two_point_seventeen.rescale(minus_two, ctx)
  let (rounded, rounded_flags) = two_point_seventeen.rescale(
    @decimal.Decimal::from_int(-1, precision=16),
    ctx,
  )
  let (integer_rhs, integer_rhs_flags) = @decimal.Decimal::from_int(
    222,
    precision=16,
  ).rescale(plus_two_exact, ctx)
  let (trailing_zero_rhs, trailing_zero_rhs_flags) = @decimal.Decimal::from_int(
    222,
    precision=16,
  ).rescale(plus_two_trailing_zero, ctx)
  let (scientific_rhs, scientific_rhs_flags) = @decimal.Decimal::from_int(
    222,
    precision=16,
  ).rescale(plus_two_scientific, ctx)
  assert_eq(
    upscaled.compare_total(
      @decimal.Decimal::from_string("0E+2", precision=16).unwrap(),
    ),
    0,
  )
  assert_true(upscaled_flags.rounded)
  assert_true(upscaled_flags.inexact)
  assert_eq(
    fixed.compare_total(
      @decimal.Decimal::from_string("2.17", precision=16).unwrap(),
    ),
    0,
  )
  assert_false(fixed_flags.rounded)
  assert_false(fixed_flags.inexact)
  assert_eq(
    rounded.compare_total(
      @decimal.Decimal::from_string("2.2", precision=16).unwrap(),
    ),
    0,
  )
  assert_true(rounded_flags.rounded)
  assert_true(rounded_flags.inexact)
  assert_eq(
    integer_rhs.compare_total(
      @decimal.Decimal::from_string("2E+2", precision=16).unwrap(),
    ),
    0,
  )
  assert_true(integer_rhs_flags.rounded)
  assert_true(integer_rhs_flags.inexact)
  assert_eq(
    trailing_zero_rhs.compare_total(
      @decimal.Decimal::from_string("2E+2", precision=16).unwrap(),
    ),
    0,
  )
  assert_true(trailing_zero_rhs_flags.rounded)
  assert_true(trailing_zero_rhs_flags.inexact)
  assert_eq(
    scientific_rhs.compare_total(
      @decimal.Decimal::from_string("2E+2", precision=16).unwrap(),
    ),
    0,
  )
  assert_true(scientific_rhs_flags.rounded)
  assert_true(scientific_rhs_flags.inexact)
}

///|
test "decimal rescale accepts exact integer rhs across exponent encodings" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
  )
  let value = @decimal.Decimal::from_string("2.17", precision=16).unwrap()
  let positive_targets = [
    @decimal.Decimal::from_int(2, precision=16),
    @decimal.Decimal::from_string("2.0", precision=16).unwrap(),
    @decimal.Decimal::from_string("0.02E+2", precision=16).unwrap(),
  ]
  let negative_targets = [
    @decimal.Decimal::from_int(-2, precision=16),
    @decimal.Decimal::from_string("-2.0", precision=16).unwrap(),
    @decimal.Decimal::from_string("-0.02E+2", precision=16).unwrap(),
  ]
  for target in positive_targets {
    let (result, flags) = value.rescale(target, ctx)
    assert_eq(
      result.compare_total(
        @decimal.Decimal::from_string("0E+2", precision=16).unwrap(),
      ),
      0,
    )
    assert_true(flags.rounded)
    assert_true(flags.inexact)
  }
  for target in negative_targets {
    let (result, flags) = value.rescale(target, ctx)
    assert_eq(
      result.compare_total(
        @decimal.Decimal::from_string("2.17", precision=16).unwrap(),
      ),
      0,
    )
    assert_false(flags.rounded)
    assert_false(flags.inexact)
  }
}

///|
test "decimal rescale validates rhs integrality and infinity rules" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
  )
  let finite = @decimal.Decimal::from_string("1.234", precision=16).unwrap()
  let inf = @decimal.Decimal::inf(@def.Sign::Positive, precision=16)
  let neg_inf = @decimal.Decimal::inf(@def.Sign::Negative, precision=16)
  let non_integer_rhs = @decimal.Decimal::from_string(
    "2.0000000001",
    precision=16,
  ).unwrap()
  let huge_rhs = @decimal.Decimal::from_int(1000, precision=16)
  let (bad_fraction, bad_fraction_flags) = finite.rescale(non_integer_rhs, ctx)
  let (bad_range, bad_range_flags) = finite.rescale(huge_rhs, ctx)
  let (finite_over_inf, finite_over_inf_flags) = finite.rescale(inf, ctx)
  let (pos_inf_rescaled, pos_inf_flags) = inf.rescale(neg_inf, ctx)
  let (neg_inf_rescaled, neg_inf_flags) = neg_inf.rescale(inf, ctx)
  assert_true(bad_fraction.is_qnan())
  assert_true(bad_fraction_flags.invalid_operation)
  assert_true(bad_range.is_qnan())
  assert_true(bad_range_flags.invalid_operation)
  assert_true(finite_over_inf.is_qnan())
  assert_true(finite_over_inf_flags.invalid_operation)
  assert_true(pos_inf_rescaled.is_infinite())
  assert_false(pos_inf_rescaled.is_negative())
  assert_false(pos_inf_flags.has_error())
  assert_true(neg_inf_rescaled.is_infinite())
  assert_true(neg_inf_rescaled.is_negative())
  assert_false(neg_inf_flags.has_error())
}

///|
test "decimal quantize and rescale honor etiny fit window" {
  let ctx = @decimal.DecimalContext::new(
    precision=7,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
  )
  let one_e_neg_999 = @decimal.Decimal::from_string("1E-999", precision=16).unwrap()
  let one_e_neg_998 = @decimal.Decimal::from_string("1E-998", precision=16).unwrap()
  let one_e_neg_1000 = @decimal.Decimal::from_string("1E-1000", precision=16).unwrap()
  let repeating_subnormal = @decimal.Decimal::from_string(
    "1.666666E-1000",
    precision=16,
  ).unwrap()
  let quantum_e_neg_1005 = @decimal.Decimal::from_string(
    "1E-1005",
    precision=16,
  ).unwrap()
  let quantum_e_neg_1006 = @decimal.Decimal::from_string(
    "1E-1006",
    precision=16,
  ).unwrap()
  let (quantized_fit, quantized_fit_flags) = one_e_neg_999.quantize(
    quantum_e_neg_1005, ctx,
  )
  let (quantized_subnormal, quantized_subnormal_flags) = one_e_neg_1000.quantize(
    quantum_e_neg_1005, ctx,
  )
  let (quantized_too_wide, quantized_too_wide_flags) = one_e_neg_998.quantize(
    quantum_e_neg_1005, ctx,
  )
  let (quantized_below_etiny, quantized_below_etiny_flags) = one_e_neg_999.quantize(
    quantum_e_neg_1006, ctx,
  )
  let (quantized_rounded_subnormal, quantized_rounded_subnormal_flags) = repeating_subnormal.quantize(
    quantum_e_neg_1005, ctx,
  )
  let (rescaled_fit, rescaled_fit_flags) = one_e_neg_999.rescale(
    @decimal.Decimal::from_int(-1005, precision=16),
    ctx,
  )
  assert_eq(
    quantized_fit.compare_total(
      @decimal.Decimal::from_string("1.000000E-999", precision=16).unwrap(),
    ),
    0,
  )
  assert_false(quantized_fit_flags.has_error())
  assert_eq(
    quantized_subnormal.compare_total(
      @decimal.Decimal::from_string("1.00000E-1000", precision=16).unwrap(),
    ),
    0,
  )
  assert_true(quantized_subnormal_flags.subnormal)
  assert_false(quantized_subnormal_flags.underflow)
  assert_eq(
    quantized_rounded_subnormal.compare_total(
      @decimal.Decimal::from_string("1.66667E-1000", precision=16).unwrap(),
    ),
    0,
  )
  assert_true(quantized_rounded_subnormal_flags.subnormal)
  assert_true(quantized_rounded_subnormal_flags.rounded)
  assert_true(quantized_rounded_subnormal_flags.inexact)
  assert_false(quantized_rounded_subnormal_flags.underflow)
  assert_true(quantized_too_wide.is_qnan())
  assert_true(quantized_too_wide_flags.invalid_operation)
  assert_true(quantized_below_etiny.is_qnan())
  assert_true(quantized_below_etiny_flags.invalid_operation)
  assert_eq(
    rescaled_fit.compare_total(
      @decimal.Decimal::from_string("1.000000E-999", precision=16).unwrap(),
    ),
    0,
  )
  assert_false(rescaled_fit_flags.has_error())
}

///|
test "decimal same_quantum handles finite and special values" {
  let cents = @decimal.Decimal::from_string("1.20", precision=8).unwrap()
  let quantum = @decimal.Decimal::from_string("0.01", precision=8).unwrap()
  let units = @decimal.Decimal::one(precision=8)
  assert_true(cents.same_quantum(quantum))
  assert_false(cents.same_quantum(units))
  assert_true(
    @decimal.Decimal::inf(@def.Sign::Positive).same_quantum(
      @decimal.Decimal::inf(@def.Sign::Negative),
    ),
  )
  assert_true(
    @decimal.Decimal::nan().same_quantum(
      @decimal.Decimal::signaling_nan(payload=1N),
    ),
  )
}

///|
test "decimal same_quantum matches official zero and special cohorts" {
  let neg_zero_exp = @decimal.Decimal::from_string("-0E-17", precision=16).unwrap()
  let pos_zero_scaled = @decimal.Decimal::from_string("0.0E-16", precision=16).unwrap()
  let pos_zero_plain = @decimal.Decimal::zero(precision=16)
  let seven = @decimal.Decimal::from_string("7", precision=16).unwrap()
  let seven_scaled = @decimal.Decimal::from_string("7E+3", precision=16).unwrap()
  let inf = @decimal.Decimal::inf(@def.Sign::Positive, precision=16)
  let snan = @decimal.Decimal::signaling_nan(payload=3N, precision=16)
  assert_true(neg_zero_exp.same_quantum(pos_zero_scaled))
  assert_false(neg_zero_exp.same_quantum(pos_zero_plain))
  assert_true(
    seven.same_quantum(
      @decimal.Decimal::from_string("-0", precision=16).unwrap(),
    ),
  )
  assert_false(seven.same_quantum(seven_scaled))
  assert_false(seven.same_quantum(inf))
  assert_false(seven.same_quantum(snan))
  assert_true(
    @decimal.Decimal::signaling_nan(payload=3N, precision=16).same_quantum(
      @decimal.Decimal::quiet_nan(payload=4N, precision=16),
    ),
  )
}

///|
test "decimal same_quantum covers official exponent matrix representatives" {
  let ten = @decimal.Decimal::from_string("10", precision=16).unwrap()
  let ten_e1 = @decimal.Decimal::from_string("1E+1", precision=16).unwrap()
  let hundred = @decimal.Decimal::from_string("100", precision=16).unwrap()
  let neg_seven = @decimal.Decimal::from_string("-7", precision=16).unwrap()
  let neg_seven_e3 = @decimal.Decimal::from_string("-7E+3", precision=16).unwrap()
  let neg_seven_em3 = @decimal.Decimal::from_string("-7E-3", precision=16).unwrap()
  let zero = @decimal.Decimal::zero(precision=16)
  let pos_seven = @decimal.Decimal::from_string("7", precision=16).unwrap()
  let pos_seven_e3 = @decimal.Decimal::from_string("7E+3", precision=16).unwrap()
  let pos_seven_em3 = @decimal.Decimal::from_string("7E-3", precision=16).unwrap()
  assert_false(ten.same_quantum(ten_e1))
  assert_false(hundred.same_quantum(ten_e1))
  assert_true(neg_seven_e3.same_quantum(pos_seven_e3))
  assert_false(neg_seven_e3.same_quantum(zero))
  assert_true(neg_seven.same_quantum(zero))
  assert_false(neg_seven.same_quantum(pos_seven_em3))
  assert_true(neg_seven_em3.same_quantum(pos_seven_em3))
  assert_false(pos_seven_e3.same_quantum(pos_seven))
}

///|
test "decimal integral rounding distinguishes exact and value flags" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let value = @decimal.Decimal::from_string("2.5", precision=8).unwrap()
  let (exact, exact_flags) = value.to_integral_exact(ctx)
  let (quiet, quiet_flags) = value.to_integral_value(ctx)
  assert_eq(exact.to_string(), "2")
  assert_eq(quiet.to_string(), "2")
  assert_true(exact_flags.rounded)
  assert_true(exact_flags.inexact)
  assert_false(quiet_flags.rounded)
  assert_false(quiet_flags.inexact)
}

///|
test "decimal to_integral_value preserves integral cohorts and special payloads" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let huge = @decimal.Decimal::from_string("10E+30", precision=16).unwrap()
  let pos_zero = @decimal.Decimal::from_string("0E+5", precision=16).unwrap()
  let neg_zero = @decimal.Decimal::from_string("-0E+5", precision=16).unwrap()
  let qnan = @decimal.Decimal::quiet_nan(payload=808N, precision=16)
  let snan = @decimal.Decimal::signaling_nan(payload=80N, precision=16)
  let (huge_integral, huge_flags) = huge.to_integral_value(ctx)
  let (pos_zero_integral, pos_zero_flags) = pos_zero.to_integral_value(ctx)
  let (neg_zero_integral, neg_zero_flags) = neg_zero.to_integral_value(ctx)
  let (qnan_integral, qnan_flags) = qnan.to_integral_value(ctx)
  let (snan_integral, snan_flags) = snan.to_integral_value(ctx)
  assert_eq(
    huge_integral.compare_total(
      @decimal.Decimal::from_string("1.0E+31", precision=16).unwrap(),
    ),
    0,
  )
  assert_eq(
    pos_zero_integral.compare_total(
      @decimal.Decimal::from_string("0E+5", precision=16).unwrap(),
    ),
    0,
  )
  assert_eq(
    neg_zero_integral.compare_total(
      @decimal.Decimal::from_string("-0E+5", precision=16).unwrap(),
    ),
    0,
  )
  assert_true(qnan_integral.is_qnan())
  assert_eq(qnan_integral.nan_payload(), 808N)
  assert_true(snan_integral.is_qnan())
  assert_eq(snan_integral.nan_payload(), 80N)
  assert_false(huge_flags.has_error())
  assert_false(pos_zero_flags.has_error())
  assert_false(neg_zero_flags.has_error())
  assert_false(qnan_flags.invalid_operation)
  assert_true(snan_flags.invalid_operation)
}

///|
test "decimal to_integral_exact preserves integral cohorts and special payloads" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let huge = @decimal.Decimal::from_string("10E+30", precision=16).unwrap()
  let pos_zero = @decimal.Decimal::from_string("0E+5", precision=16).unwrap()
  let neg_zero = @decimal.Decimal::from_string("-0E+5", precision=16).unwrap()
  let qnan = @decimal.Decimal::quiet_nan(payload=808N, precision=16)
  let snan = @decimal.Decimal::signaling_nan(payload=80N, precision=16)
  let inf = @decimal.Decimal::inf(@def.Sign::Positive, precision=16)
  let (huge_integral, huge_flags) = huge.to_integral_exact(ctx)
  let (pos_zero_integral, pos_zero_flags) = pos_zero.to_integral_exact(ctx)
  let (neg_zero_integral, neg_zero_flags) = neg_zero.to_integral_exact(ctx)
  let (qnan_integral, qnan_flags) = qnan.to_integral_exact(ctx)
  let (snan_integral, snan_flags) = snan.to_integral_exact(ctx)
  let (inf_integral, inf_flags) = inf.to_integral_exact(ctx)
  assert_eq(
    huge_integral.compare_total(
      @decimal.Decimal::from_string("1.0E+31", precision=16).unwrap(),
    ),
    0,
  )
  assert_eq(
    pos_zero_integral.compare_total(
      @decimal.Decimal::from_string("0E+5", precision=16).unwrap(),
    ),
    0,
  )
  assert_eq(
    neg_zero_integral.compare_total(
      @decimal.Decimal::from_string("-0E+5", precision=16).unwrap(),
    ),
    0,
  )
  assert_true(qnan_integral.is_qnan())
  assert_eq(qnan_integral.nan_payload(), 808N)
  assert_true(snan_integral.is_qnan())
  assert_eq(snan_integral.nan_payload(), 80N)
  assert_true(inf_integral.is_infinite())
  assert_false(inf_integral.is_negative())
  assert_false(huge_flags.has_error())
  assert_false(pos_zero_flags.has_error())
  assert_false(neg_zero_flags.has_error())
  assert_false(qnan_flags.invalid_operation)
  assert_true(snan_flags.invalid_operation)
  assert_false(inf_flags.has_error())
}

///|
test "decimal subset to_integral canonicalizes negative zero results" {
  let subset_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
    extended=false,
  )
  let neg_zero = @decimal.Decimal::from_string("-0E+5", precision=16).unwrap()
  let neg_tiny = @decimal.Decimal::from_string("-0.1", precision=16).unwrap()
  let (exact_zero, exact_zero_flags) = neg_zero.to_integral_exact(subset_ctx)
  let (value_zero, value_zero_flags) = neg_zero.to_integral_value(subset_ctx)
  let (exact_tiny, exact_tiny_flags) = neg_tiny.to_integral_exact(subset_ctx)
  let (value_tiny, value_tiny_flags) = neg_tiny.to_integral_value(subset_ctx)
  assert_eq(exact_zero.to_string(), "0")
  assert_false(exact_zero.is_negative_zero())
  assert_false(exact_zero_flags.has_error())
  assert_eq(value_zero.to_string(), "0")
  assert_false(value_zero.is_negative_zero())
  assert_false(value_zero_flags.has_error())
  assert_eq(exact_tiny.to_string(), "0")
  assert_false(exact_tiny.is_negative_zero())
  assert_true(exact_tiny_flags.rounded)
  assert_true(exact_tiny_flags.inexact)
  assert_eq(value_tiny.to_string(), "0")
  assert_false(value_tiny.is_negative_zero())
  assert_false(value_tiny_flags.rounded)
  assert_false(value_tiny_flags.inexact)
}

///|
test "decimal reduce normalizes cohort after context rounding" {
  let exact_ctx = @decimal.DecimalContext::new(precision=8)
  let rounded_ctx = @decimal.DecimalContext::new(precision=3)
  let exact = @decimal.Decimal::from_string("12.3400", precision=8).unwrap()
  let rounded = @decimal.Decimal::from_string("1.234", precision=8).unwrap()
  let neg_zero = @decimal.Decimal::from_string("-0.00", precision=8).unwrap()
  let snan = @decimal.Decimal::signaling_nan(payload=7N, precision=8)
  let (reduced, exact_flags) = exact.reduce_ctx(exact_ctx)
  let (rounded_reduced, rounded_flags) = rounded.reduce_ctx(rounded_ctx)
  let (zero_reduced, zero_flags) = neg_zero.normalize_ctx(exact_ctx)
  let (nan_reduced, nan_flags) = snan.reduce_ctx(exact_ctx)
  assert_eq(reduced.to_string(), "12.34")
  assert_false(exact_flags.rounded)
  assert_false(exact_flags.inexact)
  assert_eq(rounded_reduced.to_string(), "1.23")
  assert_true(rounded_flags.rounded)
  assert_true(rounded_flags.inexact)
  assert_eq(zero_reduced.to_string(), "-0")
  assert_true(zero_reduced.is_negative_zero())
  assert_false(zero_flags.invalid_operation)
  assert_eq(nan_reduced.to_string(), "nan7")
  assert_true(nan_flags.invalid_operation)
}

///|
test "decimal reduce preserves subnormal and special official cohorts" {
  let dd_ctx = @decimal.DecimalContext::new(precision=16, e_min=-383, e_max=384)
  let subnormal = @decimal.Decimal::from_string("2.000E-395", precision=32).unwrap()
  let neg_subnormal = @decimal.Decimal::from_string("-1E-398", precision=32).unwrap()
  let inf = @decimal.Decimal::inf(@def.Sign::Positive, precision=16)
  let neg_qnan = @decimal.Decimal::quiet_nan(
    payload=101N,
    negative=true,
    precision=16,
  )
  let neg_snan = @decimal.Decimal::signaling_nan(
    payload=10N,
    negative=true,
    precision=16,
  )
  let (reduced_subnormal, subnormal_flags) = subnormal.reduce_ctx(dd_ctx)
  let (reduced_neg_subnormal, neg_subnormal_flags) = neg_subnormal.reduce_ctx(
    dd_ctx,
  )
  let (reduced_inf, inf_flags) = inf.reduce_ctx(dd_ctx)
  let (reduced_neg_qnan, neg_qnan_flags) = neg_qnan.reduce_ctx(dd_ctx)
  let (reduced_neg_snan, neg_snan_flags) = neg_snan.reduce_ctx(dd_ctx)
  assert_eq(
    reduced_subnormal.compare_total(
      @decimal.Decimal::from_string("2E-395", precision=32).unwrap(),
    ),
    0,
  )
  assert_true(subnormal_flags.subnormal)
  assert_false(subnormal_flags.invalid_operation)
  assert_eq(
    reduced_neg_subnormal.compare_total(
      @decimal.Decimal::from_string("-1E-398", precision=32).unwrap(),
    ),
    0,
  )
  assert_true(neg_subnormal_flags.subnormal)
  assert_true(reduced_inf.is_infinite())
  assert_false(reduced_inf.is_negative())
  assert_false(inf_flags.has_error())
  assert_true(reduced_neg_qnan.is_qnan())
  assert_true(reduced_neg_qnan.is_negative())
  assert_eq(reduced_neg_qnan.nan_payload(), 101N)
  assert_false(neg_qnan_flags.invalid_operation)
  assert_true(reduced_neg_snan.is_qnan())
  assert_true(reduced_neg_snan.is_negative())
  assert_eq(reduced_neg_snan.nan_payload(), 10N)
  assert_true(neg_snan_flags.invalid_operation)
}

///|
test "decimal reduce preserves official negative zero representatives" {
  let dd_ctx = @decimal.DecimalContext::new(precision=16, e_min=-383, e_max=384)
  let cases = ["-0", "-0.00", "-00.0", "-00.00", "-00", "-0E+5", "-0E+1"]
  for text in cases {
    let value = @decimal.Decimal::from_string(text, precision=32).unwrap()
    let (reduced, flags) = value.reduce_ctx(dd_ctx)
    assert_eq(reduced.to_string(), "-0")
    assert_true(reduced.is_negative_zero())
    assert_false(flags.has_error())
  }
}

///|
test "decimal subset reduce canonicalizes negative zero to plain zero" {
  let subset_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
    extended=false,
  )
  let neg_zero = @decimal.Decimal::from_string("-0E+5", precision=16).unwrap()
  let (reduced, flags) = neg_zero.reduce_ctx(subset_ctx)
  assert_eq(reduced.to_string(), "0")
  assert_false(reduced.is_negative_zero())
  assert_false(flags.has_error())
}

///|
test "decimal copy and trim preserve gda representation semantics" {
  let finite = @decimal.Decimal::from_string("7.50", precision=8).unwrap()
  let neg_zero = @decimal.Decimal::from_string("-0.00", precision=8).unwrap()
  let snan = @decimal.Decimal::signaling_nan(
    payload=777N,
    negative=true,
    precision=8,
  )
  let copied_finite = finite.copy()
  let copied_snan = snan.copy()
  let trimmed_finite = finite.trim()
  let trimmed_zero = neg_zero.trim()
  let trimmed_snan = snan.trim()
  assert_eq(copied_finite.to_string(), "7.50")
  assert_eq(copied_finite.exponent10(), finite.exponent10())
  assert_true(copied_snan.is_signaling_nan())
  assert_true(copied_snan.is_negative())
  assert_eq(copied_snan.nan_payload(), 777N)
  assert_eq(copied_snan.to_string(), "-snan777")
  assert_eq(trimmed_finite.to_string(), "7.5")
  assert_eq(trimmed_zero.to_string(), "-0")
  assert_true(trimmed_zero.is_negative_zero())
  assert_true(trimmed_snan.is_signaling_nan())
  assert_true(trimmed_snan.is_negative())
  assert_eq(trimmed_snan.nan_payload(), 777N)
}

///|
test "decimal next plus and minus follow gda adjacent finite lattice" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-383,
    e_max=384,
  )
  let one = @decimal.Decimal::from_string("1", precision=16).unwrap()
  let (next_after_one, next_after_one_flags) = one.next_plus(ctx)
  let (prev_before_one, prev_before_one_flags) = one.next_minus(ctx)
  assert_eq(next_after_one.to_string(), "1.00000001")
  assert_false(next_after_one_flags.has_error())
  assert_eq(prev_before_one.to_string(), "0.999999999")
  assert_false(prev_before_one_flags.has_error())

  let over_precise = @decimal.Decimal::from_string(
    "1.00000011001",
    precision=32,
  ).unwrap()
  let (ceil_neighbor, _) = over_precise.next_plus(ctx)
  let (floor_neighbor, _) = over_precise.next_minus(ctx)
  assert_eq(ceil_neighbor.to_string(), "1.00000012")
  assert_eq(floor_neighbor.to_string(), "1.00000011")

  let neg_one = @decimal.Decimal::from_string("-1", precision=16).unwrap()
  let (neg_toward_zero, _) = neg_one.next_plus(ctx)
  let (neg_away_zero, _) = neg_one.next_minus(ctx)
  assert_eq(neg_toward_zero.to_string(), "-0.999999999")
  assert_eq(neg_away_zero.to_string(), "-1.00000001")
}

///|
test "decimal next plus and minus handle zeros specials and payloads" {
  let ctx = @decimal.DecimalContext::new(precision=3, e_min=-2, e_max=2)
  let (after_zero, after_zero_flags) = @decimal.Decimal::zero().next_plus(ctx)
  let (before_zero, before_zero_flags) = @decimal.Decimal::zero().next_minus(
    ctx,
  )
  assert_eq(after_zero.to_string(), "0.0001")
  assert_eq(after_zero.exponent10(), -4)
  assert_false(after_zero.is_negative())
  assert_false(after_zero_flags.has_error())
  assert_eq(before_zero.to_string(), "-0.0001")
  assert_eq(before_zero.exponent10(), -4)
  assert_true(before_zero.is_negative())
  assert_false(before_zero_flags.has_error())

  let neg_tiny = @decimal.Decimal::from_string("-0.00001", precision=16).unwrap()
  let (neg_zero, _) = neg_tiny.next_plus(ctx)
  assert_eq(neg_zero.to_string(), "-0.0000")
  assert_eq(neg_zero.exponent10(), -4)
  assert_true(neg_zero.is_negative_zero())

  let (below_inf, _) = @decimal.Decimal::inf(@def.Sign::Positive, precision=8).next_minus(
    ctx,
  )
  assert_eq(below_inf.to_string(), "999")
  let (above_neg_inf, _) = @decimal.Decimal::inf(
    @def.Sign::Negative,
    precision=8,
  ).next_plus(ctx)
  assert_eq(above_neg_inf.to_string(), "-999")

  let qnan = @decimal.Decimal::quiet_nan(
    payload=77N,
    negative=true,
    precision=8,
  )
  let snan = @decimal.Decimal::signaling_nan(payload=88N, precision=8)
  let (quiet_result, quiet_flags) = qnan.next_plus(ctx)
  let (signal_result, signal_flags) = snan.next_minus(ctx)
  assert_eq(quiet_result.to_string(), "-nan77")
  assert_false(quiet_flags.invalid_operation)
  assert_eq(signal_result.to_string(), "nan88")
  assert_true(signal_flags.invalid_operation)
}

///|
test "decimal next plus and minus cover official zero and ultra-tiny representatives" {
  let ctx = @decimal.DecimalContext::new(precision=9, e_min=-383, e_max=384)
  let ultra_tiny = @decimal.Decimal::from_string("1E-99999", precision=32).unwrap()
  let neg_ultra_tiny = @decimal.Decimal::from_string("-1E-99999", precision=32).unwrap()
  let zero = @decimal.Decimal::zero(precision=32)
  let neg_zero = @decimal.Decimal::negative_zero(precision=32)
  let zero_huge = @decimal.Decimal::from_string("0E+30000", precision=32).unwrap()
  let neg_zero_huge = @decimal.Decimal::from_string("-0E+30000", precision=32).unwrap()
  let (next_pos_tiny, next_pos_tiny_flags) = ultra_tiny.next_plus(ctx)
  let (next_neg_tiny, next_neg_tiny_flags) = neg_ultra_tiny.next_plus(ctx)
  let (next_pos_zero, next_pos_zero_flags) = zero.next_plus(ctx)
  let (next_neg_zero, next_neg_zero_flags) = neg_zero.next_plus(ctx)
  let (next_pos_zero_huge, next_pos_zero_huge_flags) = zero_huge.next_plus(ctx)
  let (next_neg_zero_huge, next_neg_zero_huge_flags) = neg_zero_huge.next_plus(
    ctx,
  )
  let (prev_pos_tiny, prev_pos_tiny_flags) = ultra_tiny.next_minus(ctx)
  let (prev_neg_tiny, prev_neg_tiny_flags) = neg_ultra_tiny.next_minus(ctx)
  let (prev_pos_zero, prev_pos_zero_flags) = zero.next_minus(ctx)
  let (prev_neg_zero, prev_neg_zero_flags) = neg_zero.next_minus(ctx)
  let (prev_pos_zero_huge, prev_pos_zero_huge_flags) = zero_huge.next_minus(ctx)
  let (prev_neg_zero_huge, prev_neg_zero_huge_flags) = neg_zero_huge.next_minus(
    ctx,
  )
  assert_eq(decimal_coeff_signed(next_pos_tiny), 1N)
  assert_eq(next_pos_tiny.exponent10(), -391)
  assert_false(next_pos_tiny_flags.has_error())
  assert_eq(decimal_coeff_signed(next_neg_tiny), 0N)
  assert_eq(next_neg_tiny.exponent10(), -391)
  assert_true(next_neg_tiny.is_negative_zero())
  assert_false(next_neg_tiny_flags.has_error())
  assert_eq(decimal_coeff_signed(next_pos_zero), 1N)
  assert_eq(next_pos_zero.exponent10(), -391)
  assert_false(next_pos_zero_flags.has_error())
  assert_eq(decimal_coeff_signed(next_neg_zero), 1N)
  assert_eq(next_neg_zero.exponent10(), -391)
  assert_false(next_neg_zero.is_negative_zero())
  assert_false(next_neg_zero_flags.has_error())
  assert_eq(decimal_coeff_signed(next_pos_zero_huge), 1N)
  assert_eq(next_pos_zero_huge.exponent10(), -391)
  assert_false(next_pos_zero_huge_flags.has_error())
  assert_eq(decimal_coeff_signed(next_neg_zero_huge), 1N)
  assert_eq(next_neg_zero_huge.exponent10(), -391)
  assert_false(next_neg_zero_huge.is_negative_zero())
  assert_false(next_neg_zero_huge_flags.has_error())
  assert_eq(decimal_coeff_signed(prev_pos_tiny), 0N)
  assert_eq(prev_pos_tiny.exponent10(), -391)
  assert_false(prev_pos_tiny.is_negative_zero())
  assert_false(prev_pos_tiny_flags.has_error())
  assert_eq(decimal_coeff_signed(prev_neg_tiny), -1N)
  assert_eq(prev_neg_tiny.exponent10(), -391)
  assert_false(prev_neg_tiny_flags.has_error())
  assert_eq(decimal_coeff_signed(prev_pos_zero), -1N)
  assert_eq(prev_pos_zero.exponent10(), -391)
  assert_false(prev_pos_zero_flags.has_error())
  assert_eq(decimal_coeff_signed(prev_neg_zero), -1N)
  assert_eq(prev_neg_zero.exponent10(), -391)
  assert_false(prev_neg_zero_flags.has_error())
  assert_eq(decimal_coeff_signed(prev_pos_zero_huge), -1N)
  assert_eq(prev_pos_zero_huge.exponent10(), -391)
  assert_false(prev_pos_zero_huge_flags.has_error())
  assert_eq(decimal_coeff_signed(prev_neg_zero_huge), -1N)
  assert_eq(prev_neg_zero_huge.exponent10(), -391)
  assert_false(prev_neg_zero_huge_flags.has_error())
}

///|
test "decimal next plus and minus preserve tiny zero cohort representatives" {
  let ctx = @decimal.DecimalContext::new(precision=9, e_min=-999, e_max=999)
  let zero_tiny = @decimal.Decimal::from_string("0E-1007", precision=32).unwrap()
  let neg_zero_tiny = @decimal.Decimal::from_string("-0E-1007", precision=32).unwrap()
  let (next_pos_zero_tiny, next_pos_zero_tiny_flags) = zero_tiny.next_plus(ctx)
  let (next_neg_zero_tiny, next_neg_zero_tiny_flags) = neg_zero_tiny.next_plus(
    ctx,
  )
  let (prev_pos_zero_tiny, prev_pos_zero_tiny_flags) = zero_tiny.next_minus(ctx)
  let (prev_neg_zero_tiny, prev_neg_zero_tiny_flags) = neg_zero_tiny.next_minus(
    ctx,
  )
  assert_eq(decimal_coeff_signed(next_pos_zero_tiny), 1N)
  assert_eq(next_pos_zero_tiny.exponent10(), -1007)
  assert_false(next_pos_zero_tiny_flags.has_error())
  assert_eq(decimal_coeff_signed(next_neg_zero_tiny), 1N)
  assert_eq(next_neg_zero_tiny.exponent10(), -1007)
  assert_false(next_neg_zero_tiny.is_negative_zero())
  assert_false(next_neg_zero_tiny_flags.has_error())
  assert_eq(decimal_coeff_signed(prev_pos_zero_tiny), -1N)
  assert_eq(prev_pos_zero_tiny.exponent10(), -1007)
  assert_false(prev_pos_zero_tiny_flags.has_error())
  assert_eq(decimal_coeff_signed(prev_neg_zero_tiny), -1N)
  assert_eq(prev_neg_zero_tiny.exponent10(), -1007)
  assert_false(prev_neg_zero_tiny_flags.has_error())
}

///|
test "decimal next plus and minus cross zero without bigint-only artifacts" {
  let ctx = @decimal.DecimalContext::new(precision=3, e_min=-2, e_max=2)
  let neg_unit = @decimal.Decimal::from_string("-0.001", precision=16).unwrap()
  let pos_unit = @decimal.Decimal::from_string("0.001", precision=16).unwrap()
  let (neg_to_zero, neg_to_zero_flags) = neg_unit.next_plus(ctx)
  let (pos_to_zero, pos_to_zero_flags) = pos_unit.next_minus(ctx)
  let (neg_past_zero, neg_past_zero_flags) = neg_to_zero.next_minus(ctx)
  let (pos_past_zero, pos_past_zero_flags) = pos_to_zero.next_plus(ctx)
  assert_eq(neg_to_zero.to_string(), "-0.0009")
  assert_false(neg_to_zero_flags.has_error())
  assert_eq(pos_to_zero.to_string(), "0.0009")
  assert_false(pos_to_zero_flags.has_error())
  assert_eq(neg_past_zero.to_string(), "-0.0010")
  assert_false(neg_past_zero_flags.has_error())
  assert_eq(pos_past_zero.to_string(), "0.0010")
  assert_false(pos_past_zero_flags.has_error())
}

///|
test "decimal next toward follows direction and reports status flags" {
  let wide_ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-383,
    e_max=384,
  )
  let one = @decimal.Decimal::from_string("1", precision=16).unwrap()
  let ten = @decimal.Decimal::from_string("10", precision=16).unwrap()
  let neg_ten = @decimal.Decimal::from_string("-10", precision=16).unwrap()
  let (toward_ten, toward_ten_flags) = one.next_toward(ten, wide_ctx)
  let (toward_neg_ten, toward_neg_ten_flags) = one.next_toward(
    neg_ten, wide_ctx,
  )
  assert_eq(toward_ten.to_string(), "1.00000001")
  assert_false(toward_ten_flags.has_error())
  assert_false(toward_ten_flags.underflow)
  assert_eq(toward_neg_ten.to_string(), "0.999999999")
  assert_false(toward_neg_ten_flags.has_error())

  let pos_zero = @decimal.Decimal::from_string("0.00", precision=16).unwrap()
  let neg_zero = @decimal.Decimal::from_string("-0.0000", precision=16).unwrap()
  let (same_zero, same_zero_flags) = pos_zero.next_toward(neg_zero, wide_ctx)
  assert_eq(same_zero.to_string(), "-0.00")
  assert_eq(same_zero.exponent10(), -2)
  assert_true(same_zero.is_negative_zero())
  assert_false(same_zero_flags.has_error())

  let (tiny, tiny_flags) = @decimal.Decimal::zero().next_toward(ten, wide_ctx)
  let expected_tiny = @decimal.Decimal::from_string("1E-391", precision=16).unwrap()
  assert_eq(tiny.compare_total(expected_tiny), 0)
  assert_true(tiny_flags.underflow)
  assert_true(tiny_flags.subnormal)
  assert_true(tiny_flags.inexact)
  assert_true(tiny_flags.rounded)
  assert_false(tiny_flags.clamped)
}

///|
test "decimal next_toward preserves zero cohort when lhs equals rhs" {
  let ctx = @decimal.DecimalContext::new(precision=9, e_min=-999, e_max=999)
  let pos_zero = @decimal.Decimal::from_string("0", precision=16).unwrap()
  let neg_zero = @decimal.Decimal::from_string("-0", precision=16).unwrap()
  let pos_zero_e4 = @decimal.Decimal::from_string("0E+4", precision=16).unwrap()
  let neg_zero_e4 = @decimal.Decimal::from_string("-0E+4", precision=16).unwrap()
  let pos_zero_frac = @decimal.Decimal::from_string("0.0000", precision=16).unwrap()
  let neg_zero_frac = @decimal.Decimal::from_string("-0.0000", precision=16).unwrap()
  let pos_zero_tiny = @decimal.Decimal::from_string("0E-141", precision=16).unwrap()
  let neg_zero_tiny = @decimal.Decimal::from_string("-0E-141", precision=16).unwrap()
  let (same_pos, same_pos_flags) = pos_zero.next_toward(pos_zero, ctx)
  let (same_neg, same_neg_flags) = neg_zero.next_toward(neg_zero, ctx)
  let (same_pos_e4, same_pos_e4_flags) = pos_zero_e4.next_toward(pos_zero, ctx)
  let (same_neg_e4, same_neg_e4_flags) = neg_zero_e4.next_toward(neg_zero, ctx)
  let (same_pos_frac, same_pos_frac_flags) = pos_zero_frac.next_toward(
    @decimal.Decimal::from_string("0.00000", precision=16).unwrap(),
    ctx,
  )
  let (same_neg_frac, same_neg_frac_flags) = neg_zero_frac.next_toward(
    @decimal.Decimal::from_string("-0.00", precision=16).unwrap(),
    ctx,
  )
  let (same_pos_tiny, same_pos_tiny_flags) = pos_zero_tiny.next_toward(
    pos_zero, ctx,
  )
  let (same_neg_tiny, same_neg_tiny_flags) = neg_zero_tiny.next_toward(
    @decimal.Decimal::from_string("-000", precision=16).unwrap(),
    ctx,
  )
  assert_eq(same_pos.to_string(), "0")
  assert_false(same_pos.is_negative_zero())
  assert_false(same_pos_flags.has_error())
  assert_eq(same_neg.to_string(), "-0")
  assert_true(same_neg.is_negative_zero())
  assert_false(same_neg_flags.has_error())
  assert_eq(same_pos_e4.to_string(), "0E+4")
  assert_false(same_pos_e4.is_negative_zero())
  assert_false(same_pos_e4_flags.has_error())
  assert_eq(same_neg_e4.to_string(), "-0E+4")
  assert_true(same_neg_e4.is_negative_zero())
  assert_false(same_neg_e4_flags.has_error())
  assert_eq(same_pos_frac.to_string(), "0.0000")
  assert_false(same_pos_frac.is_negative_zero())
  assert_false(same_pos_frac_flags.has_error())
  assert_eq(same_neg_frac.to_string(), "-0.0000")
  assert_true(same_neg_frac.is_negative_zero())
  assert_false(same_neg_frac_flags.has_error())
  assert_eq(same_pos_tiny.to_string(), "0E-141")
  assert_false(same_pos_tiny.is_negative_zero())
  assert_false(same_pos_tiny_flags.has_error())
  assert_eq(same_neg_tiny.to_string(), "-0E-141")
  assert_true(same_neg_tiny.is_negative_zero())
  assert_false(same_neg_tiny_flags.has_error())
}

///|
test "decimal next_toward matches official underflow and clamped representatives" {
  let ctx = @decimal.DecimalContext::new(precision=9, e_min=-383, e_max=384)
  let inf = @decimal.Decimal::inf(@def.Sign::Positive, precision=16)
  let neg_inf = @decimal.Decimal::inf(@def.Sign::Negative, precision=16)
  let (zero_up, zero_up_flags) = @decimal.Decimal::zero(precision=16).next_toward(
    @decimal.Decimal::from_int(10, precision=16),
    ctx,
  )
  let (zero_down, zero_down_flags) = @decimal.Decimal::zero(precision=16).next_toward(
    @decimal.Decimal::from_int(-10, precision=16),
    ctx,
  )
  let (neg_zero_up, neg_zero_up_flags) = @decimal.Decimal::negative_zero(
    precision=16,
  ).next_toward(inf, ctx)
  let (neg_tiny_up, neg_tiny_up_flags) = @decimal.Decimal::from_string(
      "-1E-99999",
      precision=32,
    )
    .unwrap()
    .next_toward(inf, ctx)
  let (neg_tiny_eqmin, neg_tiny_eqmin_flags) = @decimal.Decimal::from_string(
      "-1E-391",
      precision=32,
    )
    .unwrap()
    .next_toward(inf, ctx)
  let (pos_tiny_down, pos_tiny_down_flags) = @decimal.Decimal::from_string(
      "1E-99999",
      precision=32,
    )
    .unwrap()
    .next_toward(neg_inf, ctx)
  let (pos_zero_tiny_down, pos_zero_tiny_down_flags) = @decimal.Decimal::from_string(
      "0E-1007",
      precision=32,
    )
    .unwrap()
    .next_toward(neg_inf, ctx)
  assert_eq(zero_up.to_string(), "1E-391")
  assert_true(zero_up_flags.underflow)
  assert_true(zero_up_flags.subnormal)
  assert_true(zero_up_flags.inexact)
  assert_true(zero_up_flags.rounded)
  assert_false(zero_up_flags.clamped)
  assert_eq(zero_down.to_string(), "-1E-391")
  assert_true(zero_down_flags.underflow)
  assert_true(zero_down_flags.subnormal)
  assert_true(zero_down_flags.inexact)
  assert_true(zero_down_flags.rounded)
  assert_false(zero_down_flags.clamped)
  assert_eq(neg_zero_up.to_string(), "1E-391")
  assert_true(neg_zero_up_flags.underflow)
  assert_true(neg_zero_up_flags.subnormal)
  assert_true(neg_zero_up_flags.inexact)
  assert_true(neg_zero_up_flags.rounded)
  assert_false(neg_zero_up_flags.clamped)
  assert_eq(neg_tiny_up.to_string(), "-0E-391")
  assert_true(neg_tiny_up.is_negative_zero())
  assert_true(neg_tiny_up_flags.underflow)
  assert_true(neg_tiny_up_flags.subnormal)
  assert_true(neg_tiny_up_flags.inexact)
  assert_true(neg_tiny_up_flags.rounded)
  assert_true(neg_tiny_up_flags.clamped)
  assert_eq(neg_tiny_eqmin.to_string(), "-0E-391")
  assert_true(neg_tiny_eqmin.is_negative_zero())
  assert_true(neg_tiny_eqmin_flags.underflow)
  assert_true(neg_tiny_eqmin_flags.subnormal)
  assert_true(neg_tiny_eqmin_flags.inexact)
  assert_true(neg_tiny_eqmin_flags.rounded)
  assert_true(neg_tiny_eqmin_flags.clamped)
  assert_eq(pos_tiny_down.to_string(), "0E-391")
  assert_false(pos_tiny_down.is_negative_zero())
  assert_true(pos_tiny_down_flags.underflow)
  assert_true(pos_tiny_down_flags.subnormal)
  assert_true(pos_tiny_down_flags.inexact)
  assert_true(pos_tiny_down_flags.rounded)
  assert_true(pos_tiny_down_flags.clamped)
  assert_eq(pos_zero_tiny_down.to_string(), "-1E-1007")
  assert_true(pos_zero_tiny_down_flags.underflow)
  assert_true(pos_zero_tiny_down_flags.subnormal)
  assert_true(pos_zero_tiny_down_flags.inexact)
  assert_true(pos_zero_tiny_down_flags.rounded)
  assert_false(pos_zero_tiny_down_flags.clamped)
}

///|
test "decimal next_toward matches official negative infinity underflow representatives" {
  let ctx = @decimal.DecimalContext::new(precision=9, e_min=-383, e_max=384)
  let tiny_ctx = @decimal.DecimalContext::new(
    precision=9,
    e_min=-999,
    e_max=999,
  )
  let neg_inf = @decimal.Decimal::inf(@def.Sign::Negative, precision=16)
  let (pos_ultra_tiny, pos_ultra_tiny_flags) = @decimal.Decimal::from_string(
      "1E-99999",
      precision=32,
    )
    .unwrap()
    .next_toward(neg_inf, ctx)
  let (neg_ultra_tiny, neg_ultra_tiny_flags) = @decimal.Decimal::from_string(
      "-1E-99999",
      precision=32,
    )
    .unwrap()
    .next_toward(neg_inf, ctx)
  let (pos_zero, pos_zero_flags) = @decimal.Decimal::zero(precision=32).next_toward(
    neg_inf, ctx,
  )
  let (neg_zero, neg_zero_flags) = @decimal.Decimal::negative_zero(precision=32).next_toward(
    neg_inf, ctx,
  )
  let (pos_zero_huge, pos_zero_huge_flags) = @decimal.Decimal::from_string(
      "0E+30000",
      precision=32,
    )
    .unwrap()
    .next_toward(neg_inf, ctx)
  let (neg_zero_huge, neg_zero_huge_flags) = @decimal.Decimal::from_string(
      "-0E+30000",
      precision=32,
    )
    .unwrap()
    .next_toward(neg_inf, ctx)
  let (pos_zero_tiny, pos_zero_tiny_flags) = @decimal.Decimal::from_string(
      "0E-1007",
      precision=32,
    )
    .unwrap()
    .next_toward(neg_inf, tiny_ctx)
  let (pos_tiny_eqmin, pos_tiny_eqmin_flags) = @decimal.Decimal::from_string(
      "1E-1007",
      precision=32,
    )
    .unwrap()
    .next_toward(neg_inf, tiny_ctx)
  assert_eq(decimal_coeff_signed(pos_ultra_tiny), 0N)
  assert_eq(pos_ultra_tiny.exponent10(), -391)
  assert_false(pos_ultra_tiny.is_negative_zero())
  assert_true(pos_ultra_tiny_flags.underflow)
  assert_true(pos_ultra_tiny_flags.subnormal)
  assert_true(pos_ultra_tiny_flags.inexact)
  assert_true(pos_ultra_tiny_flags.rounded)
  assert_true(pos_ultra_tiny_flags.clamped)
  assert_eq(decimal_coeff_signed(neg_ultra_tiny), -1N)
  assert_eq(neg_ultra_tiny.exponent10(), -391)
  assert_true(neg_ultra_tiny_flags.underflow)
  assert_true(neg_ultra_tiny_flags.subnormal)
  assert_true(neg_ultra_tiny_flags.inexact)
  assert_true(neg_ultra_tiny_flags.rounded)
  assert_false(neg_ultra_tiny_flags.clamped)
  assert_eq(decimal_coeff_signed(pos_zero), -1N)
  assert_eq(pos_zero.exponent10(), -391)
  assert_true(pos_zero_flags.underflow)
  assert_true(pos_zero_flags.subnormal)
  assert_true(pos_zero_flags.inexact)
  assert_true(pos_zero_flags.rounded)
  assert_false(pos_zero_flags.clamped)
  assert_eq(decimal_coeff_signed(neg_zero), -1N)
  assert_eq(neg_zero.exponent10(), -391)
  assert_true(neg_zero_flags.underflow)
  assert_true(neg_zero_flags.subnormal)
  assert_true(neg_zero_flags.inexact)
  assert_true(neg_zero_flags.rounded)
  assert_false(neg_zero_flags.clamped)
  assert_eq(decimal_coeff_signed(pos_zero_huge), -1N)
  assert_eq(pos_zero_huge.exponent10(), -391)
  assert_true(pos_zero_huge_flags.underflow)
  assert_true(pos_zero_huge_flags.subnormal)
  assert_true(pos_zero_huge_flags.inexact)
  assert_true(pos_zero_huge_flags.rounded)
  assert_false(pos_zero_huge_flags.clamped)
  assert_eq(decimal_coeff_signed(neg_zero_huge), -1N)
  assert_eq(neg_zero_huge.exponent10(), -391)
  assert_true(neg_zero_huge_flags.underflow)
  assert_true(neg_zero_huge_flags.subnormal)
  assert_true(neg_zero_huge_flags.inexact)
  assert_true(neg_zero_huge_flags.rounded)
  assert_false(neg_zero_huge_flags.clamped)
  assert_eq(decimal_coeff_signed(pos_zero_tiny), -1N)
  assert_eq(pos_zero_tiny.exponent10(), -1007)
  assert_true(pos_zero_tiny_flags.underflow)
  assert_true(pos_zero_tiny_flags.subnormal)
  assert_true(pos_zero_tiny_flags.inexact)
  assert_true(pos_zero_tiny_flags.rounded)
  assert_false(pos_zero_tiny_flags.clamped)
  assert_eq(decimal_coeff_signed(pos_tiny_eqmin), 0N)
  assert_eq(pos_tiny_eqmin.exponent10(), -1007)
  assert_false(pos_tiny_eqmin.is_negative_zero())
  assert_true(pos_tiny_eqmin_flags.underflow)
  assert_true(pos_tiny_eqmin_flags.subnormal)
  assert_true(pos_tiny_eqmin_flags.inexact)
  assert_true(pos_tiny_eqmin_flags.rounded)
  assert_true(pos_tiny_eqmin_flags.clamped)
}

///|
test "decimal next toward handles overflow clamped zero and nan priority" {
  let ctx = @decimal.DecimalContext::new(precision=3, e_min=-2, e_max=2)
  let max = @decimal.Decimal::from_string("999", precision=16).unwrap()
  let (overflowed, overflow_flags) = max.next_toward(
    @decimal.Decimal::inf(@def.Sign::Positive),
    ctx,
  )
  assert_eq(overflowed.to_string(), "inf")
  assert_true(overflow_flags.overflow)
  assert_true(overflow_flags.inexact)
  assert_true(overflow_flags.rounded)

  let min_tiny = @decimal.Decimal::from_string("0.0001", precision=16).unwrap()
  let (zero, zero_flags) = min_tiny.next_toward(
    @decimal.Decimal::inf(@def.Sign::Negative),
    ctx,
  )
  assert_eq(zero.to_string(), "0.0000")
  assert_true(zero_flags.underflow)
  assert_true(zero_flags.subnormal)
  assert_true(zero_flags.inexact)
  assert_true(zero_flags.rounded)
  assert_true(zero_flags.clamped)

  let lhs_qnan = @decimal.Decimal::quiet_nan(payload=16N, precision=8)
  let rhs_snan = @decimal.Decimal::signaling_nan(payload=19N, precision=8)
  let (rhs_signal_result, rhs_signal_flags) = lhs_qnan.next_toward(
    rhs_snan, ctx,
  )
  assert_eq(rhs_signal_result.to_string(), "nan19")
  assert_true(rhs_signal_flags.invalid_operation)

  let lhs_snan = @decimal.Decimal::signaling_nan(
    payload=27N,
    negative=true,
    precision=8,
  )
  let rhs_snan2 = @decimal.Decimal::signaling_nan(payload=29N, precision=8)
  let (lhs_signal_result, lhs_signal_flags) = lhs_snan.next_toward(
    rhs_snan2, ctx,
  )
  assert_eq(lhs_signal_result.to_string(), "-nan27")
  assert_true(lhs_signal_flags.invalid_operation)
}

///|
test "decimal next_toward toward negative infinity matches official representatives" {
  let ctx = @decimal.DecimalContext::new(precision=9, e_min=-383, e_max=384)
  let neg_inf = @decimal.Decimal::inf(@def.Sign::Negative, precision=16)
  let (pos_ultra_tiny, pos_ultra_tiny_flags) = @decimal.Decimal::from_string(
      "1E-99999",
      precision=32,
    )
    .unwrap()
    .next_toward(neg_inf, ctx)
  let (neg_ultra_tiny, neg_ultra_tiny_flags) = @decimal.Decimal::from_string(
      "-1E-99999",
      precision=32,
    )
    .unwrap()
    .next_toward(neg_inf, ctx)
  let (pos_zero, pos_zero_flags) = @decimal.Decimal::zero(precision=32).next_toward(
    neg_inf, ctx,
  )
  let (neg_zero, neg_zero_flags) = @decimal.Decimal::negative_zero(precision=32).next_toward(
    neg_inf, ctx,
  )
  let (pos_zero_huge, pos_zero_huge_flags) = @decimal.Decimal::from_string(
      "0E+30000",
      precision=32,
    )
    .unwrap()
    .next_toward(neg_inf, ctx)
  let (neg_zero_huge, neg_zero_huge_flags) = @decimal.Decimal::from_string(
      "-0E+30000",
      precision=32,
    )
    .unwrap()
    .next_toward(neg_inf, ctx)
  assert_eq(decimal_coeff_signed(pos_ultra_tiny), 0N)
  assert_eq(pos_ultra_tiny.exponent10(), -391)
  assert_false(pos_ultra_tiny.is_negative_zero())
  assert_true(pos_ultra_tiny_flags.underflow)
  assert_true(pos_ultra_tiny_flags.subnormal)
  assert_true(pos_ultra_tiny_flags.inexact)
  assert_true(pos_ultra_tiny_flags.rounded)
  assert_true(pos_ultra_tiny_flags.clamped)
  assert_eq(decimal_coeff_signed(neg_ultra_tiny), -1N)
  assert_eq(neg_ultra_tiny.exponent10(), -391)
  assert_true(neg_ultra_tiny_flags.underflow)
  assert_true(neg_ultra_tiny_flags.subnormal)
  assert_true(neg_ultra_tiny_flags.inexact)
  assert_true(neg_ultra_tiny_flags.rounded)
  assert_false(neg_ultra_tiny_flags.clamped)
  assert_eq(decimal_coeff_signed(pos_zero), -1N)
  assert_eq(pos_zero.exponent10(), -391)
  assert_true(pos_zero_flags.underflow)
  assert_true(pos_zero_flags.subnormal)
  assert_true(pos_zero_flags.inexact)
  assert_true(pos_zero_flags.rounded)
  assert_false(pos_zero_flags.clamped)
  assert_eq(decimal_coeff_signed(neg_zero), -1N)
  assert_eq(neg_zero.exponent10(), -391)
  assert_true(neg_zero_flags.underflow)
  assert_true(neg_zero_flags.subnormal)
  assert_true(neg_zero_flags.inexact)
  assert_true(neg_zero_flags.rounded)
  assert_false(neg_zero_flags.clamped)
  assert_eq(decimal_coeff_signed(pos_zero_huge), -1N)
  assert_eq(pos_zero_huge.exponent10(), -391)
  assert_true(pos_zero_huge_flags.underflow)
  assert_true(pos_zero_huge_flags.subnormal)
  assert_true(pos_zero_huge_flags.inexact)
  assert_true(pos_zero_huge_flags.rounded)
  assert_false(pos_zero_huge_flags.clamped)
  assert_eq(decimal_coeff_signed(neg_zero_huge), -1N)
  assert_eq(neg_zero_huge.exponent10(), -391)
  assert_true(neg_zero_huge_flags.underflow)
  assert_true(neg_zero_huge_flags.subnormal)
  assert_true(neg_zero_huge_flags.inexact)
  assert_true(neg_zero_huge_flags.rounded)
  assert_false(neg_zero_huge_flags.clamped)
}

///|
test "decimal next_toward toward negative infinity preserves tiny zero cohort representatives" {
  let ctx = @decimal.DecimalContext::new(precision=9, e_min=-999, e_max=999)
  let neg_inf = @decimal.Decimal::inf(@def.Sign::Negative, precision=16)
  let (pos_zero_tiny, pos_zero_tiny_flags) = @decimal.Decimal::from_string(
      "0E-1007",
      precision=32,
    )
    .unwrap()
    .next_toward(neg_inf, ctx)
  let (pos_tiny_eqmin, pos_tiny_eqmin_flags) = @decimal.Decimal::from_string(
      "1E-1007",
      precision=32,
    )
    .unwrap()
    .next_toward(neg_inf, ctx)
  assert_eq(decimal_coeff_signed(pos_zero_tiny), -1N)
  assert_eq(pos_zero_tiny.exponent10(), -1007)
  assert_true(pos_zero_tiny_flags.underflow)
  assert_true(pos_zero_tiny_flags.subnormal)
  assert_true(pos_zero_tiny_flags.inexact)
  assert_true(pos_zero_tiny_flags.rounded)
  assert_false(pos_zero_tiny_flags.clamped)
  assert_eq(decimal_coeff_signed(pos_tiny_eqmin), 0N)
  assert_eq(pos_tiny_eqmin.exponent10(), -1007)
  assert_false(pos_tiny_eqmin.is_negative_zero())
  assert_true(pos_tiny_eqmin_flags.underflow)
  assert_true(pos_tiny_eqmin_flags.subnormal)
  assert_true(pos_tiny_eqmin_flags.inexact)
  assert_true(pos_tiny_eqmin_flags.rounded)
  assert_true(pos_tiny_eqmin_flags.clamped)
}

///|
test "decimal shift and rotate transform coefficient digits in context width" {
  let ctx = @decimal.DecimalContext::new(precision=9)
  let value = @decimal.Decimal::from_string("123456789", precision=16).unwrap()
  let (shift_left, shift_left_flags) = value.shift_ctx(
    @decimal.Decimal::from_int(2),
    ctx,
  )
  let (shift_right, shift_right_flags) = value.shift_ctx(
    @decimal.Decimal::from_int(-2),
    ctx,
  )
  let (rotate_left, rotate_left_flags) = value.rotate_ctx(
    @decimal.Decimal::from_int(2),
    ctx,
  )
  let (rotate_right, rotate_right_flags) = value.rotate_ctx(
    @decimal.Decimal::from_int(-2),
    ctx,
  )
  assert_eq(shift_left.to_string(), "345678900")
  assert_eq(shift_right.to_string(), "1234567")
  assert_eq(rotate_left.to_string(), "345678912")
  assert_eq(rotate_right.to_string(), "891234567")
  assert_false(shift_left_flags.has_error())
  assert_false(shift_right_flags.has_error())
  assert_false(rotate_left_flags.has_error())
  assert_false(rotate_right_flags.has_error())

  let tiny = @decimal.Decimal::from_string("1E-999", precision=16).unwrap()
  let (shift_tiny, _) = tiny.shift_ctx(@decimal.Decimal::from_int(8), ctx)
  let (rotate_tiny, _) = tiny.rotate_ctx(@decimal.Decimal::from_int(8), ctx)
  assert_eq(
    shift_tiny.compare_total(
      @decimal.Decimal::from_string("1.00000000E-991", precision=16).unwrap(),
    ),
    0,
  )
  assert_eq(
    rotate_tiny.compare_total(
      @decimal.Decimal::from_string("1.00000000E-991", precision=16).unwrap(),
    ),
    0,
  )
}

///|
test "decimal shift and rotate validate counts and propagate nans" {
  let ctx = @decimal.DecimalContext::new(precision=5)
  let one = @decimal.Decimal::one(precision=16)
  let invalid_fraction = @decimal.Decimal::from_string("1.0", precision=16).unwrap()
  let (invalid, invalid_flags) = one.shift_ctx(invalid_fraction, ctx)
  assert_eq(invalid.to_string(), "nan")
  assert_true(invalid_flags.invalid_operation)
  let invalid_large = @decimal.Decimal::from_int(6, precision=16)
  let (invalid_rotate, invalid_rotate_flags) = one.rotate_ctx(
    invalid_large, ctx,
  )
  assert_eq(invalid_rotate.to_string(), "nan")
  assert_true(invalid_rotate_flags.invalid_operation)

  let snan = @decimal.Decimal::signaling_nan(
    payload=1234567890N,
    negative=true,
    precision=16,
  )
  let (shift_nan, shift_nan_flags) = one.shift_ctx(snan, ctx)
  let (rotate_nan, rotate_nan_flags) = one.rotate_ctx(snan, ctx)
  assert_eq(shift_nan.to_string(), "-nan67890")
  assert_eq(rotate_nan.to_string(), "-nan67890")
  assert_true(shift_nan_flags.invalid_operation)
  assert_true(rotate_nan_flags.invalid_operation)
}

///|
test "decimal shift and rotate accept exact-context counts" {
  let value = @decimal.Decimal::from_string("1234", precision=16).unwrap()
  let count = @decimal.Decimal::from_int(2)
  let neg_zero_count = @decimal.Decimal::from_string("-0", precision=16).unwrap()
  let huge_count = @decimal.Decimal::from_string("1000000000", precision=16).unwrap()

  let fixed_ctx = @decimal.DecimalContext::new(precision=1)
  let (fixed_shift, fixed_shift_flags) = value.shift_ctx(count, fixed_ctx)
  let (fixed_rotate, fixed_rotate_flags) = value.rotate_ctx(count, fixed_ctx)
  assert_eq(fixed_shift.to_string(), "nan")
  assert_eq(fixed_rotate.to_string(), "nan")
  assert_true(fixed_shift_flags.invalid_operation)
  assert_true(fixed_rotate_flags.invalid_operation)

  let exact_ctx = @decimal.DecimalContext::new(precision=34)
  let (exact_shift, exact_shift_flags) = value.shift_ctx(count, exact_ctx)
  let (exact_rotate, exact_rotate_flags) = value.rotate_ctx(count, exact_ctx)
  assert_false(exact_shift.to_string() == "nan")
  assert_false(exact_rotate.to_string() == "nan")
  assert_false(exact_shift_flags.invalid_operation)
  assert_false(exact_rotate_flags.invalid_operation)

  let (zero_shift, zero_shift_flags) = value.shift_ctx(
    neg_zero_count, exact_ctx,
  )
  let (zero_rotate, zero_rotate_flags) = value.rotate_ctx(
    neg_zero_count, exact_ctx,
  )
  assert_eq(zero_shift.to_string(), "1234")
  assert_eq(zero_rotate.to_string(), "1234")
  assert_false(zero_shift_flags.invalid_operation)
  assert_false(zero_rotate_flags.invalid_operation)

  let (huge_shift, huge_shift_flags) = value.shift_ctx(huge_count, exact_ctx)
  let (huge_rotate, huge_rotate_flags) = value.rotate_ctx(huge_count, exact_ctx)
  assert_eq(huge_shift.to_string(), "nan")
  assert_eq(huge_rotate.to_string(), "nan")
  assert_true(huge_shift_flags.invalid_operation)
  assert_true(huge_rotate_flags.invalid_operation)
}

///|
test "decimal logb returns adjusted exponent with context flags" {
  let ctx = @decimal.DecimalContext::new(precision=9)
  let (basic, basic_flags) = @decimal.Decimal::from_string(
      "-100E-2",
      precision=16,
    )
    .unwrap()
    .logb_ctx(ctx)
  assert_eq(basic.to_string(), "0")
  assert_false(basic_flags.has_error())
  assert_false(basic_flags.rounded)
  assert_false(basic_flags.inexact)

  let rounded_ctx = @decimal.DecimalContext::new(precision=2)
  let (rounded, rounded_flags) = @decimal.Decimal::from_string(
      "1E-999",
      precision=16,
    )
    .unwrap()
    .logb_ctx(rounded_ctx)
  assert_eq(
    rounded.compare_total(
      @decimal.Decimal::from_string("-1.0E+3", precision=16).unwrap(),
    ),
    0,
  )
  assert_true(rounded_flags.rounded)
  assert_true(rounded_flags.inexact)

  let (zero_result, zero_flags) = @decimal.Decimal::negative_zero(precision=16).logb_ctx(
    ctx,
  )
  assert_eq(zero_result.to_string(), "-inf")
  assert_true(zero_flags.division_by_zero)
}

///|
test "decimal logb handles infinities and nan payloads" {
  let ctx = @decimal.DecimalContext::new(precision=5)
  let (inf_result, inf_flags) = @decimal.Decimal::inf(
    @def.Sign::Negative,
    precision=16,
  ).logb_ctx(ctx)
  assert_eq(inf_result.to_string(), "inf")
  assert_false(inf_flags.has_error())

  let snan = @decimal.Decimal::signaling_nan(
    payload=1234567890N,
    negative=true,
    precision=16,
  )
  let (nan_result, nan_flags) = snan.logb_ctx(ctx)
  assert_eq(nan_result.to_string(), "-nan67890")
  assert_true(nan_flags.invalid_operation)
}

///|
test "decimal logb matches official zero cohorts and adjusted exponent representatives" {
  let ctx = @decimal.DecimalContext::new(precision=9, e_min=-999, e_max=999)
  let zero = @decimal.Decimal::zero(precision=16)
  let neg_zero = @decimal.Decimal::negative_zero(precision=16)
  let zero_e4 = @decimal.Decimal::from_string("0E+4", precision=16).unwrap()
  let neg_zero_e4 = @decimal.Decimal::from_string("-0E+4", precision=16).unwrap()
  let zero_frac = @decimal.Decimal::from_string("0.0000", precision=16).unwrap()
  let neg_zero_frac = @decimal.Decimal::from_string("-0.0000", precision=16).unwrap()
  let zero_tiny = @decimal.Decimal::from_string("0E-141", precision=16).unwrap()
  let neg_zero_tiny = @decimal.Decimal::from_string("-0E-141", precision=16).unwrap()
  let (zero_result, zero_flags) = zero.logb_ctx(ctx)
  let (neg_zero_result, neg_zero_flags) = neg_zero.logb_ctx(ctx)
  let (zero_e4_result, zero_e4_flags) = zero_e4.logb_ctx(ctx)
  let (neg_zero_e4_result, neg_zero_e4_flags) = neg_zero_e4.logb_ctx(ctx)
  let (zero_frac_result, zero_frac_flags) = zero_frac.logb_ctx(ctx)
  let (neg_zero_frac_result, neg_zero_frac_flags) = neg_zero_frac.logb_ctx(ctx)
  let (zero_tiny_result, zero_tiny_flags) = zero_tiny.logb_ctx(ctx)
  let (neg_zero_tiny_result, neg_zero_tiny_flags) = neg_zero_tiny.logb_ctx(ctx)
  let (ten_e_neg3, ten_e_neg3_flags) = @decimal.Decimal::from_string(
      "10E-3",
      precision=16,
    )
    .unwrap()
    .logb_ctx(ctx)
  let (hundred_e_neg2, hundred_e_neg2_flags) = @decimal.Decimal::from_string(
      "100E-2",
      precision=16,
    )
    .unwrap()
    .logb_ctx(ctx)
  let (ten_e2, ten_e2_flags) = @decimal.Decimal::from_string(
      "10E2",
      precision=16,
    )
    .unwrap()
    .logb_ctx(ctx)
  assert_eq(zero_result.to_string(), "-inf")
  assert_true(zero_flags.division_by_zero)
  assert_eq(neg_zero_result.to_string(), "-inf")
  assert_true(neg_zero_flags.division_by_zero)
  assert_eq(zero_e4_result.to_string(), "-inf")
  assert_true(zero_e4_flags.division_by_zero)
  assert_eq(neg_zero_e4_result.to_string(), "-inf")
  assert_true(neg_zero_e4_flags.division_by_zero)
  assert_eq(zero_frac_result.to_string(), "-inf")
  assert_true(zero_frac_flags.division_by_zero)
  assert_eq(neg_zero_frac_result.to_string(), "-inf")
  assert_true(neg_zero_frac_flags.division_by_zero)
  assert_eq(zero_tiny_result.to_string(), "-inf")
  assert_true(zero_tiny_flags.division_by_zero)
  assert_eq(neg_zero_tiny_result.to_string(), "-inf")
  assert_true(neg_zero_tiny_flags.division_by_zero)
  assert_eq(ten_e_neg3.to_string(), "-2")
  assert_false(ten_e_neg3_flags.has_error())
  assert_eq(hundred_e_neg2.to_string(), "0")
  assert_false(hundred_e_neg2_flags.has_error())
  assert_eq(ten_e2.to_string(), "3")
  assert_false(ten_e2_flags.has_error())
}

///|
test "decimal scaleb shifts exponent and validates count operand" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
  )
  let value = @decimal.Decimal::from_string("7.50", precision=16).unwrap()
  let (up, up_flags) = value.scaleb_ctx(@decimal.Decimal::from_int(2), ctx)
  let (down, down_flags) = value.scaleb_ctx(@decimal.Decimal::from_int(-2), ctx)
  assert_eq(
    up.compare_total(
      @decimal.Decimal::from_string("750", precision=16).unwrap(),
    ),
    0,
  )
  assert_eq(
    down.compare_total(
      @decimal.Decimal::from_string("0.0750", precision=16).unwrap(),
    ),
    0,
  )
  assert_false(up_flags.has_error())
  assert_false(down_flags.has_error())

  let invalid_count = @decimal.Decimal::from_string("1.00", precision=16).unwrap()
  let (invalid, invalid_flags) = value.scaleb_ctx(invalid_count, ctx)
  assert_eq(invalid.to_string(), "nan")
  assert_true(invalid_flags.invalid_operation)
}

///|
test "decimal scaleb reports subnormal rounding and clamped zero" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
    clamp=true,
  )
  let subnormal_source = @decimal.Decimal::from_string(
    "1.00000000E-999",
    precision=16,
  ).unwrap()
  let (subnormal, subnormal_flags) = subnormal_source.scaleb_ctx(
    @decimal.Decimal::from_int(-1),
    ctx,
  )
  assert_eq(
    subnormal.compare_total(
      @decimal.Decimal::from_string("1.0000000E-1000", precision=16).unwrap(),
    ),
    0,
  )
  assert_true(subnormal_flags.subnormal)
  assert_true(subnormal_flags.rounded)
  assert_false(subnormal_flags.inexact)

  let tiny = @decimal.Decimal::from_string("1E-1007", precision=16).unwrap()
  let (zero, zero_flags) = tiny.scaleb_ctx(@decimal.Decimal::from_int(-1), ctx)
  assert_eq(
    zero.compare_total(
      @decimal.Decimal::from_string("0E-1007", precision=16).unwrap(),
    ),
    0,
  )
  assert_true(zero_flags.underflow)
  assert_true(zero_flags.subnormal)
  assert_true(zero_flags.inexact)
  assert_true(zero_flags.rounded)
  assert_true(zero_flags.clamped)
}

///|
test "decimal scaleb preserves zero sign and shifted zero cohort" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
  )
  let pos_zero = @decimal.Decimal::zero(precision=16)
  let neg_zero = @decimal.Decimal::negative_zero(precision=16)
  let frac_zero = @decimal.Decimal::from_string("0.0000", precision=16).unwrap()
  let neg_frac_zero = @decimal.Decimal::from_string("-0.0000", precision=16).unwrap()
  let exp_zero = @decimal.Decimal::from_string("0E-141", precision=16).unwrap()
  let (pos_shifted, pos_flags) = pos_zero.scaleb_ctx(
    @decimal.Decimal::from_int(1),
    ctx,
  )
  let (neg_shifted, neg_flags) = neg_zero.scaleb_ctx(
    @decimal.Decimal::from_int(2),
    ctx,
  )
  let (frac_shifted, frac_flags) = frac_zero.scaleb_ctx(
    @decimal.Decimal::from_int(5),
    ctx,
  )
  let (neg_frac_shifted, neg_frac_flags) = neg_frac_zero.scaleb_ctx(
    @decimal.Decimal::from_int(6),
    ctx,
  )
  let (exp_shifted, exp_flags) = exp_zero.scaleb_ctx(
    @decimal.Decimal::from_int(7),
    ctx,
  )
  assert_eq(decimal_coeff_signed(pos_shifted), 0N)
  assert_eq(pos_shifted.exponent10(), 1)
  assert_false(pos_shifted.is_negative_zero())
  assert_false(pos_flags.has_error())
  assert_eq(decimal_coeff_signed(neg_shifted), 0N)
  assert_eq(neg_shifted.exponent10(), 2)
  assert_true(neg_shifted.is_negative_zero())
  assert_false(neg_flags.has_error())
  assert_eq(decimal_coeff_signed(frac_shifted), 0N)
  assert_eq(frac_shifted.exponent10(), 1)
  assert_false(frac_shifted.is_negative_zero())
  assert_false(frac_flags.has_error())
  assert_eq(decimal_coeff_signed(neg_frac_shifted), 0N)
  assert_eq(neg_frac_shifted.exponent10(), 2)
  assert_true(neg_frac_shifted.is_negative_zero())
  assert_false(neg_frac_flags.has_error())
  assert_eq(decimal_coeff_signed(exp_shifted), 0N)
  assert_eq(exp_shifted.exponent10(), -134)
  assert_false(exp_shifted.is_negative_zero())
  assert_false(exp_flags.has_error())
}

///|
test "decimal scaleb handles infinities and nan priority" {
  let ctx = @decimal.DecimalContext::new(precision=5, e_min=-9, e_max=9).gda()
  let (inf_result, inf_flags) = @decimal.Decimal::inf(
    @def.Sign::Negative,
    precision=16,
  ).scaleb_ctx(@decimal.Decimal::from_int(2), ctx)
  assert_eq(inf_result.to_string(), "-inf")
  assert_false(inf_flags.has_error())

  let lhs_qnan = @decimal.Decimal::quiet_nan(payload=16N, precision=16)
  let rhs_snan = @decimal.Decimal::signaling_nan(payload=123456N, precision=16)
  let (nan_result, nan_flags) = lhs_qnan.scaleb_ctx(rhs_snan, ctx)
  assert_eq(nan_result.to_string(), "nan23456")
  assert_true(nan_flags.invalid_operation)
}

///|
test "decimal transcendental operations report invalid_context on restricted math contexts" {
  let precision_ctx = @decimal.DecimalContext::new(precision=1000000000)
  let upper_ctx = @decimal.DecimalContext::new(
    precision=9,
    e_min=-999999999,
    e_max=1000000000,
  )
  let lower_ctx = @decimal.DecimalContext::new(
    precision=9,
    e_min=-1000000000,
    e_max=999999999,
  )
  let one = @decimal.Decimal::one(precision=8)
  let ten = @decimal.Decimal::from_int(10, precision=8)
  let minus_inf = @decimal.Decimal::inf(@def.Sign::Negative, precision=8)
  let non_integer = @decimal.Decimal::from_string("1.1", precision=8).unwrap()
  let integer = @decimal.Decimal::from_int(2, precision=8)
  let (log10_precision, log10_precision_flags) = one.log10_ctx(precision_ctx)
  let (ln_upper, ln_upper_flags) = one.ln_ctx(upper_ctx)
  let (exp_lower, exp_lower_flags) = minus_inf.exp_ctx(lower_ctx)
  let (power_upper, power_upper_flags) = one.power_ctx(non_integer, upper_ctx)
  let (power_fast, power_fast_flags) = ten.power_ctx(integer, upper_ctx)
  assert_eq(log10_precision.to_string(), "nan")
  assert_true(log10_precision_flags.invalid_context)
  assert_false(log10_precision_flags.invalid_operation)
  assert_eq(ln_upper.to_string(), "nan")
  assert_true(ln_upper_flags.invalid_context)
  assert_false(ln_upper_flags.invalid_operation)
  assert_eq(exp_lower.to_string(), "nan")
  assert_true(exp_lower_flags.invalid_context)
  assert_false(exp_lower_flags.invalid_operation)
  assert_eq(power_upper.to_string(), "nan")
  assert_true(power_upper_flags.invalid_context)
  assert_false(power_upper_flags.invalid_operation)
  assert_eq(power_fast.to_string(), "nan")
  assert_true(power_fast_flags.invalid_context)
  assert_false(power_fast_flags.invalid_operation)
}

///|
test "decimal integer power accepts the full gda exponent context" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999999999,
    e_max=999999999,
    extended=false,
  )
  let (value, flags) = decimal_test_operand("905.67402").power_ctx(
    decimal_test_operand("-2"),
    ctx,
  )
  assert_decimal_total_eq(
    value,
    decimal_test_operand("0.0000012191473"),
    "rpow001 result",
  )
  assert_true(flags.inexact)
  assert_true(flags.rounded)
  assert_false(flags.invalid_context)
  assert_false(flags.invalid_operation)
}

///|
test "decimal power bounds extreme coefficients without expanding their exponent" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999999999,
    e_max=999999999,
    extended=false,
  )
  let (value, flags) = decimal_test_operand("-671.507198E-908587890").power_ctx(
    decimal_test_operand("3"),
    ctx,
  )
  assert_true(value.is_zero())
  assert_true(value.is_negative_zero())
  assert_true(flags.underflow)
  assert_true(flags.subnormal)
  assert_true(flags.inexact)
  assert_true(flags.rounded)
  assert_false(flags.clamped)
}

///|
test "decimal transcendental constant reuse stays scale-correct across interleaved contexts" {
  let low_ctx = @decimal.DecimalContext::new(
    precision=12,
    e_min=-999_999,
    e_max=999_999,
  )
  let high_ctx = @decimal.DecimalContext::new(
    precision=28,
    e_min=-999_999,
    e_max=999_999,
  )
  let ln_value = @decimal.Decimal::from_string("2.5", precision=40).unwrap()
  let log10_value = @decimal.Decimal::from_string("12345.6789", precision=40).unwrap()
  let exp_value = @decimal.Decimal::from_string("1.23456789", precision=40).unwrap()
  let exponent = @decimal.Decimal::from_string("1.25", precision=40).unwrap()

  let (ln_low0, ln_low0_flags) = ln_value.ln_ctx(low_ctx)
  let _ = log10_value.log10_ctx(high_ctx)
  let _ = exp_value.exp_ctx(high_ctx)
  let (ln_low1, ln_low1_flags) = ln_value.ln_ctx(low_ctx)
  assert_eq(ln_low0.compare_total(ln_low1), 0)
  assert_true(ln_low0_flags == ln_low1_flags)

  let (power_low0, power_low0_flags) = ln_value.power_ctx(exponent, low_ctx)
  let _ = ln_value.power_ctx(exponent, high_ctx)
  let (power_low1, power_low1_flags) = ln_value.power_ctx(exponent, low_ctx)
  assert_eq(power_low0.compare_total(power_low1), 0)
  assert_true(power_low0_flags == power_low1_flags)
}

///|
test "decimal ln lookaside constants preserve official-scale semantics" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-999_999,
    e_max=999_999,
  )
  let (ln10, ln10_flags) = @decimal.Decimal::from_int(10, precision=32).ln_ctx(
    ctx,
  )
  let (ln2e3, ln2e3_flags) = @decimal.Decimal::from_string("2E+3", precision=32)
    .unwrap()
    .ln_ctx(ctx)
  let (ln5e4, ln5e4_flags) = @decimal.Decimal::from_string("5E+4", precision=32)
    .unwrap()
    .ln_ctx(ctx)
  assert_decimal_total_eq(
    ln10,
    decimal_test_operand("2.30258509"),
    "ln10 lookaside",
  )
  assert_true(ln10_flags.rounded)
  assert_true(ln10_flags.inexact)
  assert_decimal_total_eq(
    ln2e3,
    decimal_test_operand("7.60090246"),
    "ln(2E+3) lookaside",
  )
  assert_true(ln2e3_flags.rounded)
  assert_true(ln2e3_flags.inexact)
  assert_decimal_total_eq(
    ln5e4,
    decimal_test_operand("10.8197783"),
    "ln(5E+4) lookaside",
  )
  assert_true(ln5e4_flags.rounded)
  assert_true(ln5e4_flags.inexact)
}

///|
test "decimal exact division by power of ten preserves preferred exponent behavior" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-999_999,
    e_max=999_999,
  )
  let (hundreds, hundreds_flags) = @decimal.Decimal::from_int(100, precision=32).div_ctx(
    @decimal.Decimal::from_int(100, precision=32),
    ctx,
  )
  let (shifted, shifted_flags) = @decimal.Decimal::from_string(
      "1.2300",
      precision=32,
    )
    .unwrap()
    .div_ctx(@decimal.Decimal::from_string("10", precision=32).unwrap(), ctx)
  assert_decimal_total_eq(hundreds, decimal_test_operand("1"), "100/100 cohort")
  assert_false(hundreds_flags.rounded)
  assert_false(hundreds_flags.inexact)
  assert_decimal_total_eq(
    shifted,
    decimal_test_operand("0.1230"),
    "1.2300/10 cohort",
  )
  assert_false(shifted_flags.rounded)
  assert_false(shifted_flags.inexact)
}

///|
test "decimal integer quotient fast paths for power-of-ten divisors preserve results" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-999_999,
    e_max=999_999,
  )
  let (quotient, quotient_flags) = @decimal.Decimal::from_string(
      "12345",
      precision=32,
    )
    .unwrap()
    .divide_integer(
      @decimal.Decimal::from_string("1E+3", precision=32).unwrap(),
      ctx,
    )
  let (near, near_flags) = @decimal.Decimal::from_string("12345", precision=32)
    .unwrap()
    .remainder_near(
      @decimal.Decimal::from_string("1E+2", precision=32).unwrap(),
      ctx,
    )
  assert_decimal_total_eq(
    quotient,
    decimal_test_operand("12"),
    "divide_integer 10^k fast path",
  )
  assert_false(quotient_flags.has_error())
  assert_decimal_total_eq(
    near,
    decimal_test_operand("45"),
    "remainder_near 10^k fast path",
  )
  assert_false(near_flags.has_error())
}

///|
test "decimal noninteger power matches powersqrt representative" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-999_999,
    e_max=999_999,
  )
  let (value, flags) = @decimal.Decimal::from_string("4", precision=32)
    .unwrap()
    .power_ctx(@decimal.Decimal::from_string("0.5", precision=32).unwrap(), ctx)
  assert_decimal_total_eq(
    value,
    decimal_test_operand("2.00000000"),
    "pwsx081 result",
  )
  assert_true(flags.rounded)
  assert_true(flags.inexact)
  assert_false(flags.invalid_operation)
  assert_false(flags.invalid_context)
}

///|
test "decimal noninteger power matches official near-integer and one-base representatives" {
  let near_integer_ctx = @decimal.DecimalContext::new(
    precision=16,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-383,
    e_max=384,
  )
  let (near_integer, near_integer_flags) = @decimal.Decimal::from_string(
      "2",
      precision=32,
    )
    .unwrap()
    .power_ctx(
      @decimal.Decimal::from_string("2.000001", precision=32).unwrap(),
      near_integer_ctx,
    )
  assert_decimal_total_eq(
    near_integer,
    decimal_test_operand("4.000002772589683"),
    "powx2001 result",
  )
  assert_true(near_integer_flags.rounded)
  assert_true(near_integer_flags.inexact)

  let one_ctx = @decimal.DecimalContext::new(
    precision=3,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-383,
    e_max=384,
  )
  let one = @decimal.Decimal::one(precision=16)
  let (one_noninteger, one_noninteger_flags) = one.power_ctx(
    @decimal.Decimal::from_string("12.3", precision=32).unwrap(),
    one_ctx,
  )
  let (one_integer_like, one_integer_like_flags) = one.power_ctx(
    @decimal.Decimal::from_string("12.0", precision=32).unwrap(),
    one_ctx,
  )
  assert_decimal_total_eq(
    one_noninteger,
    decimal_test_operand("1.00"),
    "powx2015 result",
  )
  assert_true(one_noninteger_flags.rounded)
  assert_true(one_noninteger_flags.inexact)
  assert_decimal_total_eq(
    one_integer_like,
    decimal_test_operand("1"),
    "powx2016 result",
  )
  assert_true(one_integer_like_flags == @decimal.DecimalFlags::new())
}

///|
test "decimal official underflow-to-zero edge rows preserve clamped zero semantics" {
  let exp_ctx = @decimal.DecimalContext::new(
    precision=7,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-383,
    e_max=384,
  )
  let mul_ctx = @decimal.DecimalContext::new(
    precision=5,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-999,
    e_max=999,
  )
  let power_ctx = mul_ctx

  let (exp_value, exp_flags) = @decimal.Decimal::from_string(
      "-896.3988",
      precision=16,
    )
    .unwrap()
    .exp_ctx(exp_ctx)
  let exp_expected = @decimal.Decimal::from_string("0E-389", precision=16).unwrap()
  assert_eq(decimal_coeff_signed(exp_value), 0N)
  assert_eq(exp_value.exponent10(), -389)
  assert_eq(exp_value.compare_total(exp_expected), 0)
  assert_true(exp_flags.underflow)
  assert_true(exp_flags.subnormal)
  assert_true(exp_flags.inexact)
  assert_true(exp_flags.rounded)
  assert_true(exp_flags.clamped)

  let (mul_value, mul_flags) = @decimal.Decimal::from_string(
      "1E-502",
      precision=16,
    )
    .unwrap()
    .mul_ctx(
      @decimal.Decimal::from_string("1E-502", precision=16).unwrap(),
      mul_ctx,
    )
  let mul_expected = @decimal.Decimal::from_string("0E-1003", precision=16).unwrap()
  assert_eq(mul_value.compare_total(mul_expected), 0)
  assert_true(mul_flags.underflow)
  assert_true(mul_flags.subnormal)
  assert_true(mul_flags.inexact)
  assert_true(mul_flags.rounded)
  assert_true(mul_flags.clamped)

  let (power_value, power_flags) = @decimal.Decimal::from_string(
      "-0.04E+336",
      precision=16,
    )
    .unwrap()
    .power_ctx(
      @decimal.Decimal::from_string("-3", precision=16).unwrap(),
      power_ctx,
    )
  let power_expected = @decimal.Decimal::from_string("-0E-1003", precision=16).unwrap()
  assert_eq(power_value.compare_total(power_expected), 0)
  assert_true(power_flags.underflow)
  assert_true(power_flags.subnormal)
  assert_true(power_flags.inexact)
  assert_true(power_flags.rounded)
  assert_true(power_flags.clamped)
}

///|
test "decimal plus_ctx handles underflow shifts far beyond coefficient digits" {
  let ctx = @decimal.DecimalContext::new(
    precision=7,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-383,
    e_max=384,
  )
  let (positive, positive_flags) = @decimal.Decimal::from_string(
      "1E-1000000000",
      precision=16,
    )
    .unwrap()
    .plus_ctx(ctx)
  let (negative, negative_flags) = @decimal.Decimal::from_string(
      "-1E-1000000000",
      precision=16,
    )
    .unwrap()
    .plus_ctx(ctx)
  let expected_positive = @decimal.Decimal::from_string("0E-389", precision=16).unwrap()
  let expected_negative = @decimal.Decimal::from_string("-0E-389", precision=16).unwrap()
  assert_eq(positive.compare_total(expected_positive), 0)
  assert_true(positive_flags.underflow)
  assert_true(positive_flags.subnormal)
  assert_true(positive_flags.inexact)
  assert_true(positive_flags.rounded)
  assert_true(positive_flags.clamped)
  assert_eq(negative.compare_total(expected_negative), 0)
  assert_true(negative_flags.underflow)
  assert_true(negative_flags.subnormal)
  assert_true(negative_flags.inexact)
  assert_true(negative_flags.rounded)
  assert_true(negative_flags.clamped)
}

///|
test "decimal gda string conversions format and report context flags" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999_999_999,
    e_max=999_999_999,
  )
  let (rounded, rounded_flags) = @decimal.Decimal::to_sci_string(
    "1000000000", ctx,
  )
  assert_eq(rounded, "1.00000000E+9")
  assert_true(rounded_flags.rounded)
  assert_false(rounded_flags.inexact)

  let (finite_overflow, overflow_flags) = @decimal.Decimal::to_sci_string(
    "7e1000000000",
    @decimal.DecimalContext::new(
      precision=9,
      decimal_rounding=@decimal.DecimalRoundingMode::Down,
      e_min=-999_999_999,
      e_max=999_999_999,
    ),
  )
  assert_eq(finite_overflow, "9.99999999E+999999999")
  assert_true(overflow_flags.overflow)
  assert_true(overflow_flags.inexact)

  let tiny_ctx = @decimal.DecimalContext::new(
    precision=7,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-95,
    e_max=96,
  )
  let (tiny, tiny_flags) = @decimal.Decimal::to_sci_string(
    "1e-2147483647", tiny_ctx,
  )
  assert_eq(tiny, "0E-101")
  assert_true(tiny_flags.underflow)
  assert_true(tiny_flags.subnormal)
  assert_true(tiny_flags.inexact)
  assert_true(tiny_flags.rounded)
  assert_true(tiny_flags.clamped)

  let (neg_tiny, neg_tiny_flags) = @decimal.Decimal::to_sci_string(
    "-1e-2147483647", tiny_ctx,
  )
  assert_eq(neg_tiny, "-0E-101")
  assert_true(neg_tiny_flags.underflow)
  assert_true(neg_tiny_flags.subnormal)
  assert_true(neg_tiny_flags.inexact)
  assert_true(neg_tiny_flags.rounded)
  assert_true(neg_tiny_flags.clamped)
}

///|
test "decimal gda string conversions match official emax229 representative" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-2,
    e_max=2,
  )
  let (emax229, emax229_flags) = @decimal.Decimal::to_sci_string("1E-11", ctx)
  assert_eq(emax229, "0E-10")
  assert_true(emax229_flags.underflow)
  assert_true(emax229_flags.subnormal)
  assert_true(emax229_flags.inexact)
  assert_true(emax229_flags.rounded)
  assert_true(emax229_flags.clamped)
}

///|
test "decimal gda string conversions match official emax280 representative" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-99,
    e_max=99,
  )
  let (emax280, emax280_flags) = @decimal.Decimal::to_sci_string("1E-120", ctx)
  assert_eq(emax280, "0E-107")
  assert_true(emax280_flags.underflow)
  assert_true(emax280_flags.subnormal)
  assert_true(emax280_flags.inexact)
  assert_true(emax280_flags.rounded)
  assert_true(emax280_flags.clamped)
}

///|
test "decimal gda string conversions match official emax420 representative" {
  let ctx = @decimal.DecimalContext::new(
    precision=5,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-999,
    e_max=999,
  )
  let (emax420, emax420_flags) = @decimal.Decimal::to_sci_string(
    "0.00005E-999", ctx,
  )
  assert_eq(emax420, "0E-1003")
  assert_true(emax420_flags.underflow)
  assert_true(emax420_flags.subnormal)
  assert_true(emax420_flags.inexact)
  assert_true(emax420_flags.rounded)
  assert_true(emax420_flags.clamped)
}

///|
test "decimal gda string conversions match official huge-emax underflow representatives" {
  let ctx_large = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999_999_999,
    e_max=999_999_999,
  )
  let (emax347, emax347_flags) = @decimal.Decimal::to_sci_string(
    "1E-1000000008", ctx_large,
  )
  assert_eq(emax347, "0E-1000000007")
  assert_true(emax347_flags.underflow)
  assert_true(emax347_flags.subnormal)
  assert_true(emax347_flags.inexact)
  assert_true(emax347_flags.rounded)
  assert_true(emax347_flags.clamped)

  let (emax367, emax367_flags) = @decimal.Decimal::to_sci_string(
    "9.999E-1000000009", ctx_large,
  )
  assert_eq(emax367, "0E-1000000007")
  assert_true(emax367_flags.underflow)
  assert_true(emax367_flags.subnormal)
  assert_true(emax367_flags.inexact)
  assert_true(emax367_flags.rounded)
  assert_true(emax367_flags.clamped)

  let (emax382, emax382_flags) = @decimal.Decimal::to_sci_string(
    "-1.001E-1000000008", ctx_large,
  )
  assert_eq(emax382, "-0E-1000000007")
  assert_true(emax382_flags.underflow)
  assert_true(emax382_flags.subnormal)
  assert_true(emax382_flags.inexact)
  assert_true(emax382_flags.rounded)
  assert_true(emax382_flags.clamped)
}

///|
test "decimal gda string conversions handle engineering zeros and syntax" {
  let ctx = @decimal.DecimalContext::new(precision=4)
  let (eng, eng_flags) = @decimal.Decimal::to_eng_string("10e1", ctx)
  assert_eq(eng, "100")
  assert_false(eng_flags.has_error())

  let (zero_eng, zero_flags) = @decimal.Decimal::to_eng_string("0e+1", ctx)
  assert_eq(zero_eng, "0.00E+3")
  assert_false(zero_flags.has_error())

  let (bad, bad_flags) = @decimal.Decimal::to_sci_string("1E++1", ctx)
  assert_eq(bad, "NaN")
  assert_true(bad_flags.conversion_syntax)
}

///|
test "decimal gda string conversions canonicalize special spellings and payloads" {
  let ctx = @decimal.DecimalContext::new(precision=8)

  let (inf, inf_flags) = @decimal.Decimal::to_sci_string("+inf", ctx)
  assert_eq(inf, "Infinity")
  assert_false(inf_flags.has_error())

  let (qnan, qnan_flags) = @decimal.Decimal::to_sci_string("-nan0007", ctx)
  assert_eq(qnan, "-NaN7")
  assert_false(qnan_flags.has_error())

  let (snan, snan_flags) = @decimal.Decimal::to_eng_string("sNaN0000", ctx)
  assert_eq(snan, "sNaN")
  assert_false(snan_flags.has_error())
}

///|
test "decimal gda string conversions enforce clamped nan payload bounds" {
  let ctx = @decimal.DecimalContext::new(precision=4, clamp=true)

  let (allowed, allowed_flags) = @decimal.Decimal::to_sci_string("NaN123", ctx)
  assert_eq(allowed, "NaN123")
  assert_false(allowed_flags.has_error())

  let (too_wide, too_wide_flags) = @decimal.Decimal::to_sci_string(
    "NaN1234", ctx,
  )
  assert_eq(too_wide, "NaN")
  assert_true(too_wide_flags.conversion_syntax)
}

///|
test "ball_float exact containment works" {
  let x = binary_test_make(3N, -1, 16)
  let ball = @ball_float.BallFloat::exact(x)
  assert_true(ball.contains(x))
  assert_eq(ball.to_string(), "3p-1 +/- 0")
}

///|
test "ball_float constructors accept coefficient and float family inputs" {
  let from_big = @ball_float.BallFloat::from_coefficient(
    @bin_float.BinCoeff::from_uint64(42UL),
    precision=20,
  )
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
    binary_test_make(9N, -4, 8),
    precision=2,
  )
  assert_eq(ball.radius().to_string(), "3p-2")
}

///|
test "ball_float arithmetic keeps exact scalar results enclosed" {
  let a = @ball_float.BallFloat::exact(binary_test_make(3N, -1, 8), precision=3)
  let b = @ball_float.BallFloat::exact(binary_test_make(5N, -2, 8), precision=3)
  let sum = a + b
  let product = a * b
  let quotient = a / b
  let exact_sum = binary_test_make(11N, -2, 32)
  let exact_product = binary_test_make(15N, -3, 32)
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
    binary_test_make(1N, -2, 8),
    binary_test_make(1N, -1, 8),
    precision=4,
  )
  let right = @ball_float.BallFloat::new(
    @bin_float.BinFloat::from_int(2, precision=8),
    binary_test_make(1N, -2, 8),
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
test "ball_float coefficient constructor keeps exact bounded interval" {
  let value = @ball_float.BallFloat::from_coefficient(
    @bin_float.BinCoeff::from_uint64(12UL),
  ).normalized()
  assert_eq(
    value,
    @ball_float.BallFloat::from_coefficient(
      @bin_float.BinCoeff::from_uint64(12UL),
    ).normalized(),
  )
  assert_true(value.is_bounded())
  assert_eq(value.lower_bound(), value.upper_bound())
}

///|
test "ball_float implements checked enclosure-preserving power and division" {
  let unit_ball = @ball_float.BallFloat::exact(
    binary_test_make(3N, -1, 24),
    precision=12,
  )
  match square_checked(unit_ball, checked_ctx) {
    Ok(value) => assert_true(value.contains(binary_test_make(9N, -2, 48)))
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
test "bin_float_checked keeps arithmetic closed and propagates errors" {
  let one = @bin_float_checked.BinFloatResult::from_int(1, precision=16)
  let two = @bin_float_checked.BinFloatResult::from_int(2, precision=16)
  match ((one + two).pow_nat(2U) * two).sqrt().result() {
    Ok(value) =>
      assert_true(value.compare(@bin_float.BinFloat::zero(precision=16)) > 0)
    Err(_) => fail("expected closed bin float result pipeline to succeed")
  }
  let zero = @bin_float_checked.BinFloatResult::from_int(0, precision=16)
  match (one / zero).abs().result() {
    Ok(_) => fail("expected division by zero to remain an error")
    Err(err) => assert_true(err.is_division_by_zero())
  }
}

///|
test "decimal_checked maps parse and checked operations inside the wrapper" {
  let parsed = @decimal_checked.DecimalResult::parse("9.0", precision=20)
  let three = @decimal_checked.DecimalResult::from_int(3, precision=20)
  match (parsed.sqrt().pow_int(1) / three).normalized().result() {
    Ok(value) => assert_eq(value, @decimal.Decimal::one(precision=20))
    Err(_) => fail("expected decimal result pipeline to succeed")
  }
  match
    @decimal_checked.DecimalResult::parse("bad", precision=20).sqrt().result() {
    Ok(_) => fail("expected parse error to short-circuit")
    Err(err) => assert_true(err.is_parse_error())
  }
  match @decimal_checked.DecimalResult::parse("sNaN7", precision=20).result() {
    Ok(value) => {
      assert_true(value.is_snan())
      assert_eq(value.nan_payload(), 7N)
    }
    Err(_) => fail("expected decimal result special parse to succeed")
  }
}

///|
test "ball_float_checked keeps interval operations in one result category" {
  let one = @ball_float_checked.BallFloatResult::from_int(1, precision=12)
  let zero_crossing = @ball_float_checked.BallFloatResult::from_bounds(
    binary_test_make(-1N, 0, 16),
    @bin_float.BinFloat::one(precision=16),
    precision=12,
  )
  match (one.pow_nat(2U) / zero_crossing).pow_int(-1).result() {
    Ok(value) => assert_true(value.is_entire())
    Err(_) => fail("expected ball result whole-real fallback to succeed")
  }
  let invalid = @ball_float_checked.BallFloatResult::from_double(
    0.0 / 0.0,
    precision=12,
  )
  match (invalid + one).result() {
    Ok(_) => fail("expected invalid ball source to short-circuit")
    Err(err) => assert_true(err.is_domain_error())
  }
}

///|
fn decimal_test_operand(src : String) -> @decimal.Decimal {
  match @decimal.Decimal::parse(src, precision=64) {
    Ok(value) => value
    Err(_) => abort("expected decimal parse to succeed: " + src)
  }
}

///|
fn assert_decimal_total_eq(
  actual : @decimal.Decimal,
  expected : @decimal.Decimal,
  label : String,
) -> Unit {
  if actual.compare_total(expected) != 0 {
    abort(label)
  }
}

///|
test "decimal transcendental results finalize with half-even regardless of context rounding" {
  let half_even_ctx = @decimal.DecimalContext::new(
    precision=3,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-999_999,
    e_max=999_999,
  )
  let upward_ctx = @decimal.DecimalContext::new(
    precision=3,
    decimal_rounding=@decimal.DecimalRoundingMode::Up,
    e_min=-999_999,
    e_max=999_999,
  )

  let (exp_even, exp_even_flags) = decimal_test_operand("0.01").exp_ctx(
    half_even_ctx,
  )
  let (exp_upward, exp_upward_flags) = decimal_test_operand("0.01").exp_ctx(
    upward_ctx,
  )
  assert_decimal_total_eq(
    exp_even,
    decimal_test_operand("1.01"),
    "exp half-even",
  )
  assert_decimal_total_eq(exp_upward, exp_even, "exp ignores ctx rounding")
  assert_true(exp_even_flags.rounded && exp_even_flags.inexact)
  assert_true(exp_upward_flags.rounded && exp_upward_flags.inexact)

  let (ln_even, _) = decimal_test_operand("2").ln_ctx(half_even_ctx)
  let (ln_upward, _) = decimal_test_operand("2").ln_ctx(upward_ctx)
  assert_decimal_total_eq(
    ln_even,
    decimal_test_operand("0.693"),
    "ln half-even",
  )
  assert_decimal_total_eq(ln_upward, ln_even, "ln ignores ctx rounding")

  let (log10_even, _) = decimal_test_operand("2").log10_ctx(half_even_ctx)
  let (log10_upward, _) = decimal_test_operand("2").log10_ctx(upward_ctx)
  assert_decimal_total_eq(
    log10_even,
    decimal_test_operand("0.301"),
    "log10 half-even",
  )
  assert_decimal_total_eq(
    log10_upward, log10_even, "log10 ignores ctx rounding",
  )
}

///|
test "decimal context enables extended GDA arithmetic by default" {
  let default_ctx = @decimal.DecimalContext::new(
    precision=17,
    e_min=-999_999,
    e_max=999_999,
  )
  let extended_ctx = @decimal.DecimalContext::new(
    precision=17,
    e_min=-999_999,
    e_max=999_999,
    extended=true,
  )
  let subset_ctx = @decimal.DecimalContext::new(
    precision=17,
    e_min=-999_999,
    e_max=999_999,
    extended=false,
  )
  assert_true(default_ctx.extended())

  let value = decimal_test_operand("0.99999991000000405")
  let (default_result, default_flags) = value.ln_ctx(default_ctx)
  let (extended_result, extended_flags) = value.ln_ctx(extended_ctx)
  let (subset_result, subset_flags) = value.ln_ctx(subset_ctx)
  assert_eq(default_result.to_string(), "-8.9999999999999878E-8")
  assert_decimal_total_eq(
    extended_result, default_result, "explicit extended ln",
  )
  assert_eq(subset_result.to_string(), "-8.9999999999999879E-8")
  assert_true(default_flags.rounded && default_flags.inexact)
  assert_true(extended_flags.rounded && extended_flags.inexact)
  assert_true(subset_flags.rounded && subset_flags.inexact)
}

///|
test "decimal integer power keeps large exact powers exact when precision allows" {
  let ctx = @decimal.DecimalContext::new(
    precision=400,
    decimal_rounding=@decimal.DecimalRoundingMode::Up,
    e_min=-999_999,
    e_max=999_999,
  )
  let base = @decimal.Decimal::from_int(2, precision=32)
  let exponent = @decimal.Decimal::from_int(1001, precision=32)
  let (value, flags) = base.power_ctx(exponent, ctx)
  let expected = @decimal.Decimal::from_bigint(2N.pow(1001N), precision=400)
  assert_decimal_total_eq(value, expected.normalized(), "2^1001 exact result")
  assert_false(flags.rounded)
  assert_false(flags.inexact)
}

///|
test "decimal subset extrema clean selected zero representations" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-999_999,
    e_max=999_999,
    extended=false,
  )
  let negative_zero = decimal_test_operand("-0")
  let positive_zero = decimal_test_operand("0")

  let (minimum, min_flags) = negative_zero.min_ctx(positive_zero, ctx)
  let (maximum, max_flags) = negative_zero.max_ctx(positive_zero, ctx)
  let (minimum_mag, min_mag_flags) = negative_zero.min_mag_ctx(
    positive_zero, ctx,
  )
  let (maximum_mag, max_mag_flags) = negative_zero.max_mag_ctx(
    positive_zero, ctx,
  )

  assert_decimal_total_eq(minimum, positive_zero, "min cleans zero")
  assert_decimal_total_eq(maximum, positive_zero, "max keeps +0")
  assert_decimal_total_eq(minimum_mag, positive_zero, "min_mag cleans zero")
  assert_decimal_total_eq(maximum_mag, positive_zero, "max_mag keeps +0")
  assert_true(min_flags == @decimal.DecimalFlags::new())
  assert_true(max_flags == @decimal.DecimalFlags::new())
  assert_true(min_mag_flags == @decimal.DecimalFlags::new())
  assert_true(max_mag_flags == @decimal.DecimalFlags::new())
}

///|
test "decimal official dectest math subsets stay aligned after gda fixes" {
  let exp_ctx9 = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-383,
    e_max=384,
    extended=false,
  )
  let exp_ctx7 = @decimal.DecimalContext::new(
    precision=7,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-383,
    e_max=384,
    extended=false,
  )
  let ln_log_ctx = @decimal.DecimalContext::new(
    precision=16,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-383,
    e_max=384,
    extended=false,
  )
  let power_ctx9 = @decimal.DecimalContext::new(
    precision=9,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
    extended=false,
  )
  let power_ctx10 = @decimal.DecimalContext::new(
    precision=10,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
    extended=false,
  )
  let minmax_ctx = @decimal.DecimalContext::new(
    precision=16,
    decimal_rounding=@decimal.DecimalRoundingMode::HalfEven,
    e_min=-383,
    e_max=384,
    clamp=true,
  )

  let (exp_zero, exp_zero_flags) = decimal_test_operand("0").exp_ctx(exp_ctx9)
  assert_decimal_total_eq(exp_zero, decimal_test_operand("1"), "exp003 result")
  assert_true(exp_zero_flags == @decimal.DecimalFlags::new())

  let (exp_tiny, exp_tiny_flags) = decimal_test_operand("0.1").exp_ctx(exp_ctx7)
  assert_decimal_total_eq(
    exp_tiny,
    decimal_test_operand("1.105171"),
    "exp021 result",
  )
  assert_true(exp_tiny_flags.rounded && exp_tiny_flags.inexact)

  let (exp_underflow, exp_underflow_flags) = decimal_test_operand("-100000000").exp_ctx(
    exp_ctx7,
  )
  assert_true(exp_underflow.is_zero())
  assert_true(exp_underflow_flags.underflow)
  assert_true(exp_underflow_flags.rounded)
  assert_true(exp_underflow_flags.inexact)
  assert_true(exp_underflow_flags.clamped)
  assert_true(exp_underflow_flags.subnormal)

  let (ln_one, ln_one_flags) = decimal_test_operand("1").ln_ctx(ln_log_ctx)
  assert_decimal_total_eq(ln_one, decimal_test_operand("0"), "ln0006 result")
  assert_true(ln_one_flags == @decimal.DecimalFlags::new())

  let (ln_two, ln_two_flags) = decimal_test_operand("2").ln_ctx(ln_log_ctx)
  assert_decimal_total_eq(
    ln_two,
    decimal_test_operand("0.6931471805599453"),
    "ln0008 result",
  )
  assert_true(ln_two_flags.rounded && ln_two_flags.inexact)

  let (log_ten, log_ten_flags) = decimal_test_operand("10").log10_ctx(
    ln_log_ctx,
  )
  assert_decimal_total_eq(log_ten, decimal_test_operand("1"), "log0013 result")
  assert_true(log_ten_flags == @decimal.DecimalFlags::new())

  let (log_two, log_two_flags) = decimal_test_operand("2").log10_ctx(ln_log_ctx)
  assert_decimal_total_eq(
    log_two,
    decimal_test_operand("0.3010299956639812"),
    "log0008 result",
  )
  assert_true(log_two_flags.rounded && log_two_flags.inexact)

  run_decimal_binary_conformance_case(
    "pow028",
    Power,
    "2",
    "32",
    "4294967296",
    power_ctx10,
  )
  let (pow_ten, pow_ten_flags) = decimal_test_operand("10").power_ctx(
    decimal_test_operand("9"),
    power_ctx9,
  )
  assert_eq(pow_ten.compare(decimal_test_operand("1E+9")).to_string(), "0")
  assert_true(pow_ten_flags.rounded)
  assert_false(pow_ten_flags.inexact)

  let negative_zero = decimal_test_operand("-0")
  let positive_zero = decimal_test_operand("0")
  let (min_value, min_flags) = positive_zero.min_ctx(negative_zero, minmax_ctx)
  let (max_value, max_flags) = positive_zero.max_ctx(negative_zero, minmax_ctx)
  assert_decimal_total_eq(min_value, negative_zero, "ddmin031 result")
  assert_decimal_total_eq(max_value, positive_zero, "ddmax031 result")
  assert_true(min_flags == @decimal.DecimalFlags::new())
  assert_true(max_flags == @decimal.DecimalFlags::new())
}

///|
test "checked natural powers preserve unsigned exponent boundaries" {
  let maximum = 0xffff_ffffU
  let binary_context = @lf_arith.ArithmeticContext::new(53)
  let binary_one = @lf_arith.PowNatChecked::pow_nat_checked(
    @bin_float.BinFloat::one(precision=53),
    maximum,
    binary_context,
  ).unwrap()
  assert_eq(binary_one.compare(@bin_float.BinFloat::one(precision=53)), 0)
  let binary_minus_one = @lf_arith.PowNatChecked::pow_nat_checked(
    @bin_float.BinFloat::from_int(-1, precision=53),
    maximum,
    binary_context,
  ).unwrap()
  assert_eq(
    binary_minus_one.compare(@bin_float.BinFloat::from_int(-1, precision=53)),
    0,
  )
  let interval_one = @lf_arith.PowNatChecked::pow_nat_checked(
    @ball_float.BallFloat::from_int(1, precision=53),
    maximum,
    binary_context,
  ).unwrap()
  assert_true(interval_one.is_singleton())
  assert_true(interval_one.contains(@bin_float.BinFloat::one(precision=53)))
  let decimal_result = @lf_arith.PowNatChecked::pow_nat_checked(
    @decimal.Decimal::from_int(1),
    maximum,
    @lf_arith.ArithmeticContext::new(34),
  )
  guard decimal_result is Err(error) else {
    fail("expected Decimal range error")
  }
  assert_true(error.is_unsupported())
}

///|
test "checked clamps reject external invalid bounds without aborting" {
  let binary_value = @bin_float_checked.BinFloatResult::from_int(2)
  let binary_reversed = binary_value
    .clamp(
      min=@bin_float_checked.BinFloatResult::from_int(3),
      max=@bin_float_checked.BinFloatResult::from_int(1),
    )
    .result()
  assert_true(binary_reversed is Err(_))
  let binary_nan = @bin_float_checked.BinFloatResult::ok(
    @bin_float.BinFloat::nan(),
  )
  assert_true(
    binary_value
    .clamp(min=binary_nan, max=@bin_float_checked.BinFloatResult::from_int(3))
    .result()
    is Err(_),
  )
  let decimal_value = @decimal_checked.DecimalResult::from_int(2)
  assert_true(
    decimal_value
    .clamp(
      min=@decimal_checked.DecimalResult::from_int(3),
      max=@decimal_checked.DecimalResult::from_int(1),
    )
    .result()
    is Err(_),
  )
  let decimal_nan = @decimal_checked.DecimalResult::ok(@decimal.Decimal::nan())
  assert_true(
    decimal_value
    .clamp(min=decimal_nan, max=@decimal_checked.DecimalResult::from_int(3))
    .result()
    is Err(_),
  )
}

///|
test "context try constructors totalize invalid public parameters" {
  assert_true(@ball_float.BallContext::try_new(precision=0) is Err(_))
  assert_true(@ball_float.BallContext::try_new(e_min=2, e_max=1) is Err(_))
  assert_true(@bin_float.BinaryContext::try_new(0) is Err(_))
  assert_true(@bin_float.BinaryContext::try_new(53, e_min=-10) is Err(_))
  assert_true(@bin_float.BinaryContext::try_new(53, e_min=1, e_max=0) is Err(_))
  assert_true(@decimal.DecimalContext::try_new(precision=-1) is Err(_))
  assert_true(@decimal.DecimalContext::try_new(e_min=1, e_max=0) is Err(_))
}

///|
test "BallFloat signed powers handle Int minimum" {
  let minimum = -2147483647 - 1
  let one = @ball_float.BallFloat::from_int(1, precision=53).pown(minimum)
  assert_true(one.is_singleton())
  assert_true(one.contains(@bin_float.BinFloat::one(precision=53)))
  let crossing = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(-1, precision=53),
    @bin_float.BinFloat::from_int(1, precision=53),
  ).pown(minimum)
  assert_true(crossing.is_entire())
}
