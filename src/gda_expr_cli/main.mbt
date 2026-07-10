///|
struct CliOptions {
  paths : Array[String]
  json : Bool
  strict_supported : Bool
  case_filter : String
  shard_count : Int
  shard_index : Int
}

///|
fn parse_cli_int(name : String, value : String) -> Result[Int, String] {
  try @string.parse_int(value) catch {
    _ => Err("invalid " + name + ": " + value)
  } noraise {
    number => Ok(number)
  }
}

///|
fn parse_cli(args : Array[String]) -> Result[CliOptions, String] {
  let paths : Array[String] = []
  let mut json = false
  let mut strict_supported = false
  let mut case_filter = ""
  let mut shard_count = 1
  let mut shard_index = 0
  let mut index = 1
  while index < args.length() {
    let argument = args[index]
    if argument == "--json" {
      json = true
    } else if argument == "--strict-supported" {
      strict_supported = true
    } else if argument == "--cases" ||
      argument == "--shard-count" ||
      argument == "--shard-index" {
      guard index + 1 < args.length() else {
        return Err(argument + " requires a value")
      }
      index += 1
      let value = args[index]
      match argument {
        "--cases" => case_filter = value
        "--shard-count" =>
          match parse_cli_int("shard count", value) {
            Ok(number) => shard_count = number
            Err(message) => return Err(message)
          }
        _ =>
          match parse_cli_int("shard index", value) {
            Ok(number) => shard_index = number
            Err(message) => return Err(message)
          }
      }
    } else if argument.has_prefix("--cases=") {
      case_filter = argument[8:].to_owned()
    } else if argument.has_prefix("--shard-count=") {
      match parse_cli_int("shard count", argument[14:].to_owned()) {
        Ok(number) => shard_count = number
        Err(message) => return Err(message)
      }
    } else if argument.has_prefix("--shard-index=") {
      match parse_cli_int("shard index", argument[14:].to_owned()) {
        Ok(number) => shard_index = number
        Err(message) => return Err(message)
      }
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
  if shard_count <= 0 || shard_index < 0 || shard_index >= shard_count {
    return Err("shard index must be within a positive shard count")
  }
  Ok({ paths, json, strict_supported, case_filter, shard_count, shard_index })
}

///|
fn collect_files(paths : Array[String]) -> Result[Array[String], String] {
  let files : Array[String] = []
  for path in paths {
    if !@fs.path_exists(path) {
      return Err("path does not exist: " + path)
    }
    let is_directory = @fs.is_dir(path) catch {
      _ => return Err("cannot inspect path: " + path)
    }
    if is_directory {
      let entries = @fs.read_dir(path) catch {
        _ => return Err("cannot read directory: " + path)
      }
      for entry in entries {
        if entry.has_suffix(".decTest") {
          files.push(path + "/" + entry)
        }
      }
    } else if path.has_suffix(".decTest") {
      files.push(path)
    }
  }
  files.sort()
  Ok(files)
}

///|
fn load_documents(
  files : Array[String],
) -> Result[Array[@gda_expr.GdaDocument], String] {
  let documents : Array[@gda_expr.GdaDocument] = []
  for path in files {
    let text = @fs.read_file_to_string(path) catch {
      _ => return Err("cannot read file: " + path)
    }
    match @gda_expr.parse_dectest(path, text) {
      Ok(document) => documents.push(document)
      Err(diagnostics) => {
        let first = diagnostics[0]
        return Err(
          first.span().source() +
          ":" +
          first.span().line().to_string() +
          ": " +
          first.message(),
        )
      }
    }
  }
  Ok(documents)
}

///|
fn summary_json(summary : @gda_expr.RunSummary, options : CliOptions) -> String {
  let mut failed_ids = "["
  let mut first_failed = true
  for result in summary.results() {
    if result.disposition() is @gda_expr.Executable && !result.passed() {
      if !first_failed {
        failed_ids = failed_ids + ","
      }
      failed_ids = failed_ids + "\"" + result.id() + "\""
      first_failed = false
    }
  }
  failed_ids = failed_ids + "]"
  "{" +
  "\"totalCases\":" +
  summary.total_cases().to_string() +
  "," +
  "\"supportedCases\":" +
  summary.executable_cases().to_string() +
  "," +
  "\"diagnosticCases\":" +
  summary.diagnostic_cases().to_string() +
  "," +
  "\"legacyConditionCases\":" +
  summary.legacy_cases().to_string() +
  "," +
  "\"unsupportedCases\":" +
  summary.unsupported_cases().to_string() +
  "," +
  "\"execution\":{" +
  "\"executableCases\":" +
  summary.executable_cases().to_string() +
  "," +
  "\"passedCases\":" +
  summary.passed_cases().to_string() +
  "," +
  "\"failedCases\":" +
  summary.failed_cases().to_string() +
  "," +
  "\"skippedCases\":" +
  summary.skipped_cases().to_string() +
  "," +
  "\"failedIds\":" +
  failed_ids +
  "," +
  "\"shardCount\":" +
  options.shard_count.to_string() +
  "," +
  "\"shardIndex\":" +
  options.shard_index.to_string() +
  "}}"
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
fn run() -> Int {
  let cli = match parse_cli(@sys.get_cli_args()) {
    Ok(value) => value
    Err(message) => {
      println(message)
      return 2
    }
  }
  let files = match collect_files(cli.paths) {
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

///|
fn main {
  @sys.exit(run())
}
