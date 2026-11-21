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
using @lf_alg {trait FromInteger, trait One, trait Semiring, trait Zero}

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
) -> Result[Int32, ArithmeticError] {
  CompareChecked::compare_checked(x, y)
}

///|
// `luna-generic` 0.4.0 splits this into `normalize`, which picks the integer
// representative, and `FromInteger::from_integer`, the canonical map out of it.
fn[T : FromInteger, S : @lf_alg.Integral] from_integral_generic(x : S) -> T {
  FromInteger::from_integer(@lf_alg.Integral::normalize(x))
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
  exponent : Int32,
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
  if x.is_sign_minus() && !x.coefficient().is_zero() {
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
test "decimal multiply exact paths can use coefficient kernel" {
  let lhs = decimal_test_operand("1234567890123")
  let rhs = decimal_test_operand("987654321")
  let plain = lhs * rhs
  let ctx = @decimal.DecimalContext::new(precision=40)
  let (ctx_value, ctx_flags) = lhs.mul_ctx(rhs, ctx)
  let expected = decimal_test_operand("1219326311247834171483")
  assert_eq(plain.total_order_compare(expected), 0)
  assert_eq(ctx_value.total_order_compare(expected), 0)
  assert_false(ctx_flags.inexact())
}

///|
test "decimal add/sub exact alignment can follow coefficient kernel shifts" {
  let ctx = @decimal.DecimalContext::new(precision=40)

  let lhs = decimal_test_operand("12345678901234567890E+7")
  let rhs = decimal_test_operand("987654321E-5")
  let (sum, sum_flags) = lhs.add_ctx(rhs, ctx)
  let expected_sum = decimal_test_operand("123456789012345678900009876.54321")
  assert_eq(sum.total_order_compare(expected_sum), 0)
  assert_false(sum_flags.inexact())

  let minuend = decimal_test_operand("1.00000000000000000000E+12")
  let subtrahend = decimal_test_operand("999999999999.9999999999")
  let (difference, difference_flags) = minuend.sub_ctx(subtrahend, ctx)
  let expected_difference = decimal_test_operand("0.0000000001")
  assert_eq(difference.total_order_compare(expected_difference), 0)
  assert_false(difference_flags.inexact())
}

///|
#derive(Eq)
enum DecimalConformanceOp {
  Add
  Subtract
  Multiply
  Sqrt
  Power
  Divide
}

///|
fn decimal_conformance_operand(
  id : String,
  src : String,
) -> @decimal.Decimal raise {
  let normalized = @decimal.Decimal::from_string(src, precision=64)
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
    return @decimal.Decimal::inf(negative~, precision=64)
  }
  fail("invalid decimal conformance operand: " + id + " " + src)
}

///|
fn assert_decimal_conformance_value(
  id : String,
  actual : @decimal.Decimal,
  expected_src : String,
) -> Unit raise {
  let expected = decimal_conformance_operand(id, expected_src)
  assert_eq(actual.total_order_compare(expected), 0, msg=id + " result")
}

///|
fn assert_decimal_conformance_flags(
  id : String,
  flags : @decimal.DecimalFlags,
  inexact~ : Bool = false,
  invalid_operation~ : Bool = false,
  division_by_zero~ : Bool = false,
  overflow~ : Bool = false,
  underflow~ : Bool = false,
) -> Unit raise {
  assert_eq(
    flags.inexact().to_string(),
    inexact.to_string(),
    msg=id + " inexact",
  )
  assert_eq(
    flags.invalid_operation().to_string(),
    invalid_operation.to_string(),
    msg=id + " invalid_operation",
  )
  assert_eq(
    flags.division_by_zero().to_string(),
    division_by_zero.to_string(),
    msg=id + " division_by_zero",
  )
  assert_eq(
    flags.overflow().to_string(),
    overflow.to_string(),
    msg=id + " overflow",
  )
  assert_eq(
    flags.underflow().to_string(),
    underflow.to_string(),
    msg=id + " underflow",
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
  inexact~ : Bool = false,
  invalid_operation~ : Bool = false,
  division_by_zero~ : Bool = false,
  overflow~ : Bool = false,
  underflow~ : Bool = false,
) -> Unit raise {
  let lhs = decimal_conformance_operand(id, lhs_src)
  let rhs = decimal_conformance_operand(id, rhs_src)
  let (actual, flags) = match op {
    Add => lhs.add_ctx(rhs, ctx)
    Subtract => lhs.sub_ctx(rhs, ctx)
    Multiply => lhs.mul_ctx(rhs, ctx)
    Sqrt => fail("binary runner cannot execute unary case: " + id)
    Power => lhs.pow_ctx(rhs, ctx)
    Divide => lhs.div_ctx(rhs, ctx)
  }
  assert_decimal_conformance_value(id, actual, expected)
  assert_decimal_conformance_flags(
    id,
    flags,
    inexact~,
    invalid_operation~,
    division_by_zero~,
    overflow~,
    underflow~,
  )
}

///|
fn run_decimal_unary_conformance_case(
  id : String,
  op : DecimalConformanceOp,
  operand_src : String,
  expected : String,
  ctx : @decimal.DecimalContext,
  inexact~ : Bool = false,
  invalid_operation~ : Bool = false,
  division_by_zero~ : Bool = false,
  overflow~ : Bool = false,
  underflow~ : Bool = false,
) -> Unit raise {
  let operand = decimal_conformance_operand(id, operand_src)
  let (actual, flags) = match op {
    Sqrt => operand.sqrt_ctx(ctx)
    Add | Subtract | Multiply | Power | Divide =>
      fail("unary runner cannot execute binary case: " + id)
  }
  assert_decimal_conformance_value(id, actual, expected)
  assert_decimal_conformance_flags(
    id,
    flags,
    inexact~,
    invalid_operation~,
    division_by_zero~,
    overflow~,
    underflow~,
  )
}

///|
test "binary normalizes powers of two" {
  let x = binary_test_make(12N, 0, 16)
  assert_eq(binary_test_signed_bigint(x), 3N)
  assert_eq(x.exponent2(), 2)
}

///|
test "binary basic arithmetic stays exact on small dyadics" {
  let a = binary_test_make(3N, -1, 16)
  let b = binary_test_make(5N, -1, 16)
  assert_eq((a + b).to_string(), "1p2")
  assert_eq((a - b).to_string(), "-1p0")
  assert_eq((a * b).to_string(), "15p-2")
}

///|
test "binary checked division reports division by zero" {
  let result = @lf_arith.DivChecked::div_checked(
    @binary.Binary::from_int(1, precision=16),
    @binary.Binary::zero(precision=16),
    @lf_arith.ArithmeticContext::new(16),
  )
  match result {
    Ok(_) => fail("expected division by zero")
    Err(err) => assert_true(err.is_division_by_zero())
  }
}

///|
test "binary sqrt and pown expose core arithmetic extensions" {
  let root = @binary.Binary::from_int(4, precision=24).sqrt()
  let power = binary_test_make(3N, -1, 24).pown(3)
  assert_eq(root.to_string(), "1p1")
  assert_eq(power.to_string(), "27p-3")
}

///|
test "binary implements generic checked arithmetic traits" {
  match
    sqrt_checked_generic(@binary.Binary::from_int(9, precision=24), checked_ctx) {
    Ok(value) => assert_eq(value.to_string(), "3p0")
    Err(_) => fail("expected generic checked sqrt to succeed")
  }
  match
    div_checked_generic(
      @binary.Binary::from_int(9, precision=24),
      @binary.Binary::from_int(2, precision=24),
      checked_ctx,
    ) {
    Ok(value) => assert_true(value.to_string() != "0")
    Err(_) => fail("expected generic checked division to succeed")
  }
  match
    compare_checked_generic(
      @binary.Binary::from_int(1, precision=24),
      @binary.Binary::from_int(2, precision=24),
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
      @binary.Binary::zero(precision=24),
      -1,
      checked_ctx,
    ) {
    Ok(_) => fail("expected negative power of zero to fail")
    Err(err) => assert_true(err.is_division_by_zero())
  }
}

///|
test "binary coefficient constructor normalizes canonical dyadics" {
  let value = @binary.Binary::from_coefficient(
    @binary.BinCoeff::from_uint64(12UL),
  )
  assert_true(value.identical(binary_test_make(12N, 0, 53).normalized()))
  assert_eq(binary_test_signed_bigint(value), 3N)
  assert_eq(value.exponent2(), 2)
}

///|
test "decimal parses and normalizes" {
  let x = @decimal.Decimal::from_string("0012.3400", precision=20)
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
  match @decimal.Decimal::from_string("-Infinity", precision=12) {
    Ok(value) => {
      assert_true(value.classify() == @lf_arith.FpClass::Infinity)
      assert_true(value.is_sign_minus())
    }
    Err(_) => fail("expected infinity parse to succeed")
  }

  match @decimal.Decimal::from_string("NaN0012", precision=4) {
    Ok(value) => {
      assert_true(value.is_quiet_nan())
      assert_eq(value.nan_payload(), 12N)
    }
    Err(_) => fail("expected quiet NaN parse to succeed")
  }

  match @decimal.Decimal::from_string("-sNaN9", precision=8) {
    Ok(value) => {
      assert_true(value.is_signaling_nan())
      assert_true(value.is_sign_minus())
      assert_eq(value.nan_payload(), 9N)
    }
    Err(_) => fail("expected signaling NaN parse to succeed")
  }

  match @decimal.Decimal::from_string("sNaN12x", precision=8) {
    Ok(_) => fail("expected malformed signaling NaN payload to fail")
    Err(err) => assert_true(err.is_parse_error())
  }

  match @decimal.Decimal::from_string("NaN12345", precision=4) {
    Ok(_) => fail("expected quiet NaN payload beyond precision to fail")
    Err(err) => assert_true(err.is_parse_error())
  }

  match @decimal.Decimal::from_string("-sNaN12345", precision=4) {
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
  assert_false(pos.is_sign_minus())
  assert_true(neg.is_sign_minus())
  assert_eq(pos.to_string(), "0.00")
  assert_eq(neg.to_string(), "-0.00")
  assert_true(pos == neg)
  assert_true(
    neg
    .with_precision(4, @decimal.DecimalRoundingMode::RoundTiesToEven)
    .is_negative_zero(),
  )
  assert_true(neg.normalized().is_negative_zero())
  assert_eq(neg.normalized().to_string(), "-0")
  assert_false(neg.abs().is_negative_zero())
  assert_true(pos.neg().is_negative_zero())
}

///|
test "decimal observers distinguish sign from signedness on specials" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let neg_zero = @decimal.Decimal::negative_zero(precision=8)
  let pos_inf = @decimal.Decimal::inf(precision=8)
  let neg_inf = @decimal.Decimal::inf(negative=true, precision=8)
  let qnan = @decimal.Decimal::quiet_nan(payload=7N, negative=true, precision=8)
  let snan = @decimal.Decimal::signaling_nan(
    payload=9N,
    negative=true,
    precision=8,
  )
  assert_true(neg_zero.signum() == @def.Sign::Zero)
  assert_true(pos_inf.signum() == @def.Sign::Positive)
  assert_true(neg_inf.signum() == @def.Sign::Negative)
  assert_true(qnan.signum() == @def.Sign::Zero)
  assert_true(snan.signum() == @def.Sign::Zero)
  assert_true(qnan.is_sign_minus())
  assert_true(snan.is_sign_minus())
  assert_true(qnan.class_of(ctx) == @def.IeeeClass::QuietNaN)
  assert_true(snan.class_of(ctx) == @def.IeeeClass::SignalingNaN)
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
  // IEEE 754-2019 6.3: the sign of a zero product is the xor of the signs
  assert_true((neg_two * pos).is_negative_zero())
  assert_true((neg / two).is_negative_zero())
}

///|
test "decimal context zero addition canonicalizes ordinary zero results" {
  let ctx = @decimal.DecimalContext::new(precision=9)
  let cents_zero = @decimal.Decimal::from_string("0.00", precision=12).unwrap()
  let unit_zero = @decimal.Decimal::zero(precision=12)
  let (sum, flags) = cents_zero.add_ctx(unit_zero, ctx)
  assert_eq(sum.to_string(), "0.00")
  assert_false(flags.inexact())
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
  let (lhs_sum, _) = one.add_ctx(tenth_zero, ctx)
  let (rhs_sum, _) = tenth_zero.add_ctx(one, ctx)
  let (medium_sum, _) = medium.add_ctx(unit_zero, ctx)
  let (huge_sum, _) = huge.add_ctx(unit_zero, ctx)
  assert_eq(lhs_sum.to_string(), "1.0")
  assert_eq(rhs_sum.to_string(), "1.0")
  assert_eq(medium_sum.to_string(), "-500000000")
  assert_eq(huge_sum.to_string(), "-5.00000000E+9")
}

///|
test "decimal add matches official tryzeros cohort cases" {
  let ctx = @decimal.DecimalContext::new(
    precision=7,
    e_max=92,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
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
  )
  run_decimal_binary_conformance_case(
    "add363",
    Add,
    "10000E+1",
    "10000E-50",
    "100000.0",
    ctx,
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
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
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
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
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
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
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
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToEven,
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
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToEven,
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
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToEven,
  )
  run_decimal_binary_conformance_case(
    "dddiv272",
    Divide,
    "1",
    "0.99e384",
    "1.01010101010101E-384",
    ctx,
    inexact=true,
    underflow=true,
  )
  run_decimal_binary_conformance_case(
    "dddiv273",
    Divide,
    "1",
    "0.9999999999999999e384",
    "1.00000000000000E-384",
    ctx,
    inexact=true,
    underflow=true,
  )
}

///|
test "decimal divide keeps enough working digits for rounded reciprocals" {
  let ctx = @decimal.DecimalContext::new(
    precision=16,
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToEven,
  )
  run_decimal_binary_conformance_case(
    "dddiv442",
    Divide,
    "1",
    "12345678000",
    "8.100000664200054E-11",
    ctx,
    inexact=true,
  )
  run_decimal_binary_conformance_case(
    "dddiv444",
    Divide,
    "1",
    "1234567800",
    "8.100000664200054E-10",
    ctx,
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
  assert_false(flags.invalid_operation())
}

///|
test "decimal absorbed subtract half-up ties keep away-from-zero representative" {
  let dd_ctx = @decimal.DecimalContext::new(
    precision=16,
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
  )
  run_decimal_binary_conformance_case(
    "ddsub508",
    Subtract,
    "1231234567456789",
    "0.5",
    "1231234567456789",
    dd_ctx,
    inexact=true,
  )
  run_decimal_binary_conformance_case(
    "ddsub608",
    Subtract,
    "0.5",
    "1231234567456789",
    "-1231234567456789",
    dd_ctx,
    inexact=true,
  )
}

///|
test "decimal context clamps zero exponent at upper cohort bound" {
  let ctx = @decimal.DecimalContext::new(precision=16, e_max=384)
  let pos = @decimal.Decimal::from_string("0E+500", precision=32).unwrap()
  let neg = @decimal.Decimal::from_string("-0E+500", precision=32).unwrap()
  let (pos_value, _) = pos.apply_ctx(ctx)
  let (neg_value, _) = neg.apply_ctx(ctx)
  assert_eq(
    pos_value
    .total_order_compare(
      @decimal.Decimal::from_string("0E+369", precision=32).unwrap(),
    )
    .to_string(),
    "0",
  )
  assert_eq(
    neg_value
    .total_order_compare(
      @decimal.Decimal::from_string("-0E+369", precision=32).unwrap(),
    )
    .to_string(),
    "0",
  )
}

///|
// oracle: A
// source: values written out: the fold-down pads the coefficient with zeros and loses no digit, so the result
//   is exact and no exception is raised (IEEE 754-2019 7.4 to 7.6); the flags are asserted as written
// shares: Decimal::from_string and total_order_compare read the written expected texts
test "decimal apply_ctx clamps finite fold-down without rounded flag" {
  let ctx = @decimal.DecimalContext::new(precision=16, e_max=384)
  let pos = @decimal.Decimal::from_string("1.23E+384", precision=32).unwrap()
  let neg_zero = @decimal.Decimal::from_string("-0E+500", precision=32).unwrap()
  let (pos_value, pos_flags) = pos.apply_ctx(ctx)
  let (neg_zero_value, neg_zero_flags) = neg_zero.apply_ctx(ctx)
  for flags in [pos_flags, neg_zero_flags] {
    assert_false(flags.inexact())
    assert_false(flags.overflow())
    assert_false(flags.underflow())
    assert_false(flags.has_error())
  }
  assert_eq(
    pos_value
    .total_order_compare(
      @decimal.Decimal::from_string("1.230000000000000E+384", precision=32).unwrap(),
    )
    .to_string(),
    "0",
  )
  assert_eq(
    neg_zero_value
    .total_order_compare(
      @decimal.Decimal::from_string("-0E+369", precision=32).unwrap(),
    )
    .to_string(),
    "0",
  )
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
  assert_true(quiet.is_sign_minus())
  assert_eq(quiet.nan_payload(), 42N)
  assert_eq(quiet.to_string(), "-nan42")
  assert_true(signaling.is_signaling_nan())
  assert_false(signaling.is_quiet_nan())
  assert_eq(signaling.nan_payload(), 7N)
  assert_eq(signaling.to_string(), "snan7")
  assert_true(quiet == signaling)
  assert_true(
    signaling
    .with_precision(3, @decimal.DecimalRoundingMode::RoundTiesToEven)
    .is_signaling_nan(),
  )
}

///|
test "decimal addition propagates nan payloads" {
  let ctx = @decimal.DecimalContext::new(precision=9)
  let quiet = @decimal.Decimal::quiet_nan(payload=17N, precision=12)
  let (quiet_sum, quiet_flags) = quiet.add_ctx(
    @decimal.Decimal::inf(negative=true),
    ctx,
  )
  assert_eq(
    quiet_sum
    .total_order_compare(@decimal.Decimal::quiet_nan(payload=17N, precision=9))
    .to_string(),
    "0",
  )
  assert_false(quiet_flags.invalid_operation())
  let signaling = @decimal.Decimal::signaling_nan(payload=23N, precision=12)
  let (signaled, signal_flags) = @decimal.Decimal::one().add_ctx(signaling, ctx)
  assert_eq(
    signaled
    .total_order_compare(@decimal.Decimal::quiet_nan(payload=23N, precision=9))
    .to_string(),
    "0",
  )
  assert_true(signal_flags.invalid_operation())
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
  assert_true(quiet_product.is_sign_minus())
  assert_eq(quiet_product.nan_payload(), 12345N)
  assert_false(quiet_flags.invalid_operation())
  assert_eq(signaled.to_string(), "nan23")
  assert_true(signaled.is_quiet_nan())
  assert_false(signaled.is_signaling_nan())
  assert_eq(signaled.nan_payload(), 23N)
  assert_true(signal_flags.invalid_operation())
}

///|
test "decimal multiply official0 deepest overflow rows keep subset flags" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    e_max=999999999,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
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
    assert_true(flags.overflow(), msg=rhs_src + " overflow")
    assert_true(flags.inexact(), msg=rhs_src + " inexact")
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
  assert_true(quiet_quotient.is_sign_minus())
  assert_eq(quiet_quotient.nan_payload(), 95N)
  assert_false(quiet_flags.invalid_operation())
  assert_eq(signaled.to_string(), "nan93")
  assert_true(signaled.is_quiet_nan())
  assert_false(signaled.is_signaling_nan())
  assert_eq(signaled.nan_payload(), 93N)
  assert_true(signal_flags.invalid_operation())
}

///|
test "IEEE decimal division preserves first nan payload and signals snans" {
  let ctx = @decimal.DecimalContext::new(precision=9)
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
    "NaN95",
    ctx,
    invalid_operation=true,
  )
  run_decimal_binary_conformance_case(
    "divx899",
    DecimalConformanceOp::Divide,
    "-NaN",
    "-sNaN89",
    "-NaN",
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
  assert_true(add_result.is_sign_minus())
  assert_eq(add_result.nan_payload(), 17N)
  assert_eq(mul_result.to_string(), "nan23")
  assert_true(mul_result.is_quiet_nan())
  assert_false(mul_result.is_signaling_nan())
  assert_eq(mul_result.nan_payload(), 23N)
  assert_eq(div_result.to_string(), "-nan17")
  assert_true(div_result.is_quiet_nan())
  assert_true(div_result.is_sign_minus())
  assert_eq(div_result.nan_payload(), 17N)
}

///|
test "IEEE decimal fma preserves first nan payload and signals snans" {
  let ctx = @decimal.DecimalContext::new(precision=9, e_max=999999)
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
  assert_false(quiet_flags.invalid_operation())
  assert_eq(signal_result.to_string(), "nan7")
  assert_eq(signal_result.nan_payload(), 7N)
  assert_true(signal_flags.invalid_operation())
  assert_eq(negative_signal_result.to_string(), "-nan23")
  assert_true(negative_signal_result.is_sign_minus())
  assert_eq(negative_signal_result.nan_payload(), 23N)
  assert_true(negative_signal_flags.invalid_operation())
}

///|
test "decimal fma handles infinite addends with direct infinity semantics" {
  let ctx = @decimal.DecimalContext::new(precision=9, e_max=999999)
  let pos_inf = @decimal.Decimal::inf(precision=16)
  let neg_inf = @decimal.Decimal::inf(negative=true, precision=16)
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
  assert_false(finite_plus_inf.is_sign_minus())
  assert_false(finite_plus_inf_flags.invalid_operation())
  assert_true(matching_inf.is_infinite())
  assert_false(matching_inf.is_sign_minus())
  assert_false(matching_inf_flags.invalid_operation())
  assert_true(negative_finite_plus_inf.is_infinite())
  assert_false(negative_finite_plus_inf.is_sign_minus())
  assert_false(negative_finite_plus_inf_flags.invalid_operation())
  assert_true(opposite_inf.is_nan())
  assert_true(opposite_inf_flags.invalid_operation())
}

///|
test "decimal fma preserves directed overflow when tiny addend cannot affect result" {
  let ctx = @decimal.DecimalContext::new(
    precision=34,
    e_max=6144,
    rounding=@decimal.DecimalRoundingMode::RoundTowardPositive,
  )
  let ctx_negative = ctx.with_rounding(
    @decimal.DecimalRoundingMode::RoundTowardNegative,
  )
  let lhs = @decimal.Decimal::from_string("-9E6144", precision=64).unwrap()
  let positive_lhs = @decimal.Decimal::from_string("9E6144", precision=64).unwrap()
  let rhs = @decimal.Decimal::from_string("10", precision=64).unwrap()
  let third = @decimal.Decimal::from_string("1", precision=64).unwrap()
  let (positive, positive_flags) = positive_lhs.fma_ctx(rhs, third, ctx)
  let (negative, negative_flags) = lhs.fma_ctx(rhs, third, ctx_negative)
  assert_true(positive.is_infinite())
  assert_false(positive.is_sign_minus())
  assert_true(positive_flags.overflow())
  assert_true(positive_flags.inexact())
  assert_true(negative.is_infinite())
  assert_true(negative.is_sign_minus())
  assert_true(negative_flags.overflow())
  assert_true(negative_flags.inexact())
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
  let result = div_checked_generic(
    @decimal.Decimal::from_int(1, precision=20),
    @decimal.Decimal::zero(precision=20),
    ArithmeticContext::new(20),
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
  match div_checked_generic(zero, zero, ArithmeticContext::new(20)) {
    Ok(_) => fail("expected zero divided by zero to be a domain error")
    Err(err) => assert_true(err.is_domain_error())
  }
  match
    div_checked_generic(
      @decimal.Decimal::one(precision=20),
      snan,
      ArithmeticContext::new(20),
    ) {
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
fn[T] checked_special_render(
  result : Result[T, ArithmeticError],
  is_nan : (T) -> Bool,
  is_infinite : (T) -> Bool,
  is_zero : (T) -> Bool,
  is_negative : (T) -> Bool,
) -> String {
  match result {
    Err(err) =>
      if err.is_division_by_zero() {
        "err:div0"
      } else if err.is_domain_error() {
        "err:invalid"
      } else {
        "err:other"
      }
    Ok(value) => {
      let sign = if is_negative(value) { "-" } else { "+" }
      if is_nan(value) {
        "ok:nan"
      } else if is_infinite(value) {
        "ok:" + sign + "inf"
      } else if is_zero(value) {
        "ok:" + sign + "0"
      } else {
        "ok:" + sign + "fin"
      }
    }
  }
}

///|
/// The issue 262 rows: dividend, divisor and the IEEE 754-2019 outcome.
fn checked_special_division_rows() -> Array[(String, String, String)] {
  [
    ("NaN", "0", "ok:nan"), // 6.2
    ("0", "0", "err:invalid"), // 7.2 e)
    ("Infinity", "0", "ok:+inf"), // 7.3 needs a finite dividend
    ("Infinity", "Infinity", "err:invalid"), // 7.2 e)
    ("1", "0", "err:div0"), // 7.3
    ("-1", "-0", "err:div0"), // 7.3
    ("sNaN", "1", "err:invalid"), // 7.2 a)
  ]
}

///|
fn checked_special_bin(text : String) -> @binary.Binary {
  match text {
    "NaN" => @binary.Binary::nan(precision=24)
    "-NaN" => @binary.Binary::quiet_nan(negative=true, precision=24)
    "sNaN" => @binary.Binary::signaling_nan(precision=24)
    "Infinity" => @binary.Binary::inf(precision=24)
    "-0" => @binary.Binary::negative_zero(precision=24)
    "0" => @binary.Binary::zero(precision=24)
    "1" => @binary.Binary::from_int(1, precision=24)
    "-1" => @binary.Binary::from_int(-1, precision=24)
    _ => abort("unknown operand " + text)
  }
}

///|
test "binary and decimal checked instances agree on special values (#262)" {
  let bin_render = fn(result) {
    checked_special_render(
      result,
      fn(x : @binary.Binary) { x.classify() == @def.FpClass::NaN },
      fn(x) { x.classify() == @def.FpClass::Infinity },
      fn(x) { x.classify() == @def.FpClass::Finite && x.is_zero() },
      fn(x) { x.is_sign_minus() },
    )
  }
  let dec_render = fn(result) {
    checked_special_render(
      result,
      fn(x : @decimal.Decimal) { x.classify() == @def.FpClass::NaN },
      fn(x) { x.classify() == @def.FpClass::Infinity },
      fn(x) { x.classify() == @def.FpClass::Finite && x.is_zero() },
      fn(x) { x.is_sign_minus() },
    )
  }
  let gda_render = fn(result) {
    checked_special_render(
      result,
      fn(x : @decimal_gda.Decimal) { x.classify() == @def.FpClass::NaN },
      fn(x) { x.classify() == @def.FpClass::Infinity },
      fn(x) { x.classify() == @def.FpClass::Finite && x.is_zero() },
      fn(x) { x.is_signed() },
    )
  }
  let dec = fn(text) {
    @decimal.Decimal::from_string(text, precision=20).unwrap()
  }
  let gda = fn(text) {
    @decimal_gda.Decimal::from_string(text, precision=20).unwrap()
  }
  for row in checked_special_division_rows() {
    let (a, b, expected) = row
    let label = a + " / " + b
    assert_eq(
      label +
      " " +
      bin_render(
        div_checked_generic(
          checked_special_bin(a),
          checked_special_bin(b),
          checked_ctx,
        ),
      ),
      label + " " + expected,
    )
    assert_eq(
      label + " " + dec_render(div_checked_generic(dec(a), dec(b), checked_ctx)),
      label + " " + expected,
    )
    assert_eq(
      label + " " + gda_render(div_checked_generic(gda(a), gda(b), checked_ctx)),
      label + " " + expected,
    )
  }
  // sqrt(-NaN): the sign bit of a quiet NaN does not make it negative (6.2).
  assert_eq(
    bin_render(sqrt_checked_generic(checked_special_bin("-NaN"), checked_ctx)),
    "ok:nan",
  )
  assert_eq(
    dec_render(sqrt_checked_generic(dec("-NaN"), checked_ctx)),
    "ok:nan",
  )
  assert_eq(
    gda_render(sqrt_checked_generic(gda("-NaN"), checked_ctx)),
    "ok:nan",
  )
}

///|
test "decimal conversion preserves dyadics exactly" {
  let d = @decimal.Decimal::from_string("0.375", precision=20).unwrap()
  let x = d.to_binary(precision=20)
  assert_eq(x.to_string(), "3p-3")
  assert_eq(@decimal.Decimal::from_binary(x, precision=20).to_string(), "0.375")
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
  assert_true(from_double_pos.is_quiet_nan())
  assert_false(from_double_pos.is_sign_minus())
  assert_true(from_double_neg.is_quiet_nan())
  assert_true(from_double_neg.is_sign_minus())
  assert_true(from_float_neg.is_quiet_nan())
  assert_true(from_float_neg.is_sign_minus())
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
  assert_eq(ds.total_order_compare(expected).to_string(), "0")
  assert_eq(dd.total_order_compare(expected).to_string(), "0")
  assert_eq(dq.total_order_compare(expected).to_string(), "0")

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
    .total_order_compare(
      @decimal.Decimal::from_string("9.999999E+96", precision=64).unwrap(),
    )
    .to_string(),
    "0",
  )
  assert_eq(
    noncanonical128
    .total_order_compare(
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
  assert_true(decimal32 == @decimal.DecimalContext::decimal32())
  assert_true(decimal64 == @decimal.DecimalContext::decimal64())
  assert_true(decimal128 == @decimal.DecimalContext::decimal128())
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
  assert_eq(plain32.total_order_compare(expected).to_string(), "0")
  assert_eq(plain.total_order_compare(expected).to_string(), "0")
  assert_eq(plain128.total_order_compare(expected).to_string(), "0")
  assert_eq(spaced32.total_order_compare(expected).to_string(), "0")
  assert_eq(spaced.total_order_compare(expected).to_string(), "0")
  assert_eq(tabbed.total_order_compare(expected).to_string(), "0")
  assert_eq(tabbed128.total_order_compare(expected).to_string(), "0")

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
  assert_true(bad_length is Err(_))
  assert_true(
    @decimal.DecimalInterchange::from_hex(
      "#A23003D",
      @decimal.DecimalInterchangeFormat::Decimal32,
    )
    is Err(_),
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
    is Err(_),
  )
  match bad_digit {
    Err(_) => ()
    Ok(_) => fail("expected invalid interchange digit to be rejected")
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
  let (encoded32, _) = value32.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  let (encoded64, _) = value64.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (encoded128, _) = value128.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  assert_eq(encoded32, "#47F4C000")
  assert_eq(encoded64, "#47FD300000000000")
  assert_eq(encoded128, "#47FFD300000000000000000000000000")
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
}

///|
test "decimal interchange from_decimal matches special encode results and flags" {
  let inf = @decimal.Decimal::inf(negative=true, precision=32)
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
  assert_false(inf.is_sign_minus())
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
  assert_false(flags.invalid_operation())
  let quiet = @decimal.Decimal::quiet_nan(
    payload=12345N,
    negative=true,
    precision=16,
  )
  let (quiet_bits, quiet_flags) = quiet.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  assert_eq(quiet_bits, "#FC000000000049C5")
  assert_false(quiet_flags.invalid_operation())

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
  assert_true(qnan32.is_quiet_nan())
  assert_false(qnan32.is_sign_minus())
  assert_eq(qnan32.nan_payload(), 12345N)
  assert_true(neg_qnan32.is_quiet_nan())
  assert_true(neg_qnan32.is_sign_minus())
  assert_eq(neg_qnan32.nan_payload(), 12345N)
  assert_true(snan128.is_signaling_nan())
  assert_false(snan128.is_sign_minus())
  assert_eq(snan128.nan_payload(), 12345N)
  assert_true(neg_snan128.is_signaling_nan())
  assert_true(neg_snan128.is_sign_minus())
  assert_eq(neg_snan128.nan_payload(), 12345N)
}

///|
test "decimal interchange special roundtrips preserve class sign and payload across formats" {
  let neg_inf = @decimal.Decimal::inf(negative=true, precision=32)
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
  assert_true(inf32.is_sign_minus())
  assert_true(inf64.is_sign_minus())
  assert_true(inf128.is_sign_minus())

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
  assert_true(qnan32.is_quiet_nan())
  assert_true(qnan64.is_quiet_nan())
  assert_true(qnan128.is_quiet_nan())
  assert_true(qnan32.is_sign_minus())
  assert_true(qnan64.is_sign_minus())
  assert_true(qnan128.is_sign_minus())
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
  assert_true(snan32.is_signaling_nan())
  assert_true(snan64.is_signaling_nan())
  assert_true(snan128.is_signaling_nan())
  assert_true(snan32.is_sign_minus())
  assert_true(snan64.is_sign_minus())
  assert_true(snan128.is_sign_minus())
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
  assert_false(dd_quiet_flags.invalid_operation())
  assert_eq(dd_signal_bits, "#7C00FF3FCFF3FCFF")
  assert_true(dd_signal_flags.invalid_operation())
  assert_eq(dq_quiet_bits, "#7C003F3FCFF3FCFF0000000000000000")
  assert_false(dq_quiet_flags.invalid_operation())
  assert_eq(dq_signal_bits, "#7C000FFFCFF3FCFF0000000000000000")
  assert_true(dq_signal_flags.invalid_operation())
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
  assert_eq(raw.to_decimal().total_order_compare(expected).to_string(), "0")
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
  assert_eq(
    raw128.to_decimal().total_order_compare(expected128).to_string(),
    "0",
  )
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
  assert_false(reencoded_flags32.invalid_operation())
  assert_false(reencoded_flags32.overflow())
  assert_false(reencoded_flags32.underflow())
  assert_false(reencoded_flags32.inexact())
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

  assert_eq(raw32.to_decimal().total_order_compare(expected32).to_string(), "0")
  assert_eq(
    neg_raw32.to_decimal().total_order_compare(expected32_negative).to_string(),
    "0",
  )
  assert_eq(raw32.canonical().to_hex(), "#77F3FF3F")
  assert_eq(neg_raw32.canonical().to_hex(), "#F7F3FF3F")
  assert_eq(expected32_bits, "#77F3FF3F")
  assert_eq(expected32_negative_bits, "#F7F3FF3F")
  assert_false(expected32_flags.invalid_operation())
  assert_false(expected32_flags.inexact())
  assert_false(expected32_negative_flags.invalid_operation())
  assert_false(expected32_negative_flags.inexact())
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

  assert_eq(
    low_extra.to_decimal().total_order_compare(expected32).to_string(),
    "0",
  )
  assert_eq(
    high_extra.to_decimal().total_order_compare(expected32).to_string(),
    "0",
  )
  assert_eq(
    both_extra.to_decimal().total_order_compare(expected32).to_string(),
    "0",
  )
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
  assert_true(qnan.is_quiet_nan())
  assert_true(qnan.is_sign_minus())
  assert_eq(qnan.nan_payload(), 999999999999999N)
  assert_true(snan.is_signaling_nan())
  assert_true(snan.is_sign_minus())
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
  assert_true(qnan32.is_quiet_nan())
  assert_true(qnan32.is_sign_minus())
  assert_eq(qnan32.nan_payload(), 12345N)
  assert_true(snan32.is_signaling_nan())
  assert_true(snan32.is_sign_minus())
  assert_eq(snan32.nan_payload(), 12345N)
  assert_true(qnan128.is_quiet_nan())
  assert_true(qnan128.is_sign_minus())
  assert_eq(qnan128.nan_payload(), 12345N)
  assert_true(snan128.is_signaling_nan())
  assert_true(snan128.is_sign_minus())
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
  assert_eq(finite.abs().to_hex(), "#77FFFF3FCFF3FCFF")
  assert_eq(neg_finite.abs().to_hex(), "#77FFFF3FCFF3FCFF")
  assert_eq(finite.neg().to_hex(), "#F7FFFF3FCFF3FCFF")
  assert_eq(qnan.neg().to_hex(), "#7C03FF3FCFF3FCFF")
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
  assert_eq(neg_qnan.abs().to_hex(), "#7C03FF3FCFF3FCFF")
  assert_eq(pos_inf.neg().to_hex(), "#F800000000000000")
  assert_eq(neg_qnan.copy_sign(pos_inf).to_hex(), "#7C03FF3FCFF3FCFF")

  let neg_qnan32 = @decimal.DecimalInterchange::from_hex(
    "#FC0049C5",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let qnan32_abs = neg_qnan32.abs().to_decimal()
  assert_true(qnan32_abs.is_quiet_nan())
  assert_false(qnan32_abs.is_sign_minus())
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
  assert_true(snan128_signed.is_signaling_nan())
  assert_false(snan128_signed.is_sign_minus())
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
  assert_eq(qnan32.abs().to_hex(), "#7C0049C5")
  assert_eq(pos_inf32.neg().to_hex(), "#F8000000")
  assert_eq(neg_inf32.abs().to_hex(), "#78000000")
  assert_eq(qnan32.copy_sign(pos_inf32).to_hex(), "#7C0049C5")
  let finite32_negative = finite32.neg().to_decimal()
  let qnan32_positive = qnan32.abs().to_decimal()
  let inf32_negative = pos_inf32.neg().to_decimal()
  let expected32_negative = @decimal.Decimal::from_string(
    "-9.999999E+96",
    precision=64,
  ).unwrap()
  assert_eq(finite32.neg().to_hex(), "#F7F3FCFF")
  assert_eq(
    finite32_negative.total_order_compare(expected32_negative).to_string(),
    "0",
  )
  assert_true(qnan32_positive.is_quiet_nan())
  assert_false(qnan32_positive.is_sign_minus())
  assert_eq(qnan32_positive.nan_payload(), 12345N)
  assert_true(inf32_negative.is_infinite())
  assert_true(inf32_negative.is_sign_minus())

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
  assert_eq(qnan128.abs().to_hex(), "#7C0000000000000000000000000049C5")
  assert_eq(pos_inf128.neg().to_hex(), "#F8000000000000000000000000000000")
  assert_eq(neg_inf128.abs().to_hex(), "#78000000000000000000000000000000")
  assert_eq(
    qnan128.copy_sign(pos_inf128).to_hex(),
    "#7C0000000000000000000000000049C5",
  )
  let finite128_negative = finite128.neg().to_decimal()
  let qnan128_positive = qnan128.abs().to_decimal()
  let inf128_negative = pos_inf128.neg().to_decimal()
  let expected128_negative = @decimal.Decimal::from_string(
    "-9.999999999999999999999999999999999E+6144",
    precision=64,
  ).unwrap()
  assert_eq(
    finite128_negative.total_order_compare(expected128_negative).to_string(),
    "0",
  )
  assert_true(qnan128_positive.is_quiet_nan())
  assert_false(qnan128_positive.is_sign_minus())
  assert_eq(qnan128_positive.nan_payload(), 12345N)
  assert_true(inf128_negative.is_infinite())
  assert_true(inf128_negative.is_sign_minus())
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
  assert_eq(scalar.total_order_compare(expected).to_string(), "0")
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
  assert_true(copied32.to_decimal().is_quiet_nan())

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
  assert_true(copied128.to_decimal().is_signaling_nan())

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
  assert_false(exact_flags.inexact())
  let rounded_source = @decimal.Decimal::from_string("1234", precision=10).unwrap()
  let (rounded, rounded_flags) = rounded_source.add_ctx(
    @decimal.Decimal::zero(precision=10),
    ctx,
  )
  assert_eq(rounded.to_string(), "1.23E+3")
  assert_true(rounded_flags.inexact())
}

///|
test "decimal context reports rounded for discarded trailing zeros" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
  )
  let lhs = @decimal.Decimal::from_string("10000e+9", precision=64).unwrap()
  let rhs = @decimal.Decimal::from_string("700000", precision=64).unwrap()
  let (sum, sum_flags) = lhs.add_ctx(rhs, ctx)
  assert_eq(
    sum
    .total_order_compare(
      @decimal.Decimal::from_string("1.00000007E+13", precision=64).unwrap(),
    )
    .to_string(),
    "0",
  )
  assert_false(sum_flags.inexact())
  let (applied, apply_flags) = @decimal.Decimal::from_string(
      "10000000700000",
      precision=64,
    )
    .unwrap()
    .apply_ctx(ctx)
  assert_eq(
    applied
    .total_order_compare(
      @decimal.Decimal::from_string("1.00000007E+13", precision=64).unwrap(),
    )
    .to_string(),
    "0",
  )
  assert_false(apply_flags.inexact())
}

///|
test "decimal context addition absorbs far smaller operand as sticky" {
  let ctx = @decimal.DecimalContext::new(precision=9)
  let lhs = @decimal.Decimal::from_string("1", precision=64).unwrap()
  let rhs = @decimal.Decimal::from_string("-77e-999", precision=64).unwrap()
  let (sum, flags) = lhs.add_ctx(rhs, ctx)
  let expected = @decimal.Decimal::from_string("1.00000000", precision=64).unwrap()
  assert_eq(sum.total_order_compare(expected).to_string(), "0")
  assert_true(flags.inexact())
}

///|
test "decimal context addition rounds exact dominant operand with sub-ulp addend" {
  let lhs = @decimal.Decimal::from_string("1", precision=64).unwrap()
  let non_boundary = @decimal.Decimal::from_string("1.23456789", precision=64).unwrap()
  let below_half = @decimal.Decimal::from_string("4.99999E-9", precision=64).unwrap()
  let above_half = @decimal.Decimal::from_string("5.00001E-9", precision=64).unwrap()
  let half_up_ctx = @decimal.DecimalContext::new(
    precision=9,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
  )
  let up_ctx = @decimal.DecimalContext::new(
    precision=9,
    rounding=@decimal.DecimalRoundingMode::RoundTowardPositive,
  )
  let down_ctx = @decimal.DecimalContext::new(
    precision=9,
    rounding=@decimal.DecimalRoundingMode::RoundTowardZero,
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
    half_up_below.total_order_compare(
      @decimal.Decimal::from_string("1.00000000", precision=64).unwrap(),
    ),
    0,
  )
  assert_true(half_up_below_flags.inexact())
  assert_eq(
    half_up_above.total_order_compare(
      @decimal.Decimal::from_string("1.00000001", precision=64).unwrap(),
    ),
    0,
  )
  assert_true(half_up_above_flags.inexact())
  assert_eq(
    up_positive.total_order_compare(
      @decimal.Decimal::from_string("1.00000001", precision=64).unwrap(),
    ),
    0,
  )
  assert_true(up_positive_flags.inexact())
  assert_eq(
    down_negative.total_order_compare(
      @decimal.Decimal::from_string("1.23456788", precision=64).unwrap(),
    ),
    0,
  )
  assert_true(down_negative_flags.inexact())
}

///|
test "decimal context reports underflow when tiny exact result rounds normal" {
  let ctx = @decimal.DecimalContext::new(precision=16, e_max=384)
  let lhs = @decimal.Decimal::from_string("1E-383", precision=64).unwrap()
  let rhs = @decimal.Decimal::from_string("1E-400", precision=64).unwrap()
  let (difference, flags) = lhs.sub_ctx(rhs, ctx)
  let expected = @decimal.Decimal::from_string(
    "1.000000000000000E-383",
    precision=64,
  ).unwrap()
  assert_eq(difference.total_order_compare(expected).to_string(), "0")
  assert_true(flags.underflow())
  assert_true(flags.inexact())
}

///|
test "decimal make keeps the zero cohort exponent it is given" {
  let dd_tiny_zero = @decimal.Decimal::make(0N, -398, 64)
  let dq_tiny_zero = @decimal.Decimal::make(0N, -6176, 64)
  assert_eq(dd_tiny_zero.to_string(), "0E-398")
  assert_eq(dq_tiny_zero.to_string(), "0E-6176")
  assert_eq(dd_tiny_zero.exponent10(), -398)
  assert_eq(dq_tiny_zero.exponent10(), -6176)
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
  assert_eq(dd_sum_lhs.total_order_compare(dd_expected).to_string(), "0")
  assert_eq(dd_sum_rhs.total_order_compare(dd_expected).to_string(), "0")
  assert_eq(dq_sum_lhs.total_order_compare(dq_expected).to_string(), "0")
  assert_eq(dq_sum_rhs.total_order_compare(dq_expected).to_string(), "0")
  assert_eq(dd_sum_lhs_bits, "#77FCFF3FCFF3FCFF")
  assert_eq(dd_sum_rhs_bits, "#77FCFF3FCFF3FCFF")
  assert_eq(dq_sum_lhs_bits, "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_eq(dq_sum_rhs_bits, "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_false(dd_sum_lhs_flags.inexact())
  assert_false(dd_sum_rhs_flags.inexact())
  assert_false(dq_sum_lhs_flags.inexact())
  assert_false(dq_sum_rhs_flags.inexact())
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
  assert_eq(dd_diff_lhs.total_order_compare(dd_expected_neg).to_string(), "0")
  assert_eq(dd_diff_rhs.total_order_compare(dd_expected_pos).to_string(), "0")
  assert_eq(dq_diff_lhs.total_order_compare(dq_expected_neg).to_string(), "0")
  assert_eq(dq_diff_rhs.total_order_compare(dq_expected_pos).to_string(), "0")
  assert_eq(dd_diff_lhs_bits, "#F7FCFF3FCFF3FCFF")
  assert_eq(dd_diff_rhs_bits, "#77FCFF3FCFF3FCFF")
  assert_eq(dq_diff_lhs_bits, "#F7FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_eq(dq_diff_rhs_bits, "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_false(dd_diff_lhs_flags.inexact())
  assert_false(dd_diff_rhs_flags.inexact())
  assert_false(dq_diff_lhs_flags.inexact())
  assert_false(dq_diff_rhs_flags.inexact())
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
  assert_eq(dd_sum_lhs.total_order_compare(dd_expected).to_string(), "0")
  assert_eq(dd_sum_rhs.total_order_compare(dd_expected).to_string(), "0")
  assert_eq(dq_sum_lhs.total_order_compare(dq_expected).to_string(), "0")
  assert_eq(dq_sum_rhs.total_order_compare(dq_expected).to_string(), "0")
  assert_eq(dd_sum_lhs_bits, "#77FCFF3FCFF3FCFF")
  assert_eq(dd_sum_rhs_bits, "#77FCFF3FCFF3FCFF")
  assert_eq(dq_sum_lhs_bits, "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_eq(dq_sum_rhs_bits, "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_true(dd_sum_lhs_flags.inexact())
  assert_true(dd_sum_rhs_flags.inexact())
  assert_true(dq_sum_lhs_flags.inexact())
  assert_true(dq_sum_rhs_flags.inexact())
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
  assert_eq(dd_diff_lhs.total_order_compare(dd_expected_neg).to_string(), "0")
  assert_eq(dd_diff_rhs.total_order_compare(dd_expected_pos).to_string(), "0")
  assert_eq(dq_diff_lhs.total_order_compare(dq_expected_neg).to_string(), "0")
  assert_eq(dq_diff_rhs.total_order_compare(dq_expected_pos).to_string(), "0")
  assert_eq(dd_diff_lhs_bits, "#F7FCFF3FCFF3FCFF")
  assert_eq(dd_diff_rhs_bits, "#77FCFF3FCFF3FCFF")
  assert_eq(dq_diff_lhs_bits, "#F7FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_eq(dq_diff_rhs_bits, "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_true(dd_diff_lhs_flags.inexact())
  assert_true(dd_diff_rhs_flags.inexact())
  assert_true(dq_diff_lhs_flags.inexact())
  assert_true(dq_diff_rhs_flags.inexact())
}

///|
test "decimal context zero plus huge finite overflows without scaling zero" {
  let ctx = @decimal.DecimalContext::new(precision=3, e_max=999999999)
  let huge = @decimal.Decimal::from_string("-9.999E+999999999", precision=64).unwrap()
  let (sum, flags) = @decimal.Decimal::zero(precision=64).add_ctx(huge, ctx)
  assert_true(sum.classify() == @lf_arith.FpClass::Infinity)
  assert_true(sum.is_sign_minus())
  assert_true(flags.overflow())
  assert_true(flags.inexact())
}

///|
test "decimal remainder_near matches official0 huge lost-digits representative" {
  let huge_ctx = @decimal.DecimalContext::new(
    precision=9,
    e_max=999999999,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
  )
  let huge_divisor = @decimal.Decimal::from_string("9E+999999999", precision=64).unwrap()
  let (huge_near, huge_near_flags) = @decimal.Decimal::from_string(
      "1.23456789012345E-0",
      precision=64,
    )
    .unwrap()
    .remainder_ctx(huge_divisor, huge_ctx)
  assert_eq(huge_near.to_string(), "1.23456789")
  assert_true(huge_near_flags.inexact())
}

///|
test "decimal context supports round ties to away" {
  let source = @decimal.Decimal::from_string("1.25", precision=12).unwrap()
  let zero = @decimal.Decimal::zero(precision=12)
  let ties_away_ctx = @decimal.DecimalContext::new(
    precision=2,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
  )
  let ties_even_ctx = @decimal.DecimalContext::new(precision=2)
  let (ties_away, ties_away_flags) = source.add_ctx(zero, ties_away_ctx)
  let (ties_even, ties_even_flags) = source.add_ctx(zero, ties_even_ctx)
  assert_eq(ties_away.to_string(), "1.3")
  assert_true(ties_away_flags.inexact())
  assert_eq(ties_even.to_string(), "1.2")
  assert_true(ties_even_flags.inexact())
  assert_true(
    @decimal.DecimalRoundingMode::RoundTiesToAway.to_arithmetic() is None,
  )
  assert_true(
    @decimal.DecimalRoundingMode::RoundTiesToEven.to_arithmetic()
    is Some(@lf_arith.RoundingMode::ToNearestEven),
  )
  assert_true(
    @decimal.DecimalRoundingMode::from_arithmetic(
      @lf_arith.RoundingMode::AwayFromZero,
    )
    is None,
  )
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
  assert_false(quarter_flags.inexact())
  let (third, third_flags) = one.div_ctx(three, ctx)
  assert_true(third.to_string().has_prefix("0.333333"))
  assert_true(third_flags.inexact())
  let (inf, div_zero_flags) = one.div_ctx(zero, ctx)
  assert_true(inf.classify() == @lf_arith.FpClass::Infinity)
  assert_true(div_zero_flags.division_by_zero())
  let (nan, undefined_flags) = zero.div_ctx(zero, ctx)
  assert_true(nan.classify() == @lf_arith.FpClass::NaN)
  assert_true(undefined_flags.invalid_operation())
  assert_true(undefined_flags.invalid_operation())
}

///|
test "decimal exact division preserves preferred integer cohort when it fits precision" {
  let ctx = @decimal.DecimalContext::new(precision=9)
  let one = @decimal.Decimal::one(precision=12)
  let ten = @decimal.Decimal::from_string("1E+1", precision=12).unwrap()
  let hundred = @decimal.Decimal::from_string("1E+2", precision=12).unwrap()
  let thousand = @decimal.Decimal::from_string("1E+3", precision=12).unwrap()
  let tiny = @decimal.Decimal::from_string("1E-8", precision=12).unwrap()
  let tinier = @decimal.Decimal::from_string("1E-9", precision=12).unwrap()
  let (ten_over_one, _) = ten.div_ctx(one, ctx)
  let (thousand_over_hundred, _) = thousand.div_ctx(hundred, ctx)
  let (plain_power, _) = one.div_ctx(tiny, ctx)
  let (scientific_power, _) = one.div_ctx(tinier, ctx)
  assert_eq(ten_over_one.to_string(), "1E+1")
  assert_eq(thousand_over_hundred.to_string(), "1E+1")
  assert_eq(plain_power.to_string(), "1E+8")
  assert_eq(
    scientific_power.total_order_compare(
      @decimal.Decimal::from_string("1E+9", precision=12).unwrap(),
    ),
    0,
  )
}

///|
test "decimal inexact division matches official rounded quotients" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    e_max=999,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
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
  assert_true(f1.inexact())
  assert_true(f2.inexact())
  assert_true(f3.inexact())
}

///|
test "decimal sqrt context reports exact inexact and invalid cases" {
  let ctx = @decimal.DecimalContext::new(precision=3)
  let (exact, exact_flags) = @decimal.Decimal::from_int(4, precision=12).sqrt_ctx(
    ctx,
  )
  assert_eq(exact.to_string(), "2")
  assert_false(exact_flags.inexact())
  let (rounded, rounded_flags) = @decimal.Decimal::from_int(2, precision=12).sqrt_ctx(
    ctx,
  )
  assert_eq(rounded.to_string(), "1.41")
  assert_true(rounded_flags.inexact())
  let (nan, invalid_flags) = @decimal.Decimal::from_int(-1, precision=12).sqrt_ctx(
    ctx,
  )
  assert_true(nan.classify() == @lf_arith.FpClass::NaN)
  assert_true(invalid_flags.invalid_operation())
  let (negative_zero, zero_flags) = @decimal.Decimal::from_string(
      "-0.00",
      precision=12,
    )
    .unwrap()
    .sqrt_ctx(ctx)
  assert_eq(negative_zero.to_string(), "-0.0")
  assert_false(zero_flags.invalid_operation())
}

///|
test "decimal sqrt exact results preserve cohort-only input rounding" {
  let ctx = @decimal.DecimalContext::new(
    precision=2,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToEven,
    e_max=999,
  )
  let (cohort_exact, cohort_flags) = @decimal.Decimal::from_string(
      "9.00E-2",
      precision=12,
    )
    .unwrap()
    .sqrt_ctx(ctx)
  assert_eq(cohort_exact.to_string(), "0.30")
  assert_false(cohort_flags.inexact())
  let (unit_exact, unit_flags) = @decimal.Decimal::from_string(
      "10.0E-1",
      precision=12,
    )
    .unwrap()
    .sqrt_ctx(ctx)
  assert_eq(unit_exact.to_string(), "1.0")
  assert_false(unit_flags.inexact())
}

///|
test "decimal context flags signaling nan as invalid operation" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let snan = @decimal.Decimal::signaling_nan(payload=9N, precision=8)
  let one = @decimal.Decimal::one(precision=8)
  let (value, flags) = snan.add_ctx(one, ctx)
  assert_true(value.classify() == @lf_arith.FpClass::NaN)
  assert_true(flags.invalid_operation())
}

///|
test "decimal context clamps finite exponent by padding coefficient" {
  let ctx = @decimal.DecimalContext::new(precision=3, e_max=9)
  let value = @decimal.Decimal::from_string("1e9", precision=10).unwrap()
  // The ideal exponent of 1e9 + 0E+9 is 9, above e_max - p + 1 = 7, so the
  // result is clamped by padding the coefficient; no digit is dropped.
  let (clamped, flags) = value.add_ctx(
    @decimal.Decimal::from_string("0E+9", precision=10).unwrap(),
    ctx,
  )
  assert_eq(clamped.to_string(), "1.00E+9")
  assert_eq(decimal_coeff_magnitude(clamped), 100N)
  assert_eq(clamped.exponent10(), 7)
  assert_false(flags.inexact())
  // With 0 (exponent 0) the ideal exponent is 0: rounding the exact sum to
  // three digits lands on exponent 7 itself, so nothing is clamped.
  let (rounded, rounded_flags) = value.add_ctx(
    @decimal.Decimal::zero(precision=10),
    ctx,
  )
  assert_eq(rounded.to_string(), "1.00E+9")
  assert_eq(rounded.exponent10(), 7)
  assert_false(rounded_flags.inexact())
}

///|
test "decimal context overflows finite results above emax" {
  let ctx = @decimal.DecimalContext::new(precision=3, e_max=3)
  let value = @decimal.Decimal::from_string("1e4", precision=10).unwrap()
  let (overflowed, flags) = value.add_ctx(
    @decimal.Decimal::zero(precision=10),
    ctx,
  )
  assert_true(overflowed.classify() == @lf_arith.FpClass::Infinity)
  assert_true(flags.overflow())
  assert_true(flags.inexact())
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
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTowardZero,
  )
  let ceiling_ctx = @decimal.DecimalContext::new(
    precision=16,
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTowardPositive,
  )
  let floor_ctx = @decimal.DecimalContext::new(
    precision=16,
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTowardNegative,
  )
  let expected_positive = @decimal.Decimal::from_string(
    "9.999999999999999E+384",
    precision=32,
  ).unwrap()
  let expected_negative = @decimal.Decimal::from_string(
    "-9.999999999999999E+384",
    precision=32,
  ).unwrap()
  let (down_positive_sci_value, _) = @decimal.Decimal::from_string_ctx(
    "9.999999999999999E+384", down_ctx,
  )
  let down_positive_sci = down_positive_sci_value.to_sci_string()
  let (down_negative_sci_value, _) = @decimal.Decimal::from_string_ctx(
    "-9.999999999999999E+384", down_ctx,
  )
  let down_negative_sci = down_negative_sci_value.to_sci_string()

  let (down_positive, down_positive_flags) = positive.add_ctx(
    positive_rhs, down_ctx,
  )
  assert_eq(
    down_positive.total_order_compare(expected_positive).to_string(),
    "0",
  )
  assert_eq(down_positive_sci, "9.999999999999999E+384")
  assert_true(down_positive_flags.overflow())
  assert_true(down_positive_flags.inexact())
  let (down_negative, down_negative_flags) = negative.add_ctx(
    negative_rhs, down_ctx,
  )
  assert_eq(
    down_negative.total_order_compare(expected_negative).to_string(),
    "0",
  )
  assert_eq(down_negative_sci, "-9.999999999999999E+384")
  assert_true(down_negative_flags.overflow())
  assert_true(down_negative_flags.inexact())

  let (ceiling_negative, ceiling_negative_flags) = negative.add_ctx(
    negative_rhs, ceiling_ctx,
  )
  assert_eq(
    ceiling_negative.total_order_compare(expected_negative).to_string(),
    "0",
  )
  assert_true(ceiling_negative_flags.overflow())
  assert_true(ceiling_negative_flags.inexact())

  let (floor_positive, floor_positive_flags) = positive.add_ctx(
    positive_rhs, floor_ctx,
  )
  assert_eq(
    floor_positive.total_order_compare(expected_positive).to_string(),
    "0",
  )
  assert_true(floor_positive_flags.overflow())
  assert_true(floor_positive_flags.inexact())
}

///|
test "decimal power handles million-scale integer exponents with rounded gda results" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToEven,
    e_max=999999,
  )
  run_decimal_binary_conformance_case(
    "powx183",
    Power,
    "7",
    "1000000",
    "1.09651419E+845098",
    ctx,
    inexact=true,
  )
  run_decimal_binary_conformance_case(
    "powx184",
    Power,
    "7",
    "1000001",
    "7.67559934E+845098",
    ctx,
    inexact=true,
  )
  run_decimal_binary_conformance_case(
    "powx186",
    Power,
    "7",
    "-1000001",
    "1.30282986E-845099",
    ctx,
    inexact=true,
  )
}

///|
test "decimal power with exponent one matches official rounding and representation cases" {
  let rounded_ctx = @decimal.DecimalContext::new(
    precision=9,
    e_max=999,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToEven,
  )
  run_decimal_binary_conformance_case(
    "powx701",
    Power,
    "12345678000",
    "1",
    "1.23456780E+10",
    rounded_ctx,
  )

  let exact_ctx = @decimal.DecimalContext::new(
    precision=15,
    e_max=999,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToEven,
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
  let pos_zero = @decimal.Decimal::from_string("0.00", precision=8).unwrap()
  let neg_zero = @decimal.Decimal::from_string("-0.00", precision=8).unwrap()
  let quiet = @decimal.Decimal::quiet_nan(payload=2N, precision=8)
  let signaling = @decimal.Decimal::signaling_nan(payload=1N, precision=8)
  assert_true(one == one_point_zero)
  assert_true(one.total_order_compare(one_point_zero) > 0)
  assert_true(neg_zero.total_order_compare(pos_zero) < 0)
  assert_true(signaling.total_order_compare(quiet) < 0)
  assert_true(one.total_order_compare(quiet) < 0)
  assert_true(quiet.abs().total_order_compare(signaling.abs()) > 0)
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
  assert_eq(huge.abs().total_order_compare(negative_huge.abs()), 0)
  assert_eq(huge.abs().total_order_compare(one.abs()), 1)
  assert_eq(small.abs().total_order_compare(one.abs()), -1)
  assert_eq(one.abs().total_order_compare(milli.abs()), 1)
  let trailing_zeros = @decimal.Decimal::from_string(
    "123.4560000000000000E789",
    precision=64,
  ).unwrap()
  let canonical = @decimal.Decimal::from_string("123.456E789", precision=64).unwrap()
  let zero_small = @decimal.Decimal::from_string("0E-383", precision=64).unwrap()
  let zero_large = @decimal.Decimal::from_string("0E+384", precision=64).unwrap()
  assert_eq(trailing_zeros.abs().total_order_compare(canonical.abs()), -1)
  assert_eq(canonical.abs().total_order_compare(trailing_zeros.abs()), 1)
  assert_eq(zero_small.abs().total_order_compare(zero_large.abs()), -1)
  assert_eq(zero_large.abs().total_order_compare(zero_small.abs()), 1)
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
test "plain decimal minmax follows IEEE operand-order nan propagation" {
  let finite = @decimal.Decimal::from_int(9, precision=8)
  let qnan_left = @decimal.Decimal::quiet_nan(
    payload=1N,
    negative=true,
    precision=8,
  )
  let qnan_right = @decimal.Decimal::quiet_nan(payload=11N, precision=8)
  let snan = @decimal.Decimal::signaling_nan(payload=93N, precision=8)
  assert_eq(qnan_left.max_num(qnan_right).to_string(), "-nan1")
  assert_eq(qnan_left.max_num(qnan_right).nan_payload(), 1N)
  assert_eq(qnan_right.min_num(qnan_left).to_string(), "nan11")
  assert_eq(qnan_right.min_num(qnan_left).nan_payload(), 11N)
  assert_eq(qnan_right.max_num(finite).to_string(), "9")
  assert_eq(finite.min_num(qnan_left).to_string(), "9")
  assert_eq(qnan_right.max_num(snan).to_string(), "nan11")
  assert_eq(qnan_right.max_num(snan).nan_payload(), 11N)
  assert_eq(finite.min_num(snan).to_string(), "nan93")
  assert_eq(finite.min_num(snan).nan_payload(), 93N)
}

///|
test "decimal quantize preserves requested quantum exponent" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let value = @decimal.Decimal::from_string("1.2", precision=8).unwrap()
  let quantum = @decimal.Decimal::from_string("0.01", precision=8).unwrap()
  let (fixed, flags) = value.quantize_ctx(quantum, ctx)
  assert_eq(fixed.to_string(), "1.20")
  assert_eq(fixed.exponent10(), -2)
  assert_true(fixed.same_quantum(quantum))
  assert_false(flags.inexact())
}

///|
test "decimal quantize distinguishes rounded from inexact" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let quantum = @decimal.Decimal::from_string("0.01", precision=8).unwrap()
  let exact = @decimal.Decimal::from_string("1.230", precision=8).unwrap()
  let inexact = @decimal.Decimal::from_string("1.235", precision=8).unwrap()
  let (exact_fixed, exact_flags) = exact.quantize_ctx(quantum, ctx)
  let (inexact_fixed, inexact_flags) = inexact.quantize_ctx(quantum, ctx)
  assert_eq(exact_fixed.to_string(), "1.23")
  assert_false(exact_flags.inexact())
  assert_eq(inexact_fixed.to_string(), "1.24")
  assert_true(inexact_flags.inexact())
}

///|
test "decimal quantize rejects coefficients beyond context precision" {
  let ctx = @decimal.DecimalContext::new(precision=3)
  let value = @decimal.Decimal::from_string("1234", precision=8).unwrap()
  let quantum = @decimal.Decimal::one(precision=8)
  let (result, flags) = value.quantize_ctx(quantum, ctx)
  assert_true(result.classify() == @lf_arith.FpClass::NaN)
  assert_true(flags.invalid_operation())
  assert_false(flags.inexact())
}

///|
test "decimal quantize invalid precision overflow suppresses rounded flags" {
  let ctx = @decimal.DecimalContext::new(
    precision=3,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
  )
  let tiny = @decimal.Decimal::from_string("9.999E-15", precision=16).unwrap()
  let fung = @decimal.Decimal::from_string("0.9998", precision=16).unwrap()
  let quantum_tiny = @decimal.Decimal::from_string("1e-17", precision=16).unwrap()
  let mills = @decimal.Decimal::from_string("0.001", precision=16).unwrap()
  let (tiny_result, tiny_flags) = tiny.quantize_ctx(quantum_tiny, ctx)
  let (fung_result, fung_flags) = fung.quantize_ctx(mills, ctx)
  assert_true(tiny_result.classify() == @lf_arith.FpClass::NaN)
  assert_true(fung_result.classify() == @lf_arith.FpClass::NaN)
  assert_true(tiny_flags.invalid_operation())
  assert_true(fung_flags.invalid_operation())
  assert_false(tiny_flags.inexact())
  assert_false(fung_flags.inexact())
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
  let pos_inf = @decimal.Decimal::inf(precision=16)
  let neg_inf = @decimal.Decimal::inf(negative=true, precision=16)
  let (qnan_result, qnan_flags) = finite.quantize_ctx(qnan, ctx)
  let (snan_result, snan_flags) = finite.quantize_ctx(snan, ctx)
  let (inf_result, inf_flags) = pos_inf.quantize_ctx(pos_inf, ctx)
  let (neg_quantum_inf, neg_quantum_inf_flags) = pos_inf.quantize_ctx(
    neg_inf, ctx,
  )
  assert_true(qnan_result.is_quiet_nan())
  assert_true(qnan_result.is_sign_minus())
  assert_eq(qnan_result.nan_payload(), 2345N)
  assert_false(qnan_flags.invalid_operation())
  assert_true(snan_result.is_quiet_nan())
  assert_true(snan_result.is_sign_minus())
  assert_eq(snan_result.nan_payload(), 67890N)
  assert_true(snan_flags.invalid_operation())
  assert_true(inf_result.is_infinite())
  assert_false(inf_result.is_sign_minus())
  assert_false(inf_flags.has_error())
  assert_true(neg_quantum_inf.is_infinite())
  assert_false(neg_quantum_inf.is_sign_minus())
  assert_false(neg_quantum_inf_flags.has_error())
}

///|
test "decimal same_quantum handles finite and special values" {
  let cents = @decimal.Decimal::from_string("1.20", precision=8).unwrap()
  let quantum = @decimal.Decimal::from_string("0.01", precision=8).unwrap()
  let units = @decimal.Decimal::one(precision=8)
  assert_true(cents.same_quantum(quantum))
  assert_false(cents.same_quantum(units))
  assert_true(
    @decimal.Decimal::inf().same_quantum(@decimal.Decimal::inf(negative=true)),
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
  let inf = @decimal.Decimal::inf(precision=16)
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
  let (exact, exact_flags) = value.to_integral_exact_ctx(ctx)
  let (quiet, quiet_flags) = value.to_integral_value_ctx(ctx)
  assert_eq(exact.to_string(), "2")
  assert_eq(quiet.to_string(), "2")
  assert_true(exact_flags.inexact())
  assert_false(quiet_flags.inexact())
}

///|
test "decimal to_integral_value preserves integral cohorts and special payloads" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let huge = @decimal.Decimal::from_string("10E+30", precision=16).unwrap()
  let pos_zero = @decimal.Decimal::from_string("0E+5", precision=16).unwrap()
  let neg_zero = @decimal.Decimal::from_string("-0E+5", precision=16).unwrap()
  let qnan = @decimal.Decimal::quiet_nan(payload=808N, precision=16)
  let snan = @decimal.Decimal::signaling_nan(payload=80N, precision=16)
  let (huge_integral, huge_flags) = huge.to_integral_value_ctx(ctx)
  let (pos_zero_integral, pos_zero_flags) = pos_zero.to_integral_value_ctx(ctx)
  let (neg_zero_integral, neg_zero_flags) = neg_zero.to_integral_value_ctx(ctx)
  let (qnan_integral, qnan_flags) = qnan.to_integral_value_ctx(ctx)
  let (snan_integral, snan_flags) = snan.to_integral_value_ctx(ctx)
  assert_eq(
    huge_integral.total_order_compare(
      @decimal.Decimal::from_string("1.0E+31", precision=16).unwrap(),
    ),
    0,
  )
  assert_eq(
    pos_zero_integral.total_order_compare(
      @decimal.Decimal::from_string("0E+5", precision=16).unwrap(),
    ),
    0,
  )
  assert_eq(
    neg_zero_integral.total_order_compare(
      @decimal.Decimal::from_string("-0E+5", precision=16).unwrap(),
    ),
    0,
  )
  assert_true(qnan_integral.is_quiet_nan())
  assert_eq(qnan_integral.nan_payload(), 808N)
  assert_true(snan_integral.is_quiet_nan())
  assert_eq(snan_integral.nan_payload(), 80N)
  assert_false(huge_flags.has_error())
  assert_false(pos_zero_flags.has_error())
  assert_false(neg_zero_flags.has_error())
  assert_false(qnan_flags.invalid_operation())
  assert_true(snan_flags.invalid_operation())
}

///|
test "decimal to_integral_exact preserves integral cohorts and special payloads" {
  let ctx = @decimal.DecimalContext::new(precision=8)
  let huge = @decimal.Decimal::from_string("10E+30", precision=16).unwrap()
  let pos_zero = @decimal.Decimal::from_string("0E+5", precision=16).unwrap()
  let neg_zero = @decimal.Decimal::from_string("-0E+5", precision=16).unwrap()
  let qnan = @decimal.Decimal::quiet_nan(payload=808N, precision=16)
  let snan = @decimal.Decimal::signaling_nan(payload=80N, precision=16)
  let inf = @decimal.Decimal::inf(precision=16)
  let (huge_integral, huge_flags) = huge.to_integral_exact_ctx(ctx)
  let (pos_zero_integral, pos_zero_flags) = pos_zero.to_integral_exact_ctx(ctx)
  let (neg_zero_integral, neg_zero_flags) = neg_zero.to_integral_exact_ctx(ctx)
  let (qnan_integral, qnan_flags) = qnan.to_integral_exact_ctx(ctx)
  let (snan_integral, snan_flags) = snan.to_integral_exact_ctx(ctx)
  let (inf_integral, inf_flags) = inf.to_integral_exact_ctx(ctx)
  assert_eq(
    huge_integral.total_order_compare(
      @decimal.Decimal::from_string("1.0E+31", precision=16).unwrap(),
    ),
    0,
  )
  assert_eq(
    pos_zero_integral.total_order_compare(
      @decimal.Decimal::from_string("0E+5", precision=16).unwrap(),
    ),
    0,
  )
  assert_eq(
    neg_zero_integral.total_order_compare(
      @decimal.Decimal::from_string("-0E+5", precision=16).unwrap(),
    ),
    0,
  )
  assert_true(qnan_integral.is_quiet_nan())
  assert_eq(qnan_integral.nan_payload(), 808N)
  assert_true(snan_integral.is_quiet_nan())
  assert_eq(snan_integral.nan_payload(), 80N)
  assert_true(inf_integral.is_infinite())
  assert_false(inf_integral.is_sign_minus())
  assert_false(huge_flags.has_error())
  assert_false(pos_zero_flags.has_error())
  assert_false(neg_zero_flags.has_error())
  assert_false(qnan_flags.invalid_operation())
  assert_true(snan_flags.invalid_operation())
  assert_false(inf_flags.has_error())
}

///|
test "decimal copy preserves gda representation semantics" {
  let finite = @decimal.Decimal::from_string("7.50", precision=8).unwrap()
  let snan = @decimal.Decimal::signaling_nan(
    payload=777N,
    negative=true,
    precision=8,
  )
  let copied_finite = finite.copy()
  let copied_snan = snan.copy()
  assert_eq(copied_finite.to_string(), "7.50")
  assert_eq(copied_finite.exponent10(), finite.exponent10())
  assert_true(copied_snan.is_signaling_nan())
  assert_true(copied_snan.is_sign_minus())
  assert_eq(copied_snan.nan_payload(), 777N)
  assert_eq(copied_snan.to_string(), "-snan777")
}

///|
test "decimal next plus and minus follow gda adjacent finite lattice" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
  )
  let one = @decimal.Decimal::from_string("1", precision=16).unwrap()
  let (next_after_one, next_after_one_flags) = one.next_up_ctx(ctx)
  let (prev_before_one, prev_before_one_flags) = one.next_down_ctx(ctx)
  assert_eq(next_after_one.to_string(), "1.00000001")
  assert_false(next_after_one_flags.has_error())
  assert_eq(prev_before_one.to_string(), "0.999999999")
  assert_false(prev_before_one_flags.has_error())

  let over_precise = @decimal.Decimal::from_string(
    "1.00000011001",
    precision=32,
  ).unwrap()
  let (ceil_neighbor, _) = over_precise.next_up_ctx(ctx)
  let (floor_neighbor, _) = over_precise.next_down_ctx(ctx)
  assert_eq(ceil_neighbor.to_string(), "1.00000012")
  assert_eq(floor_neighbor.to_string(), "1.00000011")

  let neg_one = @decimal.Decimal::from_string("-1", precision=16).unwrap()
  let (neg_toward_zero, _) = neg_one.next_up_ctx(ctx)
  let (neg_away_zero, _) = neg_one.next_down_ctx(ctx)
  assert_eq(neg_toward_zero.to_string(), "-0.999999999")
  assert_eq(neg_away_zero.to_string(), "-1.00000001")
}

///|
test "decimal next plus and minus cover official zero and ultra-tiny representatives" {
  let ctx = @decimal.DecimalContext::new(precision=9, e_max=384)
  let ultra_tiny = @decimal.Decimal::from_string("1E-99999", precision=32).unwrap()
  let neg_ultra_tiny = @decimal.Decimal::from_string("-1E-99999", precision=32).unwrap()
  let zero = @decimal.Decimal::zero(precision=32)
  let neg_zero = @decimal.Decimal::negative_zero(precision=32)
  let zero_huge = @decimal.Decimal::from_string("0E+30000", precision=32).unwrap()
  let neg_zero_huge = @decimal.Decimal::from_string("-0E+30000", precision=32).unwrap()
  let (next_pos_tiny, next_pos_tiny_flags) = ultra_tiny.next_up_ctx(ctx)
  let (next_neg_tiny, next_neg_tiny_flags) = neg_ultra_tiny.next_up_ctx(ctx)
  let (next_pos_zero, next_pos_zero_flags) = zero.next_up_ctx(ctx)
  let (next_neg_zero, next_neg_zero_flags) = neg_zero.next_up_ctx(ctx)
  let (next_pos_zero_huge, next_pos_zero_huge_flags) = zero_huge.next_up_ctx(
    ctx,
  )
  let (next_neg_zero_huge, next_neg_zero_huge_flags) = neg_zero_huge.next_up_ctx(
    ctx,
  )
  let (prev_pos_tiny, prev_pos_tiny_flags) = ultra_tiny.next_down_ctx(ctx)
  let (prev_neg_tiny, prev_neg_tiny_flags) = neg_ultra_tiny.next_down_ctx(ctx)
  let (prev_pos_zero, prev_pos_zero_flags) = zero.next_down_ctx(ctx)
  let (prev_neg_zero, prev_neg_zero_flags) = neg_zero.next_down_ctx(ctx)
  let (prev_pos_zero_huge, prev_pos_zero_huge_flags) = zero_huge.next_down_ctx(
    ctx,
  )
  let (prev_neg_zero_huge, prev_neg_zero_huge_flags) = neg_zero_huge.next_down_ctx(
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
  let ctx = @decimal.DecimalContext::new(precision=9, e_max=999)
  let zero_tiny = @decimal.Decimal::from_string("0E-1007", precision=32).unwrap()
  let neg_zero_tiny = @decimal.Decimal::from_string("-0E-1007", precision=32).unwrap()
  let (next_pos_zero_tiny, next_pos_zero_tiny_flags) = zero_tiny.next_up_ctx(
    ctx,
  )
  let (next_neg_zero_tiny, next_neg_zero_tiny_flags) = neg_zero_tiny.next_up_ctx(
    ctx,
  )
  let (prev_pos_zero_tiny, prev_pos_zero_tiny_flags) = zero_tiny.next_down_ctx(
    ctx,
  )
  let (prev_neg_zero_tiny, prev_neg_zero_tiny_flags) = neg_zero_tiny.next_down_ctx(
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
  assert_false(basic_flags.inexact())

  let rounded_ctx = @decimal.DecimalContext::new(precision=2)
  let (rounded, rounded_flags) = @decimal.Decimal::from_string(
      "1E-999",
      precision=16,
    )
    .unwrap()
    .logb_ctx(rounded_ctx)
  assert_eq(
    rounded.total_order_compare(
      @decimal.Decimal::from_string("-1.0E+3", precision=16).unwrap(),
    ),
    0,
  )
  assert_true(rounded_flags.inexact())

  let (zero_result, zero_flags) = @decimal.Decimal::negative_zero(precision=16).logb_ctx(
    ctx,
  )
  assert_eq(zero_result.to_string(), "-inf")
  assert_true(zero_flags.division_by_zero())
}

///|
test "decimal logb matches official zero cohorts and adjusted exponent representatives" {
  let ctx = @decimal.DecimalContext::new(precision=9, e_max=999)
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
  assert_true(zero_flags.division_by_zero())
  assert_eq(neg_zero_result.to_string(), "-inf")
  assert_true(neg_zero_flags.division_by_zero())
  assert_eq(zero_e4_result.to_string(), "-inf")
  assert_true(zero_e4_flags.division_by_zero())
  assert_eq(neg_zero_e4_result.to_string(), "-inf")
  assert_true(neg_zero_e4_flags.division_by_zero())
  assert_eq(zero_frac_result.to_string(), "-inf")
  assert_true(zero_frac_flags.division_by_zero())
  assert_eq(neg_zero_frac_result.to_string(), "-inf")
  assert_true(neg_zero_frac_flags.division_by_zero())
  assert_eq(zero_tiny_result.to_string(), "-inf")
  assert_true(zero_tiny_flags.division_by_zero())
  assert_eq(neg_zero_tiny_result.to_string(), "-inf")
  assert_true(neg_zero_tiny_flags.division_by_zero())
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
    e_max=999,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
  )
  let value = @decimal.Decimal::from_string("7.50", precision=16).unwrap()
  let (up, up_flags) = value.scaleb_ctx(@decimal.Decimal::from_int(2), ctx)
  let (down, down_flags) = value.scaleb_ctx(@decimal.Decimal::from_int(-2), ctx)
  assert_eq(
    up.total_order_compare(
      @decimal.Decimal::from_string("750", precision=16).unwrap(),
    ),
    0,
  )
  assert_eq(
    down.total_order_compare(
      @decimal.Decimal::from_string("0.0750", precision=16).unwrap(),
    ),
    0,
  )
  assert_false(up_flags.has_error())
  assert_false(down_flags.has_error())

  let invalid_count = @decimal.Decimal::from_string("1.00", precision=16).unwrap()
  let (invalid, invalid_flags) = value.scaleb_ctx(invalid_count, ctx)
  assert_eq(invalid.to_string(), "nan")
  assert_true(invalid_flags.invalid_operation())
}

///|
test "decimal scaleb preserves zero sign and shifted zero cohort" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    e_max=999,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
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
test "IEEE decimal scaleb preserves first nan payload" {
  let ctx = @decimal.DecimalContext::new(precision=5, e_max=9)
  let (inf_result, inf_flags) = @decimal.Decimal::inf(
    negative=true,
    precision=16,
  ).scaleb_ctx(@decimal.Decimal::from_int(2), ctx)
  assert_eq(inf_result.to_string(), "-inf")
  assert_false(inf_flags.has_error())

  let lhs_qnan = @decimal.Decimal::quiet_nan(payload=16N, precision=16)
  let rhs_snan = @decimal.Decimal::signaling_nan(payload=123456N, precision=16)
  let (nan_result, nan_flags) = lhs_qnan.scaleb_ctx(rhs_snan, ctx)
  assert_eq(nan_result.to_string(), "nan16")
  assert_true(nan_flags.invalid_operation())
}

///|
test "decimal transcendental constant reuse stays scale-correct across interleaved contexts" {
  let low_ctx = @decimal.DecimalContext::new(precision=12, e_max=999_999)
  let high_ctx = @decimal.DecimalContext::new(precision=28, e_max=999_999)
  let ln_value = @decimal.Decimal::from_string("2.5", precision=40).unwrap()
  let log10_value = @decimal.Decimal::from_string("12345.6789", precision=40).unwrap()
  let exp_value = @decimal.Decimal::from_string("1.23456789", precision=40).unwrap()
  let exponent = @decimal.Decimal::from_string("1.25", precision=40).unwrap()

  let (ln_low0, ln_low0_flags) = ln_value.ln_ctx(low_ctx)
  let _ = log10_value.log10_ctx(high_ctx)
  let _ = exp_value.exp_ctx(high_ctx)
  let (ln_low1, ln_low1_flags) = ln_value.ln_ctx(low_ctx)
  assert_eq(ln_low0.total_order_compare(ln_low1), 0)
  assert_true(ln_low0_flags == ln_low1_flags)

  let (power_low0, power_low0_flags) = ln_value.pow_ctx(exponent, low_ctx)
  let _ = ln_value.pow_ctx(exponent, high_ctx)
  let (power_low1, power_low1_flags) = ln_value.pow_ctx(exponent, low_ctx)
  assert_eq(power_low0.total_order_compare(power_low1), 0)
  assert_true(power_low0_flags == power_low1_flags)
}

///|
test "decimal ln lookaside constants preserve official-scale semantics" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    e_max=999_999,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToEven,
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
  assert_true(ln10_flags.inexact())
  assert_decimal_total_eq(
    ln2e3,
    decimal_test_operand("7.60090246"),
    "ln(2E+3) lookaside",
  )
  assert_true(ln2e3_flags.inexact())
  assert_decimal_total_eq(
    ln5e4,
    decimal_test_operand("10.8197783"),
    "ln(5E+4) lookaside",
  )
  assert_true(ln5e4_flags.inexact())
}

///|
test "decimal exact division by power of ten preserves preferred exponent behavior" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    e_max=999_999,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToEven,
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
  assert_false(hundreds_flags.inexact())
  assert_decimal_total_eq(
    shifted,
    decimal_test_operand("0.1230"),
    "1.2300/10 cohort",
  )
  assert_false(shifted_flags.inexact())
}

///|
test "decimal remainder fast path for power-of-ten divisors preserves results" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    e_max=999_999,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToEven,
  )
  let (near, near_flags) = @decimal.Decimal::from_string("12345", precision=32)
    .unwrap()
    .remainder_ctx(
      @decimal.Decimal::from_string("1E+2", precision=32).unwrap(),
      ctx,
    )
  assert_decimal_total_eq(
    near,
    decimal_test_operand("45"),
    "remainder_near 10^k fast path",
  )
  assert_false(near_flags.has_error())
}

