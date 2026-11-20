// One flag rule for every `BinFloatResult::*_ctx` method (#371): `x_ctx` is
// `x` with an explicit context and the same map kappa. Invalid operation
// (IEEE 754-2019 section 7.2) is `Err(DomainError)`, divideByZero (section
// 7.3) is `Err(DivisionByZero)`, and overflow, underflow and inexact are
// dropped. The oracle below is written from the clauses, not from the
// flags that `BinFloat::*_ctx` returns.

///|
fn ctx_rule_class(name : String) -> String {
  match name {
    "+qnan" | "-qnan" => "qnan"
    "+snan" | "-snan" => "snan"
    "+0" | "-0" => "zero"
    "+inf" | "-inf" => "inf"
    _ => "fin"
  }
}

///|
fn ctx_rule_negative(name : String) -> Bool {
  name.has_prefix("-")
}

///|
/// Expected exception of a binary operation: "invalid", "div0" or "ok".
fn ctx_rule_expect(op : String, a : String, b : String) -> String {
  let ca = ctx_rule_class(a)
  let cb = ctx_rule_class(b)
  // 6.2 / 7.2 a): a signaling NaN operand is invalid.
  if ca == "snan" || cb == "snan" {
    return "invalid"
  }
  // 6.2: a quiet NaN operand signals nothing.
  if ca == "qnan" || cb == "qnan" {
    return "ok"
  }
  match op {
    // 7.2 d): magnitude subtraction of infinities.
    "add" =>
      if ca == "inf" &&
        cb == "inf" &&
        ctx_rule_negative(a) != ctx_rule_negative(b) {
        "invalid"
      } else {
        "ok"
      }
    "sub" =>
      if ca == "inf" &&
        cb == "inf" &&
        ctx_rule_negative(a) == ctx_rule_negative(b) {
        "invalid"
      } else {
        "ok"
      }
    // 7.2 b): multiplication(0, inf) and multiplication(inf, 0).
    "mul" =>
      if (ca == "zero" && cb == "inf") || (ca == "inf" && cb == "zero") {
        "invalid"
      } else {
        "ok"
      }
    // 7.2 e): division(0, 0) and division(inf, inf); 7.3: finite nonzero / 0.
    "div" =>
      if (ca == "zero" && cb == "zero") || (ca == "inf" && cb == "inf") {
        "invalid"
      } else if ca == "fin" && cb == "zero" {
        "div0"
      } else {
        "ok"
      }
    _ => abort("unknown operation " + op)
  }
}

///|
fn ctx_rule_contexts() -> Array[(String, @bin_float.BinaryContext)] {
  let modes : Array[(String, @bin_float.BinaryRoundingMode)] = [
    ("ties-even", RoundTiesToEven),
    ("ties-away", RoundTiesToAway),
    ("toward-zero", RoundTowardZero),
    ("toward-positive", RoundTowardPositive),
    ("toward-negative", RoundTowardNegative),
    ("away-from-zero", RoundAwayFromZero),
  ]
  let out = []
  for pair in modes {
    let (label, mode) = pair
    out.push(
      ("binary64/" + label, @bin_float.BinaryContext::binary64(rounding=mode)),
    )
    out.push(
      (
        "unbounded53/" + label,
        @bin_float.BinaryContext::unbounded(53, rounding=mode),
      ),
    )
  }
  out
}

///|
fn ctx_rule_check(
  label : String,
  expected : String,
  actual : BinFloatResult,
  unwrapped : @bin_float.BinFloat,
) -> Unit raise {
  let rendered = wrapper_render(actual)
  match expected {
    "invalid" => assert_eq(rendered, "err:invalid", msg=label)
    "div0" => assert_eq(rendered, "err:div0", msg=label)
    _ =>
      assert_eq(
        rendered,
        wrapper_render(BinFloatResult::ok(unwrapped)),
        msg=label,
      )
  }
}

