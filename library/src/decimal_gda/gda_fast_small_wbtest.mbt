///|
struct GdaFastRandom {
  mut fast_state : UInt64
}

///|
fn GdaFastRandom::next(self : GdaFastRandom) -> UInt64 {
  self.fast_state = self.fast_state * 6364136223846793005UL +
    1442695040888963407UL
  self.fast_state >> 11
}

///|
fn GdaFastRandom::below(self : GdaFastRandom, limit : Int32) -> Int32 {
  (self.next() % limit.to_uint64()).to_int()
}

///|
/// A coefficient of `digits` digits (1 to 18): random, all nines, a one with
/// zeros, a five with zeros, or a value just below a power of ten, so that
/// ties, carries and exact results occur.
fn gda_fast_coefficient(random : GdaFastRandom, digits : Int32) -> UInt64 {
  let low = gda_fast_pow10.unsafe_get(digits - 1)
  let span = gda_fast_pow10.unsafe_get(digits) - low
  match random.below(8) {
    0 => gda_fast_pow10.unsafe_get(digits) - 1UL
    1 => low
    2 =>
      low * 5UL % gda_fast_pow10.unsafe_get(digits) +
      (if digits == 1 { 5UL } else { 0UL })
    3 => gda_fast_pow10.unsafe_get(digits) - 1UL - random.next() % 10UL
    _ => low + random.next() % span
  }
}

///|
fn gda_fast_operand_value(random : GdaFastRandom, around : Int32) -> Decimal {
  let digits = match random.below(4) {
    0 => 1 + random.below(4)
    1 => 1 + random.below(18)
    _ => 10 + random.below(9)
  }
  let mut coefficient = gda_fast_coefficient(random, digits)
  if coefficient == 0UL {
    coefficient = 1UL
  }
  let exponent = around +
    random.below(9) -
    4 +
    (if random.below(10) == 0 { random.below(60) - 30 } else { 0 })
  finite_with_exponent_repr(
    random.below(2) == 0,
    DecCoeff::Small(coefficient),
    exponent,
    digits,
  )
}

///|
fn gda_fast_context(random : GdaFastRandom) -> GdaContext {
  let precisions = [1, 2, 3, 5, 7, 9, 15, 16, 17, 18, 19, 34]
  let roundings = [
    GdaRoundingMode::HalfEven,
    HalfUp,
    HalfDown,
    Down,
    Ceiling,
    Floor,
    Up,
    ZeroFiveUp,
  ]
  let wide = random.below(3) != 0
  let e_min = if wide { -999999 } else { -random.below(40) }
  let e_max = if wide { 999999 } else { random.below(40) }
  match
    GdaContext::try_new(
      precision=precisions[random.below(12)],
      rounding=roundings[random.below(8)],
      e_min~,
      e_max~,
      clamp=random.below(4) == 0,
      extended=random.below(8) != 0,
    ) {
    Ok(context) => context
    Err(_) => GdaContext::decimal64()
  }
}

///|
fn gda_fast_same(
  actual : GdaOutcome[Decimal],
  expected : GdaOutcome[Decimal],
) -> Bool {
  actual.value().to_string() == expected.value().to_string() &&
  actual.value().precision() == expected.value().precision() &&
  actual.raised() == expected.raised() &&
  actual.next_context().flags() == expected.next_context().flags() &&
  (match (actual, expected) {
    (Completed(_, _, _), Completed(_, _, _)) => true
    (Trapped(a, _, _, _), Trapped(b, _, _, _)) => a == b
    _ => false
  })
}

///|
fn gda_fast_generic_sum(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
  subtract_rhs : Bool,
) -> GdaOutcome[Decimal] {
  let decimal_context = ctx.decimal_context()
  let (value, flags) = if subtract_rhs {
    lhs.sub_ctx(rhs, decimal_context)
  } else {
    lhs.add_ctx(rhs, decimal_context)
  }
  complete_decimal_gda(value, ctx, flags)
}

