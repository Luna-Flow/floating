///|
// Differential test of `exact_decimal_division_result` against its previous
// implementation (the gcd of the coefficients on every call), kept here as
// private reference code: the decision to produce a result (a quotient with a
// finite decimal expansion) and the result and flags must be the same, for
// finite and infinite expansions, divisors with factors 2 and 5 of high
// valuation, dividends that are and are not multiples of the part prime to 10,
// and the IEEE rounding directions.

///|
fn exact_division_next(state : Ref[UInt64]) -> UInt64 {
  let mut x = state.val
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  state.val = x
  x
}

///|
let exact_division_diff_cases : Int32 = 300

///|
fn reference_exact_decimal_division_result(
  dividend : Decimal,
  divisor : Decimal,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  guard dividend.class == FpClass::Finite &&
    divisor.class == FpClass::Finite &&
    !dividend.coefficient.is_zero() &&
    !divisor.coefficient.is_zero() else {
    return None
  }
  let gcd = dec_coeff_gcd_repr(dividend.coefficient, divisor.coefficient)
  let (reduced_denominator, denominator_remainder) = dec_coeff_div_rem_repr(
    divisor.coefficient,
    gcd,
  )
  guard denominator_remainder.is_zero() else {
    abort("reference exact division expected an exact denominator gcd division")
  }
  let (without_twos, twos) = dec_coeff_count_factor_unit_repr(
    reduced_denominator, 2,
  )
  let (without_fives, fives) = dec_coeff_count_factor_unit_repr(without_twos, 5)
  guard dec_coeff_compare_repr(without_fives, dec_coeff_from_int(1)) == 0 else {
    return None
  }
  let (reduced_numerator, numerator_remainder) = dec_coeff_div_rem_repr(
    dividend.coefficient,
    gcd,
  )
  guard numerator_remainder.is_zero() else {
    abort("reference exact division expected an exact numerator gcd division")
  }
  let scale = Int32::max(twos, fives)
  let magnitude = dec_coeff_multiply_repr(
    reduced_numerator,
    dec_coeff_pow_unit_repr(2, scale - twos),
  )
  let magnitude = dec_coeff_multiply_repr(
    magnitude,
    dec_coeff_pow_unit_repr(5, scale - fives),
  )
  Some(
    normalize_decimal_parts_ctx_repr(
      dividend.negative != divisor.negative,
      magnitude,
      dividend.exponent10 - divisor.exponent10 - scale,
      ctx,
    ),
  )
}

///|
fn exact_division_same_decimal(a : Decimal, b : Decimal) -> Bool {
  a.class == b.class &&
  a.negative == b.negative &&
  a.exponent10 == b.exponent10 &&
  a.precision_ == b.precision_ &&
  a.coefficient.to_string() == b.coefficient.to_string()
}

///|
fn exact_division_check(
  dividend : Decimal,
  divisor : Decimal,
  ctx : DecimalContext,
) -> Unit raise {
  let actual = exact_decimal_division_result(dividend, divisor, ctx)
  let expected = reference_exact_decimal_division_result(dividend, divisor, ctx)
  let same = match (actual, expected) {
    (None, None) => true
    (Some((value, flags)), Some((reference, reference_flags))) =>
      exact_division_same_decimal(value, reference) && flags == reference_flags
    _ => false
  }
  if !same {
    fail(
      "exact division differs: \{dividend.coefficient.to_string()}E\{dividend.exponent10} / \{divisor.coefficient.to_string()}E\{divisor.exponent10}",
    )
  }
}

///|
fn exact_division_digits(state : Ref[UInt64], count : Int32) -> String {
  let builder = StringBuilder()
  for index in 0..<count {
    let digit = (exact_division_next(state) % 10UL).to_int()
    builder.write_string(
      if index == 0 && digit == 0 {
        "3"
      } else {
        digit.to_string()
      },
    )
  }
  builder.to_string()
}

