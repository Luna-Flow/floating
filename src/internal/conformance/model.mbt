///|
pub struct SourceLocation {
  priv source : String
  priv line : Int
  priv column : Int
} derive(Eq, @debug.Debug)

///|
pub fn SourceLocation::new(
  source : String,
  line : Int,
  column? : Int = 1,
) -> SourceLocation {
  { source, line: Int::max(1, line), column: Int::max(1, column) }
}

///|
pub fn SourceLocation::source(self : SourceLocation) -> String {
  self.source
}

///|
pub fn SourceLocation::line(self : SourceLocation) -> Int {
  self.line
}

///|
pub fn SourceLocation::column(self : SourceLocation) -> Int {
  self.column
}

///|
pub(all) enum CaseDisposition {
  Executable
  Diagnostic(String)
  Legacy(String)
  Unsupported(String)
} derive(Eq, @debug.Debug)

///|
pub struct CaseResult {
  priv id : String
  priv disposition : CaseDisposition
  priv passed : Bool
  priv message : String
} derive(Eq, @debug.Debug)

///|
pub fn CaseResult::new(
  id : String,
  disposition : CaseDisposition,
  passed : Bool,
  message? : String = "",
) -> CaseResult {
  { id, disposition, passed, message }
}

///|
pub fn CaseResult::executable(
  id : String,
  passed : Bool,
  message? : String = "",
) -> CaseResult {
  CaseResult::new(id, Executable, passed, message~)
}

///|
pub fn CaseResult::id(self : CaseResult) -> String {
  self.id
}

///|
pub fn CaseResult::disposition(self : CaseResult) -> CaseDisposition {
  self.disposition
}

///|
pub fn CaseResult::passed(self : CaseResult) -> Bool {
  self.passed
}

///|
pub fn CaseResult::message(self : CaseResult) -> String {
  self.message
}

///|
pub struct ShardSpec {
  priv count : Int
  priv index : Int
} derive(Eq, @debug.Debug)

///|
pub fn ShardSpec::try_new(
  count : Int,
  index : Int,
) -> Result[ShardSpec, String] {
  guard count > 0 else { return Err("shard count must be positive") }
  guard index >= 0 && index < count else {
    return Err("shard index must be within shard count")
  }
  Ok({ count, index })
}

///|
pub fn ShardSpec::new(count : Int, index : Int) -> ShardSpec {
  match ShardSpec::try_new(count, index) {
    Ok(shard) => shard
    Err(message) => abort(message)
  }
}

///|
pub fn ShardSpec::count(self : ShardSpec) -> Int {
  self.count
}

///|
pub fn ShardSpec::index(self : ShardSpec) -> Int {
  self.index
}

///|
pub fn ShardSpec::selects(self : ShardSpec, ordinal : Int) -> Bool {
  ordinal % self.count == self.index
}

///|
pub struct RunSummary {
  priv total_cases : Int
  priv selected_cases : Int
  priv executable_cases : Int
  priv passed_cases : Int
  priv failed_cases : Int
  priv skipped_cases : Int
  priv diagnostic_cases : Int
  priv legacy_cases : Int
  priv unsupported_cases : Int
  priv results : Array[CaseResult]
} derive(Eq, @debug.Debug)

///|
pub fn RunSummary::from_results(
  total_cases : Int,
  results : Array[CaseResult],
) -> RunSummary {
  let mut executable_cases = 0
  let mut passed_cases = 0
  let mut failed_cases = 0
  let mut skipped_cases = 0
  let mut diagnostic_cases = 0
  let mut legacy_cases = 0
  let mut unsupported_cases = 0
  for result in results {
    match result.disposition() {
      Executable => {
        executable_cases += 1
        if result.passed() {
          passed_cases += 1
        } else {
          failed_cases += 1
        }
      }
      Diagnostic(_) => {
        skipped_cases += 1
        diagnostic_cases += 1
      }
      Legacy(_) => {
        skipped_cases += 1
        legacy_cases += 1
      }
      Unsupported(_) => {
        skipped_cases += 1
        unsupported_cases += 1
      }
    }
  }
  {
    total_cases,
    selected_cases: results.length(),
    executable_cases,
    passed_cases,
    failed_cases,
    skipped_cases,
    diagnostic_cases,
    legacy_cases,
    unsupported_cases,
    results: results.copy(),
  }
}

///|
pub fn RunSummary::merge(parts : Array[RunSummary]) -> RunSummary {
  let mut total_cases = 0
  let mut selected_cases = 0
  let mut executable_cases = 0
  let mut passed_cases = 0
  let mut failed_cases = 0
  let mut skipped_cases = 0
  let mut diagnostic_cases = 0
  let mut legacy_cases = 0
  let mut unsupported_cases = 0
  let results : Array[CaseResult] = []
  for part in parts {
    total_cases = Int::max(total_cases, part.total_cases)
    selected_cases += part.selected_cases
    executable_cases += part.executable_cases
    passed_cases += part.passed_cases
    failed_cases += part.failed_cases
    skipped_cases += part.skipped_cases
    diagnostic_cases += part.diagnostic_cases
    legacy_cases += part.legacy_cases
    unsupported_cases += part.unsupported_cases
    results.push_iter(part.results.iter())
  }
  {
    total_cases,
    selected_cases,
    executable_cases,
    passed_cases,
    failed_cases,
    skipped_cases,
    diagnostic_cases,
    legacy_cases,
    unsupported_cases,
    results,
  }
}

///|
pub fn RunSummary::total_cases(self : RunSummary) -> Int {
  self.total_cases
}

///|
pub fn RunSummary::selected_cases(self : RunSummary) -> Int {
  self.selected_cases
}

///|
pub fn RunSummary::executable_cases(self : RunSummary) -> Int {
  self.executable_cases
}

///|
pub fn RunSummary::passed_cases(self : RunSummary) -> Int {
  self.passed_cases
}

///|
pub fn RunSummary::failed_cases(self : RunSummary) -> Int {
  self.failed_cases
}

///|
pub fn RunSummary::skipped_cases(self : RunSummary) -> Int {
  self.skipped_cases
}

///|
pub fn RunSummary::diagnostic_cases(self : RunSummary) -> Int {
  self.diagnostic_cases
}

///|
pub fn RunSummary::legacy_cases(self : RunSummary) -> Int {
  self.legacy_cases
}

///|
pub fn RunSummary::unsupported_cases(self : RunSummary) -> Int {
  self.unsupported_cases
}

///|
pub fn RunSummary::results(self : RunSummary) -> Array[CaseResult] {
  self.results.copy()
}

///|
pub fn RunSummary::success(self : RunSummary) -> Bool {
  self.failed_cases == 0
}