///|
test "decimal power matches near-integer vector and IEEE one-base identity" {
  let near_integer_ctx = @decimal.DecimalContext::new(
    precision=16,
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToEven,
  )
  let (near_integer, near_integer_flags) = @decimal.Decimal::from_string(
      "2",
      precision=32,
    )
    .unwrap()
    .pow_ctx(
      @decimal.Decimal::from_string("2.000001", precision=32).unwrap(),
      near_integer_ctx,
    )
  assert_decimal_total_eq(
    near_integer,
    decimal_test_operand("4.000002772589683"),
    "powx2001 result",
  )
  assert_true(near_integer_flags.inexact())

  let one_ctx = @decimal.DecimalContext::new(
    precision=3,
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToEven,
  )
  let one = @decimal.Decimal::one(precision=16)
  let (one_noninteger, one_noninteger_flags) = one.pow_ctx(
    @decimal.Decimal::from_string("12.3", precision=32).unwrap(),
    one_ctx,
  )
  let (one_integer_like, one_integer_like_flags) = one.pow_ctx(
    @decimal.Decimal::from_string("12.0", precision=32).unwrap(),
    one_ctx,
  )
  assert_decimal_total_eq(
    one_noninteger,
    decimal_test_operand("1"),
    "IEEE one-base noninteger power",
  )
  // IEEE 754-2019 §9.2.1: pow(+1, y) is exact 1 for every finite y.
  assert_true(one_noninteger_flags == @decimal.DecimalFlags::new())
  assert_decimal_total_eq(
    one_integer_like,
    decimal_test_operand("1"),
    "powx2016 result",
  )
  assert_true(one_integer_like_flags == @decimal.DecimalFlags::new())
}

