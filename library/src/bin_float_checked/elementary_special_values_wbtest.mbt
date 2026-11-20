// Exception contract of the elementary `BinFloatResult` methods (#290).
//
// The checked result is the IEEE 754-2019 default result with the invalid
// operation exception (section 7.2) as `DomainError` and divideByZero
// (section 7.3) as `DivisionByZero`, as for `div`, `sqrt` and `pow_int`
// (#262). Section 9.2: "signaling NaN operands shall signal the invalid
// operation exception", "Outside its domain an operation shall return a quiet
// NaN and signal the invalid operation exception", and "An operation that has
// a simple pole for some finite floating-point operand shall signal the
// divideByZero exception". The domains and the other exceptions are those of
// Table 9.1 and the special values of 9.2.1. The oracle below is written from
// those clauses, not from the implementation; overflow, underflow and inexact
// stay in `Ok`.

///|
/// Operand names and their numeric values (NaN names carry 0.0, unused).
fn elementary_operands() -> Array[(String, Double)] {
  [
    ("+qnan", 0.0),
    ("-qnan", 0.0),
    ("+snan", 0.0),
    ("-snan", 0.0),
    ("+0", 0.0),
    ("-0", -0.0),
    ("+inf", elementary_inf),
    ("-inf", -elementary_inf),
    ("1", 1.0),
    ("-1", -1.0),
    ("2", 2.0),
    ("-2", -2.0),
    ("0.5", 0.5),
    ("-0.5", -0.5),
    ("1.5", 1.5),
    ("-1.5", -1.5),
  ]
}

///|
fn elementary_value(name : String, value : Double) -> @bin_float.BinFloat {
  match name {
    "+qnan" => @bin_float.BinFloat::quiet_nan(precision=53)
    "-qnan" => @bin_float.BinFloat::quiet_nan(negative=true, precision=53)
    "+snan" => @bin_float.BinFloat::signaling_nan(precision=53)
    "-snan" => @bin_float.BinFloat::signaling_nan(negative=true, precision=53)
    _ => @bin_float.BinFloat::from_double(value, precision=53)
  }
}

///|
fn elementary_render(result : BinFloatResult) -> String {
  match result.result() {
    Err(error) =>
      match error.kind {
        @lf_arith.ArithmeticErrorKind::DivisionByZero => "err:div0"
        @lf_arith.ArithmeticErrorKind::DomainError => "err:invalid"
        _ => "err:other(" + error.message + ")"
      }
    Ok(value) =>
      if value.classify() == @def.FpClass::NaN {
        if value.is_signaling_nan() {
          "ok:snan"
        } else {
          "ok:nan"
        }
      } else {
        "ok"
      }
  }
}

///|
fn elementary_is_snan(name : String) -> Bool {
  name.has_suffix("snan")
}

///|
fn elementary_is_nan(name : String) -> Bool {
  name.has_suffix("nan")
}

///|
fn elementary_is_integer(value : Double) -> Bool {
  value.abs() != elementary_inf && value == value.floor()
}

///|
/// Expected outcome of a unary operation from Table 9.1 and 9.2.1.
fn elementary_expected_unary(op : String, name : String, x : Double) -> String {
  if elementary_is_snan(name) {
    return "err:invalid" // 9.2, 7.2 a)
  }
  if elementary_is_nan(name) {
    return "ok:nan" // 6.2, 9.2
  }
  let infinite = x.abs() == elementary_inf
  match op {
    // log, log2, log10: x = 0 divideByZero; x < 0 invalid.
    "ln" | "log2" | "log10" =>
      if x == 0.0 {
        "err:div0"
      } else if x < 0.0 {
        "err:invalid"
      } else {
        "ok"
      }
    // logp1: x = -1 divideByZero; x < -1 invalid.
    "log1p" =>
      if x == -1.0 {
        "err:div0"
      } else if x < -1.0 {
        "err:invalid"
      } else {
        "ok"
      }
    // acosh: x < 1 invalid.
    "acosh" => if x < 1.0 { "err:invalid" } else { "ok" }
    // atanh: |x| = 1 divideByZero; |x| > 1 invalid.
    "atanh" =>
      if x.abs() == 1.0 {
        "err:div0"
      } else if x.abs() > 1.0 {
        "err:invalid"
      } else {
        "ok"
      }
    // asin, acos: |x| > 1 invalid.
    "asin" | "acos" => if x.abs() > 1.0 { "err:invalid" } else { "ok" }
    // sin, cos, tan, sinPi, cosPi: |x| = inf invalid.
    "sin" | "cos" | "tan" | "sinpi" | "cospi" =>
      if infinite {
        "err:invalid"
      } else {
        "ok"
      }
    // tanPi: |x| = inf invalid; x = n + 0.5 divideByZero.
    "tanpi" =>
      if infinite {
        "err:invalid"
      } else if elementary_is_integer(x - 0.5) {
        "err:div0"
      } else {
        "ok"
      }
    // exp family, sinh, cosh, tanh, asinh, atan and the fused ln(exp(x)):
    // only overflow and underflow besides a signaling NaN.
    _ => "ok"
  }
}

