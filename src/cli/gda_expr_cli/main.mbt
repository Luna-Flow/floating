///|
priv struct CliOptions {
  paths : Array[String]
  json : Bool
  strict_supported : Bool
  case_filter : String
  shard_count : Int
  shard_index : Int
}

///|
fn parse_cli(args : Array[String]) -> Result[CliOptions, String] {
  let common = match @runner_cli.parse_common_options(args) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let args = common.remaining()
  let paths : Array[String] = []
  let mut strict_supported = false
  let mut case_filter = ""
  let mut index = 0
  while index < args.length() {
    let argument = args[index]
    if argument == "--strict-supported" {
      strict_supported = true
    } else if argument == "--cases" {
      guard index + 1 < args.length() else {
        return Err(argument + " requires a value")
      }
      index += 1
      case_filter = args[index]
    } else if argument.has_prefix("--cases=") {
      case_filter = argument[8:].to_owned()
    } else if argument == "--help" || argument == "-h" {
      return Err(
        "usage: gda-expr [--json] [--strict-supported] [--cases SPEC] [--shard-count N --shard-index I] [path ...]",
      )
    } else if argument.has_prefix("-") {
      return Err("unknown option: " + argument)
    } else {
      paths.push(argument)
    }
    index += 1
  }
  if paths.length() == 0 {
    paths.push("testdata/decimal/smoke.decTest")
  }
  Ok({
    paths,
    json: common.json(),
    strict_supported,
    case_filter,
    shard_count: common.shard_count(),
    shard_index: common.shard_index(),
  })
}

///|
fn load_documents(
  files : Array[String],
) -> Result[Array[@gda_expr.GdaDocument], String] {
  let documents : Array[@gda_expr.GdaDocument] = []
  for path in files {
    let text = match @runner_cli.read_source(path) {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    match @gda_expr.parse_dectest(path, text) {
      Ok(document) => documents.push(document)
      Err(diagnostics) => {
        let first = diagnostics[0]
        return Err(
          @runner_cli.format_diagnostic_at(
            first.span().source(),
            first.span().line(),
            first.message(),
          ),
        )
      }
    }
  }
  Ok(documents)
}

///|
fn summary_json(summary : @gda_expr.RunSummary, options : CliOptions) -> String {
  let failed_ids : Array[String] = []
  for result in summary.results() {
    if result.disposition() is @gda_expr.Executable && !result.passed() {
      failed_ids.push(result.id())
    }
  }
  @runner_cli.json_stringify(
    @runner_cli.json_object([
      ("totalCases", @runner_cli.json_int(summary.total_cases())),
      ("supportedCases", @runner_cli.json_int(summary.executable_cases())),
      ("diagnosticCases", @runner_cli.json_int(summary.diagnostic_cases())),
      ("legacyConditionCases", @runner_cli.json_int(summary.legacy_cases())),
      ("unsupportedCases", @runner_cli.json_int(summary.unsupported_cases())),
      (
        "execution",
        @runner_cli.json_object([
          ("executableCases", @runner_cli.json_int(summary.executable_cases())),
          ("passedCases", @runner_cli.json_int(summary.passed_cases())),
          ("failedCases", @runner_cli.json_int(summary.failed_cases())),
          ("skippedCases", @runner_cli.json_int(summary.skipped_cases())),
          ("failedIds", @runner_cli.json_strings(failed_ids)),
          ("shardCount", @runner_cli.json_int(options.shard_count)),
          ("shardIndex", @runner_cli.json_int(options.shard_index)),
        ]),
      ),
    ]),
  )
}

///|
fn print_text(summary : @gda_expr.RunSummary, options : CliOptions) -> Unit {
  println("GDA expression execution summary")
  println("cases: " + summary.total_cases().to_string())
  println("selected cases: " + summary.selected_cases().to_string())
  println("executable cases: " + summary.executable_cases().to_string())
  println("passed cases: " + summary.passed_cases().to_string())
  println("failed cases: " + summary.failed_cases().to_string())
  println("skipped cases: " + summary.skipped_cases().to_string())
  println(
    "shard: " +
    options.shard_index.to_string() +
    "/" +
    options.shard_count.to_string(),
  )
  for result in summary.results() {
    if result.disposition() is @gda_expr.Executable && !result.passed() {
      println("failed " + result.id() + ": " + result.message())
    }
  }
}

///|
pub fn run(arguments : Array[String]) -> Int {
  let cli = match parse_cli(arguments) {
    Ok(value) => value
    Err(message) => {
      println(message)
      return 2
    }
  }
  let files = match @runner_cli.collect_files(cli.paths, ".decTest") {
    Ok(value) => value
    Err(message) => {
      println(message)
      return 2
    }
  }
  let documents = match load_documents(files) {
    Ok(value) => value
    Err(message) => {
      println(message)
      return 2
    }
  }
  let options = @gda_expr.RunOptions::new(
    shard_count=cli.shard_count,
    shard_index=cli.shard_index,
    strict_supported=cli.strict_supported,
    case_filter=cli.case_filter,
  )
  let summary = @gda_expr.execute_documents(documents, options~)
  if cli.json {
    println(summary_json(summary, cli))
  } else {
    print_text(summary, cli)
  }
  if summary.failed_cases() > 0 ||
    (
      cli.strict_supported &&
      (summary.legacy_cases() > 0 || summary.unsupported_cases() > 0)
    ) {
    1
  } else {
    0
  }
}
