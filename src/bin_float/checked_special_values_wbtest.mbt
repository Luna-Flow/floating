// Special-value contract of the checked adapters (#262).
//
// The checked result is the IEEE 754-2019 default result. The invalid
// operation exception (section 7.2) maps to `Err(DomainError)`, the
// divideByZero exception (section 7.3) maps to `Err(DivisionByZero)`, and
// every other result, NaN, infinity, overflow and underflow included, is
// `Ok`. This is the contract `Luna-Flow/arithmetic` documents for `Double` and
// `Float` (Luna-Flow/arithmetic#5) and that both `Decimal` instances follow.
//
// The expected column below is computed by an oracle written from the
// clauses, not from the implementation.

///|
fn checked_operand_names() -> Array[String] {
  ["+qnan", "-qnan", "+snan", "-snan", "+0", "-0", "+inf", "-inf", "+2", "-2"]
}

///|
fn checked_operand(name : String, precision : Int32) -> BinFloat {
  match name {
    "+qnan" => BinFloat::quiet_nan(precision~)
    "-qnan" => BinFloat::quiet_nan(negative=true, precision~)
    "+snan" => BinFloat::signaling_nan(precision~)
    "-snan" => BinFloat::signaling_nan(negative=true, precision~)
    "+0" => BinFloat::zero(precision~)
    "-0" => BinFloat::negative_zero(precision~)
    "+inf" => BinFloat::inf(Sign::Positive, precision~)
    "-inf" => BinFloat::inf(Sign::Negative, precision~)
    "+2" => BinFloat::from_int(2, precision~)
    "-2" => BinFloat::from_int(-2, precision~)
    _ => abort("unknown checked operand " + name)
  }
}

///|
/// Renders a checked result by class. A NaN result must be quiet (section 6.2:
/// an operation that delivers a NaN delivers a quiet NaN).
fn checked_render(result : Result[BinFloat, @def.ArithmeticError]) -> String {
  match result {
    Err(error) =>
      match error.kind {
        @lf_arith.ArithmeticErrorKind::DivisionByZero => "err:div0"
        @lf_arith.ArithmeticErrorKind::DomainError => "err:invalid"
        _ => "err:other"
      }
    Ok(value) => {
      let sign = if value.negative { "-" } else { "+" }
      match value.classify() {
        FpClass::NaN =>
          if value.is_signaling_nan() {
            "ok:snan"
          } else {
            "ok:nan"
          }
        FpClass::Infinity => "ok:" + sign + "inf"
        FpClass::Finite =>
          if value.is_zero() {
            "ok:" + sign + "0"
          } else {
            "ok:" + sign + "fin"
          }
      }
    }
  }
}

///|
fn checked_is_nan(name : String) -> Bool {
  name.has_suffix("nan")
}

///|
fn checked_is_snan(name : String) -> Bool {
  name.has_suffix("snan")
}

///|
fn checked_is_zero(name : String) -> Bool {
  name.has_suffix("0")
}

///|
fn checked_is_inf(name : String) -> Bool {
  name.has_suffix("inf")
}

///|
fn checked_is_neg(name : String) -> Bool {
  name.has_prefix("-")
}

///|
fn checked_signed(negative : Bool, magnitude : String) -> String {
  "ok:" + (if negative { "-" } else { "+" }) + magnitude
}

///|
/// Expected `a / b` from IEEE 754-2019.
fn checked_expected_div(a : String, b : String) -> String {
  let negative = checked_is_neg(a) != checked_is_neg(b)
  if checked_is_snan(a) || checked_is_snan(b) {
    // 7.2 a): any general-computational operation on a signaling NaN.
    "err:invalid"
  } else if checked_is_nan(a) || checked_is_nan(b) {
    // 6.2: quiet NaN inputs signal no exception and deliver a quiet NaN.
    "ok:nan"
  } else if (checked_is_zero(a) && checked_is_zero(b)) ||
    (checked_is_inf(a) && checked_is_inf(b)) {
    // 7.2 e): division(0, 0) or division(inf, inf).
    "err:invalid"
  } else if checked_is_inf(a) {
    // inf / finite (zero included) is an exact infinity; 7.3 applies only to
    // a finite non-zero dividend.
    checked_signed(negative, "inf")
  } else if checked_is_zero(b) {
    // 7.3: divisor zero and dividend finite non-zero.
    "err:div0"
  } else if checked_is_inf(b) || checked_is_zero(a) {
    checked_signed(negative, "0")
  } else {
    checked_signed(negative, "fin")
  }
}

