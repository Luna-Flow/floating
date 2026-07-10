# `semantic` API

The package projects concrete numeric representations into a small,
representation-independent semantic model.

## Exact And Scalar Values

- `ExactRational::new(numerator, denominator)` constructs a normalized rational.
- `ExactRational::from_scaled_integer(coefficient, exponent, radix)` constructs
  an exact scaled integer value.
- `SemanticScalar` is `Rational(ExactRational)`, `Infinity(Sign)`, or `NaN`.
- `SemanticScalar::from_bin_float` and `from_decimal` project concrete scalars.

## Intervals And Errors

- `SemanticInterval` stores public `lower` and `upper` semantic scalars;
  `from_ball_float` projects a `BallFloat`.
- `SemanticError` distinguishes division, parsing, domain, formatting,
  unsupported-operation, and unordered-comparison failures.
- `SemanticError::from_arithmetic` maps `ArithmeticError` into this vocabulary.
- `SemanticResult[T]` is either `Value(T)` or `Error(SemanticError)`.
- `semantic_scalar_result` and `semantic_interval_result` map checked concrete
  results through caller-supplied projection functions.
