///|
test "common runner options parse JSON and shard flags" {
  let options = parse_common_options([
    "runner", "--json", "--shard-count=3", "--shard-index", "1", "input",
  ]).unwrap()
  assert_true(options.json())
  assert_eq(options.shard_count(), 3)
  assert_eq(options.shard_index(), 1)
  assert_true(options.remaining() == ["input"])
}

///|
test "JSON helpers escape string values" {
  let value = json_object([
    ("message", json_string("quote: \"")),
    ("count", json_int(2)),
  ])
  assert_eq(json_stringify(value), "{\"message\":\"quote: \\\"\",\"count\":2}")
}
