///|
/// The certified exponential as it ran before the binary candidate became
/// the first attempt: the conservative precision and the decimal series
/// candidate from the start.
fn decimal_certified_exp_result_reference(
  value : Decimal,
  ctx : DecimalContext,
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
  ).unwrap()
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
    ).unwrap()
    let value = midpoint.ln_ctx(high).0
    assert_true(
      exp_candidate_same(
        decimal_certified_exp_result(value, context),
        decimal_certified_exp_result_reference(value, context),
      ),
    )
  }
}
