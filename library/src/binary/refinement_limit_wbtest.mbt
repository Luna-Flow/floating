// The refinement limit of the context (#15): `Some(n)` stops the certified
// refinement loops after `n` steps (at least one) with a certification
// failure, `None` has no count limit and stops at a work precision cap, and
// the default `Some(12)` is today's hard-coded value.

///|
/// `x = ln(1 + 2^-53)` at 330 bits, so `exp(x)` lies within about 2^-330 of the
/// midpoint `1 + 2^-53` between 1 and its successor at 53 bits: rounding to
/// nearest needs more than 300 bits of the enclosure.
fn refinement_hard_input() -> Binary {
  let wide = BinaryContext::new(precision=330)
  let one = Binary::from_int(1, precision=330)
  let step = one.scaleb_ctx(Binary::from_int(-53), wide).0
  let midpoint = one.add_ctx(step, wide).0
  midpoint.try_ln_ctx(wide).unwrap().0
}

///|
fn refinement_failed(
  result : Result[(Binary, BinaryFlags), @def.ArithmeticError],
) -> Bool {
  match result {
    Err(error) => error.certification_failure_detail() is Some(_)
    Ok(_) => false
  }
}

///|
// oracle: S
// source: the default written as Some(12) (the documented default) and the same call under the explicit limit; no external value
// shares: BinaryContext::refinement_limit and try_exp_ctx (the code under test)
test "refinement limit: default is Some(12) and matches the explicit value" {
  let context = BinaryContext::new(precision=53)
  inspect(context.refinement_limit() == Some(12), content="true")
  inspect(
    BinaryContext::binary64().refinement_limit() == Some(12),
    content="true",
  )
  inspect(
    BinaryContext::new(precision=24).refinement_limit() == Some(12),
    content="true",
  )
  let x = refinement_hard_input()
  let a = x.try_exp_ctx(context)
  let b = x.try_exp_ctx(context.with_refinement_limit(Some(12)))
  inspect(a.unwrap().0.identical(b.unwrap().0), content="true")
}

///|
// oracle: S
// source: the same try_exp_ctx call under refinement limits 1 to 3 (failure written from the input, refinement_hard_input, which needs the fourth refinement of 117, 175, 262 and 393 bits), 4, the default and None (identical results); the hard input is documented in the test
// shares: try_exp_ctx and with_refinement_limit (the code under test), refinement_failed
test "refinement limit: a hard-to-round exp fails at a small limit and succeeds at a larger one" {
  let x = refinement_hard_input()
  let base = BinaryContext::new(precision=53)
  // 117, 175, 262 and 393 bits: the fourth refinement step decides.
  inspect(
    refinement_failed(x.try_exp_ctx(base.with_refinement_limit(Some(1)))),
    content="true",
  )
  inspect(
    refinement_failed(x.try_exp_ctx(base.with_refinement_limit(Some(2)))),
    content="true",
  )
  inspect(
    refinement_failed(x.try_exp_ctx(base.with_refinement_limit(Some(3)))),
    content="true",
  )
  let four = x.try_exp_ctx(base.with_refinement_limit(Some(4))).unwrap().0
  let twelve = x.try_exp_ctx(base).unwrap().0
  let none = x.try_exp_ctx(base.with_refinement_limit(None)).unwrap().0
  inspect(four.identical(twelve) && twelve.identical(none), content="true")
}

///|
test "refinement limit: 0, 1 and negative limits are one step" {
  let x = refinement_hard_input()
  let base = BinaryContext::new(precision=53)
  for limit in [0, 1, -5] {
    inspect(
      refinement_failed(x.try_exp_ctx(base.with_refinement_limit(Some(limit)))),
      content="true",
    )
  }
  // An exact-in-one-step case needs only one step: 1 + 2^-60 rounds at once.
  let easy = Binary::from_int(1, precision=53).scaleb_ctx(
      Binary::from_int(-60),
      BinaryContext::new(precision=53),
    ).0
  let result = easy.try_exp_ctx(base.with_refinement_limit(Some(0)))
  inspect(result is Ok(_), content="true")
}

///|
test "refinement limit: the failure reports the refinements taken" {
  let x = refinement_hard_input()
  let base = BinaryContext::new(precision=53)
  match x.try_exp_ctx(base.with_refinement_limit(Some(2))) {
    Err(error) =>
      match error.certification_failure_detail() {
        Some(detail) => inspect(detail.refinements, content="2")
        None => abort("expected a certification failure")
      }
    Ok(_) => abort("expected a failure")
  }
}

///|
// oracle: S
// source: expm1 and exp2 of one input under the default limit and under None; agreement of two configurations of the same code
// shares: try_expm1_ctx and try_exp2_ctx (the code under test on both sides)
test "refinement limit: the exp family agrees with the default under None" {
  let x = refinement_hard_input()
  let base = BinaryContext::new(precision=53)
  let none = base.with_refinement_limit(None)
  inspect(
    x.try_expm1_ctx(none).unwrap().0.identical(x.try_expm1_ctx(base).unwrap().0),
    content="true",
  )
  inspect(
    x.try_exp2_ctx(none).unwrap().0.identical(x.try_exp2_ctx(base).unwrap().0),
    content="true",
  )
}

///|
test "refinement limit: contexts that differ only in the limit are different" {
  let a = BinaryContext::binary64()
  let b = a.with_refinement_limit(Some(3))
  let c = a.with_refinement_limit(None)
  inspect(a == b, content="false")
  inspect(a == c, content="false")
  inspect(b == c, content="false")
  inspect(a == b.with_refinement_limit(Some(12)), content="true")
  inspect(b.refinement_limit() == Some(3), content="true")
  inspect(c.refinement_limit() == None, content="true")
  inspect(
    b.precision() == a.precision() && b.rounding() == a.rounding(),
    content="true",
  )
  inspect(
    BinaryContext::from_arithmetic_context(@lf_arith.ArithmeticContext::new(53))
    .unwrap()
    .refinement_limit() ==
    Some(12),
    content="true",
  )
}

///|
test "refinement limit: None stays bounded by the work cap" {
  inspect(@internal.certified_unbounded_work_cap(53), content="8000000")
  inspect(@internal.certified_unbounded_work_cap(1000000), content="256000000")
  inspect(
    @internal.certified_unbounded_work_cap(268435456),
    content="1000000000",
  )
  inspect(
    @internal.certified_refinement_continues(None, 1000, 8000000, 53),
    content="true",
  )
  inspect(
    @internal.certified_refinement_continues(None, 1000, 8000001, 53),
    content="false",
  )
  inspect(
    @internal.certified_refinement_continues(Some(12), 11, 100000000, 53),
    content="true",
  )
  inspect(
    @internal.certified_refinement_continues(Some(12), 12, 10, 53),
    content="false",
  )
}