///|
test "decimal apply_ctx handles underflow shifts far beyond coefficient digits" {
  let ctx = @decimal.DecimalContext::new(
    precision=7,
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToEven,
  )
  let (positive, positive_flags) = @decimal.Decimal::from_string(
      "1E-1000000000",
      precision=16,
    )
    .unwrap()
    .apply_ctx(ctx)
  let (negative, negative_flags) = @decimal.Decimal::from_string(
      "-1E-1000000000",
      precision=16,
    )
    .unwrap()
    .apply_ctx(ctx)
  let expected_positive = @decimal.Decimal::from_string("0E-389", precision=16).unwrap()
  let expected_negative = @decimal.Decimal::from_string("-0E-389", precision=16).unwrap()
  assert_eq(positive.total_order_compare(expected_positive), 0)
  assert_true(positive_flags.underflow())
  assert_true(positive_flags.inexact())
  assert_eq(negative.total_order_compare(expected_negative), 0)
  assert_true(negative_flags.underflow())
  assert_true(negative_flags.inexact())
}

///|
test "decimal gda string conversions format and report context flags" {
  let ctx = @decimal.DecimalContext::new(
    precision=9,
    e_max=999_999_999,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
  )
  let (rounded_value, rounded_flags) = @decimal.Decimal::from_string_ctx(
    "1000000000", ctx,
  )
  let rounded = rounded_value.to_sci_string()
  assert_eq(rounded, "1.00000000E+9")
  assert_false(rounded_flags.inexact())

  let (finite_overflow_value, overflow_flags) = @decimal.Decimal::from_string_ctx(
    "7e1000000000",
    @decimal.DecimalContext::new(
      precision=9,
      e_max=999_999_999,
      rounding=@decimal.DecimalRoundingMode::RoundTowardZero,
    ),
  )
  let finite_overflow = finite_overflow_value.to_sci_string()
  assert_eq(finite_overflow, "9.99999999E+999999999")
  assert_true(overflow_flags.overflow())
  assert_true(overflow_flags.inexact())

  let tiny_ctx = @decimal.DecimalContext::new(
    precision=7,
    e_max=96,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToEven,
  )
  let (tiny_value, tiny_flags) = @decimal.Decimal::from_string_ctx(
    "1e-2147483647", tiny_ctx,
  )
  let tiny = tiny_value.to_sci_string()
  assert_eq(tiny, "0E-101")
  assert_true(tiny_flags.underflow())
  assert_true(tiny_flags.inexact())

  let (neg_tiny_value, neg_tiny_flags) = @decimal.Decimal::from_string_ctx(
    "-1e-2147483647", tiny_ctx,
  )
  let neg_tiny = neg_tiny_value.to_sci_string()
  assert_eq(neg_tiny, "-0E-101")
  assert_true(neg_tiny_flags.underflow())
  assert_true(neg_tiny_flags.inexact())
}

