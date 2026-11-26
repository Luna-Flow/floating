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
// oracle: A, S
// source: A for the value 1.000000000000000000000000000000001 of exp(5E-34) at 34 digits, from CPython decimal at 80 digits (exp = 1.00000000000000000000000000000000050000000000000000000000000000000125..., above the midpoint, so it rounds up). S for the rest: that the default limit is Some(12) restates the constant of the code under test (documented on DecimalContext::refinement_limit, not an independent source), and a == b compares the code with itself in two configurations
// shares: DecimalContext::new, refinement_limit, with_refinement_limit, Decimal::from_string, try_exp_ctx and to_string (they build the operands and read the result; the pinned text is from Python)
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
  inspect(a.to_string(), content="1.000000000000000000000000000000001")
}

///|
/// Oracle: the value is level A (Python `decimal`, 80 digits: exp(5E-34) =
/// 1.00000000000000000000000000000000050000000000000000000000000000000125...,
/// above the midpoint, so 1.000000000000000000000000000000001 at 34 digits). The
/// number of refinements a hard input needs is the implementation's own choice, so
/// it is not pinned: the test asserts the shape (a limit that is too small fails
/// with a certification failure, every larger limit and `None` give the value, and
/// the input is hard: one refinement does not certify it).
// oracle: A, S
// source: A for the value of exp(5E-34) from CPython decimal at 80 digits (see the comment above). S for the shape: the number of refinements is the implementation's own choice and is only asserted as a shape (fails at limit 1, succeeds at or before the default 12), which the code under test determines
// shares: DecimalContext::new, with_refinement_limit, Decimal::from_string, try_exp_ctx, certification_failure_detail and to_string (they build the operands and read the results; the pinned text is from Python)
test "refinement limit: a hard-to-round exp fails below a threshold and succeeds from it on" {
  let x = refinement_hard_input()
  let base = refinement_context(34)
  let expected = "1.000000000000000000000000000000001"
  inspect(x.try_exp_ctx(base).unwrap().0.to_string(), content=expected)
  let mut first_success = 0
  for limit in 1..<=20 {
    let result = x.try_exp_ctx(base.with_refinement_limit(Some(limit)))
    if first_success == 0 {
      if refinement_failed(result) {
        continue
      }
      first_success = limit
    }
    inspect(result.unwrap().0.to_string(), content=expected)
  }
  // the loop failed at limit 1 (the input is hard) and succeeded before the
  // default limit of 12
  inspect(first_success > 1 && first_success <= 12, content="true")
  let none = x.try_exp_ctx(base.with_refinement_limit(None)).unwrap().0
  inspect(none.to_string(), content=expected)
}

///|
// oracle: S
// source: the documented rule that a limit of zero, one or a negative number stops the certified loop after one step (DecimalContext::refinement_limit), pinned for the hard input exp(5E-34) at 34 digits: a certification failure with refinements 1; the count is the implementation's own choice and nothing independent is written out
// shares: DecimalContext::new, with_refinement_limit, Decimal::from_string, try_exp_ctx and certification_failure_detail (the code under test)
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
// oracle: S
// source: the written contract of DecimalContext equality (two contexts are equal only if the refinement limit is equal too, the default being Some(12)); the library's own contract, not an external value
// shares: DecimalContext::decimal64, with_refinement_limit, refinement_limit, precision and rounding are the code under test
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
