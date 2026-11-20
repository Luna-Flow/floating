///|
test "certified dyadic division encloses positive and negative ratios" {
  let third = certified_dyadic_div(
    CertifiedDyadic::from_int(1),
    CertifiedDyadic::from_int(3),
    8,
  ).unwrap()
  assert_eq(third.lower().numerator(), 85N)
  assert_eq(third.upper().numerator(), 86N)
  assert_eq(third.lower().scale(), 8)
  let negative = certified_dyadic_div(
    CertifiedDyadic::from_int(-1),
    CertifiedDyadic::from_int(3),
    8,
  ).unwrap()
  assert_eq(negative.lower().numerator(), -86N)
  assert_eq(negative.upper().numerator(), -85N)
}

///|
test "certified interval rejects reversed bounds" {
  let result = CertifiedInterval::new(2, 1, fn(left, right) {
    left.compare(right)
  })
  match result {
    Ok(_) => assert_true(false)
    Err(error) =>
      match error.certification_failure_detail() {
        Some(detail) => {
          assert_true(
            detail.stage() == @def.CertificationStage::EnclosurePropagation,
          )
          assert_true(
            detail.reason() == @def.CertificationFailureReason::InvalidEnclosure,
          )
        }
        None => assert_true(false)
      }
  }
}

///|
test "certified refinement budget grows and retains failure details" {
  let initial = CertifiedRefinementBudget::new(64)
  let next = initial.next()
  let third = next.next()
  assert_eq(initial.precision(), 64)
  assert_eq(next.precision(), 96)
  assert_eq(third.precision(), 144)
  assert_eq(third.refinements(), 2)
  let error = certified_failure(
    "probe",
    @def.CertificationStage::TargetRounding,
    @def.CertificationFailureReason::RefinementBudgetExhausted,
    53,
    third,
  )
  let detail = error.certification_failure_detail().unwrap()
  assert_eq(detail.operation(), "probe")
  assert_eq(detail.target_precision(), 53)
  assert_eq(detail.work_precision(), 144)
  assert_eq(detail.refinements(), 2)
}