///|
// oracle: E
// source: the general route as the reference: `gda_fast_generic_sum` or mul_ctx / div_ctx then complete_decimal_gda, compared with the fast path on random operands of 1 to 18 digits (ties, carries, exact results) and every context shape
// shares: complete_decimal_gda, add_ctx, sub_ctx, mul_ctx, div_ctx
// underneath: the general route (add_ctx, sub_ctx, mul_ctx, div_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic without traps: the official decTest corpus (gate stages DECIMAL_GDA: official decTest and official0) and the CPython rows of plain_operator_rows_wbtest.mbt (precision 3, 16, 34); traps, the chaining of the status and the subset arithmetic (extended false) have no level A or B oracle, so those inputs stay level E
test "fast sum equals the general path" {
  let random = { fast_state: 0x5DEECE66D7UL, }
  let mut fast = 0
  let mut rounded = 0
  for index in 0..<60000 {
    let context = gda_fast_context(random)
    let around = random.below(30) - 15
    let lhs = gda_fast_operand_value(random, around)
    let rhs = gda_fast_operand_value(random, around + random.below(7) - 3)
    let negate_rhs = index % 2 == 1
    let expected = gda_fast_generic_sum(lhs, rhs, context, negate_rhs)
    match gda_fast_sum(lhs, rhs, context, negate_rhs) {
      Some(outcome) => {
        fast += 1
        if expected.raised().rounded {
          rounded += 1
        }
        assert_true(gda_fast_same(outcome, expected))
      }
      None => ()
    }
    let public = if negate_rhs {
      subtract(lhs, rhs, context)
    } else {
      add(lhs, rhs, context)
    }
    assert_true(gda_fast_same(public, expected))
  }
  assert_true(fast > 15000)
  assert_true(rounded > 3000)
}

///|
// oracle: E
// source: the general route as the reference: `gda_fast_generic_sum` or mul_ctx / div_ctx then complete_decimal_gda, compared with the fast path on random operands of 1 to 18 digits (ties, carries, exact results) and every context shape
// shares: complete_decimal_gda, add_ctx, sub_ctx, mul_ctx, div_ctx
// underneath: the general route (add_ctx, sub_ctx, mul_ctx, div_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic without traps: the official decTest corpus (gate stages DECIMAL_GDA: official decTest and official0) and the CPython rows of plain_operator_rows_wbtest.mbt (precision 3, 16, 34); traps, the chaining of the status and the subset arithmetic (extended false) have no level A or B oracle, so those inputs stay level E
test "fast sum of near-equal and cancelling values" {
  let random = { fast_state: 0x1234ABCDEFUL, }
  let mut fast = 0
  for _ in 0..<40000 {
    let context = gda_fast_context(random)
    let lhs = gda_fast_operand_value(random, random.below(10) - 5)
    let delta = finite_with_exponent_repr(
      lhs.negative,
      DecCoeff::Small(1UL + random.next() % 1000UL),
      lhs.exponent10 + random.below(5) - 2,
      4,
    )
    let rhs = if random.below(3) == 0 {
      lhs.neg()
    } else {
      lhs.neg().add(delta)
    }
    let expected = gda_fast_generic_sum(lhs, rhs, context, false)
    match gda_fast_sum(lhs, rhs, context, false) {
      Some(outcome) => {
        fast += 1
        assert_true(gda_fast_same(outcome, expected))
      }
      None => ()
    }
  }
  assert_true(fast > 8000)
}

///|
// oracle: E
// source: the general route as the reference: `gda_fast_generic_sum` or mul_ctx / div_ctx then complete_decimal_gda, compared with the fast path on random operands of 1 to 18 digits (ties, carries, exact results) and every context shape
// shares: complete_decimal_gda, add_ctx, sub_ctx, mul_ctx, div_ctx
// underneath: the general route (add_ctx, sub_ctx, mul_ctx, div_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic without traps: the official decTest corpus (gate stages DECIMAL_GDA: official decTest and official0) and the CPython rows of plain_operator_rows_wbtest.mbt (precision 3, 16, 34); traps, the chaining of the status and the subset arithmetic (extended false) have no level A or B oracle, so those inputs stay level E
test "fast product equals the general path" {
  let random = { fast_state: 0x2545F4914F6CDD1DUL, }
  let mut fast = 0
  let mut rounded = 0
  for _ in 0..<60000 {
    let context = gda_fast_context(random)
    let lhs = gda_fast_operand_value(random, random.below(30) - 15)
    let rhs = gda_fast_operand_value(random, random.below(30) - 15)
    let decimal_context = context.decimal_context()
    let (value, flags) = lhs.mul_ctx(rhs, decimal_context)
    let expected = complete_decimal_gda(value, context, flags)
    match gda_fast_product(lhs, rhs, context) {
      Some(outcome) => {
        fast += 1
        if expected.raised().rounded {
          rounded += 1
        }
        assert_true(gda_fast_same(outcome, expected))
      }
      None => ()
    }
    assert_true(gda_fast_same(multiply(lhs, rhs, context), expected))
  }
  assert_true(fast > 20000)
  assert_true(rounded > 5000)
}

