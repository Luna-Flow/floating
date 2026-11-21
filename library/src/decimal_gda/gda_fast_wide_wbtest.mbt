///|
// Differential test of `gda_fast_wide_sum` (coefficients of up to four limbs,
// precision up to 36) against the general route at the public level: the value
// with its exact representation (sign, exponent, coefficient and its storage
// variant, stored precision), every condition raised, the status of the next
// context, trapped or completed. Helpers of `gda_fast_small_wbtest.mbt` and
// `gda_add_plain_wbtest.mbt`.

///|
/// A coefficient of `digits` digits (1 to 36): random, all nines, a one with
/// zeros, a five with zeros, just below or above a power of ten, so that ties,
/// carries and exact results occur.
fn gda_wide_coefficient(random : GdaFastRandom, digits : Int32) -> DecCoeff {
  let limbs = (digits + 8) / 9
  let units : Array[UInt32] = Array::make(limbs, 0U)
  let kind = random.below(8)
  for index in 0..<limbs {
    let width = if index == limbs - 1 { digits - 9 * (limbs - 1) } else { 9 }
    let power = gda_fast_pow10.unsafe_get(width)
    let value = match kind {
      0 => power - 1UL
      1 => if index == limbs - 1 { power / 10UL } else { 0UL }
      2 => if index == limbs - 1 { power / 10UL * 5UL % power } else { 0UL }
      3 =>
        if index == 0 {
          power - 1UL - random.next() % 10UL
        } else {
          power - 1UL
        }
      _ => power / 10UL + random.next() % (power - power / 10UL)
    }
    units[index] = value.to_uint()
  }
  if units[limbs - 1] == 0U {
    units[limbs - 1] = 1U
  }
  dec_coeff_from_unit_accumulator(units, limbs)
}

///|
fn gda_wide_operand(random : GdaFastRandom, around : Int32) -> Decimal {
  let digits = match random.below(4) {
    0 => 19 + random.below(3)
    1 => 1 + random.below(36)
    _ => 28 + random.below(9)
  }
  let exponent = around +
    random.below(9) -
    4 +
    (if random.below(10) == 0 { random.below(60) - 30 } else { 0 })
  finite_with_exponent_repr(
    random.below(2) == 0,
    gda_wide_coefficient(random, digits),
    exponent,
    digits,
  )
}

///|
fn gda_wide_context(random : GdaFastRandom) -> GdaContext {
  let precisions = [1, 2, 5, 17, 18, 19, 20, 25, 30, 33, 34, 35, 36, 37, 40]
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
  let e_min = if wide { -999999 } else { -random.below(60) }
  let e_max = if wide { 999999 } else { random.below(60) }
  let context = match
    GdaContext::try_new(
      precision=precisions[random.below(15)],
      rounding=roundings[random.below(8)],
      e_min~,
      e_max~,
      clamp=random.below(4) == 0,
      extended=random.below(8) != 0,
    ) {
    Ok(context) => context
    Err(_) => GdaContext::decimal128()
  }
  let traps = match random.below(6) {
    0 => GdaTrapSet::new().with_signal(Rounded)
    1 => GdaTrapSet::new().with_signal(Inexact)
    _ => GdaTrapSet::new()
  }
  let trapped = context.with_traps(traps)
  match random.below(4) {
    0 => gda_context_with_flags(trapped, gda_flags_rounded_only)
    1 => gda_context_with_flags(trapped, gda_flags_rounded_inexact)
    _ => trapped
  }
}

///|
fn gda_wide_same(
  actual : GdaOutcome[Decimal],
  expected : GdaOutcome[Decimal],
) -> Bool {
  add_plain_same_decimal(actual.value(), expected.value()) &&
  actual.raised() == expected.raised() &&
  actual.next_context().flags() == expected.next_context().flags() &&
  (match (actual, expected) {
    (Completed(_, _, _), Completed(_, _, _)) => true
    (Trapped(a, _, _, _), Trapped(b, _, _, _)) => a == b
    _ => false
  })
}

