///|
pub struct GdaContext {
  priv precision : Int
  priv rounding : String
  priv min_exponent : Int
  priv max_exponent : Int
  priv clamp : Bool
  priv extended : Bool
  priv dectest : String
} derive(Eq, Debug)

///|
pub fn GdaContext::default() -> GdaContext {
  {
    precision: 34,
    rounding: "half_even",
    min_exponent: -999999999,
    max_exponent: 999999999,
    clamp: false,
    extended: true,
    dectest: "",
  }
}

///|
pub fn GdaContext::precision(self : GdaContext) -> Int {
  self.precision
}

///|
pub fn GdaContext::rounding(self : GdaContext) -> String {
  self.rounding
}

///|
pub fn GdaContext::min_exponent(self : GdaContext) -> Int {
  self.min_exponent
}

///|
pub fn GdaContext::max_exponent(self : GdaContext) -> Int {
  self.max_exponent
}

///|
pub fn GdaContext::clamp(self : GdaContext) -> Bool {
  self.clamp
}

///|
pub fn GdaContext::extended(self : GdaContext) -> Bool {
  self.extended
}

///|
pub fn GdaContext::dectest(self : GdaContext) -> String {
  self.dectest
}

///|
pub struct GdaCase {
  priv id : String
  priv operation : String
  priv normalized_operation : String
  priv operands : Array[String]
  priv expected : String
  priv conditions : Array[String]
  priv context : GdaContext
  priv expression : @numeric_expr.Expr
  priv span : @numeric_expr.SourceSpan
}

///|
pub fn GdaCase::id(self : GdaCase) -> String {
  self.id
}

///|
pub fn GdaCase::operation(self : GdaCase) -> String {
  self.operation
}

///|
pub fn GdaCase::normalized_operation(self : GdaCase) -> String {
  self.normalized_operation
}

///|
pub fn GdaCase::operands(self : GdaCase) -> Array[String] {
  self.operands.copy()
}

///|
pub fn GdaCase::expected(self : GdaCase) -> String {
  self.expected
}

///|
pub fn GdaCase::conditions(self : GdaCase) -> Array[String] {
  self.conditions.copy()
}

///|
pub fn GdaCase::context(self : GdaCase) -> GdaContext {
  self.context
}

///|
pub fn GdaCase::expression(self : GdaCase) -> @numeric_expr.Expr {
  self.expression
}

///|
pub fn GdaCase::span(self : GdaCase) -> @numeric_expr.SourceSpan {
  self.span
}

///|
pub struct GdaDocument {
  priv source : String
  priv cases : Array[GdaCase]
}

///|
pub fn GdaDocument::source(self : GdaDocument) -> String {
  self.source
}

///|
pub fn GdaDocument::cases(self : GdaDocument) -> Array[GdaCase] {
  self.cases.copy()
}

///|
pub fn GdaDocument::case_count(self : GdaDocument) -> Int {
  self.cases.length()
}

///|
pub struct ParseDiagnostic {
  priv span : @numeric_expr.SourceSpan
  priv message : String
} derive(Eq, Debug)

///|
pub fn ParseDiagnostic::span(
  self : ParseDiagnostic,
) -> @numeric_expr.SourceSpan {
  self.span
}

///|
pub fn ParseDiagnostic::message(self : ParseDiagnostic) -> String {
  self.message
}

///|
pub(all) enum CaseDisposition {
  Executable
  Diagnostic(String)
  Legacy(String)
  Unsupported(String)
}

///|
pub struct CaseResult {
  priv id : String
  priv disposition : CaseDisposition
  priv passed : Bool
  priv message : String
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
pub struct RunOptions {
  priv shard_count : Int
  priv shard_index : Int
  priv strict_supported : Bool
  priv case_filter : String
} derive(Eq, Debug)

///|
pub fn RunOptions::new(
  shard_count? : Int = 1,
  shard_index? : Int = 0,
  strict_supported? : Bool = false,
  case_filter? : String = "",
) -> RunOptions {
  guard shard_count > 0 else { abort("shard_count must be positive") }
  guard shard_index >= 0 && shard_index < shard_count else {
    abort("shard_index must be within shard_count")
  }
  { shard_count, shard_index, strict_supported, case_filter }
}

///|
pub fn RunOptions::shard_count(self : RunOptions) -> Int {
  self.shard_count
}

///|
pub fn RunOptions::shard_index(self : RunOptions) -> Int {
  self.shard_index
}

///|
pub fn RunOptions::strict_supported(self : RunOptions) -> Bool {
  self.strict_supported
}

///|
pub fn RunOptions::case_filter(self : RunOptions) -> String {
  self.case_filter
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
