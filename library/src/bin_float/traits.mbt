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
  operation : String,
  value : BinFloat,
  flags : BinaryFlags,
) -> Result[@lf_arith.ArithmeticOutcome[BinFloat], @lf_arith.ArithmeticError] {
  if flags.division_by_zero() {
    Err(
      @lf_arith.ArithmeticError::division_by_zero(
        operation + ": division by zero",
      ),
    )
  } else if flags.not_computed() {
    Err(binary_not_computed_error(operation))
  } else if flags.invalid_operation() {
    Err(
      @lf_arith.ArithmeticError::domain_error(operation + ": invalid operation"),
    )
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
  match BinaryContext::from_arithmetic_context(context) {
    Err(error) => Err(error)
    Ok(bctx) => {
      let (value, flags) = self.add_ctx(other, bctx)
      binary_contextual_outcome("add", value, flags)
    }
  }
}

///|
pub impl @lf_arith.SubContextual for BinFloat with fn sub_contextual(
  self,
  other,
  context,
) {
  match BinaryContext::from_arithmetic_context(context) {
    Err(error) => Err(error)
    Ok(bctx) => {
      let (value, flags) = self.sub_ctx(other, bctx)
      binary_contextual_outcome("sub", value, flags)
    }
  }
}

///|
pub impl @lf_arith.MulContextual for BinFloat with fn mul_contextual(
  self,
  other,
  context,
) {
  match BinaryContext::from_arithmetic_context(context) {
    Err(error) => Err(error)
    Ok(bctx) => {
      let (value, flags) = self.mul_ctx(other, bctx)
      binary_contextual_outcome("mul", value, flags)
    }
  }
}

///|
pub impl @lf_arith.DivContextual for BinFloat with fn div_contextual(
  self,
  other,
  context,
) {
  match BinaryContext::from_arithmetic_context(context) {
    Err(error) => Err(error)
    Ok(bctx) => {
      let (value, flags) = self.div_ctx(other, bctx)
      binary_contextual_outcome("div", value, flags)
    }
  }
}

///|
pub impl @lf_arith.AbsContextual for BinFloat with fn abs_contextual(
  self,
  context,
) {
  match BinaryContext::from_arithmetic_context(context) {
    Err(error) => Err(error)
    Ok(bctx) => {
      let (value, flags) = self.abs().apply_ctx(bctx)
      binary_contextual_outcome("abs", value, flags)
    }
  }
}

///|
pub impl @lf_arith.SqrtContextual for BinFloat with fn sqrt_contextual(
  self,
  context,
) {
  match BinaryContext::from_arithmetic_context(context) {
    Err(error) => Err(error)
    Ok(bctx) => {
      let (value, flags) = self.sqrt_ctx(bctx)
      binary_contextual_outcome("sqrt", value, flags)
    }
  }
}

///|
pub impl @lf_arith.ExpContextual for BinFloat with fn exp_contextual(
  self,
  context,
) {
  match BinaryContext::from_arithmetic_context(context) {
    Err(error) => Err(error)
    Ok(bctx) =>
      match self.try_exp_ctx(bctx) {
        Ok((value, flags)) => binary_contextual_outcome("exp", value, flags)
        Err(error) => Err(error)
      }
  }
}

///|
pub extend BinFloat with @Luna-Flow/arithmetic.AddContextual::{add_contextual}

///|
pub extend BinFloat with @Luna-Flow/arithmetic.SubContextual::{sub_contextual}

///|
pub extend BinFloat with @Luna-Flow/arithmetic.MulContextual::{mul_contextual}

///|
pub extend BinFloat with @Luna-Flow/arithmetic.DivContextual::{div_contextual}

///|
pub extend BinFloat with @Luna-Flow/arithmetic.AbsContextual::{abs_contextual}

///|
pub extend BinFloat with @Luna-Flow/arithmetic.SqrtContextual::{sqrt_contextual}

///|
pub extend BinFloat with @Luna-Flow/arithmetic.ExpContextual::{exp_contextual}