///|
// oracle: E
// source: the general route as the reference: `gda_fast_generic_sum` or mul_ctx / div_ctx then complete_decimal_gda, compared with the fast path on random operands of 1 to 18 digits (ties, carries, exact results) and every context shape
// shares: complete_decimal_gda, add_ctx, sub_ctx, mul_ctx, div_ctx
// underneath: the general route (add_ctx, sub_ctx, mul_ctx, div_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic without traps: the official decTest corpus (gate stages DECIMAL_GDA: official decTest and official0) and the CPython rows of plain_operator_rows_wbtest.mbt (precision 3, 16, 34); traps, the chaining of the status and the subset arithmetic (extended false) have no level A or B oracle, so those inputs stay level E
test "fast quotient equals the general path" {
  let random = { fast_state: 0x9E3779B97F4A7C15UL, }
  let mut fast = 0
  for index in 0..<60000 {
    let context = gda_fast_context(random)
    let rhs = gda_fast_operand_value(random, random.below(30) - 15)
    // every fourth divisor is a power of two or of five, whose quotients have
    // long finite expansions
    let rhs = if index % 4 == 0 {
      let base = if random.below(2) == 0 { 2UL } else { 5UL }
      let mut power = 1UL
      for _ in 0..<random.below(24) {
        if power < 100000000000000000UL / base {
          power = power * base
        }
      }
      finite_with_exponent_repr(
        rhs.negative,
        DecCoeff::Small(power),
        rhs.exponent10,
        1,
      )
    } else {
      rhs
    }
    let lhs = gda_fast_operand_value(random, random.below(30) - 15)
    let (value, flags) = lhs.div_ctx(rhs, context.decimal_context())
    let expected = complete_decimal_gda(value, context, flags)
    match gda_fast_quotient(lhs, rhs, context) {
      Some(outcome) => {
        fast += 1
        assert_true(gda_fast_same(outcome, expected))
      }
      None => ()
    }
    assert_true(gda_fast_same(divide(lhs, rhs, context), expected))
  }
  assert_true(fast > 15000)
}

///|
// oracle: A
// source: written out: a 23-digit operand, a NaN and a zero are outside the fast paths, so each of gda_fast_sum, gda_fast_product and gda_fast_quotient returns None
// shares: nothing
test "fast paths decline what they do not cover" {
  let context = GdaContext::new(precision=16)
  let one = Decimal::from_string("1").unwrap()
  let wide = Decimal::from_string("12345678901234567890123").unwrap()
  assert_true(gda_fast_sum(one, wide, context, false) is None)
  assert_true(gda_fast_product(one, wide, context) is None)
  assert_true(gda_fast_quotient(one, wide, context) is None)
  assert_true(
    gda_fast_sum(one, Decimal::nan(precision=16), context, false) is None,
  )
  assert_true(
    gda_fast_sum(one, Decimal::from_string("0").unwrap(), context, false)
    is None,
  )
  assert_true(gda_fast_sum(one, one.neg(), context, false) is None)
  // an exact quotient is left to the general path
  assert_true(
    gda_fast_quotient(one, Decimal::from_string("4").unwrap(), context) is None,
  )
  let big = GdaContext::new(precision=34)
  assert_true(gda_fast_sum(one, one, big, false) is None)
  let basic = GdaContext::new(precision=16, extended=false)
  assert_true(gda_fast_sum(one, one, basic, false) is None)
  let zero_five = GdaContext::new(precision=16, rounding=ZeroFiveUp)
  assert_true(gda_fast_sum(one, one, zero_five, false) is None)
}
