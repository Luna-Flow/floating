///|
fn binary_contextual_diagnostics(
  flags : BinaryFlags,
) -> @lf_arith.ArithmeticDiagnostics {
  @lf_arith.ArithmeticDiagnostics::new(
    inexact=flags.inexact(),
    rounded=flags.inexact(),
    overflow=flags.overflow(),
    underflow=flags.underflow(),
  )
}

///|
fn binary_contextual_outcome(
  value : BinFloat,
  flags : BinaryFlags,
) -> Result[@lf_arith.ArithmeticOutcome[BinFloat], @lf_arith.ArithmeticError] {
  if flags.division_by_zero() {
    Err(@lf_arith.ArithmeticError::division_by_zero("division by zero"))
  } else if flags.invalid_operation() {
    Err(@lf_arith.ArithmeticError::domain_error("invalid binary operation"))
  } else {
    Ok(
      @lf_arith.ArithmeticOutcome::with_diagnostics(
        value,
        binary_contextual_diagnostics(flags),
      ),
    )
  }
}

///|
pub impl @lf_arith.AddContextual for BinFloat with fn add_contextual(
  self,
  other,
  context,
) {
  let (value, flags) = self.add_ctx(
    other,
    BinaryContext::from_arithmetic_context(context),
  )
  binary_contextual_outcome(value, flags)
}

///|
pub impl @lf_arith.SubContextual for BinFloat with fn sub_contextual(
  self,
  other,
  context,
) {
  let (value, flags) = self.sub_ctx(
    other,
    BinaryContext::from_arithmetic_context(context),
  )
  binary_contextual_outcome(value, flags)
}

///|
pub impl @lf_arith.MulContextual for BinFloat with fn mul_contextual(
  self,
  other,
  context,
) {
  let (value, flags) = self.mul_ctx(
    other,
    BinaryContext::from_arithmetic_context(context),
  )
  binary_contextual_outcome(value, flags)
}

///|
pub impl @lf_arith.DivContextual for BinFloat with fn div_contextual(
  self,
  other,
  context,
) {
  let (value, flags) = self.div_ctx(
    other,
    BinaryContext::from_arithmetic_context(context),
  )
  binary_contextual_outcome(value, flags)
}

///|
pub impl @lf_arith.AbsContextual for BinFloat with fn abs_contextual(
  self,
  context,
) {
  let (value, flags) = self
    .abs()
    .round_ctx(BinaryContext::from_arithmetic_context(context))
  binary_contextual_outcome(value, flags)
}

///|
pub impl @lf_arith.SqrtContextual for BinFloat with fn sqrt_contextual(
  self,
  context,
) {
  let (value, flags) = self.sqrt_ctx(
    BinaryContext::from_arithmetic_context(context),
  )
  binary_contextual_outcome(value, flags)
}

///|
pub impl @lf_arith.ExpContextual for BinFloat with fn exp_contextual(
  self,
  context,
) {
  match self.try_exp_ctx(BinaryContext::from_arithmetic_context(context)) {
    Ok((value, flags)) => binary_contextual_outcome(value, flags)
    Err(error) => Err(error)
  }
}
