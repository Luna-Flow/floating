///|
/// The decimal series candidate of the exponential. `work_precision` is a
/// number of bits (the precision of the binary enclosure), used as digits with
/// 24 added: far more than the candidate needs. Kept as the reference of the
/// tests; the certified exponential uses `decimal_exp_ball_candidate`.
fn decimal_exp_candidate(value : Decimal, work_precision : Int32) -> Decimal {
  let work_ctx = decimal_math_work_ctx(Int32::max(work_precision + 24, 96))
  let constant_scale = work_ctx.precision + 12
  let (_, _, ln10_scaled) = decimal_transcendental_ln_constants(constant_scale)
  _decimal_exp_finite_work_result_with_ln10(value, work_ctx, ln10_scaled).0
}

///|
/// The loop of `decimal_certified_exp_result`, counting the attempts.
fn decimal_certified_exp_result_counted(
  value : Decimal,
  ctx : DecimalContext,
  attempts : @ref.Ref[Int32],
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  match decimal_certified_exp_coarse_extreme_result(value, ctx) {
    Some(result) => return Ok(result)
    None => ()
  }
  let initial_precision = decimal_certified_exp_work_precision(value, ctx)
  let conservative_precision = decimal_certified_conservative_work_precision(
    value, ctx,
  )
  let mut budget = CertifiedRefinementBudget::new(initial_precision)
  let mut fast_attempt = initial_precision < conservative_precision
  while budget.available() {
    attempts.val += 1
    let input = decimal_to_certified_ball(value, budget.precision())
    match input.try_exp_interval() {
      Ok(interval) => {
        let candidate = decimal_exp_ball_candidate(
          value,
          interval,
          ctx,
          budget.precision(),
        )
        match
          decimal_certified_half_even_candidate(
            interval,
            candidate,
            value,
            ctx,
            budget.precision(),
          ) {
          Some(result) => return Ok(result)
          None =>
            if fast_attempt {
              budget = CertifiedRefinementBudget::new(conservative_precision)
              fast_attempt = false
            } else {
              match decimal_certified_target(interval, ctx) {
                Some(result) => return Ok(result)
                None => budget = budget.next()
              }
            }
        }
      }
      Err(error) =>
        if error.certification_failure_detail() is Some(_) {
          if fast_attempt {
            budget = CertifiedRefinementBudget::new(conservative_precision)
            fast_attempt = false
          } else {
            budget = budget.next()
          }
        } else {
          return Err(error)
        }
    }
  }
  Err(decimal_certified_failure("exp", ctx, budget))
}

///|
/// The certified exponential as it ran before the binary candidate became
/// the first attempt: the conservative precision and the decimal series
/// candidate from the start.
fn decimal_certified_exp_result_reference(
  value : Decimal,
  ctx : DecimalContext,
  attempts~ : @ref.Ref[Int32] = @ref.Ref(0),
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  match decimal_certified_exp_coarse_extreme_result(value, ctx) {
    Some(result) => return Ok(result)
    None => ()
  }
  let initial_precision = decimal_certified_work_precision(value, ctx)
  let conservative_precision = decimal_certified_conservative_work_precision(
    value, ctx,
  )
  let mut budget = CertifiedRefinementBudget::new(initial_precision)
  let mut fast_attempt = initial_precision < conservative_precision
  while budget.available() {
    attempts.val += 1
    let input = decimal_to_certified_ball(value, budget.precision())
    match input.try_exp_interval() {
      Ok(interval) => {
        let candidate = if fast_attempt {
          decimal_ball_candidate(interval, ctx)
        } else {
          decimal_exp_candidate(value, budget.precision())
        }
        match
          decimal_certified_half_even_candidate(
            interval,
            candidate,
            value,
            ctx,
            budget.precision(),
          ) {
          Some(result) => return Ok(result)
          None =>
            if fast_attempt {
              budget = CertifiedRefinementBudget::new(conservative_precision)
              fast_attempt = false
            } else {
              match decimal_certified_target(interval, ctx) {
                Some(result) => return Ok(result)
                None => budget = budget.next()
              }
            }
        }
      }
      Err(error) =>
        if error.certification_failure_detail() is Some(_) {
          if fast_attempt {
            budget = CertifiedRefinementBudget::new(conservative_precision)
            fast_attempt = false
          } else {
            budget = budget.next()
          }
        } else {
          return Err(error)
        }
    }
  }
  Err(decimal_certified_failure("exp", ctx, budget))
}

