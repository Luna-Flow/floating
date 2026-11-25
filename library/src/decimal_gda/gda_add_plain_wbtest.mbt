///|
// Differential test of the plain path of `add` and `subtract` against the
// general route (`add_ctx` / `sub_ctx` with `complete_decimal_gda`), which is
// the previous behavior of both functions, kept here as reference. Outcomes
// are compared in full: representation of the value (class, sign, exponent,
// coefficient and its storage variant, stored precision), the flags raised,
// the status of the returned context, and trapped or completed.

///|
let add_plain_cases : Int32 = 300

///|
fn add_plain_next(state : Ref[UInt64]) -> UInt64 {
  let mut x = state.val
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  state.val = x
  x
}

///|
fn add_plain_range(state : Ref[UInt64], low : Int32, high : Int32) -> Int32 {
  low + (add_plain_next(state) % (high - low + 1).to_uint64()).to_int()
}

///|
fn add_plain_digits(state : Ref[UInt64], count : Int32) -> String {
  let builder = StringBuilder()
  for index in 0..<count {
    // runs of nines and zeros so that carries and cancellations occur
    let pick = add_plain_next(state) % 8UL
    let digit = if pick == 0UL {
      9
    } else if pick == 1UL {
      0
    } else {
      (add_plain_next(state) % 10UL).to_int()
    }
    builder.write_string(
      if index == 0 && digit == 0 {
        "1"
      } else {
        digit.to_string()
      },
    )
  }
  builder.to_string()
}

///|
fn add_plain_operand(
  digits : String,
  exponent : Int32,
  negative : Bool,
) -> Decimal {
  let wide = GdaContext::new(precision=400)
  let text = (if negative { "-" } else { "" }) +
    digits +
    "E" +
    exponent.to_string()
  to_number(text, wide).value()
}

///|
fn add_plain_same_coefficient(a : DecCoeff, b : DecCoeff) -> Bool {
  match (a, b) {
    (Small(x), Small(y)) => x == y
    (Limbs(x, dx), Limbs(y, dy)) => dx == dy && x == y
    _ => false
  }
}

///|
fn add_plain_same_decimal(a : Decimal, b : Decimal) -> Bool {
  a.class == b.class &&
  a.negative == b.negative &&
  a.exponent10 == b.exponent10 &&
  a.precision_ == b.precision_ &&
  a.signaling_nan == b.signaling_nan &&
  add_plain_same_coefficient(a.coefficient, b.coefficient)
}

///|
fn add_plain_same_outcome(
  a : GdaOutcome[Decimal],
  b : GdaOutcome[Decimal],
) -> Bool {
  match (a, b) {
    (Completed(v, c, f), Completed(w, d, g)) =>
      add_plain_same_decimal(v, w) && c.flags_ == d.flags_ && f == g
    (Trapped(s, v, c, f), Trapped(t, w, d, g)) =>
      s == t && add_plain_same_decimal(v, w) && c.flags_ == d.flags_ && f == g
    _ => false
  }
}

