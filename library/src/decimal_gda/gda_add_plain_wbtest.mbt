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
      add_plain_same_decimal(v, w) && c.status_ == d.status_ && f == g
    (Trapped(s, v, c, f), Trapped(t, w, d, g)) =>
      s == t && add_plain_same_decimal(v, w) && c.status_ == d.status_ && f == g
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
  GdaContext::new(
    precision~,
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
test "add and subtract plain path equals the general route, 17 to 40 digits" {
  add_plain_run(17, 40, 0x9E3779B97F4A7C15UL)
}

///|
test "add and subtract plain path equals the general route, 1 to 16 digits" {
  add_plain_run(1, 16, 0xD1B54A32D192ED03UL)
}

///|
test "add and subtract plain path equals the general route, 41 to 120 digits" {
  add_plain_run(41, 120, 0x2545F4914F6CDD1DUL)
}

///|
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