///|
struct ExpCandidateRandom {
  mut exp_state : UInt64
}

///|
fn ExpCandidateRandom::next(self : ExpCandidateRandom) -> UInt64 {
  self.exp_state = self.exp_state * 6364136223846793005UL +
    1442695040888963407UL
  self.exp_state >> 11
}

///|
fn ExpCandidateRandom::below(self : ExpCandidateRandom, limit : Int32) -> Int32 {
  (self.next() % limit.to_uint64()).to_int()
}

///|
fn exp_candidate_argument(random : ExpCandidateRandom) -> Decimal {
  let count = 1 + random.below(40)
  let mut coefficient = dec_coeff_from_int(1 + random.below(9))
  for _ in 1..<count {
    coefficient = dec_coeff_multiply_by_unit_repr(coefficient, 10)
    coefficient = dec_coeff_magnitude_add_unit(coefficient, random.below(10))
  }
  // adjusted exponent from -40 to 3, so that the arguments below and above
  // the fast range both occur
  let adjusted = random.below(44) - 40
  finite_with_exponent_repr(
    random.below(2) == 0,
    coefficient,
    adjusted - (count - 1),
    count,
  )
}

///|
fn exp_candidate_context(random : ExpCandidateRandom) -> DecimalContext {
  let precisions = [1, 2, 5, 9, 16, 17, 20, 34, 40, 64, 100]
  DecimalContext::new(
    precision=precisions[random.below(11)],
    decimal_rounding=DecimalRoundingMode::HalfEven,
    e_min=-999999,
    e_max=999999,
    extended=true,
  )
}

///|
fn exp_candidate_same(
  actual : Result[(Decimal, DecimalFlags), @def.ArithmeticError],
  expected : Result[(Decimal, DecimalFlags), @def.ArithmeticError],
) -> Bool {
  match (actual, expected) {
    (Ok((value, flags)), Ok((reference, reference_flags))) =>
      value.to_string() == reference.to_string() &&
      value.precision() == reference.precision() &&
      flags == reference_flags
    (Err(_), Err(_)) => true
    _ => false
  }
}

///|
test "binary candidate exp equals the decimal series candidate" {
  let random = { exp_state: 0xE7A1BC0FFEEUL, }
  for _ in 0..<400 {
    let context = exp_candidate_context(random)
    let value = exp_candidate_argument(random)
    let actual = decimal_certified_exp_result(value, context)
    let expected = decimal_certified_exp_result_reference(value, context)
    assert_true(exp_candidate_same(actual, expected))
  }
}

///|
test "binary candidate exp at arguments whose result is near a rounding boundary" {
  let random = { exp_state: 0x51DE5EEDUL, }
  for _ in 0..<150 {
    let context = exp_candidate_context(random)
    // the argument ln(m) for m a midpoint between two results of `context`:
    // the exponential is within 10^-50 of the boundary
    let digits = context.precision
    let mut coefficient = dec_coeff_from_int(1 + random.below(9))
    for _ in 1..<digits {
      coefficient = dec_coeff_multiply_by_unit_repr(coefficient, 10)
      coefficient = dec_coeff_magnitude_add_unit(coefficient, random.below(10))
    }
    coefficient = dec_coeff_multiply_by_unit_repr(coefficient, 10)
    coefficient = dec_coeff_magnitude_add_unit(coefficient, 5)
    let midpoint = finite_with_exponent_repr(
      false,
      coefficient,
      random.below(3) - digits - 1,
      digits + 1,
    )
    let high = DecimalContext::new(
      precision=digits + 60,
      decimal_rounding=DecimalRoundingMode::HalfEven,
      e_min=-999999,
      e_max=999999,
      extended=true,
    )
    let value = midpoint.ln_ctx(high).0
    assert_true(
      exp_candidate_same(
        decimal_certified_exp_result(value, context),
        decimal_certified_exp_result_reference(value, context),
      ),
    )
  }
}