///|
fn add_plain_check(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> Unit raise {
  let (value, flags) = lhs.add_ctx(rhs, ctx.decimal_context())
  let expected_add = complete_decimal_gda(value, ctx, flags)
  let (value, flags) = lhs.sub_ctx(rhs, ctx.decimal_context())
  let expected_sub = complete_decimal_gda(value, ctx, flags)
  if !add_plain_same_outcome(add(lhs, rhs, ctx), expected_add) {
    fail(
      "add differs: \{lhs.to_sci_string()} + \{rhs.to_sci_string()} precision \{ctx.precision_}",
    )
  }
  if !add_plain_same_outcome(subtract(lhs, rhs, ctx), expected_sub) {
    fail(
      "subtract differs: \{lhs.to_sci_string()} - \{rhs.to_sci_string()} precision \{ctx.precision_}",
    )
  }
}

///|
let add_plain_modes : Array[GdaRoundingMode] = [
  HalfEven,
  HalfUp,
  HalfDown,
  Down,
  Ceiling,
  Floor,
  Up,
  ZeroFiveUp,
]

///|
fn add_plain_context(state : Ref[UInt64]) -> GdaContext {
  let precisions = [16, 17, 18, 19, 20, 25, 34, 40, 3, 1]
  let precision = precisions[(add_plain_next(state) % 10UL).to_int()]
  let mode = add_plain_modes[(add_plain_next(state) % 8UL).to_int()]
  let tight = add_plain_next(state) % 5UL == 0UL
  let clamp = add_plain_next(state) % 9UL == 0UL
  let traps = match add_plain_next(state) % 6UL {
    0UL => GdaTrapSet::new().with_signal(Inexact)
    1UL => GdaTrapSet::new().with_signal(Rounded)
    _ => GdaTrapSet::new()
  }
  let extended = add_plain_next(state) % 6UL != 0UL
  GdaContext::new(
    precision~,
    extended~,
    rounding=mode,
    e_min=if tight { -100 } else { -999999 },
    e_max=if tight { 100 } else { 999999 },
    clamp~,
    traps~,
  )
}

///|
fn add_plain_run(
  low_digits : Int32,
  high_digits : Int32,
  seed : UInt64,
) -> Unit raise {
  let state = Ref(seed)
  for _ in 0..<add_plain_cases {
    let ctx = add_plain_context(state)
    let left_digits = add_plain_digits(
      state,
      add_plain_range(state, low_digits, high_digits),
    )
    let right_kind = add_plain_next(state) % 4UL
    let left_exponent = add_plain_range(state, -60, 60)
    let left_negative = add_plain_next(state) % 2UL == 0UL
    let right_negative = add_plain_next(state) % 2UL == 0UL
    let right_digits = if right_kind == 0UL {
      // the same digits: cancellation or doubling, exact halves
      left_digits
    } else if right_kind == 1UL {
      // the digits with the last ones changed: near cancellation
      let keep = left_digits.length() - 2
      if keep > 0 {
        left_digits[:keep].to_owned() + add_plain_digits(state, 2)
      } else {
        left_digits
      }
    } else {
      add_plain_digits(state, add_plain_range(state, low_digits, high_digits))
    }
    let gap = if add_plain_next(state) % 3UL == 0UL {
      add_plain_range(state, -3, 3)
    } else {
      add_plain_range(state, -45, 45)
    }
    let lhs = add_plain_operand(left_digits, left_exponent, left_negative)
    let rhs = add_plain_operand(
      right_digits,
      left_exponent + gap,
      right_negative,
    )
    add_plain_check(lhs, rhs, ctx)
    add_plain_check(rhs, lhs, ctx)
  }
}

///|
// oracle: E
// source: the previous behaviour of the operation kept in the test: the general route at the public level, compared in full (value representation, flags raised, status of the next context, trapped or completed)
// shares: complete_decimal_gda, add_ctx, sub_ctx, the operand builder to_number
// underneath: the general route (add_ctx, sub_ctx, mul_ctx, div_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic without traps: the official decTest corpus (gate stages DECIMAL_GDA: official decTest and official0) and the CPython rows of plain_operator_rows_wbtest.mbt (precision 3, 16, 34); traps, the chaining of the status and the subset arithmetic (extended false) have no level A or B oracle, so those inputs stay level E
test "add and subtract plain path equals the general route, 17 to 40 digits" {
  add_plain_run(17, 40, 0x9E3779B97F4A7C15UL)
}

///|
// oracle: E
// source: the previous behaviour of the operation kept in the test: the general route at the public level, compared in full (value representation, flags raised, status of the next context, trapped or completed)
// shares: complete_decimal_gda, add_ctx, sub_ctx, the operand builder to_number
// underneath: the general route (add_ctx, sub_ctx, mul_ctx, div_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic without traps: the official decTest corpus (gate stages DECIMAL_GDA: official decTest and official0) and the CPython rows of plain_operator_rows_wbtest.mbt (precision 3, 16, 34); traps, the chaining of the status and the subset arithmetic (extended false) have no level A or B oracle, so those inputs stay level E
test "add and subtract plain path equals the general route, 1 to 16 digits" {
  add_plain_run(1, 16, 0xD1B54A32D192ED03UL)
}

///|
// oracle: E
// source: the previous behaviour of the operation kept in the test: the general route at the public level, compared in full (value representation, flags raised, status of the next context, trapped or completed)
// shares: complete_decimal_gda, add_ctx, sub_ctx, the operand builder to_number
// underneath: the general route (add_ctx, sub_ctx, mul_ctx, div_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic without traps: the official decTest corpus (gate stages DECIMAL_GDA: official decTest and official0) and the CPython rows of plain_operator_rows_wbtest.mbt (precision 3, 16, 34); traps, the chaining of the status and the subset arithmetic (extended false) have no level A or B oracle, so those inputs stay level E
test "add and subtract plain path equals the general route, 41 to 120 digits" {
  add_plain_run(41, 120, 0x2545F4914F6CDD1DUL)
}

///|
// oracle: E
// source: the previous behaviour of the operation kept in the test: the general route at the public level, compared in full (value representation, flags raised, status of the next context, trapped or completed)
// shares: complete_decimal_gda, add_ctx, sub_ctx, the operand builder to_number
// underneath: the general route (add_ctx, sub_ctx, mul_ctx, div_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic without traps: the official decTest corpus (gate stages DECIMAL_GDA: official decTest and official0) and the CPython rows of plain_operator_rows_wbtest.mbt (precision 3, 16, 34); traps, the chaining of the status and the subset arithmetic (extended false) have no level A or B oracle, so those inputs stay level E
test "add and subtract plain path, carries into the next digit" {
  // 99..9 plus a small amount rounds up to 10^p at several precisions
  for precision in [3, 17, 18, 19, 34] {
    for extra in [0, 1, 2, 5] {
      for mode in add_plain_modes {
        let ctx = GdaContext::new(precision~, rounding=mode)
        let nines = String::make(precision + extra, '9')
        let lhs = add_plain_operand(nines, 0, false)
        for tail in ["1", "5", "49", "50", "51", "9"] {
          let rhs = add_plain_operand(tail, -tail.length() - 1, false)
          add_plain_check(lhs, rhs, ctx)
          add_plain_check(lhs.neg(), rhs.neg(), ctx)
          add_plain_check(lhs, rhs.neg(), ctx)
        }
      }
    }
  }
}

///|
// oracle: E
// source: the previous behaviour of the operation kept in the test: the general route at the public level, compared in full (value representation, flags raised, status of the next context, trapped or completed)
// shares: complete_decimal_gda, add_ctx, sub_ctx, the operand builder to_number
// underneath: the general route (add_ctx, sub_ctx, mul_ctx, div_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic without traps: the official decTest corpus (gate stages DECIMAL_GDA: official decTest and official0) and the CPython rows of plain_operator_rows_wbtest.mbt (precision 3, 16, 34); traps, the chaining of the status and the subset arithmetic (extended false) have no level A or B oracle, so those inputs stay level E
test "add and subtract plain path, chained contexts" {
  // the status of the context accumulates over a chain of operations; both
  // routes are fed their own copy of the chain and must agree at every step
  let state = Ref(0x94D049BB133111EBUL)
  for _ in 0..<add_plain_cases {
    let first = add_plain_context(state)
    let mut plain_ctx = first
    let mut general_ctx = first
    let mut acc_plain = add_plain_operand("1", 0, false)
    let mut acc_general = acc_plain
    for _ in 0..<5 {
      let digits = add_plain_digits(state, add_plain_range(state, 1, 45))
      let operand = add_plain_operand(
        digits,
        add_plain_range(state, -30, 30),
        add_plain_next(state) % 2UL == 0UL,
      )
      let subtract_it = add_plain_next(state) % 2UL == 0UL
      let outcome = if subtract_it {
        subtract(acc_plain, operand, plain_ctx)
      } else {
        add(acc_plain, operand, plain_ctx)
      }
      let (value, flags) = if subtract_it {
        acc_general.sub_ctx(operand, general_ctx.decimal_context())
      } else {
        acc_general.add_ctx(operand, general_ctx.decimal_context())
      }
      let expected = complete_decimal_gda(value, general_ctx, flags)
      if !add_plain_same_outcome(outcome, expected) {
        fail("chained add or subtract differs")
      }
      acc_plain = outcome.value()
      acc_general = expected.value()
      plain_ctx = outcome.next_context()
      general_ctx = expected.next_context()
      if plain_ctx.flags_ != general_ctx.flags_ {
        fail("chained status differs")
      }
    }
  }
}

///|
// oracle: S
// source: the equality of flag sets after operations that raise flags: the shared empty value must stay equal to a freshly built empty set; no expected value comes from outside
// shares: nothing
test "shared empty flag sets are never written" {
  let none = GdaFlags::new()
  let decimal_none = DecimalFlags::new()
  let fresh_gda : GdaFlags = {
    conversion_syntax: false,
    division_by_zero: false,
    division_impossible: false,
    division_undefined: false,
    invalid_context: false,
    invalid_operation: false,
    overflow: false,
    underflow: false,
    subnormal: false,
    inexact: false,
    rounded: false,
    clamped: false,
    lost_digits: false,
  }
  // every path that builds a changed copy
  let updated = { ..none, rounded: true, inexact: true, }
  assert_true(updated != none)
  let combined = none.combine(updated).combine(none)
  assert_true(combined == updated)
  let decimal_updated = { ..decimal_none, rounded: true, }
  assert_true(decimal_updated != decimal_none)
  assert_true(decimal_none.combine(decimal_updated) == decimal_updated)
  let ctx = GdaContext::new(precision=7)
    .trap(Inexact)
    .trap(Rounded, enabled=false)
    .clear_flags()
    .reset()
  assert_true(ctx.flags_ == fresh_gda)
  // operations that raise flags on a context whose status is the shared value
  let wide = GdaContext::new(precision=400)
  let a = to_number("1234567890123456789012345678901234567", wide).value()
  let b = to_number("9.87654321E-3", wide).value()
  let narrow = GdaContext::new(precision=12)
  let mut chained = narrow
  for _ in 0..<4 {
    let outcome = add(a, b, chained)
    assert_true(outcome.raised().rounded())
    chained = outcome.next_context()
    ignore(subtract(a, b, chained))
    ignore(multiply(a, b, chained))
    ignore(divide(a, b, chained))
  }
  assert_true(GdaFlags::new() == fresh_gda)
  assert_true(GdaFlags::new() == none)
  assert_true(GdaContext::new(precision=3).flags_ == fresh_gda)
  assert_true(
    gda_flags_rounded_only.rounded() && !gda_flags_rounded_only.inexact(),
  )
  assert_true(
    gda_flags_rounded_inexact.rounded() && gda_flags_rounded_inexact.inexact(),
  )
  assert_true(gda_flags_are_clear(GdaFlags::new()))
  assert_true(decimal_flags_are_clear(DecimalFlags::new()))
}