///|
test "ctx rule: add sub mul div map the flags, both operand orders, every rounding" {
  for ctx_pair in ctx_rule_contexts() {
    let (cname, ctx) = ctx_pair
    for a in wrapper_names() {
      for b in wrapper_names() {
        let x = wrapper_operand(a, 53)
        let y = wrapper_operand(b, 53)
        let xv = x.result().unwrap()
        let yv = y.result().unwrap()
        let tag = cname + " " + a + " " + b
        ctx_rule_check(
          "add " + tag,
          ctx_rule_expect("add", a, b),
          x.add_ctx(y, ctx),
          xv.add_ctx(yv, ctx).0,
        )
        ctx_rule_check(
          "sub " + tag,
          ctx_rule_expect("sub", a, b),
          x.sub_ctx(y, ctx),
          xv.sub_ctx(yv, ctx).0,
        )
        ctx_rule_check(
          "mul " + tag,
          ctx_rule_expect("mul", a, b),
          x.mul_ctx(y, ctx),
          xv.mul_ctx(yv, ctx).0,
        )
        ctx_rule_check(
          "div " + tag,
          ctx_rule_expect("div", a, b),
          x.div_ctx(y, ctx),
          xv.div_ctx(yv, ctx).0,
        )
      }
    }
  }
}

///|
test "ctx rule: sqrt_ctx" {
  for ctx_pair in ctx_rule_contexts() {
    let (cname, ctx) = ctx_pair
    for a in wrapper_names() {
      let x = wrapper_operand(a, 53)
      let xv = x.result().unwrap()
      // 7.2 g): squareRoot of a value less than zero; sqrt(-0) is -0.
      let expected = match ctx_rule_class(a) {
        "snan" => "invalid"
        "fin" | "inf" => if ctx_rule_negative(a) { "invalid" } else { "ok" }
        _ => "ok"
      }
      ctx_rule_check(
        "sqrt " + cname + " " + a,
        expected,
        x.sqrt_ctx(ctx),
        xv.sqrt_ctx(ctx).0,
      )
    }
  }
}

///|
test "ctx rule: pown_ctx" {
  for ctx_pair in ctx_rule_contexts() {
    let (cname, ctx) = ctx_pair
    for a in wrapper_names() {
      for n in [-3, -2, -1, 0, 1, 2, 3] {
        let x = wrapper_operand(a, 53)
        let xv = x.result().unwrap()
        // 9.2.1: pown(+-0, n) with n < 0 signals divideByZero; pown(x, 0) is 1
        // unless x is a signaling NaN (7.2 a)).
        let expected = match ctx_rule_class(a) {
          "snan" => "invalid"
          "zero" => if n < 0 { "div0" } else { "ok" }
          _ => "ok"
        }
        let tag = cname + " " + a + " n=" + n.to_string()
        ctx_rule_check(
          "pown " + tag,
          expected,
          x.pown_ctx(n, ctx),
          xv.pown_ctx(n, ctx).0,
        )
      }
    }
  }
}

///|
test "ctx rule: overflow, underflow and inexact stay Ok" {
  let b64 = @bin_float.BinaryContext::binary64()
  let big = BinFloatResult::from_double(1.0e300)
  let tiny = BinFloatResult::from_double(1.0e-300)
  let three = BinFloatResult::from_int(3)
  let one = BinFloatResult::from_int(1)
  // overflow
  assert_true(big.mul_ctx(big, b64).is_ok())
  assert_true(big.add_ctx(big, b64).is_ok() && big.div_ctx(tiny, b64).is_ok())
  assert_true(big.pown_ctx(2, b64).is_ok())
  // underflow
  assert_true(tiny.mul_ctx(tiny, b64).is_ok())
  assert_true(tiny.div_ctx(big, b64).is_ok())
  assert_true(tiny.pown_ctx(2, b64).is_ok())
  assert_true(tiny.sqrt_ctx(b64).is_ok())
  // inexact
  assert_true(one.div_ctx(three, b64).is_ok())
  assert_true(three.sqrt_ctx(b64).is_ok())
  // a quiet NaN operand and the exact infinities are values
  let q = wrapper_operand("+qnan", 53)
  assert_eq(wrapper_render(one.add_ctx(q, b64)), "ok:nan")
  assert_eq(
    wrapper_render(one.div_ctx(wrapper_operand("+inf", 53), b64)),
    "ok:+0",
  )
  assert_eq(
    wrapper_render(
      wrapper_operand("+inf", 53).div_ctx(BinFloatResult::from_int(0), b64),
    ),
    "ok:+inf",
  )
}

///|
test "ctx rule: x_ctx agrees with x on errors for the default context" {
  let ctx = @bin_float.BinaryContext::unbounded(53)
  for a in wrapper_names() {
    for b in wrapper_names() {
      let x = wrapper_operand(a, 53)
      let y = wrapper_operand(b, 53)
      let plain = wrapper_render(x.div(y))
      let ctxed = wrapper_render(x.div_ctx(y, ctx))
      if plain.has_prefix("err:") {
        assert_eq(ctxed, plain, msg="div " + a + " " + b)
      }
    }
  }
}
