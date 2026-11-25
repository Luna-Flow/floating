///|
// The conditions of the fast paths (`gda_fast_finish` raises Rounded, and
// Inexact when a nonzero digit was dropped, through shared constants) against
// the general route at the public level: trapped signals, a context whose
// status already holds the conditions or others, every rounding mode, narrow
// ranges and clamping (helpers of `gda_fast_small_wbtest.mbt`).

///|
fn gda_fast_trap_context(random : GdaFastRandom) -> GdaContext {
  let base = gda_fast_context(random)
  let traps = match random.below(6) {
    0 => GdaTrapSet::new().with_signal(Rounded)
    1 => GdaTrapSet::new().with_signal(Inexact)
    2 => GdaTrapSet::new().with_signal(Rounded).with_signal(Inexact)
    _ => GdaTrapSet::new()
  }
  let with_traps = base.with_traps(traps)
  // a status that holds nothing, Rounded, Rounded and Inexact, or other
  // conditions, to hit every branch of the status update
  match random.below(5) {
    0 => with_traps
    1 => gda_context_with_flags(with_traps, gda_flags_rounded_only)
    2 => gda_context_with_flags(with_traps, gda_flags_rounded_inexact)
    3 =>
      gda_context_with_flags(with_traps, { ..GdaFlags::new(), clamped: true, })
    _ => with_traps
  }
}

///|
// oracle: E
// source: the previous behaviour of the operation kept in the test: the general route at the public level, compared in full (value representation, flags raised, status of the next context, trapped or completed)
// shares: complete_decimal_gda, add_ctx, mul_ctx, div_ctx
// underneath: the general route (add_ctx, sub_ctx, mul_ctx, div_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic without traps: the official decTest corpus (gate stages DECIMAL_GDA: official decTest and official0) and the CPython rows of plain_operator_rows_wbtest.mbt (precision 3, 16, 34); traps, the chaining of the status and the subset arithmetic (extended false) have no level A or B oracle, so those inputs stay level E
test "fast paths raise the general route's conditions, status and traps" {
  let random = { fast_state: 0xA076_1D64_78BD_642FUL, }
  let mut rounded_only = 0
  let mut rounded_inexact = 0
  let mut trapped = 0
  for index in 0..<60000 {
    let context = gda_fast_trap_context(random)
    let lhs = gda_fast_operand_value(random, random.below(20) - 10)
    let rhs = gda_fast_operand_value(random, random.below(20) - 10)
    let operation = index % 4
    let (expected, actual) = if operation == 0 {
      (gda_fast_generic_sum(lhs, rhs, context, false), add(lhs, rhs, context))
    } else if operation == 1 {
      (
        gda_fast_generic_sum(lhs, rhs, context, true),
        subtract(lhs, rhs, context),
      )
    } else if operation == 2 {
      let (value, flags) = lhs.mul_ctx(rhs, context.decimal_context())
      (complete_decimal_gda(value, context, flags), multiply(lhs, rhs, context))
    } else {
      let (value, flags) = lhs.div_ctx(rhs, context.decimal_context())
      (complete_decimal_gda(value, context, flags), divide(lhs, rhs, context))
    }
    assert_true(gda_fast_same(actual, expected))
    let raised = expected.raised()
    if raised.rounded && !raised.inexact {
      rounded_only += 1
    }
    if raised.rounded && raised.inexact {
      rounded_inexact += 1
    }
    if actual is Trapped(_, _, _, _) {
      trapped += 1
    }
  }
  assert_true(rounded_only > 100)
  assert_true(rounded_inexact > 5000)
  assert_true(trapped > 500)
}

