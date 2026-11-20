///|
// Differential test of the plain paths of `multiply` and `divide` against the
// general route (`mul_ctx` / `div_ctx` with `complete_decimal_gda`), which is
// the previous behavior of both functions, kept here as reference. Outcomes
// are compared in full (value representation, flags, status of the context,
// trapped or completed), see `gda_add_plain_wbtest.mbt` for the helpers.

///|
fn mul_div_plain_check(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> Unit raise {
  let (value, flags) = lhs.mul_ctx(rhs, ctx.decimal_context())
  let expected_mul = complete_decimal_gda(value, ctx, flags)
  let (value, flags) = lhs.div_ctx(rhs, ctx.decimal_context())
  let expected_div = complete_decimal_gda(value, ctx, flags)
  if !add_plain_same_outcome(multiply(lhs, rhs, ctx), expected_mul) {
    fail(
      "multiply differs: \{lhs.to_sci_string()} * \{rhs.to_sci_string()} precision \{ctx.precision_}",
    )
  }
  if !add_plain_same_outcome(divide(lhs, rhs, ctx), expected_div) {
    fail(
      "divide differs: \{lhs.to_sci_string()} / \{rhs.to_sci_string()} precision \{ctx.precision_}",
    )
  }
}

///|
fn mul_div_plain_run(
  low_digits : Int32,
  high_digits : Int32,
  seed : UInt64,
) -> Unit raise {
  let state = Ref(seed)
  let wide = GdaContext::new(precision=400)
  for _ in 0..<add_plain_cases {
    let ctx = add_plain_context(state)
    let left_digits = add_plain_digits(
      state,
      add_plain_range(state, low_digits, high_digits),
    )
    let left_exponent = add_plain_range(state, -60, 60)
    let right_exponent = left_exponent + add_plain_range(state, -45, 45)
    let kind = add_plain_next(state) % 6UL
    let right_digits = if kind == 0UL {
      left_digits
    } else if kind == 1UL {
      // a divisor that makes finite expansions: 2^a 5^b, powers of ten
      let a = add_plain_range(state, 0, 12)
      let b = add_plain_range(state, 0, 8)
      let mut v = "1"
      for _ in 0..<a {
        v = multiply(
            to_number(v, wide).value(),
            to_number("2", wide).value(),
            wide,
          )
          .value()
          .to_string()
      }
      for _ in 0..<b {
        v = multiply(
            to_number(v, wide).value(),
            to_number("5", wide).value(),
            wide,
          )
          .value()
          .to_string()
      }
      v
    } else if kind == 2UL {
      // a short divisor: repeating expansions (1/3, 1/7, 1/9, 22/7)
      add_plain_digits(state, add_plain_range(state, 1, 2))
    } else {
      add_plain_digits(state, add_plain_range(state, low_digits, high_digits))
    }
    let left_negative = add_plain_next(state) % 2UL == 0UL
    let right_negative = add_plain_next(state) % 2UL == 0UL
    let lhs = add_plain_operand(left_digits, left_exponent, left_negative)
    let rhs = add_plain_operand(right_digits, right_exponent, right_negative)
    mul_div_plain_check(lhs, rhs, ctx)
    mul_div_plain_check(rhs, lhs, ctx)
    // an exact quotient: (lhs * rhs) / rhs
    let product = multiply(lhs, rhs, wide).value()
    mul_div_plain_check(product, rhs, ctx)
    mul_div_plain_check(product, lhs, ctx)
  }
}

///|
test "multiply and divide plain paths equal the general route, 17 to 40 digits" {
  mul_div_plain_run(17, 40, 0x9E3779B97F4A7C15UL)
}

///|
test "multiply and divide plain paths equal the general route, 1 to 16 digits" {
  mul_div_plain_run(1, 16, 0xD1B54A32D192ED03UL)
}

///|
test "multiply and divide plain paths equal the general route, 41 to 120 digits" {
  mul_div_plain_run(41, 120, 0x2545F4914F6CDD1DUL)
}

///|
test "multiply and divide plain paths, carries into the next digit" {
  for precision in [3, 17, 18, 19, 34] {
    for mode in add_plain_modes {
      let ctx = GdaContext::new(precision~, rounding=mode)
      let nines = String::make(precision + 1, '9')
      for other in ["1", "9", "99", "10000000001", "99999999999", "3", "7"] {
        let a = add_plain_operand(nines, 0, false)
        let b = add_plain_operand(other, 0, false)
        mul_div_plain_check(a, b, ctx)
        mul_div_plain_check(b, a, ctx)
        mul_div_plain_check(a.neg(), b, ctx)
        mul_div_plain_check(a, a, ctx)
      }
    }
  }
}

///|
test "multiply and divide plain paths, chained contexts" {
  let state = Ref(0xBF58476D1CE4E5B9UL)
  for _ in 0..<add_plain_cases {
    let first = add_plain_context(state)
    let mut plain_ctx = first
    let mut general_ctx = first
    let mut acc_plain = add_plain_operand("17", 0, false)
    let mut acc_general = acc_plain
    for _ in 0..<5 {
      let digits = add_plain_digits(state, add_plain_range(state, 1, 45))
      let operand = add_plain_operand(
        digits,
        add_plain_range(state, -30, 30),
        add_plain_next(state) % 2UL == 0UL,
      )
      let divide_it = add_plain_next(state) % 2UL == 0UL
      let outcome = if divide_it {
        divide(acc_plain, operand, plain_ctx)
      } else {
        multiply(acc_plain, operand, plain_ctx)
      }
      let (value, flags) = if divide_it {
        acc_general.div_ctx(operand, general_ctx.decimal_context())
      } else {
        acc_general.mul_ctx(operand, general_ctx.decimal_context())
      }
      let expected = complete_decimal_gda(value, general_ctx, flags)
      if !add_plain_same_outcome(outcome, expected) {
        fail("chained multiply or divide differs")
      }
      acc_plain = outcome.value()
      acc_general = expected.value()
      plain_ctx = outcome.next_context()
      general_ctx = expected.next_context()
    }
  }
}