///|
fn gda_wide_run(seed : UInt64, near : Bool) -> Array[Int32] raise {
  let random = { fast_state: seed, }
  let counts = [0, 0, 0]
  for index in 0..<40000 {
    let context = gda_wide_context(random)
    let around = random.below(30) - 15
    let lhs = gda_wide_operand(random, around)
    let rhs = if near && random.below(3) == 0 {
      // the opposite of the first operand with its last digits changed: cancellation
      let units = match lhs.coefficient {
        DecCoeff::Limbs(units, _) => units.copy()
        DecCoeff::Small(small) =>
          [(small % 1000000000UL).to_uint(), (small / 1000000000UL).to_uint()]
      }
      units[0] = (units[0] + 1U + (random.next() % 5UL).to_uint()) % 1000000000U
      finite_with_exponent_repr(
        !lhs.negative,
        dec_coeff_from_unit_accumulator(units, units.length()),
        lhs.exponent10,
        lhs.precision_,
      )
    } else {
      gda_wide_operand(random, around + random.below(7) - 3)
    }
    let negate_rhs = index % 2 == 1
    let expected = gda_fast_generic_sum(lhs, rhs, context, negate_rhs)
    match gda_fast_wide_sum(lhs, rhs, context, negate_rhs) {
      Some(outcome) => {
        counts[0] = counts[0] + 1
        if expected.raised().rounded {
          counts[1] = counts[1] + 1
        }
        if expected.raised().rounded && !expected.raised().inexact {
          counts[2] = counts[2] + 1
        }
        if !gda_wide_same(outcome, expected) {
          fail(
            "wide sum differs: \{lhs.to_sci_string()} \{if negate_rhs { "-" } else { "+" }} \{rhs.to_sci_string()} precision \{context.precision()}",
          )
        }
      }
      None => ()
    }
    let public = if negate_rhs {
      subtract(lhs, rhs, context)
    } else {
      add(lhs, rhs, context)
    }
    assert_true(gda_wide_same(public, expected))
  }
  counts
}

///|
test "wide sum equals the general route" {
  let counts = gda_wide_run(0x9E3779B97F4A7C15UL, false)
  assert_true(counts[0] > 5000)
  assert_true(counts[1] > 2000)
}

///|
test "wide sum of near-equal and cancelling values" {
  let counts = gda_wide_run(0xD1B54A32D192ED03UL, true)
  assert_true(counts[0] > 5000)
}

///|
test "wide sum declines what it does not cover" {
  let context = GdaContext::new(precision=34)
  let wide = Decimal::from_string("1234567890123456789012345678901234567890").unwrap()
  let one = finite_with_exponent_repr(false, DecCoeff::Small(7UL), 0, 1)
  let zero = finite_with_exponent_repr(false, DecCoeff::Small(0UL), 0, 1)
  let far = finite_with_exponent_repr(false, DecCoeff::Small(7UL), 40, 1)
  let nan = Decimal::nan(precision=34)
  assert_true(gda_fast_wide_sum(one, wide, context, false) is None)
  assert_true(gda_fast_wide_sum(one, zero, context, false) is None)
  assert_true(gda_fast_wide_sum(one, nan, context, false) is None)
  // a shift of more than 19 places, and an aligned sum above 2^128
  assert_true(gda_fast_wide_sum(one, far, context, false) is None)
  let big = finite_with_exponent_repr(
    false,
    dec_coeff_from_unit_accumulator(
      [999999999U, 999999999U, 999999999U, 999999999U],
      4,
    ),
    10,
    36,
  )
  assert_true(
    gda_fast_wide_sum(big, one, GdaContext::new(precision=36), false) is None,
  )
  // ZeroFiveUp and a precision above 36 are the next route's
  assert_true(
    gda_fast_wide_sum(
      one,
      one,
      GdaContext::new(precision=34, rounding=ZeroFiveUp),
      false,
    )
    is None,
  )
  assert_true(
    gda_fast_wide_sum(one, one, GdaContext::new(precision=40), false) is None,
  )
}

///|
fn gda_wide_check_both(
  lhs : Decimal,
  rhs : Decimal,
  context : GdaContext,
  expect_fast : Bool,
) -> Unit raise {
  let expected = gda_fast_generic_sum(lhs, rhs, context, false)
  match gda_fast_wide_sum(lhs, rhs, context, false) {
    Some(outcome) => {
      assert_true(expect_fast)
      assert_true(gda_wide_same(outcome, expected))
    }
    None => assert_true(!expect_fast)
  }
  assert_true(gda_wide_same(add(lhs, rhs, context), expected))
}

///|
fn gda_wide_decimal(text : String, exponent : Int32) -> Decimal {
  let wide = GdaContext::new(precision=400)
  let value = to_number(text, wide).value()
  finite_with_exponent_repr(
    value.negative,
    value.coefficient,
    exponent,
    value.coefficient.digits10(),
  )
}

