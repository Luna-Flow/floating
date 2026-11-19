///|
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
}

///|
test "shared shard specification validates and selects ordinals" {
  assert_true(ShardSpec::try_new(0, 0) is Err(_))
  let shard = ShardSpec::new(3, 1)
  for ordinal in 0..<10 {
    assert_eq(shard.selects(ordinal), ordinal % 3 == 1)
  }
}