///|
/// A product whose dropped digits are zeros raises Rounded and not Inexact:
/// 10^15 * 10^3 at 16 digits drops three zeros.
// oracle: A, E
// source: written out: 10^15 * 10^3 at 16 digits drops three zeros, so Rounded is raised and Inexact is not (GDA 1.70, Rounded and Inexact conditions); the general route is compared as well
// shares: complete_decimal_gda, mul_ctx for the comparison
// underneath: the general route (add_ctx, sub_ctx, mul_ctx, div_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic without traps: the official decTest corpus (gate stages DECIMAL_GDA: official decTest and official0) and the CPython rows of plain_operator_rows_wbtest.mbt (precision 3, 16, 34); traps, the chaining of the status and the subset arithmetic (extended false) have no level A or B oracle, so those inputs stay level E
test "a fast product that drops only zeros raises Rounded without Inexact" {
  let context = GdaContext::new(precision=16)
  let lhs = finite_with_exponent_repr(
    false,
    DecCoeff::Small(1000000000000000UL),
    0,
    16,
  )
  let rhs = finite_with_exponent_repr(false, DecCoeff::Small(1000UL), 0, 4)
  let outcome = multiply(lhs, rhs, context)
  let raised = outcome.raised()
  assert_true(raised.rounded && !raised.inexact)
  assert_true(gda_fast_product(lhs, rhs, context) is Some(_))
  let (value, flags) = lhs.mul_ctx(rhs, context.decimal_context())
  assert_true(
    gda_fast_same(outcome, complete_decimal_gda(value, context, flags)),
  )
}

///|
/// The word that replaces `Option[UInt64]` is 0 for an operand the fast paths
/// do not take: zero, NaN, infinity, a wide coefficient, a huge exponent.
// oracle: A, E
// source: written out: the fast paths take only finite nonzero operands of at most 18 digits and a moderate exponent, so each of zero, NaN, infinity, a 23-digit coefficient and an exponent of 6*10^8 is declined; for the declined operands the public result is compared with the general route
// shares: complete_decimal_gda, add_ctx, mul_ctx, div_ctx for the comparison
// underneath: the general route (add_ctx, sub_ctx, mul_ctx, div_ctx, then complete_decimal_gda) has level A oracles on extended arithmetic without traps: the official decTest corpus (gate stages DECIMAL_GDA: official decTest and official0) and the CPython rows of plain_operator_rows_wbtest.mbt (precision 3, 16, 34); traps, the chaining of the status and the subset arithmetic (extended false) have no level A or B oracle, so those inputs stay level E
test "fast paths decline a zero, a NaN, an infinity and a wide operand" {
  let context = GdaContext::new(precision=16)
  let one = finite_with_exponent_repr(false, DecCoeff::Small(7UL), 0, 1)
  let zero = finite_with_exponent_repr(false, DecCoeff::Small(0UL), 0, 1)
  let nan = Decimal::nan(precision=16)
  let inf = Decimal::inf(precision=16)
  let wide = Decimal::from_string("12345678901234567890123").unwrap()
  let far = finite_with_exponent_repr(false, DecCoeff::Small(7UL), 600000000, 1)
  for operand in [zero, nan, inf, wide, far] {
    assert_eq(gda_fast_operand(operand), 0UL)
    assert_true(gda_fast_sum(one, operand, context, false) is None)
    assert_true(gda_fast_sum(operand, one, context, true) is None)
    assert_true(gda_fast_product(one, operand, context) is None)
    assert_true(gda_fast_product(operand, one, context) is None)
    assert_true(gda_fast_quotient(one, operand, context) is None)
    assert_true(gda_fast_quotient(operand, one, context) is None)
    for pair in [(one, operand), (operand, one)] {
      let (a, b) = pair
      let (value, flags) = a.add_ctx(b, context.decimal_context())
      assert_true(
        gda_fast_same(
          add(a, b, context),
          complete_decimal_gda(value, context, flags),
        ),
      )
      let (value, flags) = a.mul_ctx(b, context.decimal_context())
      assert_true(
        gda_fast_same(
          multiply(a, b, context),
          complete_decimal_gda(value, context, flags),
        ),
      )
      let (value, flags) = a.div_ctx(b, context.decimal_context())
      assert_true(
        gda_fast_same(
          divide(a, b, context),
          complete_decimal_gda(value, context, flags),
        ),
      )
    }
  }
}