///|
/// Constructed boundaries of the 128-bit arithmetic, one for each guard the
/// random classes reach only by chance: an aligned operand just below 2^128
/// plus a 36-digit one overflows the sum (2^128 = 3.4028...e38); a rounded
/// value of the form 10^p - 2^64 has the low word of 10^p and a different high
/// word; a kept value 2^64 - 1 that is incremented carries into the high word.
test "wide sum at the edges of its 128-bit arithmetic" {
  // sum of 2^128 or more: 3.402e19 * 10^19 + 10^36 - 1
  let big = gda_wide_decimal("34020000000000000000", 19)
  let nines = gda_wide_decimal("999999999999999999999999999999999999", 0)
  gda_wide_check_both(big, nines, GdaContext::new(precision=36), false)
  // just below it: the sum is taken
  let below = gda_wide_decimal("33000000000000000000", 19)
  gda_wide_check_both(below, nines, GdaContext::new(precision=36), true)
  // kept = 10^34 - 2^64 (low word of 10^34), plus 3 below the last digit
  let two64 = gda_wide_decimal("18446744073709551616", 0).coefficient
  let kept = dec_coeff_magnitude_sub_repr(dec_coeff_power10_repr(34), two64)
  let lhs = finite_with_exponent_repr(
    false,
    dec_coeff_multiply_by_unit_repr(kept, 10),
    0,
    35,
  )
  let rhs = gda_wide_decimal("3", 0)
  gda_wide_check_both(lhs, rhs, GdaContext::new(precision=34), true)
  // kept = 2^64 - 1 with a 5 below it, rounded up by half-up: the low word wraps
  let wrap = gda_wide_decimal("184467440737095516150", 0)
  let five = gda_wide_decimal("5", 0)
  gda_wide_check_both(
    wrap,
    five,
    GdaContext::new(precision=20, rounding=HalfUp),
    true,
  )
}

///|
fn gda_wide_modes() -> Array[GdaRoundingMode] {
  [
    GdaRoundingMode::HalfEven,
    GdaRoundingMode::HalfUp,
    GdaRoundingMode::HalfDown,
    GdaRoundingMode::Down,
    GdaRoundingMode::Up,
    GdaRoundingMode::Ceiling,
    GdaRoundingMode::Floor,
  ]
}

///|
fn gda_wide_nines(count : Int32, exponent : Int32) -> Decimal {
  gda_wide_decimal(String::make(count, '9'), exponent)
}

///|
test "wide sum: both operands 36 nines, the sum carries to 37 digits" {
  for precision in [36, 35, 30, 19, 18] {
    for mode in gda_wide_modes() {
      let context = GdaContext::new(precision~, rounding=mode)
      let lhs = gda_wide_nines(36, 0)
      let rhs = gda_wide_nines(36, 0)
      gda_wide_check_both(lhs, rhs, context, true)
      gda_wide_check_both(lhs, rhs.neg(), context, false)
      let sum = gda_fast_wide_sum(lhs, rhs, context, false)
      assert_true(sum is Some(_))
      if precision == 36 {
        // 1999...98 has 37 digits: one digit is dropped
        assert_true(sum.unwrap().raised().rounded)
      }
    }
  }
}

///|
/// The aligned operand and the sum must stay below 2^128 = 3.40e38. A 36-digit
/// operand always fits at the exponent gap 2 (below 10^38) and, at the gap 3,
/// only below 3.40e35: 36 nines times 10^3 is declined, 10^35 times 10^3 is
/// taken. The same shape for a 34-digit operand at the gaps 4 and 5 (the
/// operands 34 nines and 10^33 / 3.4e33).
test "wide sum: the largest accepted exponent gap and the first declined, from both sides" {
  let context = GdaContext::new(precision=36)
  for gap in 0..<8 {
    let small = gda_wide_nines(1, 0)
    let large36 = gda_wide_nines(36, gap)
    let large34 = gda_wide_nines(34, gap)
    // the large operand has the larger exponent: it is the one that is aligned
    gda_wide_check_both(large36, small, context, gap <= 2)
    gda_wide_check_both(small, large36, context, gap <= 2)
    gda_wide_check_both(large34, small, context, gap <= 4)
    gda_wide_check_both(small, large34, context, gap <= 4)
  }
  // at the first gap that declines 36 nines, a smaller operand still fits
  let one = gda_wide_nines(1, 0)
  let power35 = gda_wide_decimal("100000000000000000000000000000000000", 3)
  gda_wide_check_both(power35, one, context, true)
  gda_wide_check_both(one, power35, context, true)
  let below_limit = gda_wide_decimal("340000000000000000000000000000000000", 3)
  let above_limit = gda_wide_decimal("341000000000000000000000000000000000", 3)
  gda_wide_check_both(below_limit, one, context, true)
  gda_wide_check_both(above_limit, one, context, false)
  gda_wide_check_both(one, above_limit, context, false)
  let power33 = gda_wide_decimal("1000000000000000000000000000000000", 5)
  gda_wide_check_both(power33, one, context, true)
}

