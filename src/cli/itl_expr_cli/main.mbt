///|
pub fn run(args : Array[String]) -> Int {
  let mut strict_supported = false
  let operations : Array[String] = []
  let paths : Array[String] = []
  let mut index = 1
  while index < args.length() {
    if args[index] == "--strict-supported" {
      strict_supported = true
    } else if args[index] == "--operation" {
      if index + 1 >= args.length() {
        println("missing value for --operation")
        return 2
      }
      index += 1
      operations.push(args[index])
    } else if args[index].has_prefix("-") {
      println("unknown option: " + args[index])
      return 2
    } else {
      paths.push(args[index])
    }
    index += 1
  }
  if paths.length() == 0 {
    paths.push("testdata/interval/smoke.itl")
  }
  let results : Array[@itl_expr.ItlResult] = []
  for path in paths {
    let source = match @runner_cli.read_source(path, label="ITL file") {
      Ok(value) => value
      Err(message) => {
        println(message)
        return 2
      }
    }
    let cases = match @itl_expr.parse_itl(source) {
      Ok(value) => value
      Err(messages) => {
        for message in messages {
          println(path + ": " + message)
        }
        return 2
      }
    }
    for case in cases {
      if operations.length() > 0 {
        let mut selected = false
        for operation in operations {
          if case.operation() == operation {
            selected = true
            break
          }
        }
        if !selected {
          continue
        }
      }
      results.push(@itl_expr.execute_case(case))
    }
  }
  let summary = @itl_expr.summarize_results(results)
  let failed_ids : Array[String] = []
  let failed_messages : Array[String] = []
  let unsupported_ids : Array[String] = []
  let diagnostic_ids : Array[String] = []
  for result in summary.results() {
    match result.disposition() {
      @itl_expr.Executable =>
        if !result.passed() {
          failed_ids.push(result.id())
          failed_messages.push(result.id() + ": " + result.message())
        }
      @itl_expr.Unsupported(_) => unsupported_ids.push(result.id())
      @itl_expr.Diagnostic(_) => diagnostic_ids.push(result.id())
    }
  }
  println(
    @runner_cli.json_stringify(
      @runner_cli.json_object([
        ("schemaVersion", @runner_cli.json_int(1)),
        ("runner", @runner_cli.json_string("itl-expression-interpreter")),
        ("totalCases", @runner_cli.json_int(summary.total_cases())),
        ("executableCases", @runner_cli.json_int(summary.executable_cases())),
        ("passedCases", @runner_cli.json_int(summary.passed_cases())),
        ("failedCases", @runner_cli.json_int(summary.failed_cases())),
        ("unsupportedCases", @runner_cli.json_int(summary.unsupported_cases())),
        ("diagnosticCases", @runner_cli.json_int(summary.diagnostic_cases())),
        ("failedIds", @runner_cli.json_strings(failed_ids)),
        ("failedMessages", @runner_cli.json_strings(failed_messages)),
        ("unsupportedIds", @runner_cli.json_strings(unsupported_ids)),
        ("diagnosticIds", @runner_cli.json_strings(diagnostic_ids)),
      ]),
    ),
  )
  if !summary.success() || (strict_supported && summary.unsupported_cases() > 0) {
    1
  } else {
    0
  }
}