///|
test "decimal gda string conversions handle engineering zeros and syntax" {
  let ctx = @decimal.DecimalContext::new(precision=4)
  let (eng_value, eng_flags) = @decimal.Decimal::from_string_ctx("10e1", ctx)
  let eng = eng_value.to_eng_string()
  assert_eq(eng, "100")
  assert_false(eng_flags.has_error())

  let (zero_eng_value, zero_flags) = @decimal.Decimal::from_string_ctx(
    "0e+1", ctx,
  )
  let zero_eng = zero_eng_value.to_eng_string()
  assert_eq(zero_eng, "0.00E+3")
  assert_false(zero_flags.has_error())

  let (bad_value, bad_flags) = @decimal.Decimal::from_string_ctx("1E++1", ctx)
  let bad = bad_value.to_sci_string()
  assert_eq(bad, "NaN")
  assert_true(bad_flags.invalid_operation())
}

///|
test "decimal gda string conversions canonicalize special spellings and payloads" {
  let ctx = @decimal.DecimalContext::new(precision=8)

  let (inf_value, inf_flags) = @decimal.Decimal::from_string_ctx("+inf", ctx)
  let inf = inf_value.to_sci_string()
  assert_eq(inf, "Infinity")
  assert_false(inf_flags.has_error())

  let (qnan_value, qnan_flags) = @decimal.Decimal::from_string_ctx(
    "-nan0007", ctx,
  )
  let qnan = qnan_value.to_sci_string()
  assert_eq(qnan, "-NaN7")
  assert_false(qnan_flags.has_error())

  let (snan_value, snan_flags) = @decimal.Decimal::from_string_ctx(
    "sNaN0000", ctx,
  )
  let snan = snan_value.to_eng_string()
  assert_eq(snan, "sNaN")
  assert_false(snan_flags.has_error())
}