///|
fn elementary_unary(
  op : String,
  x : BinFloatResult,
  ctx : @bin_float.BinaryContext?,
) -> BinFloatResult {
  match (op, ctx) {
    ("exp", None) => x.exp()
    ("exp", Some(c)) => x.exp_ctx(c)
    ("expm1", None) => x.expm1()
    ("expm1", Some(c)) => x.expm1_ctx(c)
    ("exp2", None) => x.exp2()
    ("exp2", Some(c)) => x.exp2_ctx(c)
    ("exp10", None) => x.exp10()
    ("exp10", Some(c)) => x.exp10_ctx(c)
    ("ln", None) => x.ln()
    ("ln", Some(c)) => x.ln_ctx(c)
    ("log1p", None) => x.log1p()
    ("log1p", Some(c)) => x.log1p_ctx(c)
    ("log2", None) => x.log2()
    ("log2", Some(c)) => x.log2_ctx(c)
    ("log10", None) => x.log10()
    ("log10", Some(c)) => x.log10_ctx(c)
    ("sinh", None) => x.sinh()
    ("sinh", Some(c)) => x.sinh_ctx(c)
    ("cosh", None) => x.cosh()
    ("cosh", Some(c)) => x.cosh_ctx(c)
    ("tanh", None) => x.tanh()
    ("tanh", Some(c)) => x.tanh_ctx(c)
    ("asinh", None) => x.asinh()
    ("asinh", Some(c)) => x.asinh_ctx(c)
    ("acosh", None) => x.acosh()
    ("acosh", Some(c)) => x.acosh_ctx(c)
    ("atanh", None) => x.atanh()
    ("atanh", Some(c)) => x.atanh_ctx(c)
    ("atan", None) => x.atan()
    ("atan", Some(c)) => x.atan_ctx(c)
    ("asin", None) => x.asin()
    ("asin", Some(c)) => x.asin_ctx(c)
    ("acos", None) => x.acos()
    ("acos", Some(c)) => x.acos_ctx(c)
    ("sin", None) => x.sin()
    ("sin", Some(c)) => x.sin_ctx(c)
    ("cos", None) => x.cos()
    ("cos", Some(c)) => x.cos_ctx(c)
    ("tan", None) => x.tan()
    ("tan", Some(c)) => x.tan_ctx(c)
    ("sinpi", None) => x.sinpi()
    ("sinpi", Some(c)) => x.sinpi_ctx(c)
    ("cospi", None) => x.cospi()
    ("cospi", Some(c)) => x.cospi_ctx(c)
    ("tanpi", None) => x.tanpi()
    ("tanpi", Some(c)) => x.tanpi_ctx(c)
    _ => abort("unknown operation " + op)
  }
}

///|
fn elementary_unary_ops() -> Array[String] {
  [
    "exp", "expm1", "exp2", "exp10", "ln", "log1p", "log2", "log10", "sinh", "cosh",
    "tanh", "asinh", "acosh", "atanh", "atan", "asin", "acos", "sin", "cos", "tan",
    "sinpi", "cospi", "tanpi",
  ]
}

///|
fn elementary_contexts() -> Array[@bin_float.BinaryContext?] {
  [None, Some(@bin_float.BinaryContext::binary64())]
}

