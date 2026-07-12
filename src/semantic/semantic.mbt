///|
pub struct ExactRational {
  priv inner : @internal.ExactRat
} derive(Eq)

///|
pub(all) enum SemanticScalar {
  Rational(ExactRational)
  Infinity(Sign)
  NaN
} derive(Eq)

///|
pub struct SemanticInterval {
  lower : SemanticScalar
  upper : SemanticScalar
} derive(Eq)

///|
pub(all) enum SemanticError {
  DivisionByZero
  ParseError
  DomainError
  FormatError
  UnsupportedOperation
  UnorderedComparison
} derive(Eq)

///|
pub(all) enum SemanticResult[T] {
  Value(T)
  Error(SemanticError)
} derive(Eq)

///|
fn pow_bigint(base : Int, exponent : Int) -> BigInt {
  guard exponent >= 0 else {
    abort("semantic scale exponent must be non-negative")
  }
  BigInt::from_int(base).pow(BigInt::from_int(exponent))
}

///|
pub fn ExactRational::new(
  numerator : BigInt,
  denominator : BigInt,
) -> ExactRational {
  { inner: @internal.ExactRat::new(numerator, denominator) }
}

///|
pub fn ExactRational::numerator(self : ExactRational) -> BigInt {
  self.inner.numerator()
}

///|
pub fn ExactRational::denominator(self : ExactRational) -> BigInt {
  self.inner.denominator()
}

///|
pub fn ExactRational::from_scaled_integer(
  significand : BigInt,
  radix : Int,
  exponent : Int,
) -> ExactRational {
  guard radix > 1 else { abort("semantic radix must be greater than one") }
  if exponent >= 0 {
    ExactRational::new(significand * pow_bigint(radix, exponent), 1N)
  } else {
    ExactRational::new(significand, pow_bigint(radix, -exponent))
  }
}

///|
pub fn SemanticError::from_arithmetic(err : ArithmeticError) -> SemanticError {
  if err.is_division_by_zero() {
    DivisionByZero
  } else if err.is_parse_error() {
    ParseError
  } else if err.is_domain_error() {
    DomainError
  } else if err.is_format_error() {
    FormatError
  } else if err.is_unordered_comparison() {
    UnorderedComparison
  } else {
    UnsupportedOperation
  }
}

///|
pub fn SemanticScalar::from_bin_float(
  x : @bin_float.BinFloat,
) -> SemanticScalar {
  match x.classify() {
    @lf_arith.FpClass::Finite => {
      let magnitude = BigInt::from_octets(x.coefficient().to_bytes_be())
      let signed = if x.is_negative() { -magnitude } else { magnitude }
      Rational(ExactRational::from_scaled_integer(signed, 2, x.exponent2()))
    }
    @lf_arith.FpClass::Infinity => Infinity(x.sign())
    @lf_arith.FpClass::NaN => NaN
  }
}

///|
pub fn SemanticScalar::from_decimal(x : @decimal.Decimal) -> SemanticScalar {
  match x.classify() {
    @lf_arith.FpClass::Finite =>
      Rational(
        ExactRational::from_scaled_integer(x.coefficient(), 10, x.exponent10()),
      )
    @lf_arith.FpClass::Infinity => Infinity(x.sign())
    @lf_arith.FpClass::NaN => NaN
  }
}

///|
pub fn SemanticInterval::from_ball_float(
  x : @ball_float.BallFloat,
) -> SemanticInterval {
  {
    lower: SemanticScalar::from_bin_float(x.lower_bound()),
    upper: SemanticScalar::from_bin_float(x.upper_bound()),
  }
}

///|
pub fn[T] semantic_scalar_result(
  result : Result[T, ArithmeticError],
  interpret : (T) -> SemanticScalar,
) -> SemanticResult[SemanticScalar] {
  match result {
    Ok(value) => Value(interpret(value))
    Err(err) => Error(SemanticError::from_arithmetic(err))
  }
}

///|
pub fn[T] semantic_interval_result(
  result : Result[T, ArithmeticError],
  interpret : (T) -> SemanticInterval,
) -> SemanticResult[SemanticInterval] {
  match result {
    Ok(value) => Value(interpret(value))
    Err(err) => Error(SemanticError::from_arithmetic(err))
  }
}