///|
let exp_candidate_modes : Array[DecimalRoundingMode] = [
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
/// decimal32, decimal64, decimal128 and odd contexts, every rounding mode,
/// non-extended and narrow exponent ranges: the production loop gives the same
/// value, cohort and flags as the loop with the decimal series candidate, in
/// no more attempts.
test "midpoint candidate exp equals the series candidate in standard contexts" {
  let random = { exp_state: 0xD0C0FFEE5UL, }
  // (precision, e_min, e_max, extended, clamp)
  let shapes = [
    (7, -101, 96, false, true),
    (16, -398, 384, false, true),
    (34, -6176, 6144, false, true),
    (16, -398, 384, true, false),
    (34, -6176, 6144, true, false),
    (3, -20, 20, false, false),
    (1, -5, 5, true, false),
    (25, -999, 999, false, false),
  ]
  let mut total_new = 0
  let mut total_old = 0
  for shape in shapes {
    let (precision, e_min, e_max, extended, clamp) = shape
    for mode in exp_candidate_modes {
      let context = DecimalContext::new(
        precision~,
        decimal_rounding=mode,
        e_min~,
        e_max~,
        extended~,
        clamp~,
      )
      for _ in 0..<3 {
        let value = exp_candidate_argument(random)
        let new_attempts = @ref.Ref(0)
        let old_attempts = @ref.Ref(0)
        let actual = decimal_certified_exp_result_counted(
          value, context, new_attempts,
        )
        let expected = decimal_certified_exp_result_reference(
          value,
          context,
          attempts=old_attempts,
        )
        assert_true(exp_candidate_same(actual, expected))
        assert_true(
          exp_candidate_same(
            decimal_certified_exp_result(value, context),
            expected,
          ),
        )
        assert_true(new_attempts.val <= old_attempts.val)
        total_new += new_attempts.val
        total_old += old_attempts.val
      }
    }
  }
  assert_true(total_new <= total_old)
}

///|
/// Found by the random differential run (seed 20261120, `exp -3.00E+6` at
/// precision 3 in a context of exponents +-999999): the midpoint of the
/// enclosure is a binary float of exponent about -4.3 million, whose exact
/// decimal conversion never finished. Large arguments use the series.
test "midpoint candidate exp with large arguments in wide exponent contexts" {
  // |x| < 10^3 takes the midpoint, |x| >= 10^3 the series; both signs, on and
  // around the bound, and the row that never finished.
  let arguments = [
    "-3.00E+6", "-2999999", "-1E+5", "-123456.5", "-10001", "-10000", "-1001", "-1000",
    "-999.99", "-999", "-500", "-1.5", "1.5", "999", "999.99", "1000", "1001", "9999",
    "10000", "10001", "123456.5", "1E+5", "2999999",
  ]
  for precision in [3, 16, 34] {
    let context = DecimalContext::new(
      precision~,
      decimal_rounding=DecimalRoundingMode::HalfEven,
      e_min=-999999,
      e_max=999999,
      extended=true,
      clamp=true,
    )
    for text in arguments {
      let value = Decimal::parse(text).unwrap()
      let new_attempts = @ref.Ref(0)
      let old_attempts = @ref.Ref(0)
      let actual = decimal_certified_exp_result_counted(
        value, context, new_attempts,
      )
      let expected = decimal_certified_exp_result_reference(
        value,
        context,
        attempts=old_attempts,
      )
      assert_true(exp_candidate_same(actual, expected))
      assert_true(new_attempts.val <= old_attempts.val)
    }
  }
}