///|
/// Expected `sqrt(a)` from IEEE 754-2019.
fn checked_expected_sqrt(a : String) -> String {
  if checked_is_snan(a) {
    // 7.2 a).
    "err:invalid"
  } else if checked_is_nan(a) {
    // 6.2: the sign bit of a quiet NaN does not make it "less than zero".
    "ok:nan"
  } else if checked_is_zero(a) {
    // 5.4.1: squareRoot(-0) is -0.
    checked_signed(checked_is_neg(a), "0")
  } else if checked_is_neg(a) {
    // 7.2 g): squareRoot if the operand is less than zero.
    "err:invalid"
  } else if checked_is_inf(a) {
    "ok:+inf"
  } else {
    "ok:+fin"
  }
}

///|
/// Expected `pown(a, n)` from IEEE 754-2019 section 9.2.1, or `None` for
/// `pown(sNaN, 0)`, which 9.2.1 leaves to section 7.2 a) and which the
/// contextual layer still answers with 1 (reported separately from #262).
fn checked_expected_pown(a : String, n : Int32) -> String? {
  let negative = checked_is_neg(a) && n % 2 != 0
  if n == 0 {
    // 9.2.1: pown(x, 0) is 1 if x is not a signaling NaN.
    if checked_is_snan(a) {
      None
    } else {
      Some("ok:+fin")
    }
  } else if checked_is_snan(a) {
    Some("err:invalid")
  } else if checked_is_nan(a) {
    Some("ok:nan")
  } else if checked_is_zero(a) {
    // 9.2.1: pown(+-0, n) signals divideByZero for n < 0.
    Some(if n < 0 { "err:div0" } else { checked_signed(negative, "0") })
  } else if checked_is_inf(a) {
    Some(checked_signed(negative, if n < 0 { "0" } else { "inf" }))
  } else {
    Some(checked_signed(negative, "fin"))
  }
}

///|
fn checked_contexts() -> Array[@lf_arith.ArithmeticContext] {
  let modes = [
    @lf_arith.RoundingMode::ToNearestEven,
    @lf_arith.RoundingMode::TowardZero,
    @lf_arith.RoundingMode::TowardPositive,
    @lf_arith.RoundingMode::TowardNegative,
    @lf_arith.RoundingMode::AwayFromZero,
  ]
  // binary32, binary64 and binary128 exponent ranges, plus unbounded.
  let formats = [(24, -126, 127), (53, -1022, 1023), (113, -16382, 16383)]
  let contexts = []
  for mode in modes {
    for format in formats {
      let (precision, e_min, e_max) = format
      contexts.push(
        @lf_arith.ArithmeticContext::new(
          precision,
          rounding=mode,
          e_min~,
          e_max~,
        ),
      )
      contexts.push(@lf_arith.ArithmeticContext::new(precision, rounding=mode))
    }
  }
  contexts
}

///|
fn checked_mismatch(
  label : String,
  context : @lf_arith.ArithmeticContext,
  actual : String,
  expected : String,
) -> String {
  label +
  " at p=" +
  context.precision.to_string() +
  ": got " +
  actual +
  ", expected " +
  expected
}

///|
test "issue 262 rows through the checked traits" {
  let ctx = @lf_arith.ArithmeticContext::new(53, e_min=-1022, e_max=1023)
  let nan = BinFloat::nan()
  let zero = BinFloat::zero()
  let inf = BinFloat::inf(Sign::Positive)
  let div = fn(a, b) {
    checked_render(@lf_arith.DivChecked::div_checked(a, b, ctx))
  }
  assert_eq(div(nan, zero), "ok:nan")
  assert_eq(div(zero, zero), "err:invalid")
  assert_eq(div(inf, zero), "ok:+inf")
  assert_eq(div(inf, inf), "err:invalid")
  assert_eq(div(BinFloat::one(), zero), "err:div0")
  let sqrt = fn(a) {
    checked_render(@lf_arith.SqrtChecked::sqrt_checked(a, ctx))
  }
  assert_eq(sqrt(BinFloat::quiet_nan(negative=true)), "ok:nan")
  assert_eq(sqrt(nan), "ok:nan")
  assert_eq(sqrt(BinFloat::from_int(-1)), "err:invalid")
  assert_eq(sqrt(BinFloat::negative_zero()), "ok:-0")
  assert_eq(
    @lf_arith.SqrtChecked::sqrt_checked(BinFloat::from_int(4), ctx).unwrap(),
    BinFloat::from_int(2),
  )
  assert_eq(
    @lf_arith.DivChecked::div_checked(
      BinFloat::from_int(6),
      BinFloat::from_int(-3),
      ctx,
    ).unwrap(),
    BinFloat::from_int(-2),
  )
}

