///|
/// `value flags` for a restricted-context row, flags in decTest spelling.
fn context_bounds_row(value : Decimal, raised : GdaFlags) -> String {
  let names = []
  if raised.invalid_context {
    names.push("Invalid_context")
  }
  if raised.invalid_operation {
    names.push("Invalid_operation")
  }
  if raised.inexact {
    names.push("Inexact")
  }
  if raised.rounded {
    names.push("Rounded")
  }
  let flags = names.join(" ")
  let text = format_sci_gda(value)
  if flags == "" {
    text
  } else {
    "\{text} \{flags}"
  }
}

///|
/// GDA 1.70, Finite numbers; decNumber `decContext.h`: the adopted limits
/// require `e_min <= 0 <= e_max`.  D-F1 deliberately does not impose GDA's
/// separate balanced-range rule.
test "GDA DecimalContext rejects exponent bounds with invalid signs" {
  assert_true(DecimalContext::try_new(precision=1) is Ok(_))
  assert_true(DecimalContext::try_new(precision=0) is Err(_))
  assert_true(DecimalContext::new(precision=1) is Ok(_))
  assert_true(DecimalContext::new(precision=0) is Err(_))
  assert_true(GdaContext::try_new(precision=1) is Ok(_))
  assert_true(GdaContext::new(precision=1) is Ok(_))
  assert_true(DecimalContext::try_new(e_min=0, e_max=0) is Ok(_))
  assert_true(
    DecimalContext::try_new(e_min=-999_999_999, e_max=999_999_999) is Ok(_),
  )
  assert_true(DecimalContext::try_new(e_min=-10, e_max=10) is Ok(_))
  assert_true(DecimalContext::try_new(e_min=1, e_max=10) is Err(_))
  assert_true(DecimalContext::try_new(e_min=-10, e_max=-1) is Err(_))
  match DecimalContext::try_new(e_min=1, e_max=10) {
    Err(error) =>
      assert_eq(error.message, "e_min must be within -999999999..=0")
    Ok(_) => fail("positive e_min must be rejected")
  }
  match DecimalContext::try_new(e_min=-10, e_max=-1) {
    Err(error) => assert_eq(error.message, "e_max must be within 0..=999999999")
    Ok(_) => fail("negative e_max must be rejected")
  }
  for
    (result, expected) in [
      (
        DecimalContext::try_new(precision=999_999_999, e_min=1),
        "e_min must be within -999999999..=0",
      ),
      (
        DecimalContext::try_new(e_min=0, e_max=-1),
        "e_max must be within 0..=999999999",
      ),
      (
        DecimalContext::new(precision=999_999_999, e_min=1),
        "e_min must be within -999999999..=0",
      ),
      (
        DecimalContext::new(e_min=0, e_max=-1),
        "e_max must be within 0..=999999999",
      ),
    ] {
    match result {
      Err(error) => assert_eq(error.message, expected)
      Ok(_) =>
        fail("invalid DecimalContext boundary combination must be rejected")
    }
  }
  for
    result in [
      DecimalContext::try_new(precision=0),
      DecimalContext::try_new(precision=1_000_000_000),
    ] {
    match result {
      Err(error) =>
        assert_eq(error.message, "precision must be within 1..=999999999")
      Ok(_) => fail("invalid precision must be rejected")
    }
  }
  match DecimalContext::try_new(e_min=-1_000_000_000) {
    Err(error) =>
      assert_eq(error.message, "e_min must be within -999999999..=0")
    Ok(_) => fail("e_min below the minimum must be rejected")
  }
  match DecimalContext::try_new(e_max=1_000_000_000) {
    Err(error) => assert_eq(error.message, "e_max must be within 0..=999999999")
    Ok(_) => fail("e_max above the maximum must be rejected")
  }
  for
    (result, expected) in [
      (
        DecimalContext::new(precision=0),
        "precision must be within 1..=999999999",
      ),
      (
        DecimalContext::new(precision=1_000_000_000),
        "precision must be within 1..=999999999",
      ),
      (
        DecimalContext::new(e_min=-1_000_000_000),
        "e_min must be within -999999999..=0",
      ),
      (DecimalContext::new(e_min=1), "e_min must be within -999999999..=0"),
      (
        DecimalContext::new(e_max=1_000_000_000),
        "e_max must be within 0..=999999999",
      ),
      (DecimalContext::new(e_max=-1), "e_max must be within 0..=999999999"),
    ] {
    match result {
      Err(error) => assert_eq(error.message, expected)
      Ok(_) => fail("invalid DecimalContext field must be rejected")
    }
  }
  for
    (result, expected) in [
      (
        GdaContext::try_new(precision=0),
        "GdaContext precision must be in 1..=999999999",
      ),
      (
        GdaContext::new(precision=0),
        "GdaContext precision must be in 1..=999999999",
      ),
      (
        GdaContext::try_new(precision=1_000_000_000),
        "GdaContext precision must be in 1..=999999999",
      ),
      (
        GdaContext::new(precision=1_000_000_000),
        "GdaContext precision must be in 1..=999999999",
      ),
    ] {
    match result {
      Err(error) => assert_eq(error.message, expected)
      Ok(_) => fail("invalid GdaContext precision must be rejected")
    }
  }
  let arithmetic_min = @lf_arith.ArithmeticContext::new(34, e_min=1, e_max=10)
  let arithmetic_max = @lf_arith.ArithmeticContext::new(34, e_min=-10, e_max=-1)
  match DecimalContext::from_arithmetic_context(arithmetic_min) {
    Err(error) =>
      assert_eq(error.message, "e_min must be within -999999999..=0")
    Ok(_) => fail("positive e_min translation must be rejected")
  }
  match DecimalContext::from_arithmetic_context(arithmetic_max) {
    Err(error) => assert_eq(error.message, "e_max must be within 0..=999999999")
    Ok(_) => fail("negative e_max translation must be rejected")
  }
  for
    (e_min, e_max, expected) in [
      (1, 10, "GdaContext e_min must be within -999999999..=0"),
      (-1_000_000_000, 10, "GdaContext e_min must be within -999999999..=0"),
      (-10, -1, "GdaContext e_max must be within 0..=999999999"),
      (-10, 1_000_000_000, "GdaContext e_max must be within 0..=999999999"),
    ] {
    match context(e_min~, e_max~) {
      Err(error) => assert_eq(error.message, expected)
      Ok(_) => fail("context facade must reject invalid exponent signs")
    }
    for
      result in [
        GdaContext::try_new(e_min~, e_max~),
        GdaContext::new(e_min~, e_max~),
      ] {
      match result {
        Err(error) => assert_eq(error.message, expected)
        Ok(_) => fail("invalid GdaContext exponent signs must be rejected")
      }
    }
  }
  let large_precision_positive_min = "GdaContext e_min must be within -999999999..=0"
  let zero_min_negative_max = "GdaContext e_max must be within 0..=999999999"
  for
    (result, expected) in [
      (context(precision=999_999_999, e_min=1), large_precision_positive_min),
      (context(e_min=0, e_max=-1), zero_min_negative_max),
      (
        GdaContext::try_new(precision=999_999_999, e_min=1),
        large_precision_positive_min,
      ),
      (GdaContext::try_new(e_min=0, e_max=-1), zero_min_negative_max),
      (
        GdaContext::new(precision=999_999_999, e_min=1),
        large_precision_positive_min,
      ),
      (GdaContext::new(e_min=0, e_max=-1), zero_min_negative_max),
    ] {
    match result {
      Err(error) => assert_eq(error.message, expected)
      Ok(_) => fail("invalid GdaContext boundary combination must be rejected")
    }
  }
  let arithmetic_zero_precision = @lf_arith.ArithmeticContext::new(0)
  let zero_precision_context = DecimalContext::from_arithmetic_context(
    arithmetic_zero_precision,
  ).unwrap()
  assert_eq(zero_precision_context.precision(), 1)
  let arithmetic_excessive_precision = @lf_arith.ArithmeticContext::new(
    1_000_000_000,
  )
  match
    DecimalContext::from_arithmetic_context(arithmetic_excessive_precision) {
    Err(error) =>
      assert_eq(error.message, "precision must be within 1..=999999999")
    Ok(_) => fail("excessive arithmetic precision must be rejected")
  }
}