///|
fn exact_division_contexts() -> Array[DecimalContext] {
  let contexts = [
    DecimalContext::decimal32(),
    DecimalContext::decimal64(),
    DecimalContext::decimal128(),
  ]
  for precision in [1, 2, 3, 7, 16, 34, 60] {
    for
      rounding in [
        DecimalRoundingMode::RoundTiesToEven,
        DecimalRoundingMode::RoundTiesToAway,
        DecimalRoundingMode::RoundTowardPositive,
        DecimalRoundingMode::RoundTowardNegative,
        DecimalRoundingMode::RoundTowardZero,
      ] {
      contexts.push(DecimalContext::new(precision~, rounding~))
    }
  }
  contexts
}

///|
test "exact division with the finite-expansion decision equals the gcd route" {
  let wide = DecimalContext::new(precision=400)
  let contexts = exact_division_contexts()
  let state = Ref(0x9E3779B97F4A7C15UL)
  for iteration in 0..<exact_division_diff_cases {
    let ctx = contexts[iteration % contexts.length()]
    let dividend_digits = exact_division_digits(
      state,
      (exact_division_next(state) % 60UL).to_int() + 1,
    )
    let part_digits = exact_division_digits(
      state,
      (exact_division_next(state) % 30UL).to_int() + 1,
    )
    let twos = [0, 1, 3, 8, 9, 12, 30][(exact_division_next(state) % 7UL).to_int()]
    let fives = [0, 1, 5, 8, 9, 14][(exact_division_next(state) % 6UL).to_int()]
    let divisor_text = part_digits
    let mut divisor = Decimal::from_string_ctx(divisor_text, wide).0
    for _ in 0..<twos {
      divisor = divisor.mul_ctx(Decimal::from_string_ctx("2", wide).0, wide).0
    }
    for _ in 0..<fives {
      divisor = divisor.mul_ctx(Decimal::from_string_ctx("5", wide).0, wide).0
    }
    let exponent = (exact_division_next(state) % 41UL).to_int() - 20
    let negative_dividend = exact_division_next(state) % 2UL == 0UL
    let dividend = Decimal::from_string_ctx(
        (if negative_dividend { "-" } else { "" }) +
        dividend_digits +
        "E" +
        exponent.to_string(),
        wide,
      ).0
    let part = Decimal::from_string_ctx(part_digits, wide).0
    exact_division_check(dividend, divisor, ctx)
    // a multiple of the part prime to 10, and of the whole divisor
    exact_division_check(dividend.mul_ctx(part, wide).0, divisor, ctx)
    exact_division_check(dividend.mul_ctx(divisor, wide).0, divisor, ctx)
    exact_division_check(divisor, divisor, ctx)
    exact_division_check(Decimal::from_string_ctx("1", wide).0, divisor, ctx)
  }
}

///|
test "the shared empty flag set is never written" {
  let none = DecimalFlags::new()
  let fresh : DecimalFlags = {
    inexact: false,
    underflow: false,
    overflow: false,
    division_by_zero: false,
    invalid_operation: false,
    not_computed: false,
  }
  let updated = { ..none, inexact: true, }
  assert_true(updated != none)
  assert_true(none.combine(updated).combine(none) == updated)
  assert_true(updated.combine(none) == updated)
  assert_true(DecimalFlags::new() == fresh)
  // operations that raise flags on contexts built from the shared value
  let ctx = DecimalContext::new(precision=7)
  let a = Decimal::from_string_ctx("1234567890123456789", ctx).0
  let b = Decimal::from_string_ctx("9.87654321E-3", ctx).0
  for _ in 0..<4 {
    let (_, flags) = a.add_ctx(b, ctx)
    assert_true(flags.inexact())
    ignore(a.sub_ctx(b, ctx))
    ignore(a.mul_ctx(b, ctx))
    ignore(a.div_ctx(b, ctx))
  }
  assert_true(DecimalFlags::new() == fresh)
  assert_true(DecimalFlags::new() == none)
  assert_true(decimal_flags_are_clear(DecimalFlags::new()))
}