///|
test "checked trait adapters follow the IEEE special-value table" {
  let names = checked_operand_names()
  let failures = []
  let mut cases = 0
  for context in checked_contexts() {
    let p = context.precision
    for a in names {
      let x = checked_operand(a, p)
      for b in names {
        let y = checked_operand(b, p)
        let actual = checked_render(
          @lf_arith.DivChecked::div_checked(x, y, context),
        )
        let expected = checked_expected_div(a, b)
        cases += 1
        if actual != expected {
          failures.push(
            checked_mismatch(
              "div(" + a + ", " + b + ")",
              context,
              actual,
              expected,
            ),
          )
        }
      }
      let sqrt_actual = checked_render(
        @lf_arith.SqrtChecked::sqrt_checked(x, context),
      )
      cases += 1
      if sqrt_actual != checked_expected_sqrt(a) {
        failures.push(
          checked_mismatch(
            "sqrt(" + a + ")",
            context,
            sqrt_actual,
            checked_expected_sqrt(a),
          ),
        )
      }
      for n in -3..<=3 {
        match checked_expected_pown(a, n) {
          None => ()
          Some(expected) => {
            let actual = checked_render(
              @lf_arith.PowIntChecked::pow_int_checked(x, n, context),
            )
            cases += 1
            if actual != expected {
              failures.push(
                checked_mismatch(
                  "pow_int(" + a + ", " + n.to_string() + ")",
                  context,
                  actual,
                  expected,
                ),
              )
            }
            if n >= 0 {
              let nat = checked_render(
                @lf_arith.PowNatChecked::pow_nat_checked(
                  x,
                  n.reinterpret_as_uint(),
                  context,
                ),
              )
              cases += 1
              if nat != expected {
                failures.push(
                  checked_mismatch(
                    "pow_nat(" + a + ", " + n.to_string() + ")",
                    context,
                    nat,
                    expected,
                  ),
                )
              }
            }
          }
        }
      }
    }
  }
  assert_eq(failures, [])
  // 30 contexts x (100 div + 10 sqrt + 68 pow_int + 38 pow_nat) cases.
  assert_eq(cases, 30 * (100 + 10 + 68 + 38))
}

///|
test "inherent checked operations follow the IEEE special-value table" {
  let names = checked_operand_names()
  let failures = []
  for p in [24, 53, 113] {
    for a in names {
      let x = checked_operand(a, p)
      for b in names {
        let actual = checked_render(x.div_checked(checked_operand(b, p)))
        let expected = checked_expected_div(a, b)
        if actual != expected {
          failures.push("div(" + a + ", " + b + "): " + actual)
        }
      }
      let sqrt_actual = checked_render(x.sqrt())
      if sqrt_actual != checked_expected_sqrt(a) {
        failures.push("sqrt(" + a + "): " + sqrt_actual)
      }
      for n in -3..<=3 {
        match checked_expected_pown(a, n) {
          None => ()
          Some(expected) => {
            let pow_int = checked_render(x.pow_int(n))
            let pown = checked_render(x.pown(n))
            if pow_int != expected || pown != expected {
              failures.push(
                "pow_int(" + a + ", " + n.to_string() + "): " + pow_int,
              )
            }
          }
        }
      }
    }
  }
  assert_eq(failures, [])
}

///|
test "checked adapters return range exceptions in Ok" {
  // 7.4 and 7.5: overflow and underflow deliver a default result, they are not
  // invalid operations or divisions by zero.
  let modes = [
    @lf_arith.RoundingMode::ToNearestEven,
    @lf_arith.RoundingMode::TowardZero,
    @lf_arith.RoundingMode::TowardPositive,
    @lf_arith.RoundingMode::TowardNegative,
    @lf_arith.RoundingMode::AwayFromZero,
  ]
  let huge = BinFloat::make(BinCoeff::one(), 1000, 53)
  let tiny = BinFloat::make(BinCoeff::one(), -1000, 53)
  let two = BinFloat::from_int(2)
  for rounding in modes {
    let ctx = @lf_arith.ArithmeticContext::new(
      53,
      rounding~,
      e_min=-1022,
      e_max=1023,
    )
    assert_true(@lf_arith.DivChecked::div_checked(huge, tiny, ctx) is Ok(_))
    assert_true(@lf_arith.DivChecked::div_checked(tiny, huge, ctx) is Ok(_))
    assert_true(
      @lf_arith.PowIntChecked::pow_int_checked(two, 2000, ctx) is Ok(_),
    )
    assert_true(
      @lf_arith.PowIntChecked::pow_int_checked(two, -2000, ctx) is Ok(_),
    )
    assert_true(
      @lf_arith.PowNatChecked::pow_nat_checked(two, 2000U, ctx) is Ok(_),
    )
  }
}