///|
/// Runs one decTest row through both the GDA operation form (`GdaContext`)
/// and the status-free `_ctx` form (`DecimalContext`), which must agree.
fn context_bounds_case(
  operation : String,
  operands : Array[String],
  precision : Int,
  e_min : Int,
  e_max : Int,
) -> String raise {
  let gda = GdaContext::new(precision~, e_min~, e_max~).unwrap()
  let ctx = DecimalContext::new(precision~, e_min~, e_max~).unwrap()
  let lhs = Decimal::from_string(operands[0]).unwrap()
  let (outcome, direct) = match operation {
    "exp" => (exp(lhs, gda), lhs.exp_ctx(ctx))
    "ln" => (ln(lhs, gda), lhs.ln_ctx(ctx))
    "log10" => (log10(lhs, gda), lhs.log10_ctx(ctx))
    "power" => {
      let rhs = Decimal::from_string(operands[1]).unwrap()
      (power(lhs, rhs, gda), lhs.power_ctx(rhs, ctx))
    }
    _ => abort("unknown operation")
  }
  let via_gda = context_bounds_row(outcome.value(), outcome.raised())
  let via_ctx = context_bounds_row(direct.0, gda_flags_from_decimal(direct.1))
  assert_eq(via_gda, via_ctx)
  via_gda
}

