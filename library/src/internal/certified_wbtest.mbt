///|
// oracle: A
// source: written out by hand: 1/3 at scale 8 is 256/3 = 85.33.., so the enclosure is 85/256 to 86/256; -1/3 is -86/256 to -85/256
// shares: CertifiedDyadic::from_int and the numerator and scale accessors
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
// oracle: A
// source: hand derived and checked with CPython fractions (floor and ceil of numerator / denominator * 2^scale), rows listed as numerator (value, scale), denominator (value, scale), result scale: 1/-3 at 8 is -85.33 so -86 and -85; -1/-3 at 8 is 85 and 86; 5/-2 at 4 is exactly -40; -7/-4 at 2 is exactly 7; 2/-3 at 4 is -10.67 so -11 and -10; (3/2)/(-3/4) at 3 is exactly -16; (1/4)/(-3/2) at 4 is -2.67 so -3 and -2
// shares: CertifiedDyadic::new and the numerator accessors
test "certified dyadic division with negative denominators" {
  let rows : Array[((Int32, Int32), (Int32, Int32), Int32, Int32, Int32)] = [
    ((1, 0), (-3, 0), 8, -86, -85),
    ((-1, 0), (-3, 0), 8, 85, 86),
    ((5, 0), (-2, 0), 4, -40, -40),
    ((-7, 0), (-4, 0), 2, 7, 7),
    ((2, 0), (-3, 0), 4, -11, -10),
    ((3, 1), (-3, 2), 3, -16, -16),
    ((1, 2), (-3, 1), 4, -3, -2),
  ]
  for row in rows {
    let (n, d, scale, lower, upper) = row
    let result = certified_dyadic_div(
      CertifiedDyadic::new(BigInt::from_int(n.0), n.1),
      CertifiedDyadic::new(BigInt::from_int(d.0), d.1),
      scale,
    ).unwrap()
    assert_eq(result.lower().numerator(), BigInt::from_int(lower))
    assert_eq(result.upper().numerator(), BigInt::from_int(upper))
    assert_eq(result.lower().scale(), scale)
  }
}

///|
// oracle: A
// source: the contract of CertifiedInterval::new (lower bound above upper bound is an invalid enclosure, reported at the enclosure propagation stage), written as the two enum values
// shares: the failure detail accessors
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
// oracle: A
// source: written out by hand: the budget grows by one half per refinement, 64, 96 = 64 * 3 / 2, 144 = 96 * 3 / 2; the failure detail fields are the literals passed in
// shares: nothing
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
