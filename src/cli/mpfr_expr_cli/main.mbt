///|
pub fn run(arguments : Array[String]) -> Int {
  let common = match
    @runner_cli.parse_common_options(arguments, allow_shard=false) {
    Ok(value) => value
    Err(message) => {
      println(message)
      return 2
    }
  }
  let arguments = common.remaining()
  guard arguments.length() == 1 else {
    println("usage: mpfr-expr [--json] <MPFR sqrt, pow, or elementary corpus>")
    return 2
  }
  let path = arguments[0]
  let text = match @runner_cli.read_source(path) {
    Ok(value) => value
    Err(message) => {
      println(message)
      return 2
    }
  }
  let is_elementary = text.contains("mpfr-elementary-v1")
  let is_pow = !is_elementary && text.contains("input_coefficient_hex")
  let summary = if is_elementary {
    match @mpfr_expr.parse_elementary_data(path, text) {
      Ok(document) => @mpfr_expr.execute_elementary_data(document)
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
  } else if is_pow {
    match @mpfr_expr.parse_pow_data(path, text) {
      Ok(document) => @mpfr_expr.execute_pow_data(document)
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
  } else {
    match @mpfr_expr.parse_sqrt_data(path, text) {
      Ok(document) => @mpfr_expr.execute_sqrt_data(document)
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
  }
  if common.json() {
    let failed_ids : Array[String] = []
    for result in summary.results() {
      if !result.passed() {
        failed_ids.push(result.id())
      }
    }
    println(
      @runner_cli.json_stringify(
        @runner_cli.json_object([
          (
            "corpus",
            @runner_cli.json_string(
              if is_elementary {
                "mpfr-4.2.2-elementary"
              } else if is_pow {
                "mpfr-4.2.2-pow-si"
              } else {
                "mpfr-4.2.2-sqrt"
              },
            ),
          ),
          ("totalCases", @runner_cli.json_int(summary.total_cases())),
          ("passedCases", @runner_cli.json_int(summary.passed_cases())),
          ("failedCases", @runner_cli.json_int(summary.failed_cases())),
          ("failedIds", @runner_cli.json_strings(failed_ids)),
        ]),
      ),
    )
  } else {
    println(
      if is_pow {
        "MPFR pow_si summary"
      } else if is_elementary {
        "MPFR elementary summary"
      } else {
        "MPFR sqrt data_check summary"
      },
    )
    println("cases: " + summary.total_cases().to_string())
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
