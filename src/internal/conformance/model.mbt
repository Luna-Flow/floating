///|
pub struct SourceLocation {
  priv source : String
  priv line : Int32
  priv column : Int32
} derive(Eq, @debug.Debug)

///|
pub fn SourceLocation::new(
  source : String,
  line : Int32,
  column~ : Int32 = 1,
) -> SourceLocation {
  { source, line: Int32::max(1, line), column: Int32::max(1, column), }
}

///|
pub fn SourceLocation::source(self : SourceLocation) -> String {
  self.source
}

///|
pub fn SourceLocation::line(self : SourceLocation) -> Int32 {
  self.line
}

///|
pub fn SourceLocation::column(self : SourceLocation) -> Int32 {
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
  message~ : String = "",
) -> CaseResult {
  { id, disposition, passed, message, }
}

///|
pub fn CaseResult::executable(
  id : String,
  passed : Bool,
  message~ : String = "",
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
  priv count : Int32
  priv index : Int32
} derive(Eq, @debug.Debug)

///|
pub fn ShardSpec::try_new(
  count : Int32,
  index : Int32,
) -> Result[ShardSpec, String] {
  guard count > 0 else { return Err("shard count must be positive") }
  guard index >= 0 && index < count else {
    return Err("shard index must be within shard count")
  }
  Ok({ count, index, })
}

///|
pub fn ShardSpec::new(count : Int32, index : Int32) -> ShardSpec {
  match ShardSpec::try_new(count, index) {
    Ok(shard) => shard
    Err(message) => abort(message)
  }
}

///|
pub fn ShardSpec::count(self : ShardSpec) -> Int32 {
  self.count
}

///|
pub fn ShardSpec::index(self : ShardSpec) -> Int32 {
  self.index
}

///|
pub fn ShardSpec::selects(self : ShardSpec, ordinal : Int32) -> Bool {
  ordinal % self.count == self.index
}

///|
pub struct RunSummary {
  priv total_cases : Int32
  priv selected_cases : Int32
  priv executable_cases : Int32
  priv passed_cases : Int32
  priv failed_cases : Int32
  priv skipped_cases : Int32
  priv diagnostic_cases : Int32
  priv legacy_cases : Int32
  priv unsupported_cases : Int32
  priv results : Array[CaseResult]
} derive(Eq, @debug.Debug)

///|
pub fn RunSummary::from_results(
  total_cases : Int32,
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
    total_cases = Int32::max(total_cases, part.total_cases)
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
pub fn RunSummary::total_cases(self : RunSummary) -> Int32 {
  self.total_cases
}

///|
pub fn RunSummary::selected_cases(self : RunSummary) -> Int32 {
  self.selected_cases
}

///|
pub fn RunSummary::executable_cases(self : RunSummary) -> Int32 {
  self.executable_cases
}

///|
pub fn RunSummary::passed_cases(self : RunSummary) -> Int32 {
  self.passed_cases
}

///|
pub fn RunSummary::failed_cases(self : RunSummary) -> Int32 {
  self.failed_cases
}

///|
pub fn RunSummary::skipped_cases(self : RunSummary) -> Int32 {
  self.skipped_cases
}

///|
pub fn RunSummary::diagnostic_cases(self : RunSummary) -> Int32 {
  self.diagnostic_cases
}

///|
pub fn RunSummary::legacy_cases(self : RunSummary) -> Int32 {
  self.legacy_cases
}

///|
pub fn RunSummary::unsupported_cases(self : RunSummary) -> Int32 {
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

///|
pub extend SourceLocation with Eq::{not_equal, equal}

///|
pub extend SourceLocation with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CaseDisposition with Eq::{not_equal, equal}

///|
pub extend CaseDisposition with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CaseResult with Eq::{not_equal, equal}

///|
pub extend CaseResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ShardSpec with Eq::{not_equal, equal}

///|
pub extend ShardSpec with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend RunSummary with Eq::{not_equal, equal}

///|
pub extend RunSummary with @moonbitlang/core/debug.Debug::{to_repr}