///|
test "decTest expx901-906: exp requires bounded contexts" {
  // exp.decTest: extended 1, half_even, maxExponent 999 / minExponent -999
  // before the restriction rows.
  let row = fn(p, e_min, e_max) raise {
    context_bounds_case("exp", ["-Infinity"], p, e_min, e_max)
  }
  assert_eq(row(100_000_000, -999, 999), "NaN Invalid_context") // expx901
  assert_eq(row(99_999_999, -999, 999), "NaN Invalid_context") // expx902
  assert_eq(row(9, -999_999, 1_000_000), "NaN Invalid_context") // expx903
  assert_eq(row(9, -999_999, 999_999), "0") // expx904
  assert_eq(row(9, -1_000_000, 999_999), "NaN Invalid_context") // expx905
  assert_eq(row(9, -999_998, 999_999), "0") // expx906
}

///|
test "decTest lnx901-906 and logx901-906: logarithms require bounded contexts" {
  let ln_row = fn(x, p, e_min, e_max) raise {
    context_bounds_case("ln", [x], p, e_min, e_max)
  }
  // ln.decTest: maxExponent 384 / minExponent -383 before the rows.
  assert_eq(ln_row("1", 100_000_000, -383, 384), "NaN Invalid_context") // lnx901
  assert_eq(ln_row("0", 99_999_999, -383, 384), "NaN Invalid_context") // lnx902
  assert_eq(ln_row("1", 9, -999_999, 1_000_000), "NaN Invalid_context") // lnx903
  assert_eq(ln_row("0", 9, -999_999, 999_999), "-Infinity") // lnx904
  assert_eq(ln_row("1", 9, -1_000_000, 999_999), "NaN Invalid_context") // lnx905
  assert_eq(ln_row("0", 9, -999_998, 999_999), "-Infinity") // lnx906
  let log_row = fn(x, p, e_min, e_max) raise {
    context_bounds_case("log10", [x], p, e_min, e_max)
  }
  assert_eq(log_row("1", 100_000_000, -383, 384), "NaN Invalid_context") // logx901
  assert_eq(log_row("0", 99_999_999, -383, 384), "NaN Invalid_context") // logx902
  assert_eq(log_row("1", 9, -999_999, 1_000_000), "NaN Invalid_context") // logx903
  assert_eq(log_row("0", 9, -999_999, 999_999), "-Infinity") // logx904
  assert_eq(log_row("1", 9, -1_000_000, 999_999), "NaN Invalid_context") // logx905
  assert_eq(log_row("0", 9, -999_998, 999_999), "-Infinity") // logx906
}

///|
test "decTest powx4001-4006: non-integral power requires bounded contexts" {
  // power.decTest: extended 1, half_even, maxExponent 384 / minExponent -383
  // before the restriction rows.
  let row = fn(p, e_min, e_max) raise {
    context_bounds_case("power", ["1", "1.1"], p, e_min, e_max)
  }
  assert_eq(row(100_000_000, -383, 384), "NaN Invalid_context") // powx4001
  assert_eq(row(99_999_999, -383, 384), "NaN Invalid_context") // powx4002
  assert_eq(row(9, -999_999, 1_000_000), "NaN Invalid_context") // powx4003
  assert_eq(row(9, -999_999, 999_999), "1.00000000 Inexact Rounded") // powx4004
  assert_eq(row(9, -1_000_000, 999_999), "NaN Invalid_context") // powx4005
  assert_eq(row(9, -999_998, 999_999), "1.00000000 Inexact Rounded") // powx4006
}

