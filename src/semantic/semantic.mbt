///|
pub struct ExactRational {
  numerator : BigInt
  denominator : BigInt
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
fn bigint_zero() -> BigInt {
  BigInt::from_int(0)
}

///|
fn bigint_one() -> BigInt {
  BigInt::from_int(1)
}

///|
fn bigint_abs(x : BigInt) -> BigInt {
  if x < bigint_zero() {
    -x
  } else {
    x
  }
}

///|
fn gcd(a : BigInt, b : BigInt) -> BigInt {
  let mut x = bigint_abs(a)
  let mut y = bigint_abs(b)
  while !y.is_zero() {
    let r = x % y
    x = y
    y = r
  }
  if x.is_zero() {
    bigint_one()
  } else {
    x
  }
}

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
  guard !denominator.is_zero() else {
    abort("exact rational denominator must be non-zero")
  }
  let (num0, den0) = if denominator < bigint_zero() {
    (-numerator, -denominator)
  } else {
    (numerator, denominator)
  }
  if num0.is_zero() {
    return { numerator: bigint_zero(), denominator: bigint_one() }
  }
  let factor = gcd(num0, den0)
  { numerator: num0 / factor, denominator: den0 / factor }
}

///|
pub fn ExactRational::from_scaled_integer(
  significand : BigInt,
  radix : Int,
  exponent : Int,
) -> ExactRational {
  guard radix > 1 else { abort("semantic radix must be greater than one") }
  if exponent >= 0 {
    ExactRational::new(significand * pow_bigint(radix, exponent), bigint_one())
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
    @arithmetic.FpClass::Finite =>
      Rational(
        ExactRational::from_scaled_integer(x.significand(), 2, x.exponent2()),
      )
    @arithmetic.FpClass::Infinity => Infinity(x.sign())
    @arithmetic.FpClass::NaN => NaN
  }
}

///|
pub fn SemanticScalar::from_decimal(x : @decimal.Decimal) -> SemanticScalar {
  match x.classify() {
    @arithmetic.FpClass::Finite =>
      Rational(
        ExactRational::from_scaled_integer(x.coefficient(), 10, x.exponent10()),
      )
    @arithmetic.FpClass::Infinity => Infinity(x.sign())
    @arithmetic.FpClass::NaN => NaN
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