///|
test "decimal gda string conversions enforce clamped nan payload bounds" {
  let ctx = @decimal.DecimalContext::new(precision=4)

  let (allowed_value, allowed_flags) = @decimal.Decimal::from_string_ctx(
    "NaN123", ctx,
  )
  let allowed = allowed_value.to_sci_string()
  assert_eq(allowed, "NaN123")
  assert_false(allowed_flags.has_error())

  let (too_wide_value, too_wide_flags) = @decimal.Decimal::from_string_ctx(
    "NaN1234", ctx,
  )
  let too_wide = too_wide_value.to_sci_string()
  assert_eq(too_wide, "NaN")
  assert_true(too_wide_flags.invalid_operation())
}

///|
test "interval exact containment works" {
  let x = binary_test_make(3N, -1, 16)
  let interval = @interval.Interval::exact(x)
  assert_true(interval.is_member(x))
  assert_eq(interval.to_string(), "[1.5, 1.5]")
  assert_eq(interval.to_midpoint_radius_string(), "3p-1 +/- 0")
}

///|
test "interval constructors accept coefficient and float family inputs" {
  let from_big = @interval.Interval::from_coefficient(
    @binary.BinCoeff::from_uint64(42UL),
    precision=20,
  )
  let from_double = @interval.Interval::from_double(0.375, precision=20)
  let from_float = @interval.Interval::from_float(
    Float::from_double(0.375),
    precision=20,
  )
  assert_true(from_big.is_member(@binary.Binary::from_int(42, precision=64)))
  assert_true(
    from_double.is_member(@binary.Binary::from_double(0.375, precision=64)),
  )
  assert_true(
    from_float.is_member(@binary.Binary::from_double(0.375, precision=64)),
  )
}

