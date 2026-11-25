///|
// oracle: A
// source: counts written out from the four results of the block: two executable (one pass, one fail), one unsupported,
//   one diagnostic; skipped is unsupported plus diagnostic, so 2
// shares: nothing
test "shared conformance summary folds dispositions" {
  let summary = RunSummary::from_results(4, [
    CaseResult::executable("pass", true),
    CaseResult::executable("fail", false, message="mismatch"),
    CaseResult::new("skip", Unsupported("operation"), false),
    CaseResult::new("bad", Diagnostic("syntax"), false),
  ])
  assert_eq(summary.total_cases(), 4)
  assert_eq(summary.selected_cases(), 4)
  assert_eq(summary.executable_cases(), 2)
  assert_eq(summary.passed_cases(), 1)
  assert_eq(summary.failed_cases(), 1)
  assert_eq(summary.skipped_cases(), 2)
  assert_eq(summary.unsupported_cases(), 1)
  assert_eq(summary.diagnostic_cases(), 1)
  assert_false(summary.success())
}

///|
// oracle: A
// source: the counts are written out from the construction of the summary below (one passing case, one
//   unsupported, one diagnostic, one legacy case); nothing is computed by a second implementation of the folding
// shares: nothing
test "success ignores skipped cases and success_with_counts does not" {
  let summary = RunSummary::from_results(4, [
    CaseResult::executable("pass", true),
    CaseResult::new("skip", Unsupported("operation"), false),
    CaseResult::new("bad", Diagnostic("syntax"), false),
    CaseResult::new("old", Legacy("superseded"), false),
  ])
  assert_eq(summary.failed_cases(), 0)
  assert_eq(summary.skipped_cases(), 3)
  assert_true(summary.success())
  // the stated numbers must be exact: one row more or less skipped is a failure
  assert_true(
    summary.success_with_counts(
      skipped=3,
      diagnostic=1,
      legacy=1,
      unsupported=1,
    ),
  )
  assert_false(
    summary.success_with_counts(
      skipped=2,
      diagnostic=1,
      legacy=0,
      unsupported=1,
    ),
  )
  assert_false(
    summary.success_with_counts(
      skipped=3,
      diagnostic=1,
      legacy=1,
      unsupported=0,
    ),
  )
  let failing = RunSummary::from_results(2, [
    CaseResult::executable("pass", true),
    CaseResult::executable("fail", false, message="mismatch"),
  ])
  assert_false(
    failing.success_with_counts(
      skipped=0,
      diagnostic=0,
      legacy=0,
      unsupported=0,
    ),
  )
}

///|
// oracle: A
// source: written out: a shard count of 0 is refused; shard 1 of 3 selects the ordinals congruent to 1 modulo 3 among
//   0 to 9 (1, 4, 7); the block states the rule ordinal % 3 == 1, which is the definition
// shares: nothing
test "shared shard specification validates and selects ordinals" {
  assert_true(ShardSpec::try_new(0, 0) is Err(_))
  let shard = ShardSpec::new(3, 1)
  for ordinal in 0..<10 {
    assert_eq(shard.selects(ordinal), ordinal % 3 == 1)
  }
}
