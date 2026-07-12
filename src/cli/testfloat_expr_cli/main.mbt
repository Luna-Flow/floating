///|
priv struct CliOptions {
  function_name : String
  rounding : String
  tininess : String
  path : String
  json : Bool
  shard_count : Int
  shard_index : Int
}

///|
fn parse_cli(arguments : Array[String]) -> Result[CliOptions, String] {
  let common = match @runner_cli.parse_common_options(arguments) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let arguments = common.remaining()
  let mut function_name = ""
  let mut rounding = "rnear_even"
  let mut tininess = "after"
  let mut path = ""
  let mut index = 0
  while index < arguments.length() {
    let argument = arguments[index]
    if argument == "--function" ||
      argument == "--rounding" ||
      argument == "--tininess" {
      guard index + 1 < arguments.length() else {
        return Err(argument + " requires a value")
      }
      index += 1
      let value = arguments[index]
      match argument {
        "--function" => function_name = value
        "--rounding" => rounding = value
        _ => tininess = value
      }
    } else if argument.has_prefix("-") {
      return Err("unknown option: " + argument)
    } else if path.length() == 0 {
      path = argument
    } else {
      return Err("only one TestFloat vector file is accepted per invocation")
    }
    index += 1
  }
  guard function_name.length() > 0 else { return Err("--function is required") }
  guard path.length() > 0 else {
    return Err("a TestFloat vector path is required")
  }
  Ok({
    function_name,
    rounding,
    tininess,
    path,
    json: common.json(),
    shard_count: common.shard_count(),
    shard_index: common.shard_index(),
  })
}

///|
fn summary_json(
  summary : @testfloat_expr.RunSummary,
  options : CliOptions,
) -> String {
  let failed_ids : Array[String] = []
  for result in summary.results() {
    if !result.passed() {
      failed_ids.push(result.id())
    }
  }
  @runner_cli.json_stringify(
    @runner_cli.json_object([
      ("function", @runner_cli.json_string(options.function_name)),
      ("rounding", @runner_cli.json_string(options.rounding)),
      ("tininess", @runner_cli.json_string(options.tininess)),
      ("totalCases", @runner_cli.json_int(summary.total_cases())),
      ("selectedCases", @runner_cli.json_int(summary.selected_cases())),
      ("passedCases", @runner_cli.json_int(summary.passed_cases())),
      ("failedCases", @runner_cli.json_int(summary.failed_cases())),
      ("failedIds", @runner_cli.json_strings(failed_ids)),
    ]),
  )
}

///|
pub fn run(arguments : Array[String]) -> Int {
  let options = match parse_cli(arguments) {
    Ok(value) => value
    Err(message) => {
      println(message)
      return 2
    }
  }
  let spec = match
    @testfloat_expr.TestFloatSpec::parse(
      options.function_name,
      options.rounding,
      tininess=options.tininess,
    ) {
    Ok(value) => value
    Err(message) => {
      println(message)
      return 2
    }
  }
  let text = match @runner_cli.read_source(options.path) {
    Ok(value) => value
    Err(message) => {
      println(message)
      return 2
    }
  }
  let document = match
    @testfloat_expr.parse_testfloat(options.path, text, spec) {
    Ok(value) => value
    Err(diagnostics) => {
      let first = diagnostics[0]
      println(
        @runner_cli.format_diagnostic_at(
          first.source(),
          first.line(),
          first.message(),
        ),
      )
      return 2
    }
  }
  let summary = @testfloat_expr.execute_document(
    document,
    options=@testfloat_expr.RunOptions::new(
      shard_count=options.shard_count,
      shard_index=options.shard_index,
    ),
  )
  if options.json {
    println(summary_json(summary, options))
  } else {
    println("TestFloat execution summary")
    println("function: " + options.function_name)
    println("rounding: " + options.rounding)
    println("tininess: " + options.tininess)
    println("cases: " + summary.total_cases().to_string())
    println("selected cases: " + summary.selected_cases().to_string())
    println("passed cases: " + summary.passed_cases().to_string())
    println("failed cases: " + summary.failed_cases().to_string())
    for result in summary.results() {
      if !result.passed() {
        println("failed " + result.id() + ": " + result.message())
      }
    }
  }
  if summary.success() {
    0
  } else {
    1
  }
}
