// The refinement limit of the context (#15): `Some(n)` stops the certified
// refinement loops after `n` steps (at least one) with a certification
// failure, `None` has no count limit, and the default `Some(12)` is today's
// hard-coded value.

///|
fn refinement_context(precision : Int32) -> DecimalContext {
  DecimalContext::new(precision~, e_max=999_999)
}

///|
/// `exp(5E-34)` at 34 digits lies above the midpoint `1 + 5E-34` of two
/// neighbours by about `1.25E-67`: rounding needs about 7 digits more than the
/// first enclosure carries.
fn refinement_hard_input() -> Decimal {
  Decimal::from_string("5E-34", precision=34).unwrap()
}

///|
fn refinement_failed(
  result : Result[(Decimal, DecimalFlags), @def.ArithmeticError],
) -> Bool {
  match result {
    Err(error) => error.certification_failure_detail() is Some(_)
    Ok(_) => false
  }
}

///|
test "refinement limit: default is Some(12) and matches the explicit value" {
  let context = refinement_context(34)
  inspect(context.refinement_limit() == Some(12), content="true")
  inspect(
    DecimalContext::decimal64().refinement_limit() == Some(12),
    content="true",
  )
  let x = refinement_hard_input()
  let a = x.try_exp_ctx(context).unwrap().0
  let b = x.try_exp_ctx(context.with_refinement_limit(Some(12))).unwrap().0
  inspect(a.to_string() == b.to_string(), content="true")
  inspect(a.to_string().has_suffix("0001"), content="true")
}

///|
test "refinement limit: a hard-to-round exp fails at a small limit and succeeds at a larger one" {
  let x = refinement_hard_input()
  let base = refinement_context(34)
  let default = x.try_exp_ctx(base).unwrap().0
  for limit in [1, 2] {
    inspect(
      refinement_failed(x.try_exp_ctx(base.with_refinement_limit(Some(limit)))),
      content="true",
    )
  }
  let enough = x.try_exp_ctx(base.with_refinement_limit(Some(2 + 1))).unwrap().0
  let none = x.try_exp_ctx(base.with_refinement_limit(None)).unwrap().0
  inspect(enough.to_string() == default.to_string(), content="true")
  inspect(none.to_string() == default.to_string(), content="true")
}

///|
test "refinement limit: 0, 1 and negative limits are one step" {
  let x = refinement_hard_input()
  let base = refinement_context(34)
  for limit in [0, 1, -5] {
    inspect(
      refinement_failed(x.try_exp_ctx(base.with_refinement_limit(Some(limit)))),
      content="true",
    )
  }
  match x.try_exp_ctx(base.with_refinement_limit(Some(1))) {
    Err(error) =>
      match error.certification_failure_detail() {
        Some(detail) => inspect(detail.refinements, content="1")
        None => abort("expected a certification failure")
      }
    Ok(_) => abort("expected a failure")
  }
}

///|
test "refinement limit: contexts that differ only in the limit are different" {
  let a = DecimalContext::decimal64()
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
}
