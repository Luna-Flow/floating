///|
priv struct CliOptions {
  paths : Array[String]
  json : Bool
  strict_supported : Bool
  case_filter : String
  deviations : String
  shard_count : Int32
  shard_index : Int32
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
  let mut deviations = ""
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
    } else if argument == "--deviations" {
      guard index + 1 < args.length() else {
        return Err(argument + " requires a value")
      }
      index += 1
      deviations = args[index]
    } else if argument.has_prefix("--cases=") {
      case_filter = argument[8:].to_owned()
    } else if argument == "--help" || argument == "-h" {
      return Err(
        "usage: gda-expr [--json] [--strict-supported] [--cases SPEC] [--deviations FILE] [--shard-count N --shard-index I] [path ...]",
      )
    } else if argument.has_prefix("-") {
      return Err("unknown option: " + argument)
    } else {
      paths.push(argument)
    }
    index += 1
  }
  if paths.length() == 0 {
    paths.push("testdata/decimal_gda/smoke.decTest")
  }
  Ok({
    paths,
    json: common.json(),
    strict_supported,
    case_filter,
    deviations,
    shard_count: common.shard_count(),
    shard_index: common.shard_index(),
  })
}

///|
/// The recorded deviations of the corpus (`testdata/decimal_gda/deviations.tsv`):
/// tab-separated `corpus, file, id, corpus value, held value, decNumber value, rests
/// on, held flags`; the last is optional (condition names separated by spaces; the flags of the row are then judged against them); lines starting with `#` and blank lines are comments. Each row becomes
/// `("file:id", corpus value, held value, held flags)`.
fn load_deviations(
  path : String,
) -> Result[Array[(String, String, String, String?)], String] {
  let text = match @runner_cli.read_source(path) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let rows : Array[(String, String, String, String?)] = []
  for line_view in text.split("\n") {
    let line = line_view.to_owned()
    if line.length() == 0 || line.has_prefix("#") {
      continue
    }
    let fields = line.split("\t").map(fn(field) { field.to_owned() }).to_array()
    if fields.length() < 5 {
      return Err(
        "deviations: a row needs at least 5 tab-separated fields: " + line,
      )
    }
    let held_flags = if fields.length() >= 8 { Some(fields[7]) } else { None }
    rows.push((fields[1] + ":" + fields[2], fields[3], fields[4], held_flags))
  }
  Ok(rows)
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
/// The kinds of verdict of the passing executable rows and their counts, in a fixed
/// order: `text` (the to-scientific-string of the result against the result token),
/// `hex` (an interchange pattern against the hexadecimal text of the encoding),
/// `format-prefixed` (a result token that is a number in a named format, read by the
/// library: the only kind that passes through its reader), `value-not-checked`
/// (the corpus gives `?`: flags only), `deviation` (a recorded deviation of the
/// corpus: judged against the held value).
fn verdict_kinds(summary : @gda_expr.RunSummary) -> Array[(String, Int32)] {
  let names = [
    "text", "hex", "format-prefixed", "value-not-checked", "deviation",
  ]
  let counts : Array[Int32] = [0, 0, 0, 0, 0]
  for result in summary.results() {
    if result.disposition() is @gda_expr.Executable && result.passed() {
      for index in 0..<names.length() {
        if result.message() == names[index] {
          counts[index] = counts[index] + 1
        }
      }
    }
  }
  [
    for index in 0..<names.length() => (names[index], counts[index])
  ]
}

///|
fn verdict_kinds_json(summary : @gda_expr.RunSummary) -> Json {
  let fields : Array[(String, Json)] = []
  for kind in verdict_kinds(summary) {
    fields.push((kind.0, @runner_cli.json_int(kind.1)))
  }
  @runner_cli.json_object(fields)
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
          ("verdictKinds", verdict_kinds_json(summary)),
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
  for kind in verdict_kinds(summary) {
    println("verdict " + kind.0 + ": " + kind.1.to_string())
  }
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
pub fn run(arguments : Array[String]) -> Int32 {
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
  let deviations = if cli.deviations.length() > 0 {
    match load_deviations(cli.deviations) {
      Ok(value) => value
      Err(message) => {
        println(message)
        return 2
      }
    }
  } else {
    []
  }
  let options = @gda_expr.RunOptions::new(
    deviations~,
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
