///|
test "gda interpreter executes decimal operations in process" {
  let source =
    #|precision: 9
    #|rounding: half_even
    #|a1 add 1.20 2 -> 3.20
    #|a2 multiply 3 4 -> 12
    #|a3 compare 2 3 -> -1
    #|a4 samequantum 1.0 2.0 -> 1
    #|
  let document = @gda_expr.parse_dectest("inline.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 4)
  assert_eq(summary.passed_cases(), 4)
  assert_eq(summary.failed_cases(), 0)
}

///|
test "gda interpreter shards merge to serial totals" {
  let source =
    #|x1 add 1 1 -> 2
    #|x2 add 2 2 -> 4
    #|x3 add 3 3 -> 6
    #|x4 add 4 4 -> 8
    #|
  let document = @gda_expr.parse_dectest("shards.decTest", source).unwrap()
  let serial = @gda_expr.execute_documents([document])
  let left = @gda_expr.execute_documents(
    [document],
    options=@gda_expr.RunOptions::new(shard_count=2, shard_index=0),
  )
  let right = @gda_expr.execute_documents(
    [document],
    options=@gda_expr.RunOptions::new(shard_count=2, shard_index=1),
  )
  let merged = @gda_expr.RunSummary::merge([left, right])
  assert_eq(merged.selected_cases(), serial.selected_cases())
  assert_eq(merged.passed_cases(), serial.passed_cases())
  assert_eq(merged.failed_cases(), serial.failed_cases())
}

///|
test "gda interpreter preserves raw interchange copy semantics" {
  let source =
    #|precision: 7
    #|maxExponent: 96
    #|minExponent: -95
    #|c1 canonical #7C00016E -> #7C00006E
    #|c2 copy #7C00016E -> #7C00016E
    #|
  let document = @gda_expr.parse_dectest("decimal32.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.passed_cases(), 2)
  assert_eq(summary.failed_cases(), 0)
}

///|
test "gda interpreter rejects impossible extreme quantize before allocation" {
  let source =
    #|precision: 15
    #|maxExponent: 999999999
    #|minExponent: -999999999
    #|q1 quantize 1.234 1e-999999000 -> ? Invalid_operation
    #|
  let document = @gda_expr.parse_dectest("extreme.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.passed_cases(), 1)
  assert_eq(summary.failed_cases(), 0)
}

///|
test "gda interpreter invalidates the context cache on directives" {
  let source =
    #|precision: 3
    #|rounding: half_even
    #|c1 add 1.23 2.34 -> 3.57
    #|precision: 5
    #|c2 add 1.2345 2.3456 -> 3.5801
    #|rounding: floor
    #|c3 divide 1 3 -> 0.33333 Inexact Rounded
    #|
  let document = @gda_expr.parse_dectest("contexts.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 3)
  assert_eq(summary.passed_cases(), 3)
  assert_eq(summary.failed_cases(), 0)
}

///|
test "gda interpreter applies the 1.70 sqrt rounding rule" {
  let source =
    #|precision: 1
    #|rounding: half_up
    #|s1 squareroot 6.25 -> 2 Inexact Rounded
    #|
  let document = @gda_expr.parse_dectest("sqrt-1.70.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 1)
  assert_eq(summary.passed_cases(), 1)
  assert_eq(summary.failed_cases(), 0)
}