///|
test "an ArithmeticContext without exponent bounds is an invalid context for exp (#111)" {
  let one = Decimal::from_string("1").unwrap()
  // The translation keeps the default decNumber-limit range; it does not pick bounds.
  let unbounded = DecimalContext::from_arithmetic_context(
    @lf_arith.ArithmeticContext::new(16),
  ).unwrap()
  assert_eq(unbounded.e_min(), -999_999_999)
  assert_eq(unbounded.e_max(), 999_999_999)
  // The GDA form raises Invalid_context ...
  let (value, flags) = one.exp_ctx(unbounded)
  assert_eq(
    context_bounds_row(value, gda_flags_from_decimal(flags)),
    "NaN Invalid_context",
  )
  // ... and the contextual adapter reports it as such, naming the bounds.
  let error = @lf_arith.ExpContextual::exp_contextual(
    one,
    @lf_arith.ArithmeticContext::new(16),
  ).unwrap_err()
  assert_true(error.is_unsupported())
  assert_eq(
    error.message,
    "invalid context: exp requires precision, e_max and -e_min of at most 999999; the ArithmeticContext sets no e_min and e_max",
  )
  // The context is checked before the operand, as in expx901.
  let minus_inf = Decimal::from_string("-Infinity").unwrap()
  assert_true(
    @lf_arith.ExpContextual::exp_contextual(
      minus_inf,
      @lf_arith.ArithmeticContext::new(16),
    )
    .unwrap_err()
    .is_unsupported(),
  )
  let only_min = @lf_arith.ExpContextual::exp_contextual(
    one,
    @lf_arith.ArithmeticContext::new(16, e_min=-383),
  ).unwrap_err()
  assert_eq(
    only_min.message,
    "invalid context: exp requires precision, e_max and -e_min of at most 999999; the ArithmeticContext sets no e_max",
  )
  let too_wide = @lf_arith.ExpContextual::exp_contextual(
    one,
    @lf_arith.ArithmeticContext::new(16, e_min=-1_000_000, e_max=999_999),
  ).unwrap_err()
  assert_true(too_wide.is_unsupported())
  assert_eq(
    too_wide.message,
    "invalid context: exp requires precision, e_max and -e_min of at most 999999",
  )
  // With explicit bounds the adapter computes the value.
  let bounded = @lf_arith.ExpContextual::exp_contextual(
    one,
    @lf_arith.ArithmeticContext::new(16, e_min=-999_999, e_max=999_999),
  ).unwrap()
  assert_eq(bounded.value.to_string(), "2.718281828459045")
  let decimal64 = @lf_arith.ExpContextual::exp_contextual(
    one,
    @lf_arith.ArithmeticContext::decimal64(),
  ).unwrap()
  assert_eq(decimal64.value.to_string(), "2.718281828459045")
  // Operations that are not restricted keep working without bounds.
  let sum = @lf_arith.AddContextual::add_contextual(
    one,
    one,
    @lf_arith.ArithmeticContext::new(16),
  ).unwrap()
  assert_eq(sum.value.to_string(), "2")
}

///|
test "checked integer powers report an invalid context, not a domain error (#111)" {
  let seven = Decimal::from_int(7, precision=9)
  let error = @lf_arith.PowIntChecked::pow_int_checked(
    seven,
    1_000_000_000,
    @lf_arith.ArithmeticContext::new(9),
  ).unwrap_err()
  assert_true(error.is_unsupported())
  assert_eq(
    error.message,
    "invalid context: power requires precision, e_max and -e_min of at most 999999; the ArithmeticContext sets no e_min and e_max",
  )
  let bounded = @lf_arith.PowIntChecked::pow_int_checked(
    seven,
    1_000_000_000,
    @lf_arith.ArithmeticContext::new(9, e_min=-999_999, e_max=999_999),
  ).unwrap()
  assert_true(bounded.classify() == @lf_arith.FpClass::Infinity)
}