///|
test "elementary BinFloatResult methods map exceptions to errors" {
  let failures = []
  let mut cases = 0
  for ctx in elementary_contexts() {
    for op in elementary_unary_ops() {
      for operand in elementary_operands() {
        let (name, x) = operand
        let actual = elementary_render(
          elementary_unary(
            op,
            BinFloatResult::ok(elementary_value(name, x)),
            ctx,
          ),
        )
        let expected = elementary_expected_unary(op, name, x)
        cases += 1
        if actual != expected {
          let form = if ctx is None { "" } else { "_ctx" }
          failures.push(
            op +
            form +
            "(" +
            name +
            "): got " +
            actual +
            ", expected " +
            expected,
          )
        }
      }
    }
  }
  assert_eq(failures, [])
  // 2 forms x 23 operations x 16 operands.
  assert_eq(cases, 2 * 23 * 16)
}

///|
/// Expected `pow(x, y)` from 9.2.1 and Table 9.1, or `None` for the two
/// shortcuts whose signaling NaN handling is #289 (`pow(sNaN, +-0)` and
/// `pow(+1, sNaN)`).
fn elementary_expected_pow(
  xn : String,
  x : Double,
  yn : String,
  y : Double,
) -> String? {
  let x_nan = elementary_is_nan(xn)
  let y_nan = elementary_is_nan(yn)
  if (elementary_is_snan(xn) && !y_nan && y == 0.0) ||
    (elementary_is_snan(yn) && !x_nan && x == 1.0) {
    return None
  }
  if elementary_is_snan(xn) || elementary_is_snan(yn) {
    return Some("err:invalid") // 9.2, 7.2 a)
  }
  // pow(x, +-0) is 1 if x is not a signaling NaN; pow(+1, y) is 1 for any y
  // (even a quiet NaN).
  if (!y_nan && y == 0.0) || (!x_nan && x == 1.0) {
    return Some("ok")
  }
  if x_nan || y_nan {
    return Some("ok:nan")
  }
  let y_finite = y.abs() != elementary_inf
  if x == 0.0 && y_finite && y < 0.0 {
    // pow(+-0, y) signals divideByZero for finite y < 0 (odd integer or not).
    return Some("err:div0")
  }
  if x < 0.0 && x != -elementary_inf && y_finite && !elementary_is_integer(y) {
    // pow(x, y) signals invalid for finite x < 0 and finite non-integer y.
    return Some("err:invalid")
  }
  Some("ok")
}

///|
test "BinFloatResult pow maps poles and invalid operations" {
  let exponents = [
    ("+qnan", 0.0),
    ("+snan", 0.0),
    ("+0", 0.0),
    ("-0", -0.0),
    ("+inf", elementary_inf),
    ("-inf", -elementary_inf),
    ("1", 1.0),
    ("-1", -1.0),
    ("2", 2.0),
    ("-2", -2.0),
    ("3", 3.0),
    ("0.5", 0.5),
    ("-1.5", -1.5),
    ("2.5", 2.5),
  ]
  let failures = []
  let mut cases = 0
  for ctx in elementary_contexts() {
    for base in elementary_operands() {
      let (xn, x) = base
      for exponent in exponents {
        let (yn, y) = exponent
        match elementary_expected_pow(xn, x, yn, y) {
          None => ()
          Some(expected) => {
            let lhs = BinFloatResult::ok(elementary_value(xn, x))
            let rhs = BinFloatResult::ok(elementary_value(yn, y))
            let result = match ctx {
              None => lhs.pow(rhs)
              Some(c) => lhs.pow_ctx(rhs, c)
            }
            let actual = elementary_render(result)
            cases += 1
            if actual != expected {
              failures.push(
                "pow(" +
                xn +
                ", " +
                yn +
                "): got " +
                actual +
                ", expected " +
                expected,
              )
            }
          }
        }
      }
    }
  }
  assert_eq(failures, [])
  // 16 x 14 pairs minus (2 sNaN bases x 2 zero exponents) and (1 sNaN
  // exponent x base 1), per form.
  assert_eq(cases, 2 * (16 * 14 - 4 - 1))
}

///|
/// Expected `rootn(x, n)` from 9.2.1 and Table 9.1.
fn elementary_expected_rootn(name : String, x : Double, n : Int32) -> String {
  if elementary_is_snan(name) {
    return "err:invalid"
  }
  if n == 0 {
    // Table 9.1 "n = 0: invalid operation", for every x including a quiet NaN
    // and +-0 (#294); it is not divideByZero (7.3).
    return "err:invalid"
  }
  if elementary_is_nan(name) {
    return "ok:nan"
  }
  if x == 0.0 && n < 0 {
    return "err:div0" // rootn(+-0, n) signals divideByZero for n < 0
  }
  if x < 0.0 && n % 2 == 0 {
    return "err:invalid" // x < 0 and n even: invalid operation
  }
  "ok"
}

