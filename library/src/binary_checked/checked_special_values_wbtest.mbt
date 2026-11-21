// `BinaryChecked` special-value contract (#262): the checked result is the
// IEEE 754-2019 default result, the invalid operation exception (section 7.2)
// is `Err(DomainError)` and divideByZero (section 7.3) is
// `Err(DivisionByZero)`. The oracle mirrors the one in
// `src/binary/checked_special_values_wbtest.mbt`.

///|
fn wrapper_names() -> Array[String] {
  ["+qnan", "-qnan", "+snan", "-snan", "+0", "-0", "+inf", "-inf", "+2", "-2"]
}

///|
fn wrapper_operand(name : String, precision : Int32) -> BinaryChecked {
  BinaryChecked::ok(
    match name {
      "+qnan" => @binary.Binary::quiet_nan(precision~)
      "-qnan" => @binary.Binary::quiet_nan(negative=true, precision~)
      "+snan" => @binary.Binary::signaling_nan(precision~)
      "-snan" => @binary.Binary::signaling_nan(negative=true, precision~)
      "+0" => @binary.Binary::zero(precision~)
      "-0" => @binary.Binary::negative_zero(precision~)
      "+inf" => @binary.Binary::inf(precision~)
      "-inf" => @binary.Binary::inf(negative=true, precision~)
      "+2" => @binary.Binary::from_int(2, precision~)
      "-2" => @binary.Binary::from_int(-2, precision~)
      _ => abort("unknown operand " + name)
    },
  )
}

///|
fn wrapper_render(result : BinaryChecked) -> String {
  match result.result() {
    Err(error) =>
      match error.kind {
        @lf_arith.ArithmeticErrorKind::DivisionByZero => "err:div0"
        @lf_arith.ArithmeticErrorKind::DomainError => "err:invalid"
        _ => "err:other"
      }
    Ok(value) => {
      let sign = if value.is_negative() { "-" } else { "+" }
      match value.classify() {
        @def.FpClass::NaN =>
          if value.is_signaling_nan() {
            "ok:snan"
          } else {
            "ok:nan"
          }
        @def.FpClass::Infinity => "ok:" + sign + "inf"
        @def.FpClass::Finite =>
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
fn wrapper_signed(negative : Bool, magnitude : String) -> String {
  "ok:" + (if negative { "-" } else { "+" }) + magnitude
}

///|
fn wrapper_expected_div(a : String, b : String) -> String {
  let negative = a.has_prefix("-") != b.has_prefix("-")
  if a.has_suffix("snan") || b.has_suffix("snan") {
    "err:invalid" // 7.2 a)
  } else if a.has_suffix("nan") || b.has_suffix("nan") {
    "ok:nan" // 6.2
  } else if (a.has_suffix("0") && b.has_suffix("0")) ||
    (a.has_suffix("inf") && b.has_suffix("inf")) {
    "err:invalid" // 7.2 e)
  } else if a.has_suffix("inf") {
    wrapper_signed(negative, "inf")
  } else if b.has_suffix("0") {
    "err:div0" // 7.3
  } else if b.has_suffix("inf") || a.has_suffix("0") {
    wrapper_signed(negative, "0")
  } else {
    wrapper_signed(negative, "fin")
  }
}

///|
fn wrapper_expected_sqrt(a : String) -> String {
  if a.has_suffix("snan") {
    "err:invalid" // 7.2 a)
  } else if a.has_suffix("nan") {
    "ok:nan" // 6.2
  } else if a.has_suffix("0") {
    wrapper_signed(a.has_prefix("-"), "0")
  } else if a.has_prefix("-") {
    "err:invalid" // 7.2 g)
  } else if a.has_suffix("inf") {
    "ok:+inf"
  } else {
    "ok:+fin"
  }
}

///|
/// 9.2.1 pown; pown(sNaN, 0) is an invalid operation (7.2 a), #286).
fn wrapper_expected_pown(a : String, n : Int32) -> String {
  let negative = a.has_prefix("-") && n % 2 != 0
  if n == 0 {
    if a.has_suffix("snan") {
      "err:invalid"
    } else {
      "ok:+fin"
    }
  } else if a.has_suffix("snan") {
    "err:invalid"
  } else if a.has_suffix("nan") {
    "ok:nan"
  } else if a.has_suffix("0") {
    if n < 0 {
      "err:div0"
    } else {
      wrapper_signed(negative, "0")
    }
  } else if a.has_suffix("inf") {
    wrapper_signed(negative, if n < 0 { "0" } else { "inf" })
  } else {
    wrapper_signed(negative, "fin")
  }
}

///|
test "BinaryChecked follows the IEEE special-value table" {
  let names = wrapper_names()
  let failures = []
  let mut cases = 0
  for p in [24, 53, 113] {
    for a in names {
      let x = wrapper_operand(a, p)
      for b in names {
        let y = wrapper_operand(b, p)
        let expected = wrapper_expected_div(a, b)
        let via_method = wrapper_render(x.div(y))
        let via_operator = wrapper_render(x / y)
        cases += 2
        if via_method != expected || via_operator != expected {
          failures.push(
            "div(" + a + ", " + b + "): " + via_method + " " + via_operator,
          )
        }
      }
      let sqrt = wrapper_render(x.sqrt())
      cases += 1
      if sqrt != wrapper_expected_sqrt(a) {
        failures.push("sqrt(" + a + "): " + sqrt)
      }
      for n in -3..<=3 {
        let expected = wrapper_expected_pown(a, n)
        let pown = wrapper_render(x.pown(n))
        cases += 1
        if pown != expected {
          failures.push("pown(" + a + ", " + n.to_string() + "): " + pown)
        }
        if n >= 0 {
          let nat = wrapper_render(x.pow_nat(n.reinterpret_as_uint()))
          cases += 1
          if nat != expected {
            failures.push("pow_nat(" + a + ", " + n.to_string() + "): " + nat)
          }
        }
      }
    }
  }
  assert_eq(failures, [])
  assert_eq(cases, 3 * (200 + 10 + 70 + 40))
}