///|
test "interval radius rounds outward at lower precision" {
  let interval = @interval.Interval::from_midpoint_radius(
    @binary.Binary::zero(precision=8),
    binary_test_make(9N, -4, 8),
    precision=2,
  )
  assert_eq(interval.radius().to_string(), "3p-2")
}

///|
test "interval arithmetic keeps exact scalar results enclosed" {
  let a = @interval.Interval::exact(binary_test_make(3N, -1, 8), precision=3)
  let b = @interval.Interval::exact(binary_test_make(5N, -2, 8), precision=3)
  let sum = a + b
  let product = a * b
  let quotient = a / b
  let exact_sum = binary_test_make(11N, -2, 32)
  let exact_product = binary_test_make(15N, -3, 32)
  let exact_quotient = @decimal.Decimal::from_string("1.2", precision=40)
    .unwrap()
    .to_binary(precision=80)
  assert_true(sum.is_member(exact_sum))
  assert_true(product.is_member(exact_product))
  assert_true(quotient.is_member(exact_quotient))
}

///|
test "interval enclosure relations stay partial-order based" {
  let cross = @interval.Interval::from_midpoint_radius(
    binary_test_make(1N, -2, 8),
    binary_test_make(1N, -1, 8),
    precision=4,
  )
  let right = @interval.Interval::from_midpoint_radius(
    @binary.Binary::from_int(2, precision=8),
    binary_test_make(1N, -2, 8),
    precision=4,
  )
  assert_true(DefinitelyLt::definitely_lt(cross, right))
  assert_true(DefinitelyLe::definitely_le(cross, right))
  assert_true(cross.disjoint(right))
  assert_false(MaybeEq::maybe_eq(cross, right))
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
test "interval division by a divisor containing zero returns whole real enclosure" {
  let numerator = @interval.Interval::exact(
    @binary.Binary::from_int(1, precision=16),
    precision=8,
  )
  let divisor = @interval.Interval::from_midpoint_radius(
    @binary.Binary::zero(precision=16),
    @binary.Binary::one(precision=16),
    precision=8,
  )
  let quotient = numerator / divisor
  assert_true(quotient.is_entire())
}

///|
// oracle: A, S
// source: the bounds are compared with the written value 12 (the coefficient constructor of an exact integer
//   must give the point interval [12, 12]); is_common_interval is a consistency check
// shares: nothing
test "interval coefficient constructor keeps exact bounded interval" {
  let value = @interval.Interval::from_coefficient(
    @binary.BinCoeff::from_uint64(12UL),
  ).normalized()
  let twelve = @binary.Binary::from_int(12)
  assert_eq(value.lower_bound().compare(twelve), 0)
  assert_eq(value.upper_bound().compare(twelve), 0)
  assert_true(value.is_common_interval())
  assert_true(value.lower_bound().identical(value.upper_bound()))
}

///|
test "interval implements checked enclosure-preserving power and division" {
  let unit_interval = @interval.Interval::exact(
    binary_test_make(3N, -1, 24),
    precision=12,
  )
  match square_checked(unit_interval, checked_ctx) {
    Ok(value) => assert_true(value.is_member(binary_test_make(9N, -2, 48)))
    Err(_) => fail("expected interval checked nat power to succeed")
  }
  let zero_crossing = @interval.Interval::from_midpoint_radius(
    @binary.Binary::zero(precision=24),
    @binary.Binary::one(precision=24),
    precision=12,
  )
  match reciprocal_power_checked(zero_crossing, -1, checked_ctx) {
    Ok(value) => assert_true(value.is_entire())
    Err(_) => fail("expected whole-real fallback for zero-containing inverse")
  }
  match div_checked_generic(unit_interval, zero_crossing, checked_ctx) {
    Ok(value) => assert_true(value.is_entire())
    Err(_) => fail("expected whole-real checked division fallback")
  }
}

///|
test "binary_checked keeps arithmetic closed and propagates errors" {
  let one = @binary_checked.BinaryChecked::from_int(1, precision=16)
  let two = @binary_checked.BinaryChecked::from_int(2, precision=16)
  match ((one + two).pow_nat(2U) * two).sqrt().result() {
    Ok(value) =>
      assert_true(value.compare(@binary.Binary::zero(precision=16)) > 0)
    Err(_) => fail("expected closed bin float result pipeline to succeed")
  }
  let zero = @binary_checked.BinaryChecked::from_int(0, precision=16)
  match (one / zero).abs().result() {
    Ok(_) => fail("expected division by zero to remain an error")
    Err(err) => assert_true(err.is_division_by_zero())
  }
}

///|
test "decimal_checked preserves IEEE values and accumulated flags" {
  let context = @decimal.DecimalContext::new(precision=20)
  let result = @decimal_checked.DecimalChecked::parse("9.0", context)
    .sqrt()
    .div(
      @decimal_checked.DecimalChecked::from_decimal(
        @decimal.Decimal::from_int(3, precision=20),
        context,
      ),
    )
  assert_eq(result.value(), @decimal.Decimal::one(precision=20))
  let invalid = @decimal_checked.DecimalChecked::parse("bad", context)
  assert_true(invalid.value().is_nan())
  assert_true(invalid.flags().invalid_operation())
  let divided_by_zero = @decimal_checked.DecimalChecked::from_int(1, context).div(
    @decimal_checked.DecimalChecked::from_decimal(
      @decimal.Decimal::zero(precision=20),
      context,
    ),
  )
  assert_true(divided_by_zero.value().is_infinite())
  assert_true(divided_by_zero.flags().division_by_zero())
}

///|
test "decimal_gda_checked threads context and short-circuits traps" {
  let context = @decimal_gda.GdaContext::decimal64().trap(
    @decimal_gda.GdaSignal::DivisionByZero,
  )
  let pipe = fn(value : @decimal_gda.Decimal) {
    @decimal_gda_checked.GdaDecimalChecked::from_decimal(value, context)
  }
  let one = pipe(@decimal_gda.Decimal::one())
  let trapped = one.divide(pipe(@decimal_gda.Decimal::zero()))
  assert_true(trapped.is_err())
  assert_true(trapped.value().is_infinite())
  assert_true(trapped.add(one).is_err())
  assert_false(trapped.resume_defined().add(one).is_err())
}

///|
test "interval_checked keeps interval operations in one result category" {
  let one = @interval_checked.IntervalChecked::from_int(1, precision=12)
  let zero_crossing = @interval_checked.IntervalChecked::from_bounds(
    binary_test_make(-1N, 0, 16),
    @binary.Binary::one(precision=16),
    precision=12,
  )
  match (one.pown(2) / zero_crossing).pown(-1).result() {
    Ok(value) => assert_true(value.is_entire())
    Err(_) => fail("expected interval result whole-real fallback to succeed")
  }
  let invalid = @interval_checked.IntervalChecked::from_double(
    0.0 / 0.0,
    precision=12,
  )
  match (invalid + one).result() {
    Ok(_) => fail("expected invalid interval source to short-circuit")
    Err(err) => assert_true(err.is_domain_error())
  }
}

///|
fn decimal_test_operand(src : String) -> @decimal.Decimal {
  match @decimal.Decimal::from_string(src, precision=64) {
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
  if actual.total_order_compare(expected) != 0 {
    abort(label)
  }
}

///|
test "decimal integer power keeps large exact powers exact when precision allows" {
  let ctx = @decimal.DecimalContext::new(
    precision=400,
    e_max=999_999,
    rounding=@decimal.DecimalRoundingMode::RoundTowardPositive,
  )
  let base = @decimal.Decimal::from_int(2, precision=32)
  let exponent = @decimal.Decimal::from_int(1001, precision=32)
  let (value, flags) = base.pow_ctx(exponent, ctx)
  let expected = @decimal.Decimal::from_bigint(2N.pow(1001N), precision=400)
  assert_decimal_total_eq(value, expected.normalized(), "2^1001 exact result")
  assert_false(flags.inexact())
}

///|
test "decimal official dectest math subsets stay aligned after gda fixes" {
  let exp_ctx9 = @decimal.DecimalContext::new(
    precision=9,
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
  )
  let exp_ctx7 = @decimal.DecimalContext::new(
    precision=7,
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
  )
  let ln_log_ctx = @decimal.DecimalContext::new(
    precision=16,
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
  )
  let power_ctx9 = @decimal.DecimalContext::new(
    precision=9,
    e_max=999,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
  )
  let power_ctx10 = @decimal.DecimalContext::new(
    precision=10,
    e_max=999,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToAway,
  )
  let minmax_ctx = @decimal.DecimalContext::new(
    precision=16,
    e_max=384,
    rounding=@decimal.DecimalRoundingMode::RoundTiesToEven,
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
  assert_true(exp_tiny_flags.inexact())

  let (exp_underflow, exp_underflow_flags) = decimal_test_operand("-100000000").exp_ctx(
    exp_ctx7,
  )
  assert_true(exp_underflow.is_zero())
  assert_true(exp_underflow_flags.underflow())
  assert_true(exp_underflow_flags.inexact())

  let (ln_one, ln_one_flags) = decimal_test_operand("1").ln_ctx(ln_log_ctx)
  assert_decimal_total_eq(ln_one, decimal_test_operand("0"), "ln0006 result")
  assert_true(ln_one_flags == @decimal.DecimalFlags::new())

  let (ln_two, ln_two_flags) = decimal_test_operand("2").ln_ctx(ln_log_ctx)
  assert_decimal_total_eq(
    ln_two,
    decimal_test_operand("0.6931471805599453"),
    "ln0008 result",
  )
  assert_true(ln_two_flags.inexact())

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
  assert_true(log_two_flags.inexact())

  run_decimal_binary_conformance_case(
    "pow028",
    Power,
    "2",
    "32",
    "4294967296",
    power_ctx10,
  )
  let (pow_ten, pow_ten_flags) = decimal_test_operand("10").pow_ctx(
    decimal_test_operand("9"),
    power_ctx9,
  )
  assert_eq(pow_ten.compare(decimal_test_operand("1E+9")).to_string(), "0")
  assert_false(pow_ten_flags.inexact())

  let negative_zero = decimal_test_operand("-0")
  let positive_zero = decimal_test_operand("0")
  let (min_value, min_flags) = positive_zero.minimum_number_ctx(
    negative_zero, minmax_ctx,
  )
  let (max_value, max_flags) = positive_zero.maximum_number_ctx(
    negative_zero, minmax_ctx,
  )
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
    @binary.Binary::one(precision=53),
    maximum,
    binary_context,
  ).unwrap()
  assert_eq(binary_one.compare(@binary.Binary::one(precision=53)), 0)
  let binary_minus_one = @lf_arith.PowNatChecked::pow_nat_checked(
    @binary.Binary::from_int(-1, precision=53),
    maximum,
    binary_context,
  ).unwrap()
  assert_eq(
    binary_minus_one.compare(@binary.Binary::from_int(-1, precision=53)),
    0,
  )
  let interval_one = @lf_arith.PowNatChecked::pow_nat_checked(
    @interval.Interval::from_int(1, precision=53),
    maximum,
    binary_context,
  ).unwrap()
  assert_true(interval_one.is_singleton())
  assert_true(interval_one.is_member(@binary.Binary::one(precision=53)))
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
test "binary checked clamps reject external invalid bounds without aborting" {
  let binary_value = @binary_checked.BinaryChecked::from_int(2)
  let binary_reversed = binary_value
    .clamp(
      min=@binary_checked.BinaryChecked::from_int(3),
      max=@binary_checked.BinaryChecked::from_int(1),
    )
    .result()
  assert_true(binary_reversed is Err(_))
  let binary_nan = @binary_checked.BinaryChecked::ok(@binary.Binary::nan())
  assert_true(
    binary_value
    .clamp(min=binary_nan, max=@binary_checked.BinaryChecked::from_int(3))
    .result()
    is Err(_),
  )
}

///|
test "context try constructors totalize invalid and optional parameters" {
  assert_true(@interval.IntervalContext::try_new(precision=0) is Err(_))
  assert_true(@interval.IntervalContext::try_new(e_max=0) is Err(_))
  assert_true(@binary.BinaryContext::try_new(precision=0) is Err(_))
  assert_true(@binary.BinaryContext::try_new(precision=53, e_max=11) is Ok(_))
  assert_true(@binary.BinaryContext::try_new(precision=53, e_max=10) is Ok(_))
  assert_true(@binary.BinaryContext::try_new(precision=53, e_max=0) is Err(_))
  assert_true(@decimal.DecimalContext::try_new(precision=-1) is Err(_))
  assert_true(@decimal.DecimalContext::try_new(e_max=0) is Err(_))
}

///|
test "Interval signed powers handle Int minimum" {
  let minimum = -2147483647 - 1
  let one = @interval.Interval::from_int(1, precision=53).pown(minimum)
  assert_true(one.is_singleton())
  assert_true(one.is_member(@binary.Binary::one(precision=53)))
  let crossing = @interval.Interval::from_bounds(
    @binary.Binary::from_int(-1, precision=53),
    @binary.Binary::from_int(1, precision=53),
  ).pown(minimum)
  assert_true(crossing.is_entire())
}

///|
pub extend DecimalConformanceOp with Eq::{not_equal, equal}
