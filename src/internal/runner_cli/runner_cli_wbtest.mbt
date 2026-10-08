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

///|
test "separated shard options do not take the next option as their value" {
  for option in ["--shard-count", "--shard-index"] {
    match parse_common_options(["runner", option, "--json"]) {
      Err(message) => assert_eq(message, option + " requires a value")
      Ok(_) => fail("expected a missing value error for " + option)
    }
  }
}

///|
test "collect_files rejects a named file without the suffix" {
  match collect_files(["README.md"], ".decTest") {
    Err(message) => assert_eq(message, "not a .decTest file: README.md")
    Ok(files) => fail("expected an error, got " + files.join(","))
  }
}

///|
test "collect_files lists each file once and skips directories" {
  let files = collect_files(
    ["testdata/decimal", "testdata/decimal/smoke.decTest"],
    ".decTest",
  ).unwrap()
  assert_eq(files, ["testdata/decimal/smoke.decTest"])
  // `testdata/decimal` is a directory whose name ends in the suffix.
  assert_eq(collect_files(["testdata"], "decimal").unwrap(), [])
}