///|
/// The digits dropped by the rounding are the digits of the sum minus the
/// precision: the sum 1999...98 of two 36-nines operands has 37 digits.
test "wide sum: drop of 1, 18 and 19 digits, and the first declined (20)" {
  let lhs = gda_wide_nines(36, 0)
  let rhs = gda_wide_nines(36, 0)
  for entry in [(36, true), (19, true), (18, true), (17, false)] {
    let (precision, taken) = entry
    for mode in gda_wide_modes() {
      gda_wide_check_both(
        lhs,
        rhs,
        GdaContext::new(precision~, rounding=mode),
        taken,
      )
    }
  }
}

///|
test "wide sum: cancellation down to one digit, and to zero (declined)" {
  let context = GdaContext::new(precision=36)
  let x = gda_wide_decimal("123456789012345678901234567890123456", 0)
  let almost = gda_wide_decimal("123456789012345678901234567890123455", 0)
  // x - (x - 1) = 1: one digit
  gda_wide_check_both(x, almost.neg(), context, true)
  // x - (x - 10^k) for every k: a result of k + 1 digits
  for k in 1..<36 {
    let below = dec_coeff_magnitude_sub_repr(
      x.coefficient,
      dec_coeff_power10_repr(k),
    )
    let other = finite_with_exponent_repr(true, below, 0, 36)
    gda_wide_check_both(x, other, context, true)
  }
  // x - x = 0: the sign of a zero sum depends on the rounding, the next route's
  gda_wide_check_both(x, x.neg(), context, false)
}

///|
test "wide sum: operands of 1, 2, 3 and 4 limbs in every pairing" {
  let digits = [5, 14, 23, 34]
  for left in digits {
    for right in digits {
      for exponent in [0, 3, -4] {
        let lhs = gda_wide_decimal(String::make(left, '7'), 0)
        let rhs = gda_wide_decimal(String::make(right, '3'), exponent)
        for precision in [20, 34, 36] {
          let context = GdaContext::new(precision~)
          let expected = gda_fast_generic_sum(lhs, rhs, context, false)
          match gda_fast_wide_sum(lhs, rhs, context, false) {
            Some(outcome) => assert_true(gda_wide_same(outcome, expected))
            None => ()
          }
          assert_true(gda_wide_same(add(lhs, rhs, context), expected))
          // both exponents equal the shifts of at most 4 places: taken
          assert_true(gda_fast_wide_sum(lhs, rhs, context, false) is Some(_))
        }
      }
    }
  }
}

///|
test "wide sum: precision 1, 9, 10, 18, 19, 34, 36 and 37 (declined)" {
  // operands of `precision + 8` digits (at most 36): the sum has at most
  // `precision + 9` digits and a drop of at most 9
  for precision in [1, 9, 10, 18, 19, 34, 36] {
    let digits = if precision + 8 > 36 { 36 } else { precision + 8 }
    let lhs = gda_wide_decimal(String::make(digits, '6'), 0)
    let rhs = gda_wide_decimal(String::make(digits, '5'), 0)
    for mode in gda_wide_modes() {
      gda_wide_check_both(
        lhs,
        rhs,
        GdaContext::new(precision~, rounding=mode),
        true,
      )
    }
  }
  // 36-digit operands: a sum of 37 digits drops 36 - precision + 1 digits, so
  // precision 18 drops 19 (taken) and 10 drops 27 (declined)
  let lhs = gda_wide_decimal("123456789012345678901234567890123456", 0)
  let rhs = gda_wide_decimal("987654321098765432109876543210987654", 0)
  for entry in [(18, true), (10, false), (9, false), (1, false)] {
    let (precision, taken) = entry
    for mode in gda_wide_modes() {
      gda_wide_check_both(
        lhs,
        rhs,
        GdaContext::new(precision~, rounding=mode),
        taken,
      )
    }
  }
  // precision 37 is above the limit
  for mode in gda_wide_modes() {
    gda_wide_check_both(
      lhs,
      rhs,
      GdaContext::new(precision=37, rounding=mode),
      false,
    )
  }
}
