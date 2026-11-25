///|
// oracle: A
// source: written out: the argument list names --json, --shard-count=3 and --shard-index 1 and leaves the word input
// shares: nothing
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
// oracle: A
// source: the expected JSON text is written out character by character: a quote inside a string is escaped with a
//   backslash (RFC 8259) and the integer 2 is a bare number
// shares: nothing
test "JSON helpers escape string values" {
  let value = json_object([
    ("message", json_string("quote: \"")),
    ("count", json_int(2)),
  ])
  assert_eq(json_stringify(value), "{\"message\":\"quote: \\\"\",\"count\":2}")
}

///|
// oracle: A
// source: written out: the option that follows is --json, so --shard-count and --shard-index each lack a value and the
//   message is the option name followed by requires a value
// shares: nothing
test "separated shard options do not take the next option as their value" {
  for option in ["--shard-count", "--shard-index"] {
    match parse_common_options(["runner", option, "--json"]) {
      Err(message) => assert_eq(message, option + " requires a value")
      Ok(_) => fail("expected a missing value error for " + option)
    }
  }
}

///|
// oracle: A
// source: written out: moon.mod is a file of the module directory and does not end in .decTest, the message names it
// shares: the file system (the module directory holds moon.mod)
test "collect_files rejects a named file without the suffix" {
  // Tests run in the module directory `tooling/`: `moon.mod` is a file there and
  // the repository's `testdata/` is one level up.
  match collect_files(["moon.mod"], ".decTest") {
    Err(message) => assert_eq(message, "not a .decTest file: moon.mod")
    Ok(files) => fail("expected an error, got " + files.join(","))
  }
}

///|
// oracle: A
// source: written out: of the two paths, testdata/decimal is a directory and is skipped and smoke.decTest is a file of
//   the repository, so one file is listed; no file name in testdata ends in the suffix decimal
// shares: the file system (the repository testdata directory)
test "collect_files lists each file once and skips directories" {
  let files = collect_files(
    ["../testdata/decimal", "../testdata/decimal_gda/smoke.decTest"],
    ".decTest",
  ).unwrap()
  assert_eq(files, ["../testdata/decimal_gda/smoke.decTest"])
  // `../testdata/decimal` is a directory whose name ends in the suffix.
  assert_eq(collect_files(["../testdata"], "decimal").unwrap(), [])
}
