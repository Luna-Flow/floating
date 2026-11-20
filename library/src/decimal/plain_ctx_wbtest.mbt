///|
// Differential test of the plain paths of `add_ctx`, `sub_ctx`, `mul_ctx` and
// `div_ctx` (and with them of the plain operators) against the general route,
// which stays the definition of the behavior: `add_finite_values_ctx`,
// `decimal_mul_ctx_general`, `decimal_div_ctx_general`. A plain path that
// answers must give the same representation (coefficient, exponent, precision
// label, sign) and the same flags; one that declines is not compared. The
// contexts cover every rounding direction, clamped and unclamped formats, and
// small and storage-wide exponent ranges, with operands placed near both ends
// of the range, so that the range, clamp and subnormal guards are exercised.

///|
let plain_ctx_cases : Int32 = 4000

///|
fn plain_next(state : Ref[UInt64]) -> UInt64 {
  let mut x = state.val
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  state.val = x
  x
}

///|
fn plain_range(state : Ref[UInt64], low : Int32, high : Int32) -> Int32 {
  low + (plain_next(state) % (high - low + 1).to_uint64()).to_int()
}

///|
fn plain_digits(state : Ref[UInt64], count : Int32) -> String {
  let builder = StringBuilder()
  // runs of nines and zeros make carries and cancellations frequent
  let style = plain_next(state) % 5UL
  for index in 0..<count {
    let digit = if style == 0UL {
      9
    } else if style == 1UL && plain_next(state) % 3UL != 0UL {
      0
    } else {
      (plain_next(state) % 10UL).to_int()
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
fn plain_same_decimal(a : Decimal, b : Decimal) -> Bool {
  a.class == b.class &&
  a.negative == b.negative &&
  a.exponent10 == b.exponent10 &&
  a.precision_ == b.precision_ &&
  a.coefficient.to_string() == b.coefficient.to_string()
}

///|
fn plain_describe(value : Decimal) -> String {
  (if value.negative { "-" } else { "" }) +
  value.coefficient.to_string() +
  "E" +
  value.exponent10.to_string()
}

///|
fn plain_round_name(round : DecimalRound) -> String {
  match round {
    HalfEven => "half_even"
    HalfUp => "half_up"
    HalfDown => "half_down"
    Down => "down"
    Ceiling => "ceiling"
    Floor => "floor"
    Up => "up"
    ZeroFiveUp => "zero_five_up"
  }
}

///|
fn plain_flags_text(flags : DecimalFlags) -> String {
  "[inexact \{flags.inexact} underflow \{flags.underflow} overflow \{flags.overflow}]"
}

///|
fn plain_contexts() -> Array[DecimalContext] {
  let contexts = [
    DecimalContext::decimal32(),
    DecimalContext::decimal64(),
    DecimalContext::decimal128(),
  ]
  let roundings = [
    DecimalRound::HalfEven,
    DecimalRound::HalfUp,
    DecimalRound::HalfDown,
    DecimalRound::Down,
    DecimalRound::Ceiling,
    DecimalRound::Floor,
    DecimalRound::Up,
    DecimalRound::ZeroFiveUp,
  ]
  for precision in [1, 2, 3, 7, 16, 34, 60] {
    for round in roundings {
      // storage-wide unclamped range (the plain operators)
      contexts.push(
        DecimalContext::raw(
          precision,
          decimal_value_e_tiny + precision - 1,
          decimal_value_e_max,
          round~,
        ),
      )
      // narrow ranges, unclamped and clamped
      contexts.push(DecimalContext::raw(precision, -30, 40, round~))
      contexts.push(DecimalContext::raw(precision, -30, 40, round~, clamp=true))
      contexts.push(DecimalContext::raw(precision, -5, 7, round~, clamp=true))
    }
  }
  contexts
}

///|
/// A finite nonzero operand whose adjusted exponent is chosen near the middle
/// or near either end of the range of `ctx`, with a sign and up to `max_digits`
/// digits.
fn plain_operand(
  state : Ref[UInt64],
  ctx : DecimalContext,
  wide : DecimalContext,
  max_digits : Int32,
) -> Decimal {
  let digits = plain_digits(state, plain_range(state, 1, max_digits))
  let place = plain_next(state) % 4UL
  let adjusted = if place == 0UL {
    ctx.e_min.to_int64() + plain_range(state, -3, 6).to_int64()
  } else if place == 1UL {
    ctx.e_max.to_int64() + plain_range(state, -6, 3).to_int64()
  } else {
    plain_range(state, -12, 12).to_int64()
  }
  let exponent = adjusted - digits.length().to_int64() + 1L
  let negative = plain_next(state) % 2UL == 0UL
  Decimal::from_string_ctx(
    (if negative { "-" } else { "" }) + digits + "E" + exponent.to_string(),
    wide,
  ).0
}

///|
fn plain_second(
  state : Ref[UInt64],
  ctx : DecimalContext,
  wide : DecimalContext,
  first : Decimal,
  max_digits : Int32,
) -> Decimal {
  let kind = plain_next(state) % 6UL
  if kind == 0UL {
    // the opposite of the first operand with its last digits perturbed
    let digits = first.coefficient.to_string()
    let cut = Int32::min(digits.length(), plain_range(state, 1, 3))
    let head = digits.exact_view(start=0, end=digits.length() - cut).to_owned()
    let tail = plain_digits(state, cut)
    Decimal::from_string_ctx(
      (if first.negative { "" } else { "-" }) +
      head +
      tail +
      "E" +
      first.exponent10.to_string(),
      wide,
    ).0
  } else if kind == 1UL {
    // a nearby exponent
    let digits = plain_digits(state, plain_range(state, 1, max_digits))
    let exponent = first.exponent10.to_int64() +
      plain_range(state, -40, 40).to_int64()
    Decimal::from_string_ctx(
      (if plain_next(state) % 2UL == 0UL { "-" } else { "" }) +
      digits +
      "E" +
      exponent.to_string(),
      wide,
    ).0
  } else {
    plain_operand(state, ctx, wide, max_digits)
  }
}

///|
fn plain_check(
  lhs : Decimal,
  rhs : Decimal,
  ctx : DecimalContext,
  hits : Array[Int32],
) -> Unit raise {
  // an operand beyond the range of the wide parsing context is an infinity
  guard lhs.class == FpClass::Finite &&
    rhs.class == FpClass::Finite &&
    !lhs.is_zero() &&
    !rhs.is_zero() else {
    return
  }
  let label = "\{plain_describe(lhs)} , \{plain_describe(rhs)} precision \{ctx.precision} e \{ctx.e_min}..\{ctx.e_max} clamp \{ctx.clamp} \{plain_round_name(ctx.decimal_rounding)}"
  for subtract in [false, true] {
    let expected = add_finite_values_ctx(
      lhs,
      if subtract {
        rhs.neg()
      } else {
        rhs
      },
      ctx,
    )
    let general = if subtract {
      lhs.sub_ctx(rhs, ctx)
    } else {
      lhs.add_ctx(rhs, ctx)
    }
    if !plain_same_decimal(general.0, expected.0) || general.1 != expected.1 {
      fail("add_ctx/sub_ctx differ from add_finite_values_ctx: " + label)
    }
    match decimal_add_plain(lhs, rhs, ctx, subtract) {
      Some((value, flags)) => {
        hits[0] = hits[0] + 1
        if !plain_same_decimal(value, expected.0) || flags != expected.1 {
          fail(
            "plain add differs (subtract \{subtract}): " +
            label +
            " plain " +
            plain_describe(value) +
            " \{plain_flags_text(flags)} expected " +
            plain_describe(expected.0) +
            " \{plain_flags_text(expected.1)}",
          )
        }
      }
      None => ()
    }
  }
  let expected_mul = lhs.decimal_mul_ctx_general(rhs, ctx)
  match decimal_mul_plain(lhs, rhs, ctx) {
    Some((value, flags)) => {
      hits[1] = hits[1] + 1
      if !plain_same_decimal(value, expected_mul.0) || flags != expected_mul.1 {
        fail(
          "plain mul differs: " +
          label +
          " plain " +
          plain_describe(value) +
          " \{plain_flags_text(flags)} expected " +
          plain_describe(expected_mul.0) +
          " \{plain_flags_text(expected_mul.1)}",
        )
      }
    }
    None => ()
  }
  let expected_div = lhs.decimal_div_ctx_general(rhs, ctx)
  match decimal_div_plain(lhs, rhs, ctx) {
    Some((value, flags)) => {
      hits[2] = hits[2] + 1
      if !plain_same_decimal(value, expected_div.0) || flags != expected_div.1 {
        fail(
          "plain div differs: " +
          label +
          " plain " +
          plain_describe(value) +
          " \{plain_flags_text(flags)} expected " +
          plain_describe(expected_div.0) +
          " \{plain_flags_text(expected_div.1)}",
        )
      }
    }
    None => ()
  }
}

///|
fn plain_run(max_digits : Int32, seed : UInt64) -> Array[Int32] raise {
  let wide = DecimalContext::raw(
    4000, decimal_value_e_tiny, decimal_value_e_max,
  )
  let contexts = plain_contexts()
  let state = Ref(seed)
  let hits = [0, 0, 0]
  for iteration in 0..<plain_ctx_cases {
    let ctx = contexts[iteration % contexts.length()]
    let lhs = plain_operand(state, ctx, wide, max_digits)
    let rhs = plain_second(state, ctx, wide, lhs, max_digits)
    plain_check(lhs, rhs, ctx, hits)
    plain_check(rhs, lhs, ctx, hits)
    // exact and finite-expansion quotients: a product divided by a factor
    let product = lhs.mul_ctx(rhs, wide).0
    plain_check(product, rhs, ctx, hits)
    plain_check(lhs, Decimal::from_string_ctx("8", wide).0, ctx, hits)
  }
  hits
}

///|
test "plain add, subtract, multiply and divide equal the general route (short operands)" {
  let hits = plain_run(40, 0x9E3779B97F4A7C15UL)
  assert_true(hits[0] > 3000)
  assert_true(hits[1] > 3000)
  assert_true(hits[2] > 3000)
}

///|
test "plain add, subtract, multiply and divide equal the general route (long operands)" {
  let hits = plain_run(130, 0xD1B54A32D192ED03UL)
  assert_true(hits[0] > 1000)
  assert_true(hits[1] > 1000)
  assert_true(hits[2] > 1000)
}

///|
test "plain paths decline what they do not cover" {
  let ctx = DecimalContext::raw(7, -30, 40)
  let wide = DecimalContext::new(precision=400)
  let zero = Decimal::from_string_ctx("0", wide).0
  let one = Decimal::from_string_ctx("1", wide).0
  let nan = Decimal::nan(precision=7)
  let inf = Decimal::inf(precision=7)
  let tiny = Decimal::from_string_ctx("1E-60", wide).0
  let huge = Decimal::from_string_ctx("1E+60", wide).0
  assert_true(decimal_add_plain(zero, one, ctx, false) is None)
  assert_true(decimal_add_plain(nan, one, ctx, false) is None)
  assert_true(decimal_add_plain(inf, one, ctx, false) is None)
  assert_true(decimal_add_plain(one, one.neg(), ctx, false) is None)
  assert_true(decimal_add_plain(huge, one, ctx, false) is None)
  assert_true(decimal_mul_plain(tiny, one, ctx) is None)
  assert_true(decimal_mul_plain(huge, one, ctx) is None)
  assert_true(decimal_mul_plain(zero, one, ctx) is None)
  assert_true(decimal_div_plain(one, zero, ctx) is None)
  // 1 / 8 has a finite expansion
  assert_true(
    decimal_div_plain(one, Decimal::from_string_ctx("8", wide).0, ctx) is None,
  )
  assert_true(
    decimal_div_plain(one, Decimal::from_string_ctx("3", wide).0, ctx)
    is Some(_),
  )
  // an unrounded product above the exponent of the clamped format
  let clamped = DecimalContext::raw(7, -30, 40, clamp=true)
  let hundred = Decimal::from_string_ctx("1E+38", wide).0
  assert_true(decimal_mul_plain(hundred, hundred, clamped) is None)
}

///|
/// A rounding carry at the end of the range: a result whose adjusted exponent
/// is `e_max` before rounding is `e_max` or, after a carry into 10^p, beyond it
/// (an overflow of the general route), and `e_max - 1` before rounding stays
/// within it. The plain paths decline the first, and the second must agree.
test "plain paths at the end of the range with a rounding carry" {
  let wide = DecimalContext::raw(
    4000, decimal_value_e_tiny, decimal_value_e_max,
  )
  let hits = [0, 0, 0]
  for ctx in plain_contexts() {
    let p = ctx.precision
    for
      adjusted in [
        ctx.e_max.to_int64() - 2L,
        ctx.e_max.to_int64() - 1L,
        ctx.e_max.to_int64(),
        ctx.e_min.to_int64(),
        ctx.e_min.to_int64() + 1L,
        ctx.e_min.to_int64() - 1L,
      ] {
      let nines = String::make(p + 2, '9')
      let exponent = adjusted - (p + 2).to_int64() + 1L
      let lhs = Decimal::from_string_ctx(
          nines + "E" + exponent.to_string(),
          wide,
        ).0
      for
        text in [
          "1",
          "5",
          "50",
          "5E-1",
          "4E-1",
          "10",
          "100",
          "99",
          "9" + String::make(p + 2, '9'),
        ] {
        // the addend sits at, and one place below, the exponent of `lhs`
        for shift in [0, -1, 1] {
          let rhs_exponent = exponent + shift.to_int64()
          let rhs = Decimal::from_string_ctx(
              text + "E" + rhs_exponent.to_string(),
              wide,
            ).0
          plain_check(lhs, rhs, ctx, hits)
          plain_check(lhs, rhs.neg(), ctx, hits)
          plain_check(lhs.neg(), rhs, ctx, hits)
        }
        plain_check(lhs, Decimal::from_string_ctx(text, wide).0, ctx, hits)
      }
    }
  }
  assert_true(hits[0] > 0 && hits[1] > 0 && hits[2] > 0)
}
