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
  priv inner : @conformance.CaseResult
}

///|
pub fn CaseResult::id(self : CaseResult) -> String {
  self.inner.id()
}

///|
pub fn CaseResult::disposition(self : CaseResult) -> CaseDisposition {
  match self.inner.disposition() {
    @conformance.CaseDisposition::Executable => Executable
    @conformance.CaseDisposition::Diagnostic(message) => Diagnostic(message)
    @conformance.CaseDisposition::Legacy(message) => Legacy(message)
    @conformance.CaseDisposition::Unsupported(message) => Unsupported(message)
  }
}

///|
pub fn CaseResult::passed(self : CaseResult) -> Bool {
  self.inner.passed()
}

///|
pub fn CaseResult::message(self : CaseResult) -> String {
  self.inner.message()
}

///|
fn conformance_disposition(
  disposition : CaseDisposition,
) -> @conformance.CaseDisposition {
  match disposition {
    Executable => @conformance.CaseDisposition::Executable
    Diagnostic(message) => @conformance.CaseDisposition::Diagnostic(message)
    Legacy(message) => @conformance.CaseDisposition::Legacy(message)
    Unsupported(message) => @conformance.CaseDisposition::Unsupported(message)
  }
}

///|
fn case_result(
  id : String,
  disposition : CaseDisposition,
  passed : Bool,
  message? : String = "",
) -> CaseResult {
  {
    inner: @conformance.CaseResult::new(
      id,
      conformance_disposition(disposition),
      passed,
      message~,
    ),
  }
}

///|
pub struct RunOptions {
  priv shard : @conformance.ShardSpec
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
  {
    shard: @conformance.ShardSpec::new(shard_count, shard_index),
    strict_supported,
    case_filter,
  }
}

///|
pub fn RunOptions::shard_count(self : RunOptions) -> Int {
  self.shard.count()
}

///|
pub fn RunOptions::shard_index(self : RunOptions) -> Int {
  self.shard.index()
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
  priv inner : @conformance.RunSummary
}

///|
pub fn RunSummary::total_cases(self : RunSummary) -> Int {
  self.inner.total_cases()
}

///|
pub fn RunSummary::selected_cases(self : RunSummary) -> Int {
  self.inner.selected_cases()
}

///|
pub fn RunSummary::executable_cases(self : RunSummary) -> Int {
  self.inner.executable_cases()
}

///|
pub fn RunSummary::passed_cases(self : RunSummary) -> Int {
  self.inner.passed_cases()
}

///|
pub fn RunSummary::failed_cases(self : RunSummary) -> Int {
  self.inner.failed_cases()
}

///|
pub fn RunSummary::skipped_cases(self : RunSummary) -> Int {
  self.inner.skipped_cases()
}

///|
pub fn RunSummary::diagnostic_cases(self : RunSummary) -> Int {
  self.inner.diagnostic_cases()
}

///|
pub fn RunSummary::legacy_cases(self : RunSummary) -> Int {
  self.inner.legacy_cases()
}

///|
pub fn RunSummary::unsupported_cases(self : RunSummary) -> Int {
  self.inner.unsupported_cases()
}

///|
pub fn RunSummary::results(self : RunSummary) -> Array[CaseResult] {
  self.inner.results().map(fn(inner) { { inner, } })
}

///|
pub fn RunSummary::success(self : RunSummary) -> Bool {
  self.inner.success()
}

///|
pub fn RunSummary::merge(parts : Array[RunSummary]) -> RunSummary {
  { inner: @conformance.RunSummary::merge(parts.map(fn(part) { part.inner })) }
}
