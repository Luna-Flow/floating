///|
/// The same context with an internal rounding algorithm (one of the eight of
/// the kernels), for white-box tests of the three modes IEEE has no name for.
fn DecimalContext::with_round(
  self : DecimalContext,
  round : DecimalRound,
) -> DecimalContext {
  { ..self, decimal_rounding: round, }
}

///|
/// Test-only: the kernel mode for an `@arithmetic` mode (every mode, `AwayFromZero` as `Up`).
fn DecimalRound::from_arithmetic(mode : RoundingMode) -> DecimalRound {
  match mode {
    RoundingMode::ToNearestEven => HalfEven
    RoundingMode::TowardZero => Down
    RoundingMode::TowardPositive => Ceiling
    RoundingMode::TowardNegative => Floor
    RoundingMode::AwayFromZero => Up
  }
}