///|
test "BinFloatResult rootn maps poles and invalid operations" {
  let failures = []
  for ctx in elementary_contexts() {
    for operand in elementary_operands() {
      let (name, x) = operand
      for n in -3..<=3 {
        let value = BinFloatResult::ok(elementary_value(name, x))
        let result = match ctx {
          None => value.rootn(n)
          Some(c) => value.rootn_ctx(n, c)
        }
        let actual = elementary_render(result)
        let expected = elementary_expected_rootn(name, x, n)
        if actual != expected {
          failures.push(
            "rootn(" +
            name +
            ", " +
            n.to_string() +
            "): got " +
            actual +
            ", expected " +
            expected,
          )
        }
      }
    }
  }
  assert_eq(failures, [])
}

///|
test "BinFloatResult hypot and atan2 signal only for signaling NaN" {
  let failures = []
  for ctx in elementary_contexts() {
    for left in elementary_operands() {
      let (ln, l) = left
      for right in elementary_operands() {
        let (rn, r) = right
        let lhs = BinFloatResult::ok(elementary_value(ln, l))
        let rhs = BinFloatResult::ok(elementary_value(rn, r))
        let (hypot, atan2) = match ctx {
          None => (lhs.hypot(rhs), lhs.atan2(rhs))
          Some(c) => (lhs.hypot_ctx(rhs, c), lhs.atan2_ctx(rhs, c))
        }
        let any_snan = elementary_is_snan(ln) || elementary_is_snan(rn)
        let any_nan = elementary_is_nan(ln) || elementary_is_nan(rn)
        let infinite = (!elementary_is_nan(ln) && l.abs() == elementary_inf) ||
          (!elementary_is_nan(rn) && r.abs() == elementary_inf)
        // hypot(+-inf, qNaN) and hypot(qNaN, +-inf) are +inf (9.2.1).
        let expected_hypot = if any_snan {
          "err:invalid"
        } else if any_nan && !infinite {
          "ok:nan"
        } else {
          "ok"
        }
        let expected_atan2 = if any_snan {
          "err:invalid"
        } else if any_nan {
          "ok:nan"
        } else {
          "ok"
        }
        let got_hypot = elementary_render(hypot)
        let got_atan2 = elementary_render(atan2)
        if got_hypot != expected_hypot {
          failures.push("hypot(" + ln + ", " + rn + "): got " + got_hypot)
        }
        if got_atan2 != expected_atan2 {
          failures.push("atan2(" + ln + ", " + rn + "): got " + got_atan2)
        }
      }
    }
  }
  assert_eq(failures, [])
}

///|
test "elementary BinFloatResult methods keep range exceptions in Ok" {
  // 7.4 and 7.5: overflow and underflow deliver a default result.
  let binary64 = @bin_float.BinaryContext::binary64()
  let big = BinFloatResult::from_double(1000.0)
  assert_true(big.exp_ctx(binary64).is_ok())
  assert_true(big.neg().exp_ctx(binary64).is_ok())
  assert_true(big.sinh_ctx(binary64).is_ok())
  assert_true(big.cosh_ctx(binary64).is_ok())
  assert_true(
    BinFloatResult::from_double(10.0)
    .pow_ctx(BinFloatResult::from_double(400.5), binary64)
    .is_ok(),
  )
}

///|
let elementary_inf : Double = 1.0 / 0.0

///|
test "BinFloatResult exp agrees with the ExpContextual trait" {
  // The only elementary arithmetic trait BinFloat implements; it maps the
  // same flags through `binary_contextual_outcome`.
  let ctx = @lf_arith.ArithmeticContext::new(53, e_min=-1022, e_max=1023)
  for operand in elementary_operands() {
    let (name, x) = operand
    let value = elementary_value(name, x)
    let wrapper = elementary_render(
      BinFloatResult::ok(value).exp_ctx(
        @bin_float.BinaryContext::from_arithmetic_context(ctx),
      ),
    )
    let trait_result = match
      @lf_arith.ExpContextual::exp_contextual(value, ctx) {
      Ok(outcome) => elementary_render(BinFloatResult::ok(outcome.value))
      Err(error) => elementary_render(BinFloatResult::err(error))
    }
    assert_eq(name + " " + wrapper, name + " " + trait_result)
  }
}
